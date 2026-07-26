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
            return "Falta la copia guardada de origen \(selection.versionID)/\(selection.chatID)."
        case .contributionNotFound(let selection):
            return "La copia \(selection.versionID)/\(selection.chatID) no forma parte de ninguna conversación guardada."
        }
    }
}

struct ConversationArchiveUpdate {
    let conversation: ArchivedConversation
    let addedMessageCount: Int
}

struct ConversationIncorporationContext {
    let record: ConversationArchiveRecord?
    let previousMessageCount: Int
}

struct ConversationRemovalMessageImpact: Equatable {
    let contributionCount: Int
    let existingMessageCount: Int
    let sourceMessageCount: Int
    let removedMessageCount: Int
    let resultingMessageCount: Int
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

    /// Creates an interoperable conversation package.
    ///
    /// SwiftWABackupAPI owns package serialization and validation. Free My Chats
    /// owns choosing the destination and any later installation in its library.
    static func createPortableConversationArchive(
        from source: ConversationSource,
        producerVersion: String,
        destinationURL: URL,
        overwriteExisting: Bool = false,
        progress: WABackupProgressHandler? = nil,
        cancellation: WABackupCancellationHandler? = nil
    ) throws -> PortableConversationArchiveInfo {
        try PortableConversationArchiveCodec().createArchive(
            from: source,
            producer: PortableArchiveProducer(
                name: "Free My Chats",
                version: producerVersion
            ),
            destinationURL: destinationURL,
            overwriteExisting: overwriteExisting,
            progress: progress,
            cancellation: cancellation
        )
    }

    /// Performs a full, read-only integrity and safety inspection.
    static func inspectPortableConversationArchive(
        at archiveURL: URL,
        progress: WABackupProgressHandler? = nil,
        cancellation: WABackupCancellationHandler? = nil
    ) throws -> PortableConversationArchiveInfo {
        try PortableConversationArchiveCodec().inspectArchive(
            at: archiveURL,
            progress: progress,
            cancellation: cancellation
        )
    }

    /// Extracts only after the package has passed structural and content checks.
    ///
    /// The destination must be absent or empty. This method does not register the
    /// result in `library.json` and therefore remains a staging operation.
    static func extractPortableConversationArchive(
        at archiveURL: URL,
        to destinationDirectory: URL,
        progress: WABackupProgressHandler? = nil,
        cancellation: WABackupCancellationHandler? = nil
    ) throws -> PortableConversationDirectory {
        try PortableConversationArchiveCodec().extractValidatedArchive(
            at: archiveURL,
            to: destinationDirectory,
            progress: progress,
            cancellation: cancellation
        )
    }

    /// Builds a validated staging directory for a future imported contribution.
    /// The caller still owns installation, replacement and rollback in the library.
    static func stageCrossPerspectiveComposition(
        sources: [ConversationSource],
        targetSourceID: ConversationSourceID,
        perspectiveConstraints: [ConversationPerspectiveConstraint] = [],
        targetChatID: Int,
        destinationDirectory: URL,
        progress: WABackupProgressHandler? = nil,
        cancellation: WABackupCancellationHandler? = nil
    ) throws -> ConversationMaterializationResult {
        try ConversationCompositionEngine(policy: .conservativeDefault).compose(
            sources: sources,
            targetSourceID: targetSourceID,
            perspectiveConstraints: perspectiveConstraints,
            targetChatID: targetChatID,
            destinationDirectory: destinationDirectory,
            progress: progress,
            cancellation: cancellation
        )
    }

    static func catalog(in session: LibrarySession) throws -> [ExportedChatListItem] {
        try catalog(records: loadAvailableRecords(in: session), in: session)
    }

    static func prepareIncorporation(
        for chat: ChatInfo,
        in version: LibraryVersionSession,
        session: LibrarySession
    ) throws -> ConversationIncorporationContext {
        let resolved = identity(for: chat, in: version)
        let record = try loadAvailableRecords(in: session).first { $0.matches(resolved) }
        let previousMessageCount = try record.map {
            try openStoredConversation(record: $0, in: session).document.messages.count
        } ?? 0
        return ConversationIncorporationContext(
            record: record,
            previousMessageCount: previousMessageCount
        )
    }

    static func existingContributionCount(
        for chat: ChatInfo,
        in version: LibraryVersionSession,
        session: LibrarySession
    ) throws -> Int? {
        let resolved = identity(for: chat, in: version)
        return try loadAvailableRecords(in: session)
            .first(where: { $0.matches(resolved) })?
            .contributions.count
    }

    static func contributionCount(
        containing source: VersionChatID,
        in session: LibrarySession
    ) throws -> Int? {
        try loadAvailableRecords(in: session)
            .first(where: { record in
                record.contributions.contains(where: { $0.source == source })
            })?
            .contributions.count
    }

    static func removalMessageImpact(
        of source: VersionChatID,
        in session: LibrarySession,
        progress: WABackupProgressHandler? = nil
    ) throws -> ConversationRemovalMessageImpact {
        guard let record = try loadAvailableRecords(in: session).first(where: {
            $0.contributions.contains(where: { $0.source == source })
        }) else {
            throw ConversationArchiveError.contributionNotFound(source)
        }
        let resolved = try resolvedContributions(for: record, in: session)
        guard let selected = resolved.first(where: { $0.contribution.source == source }) else {
            throw ConversationArchiveError.contributionNotFound(source)
        }
        let compositionSources = try compositionSources(for: record, contributions: resolved)
        let sourceIDs = compositionSources.map(\.id)
        let targetSourceID = ConversationSourceID(
            rawValue: try compositionTarget(in: resolved).contribution.id
        )
        let preparation = try ConversationCompositionEngine().analyze(
            sources: compositionSources,
            targetSourceID: targetSourceID,
            perspectiveConstraints: [.samePerspective(sourceIDs: sourceIDs)],
            progress: progress
        )
        let impact = try preparation.plan.removalImpact(
            of: ConversationSourceID(rawValue: selected.contribution.id)
        )
        return ConversationRemovalMessageImpact(
            contributionCount: record.contributions.count,
            existingMessageCount: impact.currentMessageCount,
            sourceMessageCount: impact.sourceMessageCount,
            removedMessageCount: impact.removedMessageCount,
            resultingMessageCount: impact.resultingMessageCount
        )
    }

    static func storedRemovalMessageImpact(
        of source: VersionChatID,
        in session: LibrarySession
    ) throws -> ConversationRemovalMessageImpact? {
        guard let record = try loadAvailableRecords(in: session).first(where: {
            $0.contributions.contains(where: { $0.source == source })
        }), let contribution = record.contributions.first(where: { $0.source == source }) else {
            throw ConversationArchiveError.contributionNotFound(source)
        }
        guard let sourceMessageCount = contribution.messageCount,
              let removedMessageCount = contribution.exclusiveMessageCount else {
            return nil
        }
        let existingMessageCount = try record.summary?.numberMessages
            ?? openStoredConversation(record: record, in: session).document.messages.count
        return ConversationRemovalMessageImpact(
            contributionCount: record.contributions.count,
            existingMessageCount: existingMessageCount,
            sourceMessageCount: sourceMessageCount,
            removedMessageCount: removedMessageCount,
            resultingMessageCount: max(0, existingMessageCount - removedMessageCount)
        )
    }

    static func incorporate(
        _ exported: ExportedChat,
        source: VersionChatID,
        context: ConversationIncorporationContext,
        in session: LibrarySession,
        progress: WABackupProgressHandler? = nil
    ) throws -> ConversationArchiveUpdate {
        guard let version = session.version(id: source.versionID) else {
            throw ConversationArchiveError.missingSource(source)
        }
        let identity = identity(for: exported.document.chat, in: version)
        var record: ConversationArchiveRecord

        if let existing = context.record {
            guard existing.matches(identity) else {
                throw ConversationArchiveError.invalidArchive(
                    exported.directoryURL,
                    "La copia guardada ya no coincide con la conversación preparada."
                )
            }
            record = existing
        } else {
            record = ConversationArchiveRecord(key: identity.primaryKey)
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

        let conversation = try store(record: record, in: session, progress: progress)
        return ConversationArchiveUpdate(
            conversation: conversation,
            addedMessageCount: max(
                0,
                conversation.document.messages.count - context.previousMessageCount
            )
        )
    }

    static func restorePreparedRecord(
        from context: ConversationIncorporationContext,
        in session: LibrarySession
    ) throws {
        guard let record = context.record,
              record.contributions.count == 1 else { return }
        _ = try installSourceRecord(record: record, in: session)
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
        let records = try loadRecords(paths: paths) + loadSourceRecords(paths: paths)
        return Set(records.flatMap(\.identityKeys))
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

    static func openRepairing(
        item: ExportedChatListItem,
        in session: LibrarySession
    ) throws -> ArchivedConversation {
        guard item.contributionCount == 1 else {
            return try openRepairing(id: item.id, in: session)
        }

        let recordURL = item.directoryURL.appendingPathComponent(recordFilename)
        do {
            let record = try decoder().decode(
                ConversationArchiveRecord.self,
                from: Data(contentsOf: recordURL)
            )
            guard record.schemaVersion == ConversationArchiveRecord.currentSchemaVersion,
                  record.id == item.id,
                  record.contributions.count == 1 else {
                throw ConversationArchiveError.invalidArchive(
                    item.directoryURL,
                    "El manifiesto individual no corresponde a la conversación seleccionada."
                )
            }
            return try openSourceConversation(record: record, in: session)
        } catch let error as ConversationArchiveError {
            throw error
        } catch {
            throw ConversationArchiveError.invalidArchive(
                item.directoryURL,
                error.localizedDescription
            )
        }
    }

    static func openRepairing(
        id: ConversationArchiveID,
        in session: LibrarySession
    ) throws -> ArchivedConversation {
        if let sourceRecord = try loadSourceRecords(in: session).first(where: { $0.id == id }) {
            return try openSourceConversation(record: sourceRecord, in: session)
        }

        do {
            return try open(id: id, paths: session.paths)
        } catch let error as ConversationArchiveError {
            guard case .invalidArchive = error,
                  let record = try loadRecords(paths: session.paths).first(where: { $0.id == id })
            else {
                throw error
            }
            return try install(record: record, in: session)
        }
    }

    static func removeContribution(
        source: VersionChatID,
        from session: LibrarySession,
        progress: WABackupProgressHandler? = nil
    ) throws -> ConversationContributionRemoval {
        let record = try loadAvailableRecords(in: session).first {
            $0.contributions.contains(where: { $0.source == source })
        }
        guard var record else {
            throw ConversationArchiveError.contributionNotFound(source)
        }

        if record.contributions.count == 1 {
            let updatedSession = try LibraryService.deleteExportedChat(source, from: session)
            return ConversationContributionRemoval(
                session: updatedSession,
                conversationID: record.id,
                conversation: nil
            )
        }

        let archiveDirectoryURL = archiveURL(id: record.id, paths: session.paths)
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
            try fileManager.moveItem(at: archiveDirectoryURL, to: stagedArchiveURL)
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            throw error
        }

        do {
            let rebuilt = try store(record: record, in: session, progress: progress)
            let updatedSession = try LibraryService.deleteExportedChat(source, from: session)
            try? fileManager.removeItem(at: stagingURL)
            return ConversationContributionRemoval(
                session: updatedSession,
                conversationID: record.id,
                conversation: rebuilt
            )
        } catch {
            if record.contributions.count == 1,
               let remainingSource = record.contributions.first?.source,
               let version = session.version(id: remainingSource.versionID) {
                let sourceRecordURL = sourceDirectoryURL(remainingSource, in: version)
                    .appendingPathComponent(recordFilename)
                try? fileManager.removeItem(at: sourceRecordURL)
            } else {
                let replacementURL = archiveURL(id: record.id, paths: session.paths)
                if fileManager.fileExists(atPath: replacementURL.path) {
                    try? fileManager.removeItem(at: replacementURL)
                }
            }
            if fileManager.fileExists(atPath: stagedArchiveURL.path) {
                try? fileManager.moveItem(at: stagedArchiveURL, to: archiveDirectoryURL)
            }
            try? fileManager.removeItem(at: stagingURL)
            throw error
        }
    }

    private static func catalog(
        records: [ConversationArchiveRecord],
        in session: LibrarySession
    ) throws -> [ExportedChatListItem] {
        try records.map { record in
            let locations = try storageLocations(for: record, in: session)
            let chat: ChatInfo
            if let summary = record.summary {
                chat = summary
            } else {
                let archived = try openStoredConversation(record: record, in: session)
                chat = archived.document.chat
                var upgradedRecord = record
                upgradedRecord.summary = chat
                try encoder().encode(upgradedRecord).write(
                    to: locations.recordURL,
                    options: .atomic
                )
            }
            let photoURL = chat.photoFilename.map {
                locations.mediaURL.appendingPathComponent($0)
            }.flatMap {
                FileManager.default.fileExists(atPath: $0.path) ? $0 : nil
            }
            return ExportedChatListItem(
                id: record.id,
                chat: chat,
                exportedAt: record.updatedAt,
                contributionSources: record.contributions.map(\.source),
                directoryURL: locations.directoryURL,
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
        guard fileManager.fileExists(atPath: paths.mergedChatsURL.path) else { return [] }
        let entries = try fileManager.contentsOfDirectory(
            at: paths.mergedChatsURL,
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

    private static func loadAvailableRecords(
        in session: LibrarySession
    ) throws -> [ConversationArchiveRecord] {
        let materialized = try loadRecords(paths: session.paths)
        if let invalid = materialized.first(where: { $0.contributions.count < 2 }) {
            throw ConversationArchiveError.invalidArchive(
                archiveURL(id: invalid.id, paths: session.paths),
                "Las conversaciones materializadas deben contener varias copias guardadas."
            )
        }
        return materialized + (try loadSourceRecords(in: session))
    }

    private static func loadSourceRecords(
        in session: LibrarySession
    ) throws -> [ConversationArchiveRecord] {
        try sourceSelections(in: session).compactMap { source -> ConversationArchiveRecord? in
            guard let version = session.version(id: source.versionID) else { return nil }
            let directoryURL = sourceDirectoryURL(source, in: version)
            let recordURL = directoryURL.appendingPathComponent(recordFilename)
            guard FileManager.default.fileExists(atPath: recordURL.path) else { return nil }

            do {
                let record = try decoder().decode(
                    ConversationArchiveRecord.self,
                    from: Data(contentsOf: recordURL)
                )
                guard record.schemaVersion == ConversationArchiveRecord.currentSchemaVersion,
                      record.contributions.count == 1,
                      record.contributions.first?.source == source else {
                    throw ConversationArchiveError.invalidArchive(
                        directoryURL,
                        "El manifiesto individual no corresponde a esta copia guardada."
                    )
                }
                return record
            } catch let error as ConversationArchiveError {
                throw error
            } catch {
                throw ConversationArchiveError.invalidArchive(
                    directoryURL,
                    error.localizedDescription
                )
            }
        }
    }

    private static func loadSourceRecords(
        paths: LibraryPaths
    ) throws -> [ConversationArchiveRecord] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: paths.exportsURL.path) else { return [] }
        let exportDirectories = try fileManager.contentsOfDirectory(
            at: paths.exportsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var records: [ConversationArchiveRecord] = []
        for exportDirectory in exportDirectories {
            guard (try? exportDirectory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory)
                == true else { continue }
            let chatsURL = exportDirectory.appendingPathComponent("Chats", isDirectory: true)
            guard fileManager.fileExists(atPath: chatsURL.path) else { continue }
            let chatDirectories = try fileManager.contentsOfDirectory(
                at: chatsURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            for chatDirectory in chatDirectories {
                guard (try? chatDirectory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory)
                    == true else { continue }
                let recordURL = chatDirectory.appendingPathComponent(recordFilename)
                guard fileManager.fileExists(atPath: recordURL.path) else { continue }
                records.append(
                    try decoder().decode(
                        ConversationArchiveRecord.self,
                        from: Data(contentsOf: recordURL)
                    )
                )
            }
        }
        return records
    }

    private static func openStoredConversation(
        record: ConversationArchiveRecord,
        in session: LibrarySession
    ) throws -> ArchivedConversation {
        if record.contributions.count == 1 {
            return try openSourceConversation(record: record, in: session)
        }
        return try open(id: record.id, paths: session.paths)
    }

    private static func openSourceConversation(
        record: ConversationArchiveRecord,
        in session: LibrarySession
    ) throws -> ArchivedConversation {
        guard record.contributions.count == 1,
              let source = record.contributions.first?.source,
              let version = session.version(id: source.versionID) else {
            throw ConversationArchiveError.invalidArchive(
                session.paths.rootURL,
                "La conversación individual no tiene una copia de origen válida."
            )
        }
        let exported = try version.exportStore.openChat(chatId: source.chatID)
        let documentKey = ConversationIdentityKey(chat: exported.document.chat)
        guard record.identityKeys.contains(documentKey) else {
            throw ConversationArchiveError.invalidArchive(
                exported.directoryURL,
                "La identidad del chat no coincide con su manifiesto."
            )
        }
        return ArchivedConversation(
            record: record,
            document: exported.document,
            directoryURL: exported.directoryURL,
            documentURL: exported.directoryURL.appendingPathComponent(documentFilename),
            mediaDirectoryURL: exported.mediaDirectoryURL
        )
    }

    private static func storageLocations(
        for record: ConversationArchiveRecord,
        in session: LibrarySession
    ) throws -> (
        directoryURL: URL,
        recordURL: URL,
        mediaURL: URL
    ) {
        if record.contributions.count > 1 {
            let materializedURL = archiveURL(id: record.id, paths: session.paths)
            return (
                materializedURL,
                materializedURL.appendingPathComponent(recordFilename),
                materializedURL.appendingPathComponent(mediaDirectoryName, isDirectory: true)
            )
        }
        guard record.contributions.count == 1,
              let source = record.contributions.first?.source,
              let version = session.version(id: source.versionID) else {
            throw ConversationArchiveError.invalidArchive(
                session.paths.rootURL,
                "No se ha encontrado la representación física de la conversación."
            )
        }
        let directoryURL = sourceDirectoryURL(source, in: version)
        return (
            directoryURL,
            directoryURL.appendingPathComponent(recordFilename),
            directoryURL.appendingPathComponent(mediaDirectoryName, isDirectory: true)
        )
    }

    private static func identity(
        for chat: ChatInfo,
        in version: LibraryVersionSession
    ) -> ResolvedConversationIdentity {
        ConversationIdentityResolver(
            backupURL: version.hasSourceBackup ? version.backupURL : nil
        ).identity(for: chat)
    }

    private static func store(
        record: ConversationArchiveRecord,
        in session: LibrarySession,
        progress: WABackupProgressHandler? = nil
    ) throws -> ArchivedConversation {
        if record.contributions.count == 1 {
            return try installSourceRecord(record: record, in: session)
        }
        return try installCombinedRecord(record: record, in: session, progress: progress)
    }

    private static func installSourceRecord(
        record: ConversationArchiveRecord,
        in session: LibrarySession
    ) throws -> ArchivedConversation {
        guard record.contributions.count == 1,
              let source = record.contributions.first?.source,
              let version = session.version(id: source.versionID) else {
            throw ConversationArchiveError.invalidArchive(
                session.paths.rootURL,
                "La conversación individual no tiene una copia de origen válida."
            )
        }
        let exported = try version.exportStore.openChat(chatId: source.chatID)
        let documentKey = ConversationIdentityKey(chat: exported.document.chat)
        guard record.identityKeys.contains(documentKey) else {
            throw ConversationArchiveError.invalidArchive(
                exported.directoryURL,
                "La identidad del chat no coincide con su manifiesto."
            )
        }

        var installedRecord = record
        let messageCount = exported.document.messages.count
        installedRecord.contributions[0] = installedRecord.contributions[0].withMessageCounts(
            total: messageCount,
            exclusive: messageCount
        )
        installedRecord.summary = exported.document.chat
        try encoder().encode(installedRecord).write(
            to: exported.directoryURL.appendingPathComponent(recordFilename),
            options: .atomic
        )
        return try openSourceConversation(record: installedRecord, in: session)
    }

    private static func installCombinedRecord(
        record: ConversationArchiveRecord,
        in session: LibrarySession,
        progress: WABackupProgressHandler? = nil
    ) throws -> ArchivedConversation {
        guard record.contributions.count > 1 else {
            throw ConversationArchiveError.invalidArchive(
                session.paths.rootURL,
                "Una conversación combinada requiere varias copias guardadas."
            )
        }

        let fileManager = FileManager.default
        let stagingURL = session.paths.rootURL.appendingPathComponent(
            ".promoting-conversation-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: false)
        var stagedRecords: [(original: URL, staged: URL)] = []

        do {
            for (index, contribution) in record.contributions.enumerated() {
                guard let version = session.version(id: contribution.source.versionID) else {
                    throw ConversationArchiveError.missingSource(contribution.source)
                }
                let originalURL = sourceDirectoryURL(contribution.source, in: version)
                    .appendingPathComponent(recordFilename)
                guard fileManager.fileExists(atPath: originalURL.path) else { continue }
                let stagedURL = stagingURL.appendingPathComponent("\(index)-\(recordFilename)")
                // Keep the source conversation visible until the combined
                // replacement is fully installed. A force quit during the
                // expensive composition can then leave only disposable staging,
                // never a missing catalog entry.
                try fileManager.copyItem(at: originalURL, to: stagedURL)
                stagedRecords.append((originalURL, stagedURL))
            }

            let conversation = try install(record: record, in: session, progress: progress)
            for item in stagedRecords where fileManager.fileExists(atPath: item.original.path) {
                // Retire the source record only after the combined archive is
                // durable. Reusing its staged backup keeps this final move
                // recoverable until the staging directory is removed.
                try? fileManager.removeItem(at: item.staged)
                try? fileManager.moveItem(at: item.original, to: item.staged)
            }
            try? fileManager.removeItem(at: stagingURL)
            return conversation
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            throw error
        }
    }

    private static func install(
        record: ConversationArchiveRecord,
        in session: LibrarySession,
        progress: WABackupProgressHandler? = nil
    ) throws -> ArchivedConversation {
        let resolved = try resolvedContributions(for: record, in: session)
        guard !resolved.isEmpty else {
            throw ConversationArchiveError.invalidArchive(
                archiveURL(id: record.id, paths: session.paths),
                "No contiene ninguna aportación."
            )
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: session.paths.mergedChatsURL,
            withIntermediateDirectories: true
        )
        let temporaryURL = session.paths.mergedChatsURL.appendingPathComponent(
            ".building-\(record.id.rawValue)-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: temporaryURL, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: temporaryURL) }

        let sources = try compositionSources(for: record, contributions: resolved)
        let sourceIDs = sources.map(\.id)
        let target = try compositionTarget(in: resolved)
        let result = try ConversationCompositionEngine().compose(
            sources: sources,
            targetSourceID: ConversationSourceID(rawValue: target.contribution.id),
            perspectiveConstraints: [.samePerspective(sourceIDs: sourceIDs)],
            targetChatID: resolved[0].exported.document.chat.id,
            destinationDirectory: temporaryURL,
            progress: progress
        )
        let document = result.document
        var installedRecord = record
        installedRecord.summary = document.chat
        let impactsByID = Dictionary(
            uniqueKeysWithValues: result.sourceImpacts.map { ($0.sourceID.rawValue, $0) }
        )
        installedRecord.contributions = record.contributions.map { contribution in
            guard let impact = impactsByID[contribution.id] else {
                return contribution
            }
            return contribution.withMessageCounts(
                total: impact.sourceMessageCount,
                exclusive: impact.exclusiveMessageCount
            )
        }
        try encoder().encode(installedRecord).write(
            to: temporaryURL.appendingPathComponent(recordFilename),
            options: .atomic
        )
        try validateMedia(document: document, at: result.mediaDirectoryURL)

        let finalURL = archiveURL(id: record.id, paths: session.paths)
        if fileManager.fileExists(atPath: finalURL.path) {
            let previousURL = session.paths.mergedChatsURL.appendingPathComponent(
                ".replacing-\(record.id.rawValue)-\(UUID().uuidString)",
                isDirectory: true
            )
            try fileManager.moveItem(at: finalURL, to: previousURL)
            do {
                try fileManager.moveItem(at: temporaryURL, to: finalURL)
                try fileManager.removeItem(at: previousURL)
            } catch {
                if fileManager.fileExists(atPath: finalURL.path) {
                    try? fileManager.removeItem(at: finalURL)
                }
                if fileManager.fileExists(atPath: previousURL.path) {
                    try? fileManager.moveItem(at: previousURL, to: finalURL)
                }
                throw error
            }
        } else {
            try fileManager.moveItem(at: temporaryURL, to: finalURL)
        }
        var visibleFinalURL = finalURL
        var resourceValues = URLResourceValues()
        resourceValues.isHidden = false
        try visibleFinalURL.setResourceValues(resourceValues)
        return try open(id: installedRecord.id, paths: session.paths)
    }

    private static func resolvedContributions(
        for record: ConversationArchiveRecord,
        in session: LibrarySession
    ) throws -> [ResolvedContribution] {
        try record.contributions.map { contribution in
            guard let version = session.version(id: contribution.source.versionID) else {
                throw ConversationArchiveError.missingSource(contribution.source)
            }
            return ResolvedContribution(
                contribution: contribution,
                exported: try version.exportStore.openChat(chatId: contribution.source.chatID)
            )
        }
    }

    private static func compositionSources(
        for record: ConversationArchiveRecord,
        contributions: [ResolvedContribution]
    ) throws -> [ConversationSource] {
        let identityHint = conversationIdentityHint(for: record)
        return try contributions.map { resolved in
            try ConversationSource(
                id: ConversationSourceID(rawValue: resolved.contribution.id),
                exportedChat: resolved.exported,
                conversationIdentityHint: identityHint
            )
        }
    }

    private static func compositionTarget(
        in contributions: [ResolvedContribution]
    ) throws -> ResolvedContribution {
        guard let target = contributions.max(by: {
            $0.contribution.exportedAt < $1.contribution.exportedAt
        }) else {
            throw ConversationCompositionError.noSources
        }
        return target
    }

    /// Identifies the other participant of an individual conversation. This is
    /// conversation identity, not the owner represented by `isFromMe`.
    private static func conversationIdentityHint(
        for record: ConversationArchiveRecord
    ) -> CanonicalParticipantIdentity? {
        guard record.key.chatType == .individual else { return nil }
        let addresses = record.identityKeys.compactMap {
            participantAddress(for: $0.contactJID)
        }
        guard !addresses.isEmpty else { return nil }
        return CanonicalParticipantIdentity(addresses: addresses)
    }

    private static func participantAddress(for rawValue: String) -> ParticipantAddress? {
        let value = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if value.hasSuffix("@s.whatsapp.net") {
            return ParticipantAddress(kind: .phoneJID, value: value)
        }
        if value.hasSuffix("@lid") {
            return ParticipantAddress(kind: .lidJID, value: value)
        }
        let digits = value.filter(\.isNumber)
        if !digits.isEmpty, value.allSatisfy({ $0.isNumber || $0 == "+" }) {
            return ParticipantAddress(kind: .phone, value: digits)
        }
        return nil
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

    private static func archiveURL(id: ConversationArchiveID, paths: LibraryPaths) -> URL {
        paths.mergedChatsURL.appendingPathComponent(id.rawValue, isDirectory: true)
    }

    private static func sourceDirectoryURL(
        _ source: VersionChatID,
        in version: LibraryVersionSession
    ) -> URL {
        version.exportsURL
            .appendingPathComponent("Chats", isDirectory: true)
            .appendingPathComponent(String(source.chatID), isDirectory: true)
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

}

private struct ResolvedContribution {
    let contribution: ConversationContribution
    let exported: ExportedChat
}
