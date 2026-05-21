import Foundation
import AVFoundation
import Combine

@MainActor
final class PlayerState: ObservableObject {

    @Published var currentTrack: Track?
    @Published var isPlaying: Bool = false
    @Published var statusMessage: String = ""
    @Published var formatDetail: String = ""
    @Published var queue: [Track] = []
    @Published var currentIndex: Int = 0
    @Published var errorMessage: String?

    private let engine = AudioEngine()
    private var playbackTask: Task<Void, Never>?
    private var folderScope: URL?
    private var folderScopeActive = false

    // MARK: - Public API

    func play(track: Track, in queue: [Track], folderURL: URL?) {
        playbackTask?.cancel()
        releaseFolderScope()

        if let folderURL {
            folderScopeActive = folderURL.startAccessingSecurityScopedResource()
            folderScope = folderURL
        }

        self.queue = queue
        self.currentIndex = queue.firstIndex(of: track) ?? 0
        self.currentTrack = track
        self.errorMessage = nil

        playbackTask = Task { [weak self] in
            await self?.runPlayback(track: track)
        }
    }

    func togglePlayPause() {
        if isPlaying {
            engine.pause()
            isPlaying = false
        } else {
            engine.play()
            isPlaying = true
        }
    }

    func stop() {
        playbackTask?.cancel()
        playbackTask = nil
        engine.stop()
        isPlaying = false
        currentTrack = nil
        statusMessage = ""
        formatDetail = ""
        releaseFolderScope()
    }

    func next() {
        guard !queue.isEmpty else { return }
        let nextIdx = (currentIndex + 1) % queue.count
        play(track: queue[nextIdx], in: queue, folderURL: folderScope)
    }

    func previous() {
        guard !queue.isEmpty else { return }
        let prevIdx = (currentIndex - 1 + queue.count) % queue.count
        play(track: queue[prevIdx], in: queue, folderURL: folderScope)
    }

    // MARK: - Internal

    private func releaseFolderScope() {
        if folderScopeActive, let url = folderScope {
            url.stopAccessingSecurityScopedResource()
        }
        folderScope = nil
        folderScopeActive = false
    }

    private func runPlayback(track: Track) async {
        do {
            statusMessage = "Loading…"
            switch track.ext {
            case "dsf":
                try await playDSF(url: track.url)
            case "dff":
                throw NSError(domain: "Player", code: 100, userInfo: [
                    NSLocalizedDescriptionKey: "DFF (DSDIFF) not yet supported - use DSF for now"
                ])
            default:
                try await playStandard(url: track.url)
            }

            // Auto-advance to next track if queue not exhausted
            if !Task.isCancelled, currentIndex + 1 < queue.count {
                let nextTrack = queue[currentIndex + 1]
                play(track: nextTrack, in: queue, folderURL: folderScope)
            } else {
                isPlaying = false
                statusMessage = "Finished"
            }
        } catch is CancellationError {
            // Expected when user starts a new track or stops
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Error"
            isPlaying = false
        }
    }

    // MARK: - DSF playback

    private func playDSF(url: URL) async throws {
        let file = try DSFFile(url: url)
        let pcmRate = Self.choosePCMRate(forDSDRate: file.format.dsdRate)

        let decoder = DSDDecoder(
            channels: file.format.channels,
            dsdRate: file.format.dsdRate,
            pcmRate: pcmRate
        )
        try file.seekToStart()
        try engine.prepare(sampleRate: Double(pcmRate),
                           channels: file.format.channels)

        let dsdMultiple = file.format.dsdRate / 44100
        formatDetail = "DSD\(dsdMultiple) · \(file.format.channels)ch · → PCM \(pcmRate / 1000) kHz"
        statusMessage = "Playing"
        isPlaying = true

        engine.play()

        // Backpressure: keep at most N buffers queued ahead.
        let inFlight = AsyncBackpressure(limit: 4)

        let streamTask = Task.detached(priority: .userInitiated) { [engine] in
            while !Task.isCancelled {
                guard let blocks = try file.readNextBlock() else { break }
                var pcm: [[Float]] = []
                pcm.reserveCapacity(file.format.channels)
                for ch in 0..<file.format.channels {
                    let chPcm = blocks[ch].withUnsafeBufferPointer { buf in
                        decoder.decode(
                            channel: ch,
                            bytes: buf.baseAddress!,
                            count: buf.count,
                            order: file.format.bitOrder
                        )
                    }
                    pcm.append(chPcm)
                }
                let frames = pcm.map { $0.count }.min() ?? 0
                guard frames > 0 else { continue }
                let trimmed = pcm.map { Array($0.prefix(frames)) }

                await inFlight.acquire()
                if Task.isCancelled {
                    await inFlight.release()
                    break
                }
                engine.schedule(samples: trimmed) {
                    Task { await inFlight.release() }
                }
            }
            if !Task.isCancelled {
                await inFlight.drain()
            }
        }

        try await withTaskCancellationHandler {
            try await streamTask.value
        } onCancel: {
            streamTask.cancel()
        }
    }

    // MARK: - Standard formats (FLAC/WAV/AIFF/M4A/MP3)

    private func playStandard(url: URL) async throws {
        let audioFile = try AVAudioFile(forReading: url)
        let processingFormat = audioFile.processingFormat
        try engine.prepare(
            sampleRate: processingFormat.sampleRate,
            channels: Int(processingFormat.channelCount)
        )

        formatDetail = "\(Int(processingFormat.sampleRate / 1000)) kHz · \(processingFormat.channelCount)ch"
        statusMessage = "Playing"
        isPlaying = true
        engine.play()

        let bufSize: AVAudioFrameCount = 8192
        let inFlight = AsyncBackpressure(limit: 4)

        let streamTask = Task.detached(priority: .userInitiated) { [engine] in
            while !Task.isCancelled {
                guard let buf = AVAudioPCMBuffer(pcmFormat: processingFormat,
                                                 frameCapacity: bufSize) else { break }
                try audioFile.read(into: buf)
                if buf.frameLength == 0 { break }

                let ch = Int(buf.format.channelCount)
                var samples: [[Float]] = []
                samples.reserveCapacity(ch)
                for c in 0..<ch {
                    let p = buf.floatChannelData![c]
                    samples.append(Array(UnsafeBufferPointer(start: p, count: Int(buf.frameLength))))
                }

                await inFlight.acquire()
                if Task.isCancelled {
                    await inFlight.release()
                    break
                }
                engine.schedule(samples: samples) {
                    Task { await inFlight.release() }
                }
            }
            if !Task.isCancelled {
                await inFlight.drain()
            }
        }

        try await withTaskCancellationHandler {
            try await streamTask.value
        } onCancel: {
            streamTask.cancel()
        }
    }

    // MARK: - Helpers

    /// Pick a PCM output rate that's an integer divisor of the DSD rate.
    /// Maps the DSD family (44.1 kHz × 64/128/256/512) onto its native
    /// PCM family (88.2 / 176.4 / 352.8 kHz).
    private static func choosePCMRate(forDSDRate dsdRate: Int) -> Int {
        // 44100 × 64 = 2_822_400 (DSD64)  -> 88200 (decim 32)
        // 44100 × 128 = 5_644_800 (DSD128) -> 176400 (decim 32)
        // 44100 × 256 = 11_289_600 (DSD256) -> 352800 (decim 32)
        let candidates = [44100, 48000, 88200, 96000, 176400, 192000, 352800]
        for r in candidates.reversed() where dsdRate % r == 0 && dsdRate / r >= 8 {
            return r
        }
        return 88200
    }
}

/// Async semaphore that limits how many PCM buffers we have scheduled
/// (and therefore allocated) at once. `drain` waits for everything we've
/// handed out to be released back.
actor AsyncBackpressure {
    private let limit: Int
    private var inFlight: Int = 0
    private var acquireWaiters: [CheckedContinuation<Void, Never>] = []
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { self.limit = limit }

    func acquire() async {
        if inFlight < limit {
            inFlight += 1
            return
        }
        await withCheckedContinuation { cont in
            acquireWaiters.append(cont)
        }
    }

    func release() {
        if let next = acquireWaiters.first {
            acquireWaiters.removeFirst()
            next.resume()
            return
        }
        inFlight -= 1
        if inFlight == 0 {
            let waiters = drainWaiters
            drainWaiters.removeAll()
            for w in waiters { w.resume() }
        }
    }

    func drain() async {
        if inFlight == 0 { return }
        await withCheckedContinuation { cont in
            drainWaiters.append(cont)
        }
    }
}
