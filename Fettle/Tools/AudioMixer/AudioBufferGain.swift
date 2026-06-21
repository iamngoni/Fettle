import CoreAudio
import Foundation

enum AudioBufferGain {
    private static let sampleSize = MemoryLayout<Float32>.size

    static func apply(input: UnsafeMutableAudioBufferListPointer,
                      output: UnsafeMutableAudioBufferListPointer,
                      gain rawGain: Float) {
        guard input.count > 0, output.count > 0 else { return }
        let gain = max(0, min(1, rawGain))
        guard gain > 0 else { return }

        let inputInterleaved = isInterleaved(input)
        let outputInterleaved = isInterleaved(output)

        switch (inputInterleaved, outputInterleaved) {
        case (true, true):
            copyInterleavedToInterleaved(input: input[0], output: output[0], gain: gain)
        case (true, false):
            copyInterleavedToPlanar(input: input[0], output: output, gain: gain)
        case (false, true):
            copyPlanarToInterleaved(input: input, output: output[0], gain: gain)
        case (false, false):
            copyPlanarToPlanar(input: input, output: output, gain: gain)
        }
    }

    private static func isInterleaved(_ buffers: UnsafeMutableAudioBufferListPointer) -> Bool {
        buffers.count == 1 && buffers[0].mNumberChannels > 1
    }

    private static func frameCount(_ buffer: AudioBuffer, channels: Int) -> Int {
        guard buffer.mData != nil else { return 0 }
        return Int(buffer.mDataByteSize) / (sampleSize * max(1, channels))
    }

    private static func copyInterleavedToInterleaved(input: AudioBuffer,
                                                    output: AudioBuffer,
                                                    gain: Float) {
        guard let src = input.mData, let dst = output.mData else { return }
        let inputChannels = max(1, Int(input.mNumberChannels))
        let outputChannels = max(1, Int(output.mNumberChannels))
        let frames = min(frameCount(input, channels: inputChannels),
                         frameCount(output, channels: outputChannels))
        guard frames > 0 else { return }

        let source = src.assumingMemoryBound(to: Float32.self)
        let destination = dst.assumingMemoryBound(to: Float32.self)
        for frame in 0..<frames {
            for channel in 0..<outputChannels {
                let sourceChannel = inputChannels == 1 ? 0 : channel
                guard sourceChannel < inputChannels else { continue }
                destination[frame * outputChannels + channel] = source[frame * inputChannels + sourceChannel] * gain
            }
        }
    }

    private static func copyPlanarToInterleaved(input: UnsafeMutableAudioBufferListPointer,
                                                output: AudioBuffer,
                                                gain: Float) {
        guard let dst = output.mData else { return }
        let outputChannels = max(1, Int(output.mNumberChannels))
        let outputFrames = frameCount(output, channels: outputChannels)
        guard outputFrames > 0 else { return }

        let destination = dst.assumingMemoryBound(to: Float32.self)
        let channels = min(input.count, outputChannels)
        for channel in 0..<channels {
            guard let src = input[channel].mData else { continue }
            let inputChannels = max(1, Int(input[channel].mNumberChannels))
            let inputFrames = frameCount(input[channel], channels: inputChannels)
            let frames = min(outputFrames, inputFrames)
            let source = src.assumingMemoryBound(to: Float32.self)
            for frame in 0..<frames {
                destination[frame * outputChannels + channel] = source[frame * inputChannels] * gain
            }
        }
    }

    private static func copyInterleavedToPlanar(input: AudioBuffer,
                                                output: UnsafeMutableAudioBufferListPointer,
                                                gain: Float) {
        guard let src = input.mData else { return }
        let inputChannels = max(1, Int(input.mNumberChannels))
        let inputFrames = frameCount(input, channels: inputChannels)
        guard inputFrames > 0 else { return }

        let source = src.assumingMemoryBound(to: Float32.self)
        let channels = min(inputChannels, output.count)
        for channel in 0..<channels {
            guard let dst = output[channel].mData else { continue }
            let outputChannels = max(1, Int(output[channel].mNumberChannels))
            let outputFrames = frameCount(output[channel], channels: outputChannels)
            let frames = min(inputFrames, outputFrames)
            let destination = dst.assumingMemoryBound(to: Float32.self)
            for frame in 0..<frames {
                destination[frame * outputChannels] = source[frame * inputChannels + channel] * gain
            }
        }
    }

    private static func copyPlanarToPlanar(input: UnsafeMutableAudioBufferListPointer,
                                           output: UnsafeMutableAudioBufferListPointer,
                                           gain: Float) {
        let buffers = min(input.count, output.count)
        for index in 0..<buffers {
            guard let src = input[index].mData, let dst = output[index].mData else { continue }
            let byteCount = min(input[index].mDataByteSize, output[index].mDataByteSize)
            let samples = Int(byteCount) / sampleSize
            guard samples > 0 else { continue }

            let source = src.assumingMemoryBound(to: Float32.self)
            let destination = dst.assumingMemoryBound(to: Float32.self)
            for sample in 0..<samples {
                destination[sample] = source[sample] * gain
            }
        }
    }
}
