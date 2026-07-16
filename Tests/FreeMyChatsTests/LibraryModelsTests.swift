import AppKit
import Foundation
import SwiftWABackupAPI
import XCTest
@testable import FreeMyChats

final class LibraryModelsTests: XCTestCase {
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

    func testLibraryPathsNamespaceSourcesAndExportsByVersion() {
        let root = URL(fileURLWithPath: "/tmp/My Library", isDirectory: true)
        let paths = LibraryPaths(rootURL: root)

        XCTAssertEqual(paths.rootURL.path, "/tmp/My Library")
        XCTAssertEqual(paths.sourcesURL.path, "/tmp/My Library/Sources")
        XCTAssertEqual(paths.exportsURL.path, "/tmp/My Library/Exports")
        XCTAssertEqual(paths.conversationsURL.path, "/tmp/My Library/Conversations")
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
            exportDirectoryName: "Copia 2024-07-03 11.46"
        )
        XCTAssertEqual(
            paths.exportURL(for: record).path,
            "/tmp/My Library/Exports/Copia 2024-07-03 11.46"
        )
        XCTAssertEqual(paths.legacyExportURL(for: "july").path, "/tmp/My Library/Exports/july")
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
        XCTAssertTrue(FileManager.default.fileExists(atPath: session.paths.exportsURL.path))
        XCTAssertTrue(session.versions.isEmpty)
    }

    func testEmptyLibraryPresentsInitialBackupImporter() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let emptySession = try LibraryService.create(at: root)

        XCTAssertTrue(
            FreeMyChatsStore.shouldPresentBackupImporter(
                for: emptySession,
                resumeAfterPermission: false
            )
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
            importedAt: Date(timeIntervalSince1970: 1_720_000_100)
        )
        let version = LibraryVersionSession(
            record: record,
            backupURL: paths.backupURL(for: record.id),
            exportsURL: paths.exportURL(for: record),
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
            FreeMyChatsStore.shouldPresentBackupImporter(
                for: populatedSession,
                resumeAfterPermission: false
            )
        )
        XCTAssertTrue(
            FreeMyChatsStore.shouldPresentBackupImporter(
                for: populatedSession,
                resumeAfterPermission: true
            )
        )
    }

    func testLibraryOpensExportsAfterSourceBackupWasDeleted() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let session = try LibraryService.create(at: root)
        let version = LibraryVersionRecord(
            id: "july",
            sourceBackupIdentifier: "iphone-id",
            sourceBackupCreationDate: Date(timeIntervalSince1970: 1_720_000_000),
            importedAt: Date(timeIntervalSince1970: 1_720_000_100)
        )
        var manifest = session.manifest
        manifest.versions = [version]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: session.paths.manifestURL, options: .atomic)

        let legacyExportURL = session.paths.legacyExportURL(for: version.id)
        let chatDirectory = legacyExportURL
            .appendingPathComponent("Chats/44", isDirectory: true)
        try FileManager.default.createDirectory(
            at: chatDirectory.appendingPathComponent("Media", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data(
            """
            {
              "schemaVersion": 1,
              "exportedAt": "2026-07-12T12:00:00Z",
              "chat": {
                "id": 44,
                "contactJid": "family@g.us",
                "name": "Familia",
                "numberMessages": 0,
                "lastMessageDate": "2026-07-12T12:00:00Z",
                "chatType": "group",
                "isArchived": false
              },
              "messages": [],
              "contacts": []
            }
            """.utf8
        ).write(to: chatDirectory.appendingPathComponent("chat.json"))
        var hiddenLegacyExportURL = chatDirectory
        var hiddenLegacyValues = URLResourceValues()
        hiddenLegacyValues.isHidden = true
        try hiddenLegacyExportURL.setResourceValues(hiddenLegacyValues)

        let reopened = try LibraryService.open(selectedURL: root)

        XCTAssertEqual(reopened.versions.count, 1)
        XCTAssertFalse(try XCTUnwrap(reopened.versions.first).hasSourceBackup)
        XCTAssertEqual(reopened.versions.first?.backupByteCount, 0)
        XCTAssertEqual(reopened.versions.first?.chats.first?.name, "Familia")
        XCTAssertEqual(
            reopened.versions.first?.exportsURL.lastPathComponent,
            "Copia 2024-07-03 11.46"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyExportURL.path))
        XCTAssertEqual(
            try reopened.versions.first?.exportStore.openChat(chatId: 44).document.chat.id,
            44
        )

        let reopenedVersion = try XCTUnwrap(reopened.versions.first)
        let catalogOnlyVersion = LibraryVersionSession(
            record: reopenedVersion.record,
            backupURL: reopenedVersion.backupURL,
            exportsURL: reopenedVersion.exportsURL,
            backup: nil,
            reader: nil,
            chats: [],
            backupByteCount: 0
        )
        let catalogOnlySession = LibrarySession(
            paths: reopened.paths,
            manifest: reopened.manifest,
            versions: [catalogOnlyVersion]
        )
        var hiddenExportURL = reopenedVersion.exportsURL
            .appendingPathComponent("Chats/44", isDirectory: true)
        var hiddenValues = URLResourceValues()
        hiddenValues.isHidden = true
        try hiddenExportURL.setResourceValues(hiddenValues)
        let invalidExportURL = reopenedVersion.exportsURL
            .appendingPathComponent("Chats/45", isDirectory: true)
        try FileManager.default.createDirectory(at: invalidExportURL, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: invalidExportURL.appendingPathComponent("chat.json"))

        let catalog = LibraryService.exportCatalog(in: catalogOnlySession)

        XCTAssertEqual(catalog.map(\.id.chatID), [44])
        XCTAssertEqual(catalog.first?.chat.name, "Familia")
        XCTAssertFalse(
            try hiddenExportURL.resourceValues(forKeys: [.isHiddenKey]).isHidden ?? true
        )
    }

    func testDeletingLastExportOfDeletedSourceRemovesEveryVersionTrace() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let session = try LibraryService.create(at: root)
        let version = LibraryVersionRecord(
            id: "july",
            sourceBackupIdentifier: "iphone-id",
            sourceBackupCreationDate: Date(timeIntervalSince1970: 1_720_000_000),
            importedAt: Date(timeIntervalSince1970: 1_720_000_100),
            exportDirectoryName: "Copia 2024-07-03 11.46"
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

        let exportURL = session.paths.exportURL(for: version)
        try writeExportedChat(id: 44, name: "Familia", to: exportURL)
        try writeExportedChat(id: 45, name: "Amigos", to: exportURL)

        let reopened = try LibraryService.open(selectedURL: root)
        let afterFirstDeletion = try LibraryService.deleteExportedChat(
            VersionChatID(versionID: version.id, chatID: 44),
            from: reopened
        )

        XCTAssertEqual(afterFirstDeletion.versions.map(\.id), [version.id])
        XCTAssertEqual(afterFirstDeletion.versions.first?.chats.map(\.id), [45])
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceTraceURL.path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: exportURL.appendingPathComponent("Chats/44").path
            )
        )

        let legacyTraceURL = session.paths.legacyExportURL(for: version.id)
            .appendingPathComponent("orphan.txt")
        try FileManager.default.createDirectory(
            at: legacyTraceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("legacy".utf8).write(to: legacyTraceURL)

        let afterLastDeletion = try LibraryService.deleteExportedChat(
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
        XCTAssertFalse(FileManager.default.fileExists(atPath: exportURL.path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: session.paths.legacyExportURL(for: version.id).path
            )
        )
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(atPath: root.path)
                .contains { $0.hasPrefix(".deleting-export-") }
        )
    }

    func testOpeningLibraryMovesProfileCatalogOutOfExports() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let session = try LibraryService.create(at: root)
        let version = LibraryVersionRecord(
            id: "july",
            sourceBackupIdentifier: "iphone-id",
            sourceBackupCreationDate: Date(timeIntervalSince1970: 1_720_000_000),
            importedAt: Date(timeIntervalSince1970: 1_720_000_100)
        )
        var manifest = session.manifest
        manifest.versions = [version]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: session.paths.manifestURL, options: .atomic)

        let legacyPhotoURL = session.paths.legacyExportURL(for: version.id)
            .appendingPathComponent("ChatProfilePhotos", isDirectory: true)
            .appendingPathComponent("chat_44.jpg")
        try FileManager.default.createDirectory(
            at: legacyPhotoURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("photo".utf8).write(to: legacyPhotoURL)

        let reopened = try LibraryService.open(selectedURL: root)
        let migratedPhotoURL = reopened.paths.profilePhotosURL(for: version.id)
            .appendingPathComponent("chat_44.jpg")

        XCTAssertTrue(FileManager.default.fileExists(atPath: migratedPhotoURL.path))
        XCTAssertEqual(try Data(contentsOf: migratedPhotoURL), Data("photo".utf8))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: reopened.paths.exportsURL.path).isEmpty)
    }

    func testExportDisplayStatePreservesUnavailableAndInvalidStates() {
        XCTAssertEqual(ChatExportDisplayState(.notExported), .notExported)
        XCTAssertEqual(ChatExportDisplayState(.invalid(reason: "broken")), .invalid("broken"))
        XCTAssertFalse(ChatExportDisplayState.notExported.isPhysicallyExported)
        XCTAssertTrue(ChatExportDisplayState.invalid("broken").isPhysicallyExported)
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

        XCTAssertNotNil(first)
        XCTAssertTrue(first === second)
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

    private func writeExportedChat(id: Int, name: String, to exportURL: URL) throws {
        let chatDirectory = exportURL.appendingPathComponent(
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
              "schemaVersion": 1,
              "exportedAt": "2026-07-12T12:00:00Z",
              "chat": {
                "id": \(id),
                "contactJid": "chat-\(id)@g.us",
                "name": "\(name)",
                "numberMessages": 0,
                "lastMessageDate": "2026-07-12T12:00:00Z",
                "chatType": "group",
                "isArchived": false
              },
              "messages": [],
              "contacts": []
            }
            """.utf8
        ).write(to: chatDirectory.appendingPathComponent("chat.json"))
    }
}
