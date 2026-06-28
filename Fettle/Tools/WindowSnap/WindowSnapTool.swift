import SwiftUI
import Carbon.HIToolbox

@MainActor
@Observable
final class WindowSnapTool: FettleTool {
    let kind: ToolID = .windowSnap
    let title = "Window Snap"
    let symbol = "rectangle.split.2x1"
    let tint = Color(hex: 0x0A84FF)
    let section: ToolSection = .windows

    var enabled = Store.bool("snap.enabled", default: true) {
        didSet { Store.set(enabled, "snap.enabled"); enabled ? registerHotKeys() : unregisterHotKeys() }
    }
    var gap = Store.double("snap.gap", default: 8) {
        didSet { Store.set(gap, "snap.gap") }
    }

    @ObservationIgnored private var hotKeyIDs: [UInt32] = []

    var trusted: Bool { WindowManager.isTrusted }
    var isActive: Bool { enabled }
    var statusText: String {
        trusted ? "On · ⌃⌥ + arrows" : "Grant accessibility access"
    }
    var statusTint: Color { enabled && trusted ? Theme.greenLight : Theme.textMuted }
    var control: ToolControl { .toggleAndNavigate }
    func setActive(_ active: Bool) {
        if active && !trusted { WindowManager.requestAccess() }
        enabled = active
    }
    var hasDetail: Bool { true }

    init() {
        if enabled { registerHotKeys() }
    }

    func apply(_ zone: WindowManager.Zone) {
        if !trusted { WindowManager.requestAccess(); return }
        if let frame = WindowManager.apply(zone, gap: CGFloat(gap)) {
            SnapFlash.flash(frame)
        }
    }

    func requestAccess() { WindowManager.requestAccess() }

    private func registerHotKeys() {
        unregisterHotKeys()
        let mods = UInt32(controlKey | optionKey)
        let bindings: [(Int, WindowManager.Zone)] = [
            (kVK_LeftArrow, .leftHalf),
            (kVK_RightArrow, .rightHalf),
            (kVK_UpArrow, .topHalf),
            (kVK_DownArrow, .bottomHalf),
            (kVK_Return, .maximize),
        ]
        for (key, zone) in bindings {
            let id = HotKeyCenter.shared.register(keyCode: UInt32(key), modifiers: mods,
                                                  onPress: { [weak self] in self?.apply(zone) })
            if id != 0 { hotKeyIDs.append(id) }
        }
    }

    private func unregisterHotKeys() {
        hotKeyIDs.forEach { HotKeyCenter.shared.unregister($0) }
        hotKeyIDs.removeAll()
    }
}
