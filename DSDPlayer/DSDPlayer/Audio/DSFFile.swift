import Foundation

struct DSDFormatInfo {
    var channels: Int
    var dsdRate: Int           // 1-bit samples per second per channel
    var bitsPerSample: Int     // 1 or 8 (DSF spec)
    var sampleCount: Int       // total 1-bit samples per channel
    var blockSize: Int         // bytes per channel per data block
    var bitOrder: DSDDecoder.BitOrder

    /// Approximate duration in seconds.
    var duration: Double { Double(sampleCount) / Double(dsdRate) }
}

/// Minimal parser/streamer for the DSF (DSD Stream File) container format.
///
/// Layout per spec:
///   DSD chunk (28 bytes) -> fmt chunk (52 bytes) -> data chunk (12 bytes
///   header + payload). The payload is organised in fixed-size blocks of
///   `blockSize` bytes per channel, interleaved by block (not by sample).
final class DSFFile {

    enum DSFError: Error {
        case openFailed
        case badHeader(String)
        case unsupported(String)
        case truncated
    }

    let url: URL
    let format: DSDFormatInfo
    let dataOffset: UInt64
    let dataSize: UInt64

    private let handle: FileHandle
    private var bytesRead: UInt64 = 0

    init(url: URL) throws {
        self.url = url
        do {
            self.handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw DSFError.openFailed
        }

        // DSD chunk
        let dsd = try Self.readExact(handle, count: 28)
        guard dsd.starts(with: Array("DSD ".utf8)) else {
            throw DSFError.badHeader("missing 'DSD ' magic")
        }

        // fmt chunk
        let fmt = try Self.readExact(handle, count: 52)
        guard fmt.starts(with: Array("fmt ".utf8)) else {
            throw DSFError.badHeader("missing 'fmt ' chunk")
        }
        let formatID = fmt.readUInt32LE(at: 16)
        let channelNum = Int(fmt.readUInt32LE(at: 24))
        let dsdRate = Int(fmt.readUInt32LE(at: 28))
        let bitsPerSample = Int(fmt.readUInt32LE(at: 32))
        let sampleCount = Int(fmt.readUInt64LE(at: 36))
        let blockSize = Int(fmt.readUInt32LE(at: 44))

        guard formatID == 0 else {
            throw DSFError.unsupported("unknown DSF formatID \(formatID)")
        }
        guard channelNum >= 1 else {
            throw DSFError.unsupported("zero channels")
        }
        guard bitsPerSample == 1 || bitsPerSample == 8 else {
            throw DSFError.unsupported("bitsPerSample \(bitsPerSample) not supported")
        }
        guard blockSize > 0 else {
            throw DSFError.badHeader("blockSize is zero")
        }

        // data chunk header
        let dataHdr = try Self.readExact(handle, count: 12)
        guard dataHdr.starts(with: Array("data".utf8)) else {
            throw DSFError.badHeader("missing 'data' chunk")
        }
        let dataChunkSize = dataHdr.readUInt64LE(at: 4)

        self.dataOffset = 28 + 52 + 12
        self.dataSize = dataChunkSize - 12

        self.format = DSDFormatInfo(
            channels: channelNum,
            dsdRate: dsdRate,
            bitsPerSample: bitsPerSample,
            sampleCount: sampleCount,
            blockSize: blockSize,
            // DSF: bitsPerSample==1 => LSB-first; ==8 => MSB-first.
            bitOrder: bitsPerSample == 1 ? .lsbFirst : .msbFirst
        )
    }

    deinit { try? handle.close() }

    /// Reads the next block from the data chunk. Returns one byte buffer
    /// per channel (each of length `blockSize`), or `nil` at EOF.
    func readNextBlock() throws -> [[UInt8]]? {
        let perBlock = format.blockSize * format.channels
        let remaining = dataSize > bytesRead ? Int(dataSize - bytesRead) : 0
        guard remaining > 0 else { return nil }
        let toRead = min(perBlock, remaining)

        guard let data = try handle.read(upToCount: toRead), !data.isEmpty else {
            return nil
        }
        bytesRead += UInt64(data.count)

        // If we got a short read at the very end, pad with the DSD
        // "silence" pattern (0x69 = 0b01101001 - alternating bits give
        // ~zero PCM, while 0x00 / 0xFF would decode to DC and click).
        var padded = [UInt8](data)
        if padded.count < perBlock {
            padded.append(contentsOf: [UInt8](repeating: 0x69,
                                              count: perBlock - padded.count))
        }

        var blocks: [[UInt8]] = []
        blocks.reserveCapacity(format.channels)
        for ch in 0..<format.channels {
            let start = ch * format.blockSize
            blocks.append(Array(padded[start..<start + format.blockSize]))
        }
        return blocks
    }

    func seekToStart() throws {
        try handle.seek(toOffset: dataOffset)
        bytesRead = 0
    }

    // MARK: - Helpers

    private static func readExact(_ handle: FileHandle, count: Int) throws -> [UInt8] {
        guard let data = try handle.read(upToCount: count), data.count == count else {
            throw DSFError.truncated
        }
        return [UInt8](data)
    }
}

private extension Array where Element == UInt8 {
    func readUInt32LE(at offset: Int) -> UInt32 {
        UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }

    func readUInt64LE(at offset: Int) -> UInt64 {
        var v: UInt64 = 0
        for i in 0..<8 { v |= UInt64(self[offset + i]) << (8 * i) }
        return v
    }
}
