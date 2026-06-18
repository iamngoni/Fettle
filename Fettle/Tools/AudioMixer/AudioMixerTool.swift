import SwiftUI
import AppKit
import CoreAudio

/// One app currently producing audio. `id` is its Core Audio process object.
struct AppAudioStream: Identifiable {
    let id: AudioObjectID
    var name: String
    var icon: NSImage?
    var tint: Color
    var volume: Float
    var muted: Bool
}

@MainActor
@Observable
final class AudioMixerTool: FettleTool {
    let kind: ToolID = .audioMixer
    let title = "Audio Mixer"
    let symbol = "slider.vertical.3"
    let tint = Color(hex: 0xBF5AF2)
    let section: ToolSection = .inputAudio

    var masterVolume: Float = 0.5
    private(set) var streams: [AppAudioStream] = []

    /// Real per-app volume via Core Audio process taps (macOS 14.4+).
    let perAppEngineAvailable = true

    private var taps: [AudioObjectID: ProcessTap] = [:]
    private var monitorTimer: Timer?
    private static let palette: [Color] = [
        Color(hex: 0x1DB954), Color(hex: 0x1E90FF), Color(hex: 0x2D8CFF),
        Color(hex: 0xBF5AF2), Color(hex: 0xFF8A00), Color(hex: 0xFF453A),
    ]

    var isActive: Bool { false }
    var statusText: String {
        streams.isEmpty ? "Output \(Int((masterVolume * 100).rounded()))%"
                        : "\(streams.count) app\(streams.count == 1 ? "" : "s") playing"
    }
    var statusTint: Color { Theme.textMuted }
    var control: ToolControl { .navigate }
    var hasDetail: Bool { true }

    var outputDeviceName: String {
        AudioSystem.deviceName(AudioSystem.defaultDevice(input: false))
    }

    init() { masterVolume = AudioSystem.volume(of: AudioSystem.defaultDevice(input: false)) }

    func setMasterVolume(_ value: Float) {
        masterVolume = value
        AudioSystem.setVolume(value, on: AudioSystem.defaultDevice(input: false))
    }

    // MARK: Monitoring

    func startMonitoring() {
        refresh()
        guard monitorTimer == nil else { return }
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    func refresh() {
        masterVolume = AudioSystem.volume(of: AudioSystem.defaultDevice(input: false))
        let playing = AudioProcessMonitor.playingProcesses()
        let liveIDs = Set(playing.map(\.id))

        // Drop taps for apps that stopped playing.
        for (id, tap) in taps where !liveIDs.contains(id) {
            tap.invalidate()
            taps[id] = nil
        }

        // Merge, preserving any volume/mute the user already set.
        var updated: [AppAudioStream] = []
        for (index, process) in playing.enumerated() {
            if let existing = streams.first(where: { $0.id == process.id }) {
                updated.append(AppAudioStream(id: process.id, name: process.name, icon: process.icon,
                                              tint: existing.tint, volume: existing.volume, muted: existing.muted))
            } else {
                updated.append(AppAudioStream(id: process.id, name: process.name, icon: process.icon,
                                              tint: Self.palette[index % Self.palette.count], volume: 1, muted: false))
            }
        }
        streams = updated
    }

    // MARK: Per-app control

    func setVolume(_ value: Float, for id: AudioObjectID) {
        guard let i = streams.firstIndex(where: { $0.id == id }) else { return }
        streams[i].volume = value
        applyTap(for: streams[i])
    }

    func toggleMute(_ id: AudioObjectID) {
        guard let i = streams.firstIndex(where: { $0.id == id }) else { return }
        streams[i].muted.toggle()
        applyTap(for: streams[i])
    }

    /// Lazily create/destroy a tap: only attenuated apps need one.
    private func applyTap(for stream: AppAudioStream) {
        let effectiveGain: Float = stream.muted ? 0 : stream.volume
        if effectiveGain >= 0.999 {
            taps[stream.id]?.invalidate()
            taps[stream.id] = nil
            return
        }
        if let tap = taps[stream.id] {
            tap.setGain(effectiveGain)
        } else {
            let tap = ProcessTap(processObject: stream.id, gain: effectiveGain)
            if tap.activate() { taps[stream.id] = tap }
        }
    }
}
