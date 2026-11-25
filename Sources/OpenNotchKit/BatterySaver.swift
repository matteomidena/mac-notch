import SwiftUI

/// Battery saver: lower frame rates, and the closed notch's looping animations
/// (pulse dot, equalizer) hold still. Off, Automatic (on battery below 20% or in
/// macOS Low Power Mode), or Always on.
public enum BatterySaverMode: String, CaseIterable, Sendable {
    case off, automatic, always
    public static let key = "batterySaver"
    public static let threshold = 20

    public var title: String {
        switch self {
        case .off: "Off"
        case .automatic: "Automatic below \(Self.threshold)%"
        case .always: "Always on"
        }
    }

    /// `percent` is nil on a Mac without a battery.
    public func isActive(onBattery: Bool, percent: Int?, lowPowerMode: Bool) -> Bool {
        switch self {
        case .off: false
        case .always: true
        case .automatic: lowPowerMode || (onBattery && (percent ?? 100) < Self.threshold)
        }
    }
}

private struct BatterySaverKey: EnvironmentKey { static let defaultValue = false }
private struct PauseAmbientMotionKey: EnvironmentKey { static let defaultValue = false }

public extension EnvironmentValues {
    /// Battery saver is on: animations that keep running use lower frame rates.
    var batterySaver: Bool {
        get { self[BatterySaverKey.self] }
        set { self[BatterySaverKey.self] = newValue }
    }
    /// Battery saver is on and the notch is closed or hidden: looping animations hold still.
    var pauseAmbientMotion: Bool {
        get { self[PauseAmbientMotionKey.self] }
        set { self[PauseAmbientMotionKey.self] = newValue }
    }
}
