/// Conformance group: policy. Contract section 5.

import XCTest

@testable import Localaze

private func accepts(_ held: String, _ offered: String, _ policy: LocalazeUpdatePolicy) -> Bool {
    LocalazeVersion.accepts(current: held, candidate: offered, policy: policy)
}

final class PolicyTests: XCTestCase {

    func testPatchAccepted() {
        XCTAssertTrue(accepts("1.0.0", "1.0.1", .minorAndPatch))
    }

    func testPatchAcceptedUnderPatchOnly() {
        XCTAssertTrue(accepts("1.0.0", "1.0.1", .patchOnly))
    }

    func testMinorAccepted() {
        XCTAssertTrue(accepts("1.0.0", "1.1.0", .minorAndPatch))
    }

    func testMinorRefusedUnderPatchOnly() {
        XCTAssertFalse(accepts("1.0.0", "1.1.0", .patchOnly))
    }

    func testMajorRefusedUnderEveryPolicy() {
        // The one rule no policy may override. LZ-62 defines major as
        // signature-breaking by construction.
        let policies: [LocalazeUpdatePolicy] = [
            .none, .patchOnly, .minorAndPatch, .range(from: "1.0.0", to: "1.2.0"),
        ]
        for policy in policies {
            XCTAssertFalse(accepts("1.0.0", "2.0.0", policy), policy.name)
        }

        // Even a range wide enough to contain it.
        XCTAssertFalse(accepts("1.0.0", "2.0.0", .range(from: "1.0.0", to: "9.9.9")))
    }

    func testNoneFetchesNothing() {
        // Not merely a refused result: no request is made at all.
        XCTAssertFalse(LocalazeUpdatePolicy.none.fetches)
        XCTAssertTrue(LocalazeUpdatePolicy.minorAndPatch.fetches)
    }

    func testDowngradeRefused() {
        XCTAssertFalse(accepts("1.1.0", "1.0.1", .minorAndPatch))
    }

    func testSameVersionIsUpToDate() {
        // accepts() still says no — there is nothing to take. The updater turns
        // that into upToDate rather than refusedByPolicy, which FetchTests
        // covers.
        XCTAssertFalse(accepts("1.0.0", "1.0.0", .minorAndPatch))
    }

    func testNumericComparison() {
        // String comparison would put 1.10.0 below 1.9.0.
        XCTAssertTrue(accepts("1.9.0", "1.10.0", .minorAndPatch))
        XCTAssertFalse(accepts("1.10.0", "1.9.0", .minorAndPatch))
        XCTAssertTrue(LocalazeVersion.parse("1.10.0")! > LocalazeVersion.parse("1.9.0")!)
    }

    func testMalformedVersionRefused() {
        for bad in ["latest", "2.0", "", "1.0.0-rc1", "x.y.z", "1.-1.0"] {
            XCTAssertNil(LocalazeVersion.parse(bad), bad)
            XCTAssertFalse(accepts("1.0.0", bad, .minorAndPatch), bad)
            XCTAssertFalse(accepts(bad, "1.0.1", .minorAndPatch), bad)
        }
    }

    func testRangeAcceptsInsideBounds() {
        let range = LocalazeUpdatePolicy.range(from: "1.0.0", to: "1.2.0")
        XCTAssertTrue(accepts("1.0.0", "1.1.0", range))
        XCTAssertTrue(accepts("1.0.0", "1.2.0", range))
        XCTAssertFalse(accepts("1.0.0", "1.3.0", range))
    }

    func testRangeRefusesMalformedBound() {
        XCTAssertFalse(
            accepts("1.0.0", "1.1.0", .range(from: "1.0", to: "latest")))
    }
}
