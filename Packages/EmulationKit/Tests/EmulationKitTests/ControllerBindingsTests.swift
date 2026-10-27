import XCTest
@testable import EmulationKit

final class ControllerBindingsTests: XCTestCase {
    func testDefaultsAndSwapPersist() {
        var bindings = ControllerBindings()
        XCTAssertEqual(bindings[.south], .b)
        XCTAssertEqual(bindings[.east], .a)
        bindings.assign(.a, to: .south)
        XCTAssertEqual(bindings[.south], .a)
        XCTAssertEqual(bindings[.east], .b)
        let restored = ControllerBindings(serialized: bindings.serialized)
        XCTAssertEqual(restored[.south], .a)
        XCTAssertEqual(restored[.east], .b)
    }

    func testInvalidStoredValuesUseDefaults() {
        let bindings = ControllerBindings(serialized: "[\"a\",\"a\"]")
        XCTAssertEqual(bindings[.south], .b)
        XCTAssertEqual(bindings[.east], .a)
    }
}
