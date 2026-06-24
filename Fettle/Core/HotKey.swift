import Carbon.HIToolbox
import Foundation

/// Registers system-wide hotkeys via the Carbon Hot Key API. Unlike an event
/// tap this needs no Accessibility permission, and it reports both press and
/// release (so Mic Mute can do push-to-talk).
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    struct Callbacks { var onPress: () -> Void; var onRelease: () -> Void }

    private var handlerInstalled = false
    private var callbacks: [UInt32: Callbacks] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1

    /// Common modifier masks (Carbon).
    static let cmdOption = UInt32(cmdKey | optionKey)
    static let keyM = UInt32(kVK_ANSI_M)

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32,
                  onPress: @escaping () -> Void,
                  onRelease: @escaping () -> Void = {}) -> UInt32 {
        installHandlerIfNeeded()
        let id = nextID; nextID += 1
        let hotKeyID = EventHotKeyID(signature: OSType(0x46544C45), id: id) // 'FTLE'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            FettleLog.error("Hotkey registration failed (keyCode=\(keyCode) mods=\(modifiers)) — likely already taken by another app")
            return 0
        }
        refs[id] = ref
        callbacks[id] = Callbacks(onPress: onPress, onRelease: onRelease)
        return id
    }

    func unregister(_ id: UInt32) {
        if let ref = refs[id] { UnregisterEventHotKey(ref) }
        refs[id] = nil
        callbacks[id] = nil
    }

    fileprivate func dispatch(id: UInt32, pressed: Bool) {
        guard let cb = callbacks[id] else { return }
        pressed ? cb.onPress() : cb.onRelease()
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            let id = hotKeyID.id
            DispatchQueue.main.async { MainActor.assumeIsolated { HotKeyCenter.shared.dispatch(id: id, pressed: pressed) } }
            return noErr
        }, 2, &specs, nil, nil)
        handlerInstalled = true
    }
}
