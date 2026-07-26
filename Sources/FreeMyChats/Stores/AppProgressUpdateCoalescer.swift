import Foundation
import SwiftWABackupAPI

/// Keeps high-frequency API progress callbacks from producing an unbounded
/// queue of main-thread and SwiftUI updates.
final class AppProgressUpdateCoalescer: @unchecked Sendable {
    struct Update {
        let progress: WABackupProgress
        let operationID: UUID
        let fallbackTitle: String
    }

    private let lock = NSLock()
    private var latestUpdate: Update?
    private var deliveryScheduled = false

    /// Stores the latest value and returns true only when the caller must
    /// schedule a delivery. Until that delivery drains the value, further
    /// submissions replace it instead of allocating more dispatch blocks.
    func submit(_ update: Update) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        latestUpdate = update
        guard !deliveryScheduled else { return false }
        deliveryScheduled = true
        return true
    }

    func takeLatest() -> Update? {
        lock.lock()
        defer { lock.unlock() }

        let update = latestUpdate
        latestUpdate = nil
        deliveryScheduled = false
        return update
    }
}
