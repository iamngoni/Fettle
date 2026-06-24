import SwiftUI

struct ShortcutsView: View {
    @Bindable var tool: ShortcutsTool
    @Environment(AppState.self) private var app

    private let indigo = Color(hex: 0x5E5CE6)

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Shortcuts", pill: nil) { app.route = .dashboard }
            Group {
                VStack(spacing: 10) {
                    hint
                    VStack(spacing: 7) {
                        SectionLabel(text: "GLOBAL SHORTCUTS")
                        Card {
                            ForEach(Array(ShortcutsTool.actions.enumerated()), id: \.element.id) { index, action in
                                if index > 0 { Hairline() }
                                row(action)
                            }
                        }
                    }
                    note
                }
                .padding(16)
            }
        }
        .onDisappear { tool.stopRecording() }
    }

    private var hint: some View {
        HStack(spacing: 8) {
            Image(systemName: "keyboard").font(.system(size: 13)).foregroundStyle(indigo)
            Text("Tap a shortcut to record new keys. Bindings work system-wide.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 11).frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(indigo.opacity(0.1)))
    }

    private func row(_ action: ShortcutAction) -> some View {
        let binding = tool.binding(for: action.id)
        let isRecording = tool.recordingAction == action.id
        return HStack(spacing: 10) {
            IconTile(symbol: action.symbol, tint: action.tint)
            Text(action.title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 8)
            Button {
                isRecording ? tool.stopRecording() : tool.startRecording(action.id)
            } label: {
                Text(isRecording ? "Press keys…" : binding.display)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isRecording ? indigo : Color(hex: 0xC7C7CE))
                    .padding(.vertical, 4).padding(.horizontal, 9)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .fill(isRecording ? indigo.opacity(0.18) : Color.white.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(isRecording ? indigo : .clear, lineWidth: 1))
            }.buttonStyle(.plain)
            Toggle("", isOn: Binding(get: { binding.enabled }, set: { tool.toggle(action.id, $0) }))
                .labelsHidden().toggleStyle(.switch).tint(action.tint).scaleEffect(0.8)
        }
        .padding(.horizontal, 13).padding(.vertical, 9)
    }

    private var note: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle").font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
            Text("If a combination is already taken by another app, recording it may not register.")
                .font(.system(size: 11)).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.025)))
    }
}
