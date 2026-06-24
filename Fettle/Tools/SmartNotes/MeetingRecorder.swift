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

        let tapUID = description.uuid.uuidString
        let dict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Fettle Notes Capture",
            kAudioAggregateDeviceUIDKey: "com.fettle.notes.\(tapUID)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: tapUID,
                kAudioSubTapDriftCompensationKey: true,
            ]],
            kAudioAggregateDeviceTapAutoStartKey: true,
        ]
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

    private func writeSystem(_ inInputData: UnsafePointer<AudioBufferList>) {
        let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
        guard let first = abl.first, first.mDataByteSize > 0, tapFormat.mBytesPerFrame > 0 else { return }

        if systemFile == nil {
            var fmt = tapFormat
            guard let format = AVAudioFormat(streamDescription: &fmt) else { return }
            systemFile = try? AVAudioFile(forWriting: systemURL, settings: format.settings)
        }
        guard let systemFile,
              let format = AVAudioFormat(streamDescription: &tapFormat) else { return }

        let frames = first.mDataByteSize / tapFormat.mBytesPerFrame
        guard frames > 0, let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        pcm.frameLength = frames
        let dst = UnsafeMutableAudioBufferListPointer(pcm.mutableAudioBufferList)
        for i in 0..<min(abl.count, dst.count) {
            let n = min(abl[i].mDataByteSize, dst[i].mDataByteSize)
            if let s = abl[i].mData, let d = dst[i].mData { memcpy(d, s, Int(n)) }
        }
        try? systemFile.write(from: pcm)
    }
}
