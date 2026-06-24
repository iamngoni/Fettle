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
                    appTriggerRow
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
                    Hairline()
                    SettingRow(title: "Closed-display (clamshell) mode",
                               subtitle: "Stay awake with the lid shut — no external display needed") {
                        FSwitch(isOn: $tool.clamshellMode)
                    }
                }
                if tool.clamshellMode { clamshellNote }
            }
            .padding(16)
        }
    }

    private var appTriggerRow: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .frame(width: 28, height: 28)
                .overlay(Image(systemName: "macwindow")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tool.triggerWhileAppRunning ? Theme.accentLight : Theme.textSecondary))
            Button { tool.chooseTriggerApp() } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text("An app is running").font(.system(size: 13, weight: .medium)).foregroundStyle(Color(hex: 0xE5E5EA))
                    Text(tool.hasTriggerApp ? tool.triggerAppName : "Choose an app…")
                        .font(.system(size: 11.5))
                        .foregroundStyle(tool.triggerWhileAppRunning && tool.hasTriggerApp ? Theme.accentLight : Theme.textMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 8)
            FSwitch(isOn: $tool.triggerWhileAppRunning)
                .disabled(!tool.hasTriggerApp)
                .opacity(tool.hasTriggerApp ? 1 : 0.4)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private var clamshellNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 13)).foregroundStyle(Theme.accent)
            Text(tool.helperInstalled
                 ? "Requires power. Disables sleep system-wide while on; the Mac may run warm with the lid closed. Reverts when you unplug."
                 : "Needs the one-time background helper (asks for admin) to control system sleep.")
                .font(.system(size: 11)).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accent.opacity(0.08)))
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
