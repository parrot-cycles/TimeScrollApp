import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    static let shared = AppState()
    var isCapturing: Bool = false
    var lastSnapshotURL: URL?
    // Always increments for every snapshot row inserted so SwiftUI can react
    var lastSnapshotTick: Int = 0

    @ObservationIgnored let snapshotStore = SnapshotStore.shared
    @ObservationIgnored lazy var captureManager: CaptureManager = {
        let manager = CaptureManager { [weak self] url in
            Task { @MainActor in
                if !VaultManager.shared.isVaultEnabled || VaultManager.shared.isUnlocked {
                    self?.lastSnapshotURL = url
                    self?.lastSnapshotTick &+= 1
                }
            }
        }
        return manager
    }()

    func enforceRetention() {
        let days = SettingsStore.shared.retentionDays
        Task.detached {
            try? DB.shared.purgeOlderThan(days: days)
            DB.shared.pruneOldOCRBoxesIfConfigured()
            await MainActor.run {
                StorageMaintenanceManager.shared.runIfNeeded(forceMaintenance: true, afterLargeDelete: true)
            }
        }
    }

    func startCaptureIfNeeded() async {
        if isCapturing { return }
        Permissions.requestScreenRecording()
        try? await captureManager.start()
        isCapturing = true
        UsageTracker.shared.captureStarted()
    }

    func stopCaptureIfNeeded() async {
        if !isCapturing { return }
        await captureManager.stop()
        isCapturing = false
        UsageTracker.shared.captureStopped()
    }

    func restartCaptureIfRunning() async {
        if !isCapturing { return }
        await stopCaptureIfNeeded()
        await startCaptureIfNeeded()
    }
}
