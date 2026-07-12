import Foundation
@preconcurrency import SwiftWABackupAPI

struct LibraryPaths: Equatable {
    let rootURL: URL
    let backupURL: URL
    let exportsURL: URL

    init(rootURL: URL) {
        let standardizedRoot = rootURL.standardizedFileURL
        self.rootURL = standardizedRoot
        self.backupURL = standardizedRoot.appendingPathComponent("Backup", isDirectory: true)
        self.exportsURL = standardizedRoot.appendingPathComponent("Exports", isDirectory: true)
    }

    static func resolvingSelection(_ selectedURL: URL) -> LibraryPaths {
        let selected = selectedURL.standardizedFileURL
        let metadataAtSelection = selected
            .appendingPathComponent(".wa-backup", isDirectory: true)
            .appendingPathComponent("backup-info.json")

        if FileManager.default.fileExists(atPath: metadataAtSelection.path) {
            return LibraryPaths(rootURL: selected.deletingLastPathComponent())
        }

        return LibraryPaths(rootURL: selected)
    }
}

final class LibrarySession: @unchecked Sendable {
    let paths: LibraryPaths
    let backup: ExtractedWhatsAppBackup
    let reader: WhatsAppBackupReader
    let info: ExtractedWhatsAppBackupInfo
    var chats: [ChatInfo]

    init(
        paths: LibraryPaths,
        backup: ExtractedWhatsAppBackup,
        reader: WhatsAppBackupReader,
        info: ExtractedWhatsAppBackupInfo,
        chats: [ChatInfo]
    ) {
        self.paths = paths
        self.backup = backup
        self.reader = reader
        self.info = info
        self.chats = chats
    }
}

enum ChatListFilter: String, CaseIterable, Identifiable {
    case all
    case groups
    case people
    case archived

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Todos"
        case .groups: return "Grupos"
        case .people: return "Personas"
        case .archived: return "Archivados"
        }
    }
}

enum ChatExportDisplayState: Equatable {
    case checking
    case notExported
    case exported(Date)
    case stale(Date)
    case invalid(String)

    init(_ state: ChatExportState) {
        switch state {
        case .notExported:
            self = .notExported
        case .exported(let info):
            self = .exported(info.exportedAt)
        case .stale(let info):
            self = .stale(info.exportedAt)
        case .invalid(let reason):
            self = .invalid(reason)
        }
    }

    var isPhysicallyExported: Bool {
        switch self {
        case .exported, .stale, .invalid: return true
        case .checking, .notExported: return false
        }
    }
}

struct AppOperation: Equatable {
    enum Kind: Equatable {
        case discovering
        case creatingLibrary
        case openingLibrary
        case loadingChats
        case exportingChat(Int)
        case openingChat(Int)
    }

    let id: UUID
    let kind: Kind
    var title: String
    var detail: String?
    var fractionCompleted: Double?
}
