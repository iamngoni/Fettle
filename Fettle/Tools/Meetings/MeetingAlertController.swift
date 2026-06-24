import SwiftUI
import AppKit

/// Presents a borderless full-screen meeting alert (one window on the main
/// screen) that takes over the display so a meeting can't be missed.
@MainActor
final class MeetingAlertController {
    private weak var tool: MeetingsTool?
    private var window: NSWindow?

    init(tool: MeetingsTool) { self.tool = tool }

    func present(meeting: MeetingEvent) {
        guard let tool else { return }
        dismiss()
        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let win = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .screenSaver
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        win.hasShadow = false
        win.contentView = NSHostingView(rootView: MeetingAlertView(tool: tool, meeting: meeting))
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = win
    }

    func dismiss() {
        window?.orderOut(nil)
        window = nil
    }
}

struct MeetingAlertView: View {
    @Bindable var tool: MeetingsTool
    let meeting: MeetingEvent

    private let accent = Color(hex: 0x0A84FF)

    var body: some View {
        ZStack {
            Color(hex: 0x0A0A0C).opacity(0.96).ignoresSafeArea()
            RadialGradient(colors: [accent.opacity(0.28), .clear],
                           center: .init(x: 0.5, y: 0.32), startRadius: 30, endRadius: 700)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(accent.opacity(0.14)).frame(width: 96, height: 96)
                        .overlay(Circle().stroke(accent, lineWidth: 2))
                    Image(systemName: "video.fill").font(.system(size: 40)).foregroundStyle(Color(hex: 0x7DA8FF))
                }
                Text("MEETING STARTING")
                    .font(.system(size: 14, weight: .bold)).tracking(3)
                    .foregroundStyle(Color(hex: 0x7DA8FF))
                    .padding(.top, 24).padding(.bottom, 10)
                Text(meeting.title)
                    .font(.system(size: 52, weight: .bold)).foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    Text(meeting.timeRange).font(.system(size: 19)).foregroundStyle(Color(hex: 0xAEB9C8))
                    Circle().fill(Color(hex: 0x5A6373)).frame(width: 4, height: 4)
                    Text(meeting.sourceName).font(.system(size: 19)).foregroundStyle(Color(hex: 0xAEB9C8))
                    Circle().fill(Color(hex: 0x5A6373)).frame(width: 4, height: 4)
                    Text(meeting.startsInText).font(.system(size: 19, weight: .semibold)).foregroundStyle(Color(hex: 0x7DA8FF))
                }
                .padding(.top, 14)

                HStack(spacing: 14) {
                    Button { tool.join(meeting) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "video.fill").font(.system(size: 20))
                            Text("Join now").font(.system(size: 17, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.vertical, 15).padding(.horizontal, 30)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(accent))
                    }
                    .buttonStyle(.plain)
                    .disabled(meeting.url == nil)
                    .opacity(meeting.url == nil ? 0.4 : 1)

                    Button { tool.snooze(meeting) } label: {
                        HStack(spacing: 9) {
                            Image(systemName: "clock.arrow.circlepath").font(.system(size: 19))
                            Text("Snooze 1 min").font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(Color(hex: 0xD6DEEA))
                        .padding(.vertical, 15).padding(.horizontal, 24)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)

                    Button { tool.dismissAlert() } label: {
                        Text("Dismiss").font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x9AA4B2))
                            .padding(.vertical, 15).padding(.horizontal, 24)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.04)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 40)
            }
            .frame(width: 760)
        }
    }
}
