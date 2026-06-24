import Foundation
import Speech

struct TranscriptLine: Identifiable {
    let id = UUID()
    let speaker: String
    let text: String
    let start: TimeInterval
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

    static func transcribe(systemURL: URL?, micURL: URL?) async -> [TranscriptLine] {
        var lines: [TranscriptLine] = []
        if let micURL { lines += await transcribeFile(micURL, speaker: "You") }
        if let systemURL { lines += await transcribeFile(systemURL, speaker: "Them") }
        return lines.sorted { $0.start < $1.start }
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

    private static func transcribeFile(_ url: URL, speaker: String) async -> [TranscriptLine] {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.isAvailable else {
            return []
        }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        if #available(macOS 13.0, *) { request.addsPunctuation = true }

        let box = Box()
        return await withCheckedContinuation { (cont: CheckedContinuation<[TranscriptLine], Never>) in
            recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    if box.claim() { cont.resume(returning: groupSentences(result.bestTranscription, speaker: speaker)) }
                } else if error != nil {
                    if box.claim() { cont.resume(returning: []) }
                }
            }
            // Watchdog: never let "processing" hang if recognition stalls. The
            // abandoned task's later callback no-ops because claim() is taken.
            DispatchQueue.global().asyncAfter(deadline: .now() + 300) {
                if box.claim() { cont.resume(returning: []) }
            }
        }
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
