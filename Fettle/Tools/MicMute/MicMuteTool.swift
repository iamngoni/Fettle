import SwiftUI
import AppKit

@MainActor
@Observable
final class MicMuteTool: FettleTool {
    let kind: ToolID = .micMute
    let title = "Mic Mute"
    let symbol = "mic.slash.fill"
    let tint = Theme.red
    let section: ToolSection = .inputAudio

    private(set) var isMuted = false
    var pushToTalk = Store.bool("mic.pushToTalk", default: false) {
        didSet { Store.set(pushToTalk, "mic.pushToTalk") }
    }
    var playSoundOnToggle = Store.bool("mic.playSound", default: true) {
        didSet { Store.set(playSoundOnToggle, "mic.playSound") }
    }
    var showLevelInMenuBar = Store.bool("mic.showLevel", default: true) {
        didSet { Store.set(showLevelInMenuBar, "mic.showLevel") }
    }

    var isActive: Bool { isMuted }
    var statusText: String { isMuted ? "Muted" : "Mic live" }
    var statusTint: Color { isMuted ? Theme.redLight : Theme.textMuted }
    var control: ToolControl { .toggleAndNavigate }
    var hasDetail: Bool { true }

    var inputDeviceName: String {
        AudioSystem.deviceName(AudioSystem.defaultDevice(input: true))
    }

    private var pttWasMuted = false

    init() {
        let device = AudioSystem.defaultDevice(input: true)
        isMuted = AudioSystem.isMuted(device, input: true)
        HotKeyCenter.shared.register(
            keyCode: HotKeyCenter.keyM, modifiers: HotKeyCenter.cmdOption,
            onPress: { [weak self] in self?.hotKeyPressed() },
            onRelease: { [weak self] in self?.hotKeyReleased() })
    }

    private func hotKeyPressed() {
        if pushToTalk {
            pttWasMuted = isMuted
            if isMuted { setMuted(false) }      // hold to talk
        } else {
            toggle()
        }
    }

    private func hotKeyReleased() {
        if pushToTalk, pttWasMuted { setMuted(true) }
    }

    func setActive(_ active: Bool) { setMuted(active) }
    func toggle() { setMuted(!isMuted) }

    func setMuted(_ muted: Bool) {
        let device = AudioSystem.defaultDevice(input: true)
        if AudioSystem.setMuted(muted, on: device, input: true) {
            isMuted = muted
        } else {
            // Some devices don't expose a mute property; fall back to refreshing state.
            isMuted = AudioSystem.isMuted(device, input: true)
        }
        if playSoundOnToggle {
            NSSound(named: isMuted ? "Tink" : "Pop")?.play()
        }
    }
}
