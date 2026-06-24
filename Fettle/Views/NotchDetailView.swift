import SwiftUI

struct NotchDetailView: View {
    @Bindable var tool: NotchTool
    @Environment(AppState.self) private var app

    private let purple = Color(hex: 0xBF5AF2)
    private let green = Color(hex: 0x32D74B)

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Notch",
                        pill: tool.enabled ? ("On", green) : ("Off", Theme.textTertiary)) {
                app.route = .dashboard
            }
            Group {
                VStack(spacing: 10) {
                    Card {
                        SettingRow(title: "Enable notch panel",
                                   subtitle: "Hover the notch to expand it") {
                            FSwitch(isOn: $tool.enabled, tint: green)
                        }
                    }
                    VStack(spacing: 7) {
                        SectionLabel(text: "WIDGETS")
                        Card {
                            SettingRow(title: "Now Playing", subtitle: "Media info & controls") {
                                FSwitch(isOn: $tool.showNowPlaying, tint: green)
                            }
                            Hairline()
                            SettingRow(title: "Drag & drop shelf") { FSwitch(isOn: $tool.showShelf, tint: green) }
                            Hairline()
                            SettingRow(title: "Clock & battery") { FSwitch(isOn: $tool.showClock, tint: green) }
                        }
                    }
                    note
                }
                .padding(16)
            }
        }
    }

    private var note: some View {
        HStack(spacing: 8) {
            Image(systemName: "macbook").font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
            Text("Adds a hover panel under the notch with a file shelf and clock/battery. Drop files in, drag them back out.")
                .font(.system(size: 11)).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.025)))
    }
}
