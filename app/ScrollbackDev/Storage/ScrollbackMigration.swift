import Foundation

/// One-time migration from the upstream TimeScroll fork paths to Scrollback paths.
///
/// Changes v2.0.x → v2.1.0:
/// - App Support shared dir: `TimeScrollShared/` → `ScrollbackShared/`
/// - Data dir within it:     `TimeScroll/`       → `Scrollback/`
/// - Uses COPY (not move) — original data stays intact as a backup.
///
/// This runs once, guarded by a UserDefaults flag. If interrupted or if copy fails
/// partway, the flag is NOT set; next launch re-attempts. The app continues with
/// whatever data it can find.
enum ScrollbackMigration {
    private static let completionFlag = "scrollback.migration.v2_1.done"
    private static let migrationFailedFlag = "scrollback.migration.v2_1.failed"

    /// Call this very early in app startup, before any StoragePaths.defaultRoot() usage.
    static func runIfNeeded() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: completionFlag) {
            return
        }

        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!

        let oldSharedRoot = appSupport.appendingPathComponent("TimeScrollShared", isDirectory: true)
        let newSharedRoot = appSupport.appendingPathComponent("ScrollbackShared", isDirectory: true)

        let oldDataDir = oldSharedRoot.appendingPathComponent("TimeScroll", isDirectory: true)
        let newDataDir = newSharedRoot.appendingPathComponent("Scrollback", isDirectory: true)

        let needsMigration = fm.fileExists(atPath: oldDataDir.path)
        guard needsMigration else {
            // Fresh install — nothing to migrate.
            defaults.set(true, forKey: completionFlag)
            return
        }

        // If the new location already has data (e.g. user partially migrated, reinstalled),
        // skip the copy and just rewrite DB paths.
        let newAlreadyPopulated = fm.fileExists(atPath: newDataDir.appendingPathComponent("db.sqlite").path)

        fputs("[ScrollbackMigration] Starting migration. old=\(oldDataDir.path) new=\(newDataDir.path) newAlreadyPopulated=\(newAlreadyPopulated)\n", stderr)

        if !newAlreadyPopulated {
            do {
                try fm.createDirectory(at: newSharedRoot, withIntermediateDirectories: true)
                // Copy the inner data dir from TimeScrollShared/TimeScroll → ScrollbackShared/Scrollback
                try fm.copyItem(at: oldDataDir, to: newDataDir)
                fputs("[ScrollbackMigration] Copied data dir\n", stderr)
            } catch {
                fputs("[ScrollbackMigration] FAILED to copy data dir: \(error)\n", stderr)
                defaults.set(true, forKey: migrationFailedFlag)
                // Don't set completion flag — retry next launch
                return
            }

            // Copy sibling folders (Logs, Shared state) if they exist
            for sibling in ["Logs", "Shared"] {
                let oldSibling = oldSharedRoot.appendingPathComponent(sibling, isDirectory: true)
                let newSibling = newSharedRoot.appendingPathComponent(sibling, isDirectory: true)
                if fm.fileExists(atPath: oldSibling.path) && !fm.fileExists(atPath: newSibling.path) {
                    try? fm.copyItem(at: oldSibling, to: newSibling)
                    fputs("[ScrollbackMigration] Copied \(sibling)\n", stderr)
                }
            }
        }

        // Copy legacy MobileCLIP models: Application Support/TimeScroll → Application Support/Scrollback
        let oldMobileCLIPRoot = appSupport.appendingPathComponent("TimeScroll", isDirectory: true)
        let newMobileCLIPRoot = appSupport.appendingPathComponent("Scrollback", isDirectory: true)
        if fm.fileExists(atPath: oldMobileCLIPRoot.path) && !fm.fileExists(atPath: newMobileCLIPRoot.path) {
            try? fm.copyItem(at: oldMobileCLIPRoot, to: newMobileCLIPRoot)
            fputs("[ScrollbackMigration] Copied MobileCLIP models dir\n", stderr)
        }

        // Rewrite absolute paths in shared UserDefaults (settings.storageFolderPath),
        // the storage display path shown in Preferences.
        let oldPrefix = oldDataDir.path + "/"
        let oldExact = oldDataDir.path

        if let stored = StoragePaths.sharedString(forKey: StoragePaths.storageDisplayPathKey) {
            if stored == oldExact || stored.hasPrefix(oldPrefix) {
                let rewritten = stored == oldExact ? newDataDir.path : newDataDir.path + String(stored.dropFirst(oldExact.count))
                StoragePaths.setShared(rewritten, forKey: StoragePaths.storageDisplayPathKey)
                fputs("[ScrollbackMigration] Rewrote storageDisplayPath: \(rewritten)\n", stderr)
            }
        }

        // Rewrite DB rows (path, thumb_path) from old prefix → new prefix.
        // DB is opened fresh at the new location; we rewrite before any reads.
        do {
            try DB.shared.openIfNeeded()
            DB.shared.updateSnapshotPathsAfterRootMove(oldRoot: oldExact, newRoot: newDataDir.path)
        } catch {
            fputs("[ScrollbackMigration] WARN: DB rewrite failed: \(error)\n", stderr)
            // Non-fatal — app can open DB normally, paths may need a manual "Update DB paths" from Debug menu
        }

        defaults.set(true, forKey: completionFlag)
        defaults.set(false, forKey: migrationFailedFlag)
        fputs("[ScrollbackMigration] Completed. Old data preserved at \(oldDataDir.path) as backup.\n", stderr)
    }

    /// For debugging: reset the migration flag so next launch re-runs migration.
    static func resetMigrationFlagForDebug() {
        UserDefaults.standard.removeObject(forKey: completionFlag)
        UserDefaults.standard.removeObject(forKey: migrationFailedFlag)
    }
}
