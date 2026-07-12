import Foundation
import SwiftWABackupAPI

struct BackupInspectionRow: Identifiable {
    enum WhatsAppState {
        case present
        case absent
        case unknown
    }

    let id: String
    let path: String
    let creationDate: Date?
    let encryptionState: Bool?
    let whatsAppState: WhatsAppState
    let detail: String?
    let iPhoneBackup: IPhoneBackup?

    var canCreateLibrary: Bool {
        iPhoneBackup != nil && encryptionState == false
    }

    init(info: IPhoneBackupDiscoveryInfo) {
        id = info.identifier
        path = info.path
        creationDate = info.creationDate
        encryptionState = info.isEncrypted
        detail = info.issue
        iPhoneBackup = info.isReady ? info.iPhoneBackup : nil

        switch info.status {
        case .ready, .encrypted, .encryptionStatusUnavailable:
            whatsAppState = .present
        case .missingWhatsAppDatabase:
            whatsAppState = .absent
        case .missingRequiredFile, .malformedStatusPlist, .unreadableManifestDatabase, .unreadableBackup:
            whatsAppState = .unknown
        }
    }
}
