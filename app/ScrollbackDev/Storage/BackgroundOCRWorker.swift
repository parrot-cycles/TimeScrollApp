import Foundation
import CoreVideo

/// Processes un-OCR'd snapshots in the background at low priority.
/// Replaces the inline OCR that previously ran on every captured frame.
final class BackgroundOCRWorker {
    static let shared = BackgroundOCRWorker()

    private let workQueue = DispatchQueue(label: "Scrollback.BackgroundOCR", qos: .background)
    private let ocr = OCRService()
    private var running = false
    private let lock = NSLock()

    private let batchSize = 20
    private let interItemDelay: TimeInterval = 0.5

    private init() {}

    /// Process a batch of snapshots that need OCR. Safe to call from any thread.
    func processNextBatch() {
        lock.lock()
        guard !running else { lock.unlock(); return }
        running = true
        lock.unlock()

        workQueue.async { [weak self] in
            defer {
                self?.lock.lock()
                self?.running = false
                self?.lock.unlock()
            }
            self?.runBatch()
        }
    }

    private func runBatch() {
        // Bail under thermal pressure
        let thermal = ProcessInfo.processInfo.thermalState
        guard thermal != .serious && thermal != .critical else { return }

        guard let rows = try? DB.shared.snapshotsPendingOCR(limit: batchSize), !rows.isEmpty else { return }

        let debugMode = UserDefaults.standard.bool(forKey: "settings.debugMode")
        if debugMode {
            print("[BackgroundOCR] Starting batch of \(rows.count) snapshots")
        }

        for row in rows {
            // Re-check thermal between items
            let state = ProcessInfo.processInfo.thermalState
            if state == .serious || state == .critical { break }

            autoreleasepool {
                guard let pixelBuffer = SnapshotImageLoader.loadPixelBuffer(for: row) else {
                    if debugMode { print("[BackgroundOCR] Could not load image for snapshot \(row.id)") }
                    return
                }

                do {
                    let result = try ocr.recognize(from: pixelBuffer)
                    try DB.shared.updateFTS(rowId: row.id, content: result.text)
                    if !result.lines.isEmpty {
                        try DB.shared.replaceBoxes(snapshotId: row.id, boxes: result.lines)
                    }
                    // Generate embedding in the same pass (image already loaded)
                    SnapshotEmbeddingWriter.shared.storeCurrentEmbeddingIfNeeded(
                        snapshotId: row.id,
                        pixelBuffer: pixelBuffer,
                        extractedText: result.text
                    )
                    if debugMode { print("[BackgroundOCR] Completed snapshot \(row.id)") }
                } catch {
                    if debugMode { print("[BackgroundOCR] Error on snapshot \(row.id): \(error)") }
                }
            }

            // Throttle to avoid sustained CPU spikes
            Thread.sleep(forTimeInterval: interItemDelay)
        }
    }
}
