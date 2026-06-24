import Foundation
import OSLog

/// Lightweight file logger. Writes timestamped lines to
/// `~/Library/Logs/Fettle/fettle.log` (also mirrored to the unified log) so
/// there's a durable, user-readable record of activity and errors. Uncaught
/// Objective-C exceptions are captured too.
enum FettleLog {
    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Fettle", isDirectory: true)
    static let fileURL = directory.appendingPathComponent("fettle.log")

    private static let osLog = Logger(subsystem: "com.fettle.app", category: "Fettle")
    private static let queue = DispatchQueue(label: "com.fettle.filelog")
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func setup() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        rotateIfNeeded()
        NSSetUncaughtExceptionHandler { exc in
            let frames = exc.callStackSymbols.prefix(20).joined(separator: "\n    ")
            FettleLog.write("UNCAUGHT \(exc.name.rawValue): \(exc.reason ?? "")\n    \(frames)", level: "FAULT")
        }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        write("Fettle launched (v\(version))", level: "INFO")
    }

    static func log(_ message: String) { write(message, level: "INFO") }
    static func error(_ message: String) { write(message, level: "ERROR") }

    private static func write(_ message: String, level: String) {
        osLog.log("\(message, privacy: .public)")
        let timestamp = formatter.string(from: Date())
        queue.async {
            let line = "\(timestamp) [\(level)] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: fileURL)
            }
        }
    }

    /// Keep the active log under ~1 MB by rotating to a single previous file.
    private static func rotateIfNeeded() {
        guard let size = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int,
              size > 1_000_000 else { return }
        let previous = directory.appendingPathComponent("fettle.previous.log")
        try? FileManager.default.removeItem(at: previous)
        try? FileManager.default.moveItem(at: fileURL, to: previous)
    }
}
