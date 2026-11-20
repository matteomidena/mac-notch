import SwiftUI

/// Shared look: the "Hex" palette and type from the notch-look mockup.
public enum Hex {
    public static let bg = Color(red: 0x07 / 255, green: 0x07 / 255, blue: 0x07 / 255)
    public static let ink = Color(red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xEF / 255)
    public static let muted = Color(red: 0x9B / 255, green: 0x9D / 255, blue: 0xA3 / 255)
    public static let code = Color(red: 0xB9 / 255, green: 0xBB / 255, blue: 0xC0 / 255)
    /// Hairlines: ink at .07 / .10 / .14.
    public static func line(_ opacity: Double) -> Color { ink.opacity(opacity) }
    // The v4.1 variable TTF registers as "Inter Variable"; falls back to system if unregistered.
    public static func text(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Inter Variable", size: size).weight(weight)
    }
    public static func mono(_ size: CGFloat) -> Font { .system(size: size, design: .monospaced) }
}
