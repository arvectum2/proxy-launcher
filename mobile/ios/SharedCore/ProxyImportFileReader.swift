import Foundation

/// Bounded local-file ingestion used before any proxy parsing or Keychain
/// mutation. A hostile/accidental multi-gigabyte file never enters memory.
enum ProxyImportFileReader {
    static let maxBytes = 256_000
    private static let chunkSize = 16_384

    static func readUTF8(from url: URL) throws -> String {
        guard url.isFileURL else { throw ProxyImportError.invalid }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var bytes = Data()
        while true {
            // Request one extra byte at the limit to detect an oversized
            // document without buffering the rest of the file.
            let remaining = maxBytes - bytes.count
            let request = min(chunkSize, remaining + 1)
            guard let chunk = try handle.read(upToCount: request),
                  !chunk.isEmpty else { break }
            guard chunk.count <= remaining else { throw ProxyImportError.tooLarge }
            bytes.append(chunk)
        }
        guard let content = String(data: bytes, encoding: .utf8) else {
            throw ProxyImportError.invalid
        }
        return content
    }
}
