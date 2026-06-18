import SwiftUI
import Foundation

@MainActor
@Observable
final class HideDesktopTool: FettleTool {
    let kind: ToolID = .hideDesktop
    let title = "Hide Desktop Icons"
    let symbol = "eye.slash.fill"
    let tint = Theme.green
    let section: ToolSection = .system

    private(set) var isHidden = false

    var isActive: Bool { isHidden }
    var statusText: String { isHidden ? "Icons hidden" : "Icons visible" }
    var statusTint: Color { isHidden ? Theme.greenLight : Theme.textMuted }
    var control: ToolControl { .toggle }
    var hasDetail: Bool { false }

    init() {
        let value = Self.run("/usr/bin/defaults", ["read", "com.apple.finder", "CreateDesktop"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // CreateDesktop=false (or 0) means icons are hidden.
        isHidden = (value == "0" || value == "false")
    }

    func setActive(_ active: Bool) { setHidden(active) }
    func toggle() { setHidden(!isHidden) }

    func setHidden(_ hidden: Bool) {
        _ = Self.run("/usr/bin/defaults",
                     ["write", "com.apple.finder", "CreateDesktop", "-bool", hidden ? "false" : "true"])
        _ = Self.run("/usr/bin/killall", ["Finder"])
        isHidden = hidden
    }

    @discardableResult
    private static func run(_ launchPath: String, _ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
