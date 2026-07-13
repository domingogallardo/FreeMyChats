import Foundation
import SwiftWABackupAPI

enum BackupDiscoveryIssue: Equatable {
    case permissionRequired
    case unreadableDirectory(String)

    init(error: Error) {
        if Self.containsPermissionError(error) {
            self = .permissionRequired
        } else {
            self = .unreadableDirectory(error.localizedDescription)
        }
    }

    private static func containsPermissionError(_ error: Error, depth: Int = 0) -> Bool {
        guard depth < 6 else { return false }

        if let backupError = error as? BackupError,
           case .directoryAccess(let underlying) = backupError {
            return containsPermissionError(underlying, depth: depth + 1)
        }

        let nsError = error as NSError
        let cocoaPermissionCodes = [
            CocoaError.Code.fileReadNoPermission.rawValue,
            CocoaError.Code.fileWriteNoPermission.rawValue
        ]
        if nsError.domain == NSCocoaErrorDomain,
           cocoaPermissionCodes.contains(nsError.code) {
            return true
        }

        // EPERM and EACCES are the two POSIX results normally surfaced by TCC.
        if nsError.domain == NSPOSIXErrorDomain,
           nsError.code == 1 || nsError.code == 13 {
            return true
        }

        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return containsPermissionError(underlying, depth: depth + 1)
        }
        return false
    }
}

struct ImportedIPhoneBackupCleanupPrompt: Identifiable {
    let sourceURL: URL
    let creationDate: Date?

    var id: String { sourceURL.standardizedFileURL.path }
}
