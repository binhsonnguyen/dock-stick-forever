import AppKit
import CoreGraphics
import DockStickCore

/// Snapshot of the attached displays, refreshed whenever the layout changes.
///
/// Displays are identified by UUID rather than `CGDirectDisplayID` because IDs
/// are reassigned across sleep, cable swaps and reboots -- an anchor stored by
/// ID would silently start guarding the wrong panel.
struct DisplayInfo {
    let id: CGDirectDisplayID
    let uuid: String
    let name: String
    let bounds: CGRect
    let isMain: Bool
}

enum DisplayInventory {

    static func uuid(for id: CGDirectDisplayID) -> String? {
        guard let ref = CGDisplayCreateUUIDFromDisplayID(id) else { return nil }
        let cf = ref.takeRetainedValue()
        return CFUUIDCreateString(nil, cf) as String?
    }

    static func current() -> [DisplayInfo] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }

        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }

        let names = screenNames()

        return ids.prefix(Int(count)).map { id in
            DisplayInfo(
                id: id,
                uuid: uuid(for: id) ?? "display-\(id)",
                name: names[id] ?? "Display \(id)",
                bounds: CGDisplayBounds(id),
                isMain: CGDisplayIsMain(id) != 0
            )
        }
    }

    /// `CGDisplay` has no name API, so borrow AppKit's and key it back by ID.
    private static func screenNames() -> [CGDirectDisplayID: String] {
        var map: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber else { continue }
            map[CGDirectDisplayID(number.uint32Value)] = screen.localizedName
        }
        return map
    }

    static func rects(from displays: [DisplayInfo]) -> [DisplayRect] {
        displays.map { DisplayRect(id: $0.id, bounds: $0.bounds) }
    }
}
