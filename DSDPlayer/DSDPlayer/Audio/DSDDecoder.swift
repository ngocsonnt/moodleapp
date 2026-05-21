import Foundation
import Accelerate

/// Streaming DSD-to-PCM decoder.
///
/// Treats each DSD bit as a +1/-1 sample, then applies a Kaiser-windowed
/// low-pass FIR before decimating to the target PCM rate. State is kept
/// per channel so callers can feed bytes in chunks (e.g. one DSF block
/// per channel at a time).
final class DSDDecoder {

    enum BitOrder {
        case lsbFirst   // DSF (bitsPerSample = 1)
        case msbFirst   // DFF, and DSF with bitsPerSample = 8
    }

    let channels: Int
    let dsdRate: Int
    let pcmRate: Int
    let decimation: Int

    private let filter: [Float]
    private let filterLength: Int
    private var ring: [[Float]]
    private var ringPos: [Int]
    private var subCounter: [Int]

    init(channels: Int, dsdRate: Int, pcmRate: Int = 88200) {
        precondition(channels > 0, "channels must be > 0")
        precondition(dsdRate % pcmRate == 0, "DSD rate must be integer multiple of PCM rate")

        self.channels = channels
        self.dsdRate = dsdRate
        self.pcmRate = pcmRate
        self.decimation = dsdRate / pcmRate

        // 8 taps per output sample gives a usable FIR for an MVP-quality
        // single-stage decimator. Trade-off: low CPU, ~40 dB stopband.
        let length = max(64, 8 * decimation)
        self.filterLength = length
        self.filter = Self.designKaiserLowpass(
            length: length,
            normalizedCutoff: 0.45 / Double(decimation)
        )
        self.ring = Array(repeating: [Float](repeating: 0, count: length), count: channels)
        self.ringPos = Array(repeating: 0, count: channels)
        self.subCounter = Array(repeating: 0, count: channels)
    }

    /// Decode `count` bytes of single-channel DSD bitstream into PCM
    /// samples. Output count depends on `decimation` and on the
    /// internal sub-sample counter from previous calls.
    func decode(channel: Int,
                bytes: UnsafePointer<UInt8>,
                count: Int,
                order: BitOrder) -> [Float] {
        let M = filterLength
        var output: [Float] = []
        output.reserveCapacity((count * 8 / decimation) + 1)

        var pos = ringPos[channel]
        var counter = subCounter[channel]

        ring[channel].withUnsafeMutableBufferPointer { ringPtr in
            filter.withUnsafeBufferPointer { filterPtr in
                let ringBase = ringPtr.baseAddress!
                let filterBase = filterPtr.baseAddress!

                for i in 0..<count {
                    let byte = bytes[i]
                    for b in 0..<8 {
                        let bit: UInt8
                        switch order {
                        case .lsbFirst: bit = (byte >> b) & 1
                        case .msbFirst: bit = (byte >> (7 - b)) & 1
                        }
                        ringBase[pos] = bit == 1 ? 1.0 : -1.0
                        pos += 1
                        if pos == M { pos = 0 }
                        counter += 1
                        if counter == decimation {
                            counter = 0
                            // Filter convolution: align tap[0] to oldest
                            // sample (which is the one we are about to
                            // overwrite next - i.e. at index `pos`).
                            var sum: Float = 0
                            if pos == 0 {
                                vDSP_dotpr(ringBase, 1, filterBase, 1, &sum, vDSP_Length(M))
                            } else {
                                var s1: Float = 0
                                var s2: Float = 0
                                let head = M - pos
                                vDSP_dotpr(ringBase + pos, 1, filterBase, 1, &s1, vDSP_Length(head))
                                vDSP_dotpr(ringBase, 1, filterBase + head, 1, &s2, vDSP_Length(pos))
                                sum = s1 + s2
                            }
                            output.append(sum)
                        }
                    }
                }
            }
        }

        ringPos[channel] = pos
        subCounter[channel] = counter
        return output
    }

    func reset() {
        for ch in 0..<channels {
            for i in 0..<filterLength { ring[ch][i] = 0 }
            ringPos[ch] = 0
            subCounter[ch] = 0
        }
    }

    // MARK: - Filter design

    private static func designKaiserLowpass(length: Int, normalizedCutoff: Double) -> [Float] {
        let M = length
        let beta: Double = 8.6
        let mid = Double(M - 1) / 2
        let i0Beta = besselI0(beta)
        var h = [Float](repeating: 0, count: M)

        for n in 0..<M {
            let x = Double(n) - mid
            let y = 2 * normalizedCutoff * x
            let sinc: Double = abs(y) < 1e-12 ? 1 : sin(.pi * y) / (.pi * y)
            let r = (Double(n) - mid) / mid
            let inside = max(0.0, 1 - r * r)
            let kaiser = besselI0(beta * sqrt(inside)) / i0Beta
            h[n] = Float(2 * normalizedCutoff * sinc * kaiser)
        }

        // Normalise DC gain so the filter doesn't change level
        let dc = h.reduce(Float(0), +)
        if dc != 0 {
            for i in 0..<M { h[i] /= dc }
        }
        return h
    }

    private static func besselI0(_ x: Double) -> Double {
        var sum = 1.0
        var term = 1.0
        for k in 1..<60 {
            let r = x / (2 * Double(k))
            term *= r * r
            sum += term
            if term < 1e-16 * sum { break }
        }
        return sum
    }
}
