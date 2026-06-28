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
    private var dischargeBinding: Binding<Float> {
        Binding(get: { Float((tool.dischargeTarget - 20) / 70) },          // 20…90
                set: { tool.dischargeTarget = (20 + Double($0) * 70).rounded() })
    }
    private var heatBinding: Binding<Float> {
        Binding(get: { Float((tool.heatLimit - 30) / 15) },                // 30…45 °C
                set: { tool.heatLimit = (30 + Double($0) * 15).rounded() })
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Battery",
                        pill: tool.isActive ? ("On", green) : ("Off", Theme.textTertiary)) {
                app.route = .dashboard
            }
            Group {
                VStack(spacing: 10) {
                    hero
                    chargeLimitSection
                    Card {
                        SettingRow(title: "Limit charging") {
                            FSwitch(isOn: $tool.limitEnabled, tint: green)
                        }
                    }
                    powerSection
                    if let health = tool.health { healthSection(health) }
                    helperNote
                }
                .padding(16)
            }
            .onAppear { tool.refresh() }
        }
    }

    private var chargeLimitSection: some View {
        VStack(spacing: 10) {
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
        }
    }

    private var powerSection: some View {
        VStack(spacing: 10) {
            SectionLabel(text: "POWER")
            Card {
                SettingRow(title: "Discharge when plugged in",
                           subtitle: "Run on battery until it falls to the target") {
                    FSwitch(isOn: $tool.dischargeEnabled, tint: green)
                }
                if tool.dischargeEnabled {
                    Hairline()
                    sliderRow(label: "Discharge to", value: "\(Int(tool.dischargeTarget))%", binding: dischargeBinding)
                }
                Hairline()
                SettingRow(title: "Heat protection",
                           subtitle: "Pause charging when the battery gets hot") {
                    FSwitch(isOn: $tool.heatProtect, tint: green)
                }
                if tool.heatProtect {
                    Hairline()
                    sliderRow(label: "Pause above", value: "\(Int(tool.heatLimit))°C", binding: heatBinding)
                }
            }
            if tool.dischargeEnabled || tool.heatProtect {
                note(icon: "exclamationmark.triangle.fill", tint: Theme.accent,
                     text: "Forcing discharge or pausing on heat needs power and the background helper.",
                     action: nil)
            }
        }
    }

    private func sliderRow(label: String, value: String, binding: Binding<Float>) -> some View {
        VStack(spacing: 9) {
            HStack {
                Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(Color(hex: 0xE5E5EA))
                Spacer()
                Text(value).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.textPrimary)
            }
            VolumeSlider(value: binding, tint: green)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    private func healthSection(_ h: BatteryHealth) -> some View {
        VStack(spacing: 10) {
            SectionLabel(text: "BATTERY HEALTH")
            HStack(spacing: 8) {
                healthCell(value: "\(h.maxCapacityPercent)%", label: "Capacity")
                healthCell(value: "\(h.cycleCount)", label: "Cycles")
                healthCell(value: h.tempC > 0 ? String(format: "%.0f°C", h.tempC) : "—", label: "Temp")
            }
        }
    }

    private func healthCell(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.textPrimary)
            Text(label).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).fill(Theme.card))
    }

    @ViewBuilder
    private var helperNote: some View {
        if tool.helperInstalled {
            note(icon: "checkmark.seal.fill", tint: green,
                 text: "Charge-control helper installed and active.", action: nil)
        } else if tool.helperNeedsApproval {
            note(icon: "exclamationmark.triangle.fill", tint: Theme.accent,
                 text: "Approve “FettleBatteryHelper” in Login Items to enable charge control.",
                 action: { tool.openHelperApproval() })
        } else {
            note(icon: "info.circle", tint: Theme.textTertiary,
                 text: "Charge control installs a one-time background helper (asks for admin).",
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
                Text(heroStatus)
                    .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).fill(Theme.card))
    }

    private var heroStatus: String {
        if tool.dischargeEnabled { return "Running on battery to reach \(Int(tool.dischargeTarget))%" }
        if tool.limitEnabled { return "Charging paused — holding at limit" }
        return tool.isCharging ? "Charging" : "On battery"
    }
}
