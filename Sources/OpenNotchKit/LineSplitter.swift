import Foundation

/// Splits a byte stream into complete newline-terminated lines, keeping a trailing fragment.
public struct LineSplitter {
    private var buffer = Data()

    public init() {}

    public mutating func feed(_ data: Data) -> [String] { feed(data, keep: { _ in true }) }

    /// Only lines whose raw bytes pass `keep` become Strings: skipping a line costs a byte scan, not a decode.
    public mutating func feed(_ data: Data, keep: (Data.SubSequence) -> Bool) -> [String] {
        buffer.append(data)
        var lines: [String] = []
        var start = buffer.startIndex
        while let nl = buffer[start...].firstIndex(of: 0x0A) {
            let line = buffer[start..<nl]
            if keep(line) { lines.append(String(decoding: line, as: UTF8.self)) }
            start = buffer.index(after: nl)
        }
        if start != buffer.startIndex { buffer = Data(buffer[start...]) }  // trim once
        return lines
    }
}
