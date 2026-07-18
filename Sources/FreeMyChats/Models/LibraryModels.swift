import Foundation
@preconcurrency import SwiftWABackupAPI

struct LibraryPaths: Equatable {
    let rootURL: URL
    let sourcesURL: URL
    let exportsURL: URL
    let mergedChatsURL: URL
    let manifestURL: URL

    init(rootURL: URL) {
        let root = rootURL.standardizedFileURL
        self.rootURL = root
        self.sourcesURL = root.appendingPathComponent("Sources", isDirectory: true)
        self.exportsURL = root.appendingPathComponent("Exports", isDirectory: true)
        self.mergedChatsURL = root.appendingPathComponent("MergedChats", isDirectory: true)
        self.manifestURL = root.appendingPathComponent("library.json")
    }

    func backupURL(for versionID: String) -> URL {
        sourcesURL
            .appendingPathComponent(versionID, isDirectory: true)
            .appendingPathComponent("Backup", isDirectory: true)
    }

    func profilePhotosURL(for versionID: String) -> URL {
        sourcesURL
            .appendingPathComponent(versionID, isDirectory: true)
            .appendingPathComponent("Catalog", isDirectory: true)
            .appendingPathComponent("ChatProfilePhotos", isDirectory: true)
    }

    func exportURL(for record: LibraryVersionRecord) -> URL {
        exportsURL.appendingPathComponent(record.resolvedExportDirectoryName, isDirectory: true)
    }

    func legacyExportURL(for versionID: String) -> URL {
        exportsURL.appendingPathComponent(versionID, isDirectory: true)
    }

    static func resolvingSelection(_ selectedURL: URL) -> LibraryPaths {
        var candidate = selectedURL.standardizedFileURL
        let fileManager = FileManager.default

        for _ in 0..<4 {
            if fileManager.fileExists(atPath: candidate.appendingPathComponent("library.json").path) {
                return LibraryPaths(rootURL: candidate)
            }

            let legacyMetadata = candidate
                .appendingPathComponent("Backup", isDirectory: true)
                .appendingPathComponent(".wa-backup", isDirectory: true)
                .appendingPathComponent("backup-info.json")
            if fileManager.fileExists(atPath: legacyMetadata.path) {
                return LibraryPaths(rootURL: candidate)
            }

            let parent = candidate.deletingLastPathComponent()
            guard parent.path != candidate.path else { break }
            candidate = parent
        }

        return LibraryPaths(rootURL: selectedURL)
    }
}

struct LibraryManifest: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var createdAt: Date
    var versions: [LibraryVersionRecord]

    init(createdAt: Date = Date(), versions: [LibraryVersionRecord] = []) {
        self.schemaVersion = Self.currentSchemaVersion
        self.createdAt = createdAt
        self.versions = versions
    }
}

struct LibraryVersionRecord: Codable, Equatable, Identifiable {
    let id: String
    let sourceBackupIdentifier: String
    let sourceBackupCreationDate: Date
    let importedAt: Date
    let exportDirectoryName: String?

    init(
        id: String,
        sourceBackupIdentifier: String,
        sourceBackupCreationDate: Date,
        importedAt: Date,
        exportDirectoryName: String? = nil
    ) {
        self.id = id
        self.sourceBackupIdentifier = sourceBackupIdentifier
        self.sourceBackupCreationDate = sourceBackupCreationDate
        self.importedAt = importedAt
        self.exportDirectoryName = exportDirectoryName
    }

    var resolvedExportDirectoryName: String {
        exportDirectoryName ?? id
    }

    func withExportDirectoryName(_ name: String) -> Self {
        Self(
            id: id,
            sourceBackupIdentifier: sourceBackupIdentifier,
            sourceBackupCreationDate: sourceBackupCreationDate,
            importedAt: importedAt,
            exportDirectoryName: name
        )
    }

    var title: String {
        Self.titleFormatter.string(from: sourceBackupCreationDate)
    }

    private static let titleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter
    }()
}

struct VersionChatID: Codable, Hashable {
    let versionID: String
    let chatID: Int
}

struct ConversationArchiveID: Codable, Hashable, Identifiable {
    let rawValue: String

    var id: String { rawValue }

    init(rawValue: String = UUID().uuidString.lowercased()) {
        self.rawValue = rawValue
    }
}

struct ConversationIdentityKey: Codable, Hashable {
    let chatType: ChatInfo.ChatType
    let contactJID: String

    init(chat: ChatInfo) {
        self.init(chatType: chat.chatType, contactJID: chat.contactJid)
    }

    init(chatType: ChatInfo.ChatType, contactJID: String) {
        self.chatType = chatType
        self.contactJID = contactJID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

struct ConversationContribution: Codable, Equatable, Identifiable {
    let id: String
    let source: VersionChatID
    let exportedAt: Date

    init(
        id: String = UUID().uuidString.lowercased(),
        source: VersionChatID,
        exportedAt: Date
    ) {
        self.id = id
        self.source = source
        self.exportedAt = exportedAt
    }
}

struct ConversationArchiveRecord: Codable, Identifiable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let id: ConversationArchiveID
    let key: ConversationIdentityKey
    let createdAt: Date
    var updatedAt: Date
    var contributions: [ConversationContribution]
    var summary: ChatInfo?
    var contactJIDAliases: [String]?

    init(
        id: ConversationArchiveID = ConversationArchiveID(),
        key: ConversationIdentityKey,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        contributions: [ConversationContribution] = [],
        summary: ChatInfo? = nil,
        contactJIDAliases: [String]? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.key = key
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.contributions = contributions
        self.summary = summary
        self.contactJIDAliases = contactJIDAliases
    }

    var identityKeys: Set<ConversationIdentityKey> {
        var keys = Set([key])
        for alias in contactJIDAliases ?? [] {
            keys.insert(ConversationIdentityKey(chatType: key.chatType, contactJID: alias))
        }
        return keys
    }

    func matches(_ identity: ResolvedConversationIdentity) -> Bool {
        !identityKeys.isDisjoint(with: identity.keys)
    }

    mutating func register(_ identity: ResolvedConversationIdentity) {
        var aliases = Set(contactJIDAliases ?? [])
        aliases.formUnion(identity.keys.map(\.contactJID))
        aliases.remove(key.contactJID)
        contactJIDAliases = aliases.isEmpty ? nil : aliases.sorted()
    }
}

struct ArchivedConversation {
    let record: ConversationArchiveRecord
    let document: ExportedChatDocument
    let directoryURL: URL
    let documentURL: URL
    let mediaDirectoryURL: URL
}

struct SourceExportListItem {
    let id: VersionChatID
    let chat: ChatInfo
    let exportedAt: Date
    let versionTitle: String
    let directoryURL: URL
    let photoURL: URL?
}

struct ExportedChatListItem: Identifiable {
    let id: ConversationArchiveID
    let chat: ChatInfo
    let exportedAt: Date
    let contributionSources: [VersionChatID]
    let directoryURL: URL
    let photoURL: URL?

    var contributionCount: Int { contributionSources.count }
}

enum ChatDetailsState: Equatable {
    case loading
    case loaded(firstMessageDate: Date?)
    case failed(String)
}

final class LibraryVersionSession: @unchecked Sendable, Identifiable {
    let record: LibraryVersionRecord
    let backupURL: URL
    let exportsURL: URL
    let backup: ExtractedWhatsAppBackup?
    let reader: WhatsAppBackupReader?
    let exportStore: ChatExportStore
    let chats: [ChatInfo]
    let backupByteCount: Int64

    var id: String { record.id }
    var hasSourceBackup: Bool { backup != nil }

    init(
        record: LibraryVersionRecord,
        backupURL: URL,
        exportsURL: URL,
        backup: ExtractedWhatsAppBackup?,
        reader: WhatsAppBackupReader?,
        chats: [ChatInfo],
        backupByteCount: Int64
    ) {
        self.record = record
        self.backupURL = backupURL
        self.exportsURL = exportsURL
        self.backup = backup
        self.reader = reader
        self.exportStore = ChatExportStore(rootDirectory: exportsURL)
        self.chats = chats
        self.backupByteCount = backupByteCount
    }
}

final class LibrarySession: @unchecked Sendable {
    let paths: LibraryPaths
    let manifest: LibraryManifest
    let versions: [LibraryVersionSession]

    init(paths: LibraryPaths, manifest: LibraryManifest, versions: [LibraryVersionSession]) {
        self.paths = paths
        self.manifest = manifest
        self.versions = versions
    }

    func version(id: String) -> LibraryVersionSession? {
        versions.first { $0.id == id }
    }

    func chat(for selection: VersionChatID) -> ChatInfo? {
        version(id: selection.versionID)?.chats.first { $0.id == selection.chatID }
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

enum ChatListSortOrder: String, CaseIterable, Identifiable {
    case recent
    case largest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: return "Recientes"
        case .largest: return "Más grandes"
        }
    }

    func sort(_ chats: [ChatInfo]) -> [ChatInfo] {
        chats.sorted { lhs, rhs in
            if self == .largest, lhs.mediaByteCount != rhs.mediaByteCount {
                return lhs.mediaByteCount > rhs.mediaByteCount
            }
            if lhs.lastMessageDate != rhs.lastMessageDate {
                return lhs.lastMessageDate > rhs.lastMessageDate
            }
            return lhs.id < rhs.id
        }
    }
}

enum ChatExportDisplayState: Equatable {
    case checking
    case notExported
    case updateAvailable(Date)
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
        case .checking, .notExported, .updateAvailable: return false
        }
    }
}

struct AppOperation: Equatable {
    enum Kind: Equatable {
        case discovering
        case creatingLibrary
        case openingLibrary
        case addingBackup
        case deletingBackup(String)
        case deletingOriginalIPhoneBackup
        case deletingExportedContribution(VersionChatID)
        case loadingChats
        case exportingChat(VersionChatID)
    }

    let id: UUID
    let kind: Kind
    var title: String
    var detail: String?
    var fractionCompleted: Double?
}
