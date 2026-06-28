import SwiftUI
import UniformTypeIdentifiers

struct CompressView: View {
    @Bindable var tool: CompressTool
    @Environment(AppState.self) private var app
    @State private var dropTargeted = false

    private let green = Color(hex: 0x30D158)

    private var qualityBinding: Binding<Float> {
        Binding(get: { Float(tool.quality) }, set: { tool.quality = Double($0) })
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Compress", pill: nil) { app.route = .dashboard }
            Group {
                VStack(spacing: 10) {
                    dropzone
                    if !tool.picked.isEmpty { selectedList }
                    if tool.isWorking { progressView } else if !tool.picked.isEmpty { compressButton }
                    if !tool.results.isEmpty { savedHero; resultsList }
                    settings
                    videoSection
                    note
                }
                .padding(16)
            }
        }
    }

    private var dropzone: some View {
        VStack(spacing: 7) {
            Image(systemName: "photo.badge.arrow.down").font(.system(size: 22)).foregroundStyle(green)
            Text("Drop images or videos").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(hex: 0xE5E5EA))
            Text("or click to choose").font(.system(size: 11)).foregroundStyle(Theme.textMuted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 20)
        .background(RoundedRectangle(cornerRadius: 12).fill(green.opacity(0.08)))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                .foregroundStyle(green.opacity(dropTargeted ? 0.7 : 0.3)))
        .contentShape(Rectangle())
        .onTapGesture { tool.pickFiles() }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url { DispatchQueue.main.async { tool.addFiles([url]) } }
                }
            }
            return true
        }
    }

    private var selectedList: some View {
        VStack(spacing: 7) {
            HStack {
                SectionLabel(text: "SELECTED · \(tool.picked.count)")
                Spacer()
                Button("Clear") { tool.clearPicked() }
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textTertiary).buttonStyle(.plain)
            }
            Card {
                ForEach(Array(tool.picked.enumerated()), id: \.element.id) { index, file in
                    if index > 0 { Hairline() }
                    HStack(spacing: 10) {
                        Image(systemName: file.isVideo ? "film" : "photo")
                            .font(.system(size: 14)).foregroundStyle(Theme.textSecondary).frame(width: 20)
                        Text(file.name).font(.system(size: 12.5)).foregroundStyle(Color(hex: 0xD7D7DC)).lineLimit(1)
                        Spacer(minLength: 8)
                        Button { tool.removePicked(file) } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 13)).foregroundStyle(Color(hex: 0x6E6E78))
                        }.buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                }
            }
        }
    }

    private var compressButton: some View {
        Button { tool.startCompression() } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.right.and.arrow.up.left").font(.system(size: 15, weight: .semibold))
                Text("Compress \(tool.picked.count) file\(tool.picked.count == 1 ? "" : "s")").font(.system(size: 13.5, weight: .bold))
            }
            .foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 11).fill(green))
        }.buttonStyle(.plain)
    }

    private var progressView: some View {
        VStack(spacing: 8) {
            HStack {
                Text(tool.currentName.isEmpty ? "Preparing…" : tool.currentName)
                    .font(.system(size: 12)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                Spacer(minLength: 8)
                Text("\(Int(tool.overallProgress * 100))%").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.textPrimary)
            }
            ProgressView(value: tool.overallProgress).tint(green)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).fill(Theme.card))
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
                Text("\(tool.averageSaved)% smaller across \(tool.results.filter { !$0.failed }.count) files")
                    .font(.system(size: 11.5)).foregroundStyle(Color(hex: 0x9ED9AC))
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).fill(green.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(green.opacity(0.2), lineWidth: 1))
    }

    private var resultsList: some View {
        VStack(spacing: 7) {
            SectionLabel(text: "RESULTS")
            Card {
                ForEach(Array(tool.results.enumerated()), id: \.element.id) { index, r in
                    if index > 0 { Hairline() }
                    HStack(spacing: 10) {
                        Image(systemName: r.failed ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .font(.system(size: 14)).foregroundStyle(r.failed ? Theme.red : green).frame(width: 20)
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
            SectionLabel(text: "IMAGE SETTINGS")
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

    private var videoSection: some View {
        VStack(spacing: 7) {
            SectionLabel(text: "VIDEO QUALITY")
            Card {
                ForEach(Array(MediaConverter.VideoQuality.allCases.enumerated()), id: \.element) { i, q in
                    if i > 0 { Hairline() }
                    Button { tool.videoQuality = q } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(q.rawValue).font(.system(size: 13, weight: .medium)).foregroundStyle(Color(hex: 0xE5E5EA))
                                Text(q.subtitle).font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                            }
                            Spacer(minLength: 8)
                            if tool.videoQuality == q {
                                Image(systemName: "checkmark.circle.fill").font(.system(size: 16)).foregroundStyle(green)
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
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
