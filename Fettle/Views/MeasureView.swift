import SwiftUI

struct MeasureView: View {
    @Bindable var tool: MeasureTool
    @Environment(AppState.self) private var app

    private let pink = Color(hex: 0xFF375F)

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Measure", pill: nil) { app.route = .dashboard }
            Group {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        actionButton("Measure size", "ruler", filled: true) { app.route = .dashboard; tool.measureSize() }
                        actionButton("Pick color", "eyedropper.halffull", filled: false) { tool.pickColor() }
                    }
                    if !tool.recents.isEmpty { recents }
                    options
                    note
                }
                .padding(16)
            }
        }
    }

    private func actionButton(_ title: String, _ symbol: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
                Text(title).font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundStyle(filled ? .white : pink)
            .frame(maxWidth: .infinity).frame(height: 64)
            .background(RoundedRectangle(cornerRadius: 12).fill(filled ? pink : pink.opacity(0.14)))
        }.buttonStyle(.plain)
    }

    private var recents: some View {
        VStack(spacing: 7) {
            HStack {
                SectionLabel(text: "RECENT")
                Spacer()
                Button("Clear") { tool.clear() }
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textTertiary).buttonStyle(.plain)
            }
            Card {
                ForEach(Array(tool.recents.enumerated()), id: \.element.id) { index, r in
                    if index > 0 { Hairline() }
                    Button { tool.copyRecent(r) } label: {
                        HStack(spacing: 11) {
                            if let c = r.color {
                                RoundedRectangle(cornerRadius: 7).fill(c).frame(width: 28, height: 28)
                                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.15), lineWidth: 1))
                            } else {
                                IconTile(symbol: r.symbol, tint: pink)
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(r.value).font(.system(size: 12.5, weight: .medium, design: .monospaced)).foregroundStyle(Theme.textPrimary)
                                Text(r.kind).font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "doc.on.doc").font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
                        }
                        .padding(.horizontal, 13).padding(.vertical, 10).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var options: some View {
        VStack(spacing: 7) {
            SectionLabel(text: "OPTIONS")
            Card {
                SettingRow(title: "Color as HEX (off = RGB)") { FSwitch(isOn: $tool.colorAsHex, tint: pink) }
            }
        }
    }

    private var note: some View {
        HStack(spacing: 8) {
            Image(systemName: "ruler").font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
            Text("Measures anything on screen. Color picker uses the system loupe.")
                .font(.system(size: 11)).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.025)))
    }
}
