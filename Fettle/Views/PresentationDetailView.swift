import SwiftUI

struct PresentationDetailView: View {
    @Bindable var tool: PresentationTool
    @Environment(AppState.self) private var app

    private let yellow = Color(hex: 0xFFD60A)
    private var yellowGradient: LinearGradient {
        LinearGradient(colors: [Color(hex: 0xFFE066), Color(hex: 0xFFD60A)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Presentation Mode",
                        pill: tool.isActive ? ("On", yellow) : ("Off", Theme.textTertiary)) {
                app.route = .dashboard
            }
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    IconTile(symbol: "videoprojector.fill", tint: yellow, size: 40, glyph: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Focus for talks").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                        Text("One switch silences distractions while you present or share your screen.")
                            .font(.system(size: 12)).foregroundStyle(Theme.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).fill(Theme.card))

                SectionLabel(text: "WHEN ON, FETTLE WILL")
                Card {
                    includeRow("sun.max.fill", "Keep the display awake", $tool.includeKeepAwake)
                    Hairline()
                    includeRow("moon.fill", "Turn on Do Not Disturb", $tool.includeDoNotDisturb)
                    Hairline()
                    includeRow("eye.slash.fill", "Hide desktop icons", $tool.includeHideDesktop)
                    Hairline()
                    includeRow("mic.slash.fill", "Mute the microphone", $tool.includeMuteMic)
                }

                if tool.includeDoNotDisturb && !tool.dndShortcutsInstalled {
                    Button { ShortcutsRunner.openShortcutsApp() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 13)).foregroundStyle(yellow)
                            Text("Do Not Disturb needs two Shortcuts named “Fettle Focus On” and “Fettle Focus Off”. Tap to open Shortcuts.")
                                .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(yellow.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }

                PrimaryButton(title: tool.isActive ? "Stop Presentation Mode" : "Start Presentation Mode",
                              symbol: tool.isActive ? "stop.fill" : "play.fill",
                              gradient: yellowGradient,
                              fg: Color(hex: 0x3D3100)) {
                    tool.toggle()
                }
            }
            .padding(16)
        }
    }

    private func includeRow(_ symbol: String, _ label: String, _ binding: Binding<Bool>) -> some View {
        SettingRow(title: label, symbol: symbol, symbolOn: binding.wrappedValue) {
            FSwitch(isOn: binding, tint: yellow)
        }
    }
}
