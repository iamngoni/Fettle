import Foundation
import CoreAudio
import AudioToolbox
import AVFoundation
import OSLog

private let recLog = Logger(subsystem: "com.fettle.app", category: "MeetingRecorder")

/// Captures meeting audio without touching Screen Recording. System audio
/// (everyone else) is taken with a global Core Audio process tap left `.unmuted`
/// so playback is unaffected; the microphone (you) is captured with
/// `AVAudioEngine`. The two are written to separate files so the transcriber can
/// label speakers. Only needs the "System Audio Recording" + Microphone consents.
final class MeetingRecorder: NSObject, @unchecked Sendable {

    struct Output {
        var systemURL: URL?
        var micURL: URL?
        var duration: TimeInterval
    }

    // System tap
    private var tapID: AudioObjectID = 0
    private var aggregateID: AudioObjectID = 0
    private var ioProcID: AudioDeviceIOProcID?
    private var systemFile: AVAudioFile?
    private var tapFormat = AudioStreamBasicDescription()
    private var tapAVFormat: AVAudioFormat?
    private var sysCallbacks = 0
    private var sysFramesTotal = 0
    private let ioQueue = DispatchQueue(label: "com.fettle.notes.io", qos: .userInitiated)

    // Mic
    private let engine = AVAudioEngine()
    private var micFile: AVAudioFile?

    private var startedAt: Date?

    private let systemURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("fettle-meeting-system-\(UUID().uuidString).caf")
    private let micURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("fettle-meeting-mic-\(UUID().uuidString).caf")

    func start() throws {
        try startMic()
        try startSystemTap()      // if this throws, mic is still torn down by caller via stop()
        startedAt = Date()
    }

    func stop() async -> Output {
        let duration = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        // Mic
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        // System tap — stop the IOProc, then flush any in-flight callback on the
        // io queue before releasing the file it writes to (avoids a use-after-free).
        if let proc = ioProcID, aggregateID != 0 {
            AudioDeviceStop(aggregateID, proc)
            AudioDeviceDestroyIOProcID(aggregateID, proc)
        }
        ioProcID = nil
        ioQueue.sync { }
        if aggregateID != 0 { AudioHardwareDestroyAggregateDevice(aggregateID); aggregateID = 0 }
        if tapID != 0 { AudioHardwareDestroyProcessTap(tapID); tapID = 0 }
        micFile = nil
        systemFile = nil

        let sysSize = (try? FileManager.default.attributesOfItem(atPath: systemURL.path)[.size] as? Int) ?? nil
        let micSize = (try? FileManager.default.attributesOfItem(atPath: micURL.path)[.size] as? Int) ?? nil
        FettleLog.log("Recorder stop: dur=\(Int(duration))s systemBytes=\(sysSize ?? -1) micBytes=\(micSize ?? -1) sysCallbacks=\(sysCallbacks) sysFrames=\(sysFramesTotal) tapRate=\(Int(tapFormat.mSampleRate)) tapCh=\(tapFormat.mChannelsPerFrame)")

        return Output(
            systemURL: FileManager.default.fileExists(atPath: systemURL.path) ? systemURL : nil,
            micURL: FileManager.default.fileExists(atPath: micURL.path) ? micURL : nil,
            duration: duration)
    }

    // MARK: Microphone

    private func startMic() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let file = try AVAudioFile(forWriting: micURL, settings: format.settings)
        micFile = file
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            try? self?.micFile?.write(from: buffer)
        }
        engine.prepare()
        try engine.start()
    }

    // MARK: System audio (global Core Audio tap)

    private func startSystemTap() throws {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = "Fettle Notes"
        description.isPrivate = true
        description.muteBehavior = .unmuted        // keep the meeting audible

        var tap = AudioObjectID(0)
        guard AudioHardwareCreateProcessTap(description, &tap) == noErr else {
            throw NSError(domain: "Fettle", code: 10, userInfo: [NSLocalizedDescriptionKey: "Couldn’t create the system-audio tap. Enable Fettle under System Audio Recording."])
        }
        tapID = tap

        // Learn the tap's stream format so we can create a matching file.
        var fmtSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var fmtAddr = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(tapID, &fmtAddr, 0, nil, &fmtSize, &tapFormat)
        var fileFormatDescription = tapFormat
        guard let format = AVAudioFormat(streamDescription: &fileFormatDescription) else {
            throw NSError(domain: "Fettle", code: 14, userInfo: [NSLocalizedDescriptionKey: "Couldn’t read the system-audio format."])
        }
        tapAVFormat = format
        systemFile = try AVAudioFile(
            forWriting: systemURL,
            settings: [
                AVFormatIDKey: tapFormat.mFormatID,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channelCount,
            ],
            commonFormat: .pcmFormatFloat32,
            interleaved: format.isInterleaved)

        let tapUID = description.uuid.uuidString
        var dict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Fettle Notes Capture",
            kAudioAggregateDeviceUIDKey: "com.fettle.notes.\(tapUID)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: tapUID,
                kAudioSubTapDriftCompensationKey: true,
            ]],
            kAudioAggregateDeviceTapAutoStartKey: true,
        ]
        // Anchor the aggregate to the real output device so it has a clock to
        // drive the IOProc — without this the tap-only aggregate delivers no audio.
        if let outputUID = Self.defaultOutputDeviceUID() {
            dict[kAudioAggregateDeviceMainSubDeviceKey] = outputUID
            dict[kAudioAggregateDeviceSubDeviceListKey] = [[kAudioSubDeviceUIDKey: outputUID]]
        }
        var aggregate = AudioObjectID(0)
        guard AudioHardwareCreateAggregateDevice(dict as CFDictionary, &aggregate) == noErr else {
            throw NSError(domain: "Fettle", code: 11, userInfo: [NSLocalizedDescriptionKey: "Couldn’t create the capture device."])
        }
        aggregateID = aggregate

        let status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregate, ioQueue) { [weak self] _, inInputData, _, _, _ in
            self?.writeSystem(inInputData)
        }
        guard status == noErr, let proc = ioProcID else {
            throw NSError(domain: "Fettle", code: 12, userInfo: [NSLocalizedDescriptionKey: "Couldn’t start capture."])
        }
        guard AudioDeviceStart(aggregate, proc) == noErr else {
            throw NSError(domain: "Fettle", code: 13, userInfo: [NSLocalizedDescriptionKey: "Couldn’t start capture device."])
        }
    }

    deinit {
        if let proc = ioProcID, aggregateID != 0 {
            AudioDeviceStop(aggregateID, proc)
            AudioDeviceDestroyIOProcID(aggregateID, proc)
        }
        if aggregateID != 0 { AudioHardwareDestroyAggregateDevice(aggregateID) }
        if tapID != 0 { AudioHardwareDestroyProcessTap(tapID) }
        engine.stop()
    }

    /// UID of the current default output device, used to anchor the capture aggregate.
    private static func defaultOutputDeviceUID() -> String? {
        var deviceID = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID) == noErr,
              deviceID != 0 else { return nil }

        var uid: CFString = "" as CFString
        var uidSize = UInt32(MemoryLayout<CFString>.size)
        var uidAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(deviceID, &uidAddr, 0, nil, &uidSize, &uid) == noErr else { return nil }
        return uid as String
    }

    private func writeSystem(_ inInputData: UnsafePointer<AudioBufferList>) {
        sysCallbacks += 1
        guard let systemFile, let format = tapAVFormat,
              let pcm = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: inInputData, deallocator: nil),
              pcm.frameLength > 0
        else { return }
        sysFramesTotal += Int(pcm.frameLength)
        do {
            try systemFile.write(from: pcm)
        } catch {
            recLog.error("System audio write failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
