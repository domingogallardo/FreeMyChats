import Foundation
import SwiftWABackupAPI
import XCTest
@testable import FreeMyChats

final class LibraryModelsTests: XCTestCase {
    func testLibraryPathsNamespaceSourcesAndExportsByVersion() {
        let root = URL(fileURLWithPath: "/tmp/My Library", isDirectory: true)
        let paths = LibraryPaths(rootURL: root)

        XCTAssertEqual(paths.rootURL.path, "/tmp/My Library")
        XCTAssertEqual(paths.sourcesURL.path, "/tmp/My Library/Sources")
        XCTAssertEqual(paths.exportsURL.path, "/tmp/My Library/Exports")
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
}
