import XCTest
@testable import Ghostwriter

final class TypingDebouncerTests: XCTestCase {
    func testShortPauseFires() {
        let expectation = XCTestExpectation(description: "Short pause fires")
        let debouncer = TypingDebouncer(shortDelay: 0.1, longDelay: 0.5)
        debouncer.onShortPause = {
            expectation.fulfill()
        }

        debouncer.keystrokeReceived()
        wait(for: [expectation], timeout: 1.0)
        debouncer.stop()
    }

    func testLongPauseFires() {
        let expectation = XCTestExpectation(description: "Long pause fires")
        let debouncer = TypingDebouncer(shortDelay: 0.05, longDelay: 0.2)
        debouncer.onLongPause = {
            expectation.fulfill()
        }

        debouncer.keystrokeReceived()
        wait(for: [expectation], timeout: 1.0)
        debouncer.stop()
    }

    func testKeystrokeResetsTimers() {
        let shortExpectation = XCTestExpectation(description: "Short pause should not fire during typing")
        shortExpectation.isInverted = true

        let debouncer = TypingDebouncer(shortDelay: 0.5, longDelay: 1.0)
        debouncer.onShortPause = {
            shortExpectation.fulfill()
        }

        // Rapidly send keystrokes at 50ms intervals (total 200ms) — well under 500ms debounce
        for _ in 0..<4 {
            debouncer.keystrokeReceived()
            Thread.sleep(forTimeInterval: 0.05)
        }

        // Wait 300ms after last keystroke — still under 500ms debounce
        wait(for: [shortExpectation], timeout: 0.3)
        debouncer.stop()
    }

    func testCancelTimersPreventsCallbacks() {
        let shortExpectation = XCTestExpectation(description: "Short pause should not fire after cancel")
        shortExpectation.isInverted = true
        let longExpectation = XCTestExpectation(description: "Long pause should not fire after cancel")
        longExpectation.isInverted = true

        let debouncer = TypingDebouncer(shortDelay: 0.1, longDelay: 0.2)
        debouncer.onShortPause = { shortExpectation.fulfill() }
        debouncer.onLongPause = { longExpectation.fulfill() }

        debouncer.keystrokeReceived()
        debouncer.cancelTimers()

        wait(for: [shortExpectation, longExpectation], timeout: 0.5)
        debouncer.stop()
    }
}
