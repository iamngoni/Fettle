import SwiftUI
import AppKit

@main
struct FettleApp: App {
    @State private var appState = AppState.shared

    init() {
        guard Self.isPreviewLaunch else { return }
        Self.applyPreviewRoute()
        DispatchQueue.main.async {
            Self.showPreviewWindow()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            RootView()
                .environment(appState)
                .frame(width: Theme.panelWidth)
        } label: {
            MenuBarLabel(appState: appState)
        }
        .menuBarExtraStyle(.window)
    }

    @MainActor private static var previewWindow: NSWindow?

    private static var isPreviewLaunch: Bool {
        ProcessInfo.processInfo.environment["FETTLE_PREVIEW"] == "1"
    }

    private static func applyPreviewRoute() {
        guard let raw = ProcessInfo.processInfo.environment["FETTLE_PREVIEW_ROUTE"] else { return }
        let state = AppState.shared
        switch raw {
        case "settings": state.route = .settings
        case "smartNotes": state.route = .tool(.smartNotes)
        case "compress": state.route = .tool(.compress)
        case "devices": state.route = .tool(.devices)
        case "calculator": state.route = .tool(.calculator)
        case "notch": state.route = .tool(.notch)
        default: break
        }
    }

    @MainActor
    private static func showPreviewWindow() {
        guard previewWindow == nil else { return }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Theme.panelWidth, height: 820),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Fettle Preview"
        window.contentView = NSHostingView(
            rootView: RootView()
                .environment(AppState.shared)
                .frame(width: Theme.panelWidth, height: 820, alignment: .top)
        )
        window.center()
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        previewWindow = window
    }
}
