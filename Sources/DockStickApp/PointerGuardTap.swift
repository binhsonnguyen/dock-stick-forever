import AppKit
import CoreGraphics
import DockStickCore

/// Installs a session-level event tap and rewrites pointer locations that
/// would otherwise hand the Dock to a non-anchored display.
///
/// The tap sits at the head of the session queue, so the rewritten location is
/// what the window server -- and therefore the Dock -- ends up seeing.
@MainActor
final class PointerGuardTap {

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Read by the tap callback on every pointer sample, so it is rebuilt on
    /// display or setting changes rather than recomputed per event.
    private(set) var guardModel: DockGuard?

    private(set) var displays: [DisplayInfo] = []

    /// Raised when the tap is torn down by the system and cannot be restarted.
    var onFailure: ((String) -> Void)?
    /// Raised after the display layout changes so the UI can rebuild its menu.
    var onDisplaysChanged: (() -> Void)?

    var isRunning: Bool { tap != nil }

    // MARK: - Lifecycle

    func start() -> Bool {
        guard tap == nil else { return true }

        refreshDisplays()

        let mask: CGEventMask =
            (1 << CGEventType.mouseMoved.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.rightMouseDragged.rawValue) |
            (1 << CGEventType.otherMouseDragged.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, refcon in
                PointerGuardTap.handle(proxy: proxy, type: type, event: event, refcon: refcon)
            },
            userInfo: refcon
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        tap = port
        runLoopSource = source

        registerDisplayCallback()
        return true
    }

    func stop() {
        if let port = tap {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        unregisterDisplayCallback()
    }

    // MARK: - Model

    func refreshDisplays() {
        displays = DisplayInventory.current()
        rebuildGuard()
    }

    func rebuildGuard() {
        guard Settings.isEnabled, displays.count > 1 else {
            // A single display has nowhere to steal the Dock to.
            guardModel = nil
            return
        }

        let anchor = resolvedAnchor()
        guardModel = DockGuard(
            anchorID: anchor.id,
            displays: DisplayInventory.rects(from: displays),
            triggerHeight: Settings.triggerHeight
        )
    }

    /// The stored anchor, falling back to the main display when the saved one
    /// is unplugged -- guarding every display would trap the pointer.
    func resolvedAnchor() -> DisplayInfo {
        if let uuid = Settings.anchorUUID,
           let match = displays.first(where: { $0.uuid == uuid }) {
            return match
        }
        return displays.first(where: { $0.isMain }) ?? displays[0]
    }

    // MARK: - Event handling

    /// What the tap should do with a pointer sample. Deliberately made of
    /// `Sendable` values only, so the non-Sendable `CGEvent` never has to cross
    /// the actor boundary.
    private enum TapAction: Sendable {
        case passthrough
        case clamp(CGPoint, warp: Bool)
    }

    private nonisolated static func handle(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent,
        refcon: UnsafeMutableRawPointer?
    ) -> Unmanaged<CGEvent>? {
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let owner = Unmanaged<PointerGuardTap>.fromOpaque(refcon).takeUnretainedValue()

        let location = event.location

        // The tap callback is serviced by the main run loop, which is where the
        // source was installed, so main-actor state is safe to touch here.
        let action = MainActor.assumeIsolated {
            owner.decide(type: type, location: location)
        }

        switch action {
        case .passthrough:
            break
        case let .clamp(point, warp):
            event.location = point
            if warp {
                // Warping to the boundary is idempotent: the resulting sample
                // sits outside the guarded band, so it cannot feed back.
                CGWarpMouseCursorPosition(point)
                CGAssociateMouseAndMouseCursorPosition(1)
            }
        }

        return Unmanaged.passUnretained(event)
    }

    private func decide(type: CGEventType, location: CGPoint) -> TapAction {
        // The system disables a tap that blocks for too long, or when the user
        // revokes input access. Re-arming keeps the guard alive.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port = tap {
                CGEvent.tapEnable(tap: port, enable: true)
            } else {
                onFailure?("Event tap bị hệ thống tắt và không bật lại được.")
            }
            return .passthrough
        }

        guard let model = guardModel else { return .passthrough }

        let decision = model.decide(for: location)
        guard decision.didClamp else { return .passthrough }

        return .clamp(decision.location, warp: Settings.warpFallback)
    }

    // MARK: - Display reconfiguration

    private var displayCallbackRegistered = false

    fileprivate func handleDisplayReconfiguration() {
        refreshDisplays()
        onDisplaysChanged?()
    }

    private func registerDisplayCallback() {
        guard !displayCallbackRegistered else { return }
        CGDisplayRegisterReconfigurationCallback(
            dockStickDisplayReconfigured,
            Unmanaged.passUnretained(self).toOpaque()
        )
        displayCallbackRegistered = true
    }

    private func unregisterDisplayCallback() {
        guard displayCallbackRegistered else { return }
        // Must be the same function pointer and refcon used at registration,
        // otherwise CoreGraphics keeps calling into a dead object.
        CGDisplayRemoveReconfigurationCallback(
            dockStickDisplayReconfigured,
            Unmanaged.passUnretained(self).toOpaque()
        )
        displayCallbackRegistered = false
    }
}

/// Top-level so register/remove pass an identical C function pointer.
private func dockStickDisplayReconfigured(
    _ display: CGDirectDisplayID,
    _ flags: CGDisplayChangeSummaryFlags,
    _ userInfo: UnsafeMutableRawPointer?
) {
    guard let userInfo else { return }
    // Ignore the "about to change" pass; bounds are still stale there.
    guard !flags.contains(.beginConfigurationFlag) else { return }
    let owner = Unmanaged<PointerGuardTap>.fromOpaque(userInfo).takeUnretainedValue()
    Task { @MainActor in
        owner.handleDisplayReconfiguration()
    }
}
