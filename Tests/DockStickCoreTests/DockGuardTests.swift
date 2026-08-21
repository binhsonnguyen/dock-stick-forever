import XCTest
import CoreGraphics
@testable import DockStickCore

final class DockGuardTests: XCTestCase {

    // Real geometry of this machine, read from CGDisplayBounds: the built-in
    // Retina panel is main and therefore anchored at the origin, with the
    // Samsung 1080p to its right, nudged up so the two bottom edges line up.
    // That shared maxY is the interesting part -- both displays end at y=982,
    // so the guard must separate them by identity, not by height.
    private let builtIn = DisplayRect(
        id: 1,
        bounds: CGRect(x: 0, y: 0, width: 1512, height: 982)
    )
    private let external = DisplayRect(
        id: 2,
        bounds: CGRect(x: 1512, y: -98, width: 1920, height: 1080)
    )

    private func makeGuard(anchor: CGDirectDisplayID, band: CGFloat = 4) -> DockGuard {
        DockGuard(anchorID: anchor, displays: [builtIn, external], triggerHeight: band)
    }

    func testPointerDeepInsideExternalDisplayIsUntouched() {
        let sut = makeGuard(anchor: 1)
        let point = CGPoint(x: 2200, y: 400)
        let decision = sut.decide(for: point)
        XCTAssertFalse(decision.didClamp)
        XCTAssertEqual(decision.location, point)
    }

    func testPointerAtBottomEdgeOfExternalDisplayIsPulledBack() {
        let sut = makeGuard(anchor: 1)
        // Bottom row of the external display is y = 981 (maxY is exclusive).
        let decision = sut.decide(for: CGPoint(x: 2200, y: 981))
        XCTAssertTrue(decision.didClamp)
        XCTAssertEqual(decision.location.y, 978, "should sit on the band boundary")
        XCTAssertEqual(decision.location.x, 2200, "horizontal motion must survive")
    }

    func testClampPreservesHorizontalFreedom() {
        let sut = makeGuard(anchor: 1)
        let left = sut.decide(for: CGPoint(x: 1520, y: 981))
        let right = sut.decide(for: CGPoint(x: 3400, y: 981))
        XCTAssertEqual(left.location.x, 1520)
        XCTAssertEqual(right.location.x, 3400)
        XCTAssertTrue(left.didClamp)
        XCTAssertTrue(right.didClamp)
    }

    func testAnchorDisplayBottomEdgeIsNeverClamped() {
        let sut = makeGuard(anchor: 1)
        // The Dock lives here; reaching this edge must keep working.
        let decision = sut.decide(for: CGPoint(x: 700, y: 981))
        XCTAssertFalse(decision.didClamp)
        XCTAssertEqual(decision.location, CGPoint(x: 700, y: 981))
    }

    func testSwitchingAnchorMovesTheGuardedBand() {
        let sut = makeGuard(anchor: 2)
        // Now the external panel is home and the built-in gets guarded.
        XCTAssertFalse(sut.decide(for: CGPoint(x: 2200, y: 981)).didClamp)

        let decision = sut.decide(for: CGPoint(x: 700, y: 981))
        XCTAssertTrue(decision.didClamp)
        XCTAssertEqual(decision.location.y, 978)
    }

    func testPointExactlyOnBandBoundaryIsAllowed() {
        let sut = makeGuard(anchor: 1)
        // y == limit is the resting spot after a clamp; it must be stable or
        // the tap would fight itself every event.
        let decision = sut.decide(for: CGPoint(x: 2200, y: 978))
        XCTAssertFalse(decision.didClamp)
    }

    func testPointOutsideEveryDisplayIsUntouched() {
        let sut = makeGuard(anchor: 1)
        let orphan = CGPoint(x: 9000, y: 9000)
        let decision = sut.decide(for: orphan)
        XCTAssertFalse(decision.didClamp)
        XCTAssertEqual(decision.location, orphan)
    }

    func testAbsurdlyTallBandIsRefusedRatherThanPinningPointer() {
        let sut = makeGuard(anchor: 1, band: 5000)
        let point = CGPoint(x: 2200, y: 400)
        let decision = sut.decide(for: point)
        XCTAssertFalse(decision.didClamp)
        XCTAssertEqual(decision.location, point)
    }

    func testFastFlickStraightIntoTheEdgeIsStillCaught() {
        // Event taps see discrete samples; a fast throw can jump from mid-screen
        // to the last row in one event. Clamping is positional, so it holds.
        let sut = makeGuard(anchor: 1)
        let decision = sut.decide(for: CGPoint(x: 2900, y: 981))
        XCTAssertTrue(decision.didClamp)
        XCTAssertEqual(decision.location.y, 978)
    }
}
