import Foundation
import AVFoundation

/// Thin wrapper around AVAudioEngine + AVAudioPlayerNode for streaming
/// Float32 non-interleaved PCM buffers.
final class AudioEngine {

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var pcmFormat: AVAudioFormat?

    init() {
        engine.attach(player)
    }

    func prepare(sampleRate: Double, channels: Int) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true, options: [])

        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(channels),
            interleaved: false
        )
        guard let format else {
            throw NSError(domain: "AudioEngine", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot create AVAudioFormat"])
        }
        self.pcmFormat = format

        if player.isPlaying { player.stop() }
        if engine.isRunning { engine.stop() }
        engine.disconnectNodeOutput(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try engine.start()
    }

    func play() {
        if !player.isPlaying { player.play() }
    }

    func pause() {
        if player.isPlaying { player.pause() }
    }

    func stop() {
        player.stop()
        if engine.isRunning { engine.stop() }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    var isPlaying: Bool { player.isPlaying }

    /// Schedule a non-interleaved Float32 buffer. `samples[ch]` must have
    /// the same length for every channel.
    func schedule(samples: [[Float]], completion: (() -> Void)? = nil) {
        guard let format = pcmFormat else {
            completion?()
            return
        }
        let frameCount = samples.first?.count ?? 0
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(frameCount)) else {
            completion?()
            return
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        guard let channelData = buffer.floatChannelData else {
            completion?()
            return
        }
        for ch in 0..<samples.count {
            samples[ch].withUnsafeBufferPointer { src in
                channelData[ch].update(from: src.baseAddress!, count: frameCount)
            }
        }
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
            completion?()
        }
    }
}
