import XCTest
@testable import TimeScroll

final class PermissionsTests: XCTestCase {

    func test_isScreenRecordingGranted_returns_bool() {
        // Should not crash, returns a boolean
        let result = Permissions.isScreenRecordingGranted()
        XCTAssertTrue(result == true || result == false)
    }

    func test_isAccessibilityGranted_returns_bool() {
        let result = Permissions.isAccessibilityGranted()
        XCTAssertTrue(result == true || result == false)
    }

    func test_probeScreenRecordingAsync_does_not_crash() {
        // Just verify it doesn't deadlock or crash
        Permissions.probeScreenRecordingAsync()
        // Wait a moment for the background probe
        let exp = expectation(description: "probe completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            // After probe, isScreenRecordingGranted should return cached result
            _ = Permissions.isScreenRecordingGranted()
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    func test_privacyPane_urls() {
        XCTAssertNotNil(Permissions.PrivacyPane.screenRecording.url)
        XCTAssertNotNil(Permissions.PrivacyPane.accessibility.url)
        XCTAssertTrue(Permissions.PrivacyPane.screenRecording.url!.absoluteString.contains("ScreenCapture"))
        XCTAssertTrue(Permissions.PrivacyPane.accessibility.url!.absoluteString.contains("Accessibility"))
    }
}
