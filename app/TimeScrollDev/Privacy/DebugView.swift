import SwiftUI

struct DebugView: View {
    @State private var snapshotCount: Int = 0
    @State private var ftsCount: Int = 0
    @State private var rows: [DB.SnapshotRow] = []
    @State private var reindexing: Bool = false
    @State private var showMigrationDialog: Bool = false
    @State private var isMigrating: Bool = false
    @State private var migrationResult: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button("Refresh") { refresh() }
                Button("Reveal DB in Finder") { reveal() }
                Button("Clear FTS") { try? DB.shared.clearFTS(); refresh() }
                Button(reindexing ? "Reindexing…" : "Reindex from Files") {
                    reindexing = true
                    Task.detached(priority: .utility) {
                        Indexer.shared.rebuildFTSFromFiles()
                        await MainActor.run { reindexing = false; refresh() }
                    }
                }
                Button("Compact Older") {
                    Task.detached(priority: .utility) {
                        _ = try? Compactor().compactOlderSnapshots()
                        await MainActor.run { refresh() }
                    }
                }
                Menu("Migration fixes") {
                    Button("Update DB snapshot paths to current root") {
                        showMigrationDialog = true
                    }
                }
            }
            HStack {
                Text("Snapshots: \(snapshotCount)")
                Text("FTS rows: \(ftsCount)")
            }
            List(rows, id: \.self) { r in
                HStack {
                    Text("#\(r.id)")
                        .monospaced()
                    Text("\(Date(timeIntervalSince1970: TimeInterval(r.startedAtMs)/1000).description)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(r.path)
                        .lineLimit(1)
                        .font(.caption)
                }
            }
        }
        .padding()
        .onAppear { refresh() }
        .confirmationDialog("Update DB snapshot paths to the current storage root? This will rewrite the path and thumb_path columns for snapshots which appear to point at a different root.", isPresented: $showMigrationDialog, titleVisibility: .visible) {
            Button("Run", role: .destructive) {
                isMigrating = true
                Task.detached(priority: .utility) {
                    let updated = DB.shared.updateSnapshotPathsToCurrentRoot()
                    await MainActor.run {
                        isMigrating = false
                        migrationResult = "Updated \(updated) path/thumb entries"
                        refresh()
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        }
        .alert("Migration finished", isPresented: Binding(get: { migrationResult != nil }, set: { v in if !v { migrationResult = nil } })) {
            Button("OK", role: .cancel) { migrationResult = nil }
        } message: {
            Text(migrationResult ?? "")
        }
        .frame(minWidth: 700, minHeight: 400)
    }

    private func refresh() {
        snapshotCount = (try? DB.shared.snapshotCount()) ?? 0
        ftsCount = (try? DB.shared.ftsCount()) ?? 0
        rows = (try? DB.shared.listSnapshots(limit: 100)) ?? []
    }

    private func reveal() {
        guard let url = DB.shared.dbURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

