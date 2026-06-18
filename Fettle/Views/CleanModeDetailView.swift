import SwiftUI

struct CleanModeDetailView: View {
    @Bindable var tool: CleanModeTool
    @Environment(AppState.self) private var app

    var body: some View {
        if tool.needsPermission {
            CleanModePermissionView(tool: tool)
        } else {
            controls
        }
    }

    private var rows: [[CleanModeTool.AutoUnlock]] {
        [[.s30, .m1, .m3], [.m5, .m10, .manual]]
    }

    private var controls: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Clean Mode",
                        pill: tool.isActive ? ("Locked", Theme.accent) : nil) {
                app.route = .dashboard
            }
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    IconTile(symbol: "keyboard", tint: tool.tint, size: 40, glyph: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lock for cleaning").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                        Text("Disables every key so you can wipe the keyboard safely.")
                            .font(.system(size: 12)).foregroundStyle(Theme.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).fill(Theme.card))

                SectionLabel(text: "AUTO-UNLOCK AFTER")
                VStack(spacing: 8) {
                    ForEach(rows.indices, id: \.self) { r in
                        HStack(spacing: 8) {
                            ForEach(rows[r]) { option in
                                Chip(label: option.label,
                                     isSelected: tool.autoUnlock == option,
                                     tint: tool.tint) { tool.autoUnlock = option }
                            }
                        }
                    }
                }

                SectionLabel(text: "UNLOCK WITH")
                Card {
                    ForEach(Array(CleanModeTool.UnlockMethod.allCases.enumerated()), id: \.element.id) { index, method in
                        if index > 0 { Hairline() }
                        Button { tool.unlockMethod = method } label: {
                            HStack {
                                Text(method.label).font(.system(size: 13, weight: .medium)).foregroundStyle(Color(hex: 0xE5E5EA))
                                Spacer()
                                RadioDot(selected: tool.unlockMethod == method, tint: tool.tint)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                PrimaryButton(title: "Lock Keyboard", symbol: "lock.fill") { tool.lock() }

                HStack(spacing: 6) {
                    Image(systemName: "cursorarrow").font(.system(size: 12))
                    Text("Mouse & trackpad stay active").font(.system(size: 11))
                }
                .foregroundStyle(Theme.textTertiary)
            }
            .padding(16)
        }
    }
}

struct RadioDot: View {
    var selected: Bool
    var tint: Color
    var body: some View {
        Circle()
            .stroke(selected ? tint : Color.white.opacity(0.2), lineWidth: selected ? 5 : 1.5)
            .frame(width: 18, height: 18)
    }
}

struct CleanModePermissionView: View {
    @Bindable var tool: CleanModeTool
    @Environment(AppState.self) private var app

    private let steps = [
        ("1", "Open System Settings → Privacy & Security"),
        ("2", "Select Accessibility"),
        ("3", "Turn on Fettle"),
    ]

    var body: some View {
        VStack(spacing: 18) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.accent.opacity(0.08))
                .frame(width: 72, height: 72)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.accent.opacity(0.2), lineWidth: 1))
                .overlay(Image(systemName: "checkmark.shield.fill").font(.system(size: 32)).foregroundStyle(Theme.accentLight))

            VStack(spacing: 8) {
                Text("Allow Accessibility Access").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.textPrimary)
                Text("Fettle needs Accessibility permission to intercept and block keystrokes while the keyboard is locked.")
                    .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Card {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    if index > 0 { Hairline() }
                    HStack(spacing: 11) {
                        Text(step.0).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.accentLight)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Theme.accent.opacity(0.14)))
                        Text(step.1).font(.system(size: 12, weight: .medium)).foregroundStyle(Color(hex: 0xE5E5EA))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 13).padding(.vertical, 11)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "lock.fill").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                Text("Keystrokes are never stored or sent anywhere.").font(.system(size: 11)).foregroundStyle(Theme.textMuted)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.025)))

            VStack(spacing: 9) {
                PrimaryButton(title: "Open System Settings", symbol: "gearshape") {
                    AccessibilityPermission.openSettings()
                }
                Button {
                    tool.needsPermission = false
                    app.route = .dashboard
                } label: {
                    Text("Maybe later").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textMuted)
                        .frame(maxWidth: .infinity, minHeight: 38)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 28)
    }
}
