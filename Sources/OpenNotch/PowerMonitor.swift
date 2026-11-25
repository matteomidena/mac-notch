import Foundation
import IOKit.ps
import Observation
import OpenNotchKit

/// Whether battery saver is on now: the Settings mode, the power source and macOS Low Power Mode.
/// Event-driven: the IOKit power-source notification, the Low Power Mode notification, and
/// defaults changes (the Settings picker). Nothing polls.
@Observable @MainActor final class PowerMonitor {
    static let shared = PowerMonitor()
    private(set) var active = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private init() {
        if let source = IOPSNotificationCreateRunLoopSource({ _ in
            MainActor.assumeIsolated { PowerMonitor.shared.refresh() }
        }, nil)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        let nc = NotificationCenter.default
        for name in [Notification.Name.NSProcessInfoPowerStateDidChange, UserDefaults.didChangeNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { PowerMonitor.shared.refresh() }
            })
        }
        refresh()
    }

    func refresh() {
        let mode = UserDefaults.standard.string(forKey: BatterySaverMode.key).flatMap(BatterySaverMode.init) ?? .automatic
        let (onBattery, percent) = Self.battery()
        let now = mode.isActive(onBattery: onBattery, percent: percent,
                                lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
        if now != active { active = now }  // defaults change often: don't invalidate views for nothing
    }

    /// Whether the Mac runs on its battery, and the internal battery's charge in percent (nil if none).
    private static func battery() -> (onBattery: Bool, percent: Int?) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return (false, nil) }
        let onBattery = (IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?) == kIOPSBatteryPowerValue
        let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] ?? []
        for source in sources {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let now = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }
            return (onBattery, now * 100 / max)
        }
        return (onBattery, nil)
    }
}
