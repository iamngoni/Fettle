import SwiftUI

struct CaptureTextDetailView: View {
    @Bindable var tool: CaptureTextTool
    @Environment(AppState.self) private var app

    private let green = Color(hex: 0x32D74B)

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Capture Text", pill: nil) { app.route = .dashboard }
            Group {
                VStack(spacing: 10) {
                    captureButton
                    if tool.needsScreenAccess && !tool.screenAuthorized { screenAccessBanner }
                    if !tool.recents.isEmpty { recentsSection }
                    optionsSection
                    note
                }
                .padding(16)
            }
        }
    }

    private var captureButton: some View {
        Button { app.route = .dashboard; tool.triggerCapture() } label: {
            HStack(spacing: 10) {
                Image(systemName: "viewfinder").font(.system(size: 18, weight: .bold))
                Text("Capture Text").font(.system(size: 14, weight: .bold))
                Spacer()
                Text("⇧⌘2").font(.system(size: 11.5, weight: .bold))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x0B2415).opacity(0.15)))
            }
            .foregroundStyle(Color(hex: 0x0B2415))
            .padding(.horizontal, 16).frame(height: 48)
            .background(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).fill(green))
        }
        .buttonStyle(.plain)
    }

    private var screenAccessBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 13)).foregroundStyle(Theme.accent)
                Text("Screen Recording needed").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            }
            Text("Enable Fettle under Privacy → Screen & System Audio Recording, then relaunch so it takes effect.")
                .font(.system(size: 11)).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button { tool.openScreenSettings() } label: {
                    Text("Open Settings").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                        .padding(.vertical, 7).padding(.horizontal, 12)
                        .background(RoundedRectangle(cornerRadius: 8).fill(green))
                }.buttonStyle(.plain)
                Button { tool.relaunch() } label: {
                    Text("Relaunch").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                        .padding(.vertical, 7).padding(.horizontal, 12)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.card))
                }.buttonStyle(.plain)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accent.opacity(0.1)))
    }

    private var recentsSection: some View {
        VStack(spacing: 7) {
            HStack {
                SectionLabel(text: "RECENT")
                Spacer()
                Button("Clear") { tool.clearRecents() }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .buttonStyle(.plain)
            }
            Card {
                ForEach(Array(tool.recents.enumerated()), id: \.offset) { index, text in
                    if index > 0 { Hairline() }
                    Button { tool.copyRecent(text) } label: {
                        HStack(spacing: 10) {
                            Text(text)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Color(hex: 0xC7C7CE))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Image(systemName: "doc.on.doc").font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var optionsSection: some View {
        VStack(spacing: 7) {
            SectionLabel(text: "OPTIONS")
            Card {
                SettingRow(title: "Keep line breaks") { FSwitch(isOn: $tool.keepLineBreaks, tint: green) }
                Hairline()
                SettingRow(title: "Auto-copy to clipboard") { FSwitch(isOn: $tool.autoCopy, tint: green) }
                Hairline()
                SettingRow(title: "Detect QR & barcodes") { FSwitch(isOn: $tool.detectBarcodes, tint: green) }
                Hairline()
                SettingRow(title: "Play sound on capture") { FSwitch(isOn: $tool.soundFeedback, tint: green) }
            }
        }
    }

    private var note: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield").font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
            Text("Recognition runs fully on-device — nothing leaves your Mac.")
                .font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.025)))
    }
}
