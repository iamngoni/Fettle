import SwiftUI

struct VolumeSlider: View {
    @Binding var value: Float
    var tint: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12)).frame(height: 6)
                Capsule().fill(tint).frame(width: max(6, CGFloat(value) * w), height: 6)
                Circle().fill(.white)
                    .frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.2), radius: 1)
                    .offset(x: min(max(0, CGFloat(value) * w - 7), w - 14))
            }
            .frame(height: 16)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { g in
                    value = Float(min(max(0, g.location.x / w), 1))
                }
            )
        }
        .frame(height: 16)
    }
}

struct AudioMixerView: View {
    @Bindable var tool: AudioMixerTool
    @Environment(AppState.self) private var app

    private var masterBinding: Binding<Float> {
        Binding(get: { tool.masterVolume }, set: { tool.setMasterVolume($0) })
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Audio Mixer", pill: nil) { app.route = .dashboard }
            VStack(spacing: 14) {
                master
                SectionLabel(text: "PLAYING NOW")
                if tool.streams.isEmpty {
                    emptyState
                } else {
                    Card {
                        ForEach(Array(tool.streams.enumerated()), id: \.element.id) { index, stream in
                            if index > 0 { Hairline() }
                            StreamRow(
                                stream: stream,
                                onVolume: { tool.setVolume($0, for: stream.id) },
                                onToggleMute: { tool.toggleMute(stream.id) }
                            )
                        }
                    }
                }
            }
            .padding(16)
            .onAppear { tool.startMonitoring() }
            .onDisappear { tool.stopMonitoring() }
        }
    }

    private var master: some View {
        VStack(spacing: 13) {
            HStack(spacing: 11) {
                IconTile(symbol: "speaker.wave.3.fill", tint: tool.tint, size: 32, glyph: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text("System Output").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Text(tool.outputDeviceName).font(.system(size: 11.5)).foregroundStyle(Theme.textMuted).lineLimit(1)
                }
                Spacer(minLength: 8)
                DevicePicker(input: false) { tool.refresh() }
            }
            HStack(spacing: 11) {
                VolumeSlider(value: masterBinding, tint: tool.tint)
                Text("\(Int((tool.masterVolume * 100).rounded()))")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(hex: 0xC7C7CE))
                    .frame(width: 26, alignment: .trailing)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).fill(Theme.card))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform").font(.system(size: 26)).foregroundStyle(Theme.textTertiary)
            Text("Nothing is playing").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textSecondary)
            Text("Apps appear here while they’re producing audio. Lower one below 100% and Fettle takes over its volume.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 22).padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).fill(Theme.card))
    }
}

struct StreamRow: View {
    var stream: AppAudioStream
    var onVolume: (Float) -> Void
    var onToggleMute: () -> Void

    private var sliderBinding: Binding<Float> {
        Binding(get: { stream.muted ? 0 : stream.volume }, set: { onVolume($0) })
    }

    var body: some View {
        HStack(spacing: 11) {
            appIcon
            VStack(spacing: 7) {
                HStack {
                    Text(stream.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Spacer()
                    Text(stream.muted ? "Muted" : "\(Int(stream.volume * 100))")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(stream.muted ? Theme.redLight : Color(hex: 0xC7C7CE))
                    Button(action: onToggleMute) {
                        Image(systemName: stream.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(stream.muted ? Theme.redLight : Theme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
                VolumeSlider(value: sliderBinding, tint: stream.tint)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
    }

    @ViewBuilder
    private var appIcon: some View {
        if let icon = stream.icon {
            Image(nsImage: icon)
                .resizable().interpolation(.high)
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        } else {
            IconTile(symbol: "app.fill", tint: stream.tint, size: 34, glyph: 18)
        }
    }
}
