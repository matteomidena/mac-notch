import Accelerate
import Foundation

/// Hann-windowed real FFT magnitudes. Setup and window are built once.
public struct SpectrumAnalyzer {
    private let fftSize: Int
    private let fft: vDSP.FFT<DSPSplitComplex>
    private let window: [Float]

    public init(fftSize: Int = 2048) {
        precondition(fftSize >= 4 && fftSize & (fftSize - 1) == 0, "fftSize must be a power of two")
        self.fftSize = fftSize
        self.fft = vDSP.FFT(log2n: vDSP_Length(fftSize.trailingZeroBitCount), radix: .radix2, ofType: DSPSplitComplex.self)!
        self.window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: fftSize, isHalfWindow: false)
    }

    /// `fftSize / 2` magnitudes. Short input is zero-padded; long input uses its last `fftSize` samples.
    /// Scale: vDSP's real FFT returns 2x the DFT and the Hann window has coherent gain 0.5,
    /// so a full-scale sine peaks at fftSize / 2; dividing by that makes it read ~1.0 (0 dB).
    public func magnitudes(_ samples: [Float]) -> [Float] {
        var x = Array(samples.suffix(fftSize))
        x += [Float](repeating: 0, count: fftSize - x.count)
        x = vDSP.multiply(x, window)
        let half = fftSize / 2
        var re = (0..<half).map { x[2 * $0] }
        var im = (0..<half).map { x[2 * $0 + 1] }
        re.withUnsafeMutableBufferPointer { r in
            im.withUnsafeMutableBufferPointer { i in
                var split = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                fft.transform(input: split, output: &split, direction: .forward)
            }
        }
        let scale = 2 / Float(fftSize)
        return (0..<half).map { (re[$0] * re[$0] + im[$0] * im[$0]).squareRoot() * scale }
    }
}

/// Folds magnitudes into smoothed 0...1 band levels.
public struct SpectrumBands {
    public static let defaultEdges: [ClosedRange<Double>] = [20...250, 250...2000, 2000...12000]

    private let bandBins: [[Int]]
    private let attack: Double
    private let release: Double
    public private(set) var levels: [Double]

    public init(sampleRate: Double, fftSize: Int, edges: [ClosedRange<Double>] = defaultEdges,
                attack: Double = 0.5, release: Double = 0.08) {
        // A bin belongs to the first edge range containing its frequency; bins outside all edges are ignored.
        bandBins = edges.indices.map { b in
            (0..<fftSize / 2).filter { i in
                let f = Double(i) * sampleRate / Double(fftSize)
                return edges[b].contains(f) && !edges[..<b].contains { $0.contains(f) }
            }
        }
        self.attack = attack
        self.release = release
        levels = Array(repeating: 0, count: edges.count)
    }

    @discardableResult
    public mutating func update(magnitudes: [Float]) -> [Double] {
        for (b, bins) in bandBins.enumerated() {
            let energy = bins.reduce(0.0) { $0 + Double(magnitudes[$1]) * Double(magnitudes[$1]) }
            let db = 10 * log10(max(energy, 1e-12))      // floor keeps silence finite
            let target = min(max((db + 60) / 60, 0), 1)  // -60...0 dB -> 0...1
            levels[b] += (target - levels[b]) * (target > levels[b] ? attack : release)
            levels[b] = min(max(levels[b], 0), 1)
        }
        return levels
    }
}
