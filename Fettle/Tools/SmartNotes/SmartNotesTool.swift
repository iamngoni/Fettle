import SwiftUI
import AppKit
import AVFoundation

@MainActor
@Observable
final class SmartNotesTool: FettleTool {
    enum State: Equatable { case idle, recording, processing, done }

    let kind: ToolID = .smartNotes
    let title = "Smart Notes"
    let symbol = "sparkles"
    let tint = Color(hex: 0xBF5AF2)
    let section: ToolSection = .sessions

    private(set) var state: State = .idle
    private(set) var elapsed: TimeInterval = 0
    private(set) var transcript: [TranscriptLine] = []
    private(set) var summary: MeetingSummary?
    private(set) var errorMessage: String?
    private(set) var processingMessage = "Transcribing & summarizing…"
    private(set) var meetingTitle = "Meeting"

    var intelligenceEngine = Store.rawValue("notes.engine", default: MeetingSummarizer.Engine.appleIntelligence) {
        didSet {
            Store.set(intelligenceEngine, "notes.engine")
            if oldValue != intelligenceEngine { mlxStatus = .notLoaded }
        }
    }
    var transcriptionEngine = Store.rawValue("notes.tx", default: TranscriptionEngine.whisper) {
        didSet { Store.set(transcriptionEngine, "notes.tx") }
    }
    var keepRecordings = Store.bool("notes.keep", default: false) {
        didSet { Store.set(keepRecordings, "notes.keep") }
    }

    private(set) var sessions: [MeetingSession] = []
    var whisperStatus: WhisperTranscriber.Status = .notLoaded
    var mlxStatus: MLXSummarizer.Status = .notLoaded
    @ObservationIgnored private var currentSessionID: UUID?

    var recordingsFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Fettle/Recordings", isDirectory: true)
    }

    @ObservationIgnored private var recorder: MeetingRecorder?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var startedAt: Date?

    var isActive: Bool { state == .recording }
    var statusText: String {
        switch state {
        case .idle: return "Record & summarize a meeting"
        case .recording: return "Recording · \(elapsedString)"
        case .processing: return "Transcribing & summarizing…"
        case .done: return summary == nil ? "Ready" : "Notes ready"
        }
    }
    var statusTint: Color { state == .recording ? Color(hex: 0xFF6B61) : Theme.textMuted }
    var control: ToolControl { .toggleAndNavigate }
    func setActive(_ active: Bool) { active ? start() : stop() }
    var hasDetail: Bool { true }

    var elapsedString: String {
        let s = Int(elapsed)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    init() { loadSessions() }

    func toggle() { state == .recording ? stop() : start() }

    /// Starts loading the Whisper model in the background. Safe to call repeatedly.
    func ensureWhisper() {
        Task { _ = await loadWhisperForUse() }
    }

    @discardableResult
    private func loadWhisperForUse() async -> Bool {
        guard transcriptionEngine == .whisper else { return true }
        if case .ready = whisperStatus { return true }
        whisperStatus = .downloading(0)
        let ok = await WhisperTranscriber.shared.load { [weak self] p in
            Task { @MainActor in
                guard let self else { return }
                if case .ready = self.whisperStatus { return }
                self.whisperStatus = .downloading(p)
            }
        }
        whisperStatus = ok ? .ready : .failed("Whisper unavailable; using Apple Speech fallback")
        return ok
    }

    func downloadWhisper() { ensureWhisper() }

    /// Starts loading the selected Gemma model in the background.
    func ensureMLX() {
        Task { _ = await loadMLXForUse() }
    }

    @discardableResult
    private func loadMLXForUse() async -> Bool {
        guard let variant = intelligenceEngine.mlxVariant else { return true }
        if case .ready = mlxStatus { return true }
        mlxStatus = .downloading(0)
        let ok = await MLXSummarizer.shared.load(variant) { [weak self] p in
            Task { @MainActor in
                guard let self else { return }
                if case .ready = self.mlxStatus { return }
                self.mlxStatus = .downloading(p)
            }
        }
        mlxStatus = ok ? .ready : .failed("Gemma unavailable; using Apple Intelligence/on-device fallback")
        return ok
    }

    func downloadMLX() { ensureMLX() }

    func start() {
        guard state != .recording else { return }
        errorMessage = nil
        transcript = []
        summary = nil
        ensureWhisper()   // start the model downloads now so they're ready by "Stop"
        ensureMLX()
        Task {
            if Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") != nil {
                _ = await MeetingTranscriber.authorize()
            } else {
                FettleLog.error("Smart Notes: missing NSSpeechRecognitionUsageDescription; skipping speech authorization request")
            }
            let micOK = await AVCaptureDevice.requestAccess(for: .audio)
            guard micOK else {
                errorMessage = "Microphone access is needed. Enable Fettle under Privacy → Microphone."
                state = .idle
                return
            }
            let rec = MeetingRecorder()
            do {
                try rec.start()
                recorder = rec
                startedAt = Date()
                elapsed = 0
                state = .recording
                startTimer()
            } catch {
                _ = await rec.stop()
                errorMessage = error.localizedDescription + " Enable Fettle under Privacy → System Audio Recording and Microphone."
                state = .idle
            }
        }
    }

    func stop() {
        guard state == .recording, let recorder else { return }
        stopTimer()
        state = .processing
        Task {
            let output = await recorder.stop()
            self.recorder = nil
            if transcriptionEngine == .whisper {
                processingMessage = "Loading Whisper…"
                let ok = await loadWhisperForUse()
                if !ok {
                    errorMessage = "Whisper was unavailable, so this recording used Apple Speech fallback."
                }
            }
            processingMessage = "Transcribing audio…"
            let lines = await MeetingTranscriber.transcribe(systemURL: output.systemURL, micURL: output.micURL, engine: transcriptionEngine)
            transcript = lines
            let joined = lines.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
            if intelligenceEngine.mlxVariant != nil {
                processingMessage = "Loading \(intelligenceEngine.rawValue)…"
                let ok = await loadMLXForUse()
                if !ok {
                    errorMessage = "Gemma was unavailable, so this recording used Apple Intelligence/on-device fallback."
                }
            }
            processingMessage = "Summarizing notes…"
            summary = await MeetingSummarizer.summarize(transcript: joined, engine: intelligenceEngine)
            state = .done
            processingMessage = "Transcribing & summarizing…"
            saveSession(duration: output.duration)
            handleRecordings(output.systemURL, output.micURL)
        }
    }

    // MARK: Sessions

    func loadSessions() { sessions = SessionStore.all() }

    private func saveSession(duration: TimeInterval) {
        guard let summary, !transcript.isEmpty else { return }
        let session = MeetingSession(date: Date(), title: meetingTitle, duration: duration,
                                     transcript: transcript, summary: summary)
        currentSessionID = session.id
        SessionStore.save(session)
        loadSessions()
    }

    func openSession(_ session: MeetingSession) {
        transcript = session.transcript
        summary = session.summary
        meetingTitle = session.title
        currentSessionID = session.id
        errorMessage = nil
        state = .done
    }

    /// Re-runs summarization on the current transcript with the chosen engine —
    /// useful when the first attempt failed or you switch engines.
    func reSummarize() {
        guard !transcript.isEmpty else { return }
        let lines = transcript
        state = .processing
        Task {
            let joined = lines.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
            if intelligenceEngine.mlxVariant != nil {
                processingMessage = "Loading \(intelligenceEngine.rawValue)…"
                let ok = await loadMLXForUse()
                if !ok {
                    errorMessage = "Gemma was unavailable, so re-summarize used Apple Intelligence/on-device fallback."
                }
            }
            processingMessage = "Summarizing notes…"
            let newSummary = await MeetingSummarizer.summarize(transcript: joined, engine: intelligenceEngine)
            summary = newSummary
            state = .done
            processingMessage = "Transcribing & summarizing…"
            if let id = currentSessionID, var session = sessions.first(where: { $0.id == id }) {
                session.summary = newSummary
                SessionStore.save(session)
                loadSessions()
            }
        }
    }

    func deleteSession(_ session: MeetingSession) {
        SessionStore.delete(session)
        if currentSessionID == session.id { reset() }
        loadSessions()
    }

    /// Either keeps the recordings in the Recordings folder or deletes them.
    private func handleRecordings(_ urls: URL?...) {
        let files = urls.compactMap { $0 }
        guard keepRecordings else {
            files.forEach { try? FileManager.default.removeItem(at: $0) }
            return
        }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let dest = recordingsFolder.appendingPathComponent(stamp, isDirectory: true)
        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        for url in files {
            let to = dest.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.moveItem(at: url, to: to)
        }
    }

    func openRecordingsFolder() {
        try? FileManager.default.createDirectory(at: recordingsFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(recordingsFolder)
    }

    func reset() {
        guard state != .recording else { return }
        state = .idle
        transcript = []
        summary = nil
        errorMessage = nil
        currentSessionID = nil
    }

    func copyNotes() {
        guard let summary else { return }
        var text = "\(meetingTitle)\n\n\(summary.summary)\n"
        if !summary.actionItems.isEmpty {
            text += "\nAction items:\n" + summary.actionItems.map { "- \($0)" }.joined(separator: "\n")
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func startTimer() {
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let startedAt = self.startedAt else { return }
                self.elapsed = Date().timeIntervalSince(startedAt)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
