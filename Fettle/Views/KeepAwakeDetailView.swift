import SwiftUI

struct KeepAwakeDetailView: View {
    @Bindable var tool: KeepAwakeTool
    @Environment(AppState.self) private var app

    private var rows: [[KeepAwakeTool.Duration]] {
        [[.m15, .m30, .h1], [.h2, .h5, .indefinite]]
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Keep Awake",
                        pill: tool.isActive ? ("Awake", Theme.green) : ("Off", Theme.textTertiary)) {
                app.route = .dashboard
            }
            VStack(spacing: 14) {
                primaryCard
                SectionLabel(text: "SESSION DURATION")
                VStack(spacing: 8) {
                    ForEach(rows.indices, id: \.self) { r in
                        HStack(spacing: 8) {
                            ForEach(rows[r]) { duration in
                                Chip(label: duration.label,
                                     isSelected: tool.selectedDuration == duration) {
                                    tool.selectedDuration = duration
                                    if tool.isActive { tool.start() }
                                }
                            }
                        }
                    }
                }
                SectionLabel(text: "KEEP AWAKE WHILE")
                Card {
                    SettingRow(title: "An app is running",
                               subtitle: tool.triggerAppName,
                               subtitleTint: tool.triggerWhileAppRunning ? Theme.accentLight : Theme.textMuted,
                               symbol: "macwindow", symbolOn: tool.triggerWhileAppRunning) {
                        FSwitch(isOn: $tool.triggerWhileAppRunning)
                    }
                    Hairline()
                    SettingRow(title: "Connected to power",
                               subtitle: "On charger only",
                               subtitleTint: tool.triggerWhileOnPower ? Theme.accentLight : Theme.textMuted,
                               symbol: "powerplug.fill", symbolOn: tool.triggerWhileOnPower) {
                        FSwitch(isOn: $tool.triggerWhileOnPower)
                    }
                }
                SectionLabel(text: "OPTIONS")
                Card {
                    SettingRow(title: "Keep display awake") { FSwitch(isOn: $tool.keepDisplayAwake) }
                    Hairline()
                    SettingRow(title: "Activate on launch") { FSwitch(isOn: $tool.activateOnLaunch) }
                }
            }
            .padding(16)
        }
    }

    private var primaryCard: some View {
        HStack(spacing: 12) {
            IconTile(symbol: "sun.max.fill", tint: Theme.accent, size: 36, glyph: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("Keep Awake").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Text(tool.statusText).font(.system(size: 12)).foregroundStyle(tool.isActive ? Theme.accentLight : Theme.textMuted)
            }
            Spacer(minLength: 8)
            FSwitch(isOn: Binding(get: { tool.isActive }, set: { tool.setActive($0) }))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .fill(tool.isActive ? Theme.accent.opacity(0.07) : Theme.card)
                .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .stroke(tool.isActive ? Theme.accent.opacity(0.2) : .clear, lineWidth: 1))
        )
    }
}
