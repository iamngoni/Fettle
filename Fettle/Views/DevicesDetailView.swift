import SwiftUI

struct DevicesDetailView: View {
    @Bindable var tool: DevicesTool
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Devices", pill: nil) { app.route = .dashboard }
            Group {
                VStack(spacing: 10) {
                    if let mac = tool.mac { macHero(mac) }
                    if tool.peripherals.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 7) {
                            SectionLabel(text: "BLUETOOTH DEVICES")
                            Card {
                                ForEach(Array(tool.peripherals.enumerated()), id: \.element.id) { index, dev in
                                    if index > 0 { Hairline() }
                                    deviceRow(dev)
                                }
                            }
                        }
                    }
                    note
                }
                .padding(16)
            }
            .onAppear { tool.refresh(); tool.startAutoRefresh() }
            .onDisappear { tool.stopAutoRefresh() }
        }
    }

    private func macHero(_ dev: BatteryDevice) -> some View {
        HStack(spacing: 11) {
            IconTile(symbol: dev.kind.symbol, tint: dev.kind.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(dev.name).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Text(dev.charging ? "Power Adapter · Charging" : "On battery")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Text("\(dev.percent)%").font(.system(size: 15, weight: .bold)).foregroundStyle(dev.levelColor)
                Image(systemName: dev.batterySymbol).font(.system(size: 15)).foregroundStyle(dev.levelColor)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).fill(Theme.card))
    }

    private func deviceRow(_ dev: BatteryDevice) -> some View {
        HStack(spacing: 11) {
            IconTile(symbol: dev.kind.symbol, tint: dev.kind.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(dev.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Text("Connected").font(.system(size: 11)).foregroundStyle(Theme.textMuted)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Text("\(dev.percent)%").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(dev.levelColor)
                Image(systemName: dev.batterySymbol).font(.system(size: 15)).foregroundStyle(dev.levelColor)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 20)).foregroundStyle(Theme.textTertiary)
            Text("No battery-reporting accessories connected")
                .font(.system(size: 12)).foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24)
        .background(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).fill(Theme.card))
    }

    private var note: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle").font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
            Text("Shows the Mac and Bluetooth accessories that report a battery level.")
                .font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.025)))
    }
}
