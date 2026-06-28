import SwiftUI
import AppKit

struct SettingsView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        return VStack(spacing: 0) {
            PanelHeader(title: "Settings", pill: nil) { app.route = .dashboard }
            VStack(spacing: 14) {
                SectionLabel(text: "GENERAL")
                Card {
                    SettingRow(title: "Launch Fettle at login") {
                        FSwitch(isOn: $app.launchAtLogin)
                    }
                    Hairline()
                    SettingRow(title: "Start Keep Awake on launch") {
                        FSwitch(isOn: Binding(get: { app.keepAwake.activateOnLaunch },
                                              set: { app.keepAwake.activateOnLaunch = $0 }))
                    }
                }

                SectionLabel(text: "LICENSE")
                licenseCard

                SectionLabel(text: "SHORTCUTS")
                Card {
                    SettingRow(title: "Toggle mute") { KbdChip(text: "⌥ ⌘ M") }
                }

                SectionLabel(text: "BATTERY HELPER")
                Card {
                    SettingRow(title: "Charge-limit helper",
                               subtitle: app.battery.helperInstalled ? "Installed"
                                       : (app.battery.helperNeedsApproval ? "Needs approval" : "Not installed"),
                               subtitleTint: app.battery.helperInstalled ? Theme.greenLight : Theme.textMuted) {
                        if app.battery.helperInstalled {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
                        } else {
                            Button(app.battery.helperNeedsApproval ? "Approve" : "Install") {
                                if app.battery.helperNeedsApproval { app.battery.openHelperApproval() }
                                else { app.battery.installHelper() }
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.accent)
                        }
                    }
                }

                SectionLabel(text: "ABOUT")
                Card {
                    SettingRow(title: "Fettle", subtitle: "Version \(appVersion)") {
                        EmptyView()
                    }
                    Hairline()
                    Button { NSApp.terminate(nil) } label: {
                        HStack {
                            Text("Quit Fettle").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.red)
                            Spacer()
                            Image(systemName: "power").font(.system(size: 13)).foregroundStyle(Theme.red)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private var licenseCard: some View {
        Card {
            SettingRow(title: "Fettle lifetime",
                       subtitle: "$3 once · one active Mac at a time",
                       subtitleTint: app.license.isActivated ? Theme.greenLight : Theme.textMuted) {
                if app.license.isActivated {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.green)
                } else {
                    Image(systemName: "key.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accentLight)
                }
            }
            Hairline()
            if app.license.isActivated {
                activatedLicenseRows
            } else {
                activationRows
            }
            Hairline()
            HStack(spacing: 8) {
                Image(systemName: app.license.isWorking ? "arrow.triangle.2.circlepath" : "info.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(app.license.statusColor)
                Text(app.license.statusMessage)
                    .font(.system(size: 11.5))
                    .foregroundStyle(app.license.statusColor)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
    }

    private var activationRows: some View {
        VStack(spacing: 9) {
            TextField("License key", text: Binding(
                get: { app.license.licenseKeyInput },
                set: { app.license.licenseKeyInput = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 12.5, weight: .medium, design: .monospaced))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.06)))

            Button {
                app.license.activate()
            } label: {
                HStack(spacing: 7) {
                    if app.license.isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "key.radiowaves.forward.fill")
                    }
                    Text("Activate")
                }
                .font(.system(size: 12.5, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 34)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(app.license.isWorking)
        }
        .padding(14)
    }

    private var activatedLicenseRows: some View {
        VStack(spacing: 0) {
            SettingRow(title: "License key",
                       subtitle: app.license.activationUsage ?? "Seat active",
                       subtitleTint: Theme.textMuted) {
                Text(app.license.displayKeyTail)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
            }
            Hairline()
            HStack(spacing: 8) {
                Button("Validate") { app.license.validate() }
                    .font(.system(size: 12, weight: .semibold))
                    .buttonStyle(.bordered)
                    .disabled(app.license.isWorking)
                Button("Release seat") { app.license.deactivate() }
                    .font(.system(size: 12, weight: .semibold))
                    .buttonStyle(.bordered)
                    .tint(Theme.red)
                    .disabled(app.license.isWorking)
                Spacer(minLength: 0)
                if app.license.isWorking { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }
}
