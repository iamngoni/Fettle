import SwiftUI

struct CompressView: View {
    @Bindable var tool: CompressTool
    @Environment(AppState.self) private var app

    private let green = Color(hex: 0x30D158)

    private var qualityBinding: Binding<Float> {
        Binding(get: { Float(tool.quality) }, set: { tool.quality = Double($0) })
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Compress", pill: nil) { app.route = .dashboard }
            Group {
                VStack(spacing: 10) {
                    chooseButton
                    if !tool.results.isEmpty { savedHero; filesList }
                    settings
                    note
                }
                .padding(16)
            }
        }
    }

    private var chooseButton: some View {
        Button { tool.pickAndCompress() } label: {
            HStack(spacing: 10) {
                if tool.isWorking { ProgressView().controlSize(.small) }
                else { Image(systemName: "photo.badge.arrow.down").font(.system(size: 16, weight: .semibold)) }
                Text(tool.isWorking ? "Compressing…" : "Choose images").font(.system(size: 13.5, weight: .bold))
            }
            .foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 11).fill(green))
        }.buttonStyle(.plain).disabled(tool.isWorking)
    }

    private var savedHero: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(green.opacity(0.15)).frame(width: 40, height: 40)
                Image(systemName: "arrow.down").font(.system(size: 18, weight: .bold)).foregroundStyle(green)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Saved \(MediaConverter.humanSize(tool.totalSaved))")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.textPrimary)
                Text("\(tool.averageSaved)% smaller across \(tool.results.filter { !$0.failed }.count) images")
                    .font(.system(size: 11.5)).foregroundStyle(Color(hex: 0x9ED9AC))
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).fill(green.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(green.opacity(0.2), lineWidth: 1))
    }

    private var filesList: some View {
        VStack(spacing: 7) {
            SectionLabel(text: "FILES")
            Card {
                ForEach(Array(tool.results.enumerated()), id: \.element.id) { index, r in
                    if index > 0 { Hairline() }
                    HStack(spacing: 10) {
                        Image(systemName: r.failed ? "xmark.circle.fill" : "photo")
                            .font(.system(size: 14)).foregroundStyle(r.failed ? Theme.red : Theme.textSecondary)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.name).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                            Text(r.failed ? "Couldn’t compress"
                                 : "\(MediaConverter.humanSize(r.before))  →  \(MediaConverter.humanSize(r.after))")
                                .font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                        }
                        Spacer(minLength: 8)
                        if !r.failed {
                            Text("-\(r.savedPercent)%")
                                .font(.system(size: 11, weight: .bold)).foregroundStyle(Color(hex: 0x7DE08F))
                                .padding(.vertical, 3).padding(.horizontal, 7)
                                .background(RoundedRectangle(cornerRadius: 6).fill(green.opacity(0.15)))
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                }
            }
        }
    }

    private var settings: some View {
        VStack(spacing: 7) {
            SectionLabel(text: "SETTINGS")
            Card {
                VStack(spacing: 9) {
                    HStack {
                        Text("Quality").font(.system(size: 13, weight: .medium)).foregroundStyle(Color(hex: 0xE5E5EA))
                        Spacer()
                        Text("\(Int(tool.quality * 100))%").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.textPrimary)
                    }
                    VolumeSlider(value: qualityBinding, tint: green)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                Hairline()
                SettingRow(title: "Resize large images") { FSwitch(isOn: $tool.resizeEnabled, tint: green) }
                if tool.resizeEnabled {
                    Hairline()
                    HStack {
                        Text("Max dimension").font(.system(size: 13, weight: .medium)).foregroundStyle(Color(hex: 0xE5E5EA))
                        Spacer()
                        Text("\(Int(tool.maxDimension)) px").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
                        Stepper("", value: $tool.maxDimension, in: 512...8192, step: 256).labelsHidden().scaleEffect(0.8)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                }
                Hairline()
                SettingRow(title: "Strip metadata") { FSwitch(isOn: $tool.stripMetadata, tint: green) }
                Hairline()
                SettingRow(title: "Replace originals") { FSwitch(isOn: $tool.replaceOriginals, tint: green) }
            }
        }
    }

    private var note: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield").font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
            Text("On-device. Quality affects JPEG/HEIC; PNGs shrink via resize. Saved beside originals unless you enable replace.")
                .font(.system(size: 11)).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.025)))
    }
}
