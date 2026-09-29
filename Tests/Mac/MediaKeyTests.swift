import AppKit
import XCTest
@testable import MultiOutputVolume

final class MediaKeyTests: XCTestCase {
    @MainActor func testNativeEventsAndOrdinaryKeys() async throws {
        let monitor = MediaKeyMonitor()
        var actions: [VolumeKeyAction] = []
        let delivered = expectation(description: "native action delivered")
        monitor.onAction = { action, _ in actions.append(action); delivered.fulfill() }
        let ordinary = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 109, keyDown: true))
        XCTAssertNotNil(monitor.handle(event: ordinary, type: .keyDown))
        let press = try XCTUnwrap(NSEvent.otherEvent(with: .systemDefined, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            subtype: 8, data1: 0x0A00, data2: -1)?.cgEvent)
        XCTAssertNil(monitor.handle(event: press, type: CGEventType(rawValue: 14)!))
        let release = try XCTUnwrap(NSEvent.otherEvent(with: .systemDefined, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            subtype: 8, data1: 0x0B00, data2: -1)?.cgEvent)
        XCTAssertNil(monitor.handle(event: release, type: CGEventType(rawValue: 14)!))
        let modified = try XCTUnwrap(NSEvent.otherEvent(with: .systemDefined, location: .zero,
            modifierFlags: [.command], timestamp: 0, windowNumber: 0, context: nil,
            subtype: 8, data1: 0x0A00, data2: -1)?.cgEvent)
        XCTAssertNotNil(monitor.handle(event: modified, type: CGEventType(rawValue: 14)!))
        await fulfillment(of: [delivered], timeout: 1)
        XCTAssertEqual(actions, [.increase])
    }
}
