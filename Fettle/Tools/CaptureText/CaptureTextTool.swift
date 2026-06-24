import SwiftUI
import AppKit
import Carbon.HIToolbox
import CoreGraphics

@MainActor
@Observable
final class CaptureTextTool: FettleTool {
    let kind: ToolID = .captureText
    let title = "Capture Text"
    let symbol = "text.viewfinder"
    let tint = Color(hex: 0x32D74B)
    let section: ToolSection = .tools

    var keepLineBreaks = Store.bool("ocr.keepLines", default: true) {
        didSet { Store.set(keepLineBreaks, "ocr.keepLines") }
    }
    var autoCopy = Store.bool("ocr.autoCopy", default: true) {
        didSet { Store.set(autoCopy, "ocr.autoCopy") }
    }
    var detectBarcodes = Store.bool("ocr.barcodes", default: true) {
        didSet { Store.set(detectBarcodes, "ocr.barcodes") }
    }
    var soundFeedback = Store.bool("ocr.sound", default: true) {
        didSet { Store.set(soundFeedback, "ocr.sound") }
    }

    private(set) var recents: [String] = []
    private(set) var isCapturing = false
    private(set) var lastResultWasBarcode = false
    private(set) var needsScreenAccess = false

    var screenAuthorized: Bool { CGPreflightScreenCaptureAccess() }

    private var hotKeyID: UInt32 = 0

    var isActive: Bool { false }
    var statusText: String {
        if isCapturing { return "Select a region…" }
        return recents.isEmpty ? "⇧⌘2 · grab text on screen" : "\(recents.count) recent · ⇧⌘2"
    }
    var statusTint: Color { Theme.textMuted }
    var control: ToolControl { .navigate }
    var hasDetail: Bool { true }

    init() {
        loadRecents()
        registerHotKey()
    }

    func registerHotKey() {
        guard hotKeyID == 0 else { return }
        // ⇧⌘2
        hotKeyID = HotKeyCenter.shared.register(
            keyCode: UInt32(kVK_ANSI_2),
            modifiers: UInt32(cmdKey | shiftKey),
            onPress: { [weak self] in self?.triggerCapture() })
    }

    func triggerCapture() {
        guard !isCapturing else { return }
        // Screen-recording authorization is read once per app launch. If it's not
        // effective yet, request it and tell the user to relaunch — don't spawn
        // screencapture into a stale-permission state.
        if !CGPreflightScreenCaptureAccess() {
            needsScreenAccess = true
            CGRequestScreenCaptureAccess()
            return
        }
        needsScreenAccess = false
        isCapturing = true
        Task {
            let result = await CaptureService.captureAndRecognize(
                keepLineBreaks: keepLineBreaks, detectBarcodes: detectBarcodes)
            isCapturing = false
            guard let result, !result.text.isEmpty else {
                if soundFeedback { NSSound.beep() }
                return
            }
            lastResultWasBarcode = result.isBarcode
            if autoCopy {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(result.text, forType: .string)
            }
            addRecent(result.text)
            if soundFeedback { NSSound(named: "Tink")?.play() }
        }
    }

    func openScreenSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func relaunch() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    func copyRecent(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        if soundFeedback { NSSound(named: "Tink")?.play() }
    }

    func clearRecents() {
        recents.removeAll()
        saveRecents()
    }

    private func addRecent(_ text: String) {
        recents.removeAll { $0 == text }
        recents.insert(text, at: 0)
        if recents.count > 8 { recents = Array(recents.prefix(8)) }
        saveRecents()
    }

    private func loadRecents() {
        if let data = UserDefaults.standard.data(forKey: "ocr.recents"),
           let list = try? JSONDecoder().decode([String].self, from: data) {
            recents = list
        }
    }

    private func saveRecents() {
        if let data = try? JSONEncoder().encode(recents) {
            UserDefaults.standard.set(data, forKey: "ocr.recents")
        }
    }
}
