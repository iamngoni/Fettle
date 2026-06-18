import Foundation
import AppKit

/// Runs Shortcuts by name — the only reliable way to toggle a Focus / Do Not
/// Disturb, since macOS exposes no public Focus API. Presentation Mode calls
/// the user's "Fettle Focus On/Off" shortcuts.
enum ShortcutsRunner {
    static let focusOnName = "Fettle Focus On"
    static let focusOffName = "Fettle Focus Off"

    @discardableResult
    static func run(_ name: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do { try process.run(); return true } catch { return false }
    }

    /// Whether both Focus shortcuts exist.
    static func focusShortcutsInstalled() -> Bool {
        let names = list()
        return names.contains(focusOnName) && names.contains(focusOffName)
    }

    static func list() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["list"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return [] }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func openShortcutsApp() {
        if let url = URL(string: "shortcuts://") { NSWorkspace.shared.open(url) }
    }
}
