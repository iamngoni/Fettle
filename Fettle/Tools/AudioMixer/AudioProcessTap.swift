import CoreAudio
import AudioToolbox
import AppKit
import OSLog

private let log = Logger(subsystem: "com.fettle.app", category: "AudioTap")

// MARK: - Core Audio property helpers

enum CAProp {
    static func ids(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var ids = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    static func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                       scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32 {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
        return value
    }

    static func pid(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> pid_t {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
        return value
    }

    static func cfString(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
}

// MARK: - Process enumeration

struct AudioProcess: Identifiable {
    let id: AudioObjectID            // the process AudioObject
    let pid: pid_t
    let name: String
    let icon: NSImage?
}

enum AudioProcessMonitor {
    /// Processes that are currently producing output audio.
    static func playingProcesses() -> [AudioProcess] {
        let processes = CAProp.ids(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList)
        var result: [AudioProcess] = []
        for object in processes {
            let running = CAProp.uint32(object, kAudioProcessPropertyIsRunningOutput)
            guard running != 0 else { continue }
            let pid = CAProp.pid(object, kAudioProcessPropertyPID)
            guard pid > 0, let app = NSRunningApplication(processIdentifier: pid) else { continue }
            // Skip our own audio path.
            if pid == ProcessInfo.processInfo.processIdentifier { continue }
            let name = app.localizedName ?? CAProp.cfString(object, kAudioProcessPropertyBundleID) ?? "Audio"
            result.append(AudioProcess(id: object, pid: pid, name: name, icon: app.icon))
        }
        return result
    }
}

// MARK: - Per-process tap + aggregate-device gain stage

/// Taps a single process, mutes its normal output, and re-renders it through a
/// private aggregate device at an adjustable gain. Active only while a process
/// is being attenuated; at unity gain the tap is torn down so the app plays
/// normally with zero added latency.
final class ProcessTap: @unchecked Sendable {
    let processObject: AudioObjectID
    nonisolated(unsafe) private var gain: Float

    private var tapID: AudioObjectID = 0
    private var aggregateID: AudioObjectID = 0
    private var ioProcID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "com.fettle.tap.io", qos: .userInitiated)
    private(set) var isActive = false

    init(processObject: AudioObjectID, gain: Float) {
        self.processObject = processObject
        self.gain = gain
    }

    func setGain(_ value: Float) { gain = max(0, min(1, value)) }

    private func deviceUID(_ device: AudioObjectID) -> String? {
        CAProp.cfString(device, kAudioDevicePropertyDeviceUID)
    }

    @discardableResult
    func activate() -> Bool {
        guard !isActive else { return true }
        let outputDevice = AudioSystem.defaultDevice(input: false)
        guard let outputUID = deviceUID(outputDevice) else { return false }

        let description = CATapDescription(stereoMixdownOfProcesses: [processObject])
        description.name = "Fettle Tap"
        description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped

        var tap = AudioObjectID(0)
        guard AudioHardwareCreateProcessTap(description, &tap) == noErr else {
            log.error("AudioHardwareCreateProcessTap failed")
            return false
        }
        tapID = tap

        let tapUID = description.uuid.uuidString
        let aggregateUID = "com.fettle.aggregate.\(description.uuid.uuidString)"
        let dict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Fettle Mixer",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: tapUID,
            ]],
            kAudioAggregateDeviceTapAutoStartKey: true,
        ]

        var aggregate = AudioObjectID(0)
        guard AudioHardwareCreateAggregateDevice(dict as CFDictionary, &aggregate) == noErr else {
            log.error("AudioHardwareCreateAggregateDevice failed")
            teardown()
            return false
        }
        aggregateID = aggregate

        let status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregate, queue) { [weak self] _, inInputData, _, outOutputData, _ in
            guard let self else { return }
            let g = self.gain
            let input = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
            let output = UnsafeMutableAudioBufferListPointer(outOutputData)
            let buffers = min(input.count, output.count)
            for i in 0..<buffers {
                guard let src = input[i].mData, let dst = output[i].mData else { continue }
                let byteCount = min(input[i].mDataByteSize, output[i].mDataByteSize)
                let samples = Int(byteCount) / MemoryLayout<Float32>.size
                let sp = src.assumingMemoryBound(to: Float32.self)
                let dp = dst.assumingMemoryBound(to: Float32.self)
                for s in 0..<samples { dp[s] = sp[s] * g }
            }
        }
        guard status == noErr, let proc = ioProcID else {
            log.error("AudioDeviceCreateIOProcIDWithBlock failed: \(status)")
            teardown()
            return false
        }

        AudioDeviceStart(aggregate, proc)
        isActive = true
        return true
    }

    func invalidate() { teardown() }

    private func teardown() {
        if let proc = ioProcID {
            if aggregateID != 0 { AudioDeviceStop(aggregateID, proc); AudioDeviceDestroyIOProcID(aggregateID, proc) }
            ioProcID = nil
        }
        if aggregateID != 0 { AudioHardwareDestroyAggregateDevice(aggregateID); aggregateID = 0 }
        if tapID != 0 { AudioHardwareDestroyProcessTap(tapID); tapID = 0 }
        isActive = false
    }

    deinit { teardown() }
}
