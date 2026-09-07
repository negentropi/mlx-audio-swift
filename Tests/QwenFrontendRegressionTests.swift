import Foundation
import Testing
import MLX
@testable import MLXAudioCore
@testable import MLXAudioSTT

struct QwenFrontendRegressionTests {
    @Test func undersizedFollowUpWaitsForACompleteFrame() {
        let frontend = IncrementalMelSpectrogram()
        let first = (0..<200).map { Float(sin(Double($0) * 0.2)) }
        #expect(frontend.process(samples: first) != nil)
        // The saved overlap plus this sample totals 241, less than the 400-point FFT.
        #expect(frontend.process(samples: [0]) == nil)
        #expect(frontend.flush() != nil)
        #expect(frontend.flush() == nil)
    }

    @Test func subsequentPacketBoundariesPreserveInteriorFrames() {
        let samples: [Float] = (0..<32_000).map { index in
            let t = Double(index) / 16_000
            return Float(0.2 * cos(2 * .pi * 400 * t) + 0.1 * cos(2 * .pi * 1200 * t))
        }
        let batch = computeMelSpectrogram(audio: MLXArray(samples), sampleRate: 16_000,
            nFft: 400, hopLength: 160, nMels: 128, melScale: .slaney, hannPeriodic: true)
        let frontend = IncrementalMelSpectrogram()
        let packetSizes = [1280, 13, 147, 1279, 161, 64]
        var chunks: [MLXArray] = []
        var offset = 0
        var packet = 0
        while offset < samples.count {
            let end = min(samples.count, offset + packetSizes[packet % packetSizes.count])
            if let frames = frontend.process(samples: Array(samples[offset..<end])) {
                chunks.append(frames)
            }
            offset = end
            packet += 1
        }
        if let frames = frontend.flush() { chunks.append(frames) }
        let incremental = concatenated(chunks, axis: 0)
        let end = min(batch.dim(0), incremental.dim(0)) - 2
        #expect(batch.dim(0) == incremental.dim(0))
        #expect(MLX.abs(batch[2..<end] - incremental[2..<end]).max().item(Float.self) < 0.0001)
    }

    @Test func partialEncoderChunksExcludePadding() {
        let frameCounts = Array(1...800)
        let actual = getFeatExtractOutputLengths(MLXArray(frameCounts.map(Int32.init)))
        let tokenCounts = actual.asArray(Int32.self)
        for (index, frames) in frameCounts.enumerated() {
            // Each 100-frame chunk passes three stride-two convolutions independently.
            let completeChunks = frames / 100
            let remainingFrames = frames % 100
            let expected = completeChunks * 13 + (remainingFrames + 7) / 8
            #expect(tokenCounts[index] == Int32(expected), "Incorrect token count for \(frames) frames")
        }
        #expect(actual.dtype == .int32)
    }

    @Test func incrementalMelMatchesBatchInteriorFrames() {
        let samples: [Float] = (0..<32_000).map { index in
            let t = Double(index) / 16_000
            return Float(0.2 * sin(2 * .pi * 440 * t) + 0.1 * sin(2 * .pi * 1733 * t))
        }
        let batch = computeMelSpectrogram(audio: MLXArray(samples), sampleRate: 16_000,
            nFft: 400, hopLength: 160, nMels: 128, melScale: .slaney, hannPeriodic: true)
        let frontend = IncrementalMelSpectrogram()
        guard let incremental = frontend.process(samples: samples) else {
            Issue.record("Incremental frontend returned no frames")
            return
        }
        // Compare trained features independently of final-frame padding conventions.
        let end = min(batch.dim(0), incremental.dim(0)) - 2
        let difference = MLX.abs(batch[2..<end] - incremental[2..<end]).max().item(Float.self)
        #expect(difference < 0.0001)
    }
}
