import SwiftUI
import AppKit

/// A borderless overlay on the main screen. The user drags a rectangle and its
/// pixel dimensions are reported back (points × backing scale).
@MainActor
final class MeasureOverlayController {
    private weak var tool: MeasureTool?
    private var window: NSWindow?
    private var keyMonitor: Any?

    init(tool: MeasureTool) { self.tool = tool }

    func present(onComplete: @escaping (CGFloat, CGFloat) -> Void) {
        dismiss()
        guard let screen = NSScreen.main else { return }
        let scale = screen.backingScaleFactor
        let win = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .screenSaver
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        win.ignoresMouseEvents = false
        win.contentView = NSHostingView(rootView: MeasureOverlayView(
            scale: scale,
            onComplete: { [weak self] w, h in
                onComplete(w, h)
                self?.dismiss()
            },
            onCancel: { [weak self] in self?.dismiss() }))
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = win

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.dismiss(); return nil }   // esc
            return event
        }
    }

    func dismiss() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        window?.orderOut(nil)
        window = nil
    }
}

struct MeasureOverlayView: View {
    let scale: CGFloat
    var onComplete: (CGFloat, CGFloat) -> Void
    var onCancel: () -> Void

    @State private var start: CGPoint?
    @State private var current: CGPoint?

    private let accent = Color(hex: 0xFF375F)

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.06).ignoresSafeArea()

            if let rect = selectionRect {
                Rectangle()
                    .fill(accent.opacity(0.1))
                    .overlay(Rectangle().stroke(accent, lineWidth: 1.5))
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)

                Text("\(Int(rect.width * scale)) × \(Int(rect.height * scale)) px")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.vertical, 4).padding(.horizontal, 9)
                    .background(RoundedRectangle(cornerRadius: 6).fill(accent))
                    .offset(x: rect.midX - 50, y: rect.midY - 12)
            }

            if start == nil {
                VStack {
                    Spacer()
                    Text("Drag to measure · Esc to cancel")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                        .padding(.vertical, 8).padding(.horizontal, 16)
                        .background(Capsule().fill(.black.opacity(0.5)))
                    Spacer().frame(height: 60)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if start == nil { start = value.startLocation }
                    current = value.location
                }
                .onEnded { value in
                    let s = start ?? value.startLocation
                    let w = abs(value.location.x - s.x) * scale
                    let h = abs(value.location.y - s.y) * scale
                    if w < 2 || h < 2 { onCancel() } else { onComplete(w, h) }
                }
        )
    }

    private var selectionRect: CGRect? {
        guard let s = start, let c = current else { return nil }
        return CGRect(x: min(s.x, c.x), y: min(s.y, c.y), width: abs(c.x - s.x), height: abs(c.y - s.y))
    }
}
