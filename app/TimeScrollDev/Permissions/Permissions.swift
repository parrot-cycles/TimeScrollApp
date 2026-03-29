import Foundation
import CoreGraphics
import AppKit
import ApplicationServices
import ScreenCaptureKit

enum Permissions {
    enum PrivacyPane {
        case screenRecording
        case accessibility

        var url: URL? {
            switch self {
            case .screenRecording:
                return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
            case .accessibility:
                return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            }
        }
    }

    // MARK: - Cached async probe for Screen Recording

    private static var _screenRecordingProbeResult: Bool?
    private static let probeQueue = DispatchQueue(label: "TimeScroll.PermissionProbe")

    /// Call once on app launch to probe actual screen recording access in the background.
    /// The result is cached and used by isScreenRecordingGranted().
    static func probeScreenRecordingAsync() {
        probeQueue.async {
            let semaphore = DispatchSemaphore(value: 0)
            var result = false
            Task.detached {
                do {
                    _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                    result = true
                } catch {
                    result = false
                }
                semaphore.signal()
            }
            semaphore.wait()
            _screenRecordingProbeResult = result
        }
    }

    /// Re-probe (called by refresh buttons). Non-blocking — updates cached result.
    static func reprobeScreenRecording() {
        probeScreenRecordingAsync()
    }

    static func isAccessibilityGranted() -> Bool {
        return AXIsProcessTrusted()
    }

    /// Triggers the system prompt to grant Accessibility access; also opens Settings.
    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeRetainedValue() as String
        let opts: NSDictionary = [key: true]
        _ = AXIsProcessTrustedWithOptions(opts)
        _ = open(.accessibility)
    }

    static func isScreenRecordingGranted() -> Bool {
        // 1. Standard API check (works for properly signed apps)
        if CGPreflightScreenCaptureAccess() { return true }
        // 2. Cached probe result from actual SCShareableContent call
        //    (works for ad-hoc signed apps where CGPreflight lies)
        if let cached = _screenRecordingProbeResult { return cached }
        // 3. Not yet probed — return false, probe will update soon
        return false
    }

    /// Triggers the system prompt (if possible) to request Screen Recording access.
    /// Falls back to opening the System Settings privacy pane.
    static func requestScreenRecording() {
        let granted = CGPreflightScreenCaptureAccess()
        if !granted {
            _ = CGRequestScreenCaptureAccess()
            open(.screenRecording)
        }
    }

    /// Opens the specific System Settings privacy pane for the given case.
    @discardableResult
    static func open(_ pane: PrivacyPane) -> Bool {
        guard let url = pane.url else { return false }
        return NSWorkspace.shared.open(url)
    }
}
