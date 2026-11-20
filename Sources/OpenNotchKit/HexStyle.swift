import SwiftUI

/// Shared look: the "Hex" palette and type from the notch-look mockup.
public enum Hex {
    public static let bg = Color(red: 0x07 / 255, green: 0x07 / 255, blue: 0x07 / 255)
    public static let ink = Color(red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xEF / 255)
    public static let muted = Color(red: 0x9B / 255, green: 0x9D / 255, blue: 0xA3 / 255)
    public static let code = Color(red: 0xB9 / 255, green: 0xBB / 255, blue: 0xC0 / 255)
    /// Hairlines: ink at .07 / .10 / .14.
    public static func line(_ opacity: Double) -> Color { ink.opacity(opacity) }
    // Inter isn't bundled yet; `.custom` falls back to the system font until it is.
    public static func text(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Inter", size: size).weight(weight)
    }
    public static func mono(_ size: CGFloat) -> Font { .system(size: size, design: .monospaced) }
}

/// Three capsules at the given levels (0…1). Paused, they rest at the 3 pt minimum.
public struct SpectrumBars: View {
    private let levels: [Double]
    private let isPlaying: Bool
    private let height: CGFloat
    public init(levels: [Double], isPlaying: Bool, height: CGFloat) {
        self.levels = levels; self.isPlaying = isPlaying; self.height = height
    }
    public var body: some View {
        HStack(alignment: .center, spacing: height > 18 ? 3 : 2.5) {
            ForEach(0..<3, id: \.self) { i in
                let v = isPlaying && i < levels.count ? min(max(levels[i], 0), 1) : 0
                Capsule().frame(width: 3, height: max(3, v * height))
            }
        }
        .frame(height: height)
    }
}
