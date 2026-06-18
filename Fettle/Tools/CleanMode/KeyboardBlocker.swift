import CoreGraphics
import Foundation

/// Installs a session-level CGEvent tap that swallows all keyboard input.
/// Mouse/trackpad are intentionally untouched so the user can always unlock.
/// The configured escape sequence (Esc ×3) is detected by the tap and used as
/// an unlock signal rather than being passed through.
///
/// Not main-actor isolated: the tap callback fires on the run loop thread.
final class KeyboardBlocker: @unchecked Sendable {

    nonisolated(unsafe) private var tap: CFMachPort?
    nonisolated(unsafe) private var source: CFRunLoopSource?
    nonisolated(unsafe) private var escTimestamps: [CFAbsoluteTime] = []
    nonisolated(unsafe) var onKeyBlocked: (() -> Void)?
    nonisolated(unsafe) var onUnlockSequence: (() -> Void)?
    nonisolated(unsafe) var escUnlockEnabled = true

    private static let escKeyCode: Int64 = 53
    private static let escWindow: CFAbsoluteTime = 2.0

    nonisolated var isRunning: Bool { tap != nil }

    nonisolated func start() -> Bool {
        guard tap == nil else { return true }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let blocker = Unmanaged<KeyboardBlocker>.fromOpaque(refcon).takeUnretainedValue()
                return blocker.handle(type: type, event: event)
            },
            userInfo: refcon
        ) else { return false }

        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.source = src
        return true
    }

    nonisolated func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        escTimestamps.removeAll()
    }

    private nonisolated func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system disables a tap that times out; re-enable and keep blocking.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return nil
        }

        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            onKeyBlocked?()
            if escUnlockEnabled && keyCode == Self.escKeyCode {
                registerEscPress()
            }
        }
        // Swallow every keyboard event.
        return nil
    }

    private nonisolated func registerEscPress() {
        let now = CFAbsoluteTimeGetCurrent()
        escTimestamps = escTimestamps.filter { now - $0 <= Self.escWindow }
        escTimestamps.append(now)
        if escTimestamps.count >= 3 {
            escTimestamps.removeAll()
            onUnlockSequence?()
        }
    }
}
