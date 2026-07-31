import AppKit
import Foundation
import SwiftWABackupAPI
import XCTest
@testable import FreeMyChats

final class LibraryModelsTests: XCTestCase {
    func testConversationActionLabelsDifferentiateAddingDetachingAndDeleting() {
        XCTAssertEqual(
            UnifiedViewPresentation.additionActionTitle(addsToExistingConversation: false),
            "Añadir al catálogo"
        )
        XCTAssertEqual(
            UnifiedViewPresentation.additionActionTitle(addsToExistingConversation: true),
            "Añadir al catálogo"
        )
        XCTAssertEqual(
            UnifiedViewPresentation.contributionDescription(messageCount: 12),
            "Aporta 12 mensajes a la conversación"
        )
        XCTAssertEqual(
            UnifiedViewPresentation.detachmentTitle(contributionCount: 3),
            "¿Eliminar del catálogo?"
        )
        XCTAssertEqual(
            UnifiedViewPresentation.detachmentTitle(contributionCount: 1),
            "¿Eliminar del catálogo?"
        )
        XCTAssertEqual(
            UnifiedViewPresentation.deletionTitle(
                contributionCount: 3,
                hasSourceBackup: true
            ),
            "¿Borrar este chat guardado de la Vista unificada?"
        )
        XCTAssertEqual(
            UnifiedViewPresentation.deletionTitle(
                contributionCount: 0,
                hasSourceBackup: true
            ),
            "¿Borrar este chat extraído?"
        )
        XCTAssertEqual(
            UnifiedViewPresentation.deletionButtonTitle(
                contributionCount: 3,
                hasSourceBackup: true
            ),
            "Borrar y reconstruir la vista"
        )
        XCTAssertEqual(
            UnifiedViewPresentation.deletionButtonTitle(
                contributionCount: 0,
                hasSourceBackup: true
            ),
            "Borrar chat extraído"
        )
    }

    func testConversationPresentationOnlyCallsMultipleSavedCopiesUnified() {
        XCTAssertEqual(
            ConversationPresentation.cellTypeLabel(chatType: .individual),
            "Individual"
        )
        XCTAssertEqual(
            ConversationPresentation.cellTypeLabel(chatType: .group),
            "Grupo"
        )
        XCTAssertEqual(
            ConversationPresentation.headerTitle(contributionCount: 1),
            "Conversación"
        )
        XCTAssertEqual(
            ConversationPresentation.subtitle(
                chatType: .group,
                messageCount: 820,
                contributionCount: 1,
                date: "hoy, 10:10"
            ),
            "Grupo · 820 mensajes · 1 chat guardado · hoy, 10:10"
        )
        XCTAssertEqual(
            ConversationPresentation.headerTitle(contributionCount: 2),
            "Vista unificada"
        )
        XCTAssertEqual(
            ConversationPresentation.subtitle(
                chatType: .group,
                messageCount: 900,
                contributionCount: 2,
                date: "hoy, 10:10"
            ),
            "Vista unificada · Grupo · 900 mensajes · 2 chats guardados · hoy, 10:10"
        )
    }

    func testUnifiedViewCreationCopyExplainsThatSavedCopiesRemainSeparate() {
        XCTAssertEqual(
            UnifiedViewPresentation.additionTitle(
                chatName: "Familia",
                existingContributionCount: 1
            ),
            "¿Añadir “Familia” al catálogo?"
        )
        let message = UnifiedViewPresentation.additionMessage(
            existingContributionCount: 1,
            sourceMessageCount: 900,
            requiresExtraction: false
        )
        XCTAssertEqual(
            message,
            "Este chat extraído se conservará por separado. Sus mensajes se mostrarán "
                + "junto a los del otro chat en una Vista unificada.\n\nLos mensajes repetidos "
                + "aparecerán una sola vez; al terminar verás cuántos mensajes nuevos "
                + "se han incorporado."
        )
        XCTAssertEqual(
            UnifiedViewPresentation.additionButtonTitle(
                existingContributionCount: 1,
                requiresExtraction: false
            ),
            "Añadir al catálogo"
        )
    }

    func testUnifiedViewUpdateCopyExplainsThatEverySavedCopyRemainsSeparate() {
        XCTAssertEqual(
            UnifiedViewPresentation.additionTitle(
                chatName: "Familia",
                existingContributionCount: 2
            ),
            "¿Añadir “Familia” al catálogo?"
        )
        let message = UnifiedViewPresentation.additionMessage(
            existingContributionCount: 2,
            sourceMessageCount: 900,
            requiresExtraction: true
        )
        XCTAssertEqual(
            message,
            "Este chat se extraerá de la copia de WhatsApp y se conservará por separado. "
                + "Sus mensajes se añadirán a la Vista unificada.\n\nLos mensajes repetidos "
                + "aparecerán una sola vez; al "
                + "terminar verás cuántos mensajes nuevos se han incorporado."
        )
        XCTAssertEqual(
            UnifiedViewPresentation.additionButtonTitle(
                existingContributionCount: 2,
                requiresExtraction: true
            ),
            "Extraer y añadir al catálogo"
        )
    }

    func testDeletingOneOfTwoSavedCopiesSummarizesTheMessageImpact() {
        XCTAssertEqual(
            UnifiedViewPresentation.deletionTitle(
                contributionCount: 2,
                hasSourceBackup: true
            ),
            "¿Borrar este chat guardado y deshacer la Vista unificada?"
        )
        let message = UnifiedViewPresentation.deletionMessage(
            chatName: "Familia",
            versionTitle: "Copia de junio",
            hasSourceBackup: true,
            impact: ConversationRemovalMessageImpact(
                contributionCount: 2,
                existingMessageCount: 900,
                sourceMessageCount: 850,
                removedMessageCount: 50,
                resultingMessageCount: 850
            )
        )
        XCTAssertEqual(
            message,
            "Se borrará el chat guardado “Familia” procedente de “Copia de junio”. "
                + "Al borrarlo, 50 mensajes exclusivos dejarán de aparecer en la "
                + "conversación, que quedará con 850 mensajes. La copia de WhatsApp "
                + "sigue disponible, por lo que podrás volver a extraerlo con “Añadir "
                + "al catálogo”."
        )
    }

    func testDeletingOneOfThreeSavedCopiesOmitsUnchangedChatDetails() {
        XCTAssertEqual(
            UnifiedViewPresentation.deletionTitle(
                contributionCount: 3,
                hasSourceBackup: true
            ),
            "¿Borrar este chat guardado de la Vista unificada?"
        )
        let message = UnifiedViewPresentation.deletionMessage(
            chatName: "Familia",
            versionTitle: "Copia de junio",
            hasSourceBackup: true,
            impact: ConversationRemovalMessageImpact(
                contributionCount: 3,
                existingMessageCount: 900,
                sourceMessageCount: 700,
                removedMessageCount: 0,
                resultingMessageCount: 900
            )
        )
        XCTAssertEqual(
            message,
            "Se borrará el chat guardado “Familia” procedente de “Copia de junio”. "
                + "Al borrarlo, ningún mensaje dejará de aparecer en la conversación "
                + "porque todos están también en otros chats; seguirá teniendo 900 mensajes. "
                + "La copia de WhatsApp sigue disponible, por lo que podrás volver a extraerlo "
                + "con “Añadir al catálogo”."
        )
        XCTAssertEqual(
            UnifiedViewPresentation.deletionButtonTitle(
                contributionCount: 3,
                hasSourceBackup: true
            ),
            "Borrar y reconstruir la vista"
        )
    }

    func testDetachingCopySummarizesTheMessageImpact() {
        let impact = ConversationRemovalMessageImpact(
            contributionCount: 3,
            existingMessageCount: 900,
            sourceMessageCount: 700,
            removedMessageCount: 25,
            resultingMessageCount: 875
        )

        XCTAssertEqual(
            UnifiedViewPresentation.detachmentTitle(contributionCount: 3),
            "¿Eliminar del catálogo?"
        )
        let message = UnifiedViewPresentation.detachmentMessage(
            chatName: "Familia",
            versionTitle: "Copia de junio",
            impact: impact
        )
        XCTAssertEqual(
            message,
            "El chat guardado “Familia” procedente de “Copia de junio” se conservará "
                + "extraído en su copia de WhatsApp, pero se eliminará del catálogo. "
                + "Podrás volver a incorporarlo con “Añadir al catálogo”. Al eliminarlo "
                + "del catálogo, 25 mensajes exclusivos dejarán de aparecer en la "
                + "conversación, que quedará con 875 mensajes."
        )
    }

    func testDetachingOneOfTwoCopiesUsesTheConciseConfirmationMessage() {
        let message = UnifiedViewPresentation.detachmentMessage(
            chatName: "Instituto Juan Gil Albert",
            versionTitle: "23 de julio de 2026 a las 11:37",
            impact: ConversationRemovalMessageImpact(
                contributionCount: 2,
                existingMessageCount: 847,
                sourceMessageCount: 2,
                removedMessageCount: 2,
                resultingMessageCount: 845
            )
        )

        XCTAssertEqual(
            message,
            "El chat guardado “Instituto Juan Gil Albert” procedente de “23 de julio "
                + "de 2026 a las 11:37” se conservará extraído en su copia de WhatsApp, "
                + "pero se eliminará del catálogo. Podrás volver a incorporarlo con "
                + "“Añadir al catálogo”. Al eliminarlo del catálogo, 2 mensajes exclusivos "
                + "dejarán de aparecer en la conversación, que quedará con 845 mensajes."
        )
    }

    func testDetachingOnlyContributionExplainsTheTwoPhaseRemoval() {
        let impact = ConversationRemovalMessageImpact(
            contributionCount: 1,
            existingMessageCount: 700,
            sourceMessageCount: 700,
            removedMessageCount: 700,
            resultingMessageCount: 0
        )

        let detachment = UnifiedViewPresentation.detachmentMessage(
            chatName: "Familia",
            versionTitle: "Copia de junio",
            impact: impact
        )
        XCTAssertEqual(
            detachment,
            "“Familia” se eliminará del catálogo, pero podrá volver a añadirse "
                + "con “Añadir al catálogo”."
        )

        let deletion = UnifiedViewPresentation.deletionMessage(
            chatName: "Familia",
            versionTitle: "Copia de junio",
            hasSourceBackup: false,
            impact: ConversationRemovalMessageImpact(
                contributionCount: 0,
                existingMessageCount: 700,
                sourceMessageCount: 700,
                removedMessageCount: 700,
                resultingMessageCount: 0
            )
        )
        XCTAssertEqual(
            deletion,
            "Se borrará el chat guardado “Familia” procedente de “Copia de junio”. "
                + "Sus mensajes y archivos se eliminarán definitivamente de la biblioteca. "
                + "La copia de WhatsApp ya no está disponible. Si lo borras, no podrás "
                + "recuperar este chat."
        )
        XCTAssertEqual(
            UnifiedViewPresentation.deletionTitle(
                contributionCount: 0,
                hasSourceBackup: false
            ),
            "¿Borrar definitivamente este chat extraído?"
        )
        XCTAssertEqual(
            UnifiedViewPresentation.deletionButtonTitle(
                contributionCount: 0,
                hasSourceBackup: false
            ),
            "Borrar definitivamente"
        )
    }

    func testDeletingExtractedChatWithSourceBackupExplainsItCanBeRecovered() {
        let deletion = UnifiedViewPresentation.deletionMessage(
            chatName: "Familia",
            versionTitle: "Copia de junio",
            hasSourceBackup: true,
            impact: ConversationRemovalMessageImpact(
                contributionCount: 0,
                existingMessageCount: 700,
                sourceMessageCount: 700,
                removedMessageCount: 700,
                resultingMessageCount: 0
            )
        )

        XCTAssertEqual(
            deletion,
            "Se borrará el chat guardado “Familia” procedente de “Copia de junio”. "
                + "Sus mensajes y archivos se eliminarán de la biblioteca. La copia de "
                + "WhatsApp sigue disponible, por lo que podrás volver a extraerlo con "
                + "“Añadir al catálogo”."
        )
    }

    func testUnifiedViewCompletionMessagesAvoidRepeatingStorageDetails() {
        XCTAssertEqual(
            UnifiedViewPresentation.incorporationCompletionMessage(
                chatName: "Familia",
                previousContributionCount: 1,
                contributionCount: 2,
                addedMessageCount: 25,
                sourceWasAlreadyIncluded: false
            ),
            "Se ha creado la Vista unificada de “Familia” con 2 chats. "
                + "Se han añadido 25 mensajes nuevos."
        )
        XCTAssertEqual(
            UnifiedViewPresentation.incorporationCompletionMessage(
                chatName: "Familia",
                previousContributionCount: 2,
                contributionCount: 3,
                addedMessageCount: 0,
                sourceWasAlreadyIncluded: false
            ),
            "Se ha actualizado la Vista unificada de “Familia” con 3 chats. "
                + "No había mensajes nuevos que añadir."
        )
        XCTAssertNil(
            UnifiedViewPresentation.automaticallyRemovedPreviousChatsNotice(count: 0)
        )
        XCTAssertEqual(
            UnifiedViewPresentation.automaticallyRemovedPreviousChatsNotice(count: 1),
            "El chat anterior se ha eliminado automáticamente del catálogo porque ya no "
                + "aporta ningún mensaje."
        )
        XCTAssertEqual(
            UnifiedViewPresentation.automaticallyRemovedPreviousChatsNotice(count: 2),
            "2 chats anteriores se han eliminado automáticamente del catálogo porque ya no "
                + "aportan ningún mensaje."
        )
        XCTAssertEqual(
            UnifiedViewPresentation.noNewMessagesAdditionNotice(chatName: "Familia"),
            "“Familia” no se ha añadido al catálogo porque no aporta ningún mensaje nuevo "
                + "a la conversación."
        )
    }

    func testConversationRecordDetectsExistingContributionsThatBecomeRedundant() {
        let first = VersionChatID(versionID: "old", chatID: 7)
        let second = VersionChatID(versionID: "current", chatID: 7)
        let incoming = VersionChatID(versionID: "new", chatID: 7)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let key = ConversationIdentityKey(chatType: .group, contactJID: "family@g.us")
        let previous = ConversationArchiveRecord(
            key: key,
            contributions: [
                ConversationContribution(
                    id: "first",
                    source: first,
                    storedAt: date,
                    messageCount: 10,
                    exclusiveMessageCount: 3
                ),
                ConversationContribution(
                    id: "second",
                    source: second,
                    storedAt: date,
                    messageCount: 20,
                    exclusiveMessageCount: 7
                )
            ]
        )
        let updated = ConversationArchiveRecord(
            key: key,
            contributions: [
                ConversationContribution(
                    id: "first",
                    source: first,
                    storedAt: date,
                    messageCount: 10,
                    exclusiveMessageCount: 0
                ),
                ConversationContribution(
                    id: "second",
                    source: second,
                    storedAt: date,
                    messageCount: 20,
                    exclusiveMessageCount: 5
                ),
                ConversationContribution(
                    id: "incoming",
                    source: incoming,
                    storedAt: date,
                    messageCount: 30,
                    exclusiveMessageCount: 0
                )
            ]
        )

        XCTAssertEqual(
            updated.newlyRedundantContributionCount(comparedTo: previous),
            1
        )
    }

    func testAudioTimeFormatterUsesClockStyleDurations() {
        XCTAssertEqual(AudioTimeFormatter.string(from: 0), "0:00")
        XCTAssertEqual(AudioTimeFormatter.string(from: 9.9), "0:09")
        XCTAssertEqual(AudioTimeFormatter.string(from: 65), "1:05")
        XCTAssertEqual(AudioTimeFormatter.string(from: 3_725), "1:02:05")
    }

    func testBackupDiscoveryRecognizesWrappedCocoaPermissionError() {
        let permissionError = NSError(
            domain: NSCocoaErrorDomain,
            code: CocoaError.Code.fileReadNoPermission.rawValue
        )

        XCTAssertEqual(
            BackupDiscoveryIssue(error: BackupError.directoryAccess(permissionError)),
            .permissionRequired
        )
    }

    func testBackupDiscoveryKeepsNonPermissionErrorDetail() {
        let missingError = NSError(
            domain: NSCocoaErrorDomain,
            code: CocoaError.Code.fileNoSuchFile.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "No existe"]
        )

        XCTAssertEqual(
            BackupDiscoveryIssue(error: BackupError.directoryAccess(missingError)),
            .unreadableDirectory("Failed to access backup directory: No existe")
        )
    }

    func testLibraryPathsNamespaceSourcesAndStoredChatsByVersion() {
        let root = URL(fileURLWithPath: "/tmp/My Library", isDirectory: true)
        let paths = LibraryPaths(rootURL: root)

        XCTAssertEqual(paths.rootURL.path, "/tmp/My Library")
        XCTAssertEqual(paths.sourcesURL.path, "/tmp/My Library/Sources")
        XCTAssertEqual(paths.storedChatsURL.path, "/tmp/My Library/StoredChats")
        XCTAssertEqual(paths.importedChatsURL.path, "/tmp/My Library/ImportedChats")
        XCTAssertEqual(paths.mergedChatsURL.path, "/tmp/My Library/MergedChats")
        XCTAssertEqual(paths.manifestURL.path, "/tmp/My Library/library.json")
        XCTAssertEqual(paths.backupURL(for: "july").path, "/tmp/My Library/Sources/july/Backup")
        XCTAssertEqual(
            paths.profilePhotosURL(for: "july").path,
            "/tmp/My Library/Sources/july/Catalog/ChatProfilePhotos"
        )
        let record = LibraryVersionRecord(
            id: "july",
            sourceBackupIdentifier: "iphone-id",
            sourceBackupCreationDate: Date(timeIntervalSince1970: 1_720_000_000),
            importedAt: Date(timeIntervalSince1970: 1_720_000_100),
            storageDirectoryName: "Copia 2024-07-03 11.46"
        )
        XCTAssertEqual(
            paths.storedChatURL(for: record).path,
            "/tmp/My Library/StoredChats/Copia 2024-07-03 11.46"
        )
        XCTAssertEqual(
            paths.importedConversationURL(
                conversationID: ConversationArchiveID(rawValue: "family"),
                importID: "shared-july"
            ).path,
            "/tmp/My Library/ImportedChats/family/shared-july"
        )
    }

    func testResolvingVersionBackupSelectionReturnsLibraryRoot() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = LibraryPaths(rootURL: root)
        let backup = paths.backupURL(for: "july")
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: paths.manifestURL)
        defer { try? FileManager.default.removeItem(at: root) }

        let resolved = LibraryPaths.resolvingSelection(backup)

        XCTAssertEqual(resolved.rootURL, root.standardizedFileURL)
    }

    func testEmptyLibraryCreationWritesVersionedManifest() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let session = try LibraryService.create(at: root)

        XCTAssertTrue(FileManager.default.fileExists(atPath: session.paths.manifestURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: session.paths.sourcesURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: session.paths.storedChatsURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: session.paths.importedChatsURL.path))
        XCTAssertEqual(session.manifest.schemaVersion, LibraryManifest.currentSchemaVersion)
        XCTAssertTrue(session.versions.isEmpty)
    }

    func testEmptyLibraryPresentsInitialBackupImporter() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let emptySession = try LibraryService.create(at: root)

        XCTAssertTrue(
            FreeMyChatsStore.shouldPresentBackupImporter(for: emptySession)
        )
    }

    func testPopulatedLibraryDoesNotPresentInitialBackupImporter() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = LibraryPaths(rootURL: root)
        let record = LibraryVersionRecord(
            id: "july",
            sourceBackupIdentifier: "iphone-id",
            sourceBackupCreationDate: Date(timeIntervalSince1970: 1_720_000_000),
            importedAt: Date(timeIntervalSince1970: 1_720_000_100),
            storageDirectoryName: "Copia 2024-07-03 11.46"
        )
        let version = LibraryVersionSession(
            record: record,
            backupURL: paths.backupURL(for: record.id),
            storedChatsURL: paths.storedChatURL(for: record),
            backup: nil,
            reader: nil,
            chats: [],
            backupByteCount: 0
        )
        let populatedSession = LibrarySession(
            paths: paths,
            manifest: LibraryManifest(versions: [record]),
            versions: [version]
        )

        XCTAssertFalse(
            FreeMyChatsStore.shouldPresentBackupImporter(for: populatedSession)
        )
    }

    func testLibraryOpensStoredChatsAfterSourceBackupWasDeleted() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let session = try LibraryService.create(at: root)
        let version = LibraryVersionRecord(
            id: "july",
            sourceBackupIdentifier: "iphone-id",
            sourceBackupCreationDate: Date(timeIntervalSince1970: 1_720_000_000),
            importedAt: Date(timeIntervalSince1970: 1_720_000_100),
            storageDirectoryName: "Copia 2024-07-03 11.46"
        )
        var manifest = session.manifest
        manifest.versions = [version]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: session.paths.manifestURL, options: .atomic)

        let storedChatsURL = session.paths.storedChatURL(for: version)
        let chatDirectory = storedChatsURL
            .appendingPathComponent("Chats/44", isDirectory: true)
        try FileManager.default.createDirectory(
            at: chatDirectory.appendingPathComponent("Media", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data(
            """
            {
              "schemaVersion": 2,
              "storedAt": "2026-07-12T12:00:00Z",
              "chat": {
                "id": 44,
                "contactJid": "family@g.us",
                "name": "Familia",
                "numberMessages": 0,
                "lastMessageDate": "2026-07-12T12:00:00Z",
                "chatType": "group",
                "isArchived": false,
                "mediaByteCount": 0
              },
              "messages": [],
              "contacts": []
            }
            """.utf8
        ).write(to: chatDirectory.appendingPathComponent("chat.json"))
        let reopened = try LibraryService.open(selectedURL: root)

        XCTAssertEqual(reopened.versions.count, 1)
        XCTAssertFalse(try XCTUnwrap(reopened.versions.first).hasSourceBackup)
        XCTAssertEqual(reopened.versions.first?.backupByteCount, 0)
        XCTAssertEqual(reopened.versions.first?.chats.first?.name, "Familia")
        XCTAssertEqual(
            reopened.versions.first?.storedChatsURL.lastPathComponent,
            "Copia 2024-07-03 11.46"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: storedChatsURL.path))
        XCTAssertEqual(
            try reopened.versions.first?.storedChatStore.openChat(chatId: 44).document.chat.id,
            44
        )
    }

    func testDeletingLastStoredChatOfDeletedSourceRemovesEveryVersionTrace() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let session = try LibraryService.create(at: root)
        let version = LibraryVersionRecord(
            id: "july",
            sourceBackupIdentifier: "iphone-id",
            sourceBackupCreationDate: Date(timeIntervalSince1970: 1_720_000_000),
            importedAt: Date(timeIntervalSince1970: 1_720_000_100),
            storageDirectoryName: "Copia 2024-07-03 11.46"
        )
        var manifest = session.manifest
        manifest.versions = [version]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: session.paths.manifestURL, options: .atomic)

        let sourceTraceURL = session.paths.profilePhotosURL(for: version.id)
            .appendingPathComponent("chat_44.jpg")
        try FileManager.default.createDirectory(
            at: sourceTraceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("photo".utf8).write(to: sourceTraceURL)

        let storedChatURL = session.paths.storedChatURL(for: version)
        try writeStoredChat(id: 44, name: "Familia", to: storedChatURL)
        try writeStoredChat(id: 45, name: "Amigos", to: storedChatURL)

        let reopened = try LibraryService.open(selectedURL: root)
        let afterFirstDeletion = try LibraryService.deleteStoredChat(
            VersionChatID(versionID: version.id, chatID: 44),
            from: reopened
        )

        XCTAssertEqual(afterFirstDeletion.versions.map(\.id), [version.id])
        XCTAssertEqual(afterFirstDeletion.versions.first?.chats.map(\.id), [45])
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceTraceURL.path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: storedChatURL.appendingPathComponent("Chats/44").path
            )
        )

        let afterLastDeletion = try LibraryService.deleteStoredChat(
            VersionChatID(versionID: version.id, chatID: 45),
            from: afterFirstDeletion
        )

        XCTAssertTrue(afterLastDeletion.versions.isEmpty)
        XCTAssertTrue(afterLastDeletion.manifest.versions.isEmpty)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: session.paths.backupURL(for: version.id).deletingLastPathComponent().path
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: storedChatURL.path))
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(atPath: root.path)
                .contains { $0.hasPrefix(".deleting-stored-chat-") }
        )
    }

    func testStoredChatDisplayStatePreservesUnavailableAndInvalidStates() {
        XCTAssertEqual(StoredChatDisplayState(.notStored), .notStored)
        XCTAssertEqual(StoredChatDisplayState(.invalid(reason: "broken")), .invalid("broken"))
        XCTAssertFalse(StoredChatDisplayState.notStored.isPhysicallyStored)
        XCTAssertTrue(StoredChatDisplayState.extracted(Date()).isPhysicallyStored)
        XCTAssertTrue(StoredChatDisplayState.extracted(Date()).isExtracted)
        XCTAssertTrue(StoredChatDisplayState.invalid("broken").isPhysicallyStored)
    }

    func testChatListCanSortLargestMediaSizeFirst() throws {
        let data = Data(
            """
            [
              {
                "id": 1,
                "contactJid": "recent@s.whatsapp.net",
                "name": "Reciente",
                "numberMessages": 1,
                "lastMessageDate": "2026-07-13T12:00:00Z",
                "chatType": "individual",
                "isArchived": false,
                "mediaByteCount": 100000000
              },
              {
                "id": 2,
                "contactJid": "large@g.us",
                "name": "Grande",
                "numberMessages": 1,
                "lastMessageDate": "2026-07-11T12:00:00Z",
                "chatType": "group",
                "isArchived": false,
                "mediaByteCount": 3000000000
              },
              {
                "id": 3,
                "contactJid": "middle@s.whatsapp.net",
                "name": "Mediano",
                "numberMessages": 1,
                "lastMessageDate": "2026-07-12T12:00:00Z",
                "chatType": "individual",
                "isArchived": false,
                "mediaByteCount": 500000000
              }
            ]
            """.utf8
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let chats = try decoder.decode([ChatInfo].self, from: data)

        XCTAssertEqual(ChatListSortOrder.largest.sort(chats).map(\.id), [2, 3, 1])
        XCTAssertEqual(ChatListSortOrder.recent.sort(chats).map(\.id), [1, 3, 2])
    }

    func testReadingPositionsPersistIndependentlyForEachLibraryAndChat() throws {
        let suiteName = "ChatReadingPositionStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = ChatReadingPositionStore(defaults: defaults)
        let firstLibrary = URL(fileURLWithPath: "/tmp/First Library", isDirectory: true)
        let secondLibrary = URL(fileURLWithPath: "/tmp/Second Library", isDirectory: true)
        let firstChat = VersionChatID(versionID: "version-a", chatID: 44)
        let secondChat = VersionChatID(versionID: "version-a", chatID: 45)

        store.save(messageID: 1_234, for: firstChat, in: firstLibrary)
        store.save(messageID: 5_678, for: secondChat, in: firstLibrary)
        store.save(messageID: 9_012, for: firstChat, in: secondLibrary)

        let reopenedStore = ChatReadingPositionStore(defaults: defaults)
        XCTAssertEqual(reopenedStore.messageID(for: firstChat, in: firstLibrary), 1_234)
        XCTAssertEqual(reopenedStore.messageID(for: secondChat, in: firstLibrary), 5_678)
        XCTAssertEqual(reopenedStore.messageID(for: firstChat, in: secondLibrary), 9_012)

        reopenedStore.remove(chat: firstChat, in: firstLibrary)
        XCTAssertNil(reopenedStore.messageID(for: firstChat, in: firstLibrary))
        XCTAssertEqual(reopenedStore.messageID(for: secondChat, in: firstLibrary), 5_678)

        reopenedStore.remove(versionID: firstChat.versionID, in: firstLibrary)
        XCTAssertNil(reopenedStore.messageID(for: secondChat, in: firstLibrary))
        XCTAssertEqual(reopenedStore.messageID(for: firstChat, in: secondLibrary), 9_012)
    }

    func testLargeMessageSearchCompletesInOneLinearPass() throws {
        let data = Data(
            """
            {
              "id": 1,
              "chatId": 44,
              "message": "Aguja en el pajar",
              "date": "2026-07-12T12:00:00Z",
              "isFromMe": false,
              "messageType": "Text"
            }
            """.utf8
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let message = try decoder.decode(MessageInfo.self, from: data)
        let messages = Array(repeating: message, count: 50_000)

        let start = Date()
        let results = MessageSearch.filter(messages, query: "aguja")
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(results.count, 50_000)
        XCTAssertLessThan(elapsed, 2, "Filtering 50,000 messages should remain interactive")
    }

    func testMessageSearchIncludesReplyPreview() throws {
        let data = Data(
            """
            {
              "id": 2,
              "chatId": 44,
              "message": "De acuerdo",
              "date": "2026-07-12T12:00:00Z",
              "isFromMe": false,
              "messageType": "Text",
              "replyTo": 1,
              "replyToPreview": "La reunión será el jueves"
            }
            """.utf8
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let message = try decoder.decode(MessageInfo.self, from: data)

        XCTAssertEqual(message.replyToPreview, "La reunión será el jueves")
        XCTAssertEqual(MessageSearch.filter([message], query: "jueves").map(\.id), [2])
    }

    func testMessageSearchNavigatorMovesBetweenResultsWithoutLeavingBounds() {
        var navigator = MessageSearchNavigator(messageIDs: [11, 22, 33])

        XCTAssertEqual(navigator.selectedResultNumber, 1)
        XCTAssertEqual(navigator.selectedMessageID, 11)
        XCTAssertFalse(navigator.canMoveToPrevious)
        XCTAssertTrue(navigator.canMoveToNext)
        XCTAssertNil(navigator.move(.previous))

        XCTAssertEqual(navigator.move(.next), 22)
        XCTAssertEqual(navigator.selectedResultNumber, 2)
        XCTAssertTrue(navigator.canMoveToPrevious)
        XCTAssertTrue(navigator.canMoveToNext)

        XCTAssertEqual(navigator.move(.next), 33)
        XCTAssertEqual(navigator.selectedResultNumber, 3)
        XCTAssertTrue(navigator.canMoveToPrevious)
        XCTAssertFalse(navigator.canMoveToNext)
        XCTAssertNil(navigator.move(.next))

        XCTAssertEqual(navigator.move(.previous), 22)
        XCTAssertEqual(navigator.selectedResultNumber, 2)
    }

    func testMessageSearchNavigatorCanStartAtTheNearestResult() {
        var navigator = MessageSearchNavigator(
            messageIDs: [11, 22, 33, 44],
            selectedIndex: 2
        )

        XCTAssertEqual(navigator.selectedResultNumber, 3)
        XCTAssertEqual(navigator.selectedMessageID, 33)
        XCTAssertEqual(navigator.move(.previous), 22)
        XCTAssertEqual(navigator.move(.next), 33)
        XCTAssertEqual(navigator.move(.next), 44)
    }

    func testMessageSearchChoosesTheMatchNearestToTheReadingPosition() throws {
        let messages = try (0..<10).map { try makeMessage(id: $0) }
        let matches = [messages[1], messages[4], messages[8]]

        XCTAssertEqual(
            MessageSearch.nearestMatchIndex(in: matches, among: messages, to: 7),
            2
        )
        XCTAssertEqual(
            MessageSearch.nearestMatchIndex(in: matches, among: messages, to: 6),
            1,
            "If two results are equally close, keep the earlier one"
        )
        XCTAssertEqual(
            MessageSearch.nearestMatchIndex(in: matches, among: messages, to: 4),
            1
        )
        XCTAssertEqual(
            MessageSearch.nearestMatchIndex(in: matches, among: messages, to: nil),
            0
        )
        XCTAssertNil(
            MessageSearch.nearestMatchIndex(in: [], among: messages, to: 4)
        )
    }

    func testMessageSearchNavigatorHasNoSelectionForEmptyResults() {
        var navigator = MessageSearchNavigator(messageIDs: [])

        XCTAssertEqual(navigator.resultCount, 0)
        XCTAssertNil(navigator.selectedResultNumber)
        XCTAssertNil(navigator.selectedMessageID)
        XCTAssertFalse(navigator.canMoveToPrevious)
        XCTAssertFalse(navigator.canMoveToNext)
        XCTAssertNil(navigator.move(.next))
    }

    func testMessageTimelineWindowKeepsAStableBoundedPage() throws {
        let messages = try (0..<10).map { try makeMessage(id: $0) }
        var window = MessageTimelineWindow(
            messages: messages,
            centeredOn: nil,
            pageSize: 3,
            maximumVisibleCount: 4
        )

        XCTAssertEqual(window.rows.map(\.id), [6, 7, 8, 9])
        XCTAssertTrue(window.hasEarlierMessages)
        XCTAssertFalse(window.hasLaterMessages)

        XCTAssertEqual(window.loadEarlier(), 6)
        XCTAssertEqual(window.rows.map(\.id), [3, 4, 5, 6])
        XCTAssertTrue(window.hasEarlierMessages)
        XCTAssertTrue(window.hasLaterMessages)

        XCTAssertEqual(window.loadLater(), 6)
        XCTAssertEqual(window.rows.map(\.id), [6, 7, 8, 9])

        let centered = MessageTimelineWindow(
            messages: messages,
            centeredOn: 5,
            pageSize: 3,
            maximumVisibleCount: 4
        )
        XCTAssertEqual(centered.rows.map(\.id), [3, 4, 5, 6])
    }

    func testMessageTimelineWindowCapsFamilyScaleHistory() throws {
        let message = try makeMessage(id: 1)
        let messages = Array(repeating: message, count: 43_716)

        let window = MessageTimelineWindow(messages: messages, centeredOn: nil)

        XCTAssertEqual(window.rows.count, 900)
        XCTAssertEqual(window.range, 42_816..<43_716)
    }

    func testMessageTimelineWindowStartsEveryVisiblePageWithDaySeparator() throws {
        let messages = try (0..<10).map { try makeMessage(id: $0) }
        var window = MessageTimelineWindow(
            messages: messages,
            centeredOn: nil,
            pageSize: 3,
            maximumVisibleCount: 4
        )

        XCTAssertTrue(window.rows[0].beginsNewDay)
        XCTAssertFalse(window.rows[1].beginsNewDay)

        _ = window.loadEarlier()

        XCTAssertTrue(window.rows[0].beginsNewDay)
        XCTAssertFalse(window.rows[1].beginsNewDay)
    }

    func testMessageTimelineWindowCanMoveDirectlyToEitherEnd() throws {
        let messages = try (0..<10).map { try makeMessage(id: $0) }
        var window = MessageTimelineWindow(
            messages: messages,
            centeredOn: nil,
            maximumVisibleCount: 4
        )

        XCTAssertEqual(window.moveToBeginning(), 0)
        XCTAssertEqual(window.rows.map(\.id), [0, 1, 2, 3])
        XCTAssertFalse(window.hasEarlierMessages)
        XCTAssertTrue(window.hasLaterMessages)

        XCTAssertEqual(window.moveToEnd(), 9)
        XCTAssertEqual(window.rows.map(\.id), [6, 7, 8, 9])
        XCTAssertTrue(window.hasEarlierMessages)
        XCTAssertFalse(window.hasLaterMessages)
    }

    func testMessageTimelineWindowCanMoveDirectlyToAReferencedMessage() throws {
        let messages = try (0..<10).map { try makeMessage(id: $0) }
        var window = MessageTimelineWindow(
            messages: messages,
            centeredOn: nil,
            maximumVisibleCount: 4
        )

        XCTAssertEqual(window.rows.map(\.id), [6, 7, 8, 9])

        XCTAssertEqual(window.move(to: 1), 1)
        XCTAssertEqual(window.rows.map(\.id), [0, 1, 2, 3])

        XCTAssertEqual(window.move(to: 5), 5)
        XCTAssertEqual(window.rows.map(\.id), [3, 4, 5, 6])

        XCTAssertNil(window.move(to: 99))
        XCTAssertEqual(window.rows.map(\.id), [3, 4, 5, 6])
    }

    func testImageThumbnailCacheLoadsAndReusesLocalThumbnail() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let imageURL = root.appendingPathComponent("pixel.png")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encodedPNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl2"
            + "ZQAAAABJRU5ErkJggg=="
        let pngData = try XCTUnwrap(
            Data(base64Encoded: encodedPNG)
        )
        try pngData.write(to: imageURL)

        let first = await ImageThumbnailCache.shared.thumbnail(for: imageURL)
        let second = await ImageThumbnailCache.shared.thumbnail(for: imageURL)
        let firstPreview = await ImageThumbnailCache.shared.preview(for: imageURL)
        let secondPreview = await ImageThumbnailCache.shared.preview(for: imageURL)

        XCTAssertNotNil(first)
        XCTAssertTrue(first === second)
        XCTAssertNotNil(firstPreview)
        XCTAssertTrue(firstPreview === secondPreview)
    }

    func testImageThumbnailCacheLoadsJPEGWithThumbExtension() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let imageURL = root.appendingPathComponent("pixel.thumb")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let bitmap = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 1,
                pixelsHigh: 1,
                bitsPerSample: 8,
                samplesPerPixel: 3,
                hasAlpha: false,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 3,
                bitsPerPixel: 24
            )
        )
        let pixels = try XCTUnwrap(bitmap.bitmapData)
        pixels[0] = 0
        pixels[1] = 255
        pixels[2] = 0
        let jpegData = try XCTUnwrap(
            bitmap.representation(using: .jpeg, properties: [:])
        )
        try jpegData.write(to: imageURL)

        let thumbnail = await ImageThumbnailCache.shared.thumbnail(for: imageURL)

        XCTAssertNotNil(thumbnail)
    }

    private func makeMessage(id: Int) throws -> MessageInfo {
        let data = Data(
            """
            {
              "id": \(id),
              "chatId": 224,
              "message": "Message \(id)",
              "date": "2026-07-12T12:00:00Z",
              "isFromMe": false,
              "messageType": "Text"
            }
            """.utf8
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MessageInfo.self, from: data)
    }

    private func writeStoredChat(id: Int, name: String, to storedChatURL: URL) throws {
        let chatDirectory = storedChatURL.appendingPathComponent(
            "Chats/\(id)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: chatDirectory.appendingPathComponent("Media", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data(
            """
            {
              "schemaVersion": 2,
              "storedAt": "2026-07-12T12:00:00Z",
              "chat": {
                "id": \(id),
                "contactJid": "chat-\(id)@g.us",
                "name": "\(name)",
                "numberMessages": 0,
                "lastMessageDate": "2026-07-12T12:00:00Z",
                "chatType": "group",
                "isArchived": false,
                "mediaByteCount": 0
              },
              "messages": [],
              "contacts": []
            }
            """.utf8
        ).write(to: chatDirectory.appendingPathComponent("chat.json"))
    }
}
