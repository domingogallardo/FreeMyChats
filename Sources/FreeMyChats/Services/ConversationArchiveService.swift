import CryptoKit
import Foundation
import SwiftWABackupAPI

enum ConversationArchiveError: Error, LocalizedError {
    case invalidArchive(URL, String)
    case missingSource(VersionChatID)
    case contributionNotFound(VersionChatID)

    var errorDescription: String? {
        switch self {
        case .invalidArchive(let url, let reason):
            return "La conversación guardada en \(url.lastPathComponent) no es válida: \(reason)"
        case .missingSource(let selection):
            return "Falta la exportación de origen \(selection.versionID)/\(selection.chatID)."
        case .contributionNotFound(let selection):
            return "La exportación \(selection.versionID)/\(selection.chatID) no forma parte de ninguna conversación guardada."
        }
    }
}

struct ConversationArchiveUpdate {
    let conversation: ArchivedConversation
    let addedMessageCount: Int
}

struct ConversationContributionRemoval {
    let session: LibrarySession
    let conversationID: ConversationArchiveID
    let conversation: ArchivedConversation?
}

enum ConversationArchiveService {
    private static let recordFilename = "archive.json"
    private static let documentFilename = "chat.json"
    private static let mediaDirectoryName = "Media"

    static func synchronize(in session: LibrarySession) throws -> [ExportedChatListItem] {
        try FileManager.default.createDirectory(
            at: session.paths.conversationsURL,
            withIntermediateDirectories: true
        )

        let consolidation = consolidate(try loadRecords(paths: session.paths))
        var records = consolidation.records
        var dirtyIDs = consolidation.dirtyIDs
        let knownSources = Set(records.flatMap { $0.contributions.map(\.source) })

        for source in sourceSelections(in: session) where !knownSources.contains(source) {
            guard let version = session.version(id: source.versionID) else { continue }
            let exported = try version.exportStore.openChat(chatId: source.chatID)
            let identity = identity(for: exported.document.chat, in: version)
            let recordIndex: Int
            if let existingIndex = records.firstIndex(where: { $0.matches(identity) }) {
                recordIndex = existingIndex
            } else {
                records.append(ConversationArchiveRecord(key: identity.primaryKey))
                recordIndex = records.index(before: records.endIndex)
            }
            records[recordIndex].register(identity)

            if let contributionIndex = records[recordIndex].contributions.firstIndex(
                where: { $0.source == source }
            ) {
                let previous = records[recordIndex].contributions[contributionIndex]
                if previous.exportedAt != exported.document.exportedAt {
                    records[recordIndex].contributions[contributionIndex] = ConversationContribution(
                        id: previous.id,
                        source: source,
                        exportedAt: exported.document.exportedAt
                    )
                    records[recordIndex].updatedAt = max(
                        records[recordIndex].updatedAt,
                        exported.document.exportedAt
                    )
                    dirtyIDs.insert(records[recordIndex].id)
                }
            } else {
                records[recordIndex].contributions.append(
                    ConversationContribution(
                        source: source,
                        exportedAt: exported.document.exportedAt
                    )
                )
                records[recordIndex].updatedAt = max(
                    records[recordIndex].updatedAt,
                    exported.document.exportedAt
                )
                dirtyIDs.insert(records[recordIndex].id)
            }
        }

        for record in records where dirtyIDs.contains(record.id) {
            _ = try install(record: record, in: session)
        }
        for duplicateID in consolidation.duplicateIDs {
            let duplicateURL = archiveURL(id: duplicateID, paths: session.paths)
            if FileManager.default.fileExists(atPath: duplicateURL.path) {
                try FileManager.default.removeItem(at: duplicateURL)
            }
        }

        return try catalog(paths: session.paths)
    }

    static func incorporate(
        _ exported: ExportedChat,
        source: VersionChatID,
        in session: LibrarySession
    ) throws -> ConversationArchiveUpdate {
        guard let version = session.version(id: source.versionID) else {
            throw ConversationArchiveError.missingSource(source)
        }
        let identity = identity(for: exported.document.chat, in: version)
        let records = try loadRecords(paths: session.paths)
        let oldMessageCount: Int
        var record: ConversationArchiveRecord

        if let existing = records.first(where: { $0.matches(identity) }) {
            record = existing
            oldMessageCount = (try? open(id: existing.id, paths: session.paths))?
                .document.messages.count ?? 0
        } else {
            record = ConversationArchiveRecord(key: identity.primaryKey)
            oldMessageCount = 0
        }
        record.register(identity)

        if let index = record.contributions.firstIndex(where: { $0.source == source }) {
            let previous = record.contributions[index]
            record.contributions[index] = ConversationContribution(
                id: previous.id,
                source: source,
                exportedAt: exported.document.exportedAt
            )
        } else {
            record.contributions.append(
                ConversationContribution(source: source, exportedAt: exported.document.exportedAt)
            )
        }
        record.updatedAt = Date()

        let conversation = try install(record: record, in: session)
        return ConversationArchiveUpdate(
            conversation: conversation,
            addedMessageCount: max(0, conversation.document.messages.count - oldMessageCount)
        )
    }

    static func hasArchive(
        for chat: ChatInfo,
        in version: LibraryVersionSession,
        paths: LibraryPaths
    ) -> Bool {
        let resolved = identity(for: chat, in: version)
        guard let keys = try? archiveKeys(paths: paths) else { return false }
        return !keys.isDisjoint(with: resolved.keys)
    }

    static func archiveKeys(paths: LibraryPaths) throws -> Set<ConversationIdentityKey> {
        Set(try loadRecords(paths: paths).flatMap(\.identityKeys))
    }

    static func open(
        id: ConversationArchiveID,
        paths: LibraryPaths
    ) throws -> ArchivedConversation {
        let directoryURL = archiveURL(id: id, paths: paths)
        let recordURL = directoryURL.appendingPathComponent(recordFilename)
        let documentURL = directoryURL.appendingPathComponent(documentFilename)
        let mediaURL = directoryURL.appendingPathComponent(mediaDirectoryName, isDirectory: true)

        do {
            let record = try decoder().decode(
                ConversationArchiveRecord.self,
                from: Data(contentsOf: recordURL)
            )
            guard record.schemaVersion == ConversationArchiveRecord.currentSchemaVersion,
                  record.id == id else {
                throw ConversationArchiveError.invalidArchive(
                    directoryURL,
                    "El manifiesto tiene una versión o identidad incompatible."
                )
            }

            let document = try decoder().decode(
                ExportedChatDocument.self,
                from: Data(contentsOf: documentURL)
            )
            let documentKey = ConversationIdentityKey(chat: document.chat)
            guard record.identityKeys.contains(documentKey) else {
                throw ConversationArchiveError.invalidArchive(
                    directoryURL,
                    "La identidad del chat no coincide con su manifiesto."
                )
            }
            try validateMedia(document: document, at: mediaURL)
            return ArchivedConversation(
                record: record,
                document: document,
                directoryURL: directoryURL,
                documentURL: documentURL,
                mediaDirectoryURL: mediaURL
            )
        } catch let error as ConversationArchiveError {
            throw error
        } catch {
            throw ConversationArchiveError.invalidArchive(directoryURL, error.localizedDescription)
        }
    }

    static func removeContribution(
        source: VersionChatID,
        from session: LibrarySession
    ) throws -> ConversationContributionRemoval {
        let record = try loadRecords(paths: session.paths).first {
            $0.contributions.contains(where: { $0.source == source })
        }
        guard var record else {
            throw ConversationArchiveError.contributionNotFound(source)
        }

        let archived = try open(id: record.id, paths: session.paths)
        record.contributions.removeAll { $0.source == source }
        record.updatedAt = Date()

        let fileManager = FileManager.default
        let stagingURL = session.paths.rootURL.appendingPathComponent(
            ".removing-contribution-\(UUID().uuidString)",
            isDirectory: true
        )
        let stagedArchiveURL = stagingURL.appendingPathComponent(
            "Conversation",
            isDirectory: true
        )
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: false)
        do {
            try fileManager.moveItem(at: archived.directoryURL, to: stagedArchiveURL)
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            throw error
        }

        do {
            let rebuilt = record.contributions.isEmpty
                ? nil
                : try install(record: record, in: session)
            let updatedSession = try LibraryService.deleteExportedChat(source, from: session)
            try? fileManager.removeItem(at: stagingURL)
            return ConversationContributionRemoval(
                session: updatedSession,
                conversationID: record.id,
                conversation: rebuilt
            )
        } catch {
            let replacementURL = archiveURL(id: record.id, paths: session.paths)
            if fileManager.fileExists(atPath: replacementURL.path) {
                try? fileManager.removeItem(at: replacementURL)
            }
            if fileManager.fileExists(atPath: stagedArchiveURL.path) {
                try? fileManager.moveItem(at: stagedArchiveURL, to: archived.directoryURL)
            }
            try? fileManager.removeItem(at: stagingURL)
            throw error
        }
    }

    private static func catalog(paths: LibraryPaths) throws -> [ExportedChatListItem] {
        try loadRecords(paths: paths).map { record in
            let directoryURL = archiveURL(id: record.id, paths: paths)
            let mediaURL = directoryURL.appendingPathComponent(
                mediaDirectoryName,
                isDirectory: true
            )
            let chat: ChatInfo
            if let summary = record.summary {
                chat = summary
            } else {
                let archived = try open(id: record.id, paths: paths)
                chat = archived.document.chat
                var upgradedRecord = record
                upgradedRecord.summary = chat
                try encoder().encode(upgradedRecord).write(
                    to: directoryURL.appendingPathComponent(recordFilename),
                    options: .atomic
                )
            }
            let photoURL = chat.photoFilename.map {
                mediaURL.appendingPathComponent($0)
            }.flatMap {
                FileManager.default.fileExists(atPath: $0.path) ? $0 : nil
            }
            return ExportedChatListItem(
                id: record.id,
                chat: chat,
                exportedAt: record.updatedAt,
                contributionCount: record.contributions.count,
                directoryURL: directoryURL,
                photoURL: photoURL
            )
        }.sorted { lhs, rhs in
            if lhs.exportedAt != rhs.exportedAt {
                return lhs.exportedAt > rhs.exportedAt
            }
            return lhs.chat.name.localizedStandardCompare(rhs.chat.name) == .orderedAscending
        }
    }

    private static func loadRecords(paths: LibraryPaths) throws -> [ConversationArchiveRecord] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: paths.conversationsURL.path) else { return [] }
        let entries = try fileManager.contentsOfDirectory(
            at: paths.conversationsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )

        return try entries.compactMap { entry in
            guard !entry.lastPathComponent.hasPrefix(".") else { return nil }
            guard (try entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return nil
            }
            let recordURL = entry.appendingPathComponent(recordFilename)
            guard fileManager.fileExists(atPath: recordURL.path) else { return nil }
            return try decoder().decode(
                ConversationArchiveRecord.self,
                from: Data(contentsOf: recordURL)
            )
        }
    }

    private static func identity(
        for chat: ChatInfo,
        in version: LibraryVersionSession
    ) -> ResolvedConversationIdentity {
        ConversationIdentityResolver(
            backupURL: version.hasSourceBackup ? version.backupURL : nil
        ).identity(for: chat)
    }

    private static func consolidate(
        _ records: [ConversationArchiveRecord]
    ) -> (
        records: [ConversationArchiveRecord],
        duplicateIDs: Set<ConversationArchiveID>,
        dirtyIDs: Set<ConversationArchiveID>
    ) {
        var consolidated: [ConversationArchiveRecord] = []
        var duplicateIDs: Set<ConversationArchiveID> = []
        var dirtyIDs: Set<ConversationArchiveID> = []

        for candidate in records.sorted(by: { $0.createdAt < $1.createdAt }) {
            let candidateSources = Set(candidate.contributions.map(\.source))
            let existingIndex = consolidated.firstIndex { existing in
                !existing.identityKeys.isDisjoint(with: candidate.identityKeys)
                    || !Set(existing.contributions.map(\.source)).isDisjoint(with: candidateSources)
            }
            guard let existingIndex else {
                consolidated.append(candidate)
                continue
            }

            var existing = consolidated[existingIndex]
            existing.register(
                ResolvedConversationIdentity(
                    primaryKey: existing.key,
                    keys: candidate.identityKeys
                )
            )
            for contribution in candidate.contributions {
                if let index = existing.contributions.firstIndex(
                    where: { $0.source == contribution.source }
                ) {
                    if contribution.exportedAt > existing.contributions[index].exportedAt {
                        let previous = existing.contributions[index]
                        existing.contributions[index] = ConversationContribution(
                            id: previous.id,
                            source: contribution.source,
                            exportedAt: contribution.exportedAt
                        )
                    }
                } else {
                    existing.contributions.append(contribution)
                }
            }
            if candidate.updatedAt > existing.updatedAt {
                existing.updatedAt = candidate.updatedAt
                existing.summary = candidate.summary ?? existing.summary
            }
            consolidated[existingIndex] = existing
            duplicateIDs.insert(candidate.id)
            dirtyIDs.insert(existing.id)
        }

        return (consolidated, duplicateIDs, dirtyIDs)
    }

    private static func install(
        record: ConversationArchiveRecord,
        in session: LibrarySession
    ) throws -> ArchivedConversation {
        let resolved = try record.contributions.enumerated().map { index, contribution in
            guard let version = session.version(id: contribution.source.versionID) else {
                throw ConversationArchiveError.missingSource(contribution.source)
            }
            return ResolvedContribution(
                index: index,
                contribution: contribution,
                exported: try version.exportStore.openChat(chatId: contribution.source.chatID)
            )
        }
        guard !resolved.isEmpty else {
            throw ConversationArchiveError.invalidArchive(
                archiveURL(id: record.id, paths: session.paths),
                "No contiene ninguna aportación."
            )
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: session.paths.conversationsURL,
            withIntermediateDirectories: true
        )
        let temporaryURL = session.paths.conversationsURL.appendingPathComponent(
            ".building-\(record.id.rawValue)-\(UUID().uuidString)",
            isDirectory: true
        )
        let temporaryMediaURL = temporaryURL.appendingPathComponent(
            mediaDirectoryName,
            isDirectory: true
        )
        try fileManager.createDirectory(at: temporaryMediaURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryURL) }

        let materializer = MediaMaterializer(destinationURL: temporaryMediaURL)
        let document = try buildDocument(
            record: record,
            contributions: resolved,
            materializer: materializer
        )
        var installedRecord = record
        installedRecord.summary = document.chat
        try encoder().encode(document).write(
            to: temporaryURL.appendingPathComponent(documentFilename),
            options: .atomic
        )
        try encoder().encode(installedRecord).write(
            to: temporaryURL.appendingPathComponent(recordFilename),
            options: .atomic
        )
        try validateMedia(document: document, at: temporaryMediaURL)

        let finalURL = archiveURL(id: record.id, paths: session.paths)
        if fileManager.fileExists(atPath: finalURL.path) {
            _ = try fileManager.replaceItemAt(
                finalURL,
                withItemAt: temporaryURL,
                backupItemName: nil,
                options: []
            )
        } else {
            try fileManager.moveItem(at: temporaryURL, to: finalURL)
        }
        var visibleFinalURL = finalURL
        var resourceValues = URLResourceValues()
        resourceValues.isHidden = false
        try visibleFinalURL.setResourceValues(resourceValues)
        return try open(id: installedRecord.id, paths: session.paths)
    }

    private static func buildDocument(
        record: ConversationArchiveRecord,
        contributions: [ResolvedContribution],
        materializer: MediaMaterializer
    ) throws -> ExportedChatDocument {
        if contributions.count == 1 {
            let exported = contributions[0].exported
            let filenames = [exported.document.chat.photoFilename].compactMap { $0 }
                + exported.document.messages.compactMap(\.mediaFilename)
                + exported.document.contacts.compactMap(\.photoFilename)
            for filename in Set(filenames) {
                _ = try materializer.materializeDirect(
                    filename: filename,
                    from: contributions[0]
                )
            }
            return exported.document
        }

        var hashCache: [URL: String] = [:]
        var sourceMessages: [SourceMessage] = []

        for resolved in contributions {
            for (messageIndex, message) in resolved.exported.document.messages.enumerated() {
                sourceMessages.append(
                    SourceMessage(
                        contribution: resolved,
                        messageIndex: messageIndex,
                        message: message,
                        fingerprint: try messageFingerprint(
                            message,
                            mediaDirectoryURL: resolved.exported.mediaDirectoryURL,
                            hashCache: &hashCache
                        )
                    )
                )
            }
        }
        sourceMessages.sort {
            if $0.message.date != $1.message.date { return $0.message.date < $1.message.date }
            if $0.contribution.index != $1.contribution.index {
                return $0.contribution.index < $1.contribution.index
            }
            return $0.messageIndex < $1.messageIndex
        }

        var fingerprintToID: [String: Int] = [:]
        var sourceToID: [SourceMessageKey: Int] = [:]
        var representatives: [(id: Int, source: SourceMessage)] = []
        for source in sourceMessages {
            let aggregateID: Int
            if let existing = fingerprintToID[source.fingerprint] {
                aggregateID = existing
            } else {
                aggregateID = representatives.count + 1
                fingerprintToID[source.fingerprint] = aggregateID
                representatives.append((aggregateID, source))
            }
            sourceToID[source.key] = aggregateID
        }

        let aggregateChatID = contributions[0].exported.document.chat.id
        var messageMediaNames: Set<String> = []
        let messages = try representatives.map { representative in
            let source = representative.source
            let mediaFilename = try source.message.mediaFilename.map {
                try materializer.materialize(
                    filename: $0,
                    from: source.contribution
                )
            }
            if let mediaFilename { messageMediaNames.insert(mediaFilename) }
            let replyTo = source.message.replyTo.flatMap {
                sourceToID[
                    SourceMessageKey(
                        contributionID: source.contribution.contribution.id,
                        messageID: $0
                    )
                ]
            }
            return try transformedMessage(
                source.message,
                id: representative.id,
                chatID: aggregateChatID,
                replyTo: replyTo,
                mediaFilename: mediaFilename
            )
        }

        let latest = contributions.max {
            $0.contribution.exportedAt < $1.contribution.exportedAt
        } ?? contributions[contributions.count - 1]
        var chosenContacts: [String: (ContactInfo, ResolvedContribution)] = [:]
        for contribution in contributions {
            for contact in contribution.exported.document.contacts {
                chosenContacts[contact.phone] = (contact, contribution)
            }
        }
        let contacts = try chosenContacts.keys.sorted().map { phone in
            let (contact, contribution) = chosenContacts[phone]!
            let photoFilename = try contact.photoFilename.map {
                try materializer.materialize(filename: $0, from: contribution)
            }
            return try transformedContact(contact, photoFilename: photoFilename)
        }
        let chatPhotoFilename = try latest.exported.document.chat.photoFilename.map {
            try materializer.materialize(filename: $0, from: latest)
        }
        let mediaByteCount = messageMediaNames.reduce(Int64(0)) {
            $0 + materializer.byteCount(for: $1)
        }
        let lastMessageDate = messages.last?.date
            ?? latest.exported.document.chat.lastMessageDate
        let chat = try transformedChat(
            latest.exported.document.chat,
            id: aggregateChatID,
            numberMessages: messages.count,
            lastMessageDate: lastMessageDate,
            mediaByteCount: mediaByteCount,
            photoFilename: chatPhotoFilename
        )
        return ExportedChatDocument(
            payload: ChatDumpPayload(chatInfo: chat, messages: messages, contacts: contacts),
            exportedAt: record.updatedAt
        )
    }

    private static func messageFingerprint(
        _ message: MessageInfo,
        mediaDirectoryURL: URL,
        hashCache: inout [URL: String]
    ) throws -> String {
        let mediaHash: String?
        if let filename = message.mediaFilename {
            let url = mediaDirectoryURL.appendingPathComponent(filename).standardizedFileURL
            if let cached = hashCache[url] {
                mediaHash = cached
            } else {
                let hash = try fileHash(url)
                hashCache[url] = hash
                mediaHash = hash
            }
        } else {
            mediaHash = nil
        }

        let payload = MessageFingerprint(
            timestampMilliseconds: Int64((message.date.timeIntervalSince1970 * 1_000).rounded()),
            isFromMe: message.isFromMe,
            messageType: message.messageType,
            message: message.message,
            caption: message.caption,
            authorIdentity: authorFingerprintIdentity(message.author),
            mediaHash: mediaHash,
            seconds: message.seconds,
            latitude: message.latitude,
            longitude: message.longitude
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return sha256Hex(try encoder.encode(payload))
    }

    private static func authorFingerprintIdentity(_ author: MessageAuthor?) -> String? {
        guard let author else { return nil }

        if let phone = normalizedPhone(author.phone) {
            return "phone:\(phone)"
        }

        guard let jid = author.jid?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !jid.isEmpty else { return nil }
        if jid.hasSuffix("@s.whatsapp.net"),
           let phone = normalizedPhone(String(jid.prefix { $0 != "@" })) {
            return "phone:\(phone)"
        }
        return "jid:\(jid)"
    }

    private static func normalizedPhone(_ value: String?) -> String? {
        guard let value else { return nil }
        let digits = value.filter(\.isNumber)
        return digits.isEmpty ? nil : digits
    }

    private static func transformedMessage(
        _ message: MessageInfo,
        id: Int,
        chatID: Int,
        replyTo: Int?,
        mediaFilename: String?
    ) throws -> MessageInfo {
        var object = try jsonObject(message)
        object["id"] = id
        object["chatId"] = chatID
        set(replyTo, for: "replyTo", in: &object)
        set(mediaFilename, for: "mediaFilename", in: &object)
        return try decodeObject(object, as: MessageInfo.self)
    }

    private static func transformedChat(
        _ chat: ChatInfo,
        id: Int,
        numberMessages: Int,
        lastMessageDate: Date,
        mediaByteCount: Int64,
        photoFilename: String?
    ) throws -> ChatInfo {
        var object = try jsonObject(chat)
        object["id"] = id
        object["numberMessages"] = numberMessages
        object["lastMessageDate"] = iso8601Formatter.string(from: lastMessageDate)
        object["mediaByteCount"] = mediaByteCount
        set(photoFilename, for: "photoFilename", in: &object)
        return try decodeObject(object, as: ChatInfo.self)
    }

    private static func transformedContact(
        _ contact: ContactInfo,
        photoFilename: String?
    ) throws -> ContactInfo {
        var object = try jsonObject(contact)
        set(photoFilename, for: "photoFilename", in: &object)
        return try decodeObject(object, as: ContactInfo.self)
    }

    private static func jsonObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try encoder().encode(value)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConversationArchiveError.invalidArchive(
                URL(fileURLWithPath: "chat.json"),
                "No se ha podido transformar el documento."
            )
        }
        return object
    }

    private static func decodeObject<T: Decodable>(
        _ object: [String: Any],
        as type: T.Type
    ) throws -> T {
        try decoder().decode(type, from: JSONSerialization.data(withJSONObject: object))
    }

    private static func set(_ value: Any?, for key: String, in object: inout [String: Any]) {
        if let value {
            object[key] = value
        } else {
            object.removeValue(forKey: key)
        }
    }

    private static func validateMedia(
        document: ExportedChatDocument,
        at mediaDirectoryURL: URL
    ) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: mediaDirectoryURL.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw ConversationArchiveError.invalidArchive(
                mediaDirectoryURL,
                "Falta la carpeta Media."
            )
        }

        let filenames = [document.chat.photoFilename].compactMap { $0 }
            + document.messages.compactMap(\.mediaFilename)
            + document.contacts.compactMap(\.photoFilename)
        for filename in filenames {
            guard filename == URL(fileURLWithPath: filename).lastPathComponent,
                  FileManager.default.fileExists(
                    atPath: mediaDirectoryURL.appendingPathComponent(filename).path
                  ) else {
                throw ConversationArchiveError.invalidArchive(
                    mediaDirectoryURL,
                    "Falta el archivo multimedia \(filename)."
                )
            }
        }
    }

    fileprivate static func fileHash(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func archiveURL(id: ConversationArchiveID, paths: LibraryPaths) -> URL {
        paths.conversationsURL.appendingPathComponent(id.rawValue, isDirectory: true)
    }

    private static func sourceSelections(in session: LibrarySession) -> [VersionChatID] {
        let fileManager = FileManager.default
        return session.versions.flatMap { version -> [VersionChatID] in
            let chatsURL = version.exportsURL.appendingPathComponent("Chats", isDirectory: true)
            guard let entries = try? fileManager.contentsOfDirectory(
                at: chatsURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { return [] }
            return entries.compactMap { entry in
                guard let chatID = Int(entry.lastPathComponent),
                      entry.lastPathComponent == String(chatID),
                      fileManager.fileExists(
                        atPath: entry.appendingPathComponent(documentFilename).path
                      ) else { return nil }
                return VersionChatID(versionID: version.id, chatID: chatID)
            }
        }
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static let iso8601Formatter = ISO8601DateFormatter()
}

private struct ResolvedContribution {
    let index: Int
    let contribution: ConversationContribution
    let exported: ExportedChat
}

private struct SourceMessageKey: Hashable {
    let contributionID: String
    let messageID: Int
}

private struct SourceMessage {
    let contribution: ResolvedContribution
    let messageIndex: Int
    let message: MessageInfo
    let fingerprint: String

    var key: SourceMessageKey {
        SourceMessageKey(
            contributionID: contribution.contribution.id,
            messageID: message.id
        )
    }
}

private struct MessageFingerprint: Encodable {
    let timestampMilliseconds: Int64
    let isFromMe: Bool
    let messageType: String
    let message: String?
    let caption: String?
    let authorIdentity: String?
    let mediaHash: String?
    let seconds: Int?
    let latitude: Double?
    let longitude: Double?
}

private struct SourceMediaKey: Hashable {
    let contributionID: String
    let filename: String
}

private final class MediaMaterializer {
    private let destinationURL: URL
    private var namesBySource: [SourceMediaKey: String] = [:]
    private var namesByHash: [String: String] = [:]
    private var byteCounts: [String: Int64] = [:]

    init(destinationURL: URL) {
        self.destinationURL = destinationURL
    }

    func materialize(
        filename: String,
        from contribution: ResolvedContribution
    ) throws -> String {
        let key = SourceMediaKey(
            contributionID: contribution.contribution.id,
            filename: filename
        )
        if let existing = namesBySource[key] { return existing }

        let sourceURL = contribution.exported.mediaDirectoryURL
            .appendingPathComponent(filename)
            .standardizedFileURL
        let hash = try ConversationArchiveService.fileHash(sourceURL)
        if let existing = namesByHash[hash] {
            namesBySource[key] = existing
            return existing
        }

        let safeName = URL(fileURLWithPath: filename).lastPathComponent
        let destinationName = "\(hash.prefix(12))-\(safeName)"
        let destinationFileURL = destinationURL.appendingPathComponent(destinationName)
        do {
            try FileManager.default.linkItem(at: sourceURL, to: destinationFileURL)
        } catch {
            try FileManager.default.copyItem(at: sourceURL, to: destinationFileURL)
        }
        let byteCount = Int64(
            (try? destinationFileURL.resourceValues(
                forKeys: [URLResourceKey.fileSizeKey]
            ).fileSize) ?? 0
        )
        namesBySource[key] = destinationName
        namesByHash[hash] = destinationName
        byteCounts[destinationName] = byteCount
        return destinationName
    }

    func materializeDirect(
        filename: String,
        from contribution: ResolvedContribution
    ) throws -> String {
        let key = SourceMediaKey(
            contributionID: contribution.contribution.id,
            filename: filename
        )
        if let existing = namesBySource[key] { return existing }

        let safeName = URL(fileURLWithPath: filename).lastPathComponent
        guard safeName == filename else {
            throw ConversationArchiveError.invalidArchive(
                contribution.exported.directoryURL,
                "Nombre multimedia no seguro: \(filename)"
            )
        }
        let sourceURL = contribution.exported.mediaDirectoryURL.appendingPathComponent(filename)
        let destinationFileURL = destinationURL.appendingPathComponent(safeName)
        do {
            try FileManager.default.linkItem(at: sourceURL, to: destinationFileURL)
        } catch {
            try FileManager.default.copyItem(at: sourceURL, to: destinationFileURL)
        }
        let byteCount = Int64(
            (try? destinationFileURL.resourceValues(
                forKeys: [URLResourceKey.fileSizeKey]
            ).fileSize) ?? 0
        )
        namesBySource[key] = safeName
        byteCounts[safeName] = byteCount
        return safeName
    }

    func byteCount(for filename: String) -> Int64 {
        byteCounts[filename] ?? 0
    }
}
