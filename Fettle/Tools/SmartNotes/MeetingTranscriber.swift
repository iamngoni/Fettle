import Foundation
import Speech
import NaturalLanguage

struct TranscriptLine: Identifiable, Codable, Equatable {
    var id = UUID()
    let speaker: String
    let text: String
    let start: TimeInterval
}

enum TranscriptionEngine: String, CaseIterable, Codable {
    case whisper = "Whisper", appleSpeech = "Apple Speech"
    var subtitle: String {
        switch self {
        case .whisper: return "Faster · downloads on first use"
        case .appleSpeech: return "Built-in · on-device"
        }
    }
    var isAvailable: Bool { true }
}

/// On-device speech-to-text. Each audio file is transcribed separately and the
/// resulting sentences are interleaved by timestamp, so the mic file is labelled
/// "You" and the system file "Them".
enum MeetingTranscriber {

    static func authorize() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }

    static func transcribe(systemURL: URL?, micURL: URL?, engine: TranscriptionEngine) async -> [TranscriptLine] {
        var useWhisper = false
        if engine == .whisper { useWhisper = await WhisperTranscriber.shared.isReady }
        FettleLog.log("Transcribe engine=\(engine.rawValue) useWhisper=\(useWhisper)")
        var lines: [TranscriptLine] = []
        if let micURL { lines += await transcribeFile(micURL, speaker: "You", useWhisper: useWhisper) }
        if let systemURL { lines += await transcribeFile(systemURL, speaker: "Them", useWhisper: useWhisper) }
        return lines.sorted { $0.start < $1.start }
    }

    /// Splits Whisper's plain text into sentence-sized lines for one speaker.
    private static func splitLines(_ text: String, speaker: String) -> [TranscriptLine] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var lines: [TranscriptLine] = []
        var index: TimeInterval = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let s = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { lines.append(TranscriptLine(speaker: speaker, text: s, start: index)); index += 1 }
            return true
        }
        if lines.isEmpty { lines.append(TranscriptLine(speaker: speaker, text: text, start: 0)) }
        return lines
    }

    /// Ensures the continuation is resumed exactly once across the recognition
    /// callback and the watchdog, from any thread.
    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed = false
        func claim() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if claimed { return false }
            claimed = true
            return true
        }
    }

    private static func transcribeFile(_ url: URL, speaker: String, useWhisper: Bool) async -> [TranscriptLine] {
        if useWhisper, let text = await WhisperTranscriber.shared.transcribe(url), !text.isEmpty {
            FettleLog.log("Transcriber[\(speaker)]: whisper \(text.count) chars")
            return splitLines(text, speaker: speaker)
        }
        let auth = SFSpeechRecognizer.authorizationStatus().rawValue
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) else {
            FettleLog.error("Transcriber[\(speaker)]: no recognizer (auth=\(auth))")
            return []
        }
        FettleLog.log("Transcriber[\(speaker)]: available=\(recognizer.isAvailable) onDevice=\(recognizer.supportsOnDeviceRecognition) auth=\(auth)")
        guard recognizer.isAvailable else { return [] }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.shouldReportPartialResults = false
        if #available(macOS 13.0, *) { request.addsPunctuation = true }

        let box = Box()
        let lines = await withCheckedContinuation { (cont: CheckedContinuation<[TranscriptLine], Never>) in
            recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    if box.claim() {
                        FettleLog.log("Transcriber[\(speaker)]: \(result.bestTranscription.segments.count) segments, \(result.bestTranscription.formattedString.count) chars")
                        cont.resume(returning: groupSentences(result.bestTranscription, speaker: speaker))
                    }
                } else if let error {
                    if box.claim() {
                        FettleLog.error("Transcriber[\(speaker)] error: \(error.localizedDescription)")
                        cont.resume(returning: [])
                    }
                }
            }
            // Watchdog: never let "processing" hang if recognition stalls. The
            // abandoned task's later callback no-ops because claim() is taken.
            DispatchQueue.global().asyncAfter(deadline: .now() + 300) {
                if box.claim() { cont.resume(returning: []) }
            }
        }
        return lines
    }

    /// Groups transcription segments into sentence-sized lines with start times.
    private static func groupSentences(_ transcription: SFTranscription, speaker: String) -> [TranscriptLine] {
        var lines: [TranscriptLine] = []
        var current = ""
        var lineStart: TimeInterval = 0
        for (index, seg) in transcription.segments.enumerated() {
            if current.isEmpty { lineStart = seg.timestamp }
            current += (current.isEmpty ? "" : " ") + seg.substring
            let endsSentence = seg.substring.range(of: "[.!?]$", options: .regularExpression) != nil
            if endsSentence || index == transcription.segments.count - 1 {
                let trimmed = current.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    lines.append(TranscriptLine(speaker: speaker, text: trimmed, start: lineStart))
                }
                current = ""
            }
        }
        if lines.isEmpty, !transcription.formattedString.isEmpty {
            lines.append(TranscriptLine(speaker: speaker, text: transcription.formattedString, start: 0))
        }
        return lines
    }
}
