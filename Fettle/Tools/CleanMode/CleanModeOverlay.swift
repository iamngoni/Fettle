import SwiftUI
import AppKit

/// Manages borderless overlay windows (one per screen) shown while the keyboard
/// is locked.
@MainActor
final class CleanModeOverlayController {
    private weak var tool: CleanModeTool?
    private var windows: [NSWindow] = []

    init(tool: CleanModeTool) { self.tool = tool }

    func present() {
        guard let tool else { return }
        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.ignoresMouseEvents = false
            window.hasShadow = false
            window.contentView = NSHostingView(rootView: CleanModeOverlayView(tool: tool))
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        for window in windows { window.orderOut(nil) }
        windows.removeAll()
    }
}

struct CleanModeOverlayView: View {
    @Bindable var tool: CleanModeTool
    @State private var holdProgress = false

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [Color(hex: 0x241A10).opacity(0.95), Color(hex: 0x0A0A0C).opacity(0.97)],
                center: .init(x: 0.5, y: 0.42), startRadius: 40, endRadius: 900)
            .ignoresSafeArea()

            VStack(spacing: 26) {
                ZStack {
                    Circle().fill(Theme.accent.opacity(0.08))
                        .frame(width: 92, height: 92)
                        .overlay(Circle().stroke(Theme.accent.opacity(0.2), lineWidth: 1))
                    Circle().fill(Theme.accentGradient).frame(width: 66, height: 66)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Color(hex: 0x3A1D00))
                }

                VStack(spacing: 8) {
                    Text("Keyboard Locked")
                        .font(.system(size: 27, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Wipe away — every key is disabled.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textSecondary)
                }

                VStack(spacing: 13) {
                    if let remaining = tool.remainingText {
                        HStack(spacing: 9) {
                            Image(systemName: "timer").font(.system(size: 18))
                            Text(remaining).font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(Theme.accentLight)
                        .padding(.vertical, 10).padding(.horizontal, 16)
                        .background(Capsule().fill(Theme.card))
                        .overlay(Capsule().stroke(Theme.fieldStroke, lineWidth: 1))
                    }
                    HStack(spacing: 6) {
                        Text("\(tool.liveBlockedCount)").font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(hex: 0xE5E5EA))
                        Text("keystrokes blocked").font(.system(size: 13)).foregroundStyle(Theme.textMuted)
                    }
                }

                VStack(spacing: 14) {
                    Button {
                        tool.unlock()
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: "lock.open.fill").font(.system(size: 18))
                            Text("Hold to Unlock").font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 340, height: 52)
                        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.white.opacity(0.06)))
                        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Theme.fieldStroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 1.0).onEnded { _ in tool.unlock() }
                    )

                    if tool.unlockMethod == .escTriple {
                        HStack(spacing: 7) {
                            Text("or press").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                            Text("esc")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color(hex: 0xC7C7CE))
                                .padding(.vertical, 3).padding(.horizontal, 8)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
                            Text("three times").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
            }
            .padding(40)
            .frame(width: 420)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.bg.opacity(0.9)))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 40, y: 30)
        }
    }
}
