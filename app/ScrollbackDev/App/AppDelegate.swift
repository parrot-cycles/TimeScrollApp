import Foundation
import AppKit
#if canImport(Sparkle)
import Sparkle
#endif

// Windows: helper to ignore the status bar host window when deciding whether
// the app currently has a user-facing window. The status item always keeps an
// NSStatusBarWindow alive and visible, which would otherwise prevent us from
// hiding the Dock icon.
extension NSApplication {
    var ts_hasVisibleUserWindow: Bool {
        let statusBarWindowClass: AnyClass? = NSClassFromString("NSStatusBarWindow")
        return windows.contains { window in
            guard window.isVisible else { return false }
            // Exclude the system status bar host window and any other status-bar-level windows
            if let cls = statusBarWindowClass, window.isKind(of: cls) { return false }
            if window.level == .statusBar { return false }
            return true
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var prefsWC: NSWindowController?
    var mainWC: NSWindowController?
    var onboardingWC: NSWindowController?
    var updateNotiTokens: [NSObjectProtocol] = []
    var powerNotiTokens: [NSObjectProtocol] = []
    var lastWakeRestartAt: TimeInterval = 0
    #if canImport(Sparkle)
    var updaterController: SPUStandardUpdaterController!
    var updatesDelegate: UpdatesDelegate!
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[App] applicationDidFinishLaunching")
        let bundleId = Bundle.main.bundleIdentifier ?? "(nil)"
        let lib = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?.path ?? "(unknown)"
        print("[Prefs] Launch bundle=\(bundleId) libraryDir=\(lib)")
        // Seed App Group defaults so the MCP helper can see storage bookmarks/paths immediately
        StoragePaths.syncSharedDefaultsFromStandard()
        setupStatusItem()

        // Probe actual screen recording permission in background (works for ad-hoc signed builds)
        Permissions.probeScreenRecordingAsync()

        // Sparkle updater (if available)
        #if canImport(Sparkle)
        updatesDelegate = UpdatesDelegate()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: updatesDelegate,
            userDriverDelegate: nil
        )
        print("[Sparkle] SPUStandardUpdaterController initialized")
        applySparklePrefsFromSettings()
        // Optional: initial background check shortly after launch
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard self != nil else { return }
            if SettingsStore.sharedEnableAutoCheckUpdatesSnapshot() {
                updaterController.updater.checkForUpdatesInBackground()
                print("[Sparkle] Scheduled initial background update check")
            }
        }
        #endif

        // Apply start-minimized and dock visibility policy
        Task { @MainActor [weak self] in
            // Load vault prefs
            VaultManager.shared.loadPrefs()
            self?.applyStartMinimizedIfNeeded()
            self?.updateActivationPolicy()
            self?.installSettingsObservers()
            self?.installWindowObservers()
            self?.installUpdateNotificationObservers()
            self?.installSleepWakeObservers()
            StorageMaintenanceManager.shared.start()
            // Show onboarding if permissions are missing; otherwise open the main window
            // and honor auto-start. Respect startMinimized preference (menu-bar-only launch).
            let startMin = UserDefaults.standard.object(forKey: "settings.startMinimized") != nil
                ? UserDefaults.standard.bool(forKey: "settings.startMinimized")
                : false
            if !Permissions.isScreenRecordingGranted() {
                self?.showOnboardingWindow()
            } else {
                if !startMin { self?.showMainWindow() }
                self?.applyAutoStartCaptureIfNeeded()
            }
            // Prompt unlock if vault is enabled
            if SettingsStore.shared.vaultEnabled {
                Task { await VaultManager.shared.unlock(presentingWindow: NSApp.keyWindow) }
            }
        }
    }

    deinit {
        for token in updateNotiTokens { NotificationCenter.default.removeObserver(token) }
        updateNotiTokens.removeAll()
        for token in powerNotiTokens { NotificationCenter.default.removeObserver(token) }
        powerNotiTokens.removeAll()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if SettingsStore.shared.vaultEnabled {
            VaultManager.shared.lock()
        }
        SettingsStore.shared.flush()
        // Ensure any open HEVC writers are flushed (best-effort with timeout)
        HEVCVideoStore.shared.shutdown(timeout: 2.0)
        StorageMaintenanceManager.shared.stop()
        UsageTracker.shared.appWillTerminate()
        UserDefaults.standard.synchronize()
    }
}
