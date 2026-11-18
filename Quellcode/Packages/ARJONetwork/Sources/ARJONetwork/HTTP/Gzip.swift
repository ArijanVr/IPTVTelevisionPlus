import Compression
import Foundation

public enum GzipError: Error, Equatable {
    case invalidHeader
    case decompressionFailed
    case truncated
}

/// Entpackt `.gz`-Dateien stückweise (konstanter Speicher), z. B. grosse XMLTV-Dateien.
public enum Gzip {
    private static let chunkSize = 64 * 1024

    public static func isGzipped(_ url: URL) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try handle.read(upToCount: 2) == Data([0x1F, 0x8B])
    }

    public static func decompress(from source: URL, to destination: URL) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }

        try skipHeader(of: input)

        let outBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        defer { outBuffer.deallocate() }
        var stream = compression_stream(dst_ptr: outBuffer, dst_size: chunkSize, src_ptr: UnsafePointer(outBuffer), src_size: 0, state: nil)
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw GzipError.decompressionFailed
        }
        defer { compression_stream_destroy(&stream) }

        var finished = false
        while !finished {
            let chunk = try input.read(upToCount: chunkSize) ?? Data()
            let isLast = chunk.isEmpty
            let flags = isLast ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0

            try chunk.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                stream.src_ptr = raw.bindMemory(to: UInt8.self).baseAddress ?? UnsafePointer(outBuffer)
                stream.src_size = chunk.count
                var produced = 0
                repeat {
                    stream.dst_ptr = outBuffer
                    stream.dst_size = chunkSize
                    let status = compression_stream_process(&stream, flags)
                    guard status == COMPRESSION_STATUS_OK || status == COMPRESSION_STATUS_END else {
                        throw GzipError.decompressionFailed
                    }
                    produced = chunkSize - stream.dst_size
                    if produced > 0 { try output.write(contentsOf: Data(bytes: outBuffer, count: produced)) }
                    if status == COMPRESSION_STATUS_END {
                        finished = true
                        return
                    }
                    if isLast && produced == 0 { throw GzipError.truncated }
                } while stream.src_size > 0 || produced == chunkSize
            }
        }
    }

    /// RFC 1952: 10 Byte Kopf, danach optionale Felder je nach Flags.
    private static func skipHeader(of handle: FileHandle) throws {
        guard let header = try handle.read(upToCount: 10), header.count == 10,
              header[0] == 0x1F, header[1] == 0x8B, header[2] == 8
        else { throw GzipError.invalidHeader }
        let flags = header[3]

        if flags & 0x04 != 0 {
            guard let length = try handle.read(upToCount: 2), length.count == 2 else { throw GzipError.invalidHeader }
            _ = try handle.read(upToCount: Int(length[0]) | Int(length[1]) << 8)
        }
        for flag: UInt8 in [0x08, 0x10] where flags & flag != 0 {
            while let byte = try handle.read(upToCount: 1), let value = byte.first, value != 0 {}
        }
        if flags & 0x02 != 0 { _ = try handle.read(upToCount: 2) }
    }
}
