import Foundation
import CoreGraphics

/// User-facing knobs, persisted in the app's own defaults domain.
///
/// Deliberately *not* `com.apple.dock` -- the whole point of this rewrite is
/// that we no longer poke Apple's Dock preferences.
///
/// Main-actor bound: every reader is the menu or the tap callback, both of
/// which run on the main run loop.
@MainActor
enum Settings {
    private static let defaults = UserDefaults.standard

    enum Key {
        static let anchorUUID = "anchorDisplayUUID"
        static let triggerHeight = "triggerHeight"
        static let enabled = "guardEnabled"
        static let warpFallback = "warpFallback"
    }

    /// Reserved band along the bottom of every non-anchor display. Four points
    /// clears the Dock's trigger depth while staying imperceptible in use.
    static let defaultTriggerHeight: CGFloat = 4

    static func registerDefaults() {
        defaults.register(defaults: [
            Key.triggerHeight: defaultTriggerHeight,
            Key.enabled: true,
            Key.warpFallback: false,
        ])
    }

    static var anchorUUID: String? {
        get { defaults.string(forKey: Key.anchorUUID) }
        set { defaults.set(newValue, forKey: Key.anchorUUID) }
    }

    static var triggerHeight: CGFloat {
        get { CGFloat(defaults.double(forKey: Key.triggerHeight)) }
        set { defaults.set(Double(newValue), forKey: Key.triggerHeight) }
    }

    static var isEnabled: Bool {
        get { defaults.bool(forKey: Key.enabled) }
        set { defaults.set(newValue, forKey: Key.enabled) }
    }

    /// Belt-and-braces mode: also warp the cursor instead of trusting the
    /// window server to honour the rewritten event location.
    static var warpFallback: Bool {
        get { defaults.bool(forKey: Key.warpFallback) }
        set { defaults.set(newValue, forKey: Key.warpFallback) }
    }
}
