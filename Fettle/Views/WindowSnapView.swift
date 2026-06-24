import SwiftUI

struct WindowSnapView: View {
    @Bindable var tool: WindowSnapTool
    @Environment(AppState.self) private var app

    private let accent = Color(hex: 0x0A84FF)
    private let green = Color(hex: 0x32D74B)

    private var gapBinding: Binding<Float> {
        Binding(get: { Float(tool.gap / 32) }, set: { tool.gap = (Double($0) * 32).rounded() })
    }

    private let presets: [(String, WindowManager.Zone, CGRect)] = [
        ("Left", .leftHalf, CGRect(x: 0, y: 0, width: 0.5, height: 1)),
        ("Right", .rightHalf, CGRect(x: 0.5, y: 0, width: 0.5, height: 1)),
        ("Top", .topHalf, CGRect(x: 0, y: 0, width: 1, height: 0.5)),
        ("Bottom", .bottomHalf, CGRect(x: 0, y: 0.5, width: 1, height: 0.5)),
        ("Maximize", .maximize, CGRect(x: 0, y: 0, width: 1, height: 1)),
        ("Center", .center, CGRect(x: 0.18, y: 0.16, width: 0.64, height: 0.68)),
        ("Quarter", .topLeft, CGRect(x: 0, y: 0, width: 0.5, height: 0.5)),
        ("Thirds", .leftThird, CGRect(x: 0, y: 0, width: 0.34, height: 1)),
    ]

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Window Snap",
                        pill: tool.enabled && tool.trusted ? ("On", green) : ("Off", Theme.textTertiary)) {
                app.route = .dashboard
            }
            Group {
                VStack(spacing: 10) {
                    if !tool.trusted { accessPrompt }
                    grid
                    behavior
                    shortcuts
                    note
                }
                .padding(16)
            }
        }
    }

    private var accessPrompt: some View {
        Button { tool.requestAccess() } label: {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield").font(.system(size: 14)).foregroundStyle(accent)
                Text("Grant Accessibility access to move windows").font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 11).frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10).fill(accent.opacity(0.1)))
        }.buttonStyle(.plain)
    }

    private var grid: some View {
        VStack(spacing: 12) {
            ForEach(0..<2) { row in
                HStack(spacing: 8) {
                    ForEach(0..<4) { col in
                        let p = presets[row * 4 + col]
                        Button { tool.apply(p.1) } label: {
                            VStack(spacing: 6) {
                                ZoneGlyph(zone: p.2, accent: accent)
                                Text(p.0).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Color(hex: 0xB8B8C0))
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 9).fill(Theme.card))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var behavior: some View {
        VStack(spacing: 7) {
            SectionLabel(text: "BEHAVIOR")
            Card {
                SettingRow(title: "Snap shortcuts enabled") { FSwitch(isOn: $tool.enabled, tint: green) }
                Hairline()
                VStack(spacing: 9) {
                    HStack {
                        Text("Window gaps").font(.system(size: 13, weight: .medium)).foregroundStyle(Color(hex: 0xE5E5EA))
                        Spacer()
                        Text("\(Int(tool.gap)) px").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.textPrimary)
                    }
                    VolumeSlider(value: gapBinding, tint: accent)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
            }
        }
    }

    private var shortcuts: some View {
        VStack(spacing: 7) {
            SectionLabel(text: "SHORTCUTS")
            Card {
                shortcutRow("Left half", "⌃⌥←")
                Hairline(); shortcutRow("Right half", "⌃⌥→")
                Hairline(); shortcutRow("Top / Bottom", "⌃⌥↑ ↓")
                Hairline(); shortcutRow("Maximize", "⌃⌥↩")
            }
        }
    }

    private func shortcutRow(_ title: String, _ key: String) -> some View {
        HStack {
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Color(hex: 0xE5E5EA))
            Spacer()
            Text(key).font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(Color(hex: 0xC7C7CE))
                .padding(.vertical, 3).padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    private var note: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.on.rectangle").font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
            Text("Tiles the frontmost app’s window by keyboard or by tapping a zone.")
                .font(.system(size: 11)).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.025)))
    }
}

struct ZoneGlyph: View {
    let zone: CGRect      // normalized, top-left origin
    let accent: Color
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            RoundedRectangle(cornerRadius: 3)
                .fill(accent)
                .frame(width: max(3, w * zone.width), height: max(3, h * zone.height))
                .offset(x: w * zone.minX, y: h * zone.minY)
        }
        .frame(width: 34, height: 24)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.18), lineWidth: 1))
    }
}
