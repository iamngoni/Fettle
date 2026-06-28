import Foundation

/// A saved Smart Notes session — transcript + summary kept so past meetings can
/// be revisited and re-summarized.
struct MeetingSession: Identifiable, Codable, Equatable {
    var id = UUID()
    var date: Date
    var title: String
    var duration: TimeInterval
    var transcript: [TranscriptLine]
    var summary: MeetingSummary

    var transcriptText: String {
        transcript.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
    }
    var durationText: String {
        let s = Int(duration)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Persists sessions as individual JSON files under Application Support.
enum SessionStore {
    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Fettle/Sessions", isDirectory: true)
    }

    static func all() -> [MeetingSession] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(MeetingSession.self, from: Data(contentsOf: $0)) }
            .sorted { $0.date > $1.date }
    }

    static func save(_ session: MeetingSession) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(session) else { return }
        try? data.write(to: folder.appendingPathComponent("\(session.id.uuidString).json"))
    }

    static func delete(_ session: MeetingSession) {
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("\(session.id.uuidString).json"))
    }
}
