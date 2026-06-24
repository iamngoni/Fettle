import SwiftUI
import AppKit

struct RootView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        content
            .background(Theme.bg)
            .foregroundStyle(Theme.textPrimary)
            .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var content: some View {
        switch app.route {
        case .dashboard:
            DashboardView()
        case .settings:
            SettingsView()
        case .tool(let id):
            switch id {
            case .keepAwake:    KeepAwakeDetailView(tool: app.keepAwake)
            case .cleanMode:    CleanModeDetailView(tool: app.cleanMode)
            case .micMute:      MicMuteDetailView(tool: app.micMute)
            case .audioMixer:   AudioMixerView(tool: app.audioMixer)
            case .presentation: PresentationDetailView(tool: app.presentation)
            case .battery:      BatteryDetailView(tool: app.battery)
            case .captureText:  CaptureTextDetailView(tool: app.captureText)
            case .devices:      DevicesDetailView(tool: app.devices)
            case .meetings:     MeetingsDetailView(tool: app.meetings)
            case .smartNotes:   SmartNotesDetailView(tool: app.smartNotes)
            case .calculator:   CalculatorView(tool: app.calculator)
            case .convert:      ConvertView(tool: app.convert)
            case .compress:     CompressView(tool: app.compress)
            case .windowSnap:   WindowSnapView(tool: app.windowSnap)
            case .shortcuts:    ShortcutsView(tool: app.shortcuts)
            case .measure:      MeasureView(tool: app.measure)
            case .notch:        NotchDetailView(tool: app.notch)
            case .hideDesktop:  DashboardView()
            }
        }
    }
}

struct FooterBar: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack {
                FooterButton(symbol: "gearshape", label: "Settings") {
                    app.route = .settings
                }
                Spacer()
                FooterButton(symbol: "power", label: "Quit") {
                    NSApp.terminate(nil)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
    }
}

private struct FooterButton: View {
    var symbol: String
    var label: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 14))
                Text(label).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 9).padding(.vertical, 7)
        }
        .buttonStyle(.plain)
    }
}
