import SwiftUI
import AppKit
import Carbon.HIToolbox

struct ShortcutBinding: Codable {
    var keyCode: Int
    var carbonMods: UInt32
    var display: String
    var enabled: Bool
}

struct ShortcutAction: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let tint: Color
    let defaultBinding: ShortcutBinding
}

@MainActor
@Observable
final class ShortcutsTool: FettleTool {
    let kind: ToolID = .shortcuts
    let title = "Shortcuts"
    let symbol = "command.square"
    let tint = Color(hex: 0x5E5CE6)
    let section: ToolSection = .windows

    static let actions: [ShortcutAction] = [
        .init(id: "mute", title: "Mute / unmute mic", symbol: "mic.slash.fill", tint: Color(hex: 0xFF453A),
              defaultBinding: bind(kVK_ANSI_M, control: true, option: true, "⌃⌥M")),
        .init(id: "capture", title: "Capture text", symbol: "text.viewfinder", tint: Color(hex: 0x32D74B),
              defaultBinding: bind(kVK_ANSI_T, control: true, option: true, "⌃⌥T")),
        .init(id: "notes", title: "Start / stop Smart Notes", symbol: "sparkles", tint: Color(hex: 0xBF5AF2),
              defaultBinding: bind(kVK_ANSI_N, control: true, option: true, "⌃⌥N")),
        .init(id: "keepAwake", title: "Toggle Keep Awake", symbol: "cup.and.saucer.fill", tint: Color(hex: 0xFF8A00),
              defaultBinding: bind(kVK_ANSI_K, control: true, option: true, "⌃⌥K")),
        .init(id: "presentation", title: "Toggle Presentation Mode", symbol: "play.rectangle.fill", tint: Color(hex: 0xFFD60A),
              defaultBinding: bind(kVK_ANSI_P, control: true, option: true, "⌃⌥P")),
        .init(id: "hideDesktop", title: "Hide / show desktop icons", symbol: "menubar.dock.rectangle", tint: Color(hex: 0x8E8E96),
              defaultBinding: bind(kVK_ANSI_D, control: true, option: true, "⌃⌥D")),
    ]

    var bindings: [String: ShortcutBinding] = [:]
    private(set) var recordingAction: String?

    @ObservationIgnored private var handlers: [String: () -> Void] = [:]
    @ObservationIgnored private var hotKeyIDs: [String: UInt32] = [:]
    @ObservationIgnored private var recordMonitor: Any?

    var isActive: Bool { false }
    var statusText: String {
        let on = bindings.values.filter { $0.enabled }.count
        return "\(on) active shortcut\(on == 1 ? "" : "s")"
    }
    var statusTint: Color { Theme.textMuted }
    var control: ToolControl { .navigate }
    var hasDetail: Bool { true }

    init() {
        load()
        for action in Self.actions where bindings[action.id] == nil {
            bindings[action.id] = action.defaultBinding
        }
    }

    /// Wired up by AppState with closures that invoke the relevant tools.
    func configure(handlers: [String: () -> Void]) {
        self.handlers = handlers
        registerAll()
    }

    func binding(for id: String) -> ShortcutBinding {
        bindings[id] ?? Self.actions.first { $0.id == id }!.defaultBinding
    }

    func toggle(_ id: String, _ enabled: Bool) {
        bindings[id]?.enabled = enabled
        save(); registerAll()
    }

    func startRecording(_ id: String) {
        stopRecording()
        recordingAction = id
        recordMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            self.captureRecording(event)
            return nil
        }
    }

    func stopRecording() {
        if let m = recordMonitor { NSEvent.removeMonitor(m); recordMonitor = nil }
        recordingAction = nil
    }

    private func captureRecording(_ event: NSEvent) {
        guard let id = recordingAction else { return }
        if event.keyCode == UInt16(kVK_Escape) { stopRecording(); return }
        let mods = Self.carbonModifiers(event.modifierFlags)
        guard mods != 0 else { return }   // require at least one modifier
        let display = Self.displayString(keyCode: Int(event.keyCode), flags: event.modifierFlags)
        var b = binding(for: id)
        b.keyCode = Int(event.keyCode)
        b.carbonMods = mods
        b.display = display
        bindings[id] = b
        save()
        stopRecording()
        registerAll()
    }

    // MARK: Hotkey registration

    private func registerAll() {
        hotKeyIDs.values.forEach { HotKeyCenter.shared.unregister($0) }
        hotKeyIDs.removeAll()
        for action in Self.actions {
            let b = binding(for: action.id)
            guard b.enabled, let handler = handlers[action.id] else { continue }
            let id = HotKeyCenter.shared.register(keyCode: UInt32(b.keyCode), modifiers: b.carbonMods,
                                                  onPress: handler)
            if id != 0 { hotKeyIDs[action.id] = id }
        }
    }

    // MARK: Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(bindings) {
            UserDefaults.standard.set(data, forKey: "shortcuts.bindings")
        }
    }
    private func load() {
        if let data = UserDefaults.standard.data(forKey: "shortcuts.bindings"),
           let decoded = try? JSONDecoder().decode([String: ShortcutBinding].self, from: data) {
            bindings = decoded
        }
    }

    // MARK: Helpers

    private static func bind(_ key: Int, control: Bool = false, option: Bool = false,
                             command: Bool = false, shift: Bool = false, _ display: String) -> ShortcutBinding {
        var m: UInt32 = 0
        if control { m |= UInt32(controlKey) }
        if option { m |= UInt32(optionKey) }
        if command { m |= UInt32(cmdKey) }
        if shift { m |= UInt32(shiftKey) }
        return ShortcutBinding(keyCode: key, carbonMods: m, display: display, enabled: true)
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    static func displayString(keyCode: Int, flags: NSEvent.ModifierFlags) -> String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        s += keyName(keyCode)
        return s
    }

    static func keyName(_ keyCode: Int) -> String {
        let map: [Int: String] = [
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Return: "↩", kVK_Space: "Space", kVK_Escape: "esc", kVK_Tab: "⇥", kVK_Delete: "⌫",
        ]
        if let s = map[keyCode] { return s }
        let letters: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E",
            kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J",
            kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
            kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
            kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y",
            kVK_ANSI_Z: "Z", kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
            kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        ]
        return letters[keyCode] ?? "?"
    }
}
