import AppKit
import OpenNotchKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // agent app: no dock icon
print("OpenNotch \(OpenNotchKit.version) starting")
app.run()
