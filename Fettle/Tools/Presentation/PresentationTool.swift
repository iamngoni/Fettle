import SwiftUI

/// A meta-tool that composes other tools into a single "focus for talks" switch.
/// Demonstrates that tools can drive each other through the same model layer.
@MainActor
@Observable
final class PresentationTool: FettleTool {
    let kind: ToolID = .presentation
    let title = "Presentation Mode"
    let symbol = "videoprojector.fill"
    let tint = Color(hex: 0xFFD60A)
    let section: ToolSection = .sessions

    // Which actions the mode bundles.
    var includeKeepAwake = Store.bool("pm.keepAwake", default: true) {
        didSet { Store.set(includeKeepAwake, "pm.keepAwake") }
    }
    var includeDoNotDisturb = Store.bool("pm.dnd", default: true) {
        didSet { Store.set(includeDoNotDisturb, "pm.dnd") }
    }
    var includeHideDesktop = Store.bool("pm.hideDesktop", default: true) {
        didSet { Store.set(includeHideDesktop, "pm.hideDesktop") }
    }
    var includeMuteMic = Store.bool("pm.muteMic", default: false) {
        didSet { Store.set(includeMuteMic, "pm.muteMic") }
    }

    private(set) var isActive = false

    // Wired up by AppState after init to avoid an initialization cycle.
    weak var keepAwake: KeepAwakeTool?
    weak var hideDesktop: HideDesktopTool?
    weak var micMute: MicMuteTool?

    private var restoreHideDesktopVisible = false
    private var restoreMicLive = false

    var statusText: String { isActive ? "On" : "Off" }
    var statusTint: Color { isActive ? Color(hex: 0xFFE08A) : Theme.textMuted }
    var control: ToolControl { .toggleAndNavigate }
    var hasDetail: Bool { true }

    func configure(keepAwake: KeepAwakeTool, hideDesktop: HideDesktopTool, micMute: MicMuteTool) {
        self.keepAwake = keepAwake
        self.hideDesktop = hideDesktop
        self.micMute = micMute
    }

    func setActive(_ active: Bool) { active ? start() : stop() }
    func toggle() { isActive ? stop() : start() }

    var dndShortcutsInstalled: Bool { ShortcutsRunner.focusShortcutsInstalled() }

    func start() {
        if includeKeepAwake { keepAwake?.start() }
        if includeHideDesktop, let hd = hideDesktop {
            restoreHideDesktopVisible = !hd.isActive
            hd.setHidden(true)
        }
        if includeMuteMic, let mm = micMute {
            restoreMicLive = !mm.isActive
            mm.setMuted(true)
        }
        // Focus / Do Not Disturb via the user's Shortcut (no public Focus API).
        if includeDoNotDisturb { ShortcutsRunner.run(ShortcutsRunner.focusOnName) }
        isActive = true
    }

    func stop() {
        if includeKeepAwake { keepAwake?.stop() }
        if includeHideDesktop, restoreHideDesktopVisible { hideDesktop?.setHidden(false) }
        if includeMuteMic, restoreMicLive { micMute?.setMuted(false) }
        if includeDoNotDisturb { ShortcutsRunner.run(ShortcutsRunner.focusOffName) }
        isActive = false
    }
}
