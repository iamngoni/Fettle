import SwiftUI

struct MicMuteDetailView: View {
    @Bindable var tool: MicMuteTool
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Mic Mute",
                        pill: tool.isMuted ? ("Muted", Theme.red) : ("Live", Theme.green)) {
                app.route = .dashboard
            }
            VStack(spacing: 14) {
                hero
                SectionLabel(text: "CONTROLS")
                Card {
                    SettingRow(title: "Toggle shortcut") {
                        KbdChip(text: "⌥ ⌘ M")
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(hex: 0x5A5A62))
                    }
                    Hairline()
                    SettingRow(title: "Push to talk", subtitle: "Hold the shortcut to unmute") {
                        FSwitch(isOn: $tool.pushToTalk, tint: Theme.accent)
                    }
                    Hairline()
                    SettingRow(title: "Play sound when toggled") {
                        FSwitch(isOn: $tool.playSoundOnToggle, tint: Theme.accent)
                    }
                    Hairline()
                    SettingRow(title: "Show level in menu bar") {
                        FSwitch(isOn: $tool.showLevelInMenuBar, tint: Theme.accent)
                    }
                }
                SectionLabel(text: "INPUT DEVICE")
                Card {
                    SettingRow(title: tool.inputDeviceName, subtitle: "Default input") {
                        DevicePicker(input: true)
                    }
                }
            }
            .padding(16)
        }
    }

    private var hero: some View {
        HStack(spacing: 12) {
            IconTile(symbol: "mic.slash.fill", tint: Theme.red, size: 40, glyph: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.isMuted ? "Microphone muted" : "Microphone live").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Text(tool.isMuted ? "No app can hear you" : "Apps can use your mic").font(.system(size: 12)).foregroundStyle(tool.isMuted ? Color(hex: 0xFF8E86) : Theme.textMuted)
            }
            Spacer(minLength: 8)
            FSwitch(isOn: Binding(get: { tool.isMuted }, set: { tool.setMuted($0) }), tint: Theme.red)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .fill(tool.isMuted ? Theme.red.opacity(0.08) : Theme.card)
                .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .stroke(tool.isMuted ? Theme.red.opacity(0.18) : .clear, lineWidth: 1))
        )
    }
}

struct KbdChip: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color(hex: 0xC7C7CE))
            .padding(.vertical, 4).padding(.horizontal, 9)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.fieldStroke, lineWidth: 1))
    }
}
