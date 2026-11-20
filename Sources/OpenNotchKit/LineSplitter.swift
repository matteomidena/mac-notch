import Foundation

/// Splits a byte stream into complete newline-terminated lines, keeping a trailing fragment.
public struct LineSplitter {
    private var buffer = Data()

    public init() {}

    public mutating func feed(_ data: Data) -> [String] {
        buffer.append(data)
        var lines: [String] = []
        var start = buffer.startIndex
        while let nl = buffer[start...].firstIndex(of: 0x0A) {
            lines.append(String(decoding: buffer[start..<nl], as: UTF8.self))
            start = buffer.index(after: nl)
        }
        if start != buffer.startIndex { buffer = Data(buffer[start...]) }  // trim once
        return lines
    }
}
