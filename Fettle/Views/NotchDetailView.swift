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
                                   subtitle: "Hover the physical notch to expand it") {
                            FSwitch(isOn: $tool.enabled, tint: green)
                        }
                    }
                    VStack(spacing: 7) {
                        SectionLabel(text: "LAYOUT")
                        Card {
                            SettingRow(title: "Expanded items",
                                       subtitle: "Show at most \(tool.maxItems)") {
                                maxItemsControl
                            }
                        }
                    }
                    VStack(spacing: 7) {
                        SectionLabel(text: "WIDGETS")
                        Card {
                            SettingRow(title: "Now Playing", subtitle: "Media info & controls") {
                                FSwitch(isOn: $tool.showNowPlaying, tint: green)
                            }
                            Hairline()
                            SettingRow(title: "Devices", subtitle: "Mac and peripheral battery levels") {
                                FSwitch(isOn: $tool.showDevices, tint: green)
                            }
                            Hairline()
                            SettingRow(title: "Meetings", subtitle: "Next calendar event") {
                                FSwitch(isOn: $tool.showMeetings, tint: green)
                            }
                            Hairline()
                            SettingRow(title: "Quick actions", subtitle: "Mic, awake, notes, and capture") {
                                FSwitch(isOn: $tool.showQuickActions, tint: green)
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
            Text("Collapsed stays blank and notch-sized. Expanded view shows only the first enabled widgets up to the item limit.")
                .font(.system(size: 11)).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.025)))
    }

    private var maxItemsControl: some View {
        HStack(spacing: 3) {
            ForEach([1, 2, 3], id: \.self) { count in
                Button {
                    tool.maxItems = count
                } label: {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(tool.maxItems == count ? .black : Theme.textSecondary)
                        .frame(width: 26, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(tool.maxItems == count ? green : Color.white.opacity(0.07))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
