import Foundation

/// Splits a byte stream into complete newline-terminated lines, keeping a trailing fragment.
public struct LineSplitter {
    private var buffer = Data()

    public init() {}

    public mutating func feed(_ data: Data) -> [String] {
        buffer.append(data)
        var lines: [String] = []
        while let nl = buffer.firstIndex(of: 0x0A) {
            lines.append(String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self))
            buffer = Data(buffer[buffer.index(after: nl)...])
        }
        return lines
    }
}
