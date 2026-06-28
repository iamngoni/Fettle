import SwiftUI
import AppKit

/// Briefly flashes a translucent highlight over the region a window was just
/// snapped to, so the action is visible.
@MainActor
enum SnapFlash {
    private static var window: NSWindow?
    private static var hideWork: DispatchWorkItem?

    static func flash(_ frame: NSRect) {
        hideWork?.cancel()
        let win = window ?? makeWindow()
        window = win
        win.setFrame(frame, display: false)
        win.alphaValue = 0
        win.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.10
            win.animator().alphaValue = 1
        }
        let work = DispatchWorkItem { fadeOut() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private static func fadeOut() {
        guard let win = window else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.28
            win.animator().alphaValue = 0
        }, completionHandler: { win.orderOut(nil) })
    }

    private static func makeWindow() -> NSWindow {
        let win = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .floating
        win.ignoresMouseEvents = true
        win.hasShadow = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        win.contentView = NSHostingView(rootView: SnapFlashView())
        return win
    }
}

private struct SnapFlashView: View {
    private let accent = Color(hex: 0x0A84FF)
    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(accent.opacity(0.22))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(accent, lineWidth: 3))
            .padding(5)
    }
}
