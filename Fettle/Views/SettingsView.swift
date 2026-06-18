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
}
