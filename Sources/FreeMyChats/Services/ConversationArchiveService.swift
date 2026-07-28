import Foundation
import SwiftWABackupAPI

enum ConversationArchiveError: Error, LocalizedError {
    case invalidArchive(URL, String)
    case missingSource(VersionChatID)
    case contributionNotFound(VersionChatID)
    case noMatchingConversation(String)
    case ambiguousMatchingConversations([String])
    case importedConversationAlreadyExists(String)
    case importedContributionNotFound(String)
    case cannotRemoveLastLocalContribution(String)
    case contributionIsNotUnified(VersionChatID)

    var errorDescription: String? {
        switch self {
        case .invalidArchive(let url, let reason):
            return "La conversación guardada en \(url.lastPathComponent) no es válida: \(reason)"
        case .missingSource(let selection):
            return "Falta la copia guardada de origen \(selection.versionID)/\(selection.chatID)."
        case .contributionNotFound(let selection):
            return "La copia \(selection.versionID)/\(selection.chatID) no forma parte de ninguna conversación guardada."
        case .noMatchingConversation(let name):
            return "No hay en esta biblioteca ninguna conversación compatible con “\(name)”. "
                + "El chat exportado solo se puede añadir a una conversación que ya exista."
        case .ambiguousMatchingConversations(let names):
            return "El chat exportado coincide de forma segura con varias conversaciones "
                + "(\(names.joined(separator: ", "))). No se ha importado para evitar elegir una incorrecta."
        case .importedConversationAlreadyExists(let name):
            return "Esta exportación de “\(name)” ya se había importado en la biblioteca."
        case .importedContributionNotFound:
            return "El chat importado ya no forma parte de ninguna conversación de la biblioteca."
        case .cannotRemoveLastLocalContribution(let name):
            return "No se puede borrar la última copia local de “\(name)” mientras conserve chats importados, "
                + "porque esa copia fija la perspectiva local de la Vista unificada."
        case .contributionIsNotUnified(let selection):
            return "La copia \(selection.versionID)/\(selection.chatID) no forma parte de una Vista unificada."
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

struct ConversationContributionDetachment {
    let conversation: ArchivedConversation
}

struct PortableConversationImportResult {
    let session: LibrarySession
    let conversation: ArchivedConversation
    let importedContribution: ImportedConversationContribution
    let addedMessageCount: Int
}

struct ImportedConversationRemoval {
    let conversation: ArchivedConversation
    let removedContribution: ImportedConversationContribution
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

    static func createPortableConversationArchive(
        from conversation: ArchivedConversation,
        producerVersion: String,
        destinationURL: URL,
        progress: WABackupProgressHandler? = nil,
        cancellation: WABackupCancellationHandler? = nil
    ) throws -> PortableConversationArchiveInfo {
        let source = try ConversationSource(
            id: ConversationSourceID(rawValue: "export-\(UUID().uuidString.lowercased())"),
            document: conversation.document,
            mediaDirectoryURL: conversation.mediaDirectoryURL,
            conversationIdentityHint: conversationIdentityHint(for: conversation.record)
        )
        return try createPortableConversationArchive(
            from: source,
            producerVersion: producerVersion,
            destinationURL: destinationURL,
            progress: progress,
            cancellation: cancellation
        )
    }

    static func createPortableConversationArchive(
        for conversationID: ConversationArchiveID,
        in session: LibrarySession,
        producerVersion: String,
        destinationURL: URL,
        progress: WABackupProgressHandler? = nil,
        cancellation: WABackupCancellationHandler? = nil
    ) throws -> PortableConversationArchiveInfo {
        let conversation = try openRepairing(id: conversationID, in: session)
        return try createPortableConversationArchive(
            from: conversation,
            producerVersion: producerVersion,
            destinationURL: destinationURL,
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

    static func importPortableConversationArchive(
        at archiveURL: URL,
        into session: LibrarySession,
        progress: WABackupProgressHandler? = nil,
        cancellation: WABackupCancellationHandler? = nil
    ) throws -> PortableConversationImportResult {
        let archiveInfo = try inspectPortableConversationArchive(
            at: archiveURL,
            progress: progress,
            cancellation: cancellation
        )
        let records = try loadAvailableRecords(in: session)
        if records.contains(where: {
            $0.importedContributions.contains {
                $0.packageID == archiveInfo.manifest.packageID
                    || $0.contentDigest == archiveInfo.manifest.contentDigest
            }
        }) {
            throw ConversationArchiveError.importedConversationAlreadyExists(
                archiveInfo.manifest.conversation.displayName
            )
        }

        let fileManager = FileManager.default
        let stagingRoot = session.paths.rootURL.appendingPathComponent(
            ".importing-chat-\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        let extractedURL = stagingRoot.appendingPathComponent("ImportedChat", isDirectory: true)
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: stagingRoot) }

        let portableDirectory = try extractPortableConversationArchive(
            at: archiveURL,
            to: extractedURL,
            progress: progress,
            cancellation: cancellation
        )
        let matchedRecord = try matchingRecord(
            for: portableDirectory,
            among: records,
            in: session,
            progress: progress,
            cancellation: cancellation
        )
        let previousMessageCount = try openStoredConversation(
            record: matchedRecord,
            in: session
        ).document.messages.count

        let importID = UUID().uuidString.lowercased()
        let relativeDirectory = "\(matchedRecord.id.rawValue)/\(importID)"
        let contribution = ImportedConversationContribution(
            id: importID,
            packageID: archiveInfo.manifest.packageID,
            packageCreatedAt: archiveInfo.manifest.createdAt,
            producerName: archiveInfo.manifest.producer.name,
            producerVersion: archiveInfo.manifest.producer.version,
            relativeDirectory: relativeDirectory,
            archiveSHA256: archiveInfo.archiveSHA256,
            contentDigest: archiveInfo.manifest.contentDigest,
            displayName: archiveInfo.manifest.conversation.displayName
        )
        let finalImportURL = session.paths.importedConversationURL(
            conversationID: matchedRecord.id,
            importID: importID
        )
        try fileManager.createDirectory(
            at: finalImportURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.moveItem(at: extractedURL, to: finalImportURL)
        var visibleImportURL = finalImportURL
        var resourceValues = URLResourceValues()
        resourceValues.isHidden = false
        try? visibleImportURL.setResourceValues(resourceValues)

        var upgradedManifest = session.manifest
        let previousManifest = upgradedManifest
        upgradedManifest.schemaVersion = LibraryManifest.currentSchemaVersion
        var record = matchedRecord
        record.markCurrentSchema()
        record.importedContributions.append(contribution)
        record.updatedAt = Date()
        let upgradedSession = LibrarySession(
            paths: session.paths,
            manifest: upgradedManifest,
            versions: session.versions
        )

        do {
            if previousManifest.schemaVersion != upgradedManifest.schemaVersion {
                try LibraryService.write(upgradedManifest, to: session.paths.manifestURL)
            }
            let conversation = try store(
                record: record,
                in: upgradedSession,
                progress: progress,
                cancellation: cancellation
            )
            let installedContribution = conversation.record.importedContributions.first {
                $0.id == importID
            } ?? contribution
            return PortableConversationImportResult(
                session: upgradedSession,
                conversation: conversation,
                importedContribution: installedContribution,
                addedMessageCount: max(
                    0,
                    conversation.document.messages.count - previousMessageCount
                )
            )
        } catch {
            try? fileManager.removeItem(at: finalImportURL)
            try? removeDirectoryIfEmpty(finalImportURL.deletingLastPathComponent())
            if previousManifest.schemaVersion != upgradedManifest.schemaVersion {
                try? LibraryService.write(previousManifest, to: session.paths.manifestURL)
            }
            throw error
        }
    }

    /// Builds a validated staging directory for a cross-perspective contribution.
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

    static func catalog(in session: LibrarySession) throws -> [ConversationCatalogItem] {
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
            .totalContributionCount
    }

    static func existingContributionCounts(
        for chats: [(selection: VersionChatID, chat: ChatInfo, version: LibraryVersionSession)],
        in session: LibrarySession
    ) throws -> [VersionChatID: Int] {
        let records = try loadAvailableRecords(in: session)
        return Dictionary(uniqueKeysWithValues: chats.compactMap { candidate in
            let resolved = identity(for: candidate.chat, in: candidate.version)
            guard let record = records.first(where: { $0.matches(resolved) }) else {
                return nil
            }
            return (candidate.selection, record.totalContributionCount)
        })
    }

    static func contributionCount(
        containing source: VersionChatID,
        in session: LibrarySession
    ) throws -> Int? {
        try loadAvailableRecords(in: session)
            .first(where: { record in
                record.contributions.contains(where: { $0.source == source })
            })?
            .totalContributionCount
    }

    static func incorporatedContributionSources(
        in session: LibrarySession
    ) throws -> Set<VersionChatID> {
        Set(try loadAvailableRecords(in: session).flatMap {
            $0.contributions.map(\.source)
        })
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
        let localSources = try compositionSources(for: record, contributions: resolved)
        let importedSources = try resolvedImportedContributions(for: record, in: session).map {
            try $0.directory.makeConversationSource(
                id: ConversationSourceID(rawValue: $0.contribution.id),
                perspectiveHint: $0.contribution.perspectiveHint
            )
        }
        let compositionSources = localSources + importedSources
        let targetSourceID = ConversationSourceID(
            rawValue: try compositionTarget(in: resolved).contribution.id
        )
        let engine = ConversationCompositionEngine(
            policy: importedSources.isEmpty ? .currentUnifiedView : .conservativeDefault
        )
        let constraints: [ConversationPerspectiveConstraint]
        if importedSources.isEmpty || localSources.count > 1 {
            constraints = [.samePerspective(sourceIDs: localSources.map(\.id))]
        } else {
            constraints = []
        }
        let preparation = try engine.analyze(
            sources: compositionSources,
            targetSourceID: targetSourceID,
            perspectiveConstraints: constraints,
            progress: progress
        )
        let impact = try preparation.plan.removalImpact(
            of: ConversationSourceID(rawValue: selected.contribution.id)
        )
        return ConversationRemovalMessageImpact(
            contributionCount: record.totalContributionCount,
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
            contributionCount: record.totalContributionCount,
            existingMessageCount: existingMessageCount,
            sourceMessageCount: sourceMessageCount,
            removedMessageCount: removedMessageCount,
            resultingMessageCount: max(0, existingMessageCount - removedMessageCount)
        )
    }

    static func incorporate(
        _ stored: StoredChat,
        source: VersionChatID,
        context: ConversationIncorporationContext,
        in session: LibrarySession,
        progress: WABackupProgressHandler? = nil
    ) throws -> ConversationArchiveUpdate {
        guard let version = session.version(id: source.versionID) else {
            throw ConversationArchiveError.missingSource(source)
        }
        let identity = identity(for: stored.document.chat, in: version)
        var record: ConversationArchiveRecord

        if let existing = context.record {
            guard existing.matches(identity) else {
                throw ConversationArchiveError.invalidArchive(
                    stored.directoryURL,
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
                storedAt: stored.document.storedAt
            )
        } else {
            record.contributions.append(
                ConversationContribution(source: source, storedAt: stored.document.storedAt)
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
              record.contributions.count == 1,
              record.importedContributions.isEmpty else { return }
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
            guard record.isSupported,
                  record.id == id else {
                throw ConversationArchiveError.invalidArchive(
                    directoryURL,
                    "El manifiesto tiene una versión o identidad incompatible."
                )
            }

            let document = try decoder().decode(
                StoredChatDocument.self,
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
        item: ConversationCatalogItem,
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
            guard record.isSupported,
                  record.id == item.id,
                  record.contributions.count == 1,
                  record.importedContributions.isEmpty else {
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

        if record.contributions.count == 1, !record.importedContributions.isEmpty {
            throw ConversationArchiveError.cannotRemoveLastLocalContribution(
                record.summary?.name ?? "esta conversación"
            )
        }

        if record.totalContributionCount == 1 {
            let updatedSession = try LibraryService.deleteStoredChat(source, from: session)
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
            let updatedSession = try LibraryService.deleteStoredChat(source, from: session)
            try? fileManager.removeItem(at: stagingURL)
            return ConversationContributionRemoval(
                session: updatedSession,
                conversationID: record.id,
                conversation: rebuilt
            )
        } catch {
            if record.importedContributions.isEmpty,
               record.contributions.count == 1,
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

    static func detachContribution(
        source: VersionChatID,
        from session: LibrarySession,
        progress: WABackupProgressHandler? = nil
    ) throws -> ConversationContributionDetachment {
        guard var record = try loadAvailableRecords(in: session).first(where: {
            $0.contributions.contains(where: { $0.source == source })
        }) else {
            throw ConversationArchiveError.contributionNotFound(source)
        }
        guard record.totalContributionCount > 1 else {
            throw ConversationArchiveError.contributionIsNotUnified(source)
        }
        if record.contributions.count == 1, !record.importedContributions.isEmpty {
            throw ConversationArchiveError.cannotRemoveLastLocalContribution(
                record.summary?.name ?? "esta conversación"
            )
        }

        record.contributions.removeAll { $0.source == source }
        record.updatedAt = Date()

        let archiveDirectoryURL = archiveURL(id: record.id, paths: session.paths)
        let fileManager = FileManager.default
        let stagingURL = session.paths.rootURL.appendingPathComponent(
            ".detaching-contribution-\(UUID().uuidString)",
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
            try? fileManager.removeItem(at: stagingURL)
            return ConversationContributionDetachment(
                conversation: rebuilt
            )
        } catch {
            removeInstalledRecord(record, in: session)
            if fileManager.fileExists(atPath: stagedArchiveURL.path) {
                try? fileManager.moveItem(at: stagedArchiveURL, to: archiveDirectoryURL)
            }
            try? fileManager.removeItem(at: stagingURL)
            throw error
        }
    }

    static func removeImportedContribution(
        id importID: String,
        from session: LibrarySession,
        progress: WABackupProgressHandler? = nil,
        cancellation: WABackupCancellationHandler? = nil
    ) throws -> ImportedConversationRemoval {
        guard var record = try loadAvailableRecords(in: session).first(where: {
            $0.importedContributions.contains(where: { $0.id == importID })
        }), let removed = record.importedContributions.first(where: { $0.id == importID }) else {
            throw ConversationArchiveError.importedContributionNotFound(importID)
        }
        record.importedContributions.removeAll { $0.id == importID }
        record.markCurrentSchema()
        record.updatedAt = Date()

        let fileManager = FileManager.default
        let archiveDirectoryURL = archiveURL(id: record.id, paths: session.paths)
        let stagingURL = session.paths.rootURL.appendingPathComponent(
            ".removing-imported-chat-\(UUID().uuidString.lowercased())",
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
            let rebuilt = try store(
                record: record,
                in: session,
                progress: progress,
                cancellation: cancellation
            )
            let importedURL = importedContributionURL(removed, in: session)
            try fileManager.removeItem(at: importedURL)
            try? removeDirectoryIfEmpty(importedURL.deletingLastPathComponent())
            try? fileManager.removeItem(at: stagingURL)
            return ImportedConversationRemoval(
                conversation: rebuilt,
                removedContribution: removed
            )
        } catch {
            if record.importedContributions.isEmpty, record.contributions.count == 1,
               let remainingSource = record.contributions.first?.source,
               let version = session.version(id: remainingSource.versionID) {
                try? fileManager.removeItem(
                    at: sourceDirectoryURL(remainingSource, in: version)
                        .appendingPathComponent(recordFilename)
                )
            } else {
                try? fileManager.removeItem(at: archiveDirectoryURL)
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
    ) throws -> [ConversationCatalogItem] {
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
            return ConversationCatalogItem(
                id: record.id,
                chat: chat,
                updatedAt: record.updatedAt,
                contributionSources: record.contributions.map(\.source),
                localContributionMessageCounts: Dictionary(
                    uniqueKeysWithValues: record.contributions.compactMap { contribution in
                        contribution.exclusiveMessageCount.map {
                            (contribution.source, $0)
                        }
                    }
                ),
                importedContributions: record.importedContributions,
                directoryURL: locations.directoryURL,
                photoURL: photoURL
            )
        }.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
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
        if let invalid = materialized.first(where: {
            !$0.isSupported
                || ($0.importedContributions.isEmpty && $0.contributions.count < 2)
                || $0.contributions.isEmpty
        }) {
            throw ConversationArchiveError.invalidArchive(
                archiveURL(id: invalid.id, paths: session.paths),
                "La conversación materializada tiene una versión o una combinación de aportaciones no válida."
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
                guard record.isSupported,
                      record.contributions.count == 1,
                      record.importedContributions.isEmpty,
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
        guard fileManager.fileExists(atPath: paths.storedChatsURL.path) else { return [] }
        let storageDirectories = try fileManager.contentsOfDirectory(
            at: paths.storedChatsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var records: [ConversationArchiveRecord] = []
        for storageDirectory in storageDirectories {
            guard (try? storageDirectory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory)
                == true else { continue }
            let chatsURL = storageDirectory.appendingPathComponent("Chats", isDirectory: true)
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
        if record.contributions.count == 1, record.importedContributions.isEmpty {
            return try openSourceConversation(record: record, in: session)
        }
        return try open(id: record.id, paths: session.paths)
    }

    private static func openSourceConversation(
        record: ConversationArchiveRecord,
        in session: LibrarySession
    ) throws -> ArchivedConversation {
        guard record.contributions.count == 1,
              record.importedContributions.isEmpty,
              let source = record.contributions.first?.source,
              let version = session.version(id: source.versionID) else {
            throw ConversationArchiveError.invalidArchive(
                session.paths.rootURL,
                "La conversación individual no tiene una copia de origen válida."
            )
        }
        let stored = try version.storedChatStore.openChat(chatId: source.chatID)
        let documentKey = ConversationIdentityKey(chat: stored.document.chat)
        guard record.identityKeys.contains(documentKey) else {
            throw ConversationArchiveError.invalidArchive(
                stored.directoryURL,
                "La identidad del chat no coincide con su manifiesto."
            )
        }
        return ArchivedConversation(
            record: record,
            document: stored.document,
            directoryURL: stored.directoryURL,
            documentURL: stored.directoryURL.appendingPathComponent(documentFilename),
            mediaDirectoryURL: stored.mediaDirectoryURL
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
        if record.contributions.count > 1 || !record.importedContributions.isEmpty {
            let materializedURL = archiveURL(id: record.id, paths: session.paths)
            return (
                materializedURL,
                materializedURL.appendingPathComponent(recordFilename),
                materializedURL.appendingPathComponent(mediaDirectoryName, isDirectory: true)
            )
        }
        guard record.contributions.count == 1,
              record.importedContributions.isEmpty,
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
        progress: WABackupProgressHandler? = nil,
        cancellation: WABackupCancellationHandler? = nil
    ) throws -> ArchivedConversation {
        if record.contributions.count == 1, record.importedContributions.isEmpty {
            return try installSourceRecord(record: record, in: session)
        }
        return try installCombinedRecord(
            record: record,
            in: session,
            progress: progress,
            cancellation: cancellation
        )
    }

    private static func installSourceRecord(
        record: ConversationArchiveRecord,
        in session: LibrarySession
    ) throws -> ArchivedConversation {
        guard record.contributions.count == 1,
              record.importedContributions.isEmpty,
              let source = record.contributions.first?.source,
              let version = session.version(id: source.versionID) else {
            throw ConversationArchiveError.invalidArchive(
                session.paths.rootURL,
                "La conversación individual no tiene una copia de origen válida."
            )
        }
        let stored = try version.storedChatStore.openChat(chatId: source.chatID)
        let documentKey = ConversationIdentityKey(chat: stored.document.chat)
        guard record.identityKeys.contains(documentKey) else {
            throw ConversationArchiveError.invalidArchive(
                stored.directoryURL,
                "La identidad del chat no coincide con su manifiesto."
            )
        }

        var installedRecord = record
        let messageCount = stored.document.messages.count
        installedRecord.contributions[0] = installedRecord.contributions[0].withMessageCounts(
            total: messageCount,
            exclusive: messageCount
        )
        installedRecord.summary = stored.document.chat
        try encoder().encode(installedRecord).write(
            to: stored.directoryURL.appendingPathComponent(recordFilename),
            options: .atomic
        )
        return try openSourceConversation(record: installedRecord, in: session)
    }

    private static func installCombinedRecord(
        record: ConversationArchiveRecord,
        in session: LibrarySession,
        progress: WABackupProgressHandler? = nil,
        cancellation: WABackupCancellationHandler? = nil
    ) throws -> ArchivedConversation {
        guard record.totalContributionCount > 1,
              !record.contributions.isEmpty else {
            throw ConversationArchiveError.invalidArchive(
                session.paths.rootURL,
                "Una conversación combinada requiere una copia local y otra aportación."
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

            let conversation = try install(
                record: record,
                in: session,
                progress: progress,
                cancellation: cancellation
            )
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
        progress: WABackupProgressHandler? = nil,
        cancellation: WABackupCancellationHandler? = nil
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

        let target = try compositionTarget(in: resolved)
        let localSources = try compositionSources(for: record, contributions: resolved)
        let imported = try resolvedImportedContributions(for: record, in: session)
        let importedSources = try imported.map {
            try $0.directory.makeConversationSource(
                id: ConversationSourceID(rawValue: $0.contribution.id),
                perspectiveHint: $0.contribution.perspectiveHint
            )
        }
        let localTargetSourceID = ConversationSourceID(rawValue: target.contribution.id)
        let result: ConversationMaterializationResult
        let localMessageCountsByID: [String: ContributionMessageCounts]

        if importedSources.isEmpty {
            result = try ConversationCompositionEngine(policy: .currentUnifiedView).compose(
                sources: localSources,
                targetSourceID: localTargetSourceID,
                perspectiveConstraints: [
                    .samePerspective(sourceIDs: localSources.map(\.id))
                ],
                targetChatID: target.stored.document.chat.id,
                destinationDirectory: temporaryURL,
                progress: progress,
                cancellation: cancellation
            )
            localMessageCountsByID = messageCountsBySourceID(result.sourceImpacts)
        } else if localSources.count == 1 {
            result = try ConversationCompositionEngine(policy: .conservativeDefault).compose(
                sources: localSources + importedSources,
                targetSourceID: localTargetSourceID,
                perspectiveConstraints: [],
                targetChatID: target.stored.document.chat.id,
                destinationDirectory: temporaryURL,
                progress: progress,
                cancellation: cancellation
            )
            localMessageCountsByID = messageCountsBySourceID(result.sourceImpacts)
        } else {
            let localTemporaryURL = session.paths.mergedChatsURL.appendingPathComponent(
                ".combining-local-\(record.id.rawValue)-\(UUID().uuidString)",
                isDirectory: true
            )
            try fileManager.createDirectory(
                at: localTemporaryURL,
                withIntermediateDirectories: false
            )
            defer { try? fileManager.removeItem(at: localTemporaryURL) }

            let localResult = try ConversationCompositionEngine(
                policy: .currentUnifiedView
            ).compose(
                sources: localSources,
                targetSourceID: localTargetSourceID,
                perspectiveConstraints: [
                    .samePerspective(sourceIDs: localSources.map(\.id))
                ],
                targetChatID: target.stored.document.chat.id,
                destinationDirectory: localTemporaryURL,
                progress: { update in
                    if update.phase != .completed {
                        progress?(update)
                    }
                },
                cancellation: cancellation
            )
            let combinedLocalSourceID = ConversationSourceID(
                rawValue: "combined-local-\(record.id.rawValue)"
            )
            let combinedLocalSource = try ConversationSource(
                id: combinedLocalSourceID,
                document: localResult.document,
                mediaDirectoryURL: localResult.mediaDirectoryURL,
                conversationIdentityHint: conversationIdentityHint(for: record),
                stableMessageIDs: localResult.stableMessageIDsByMaterializedID
            )
            result = try ConversationCompositionEngine(
                policy: .conservativeDefault
            ).compose(
                sources: [combinedLocalSource] + importedSources,
                targetSourceID: combinedLocalSourceID,
                perspectiveConstraints: [],
                targetChatID: target.stored.document.chat.id,
                destinationDirectory: temporaryURL,
                progress: progress,
                cancellation: cancellation
            )
            localMessageCountsByID = try localMessageCounts(
                localResult: localResult,
                finalResult: result,
                combinedLocalSourceID: combinedLocalSourceID
            )
        }

        let document = result.document
        var installedRecord = record
        installedRecord.summary = document.chat
        let impactsByID = Dictionary(
            uniqueKeysWithValues: result.sourceImpacts.map { ($0.sourceID.rawValue, $0) }
        )
        installedRecord.contributions = record.contributions.map { contribution in
            guard let counts = localMessageCountsByID[contribution.id] else {
                return contribution
            }
            return contribution.withMessageCounts(
                total: counts.total,
                exclusive: counts.exclusive
            )
        }
        installedRecord.importedContributions = record.importedContributions.map {
            contribution in
            guard let impact = impactsByID[contribution.id] else {
                return contribution
            }
            return contribution.withImpact(impact)
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
                stored: try version.storedChatStore.openChat(chatId: contribution.source.chatID)
            )
        }
    }

    private static func resolvedImportedContributions(
        for record: ConversationArchiveRecord,
        in session: LibrarySession
    ) throws -> [ResolvedImportedContribution] {
        try record.importedContributions.map { contribution in
            let directoryURL = try importedContributionURL(
                contribution,
                conversationID: record.id,
                in: session
            )
            return ResolvedImportedContribution(
                contribution: contribution,
                directory: try PortableConversationArchiveCodec()
                    .openValidatedDirectory(at: directoryURL)
            )
        }
    }

    private static func matchingRecord(
        for portableDirectory: PortableConversationDirectory,
        among records: [ConversationArchiveRecord],
        in session: LibrarySession,
        progress: WABackupProgressHandler?,
        cancellation: WABackupCancellationHandler?
    ) throws -> ConversationArchiveRecord {
        let descriptor = portableDirectory.manifest.conversation
        let candidates = records.filter { record in
            guard record.key.chatType == descriptor.chatType else { return false }
            guard descriptor.chatType == .group else { return true }
            guard let groupJID = descriptor.groupJID else { return false }
            let normalizedGroupJID = normalizedJID(groupJID)
            return record.identityKeys.contains {
                normalizedJID($0.contactJID) == normalizedGroupJID
            }
        }

        var matches: [(record: ConversationArchiveRecord, name: String)] = []
        for record in candidates {
            if cancellation?() == true {
                throw PortableConversationArchiveError.cancelled
            }
            let targetConversation = try openStoredConversation(record: record, in: session)
            let targetID = ConversationSourceID(
                rawValue: "candidate-\(record.id.rawValue)"
            )
            let portableID = ConversationSourceID(
                rawValue: "incoming-\(portableDirectory.manifest.packageID.uuidString.lowercased())"
            )
            let target = try ConversationSource(
                id: targetID,
                document: targetConversation.document,
                mediaDirectoryURL: targetConversation.mediaDirectoryURL,
                conversationIdentityHint: conversationIdentityHint(for: record)
            )
            let incoming = try portableDirectory.makeConversationSource(id: portableID)
            let diagnostic = try ConversationCompositionEngine(
                policy: .conservativeDefault
            ).diagnose(
                sources: [target, incoming],
                targetSourceID: targetID,
                progress: progress,
                cancellation: cancellation
            )
            if diagnostic.disposition == .applicable {
                matches.append((
                    record: record,
                    name: targetConversation.document.chat.name
                ))
            }
        }

        guard !matches.isEmpty else {
            throw ConversationArchiveError.noMatchingConversation(
                descriptor.displayName
            )
        }
        guard matches.count == 1 else {
            throw ConversationArchiveError.ambiguousMatchingConversations(
                Array(Set(matches.map(\.name))).sorted()
            )
        }
        return matches[0].record
    }

    private static func compositionSources(
        for record: ConversationArchiveRecord,
        contributions: [ResolvedContribution]
    ) throws -> [ConversationSource] {
        let identityHint = conversationIdentityHint(for: record)
        return try contributions.map { resolved in
            try ConversationSource(
                id: ConversationSourceID(rawValue: resolved.contribution.id),
                storedChat: resolved.stored,
                conversationIdentityHint: identityHint
            )
        }
    }

    private static func compositionTarget(
        in contributions: [ResolvedContribution]
    ) throws -> ResolvedContribution {
        guard let target = contributions.max(by: {
            $0.contribution.storedAt < $1.contribution.storedAt
        }) else {
            throw ConversationCompositionError.noSources
        }
        return target
    }

    private static func messageCountsBySourceID(
        _ impacts: [ConversationSourceImpact]
    ) -> [String: ContributionMessageCounts] {
        Dictionary(
            uniqueKeysWithValues: impacts.map {
                (
                    $0.sourceID.rawValue,
                    ContributionMessageCounts(
                        total: $0.sourceMessageCount,
                        exclusive: $0.exclusiveMessageCount
                    )
                )
            }
        )
    }

    private static func localMessageCounts(
        localResult: ConversationMaterializationResult,
        finalResult: ConversationMaterializationResult,
        combinedLocalSourceID: ConversationSourceID
    ) throws -> [String: ContributionMessageCounts] {
        guard let combinedMapping = finalResult.sourceMappings.first(where: {
            $0.sourceID == combinedLocalSourceID
        }) else {
            throw ConversationCompositionError.invalidMaterializedOutput(
                url: finalResult.directoryURL,
                reason: "The combined local source mapping is missing."
            )
        }

        var finalIDByLocalID: [ArchiveMessageID: ArchiveMessageID] = [:]
        for (materializedID, localID) in localResult.stableMessageIDsByMaterializedID {
            guard let finalID = combinedMapping.sourceMessageIDs[materializedID] else {
                throw ConversationCompositionError.invalidMaterializedOutput(
                    url: finalResult.directoryURL,
                    reason: "A combined local message is missing from the final mapping."
                )
            }
            finalIDByLocalID[localID] = finalID
        }

        var ownerIDsByMessage: [ArchiveMessageID: Set<String>] = [:]
        for mapping in localResult.sourceMappings {
            for localID in Set(mapping.sourceMessageIDs.values) {
                guard let finalID = finalIDByLocalID[localID] else {
                    throw ConversationCompositionError.invalidMaterializedOutput(
                        url: finalResult.directoryURL,
                        reason: "A local contribution message is missing from the final mapping."
                    )
                }
                ownerIDsByMessage[finalID, default: []].insert(mapping.sourceID.rawValue)
            }
        }
        for mapping in finalResult.sourceMappings where mapping.sourceID != combinedLocalSourceID {
            for finalID in Set(mapping.sourceMessageIDs.values) {
                ownerIDsByMessage[finalID, default: []].insert(mapping.sourceID.rawValue)
            }
        }

        let localMappingsByID = Dictionary(
            uniqueKeysWithValues: localResult.sourceMappings.map {
                ($0.sourceID, $0)
            }
        )
        var countsByID: [String: ContributionMessageCounts] = [:]
        for impact in localResult.sourceImpacts {
            guard let mapping = localMappingsByID[impact.sourceID] else {
                throw ConversationCompositionError.invalidMaterializedOutput(
                    url: localResult.directoryURL,
                    reason: "A local contribution mapping is missing."
                )
            }
            let representedMessages = try Set(mapping.sourceMessageIDs.values.map { localID in
                guard let finalID = finalIDByLocalID[localID] else {
                    throw ConversationCompositionError.invalidMaterializedOutput(
                        url: finalResult.directoryURL,
                        reason: "A local contribution message is missing from the final mapping."
                    )
                }
                return finalID
            })
            let exclusiveCount = representedMessages.reduce(into: 0) { count, messageID in
                if ownerIDsByMessage[messageID]?.count == 1 {
                    count += 1
                }
            }
            countsByID[impact.sourceID.rawValue] = ContributionMessageCounts(
                total: impact.sourceMessageCount,
                exclusive: exclusiveCount
            )
        }
        return countsByID
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

    private static func normalizedJID(_ rawValue: String) -> String {
        rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .lowercased()
    }

    private static func importedContributionURL(
        _ contribution: ImportedConversationContribution,
        in session: LibrarySession
    ) -> URL {
        session.paths.importedChatsURL
            .appendingPathComponent(contribution.relativeDirectory, isDirectory: true)
            .standardizedFileURL
    }

    private static func importedContributionURL(
        _ contribution: ImportedConversationContribution,
        conversationID: ConversationArchiveID,
        in session: LibrarySession
    ) throws -> URL {
        let expectedRelativeDirectory = "\(conversationID.rawValue)/\(contribution.id)"
        guard contribution.relativeDirectory == expectedRelativeDirectory else {
            throw ConversationArchiveError.invalidArchive(
                session.paths.importedChatsURL,
                "La ruta del chat importado no coincide con su identidad."
            )
        }
        let url = importedContributionURL(contribution, in: session)
        let root = session.paths.importedChatsURL.standardizedFileURL
        guard url.path.hasPrefix(root.path + "/") else {
            throw ConversationArchiveError.invalidArchive(
                url,
                "La ruta del chat importado sale de ImportedChats."
            )
        }
        return url
    }

    private static func removeDirectoryIfEmpty(_ directoryURL: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directoryURL.path) else { return }
        let contents = try fileManager.contentsOfDirectory(atPath: directoryURL.path)
            .filter { $0 != ".DS_Store" }
        if contents.isEmpty {
            try fileManager.removeItem(at: directoryURL)
        }
    }

    private static func validateMedia(
        document: StoredChatDocument,
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

    private static func removeInstalledRecord(
        _ record: ConversationArchiveRecord,
        in session: LibrarySession
    ) {
        let fileManager = FileManager.default
        if record.contributions.count == 1,
           record.importedContributions.isEmpty,
           let source = record.contributions.first?.source,
           let version = session.version(id: source.versionID) {
            try? fileManager.removeItem(
                at: sourceDirectoryURL(source, in: version)
                    .appendingPathComponent(recordFilename)
            )
        } else {
            try? fileManager.removeItem(at: archiveURL(id: record.id, paths: session.paths))
        }
    }

    private static func sourceDirectoryURL(
        _ source: VersionChatID,
        in version: LibraryVersionSession
    ) -> URL {
        version.storedChatsURL
            .appendingPathComponent("Chats", isDirectory: true)
            .appendingPathComponent(String(source.chatID), isDirectory: true)
    }

    private static func sourceSelections(in session: LibrarySession) -> [VersionChatID] {
        let fileManager = FileManager.default
        return session.versions.flatMap { version -> [VersionChatID] in
            let chatsURL = version.storedChatsURL.appendingPathComponent("Chats", isDirectory: true)
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
    let stored: StoredChat
}

private struct ResolvedImportedContribution {
    let contribution: ImportedConversationContribution
    let directory: PortableConversationDirectory
}

private struct ContributionMessageCounts {
    let total: Int
    let exclusive: Int
}
