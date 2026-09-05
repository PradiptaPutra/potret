import Foundation
import os

/// Unified-log channels.
///
/// The Tauri app reported its failures with `eprintln!`, which goes to a stderr that a bundled
/// .app has no terminal for — so every backend error was invisible in a shipping build. os.Logger
/// entries survive, are queryable after the fact with
/// `log show --predicate 'subsystem == "com.potret.app"'`, and can be streamed live.
public enum Log {
    private static let subsystem = "com.potret.app"

    public static let capture = Logger(subsystem: subsystem, category: "capture")
    public static let shortcuts = Logger(subsystem: subsystem, category: "shortcuts")
    public static let history = Logger(subsystem: subsystem, category: "history")
    public static let ui = Logger(subsystem: subsystem, category: "ui")
}
