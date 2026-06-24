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
    private(set) var meetingTitle = "Meeting"

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

    func toggle() { state == .recording ? stop() : start() }

    func start() {
        guard state != .recording else { return }
        errorMessage = nil
        transcript = []
        summary = nil
        Task {
            _ = await MeetingTranscriber.authorize()
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
            let lines = await MeetingTranscriber.transcribe(systemURL: output.systemURL, micURL: output.micURL)
            transcript = lines
            let joined = lines.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
            summary = await MeetingSummarizer.summarize(transcript: joined)
            state = .done
            // Clean up temp audio.
            [output.systemURL, output.micURL].compactMap { $0 }.forEach { try? FileManager.default.removeItem(at: $0) }
        }
    }

    func reset() {
        guard state != .recording else { return }
        state = .idle
        transcript = []
        summary = nil
        errorMessage = nil
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
