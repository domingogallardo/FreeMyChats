import Foundation
@preconcurrency import SwiftWABackupAPI

struct LibraryPaths: Equatable {
    let rootURL: URL
    let sourcesURL: URL
    let storedChatsURL: URL
    let importedChatsURL: URL
    let mergedChatsURL: URL
    let manifestURL: URL

    init(rootURL: URL) {
        let root = rootURL.standardizedFileURL
        self.rootURL = root
        self.sourcesURL = root.appendingPathComponent("Sources", isDirectory: true)
        self.storedChatsURL = root.appendingPathComponent("StoredChats", isDirectory: true)
        self.importedChatsURL = root.appendingPathComponent("ImportedChats", isDirectory: true)
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

    func storedChatURL(for record: LibraryVersionRecord) -> URL {
        storedChatsURL.appendingPathComponent(record.storageDirectoryName, isDirectory: true)
    }

    func importedConversationURL(
        conversationID: ConversationArchiveID,
        importID: String
    ) -> URL {
        importedChatsURL
            .appendingPathComponent(conversationID.rawValue, isDirectory: true)
            .appendingPathComponent(importID, isDirectory: true)
    }

    static func resolvingSelection(_ selectedURL: URL) -> LibraryPaths {
        var candidate = selectedURL.standardizedFileURL
        let fileManager = FileManager.default

        for _ in 0..<4 {
            if fileManager.fileExists(atPath: candidate.appendingPathComponent("library.json").path) {
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
    static let previousSchemaVersion = 2
    static let currentSchemaVersion = 3

    var schemaVersion: Int
    var createdAt: Date
    var versions: [LibraryVersionRecord]

    init(createdAt: Date = Date(), versions: [LibraryVersionRecord] = []) {
        self.schemaVersion = Self.currentSchemaVersion
        self.createdAt = createdAt
        self.versions = versions
    }

    var isSupported: Bool {
        schemaVersion == Self.previousSchemaVersion
            || schemaVersion == Self.currentSchemaVersion
    }
}

struct LibraryVersionRecord: Codable, Equatable, Identifiable {
    let id: String
    let sourceBackupIdentifier: String
    let sourceBackupCreationDate: Date
    let importedAt: Date
    let storageDirectoryName: String

    init(
        id: String,
        sourceBackupIdentifier: String,
        sourceBackupCreationDate: Date,
        importedAt: Date,
        storageDirectoryName: String
    ) {
        self.id = id
        self.sourceBackupIdentifier = sourceBackupIdentifier
        self.sourceBackupCreationDate = sourceBackupCreationDate
        self.importedAt = importedAt
        self.storageDirectoryName = storageDirectoryName
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
    let storedAt: Date
    let messageCount: Int?
    let exclusiveMessageCount: Int?

    init(
        id: String = UUID().uuidString.lowercased(),
        source: VersionChatID,
        storedAt: Date,
        messageCount: Int? = nil,
        exclusiveMessageCount: Int? = nil
    ) {
        self.id = id
        self.source = source
        self.storedAt = storedAt
        self.messageCount = messageCount
        self.exclusiveMessageCount = exclusiveMessageCount
    }

    func withMessageCounts(total: Int, exclusive: Int) -> Self {
        ConversationContribution(
            id: id,
            source: source,
            storedAt: storedAt,
            messageCount: total,
            exclusiveMessageCount: exclusive
        )
    }
}

struct ImportedConversationContribution: Codable, Equatable, Identifiable {
    let id: String
    let importedAt: Date
    let packageID: UUID
    let packageCreatedAt: Date
    let producerName: String
    let producerVersion: String
    let relativeDirectory: String
    let archiveSHA256: String
    let contentDigest: String
    let displayName: String
    let perspectiveHint: ConversationPerspectiveHint?
    let messageCount: Int?
    let exclusiveMessageCount: Int?
    let exclusiveMediaByteCount: Int64?

    init(
        id: String = UUID().uuidString.lowercased(),
        importedAt: Date = Date(),
        packageID: UUID,
        packageCreatedAt: Date,
        producerName: String,
        producerVersion: String,
        relativeDirectory: String,
        archiveSHA256: String,
        contentDigest: String,
        displayName: String,
        perspectiveHint: ConversationPerspectiveHint? = nil,
        messageCount: Int? = nil,
        exclusiveMessageCount: Int? = nil,
        exclusiveMediaByteCount: Int64? = nil
    ) {
        self.id = id
        self.importedAt = importedAt
        self.packageID = packageID
        self.packageCreatedAt = packageCreatedAt
        self.producerName = producerName
        self.producerVersion = producerVersion
        self.relativeDirectory = relativeDirectory
        self.archiveSHA256 = archiveSHA256
        self.contentDigest = contentDigest
        self.displayName = displayName
        self.perspectiveHint = perspectiveHint
        self.messageCount = messageCount
        self.exclusiveMessageCount = exclusiveMessageCount
        self.exclusiveMediaByteCount = exclusiveMediaByteCount
    }

    func withImpact(_ impact: ConversationSourceImpact) -> Self {
        ImportedConversationContribution(
            id: id,
            importedAt: importedAt,
            packageID: packageID,
            packageCreatedAt: packageCreatedAt,
            producerName: producerName,
            producerVersion: producerVersion,
            relativeDirectory: relativeDirectory,
            archiveSHA256: archiveSHA256,
            contentDigest: contentDigest,
            displayName: displayName,
            perspectiveHint: perspectiveHint,
            messageCount: impact.sourceMessageCount,
            exclusiveMessageCount: impact.exclusiveMessageCount,
            exclusiveMediaByteCount: impact.exclusiveMediaByteCount
        )
    }
}

struct ConversationArchiveRecord: Codable, Identifiable {
    static let previousSchemaVersion = 2
    static let currentSchemaVersion = 3

    var schemaVersion: Int
    let id: ConversationArchiveID
    let key: ConversationIdentityKey
    let createdAt: Date
    var updatedAt: Date
    var contributions: [ConversationContribution]
    var importedContributions: [ImportedConversationContribution]
    var summary: ChatInfo?
    var contactJIDAliases: [String]?

    init(
        id: ConversationArchiveID = ConversationArchiveID(),
        key: ConversationIdentityKey,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        contributions: [ConversationContribution] = [],
        importedContributions: [ImportedConversationContribution] = [],
        summary: ChatInfo? = nil,
        contactJIDAliases: [String]? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.key = key
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.contributions = contributions
        self.importedContributions = importedContributions
        self.summary = summary
        self.contactJIDAliases = contactJIDAliases
    }

    var isSupported: Bool {
        schemaVersion == Self.previousSchemaVersion
            || schemaVersion == Self.currentSchemaVersion
    }

    var totalContributionCount: Int {
        contributions.count + importedContributions.count
    }

    mutating func markCurrentSchema() {
        schemaVersion = Self.currentSchemaVersion
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case key
        case createdAt
        case updatedAt
        case contributions
        case importedContributions
        case summary
        case contactJIDAliases
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        id = try container.decode(ConversationArchiveID.self, forKey: .id)
        key = try container.decode(ConversationIdentityKey.self, forKey: .key)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        contributions = try container.decode(
            [ConversationContribution].self,
            forKey: .contributions
        )
        importedContributions = try container.decodeIfPresent(
            [ImportedConversationContribution].self,
            forKey: .importedContributions
        ) ?? []
        summary = try container.decodeIfPresent(ChatInfo.self, forKey: .summary)
        contactJIDAliases = try container.decodeIfPresent(
            [String].self,
            forKey: .contactJIDAliases
        )
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
    // The on-disk archive keeps the same conversation ID and directory when its
    // contributions are rebuilt. Stateful views use this transient revision to
    // distinguish each freshly opened/rebuilt snapshot.
    let contentRevisionID = UUID()
    let record: ConversationArchiveRecord
    let document: StoredChatDocument
    let directoryURL: URL
    let documentURL: URL
    let mediaDirectoryURL: URL
}

struct ConversationCatalogItem: Identifiable {
    let id: ConversationArchiveID
    let chat: ChatInfo
    let updatedAt: Date
    let contributionSources: [VersionChatID]
    let importedContributions: [ImportedConversationContribution]
    let directoryURL: URL
    let photoURL: URL?

    var contributionCount: Int {
        contributionSources.count + importedContributions.count
    }

    var localContributionCount: Int { contributionSources.count }
    var importedContributionCount: Int { importedContributions.count }
}

struct ImportedChatSidebarItem: Identifiable {
    let contribution: ImportedConversationContribution
    let conversationID: ConversationArchiveID
    let conversationName: String

    var id: String { contribution.id }
}

enum ChatDetailsState: Equatable {
    case loading
    case loaded(firstMessageDate: Date?)
    case failed(String)
}

final class LibraryVersionSession: @unchecked Sendable, Identifiable {
    let record: LibraryVersionRecord
    let backupURL: URL
    let storedChatsURL: URL
    let backup: ExtractedWhatsAppBackup?
    let reader: WhatsAppBackupReader?
    let storedChatStore: StoredChatStore
    let chats: [ChatInfo]
    let backupByteCount: Int64

    var id: String { record.id }
    var hasSourceBackup: Bool { backup != nil }

    init(
        record: LibraryVersionRecord,
        backupURL: URL,
        storedChatsURL: URL,
        backup: ExtractedWhatsAppBackup?,
        reader: WhatsAppBackupReader?,
        chats: [ChatInfo],
        backupByteCount: Int64
    ) {
        self.record = record
        self.backupURL = backupURL
        self.storedChatsURL = storedChatsURL
        self.backup = backup
        self.reader = reader
        self.storedChatStore = StoredChatStore(rootDirectory: storedChatsURL)
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

enum StoredChatDisplayState: Equatable {
    case checking
    case notStored
    case updateAvailable(Date)
    case stored(Date)
    case stale(Date)
    case invalid(String)

    init(_ state: StoredChatState) {
        switch state {
        case .notStored:
            self = .notStored
        case .stored(let info):
            self = .stored(info.storedAt)
        case .stale(let info):
            self = .stale(info.storedAt)
        case .invalid(let reason):
            self = .invalid(reason)
        }
    }

    var isPhysicallyStored: Bool {
        switch self {
        case .stored, .stale, .invalid: return true
        case .checking, .notStored, .updateAvailable: return false
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
        case deletingStoredContribution(VersionChatID)
        case preparingStoredCopyDeletion(VersionChatID)
        case loadingChats
        case storingChat(VersionChatID)
        case exportingConversation(ConversationArchiveID)
        case importingPortableConversation
        case removingImportedConversation(String)
    }

    let id: UUID
    let kind: Kind
    var title: String
    var detail: String?
    var fractionCompleted: Double?
}
