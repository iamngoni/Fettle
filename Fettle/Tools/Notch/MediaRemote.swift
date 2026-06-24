import Foundation
import AppKit

/// Live "Now Playing" from the system, via the private MediaRemote framework
/// (the same source Control Center uses). Works with any app that reports media
/// — Apple Music, Spotify, YouTube Music in a browser, etc.
@MainActor
@Observable
final class NowPlayingModel {

    struct Track: Equatable {
        var title: String
        var artist: String
        var album: String
        var duration: Double
        var elapsed: Double
        var isPlaying: Bool
        var asOf: Date

        /// Extrapolated elapsed time so the progress bar moves smoothly between
        /// MediaRemote updates.
        func liveElapsed(at now: Date) -> Double {
            let base = isPlaying ? elapsed + now.timeIntervalSince(asOf) : elapsed
            return max(0, min(base, duration))
        }
    }

    private(set) var track: Track?
    private(set) var artwork: NSImage?

    // MARK: Private framework bridge

    private typealias GetInfoFn = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    private typealias RegisterFn = @convention(c) (DispatchQueue) -> Void
    private typealias SendCmdFn = @convention(c) (Int, CFDictionary?) -> Bool

    @ObservationIgnored private var handle: UnsafeMutableRawPointer?
    @ObservationIgnored private var fnGetInfo: GetInfoFn?
    @ObservationIgnored private var fnRegister: RegisterFn?
    @ObservationIgnored private var fnSend: SendCmdFn?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var started = false

    // MRMediaRemoteCommand values.
    private enum Command: Int { case togglePlayPause = 2, nextTrack = 4, previousTrack = 5 }

    func start() {
        guard !started else { return }
        guard let h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY) else {
            FettleLog.error("MediaRemote: dlopen failed")
            return
        }
        handle = h
        if let s = dlsym(h, "MRMediaRemoteGetNowPlayingInfo") { fnGetInfo = unsafeBitCast(s, to: GetInfoFn.self) }
        if let s = dlsym(h, "MRMediaRemoteRegisterForNowPlayingNotifications") { fnRegister = unsafeBitCast(s, to: RegisterFn.self) }
        if let s = dlsym(h, "MRMediaRemoteSendCommand") { fnSend = unsafeBitCast(s, to: SendCmdFn.self) }
        guard fnGetInfo != nil else { FettleLog.error("MediaRemote: symbols unavailable"); return }
        started = true

        fnRegister?(.main)
        for name in ["kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                     "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"] {
            let o = NotificationCenter.default.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.fetch() }
            }
            observers.append(o)
        }
        fetch()
    }

    func stop() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        track = nil
        artwork = nil
        started = false
    }

    func togglePlayPause() { send(.togglePlayPause) }
    func next() { send(.nextTrack) }
    func previous() { send(.previousTrack) }

    private func send(_ command: Command) {
        _ = fnSend?(command.rawValue, nil)
        // MediaRemote posts a change notification shortly after; nudge a refetch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            MainActor.assumeIsolated { self?.fetch() }
        }
    }

    private func fetch() {
        fnGetInfo?(.main) { [weak self] info in
            MainActor.assumeIsolated {
                guard let self else { return }
                let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
                let artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
                guard !(title.isEmpty && artist.isEmpty) else {
                    self.track = nil; self.artwork = nil; return
                }
                let rate = (info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double) ?? 0
                self.track = Track(
                    title: title,
                    artist: artist,
                    album: info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? "",
                    duration: (info["kMRMediaRemoteNowPlayingInfoDuration"] as? Double) ?? 0,
                    elapsed: (info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double) ?? 0,
                    isPlaying: rate > 0,
                    asOf: Date())
                if let data = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data {
                    self.artwork = NSImage(data: data)
                } else {
                    self.artwork = nil
                }
            }
        }
    }
}
