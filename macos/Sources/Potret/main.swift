import AppKit
import PotretUI

// Hand-rolled entry point rather than `@main` + NSApplicationDelegateAdaptor: the activation
// policy has to be set before the run loop starts, so the app never flashes a Dock tile.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = AppDelegate()
app.delegate = delegate
app.run()
