import SwiftUI

@MainActor
@Observable
final class CleanModeTool: FettleTool {
    let kind: ToolID = .cleanMode
    let title = "Clean Mode"
    let symbol = "sparkles"
    let tint = Color(hex: 0x5AC8FA)
    let section: ToolSection = .inputAudio

    enum AutoUnlock: String, CaseIterable, Identifiable {
        case s30, m1, m3, m5, m10, manual
        var id: String { rawValue }
        var label: String {
            switch self {
            case .s30: "30 sec"; case .m1: "1 min"; case .m3: "3 min"
            case .m5: "5 min"; case .m10: "10 min"; case .manual: "Manual"
            }
        }
        var seconds: TimeInterval? {
            switch self {
            case .s30: 30; case .m1: 60; case .m3: 180
            case .m5: 300; case .m10: 600; case .manual: nil
            }
        }
    }

    enum UnlockMethod: String, CaseIterable, Identifiable {
        case escTriple, button, touchID
        var id: String { rawValue }
        var label: String {
            switch self {
            case .escTriple: "Press Esc three times"
            case .button: "Click the unlock button"
            case .touchID: "Touch ID"
            }
        }
    }

    var autoUnlock = Store.rawValue("cm.autoUnlock", default: AutoUnlock.m1) {
        didSet { Store.set(autoUnlock, "cm.autoUnlock") }
    }
    var unlockMethod = Store.rawValue("cm.unlock", default: UnlockMethod.escTriple) {
        didSet { Store.set(unlockMethod, "cm.unlock"); blocker.escUnlockEnabled = unlockMethod == .escTriple }
    }

    private(set) var isActive = false      // keyboard currently locked
    private(set) var blockedCount = 0
    private(set) var endDate: Date?
    var needsPermission = false
    private var tick = 0

    private let blocker = KeyboardBlocker()
    private var overlay: CleanModeOverlayController?
    private var ticker: Timer?

    var statusText: String { isActive ? "Keyboard locked" : "Tap to lock keyboard" }
    var statusTint: Color { isActive ? Theme.accentLight : Theme.textMuted }
    var control: ToolControl { .navigate }
    var hasDetail: Bool { true }

    var remainingText: String? {
        _ = tick
        guard let endDate else { return nil }
        return "Auto-unlocks in " + Self.clock(max(0, endDate.timeIntervalSinceNow))
    }
    var liveBlockedCount: Int { _ = tick; return blockedCount }

    /// Returns false if it could not lock (permission missing).
    @discardableResult
    func lock() -> Bool {
        guard !isActive else { return true }
        guard AccessibilityPermission.isGranted else {
            needsPermission = true
            AccessibilityPermission.prompt()
            return false
        }
        blocker.escUnlockEnabled = unlockMethod == .escTriple
        blocker.onKeyBlocked = { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.blockedCount += 1 } }
        }
        blocker.onUnlockSequence = { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.unlock() } }
        }
        guard blocker.start() else { needsPermission = true; return false }

        blockedCount = 0
        needsPermission = false
        isActive = true
        if let secs = autoUnlock.seconds { endDate = Date().addingTimeInterval(secs) }
        else { endDate = nil }

        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.tick &+= 1
                if let end = self.endDate, Date() >= end { self.unlock() }
            }
        }
        overlay = CleanModeOverlayController(tool: self)
        overlay?.present()
        return true
    }

    func unlock() {
        guard isActive else { return }
        blocker.stop()
        ticker?.invalidate(); ticker = nil
        overlay?.dismiss(); overlay = nil
        endDate = nil
        isActive = false
    }

    static func clock(_ t: TimeInterval) -> String {
        let total = Int(t.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
