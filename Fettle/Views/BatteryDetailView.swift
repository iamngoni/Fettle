import SwiftUI

struct BatteryGlyph: View {
    var level: Double          // 0…1
    var color: Color
    var body: some View {
        HStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 2)
                .frame(width: 64, height: 30)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(color)
                        .padding(3)
                        .frame(width: max(8, 64 * level))
                }
            RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.2)).frame(width: 3, height: 12)
        }
    }
}

struct BatteryDetailView: View {
    @Bindable var tool: BatteryTool
    @Environment(AppState.self) private var app

    private let green = Color(hex: 0x32D74B)

    private var limitBinding: Binding<Float> {
        Binding(get: { Float((tool.chargeLimit - 50) / 50) },
                set: { tool.chargeLimit = (50 + Double($0) * 50).rounded() })
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Battery Limit",
                        pill: tool.limitEnabled ? ("On", green) : ("Off", Theme.textTertiary)) {
                app.route = .dashboard
            }
            VStack(spacing: 14) {
                hero
                SectionLabel(text: "CHARGE LIMIT")
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        VolumeSlider(value: limitBinding, tint: green)
                        Text("\(Int(tool.chargeLimit))%").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.textPrimary)
                            .frame(width: 44, alignment: .trailing)
                    }
                    HStack {
                        Text("50%").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                        Spacer()
                        Text("100%").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).fill(Theme.card))

                HStack(spacing: 8) {
                    ForEach([60, 80, 90, 100], id: \.self) { preset in
                        Chip(label: "\(preset)%",
                             isSelected: Int(tool.chargeLimit) == preset,
                             tint: green) { tool.chargeLimit = Double(preset) }
                    }
                }

                Card {
                    SettingRow(title: "Limit charging") {
                        FSwitch(isOn: $tool.limitEnabled, tint: green)
                    }
                    Hairline()
                    SettingRow(title: "Top up to 100% before unplug") {
                        FSwitch(isOn: $tool.topUpBeforeUnplug, tint: green)
                    }
                }

                helperNote
            }
            .padding(16)
            .onAppear { tool.refresh() }
        }
    }

    @ViewBuilder
    private var helperNote: some View {
        if tool.helperInstalled {
            note(icon: "checkmark.seal.fill", tint: green,
                 text: "Charge-limit helper installed and active.", action: nil)
        } else if tool.helperNeedsApproval {
            note(icon: "exclamationmark.triangle.fill", tint: Theme.accent,
                 text: "Approve “FettleBatteryHelper” in Login Items to enable charge limiting.",
                 action: { tool.openHelperApproval() })
        } else {
            note(icon: "info.circle", tint: Theme.textTertiary,
                 text: "Charge limiting installs a one-time background helper (asks for admin).",
                 action: { tool.installHelper() })
        }
    }

    private func note(icon: String, tint: Color, text: String, action: (() -> Void)?) -> some View {
        let content = HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(tint)
            Text(text).font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if action != nil {
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.025)))
        .contentShape(Rectangle())
        return Group {
            if let action {
                Button(action: action) { content }.buttonStyle(.plain)
            } else {
                content
            }
        }
    }

    private var hero: some View {
        HStack(spacing: 14) {
            BatteryGlyph(level: Double(tool.currentLevel) / 100, color: green)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(tool.currentLevel)%").font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.textPrimary)
                    if tool.isCharging { Image(systemName: "bolt.fill").font(.system(size: 13)).foregroundStyle(green) }
                }
                Text(tool.limitEnabled ? "Charging paused — holding at limit" : (tool.isCharging ? "Charging" : "On battery"))
                    .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).fill(Theme.card))
    }
}
