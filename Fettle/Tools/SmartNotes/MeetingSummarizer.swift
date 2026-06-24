import Foundation
import NaturalLanguage
#if canImport(FoundationModels)
import FoundationModels
#endif

struct MeetingSummary {
    var summary: String
    var actionItems: [String]
    var engine: String
}

/// Summarizes a transcript. Prefers Apple Intelligence (Foundation Models) when
/// available on-device; otherwise falls back to a NaturalLanguage extractive
/// summary so notes always work offline.
enum MeetingSummarizer {

    static func summarize(transcript: String) async -> MeetingSummary {
        let clean = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            return MeetingSummary(summary: "No speech was recognized in this recording.", actionItems: [], engine: "—")
        }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), let ai = await foundationModels(clean) {
            return ai
        }
        #endif
        return extractive(clean)
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func foundationModels(_ transcript: String) async -> MeetingSummary? {
        guard SystemLanguageModel.default.availability == .available else { return nil }
        do {
            let session = LanguageModelSession()
            let prompt = """
            You are summarizing a meeting transcript. Write a concise 2–3 sentence summary, \
            then a line that says "ACTIONS:" followed by each action item on its own line \
            prefixed with "- ". Only include action items that were actually discussed.

            Transcript:
            \(transcript.prefix(6000))
            """
            let response = try await session.respond(to: prompt)
            return parse(response.content, engine: "Apple Intelligence")
        } catch {
            return nil
        }
    }
    #endif

    private static func parse(_ text: String, engine: String) -> MeetingSummary {
        let parts = text.components(separatedBy: "ACTIONS:")
        let summary = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? text
        var actions: [String] = []
        if parts.count > 1 {
            actions = parts[1]
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "-•* \t")) }
                .filter { !$0.isEmpty }
        }
        return MeetingSummary(summary: summary, actionItems: actions, engine: engine)
    }

    // MARK: NaturalLanguage extractive fallback

    private static func extractive(_ transcript: String) -> MeetingSummary {
        let sentences = splitSentences(transcript)
        guard !sentences.isEmpty else {
            return MeetingSummary(summary: transcript, actionItems: [], engine: "On-device")
        }

        // Rank sentences by summed frequency of their significant words.
        var freq: [String: Int] = [:]
        for word in significantWords(transcript) { freq[word, default: 0] += 1 }
        func score(_ s: String) -> Int { significantWords(s).reduce(0) { $0 + (freq[$1] ?? 0) } }

        let ranked = sentences.enumerated().sorted { score($0.element) > score($1.element) }
        let topIndices = Set(ranked.prefix(3).map { $0.offset })
        let summary = sentences.enumerated()
            .filter { topIndices.contains($0.offset) }
            .map { $0.element }
            .joined(separator: " ")

        let actionKeywords = ["will ", "need to", "should ", "let's ", "action", "follow up",
                              "to-do", "todo", "by ", "i'll ", "we'll ", "next step", "assign"]
        let actions = sentences
            .filter { s in let l = s.lowercased(); return actionKeywords.contains { l.contains($0) } }
            .prefix(5)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        return MeetingSummary(summary: summary.isEmpty ? transcript : summary,
                              actionItems: Array(actions), engine: "On-device")
    }

    private static func splitSentences(_ text: String) -> [String] {
        var result: [String] = []
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let s = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if s.count > 8 { result.append(s) }
            return true
        }
        return result
    }

    private static func significantWords(_ text: String) -> [String] {
        var words: [String] = []
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        let stop: Set<String> = ["the", "a", "an", "and", "or", "but", "to", "of", "in", "on",
                                 "is", "are", "was", "were", "it", "this", "that", "i", "you", "we"]
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass,
                             options: [.omitPunctuation, .omitWhitespace]) { tag, range in
            let w = text[range].lowercased()
            if let tag, (tag == .noun || tag == .verb || tag == .adjective), !stop.contains(w), w.count > 2 {
                words.append(w)
            }
            return true
        }
        return words
    }
}
