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
    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private var fallbackInFlight = false

    // MRMediaRemoteCommand values.
    private enum Command: Int { case togglePlayPause = 2, nextTrack = 4, previousTrack = 5 }
    private static let prefersFallbackMetadata: Bool = {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        if version.majorVersion > 15 { return true }
        return version.majorVersion == 15 && version.minorVersion >= 4
    }()

    func start() {
        guard !started else { return }
        started = true

        guard let h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY) else {
            FettleLog.error("MediaRemote: dlopen failed")
            fetchFallback()
            startPolling()
            return
        }
        handle = h
        if let s = dlsym(h, "MRMediaRemoteGetNowPlayingInfo") { fnGetInfo = unsafeBitCast(s, to: GetInfoFn.self) }
        if let s = dlsym(h, "MRMediaRemoteRegisterForNowPlayingNotifications") { fnRegister = unsafeBitCast(s, to: RegisterFn.self) }
        if let s = dlsym(h, "MRMediaRemoteSendCommand") { fnSend = unsafeBitCast(s, to: SendCmdFn.self) }
        if Self.prefersFallbackMetadata {
            fetchFallback()
            startPolling()
            return
        }
        guard fnGetInfo != nil else {
            FettleLog.error("MediaRemote: symbols unavailable")
            fetchFallback()
            startPolling()
            return
        }

        fnRegister?(.main)
        for name in ["kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                     "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"] {
            let o = NotificationCenter.default.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.fetch() }
            }
            observers.append(o)
        }
        fetch()
        startPolling()
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
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

    private func startPolling() {
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.fetch() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func fetch() {
        if Self.prefersFallbackMetadata {
            fetchFallback()
            return
        }
        guard let fnGetInfo else {
            fetchFallback()
            return
        }
        fnGetInfo(.main) { [weak self] info in
            MainActor.assumeIsolated {
                guard let self else { return }
                if !self.applyMediaRemoteInfo(info) { self.fetchFallback() }
            }
        }
    }

    @discardableResult
    private func applyMediaRemoteInfo(_ info: [String: Any]) -> Bool {
        let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
        let artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
        guard !(title.isEmpty && artist.isEmpty) else { return false }
        let rate = (info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double) ?? 0
        track = Track(
            title: title,
            artist: artist,
            album: info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? "",
            duration: (info["kMRMediaRemoteNowPlayingInfoDuration"] as? Double) ?? 0,
            elapsed: (info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double) ?? 0,
            isPlaying: rate > 0,
            asOf: Date())
        if let data = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data {
            artwork = NSImage(data: data)
        } else {
            artwork = nil
        }
        return true
    }

    private func fetchFallback() {
        guard !fallbackInFlight else { return }
        fallbackInFlight = true
        Task {
            let payload = await Task.detached(priority: .utility) {
                Self.runFallbackScript()
            }.value
            fallbackInFlight = false
            guard started else { return }
            applyFallbackPayload(payload)
        }
    }

    private func applyFallbackPayload(_ payload: String?) {
        guard let payload, !payload.isEmpty else {
            track = nil
            artwork = nil
            return
        }
        let fields = payload.components(separatedBy: "\u{1f}")
        guard fields.count >= 6 else { return }
        let title = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = fields[2].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !(title.isEmpty && artist.isEmpty) else {
            track = nil
            artwork = nil
            return
        }
        track = Track(
            title: title,
            artist: artist,
            album: fields[3].trimmingCharacters(in: .whitespacesAndNewlines),
            duration: Double(fields[4]) ?? 0,
            elapsed: Double(fields[5]) ?? 0,
            isPlaying: fields[0] == "Playing",
            asOf: Date())
        artwork = nil
    }

    nonisolated private static func runFallbackScript() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", fallbackScript]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static let fallbackScript = """
use scripting additions
use framework "/System/Library/PrivateFrameworks/MediaRemote.framework"
set MRNowPlayingRequest to current application's NSClassFromString("MRNowPlayingRequest")
if MRNowPlayingRequest's localNowPlayingItem() is missing value then return ""
set infoDict to MRNowPlayingRequest's localNowPlayingItem()'s nowPlayingInfo()
set playingText to "Paused"
if MRNowPlayingRequest's localIsPlaying() then set playingText to "Playing"
set titleText to (infoDict's valueForKey:"kMRMediaRemoteNowPlayingInfoTitle")
if titleText is missing value then set titleText to ""
set artistText to (infoDict's valueForKey:"kMRMediaRemoteNowPlayingInfoArtist")
if artistText is missing value then set artistText to ""
set albumText to (infoDict's valueForKey:"kMRMediaRemoteNowPlayingInfoAlbum")
if albumText is missing value then set albumText to ""
set durationText to (infoDict's valueForKey:"kMRMediaRemoteNowPlayingInfoDuration")
if durationText is missing value then set durationText to 0
set elapsedText to (infoDict's valueForKey:"kMRMediaRemoteNowPlayingInfoElapsedTime")
if elapsedText is missing value then set elapsedText to 0
set sep to ASCII character 31
return playingText & sep & (titleText as text) & sep & (artistText as text) & sep & (albumText as text) & sep & (durationText as text) & sep & (elapsedText as text)
"""
}
