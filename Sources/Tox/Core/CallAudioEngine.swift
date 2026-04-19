import Foundation
import AVFoundation

final class CallAudioEngine: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let queue = DispatchQueue(label: "smoothtox.audio.engine")

    private var frameHandler: (@Sendable (_ samples: [Int16], _ channels: UInt8, _ sampleRate: UInt32) -> Void)?
    private var isRunning = false
    private var isCapturing = false

    init() {
        engine.attach(player)
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func startCapture(_ onFrame: @escaping @Sendable (_ samples: [Int16], _ channels: UInt8, _ sampleRate: UInt32) -> Void) {
        queue.async {
            self.frameHandler = onFrame

            guard !self.isCapturing else { return }
            let input = self.engine.inputNode
            let inputFormat = input.inputFormat(forBus: 0)

            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 960, format: inputFormat) { [weak self] buffer, _ in
                guard let self else { return }
                self.handleInputBuffer(buffer, sampleRate: UInt32(inputFormat.sampleRate))
            }

            self.isCapturing = true
            self.ensureEngineRunning()
        }
    }

    func stopCapture() {
        queue.async {
            self.engine.inputNode.removeTap(onBus: 0)
            self.frameHandler = nil
            self.isCapturing = false
            self.stopEngineIfIdle()
        }
    }

    func playReceived(samples: [Int16], channels: UInt8, sampleRate: UInt32) {
        queue.async {
            guard !samples.isEmpty else { return }
            guard channels == 1 else { return }

            self.ensureEngineRunning()
            if !self.player.isPlaying {
                self.player.play()
            }

            guard let format = AVAudioFormat(
                standardFormatWithSampleRate: Double(sampleRate),
                channels: 1
            ),
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(samples.count)
            ) else {
                return
            }

            buffer.frameLength = AVAudioFrameCount(samples.count)
            if let channel = buffer.floatChannelData?[0] {
                for index in 0..<samples.count {
                    channel[index] = Float(samples[index]) / Float(Int16.max)
                }
            }

            self.player.scheduleBuffer(buffer, completionHandler: nil)
        }
    }

    private func handleInputBuffer(_ buffer: AVAudioPCMBuffer, sampleRate: UInt32) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let sampleCount = Int(buffer.frameLength)
        if sampleCount == 0 { return }

        var monoSamples = [Int16](repeating: 0, count: sampleCount)
        for index in 0..<sampleCount {
            let value = max(-1.0, min(1.0, channel[index]))
            monoSamples[index] = Int16(value * Float(Int16.max))
        }

        frameHandler?(monoSamples, 1, sampleRate)
    }

    private func ensureEngineRunning() {
        guard !isRunning else { return }

        do {
            try engine.start()
            isRunning = true
        } catch {
            isRunning = false
        }
    }

    private func stopEngineIfIdle() {
        guard isRunning, !isCapturing else { return }
        player.stop()
        engine.stop()
        isRunning = false
    }
}
