import CoreGraphics

/// A display and its bounds in global display coordinates.
///
/// Global display coordinates put the origin at the top-left of the main
/// display with +Y pointing *down*. `CGDisplayBounds` and `CGEvent.location`
/// both use this space, so they can be compared directly -- no AppKit-style
/// bottom-left flipping is involved anywhere in this file.
public struct DisplayRect: Equatable, Sendable {
    public let id: CGDirectDisplayID
    public let bounds: CGRect

    public init(id: CGDirectDisplayID, bounds: CGRect) {
        self.id = id
        self.bounds = bounds
    }
}

/// Outcome of running a pointer location past the guard.
public struct GuardDecision: Equatable, Sendable {
    /// Where the pointer is allowed to be.
    public let location: CGPoint
    /// True when `location` differs from the requested one.
    public let didClamp: Bool

    public init(location: CGPoint, didClamp: Bool) {
        self.location = location
        self.didClamp = didClamp
    }
}

/// Decides whether a pointer location would let macOS hand the Dock to a
/// non-anchored display, and pulls it back if so.
///
/// macOS moves the Dock to whichever display the pointer presses against the
/// bottom edge of. We never see that decision; we only get to shape the
/// pointer stream feeding it. So the guard keeps a thin band along the bottom
/// of every *non-anchor* display permanently unreachable. The Dock's trigger
/// never fires there because the pointer never arrives.
///
/// The anchor display is left completely untouched -- its bottom edge is
/// where the Dock actually lives.
public struct DockGuard: Sendable {
    /// Height in points of the reserved band along the bottom of each
    /// non-anchor display. Must exceed the Dock's own trigger depth.
    public let triggerHeight: CGFloat
    public let anchorID: CGDirectDisplayID
    public let displays: [DisplayRect]

    public init(anchorID: CGDirectDisplayID, displays: [DisplayRect], triggerHeight: CGFloat) {
        self.anchorID = anchorID
        self.displays = displays
        self.triggerHeight = triggerHeight
    }

    /// The display whose bounds contain `point`, if any.
    public func display(containing point: CGPoint) -> DisplayRect? {
        displays.first { $0.bounds.contains(point) }
    }

    public func decide(for point: CGPoint) -> GuardDecision {
        // Off every display: a transient the window server will resolve on its
        // own. Clamping against a guessed display would teleport the pointer.
        guard let screen = display(containing: point) else {
            return GuardDecision(location: point, didClamp: false)
        }

        // The Dock belongs here. Never interfere.
        guard screen.id != anchorID else {
            return GuardDecision(location: point, didClamp: false)
        }

        let limit = screen.bounds.maxY - triggerHeight
        guard point.y > limit else {
            return GuardDecision(location: point, didClamp: false)
        }

        // A guard band taller than the display would pin the pointer to the top
        // edge and make the display unusable. Refuse rather than mangle.
        guard limit >= screen.bounds.minY else {
            return GuardDecision(location: point, didClamp: false)
        }

        return GuardDecision(location: CGPoint(x: point.x, y: limit), didClamp: true)
    }
}
