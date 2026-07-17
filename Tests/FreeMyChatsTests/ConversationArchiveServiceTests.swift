import Foundation
import SQLite3
import SwiftWABackupAPI
import XCTest
@testable import FreeMyChats

final class ConversationArchiveServiceTests: XCTestCase {
    func testCatalogOpensSingleConversationDirectlyFromItsExport() throws {
        let fixture = try makeLibrary(
            exports: [
                ExportFixture(
                    versionID: "single",
                    chatID: 7,
                    jid: "family@g.us",
                    name: "Familia",
                    exportedAt: "2026-01-10T12:00:00Z",
                    messages: [
                        MessageFixture(
                            id: 101,
                            text: "Mensaje único",
                            date: "2026-01-01T10:00:00Z"
                        )
                    ]
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let version = try XCTUnwrap(fixture.session.version(id: "single"))
        let exported = try version.exportStore.openChat(chatId: 7)
        let context = try ConversationArchiveService.prepareIncorporation(
            for: exported.document.chat,
            in: version,
            session: fixture.session
        )
        let update = try ConversationArchiveService.incorporate(
            exported,
            source: VersionChatID(versionID: "single", chatID: 7),
            context: context,
            in: fixture.session
        )

        let catalog = try ConversationArchiveService.catalog(in: fixture.session)
        let item = try XCTUnwrap(catalog.first)
        let opened = try ConversationArchiveService.openRepairing(
            item: item,
            in: fixture.session
        )

        XCTAssertEqual(catalog.count, 1)
        XCTAssertEqual(item.id, update.conversation.record.id)
        XCTAssertEqual(item.contributionCount, 1)
        XCTAssertEqual(item.directoryURL.standardizedFileURL, exported.directoryURL.standardizedFileURL)
        XCTAssertEqual(opened.directoryURL.standardizedFileURL, exported.directoryURL.standardizedFileURL)
        XCTAssertEqual(opened.document.messages.map(\.message), ["Mensaje único"])
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(
                atPath: fixture.session.paths.mergedChatsURL.path
            ).isEmpty
        )
    }

    func testCatalogOpensCombinedConversationFromMergedChatsDirectory() throws {
        let fixture = try makeLibrary(
            exports: [
                ExportFixture(
                    versionID: "old",
                    chatID: 7,
                    jid: "family@g.us",
                    name: "Familia",
                    exportedAt: "2026-01-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 1, text: "A", date: "2026-01-01T10:00:00Z")
                    ]
                ),
                ExportFixture(
                    versionID: "new",
                    chatID: 8,
                    jid: "family@g.us",
                    name: "Familia",
                    exportedAt: "2026-02-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 2, text: "B", date: "2026-02-01T10:00:00Z")
                    ]
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let catalog = try incorporateAllExports(in: fixture)
        let item = try XCTUnwrap(catalog.first)
        let opened = try ConversationArchiveService.openRepairing(
            item: item,
            in: fixture.session
        )

        XCTAssertEqual(catalog.count, 1)
        XCTAssertEqual(item.contributionCount, 2)
        XCTAssertEqual(
            item.directoryURL.standardizedFileURL,
            fixture.session.paths.mergedChatsURL
                .appendingPathComponent(item.id.rawValue, isDirectory: true)
                .standardizedFileURL
        )
        XCTAssertEqual(opened.document.messages.map(\.message), ["A", "B"])
    }

    func testLIDIdentityResolvesToTheSamePhoneConversation() throws {
        let backupURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: backupURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: backupURL) }
        try writeLIDDatabase(
            at: backupURL.appendingPathComponent("LID.sqlite"),
            lid: "90099974987905@lid",
            phone: "34686275599"
        )

        let resolver = ConversationIdentityResolver(backupURL: backupURL)
        let phoneIdentity = resolver.identity(
            for: try decodeChat(jid: "34686275599@s.whatsapp.net")
        )
        let lidIdentity = resolver.identity(
            for: try decodeChat(jid: "90099974987905@lid")
        )
        var record = ConversationArchiveRecord(key: phoneIdentity.primaryKey)
        record.register(lidIdentity)

        XCTAssertEqual(lidIdentity.primaryKey, phoneIdentity.primaryKey)
        XCTAssertTrue(record.matches(lidIdentity))
        XCTAssertTrue(
            record.identityKeys.contains(
                ConversationIdentityKey(
                    chatType: .individual,
                    contactJID: "90099974987905@lid"
                )
            )
        )
    }

    func testSuccessiveExportsFromSameOwnerBecomeOneConversation() throws {
        let fixture = try makeLibrary(
            exports: [
                ExportFixture(
                    versionID: "january",
                    chatID: 7,
                    jid: "34600111222@s.whatsapp.net",
                    name: "Ana",
                    exportedAt: "2026-01-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 101, text: "Mensaje antiguo 1", date: "2026-01-01T10:00:00Z"),
                        MessageFixture(id: 102, text: "Mensaje antiguo 2", date: "2026-01-02T10:00:00Z")
                    ]
                ),
                ExportFixture(
                    versionID: "july",
                    chatID: 42,
                    jid: "34600111222@s.whatsapp.net",
                    name: "Ana",
                    exportedAt: "2026-07-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 1, text: "Mensaje nuevo 1", date: "2026-07-01T10:00:00Z"),
                        MessageFixture(id: 2, text: "Mensaje nuevo 2", date: "2026-07-02T10:00:00Z")
                    ]
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let catalog = try incorporateAllExports(in: fixture)
        let item = try XCTUnwrap(catalog.first)
        let archived = try ConversationArchiveService.open(
            id: item.id,
            paths: fixture.session.paths
        )

        XCTAssertEqual(catalog.count, 1)
        XCTAssertEqual(item.contributionCount, 2)
        XCTAssertEqual(item.chat.numberMessages, 4)
        XCTAssertEqual(
            archived.document.messages.map(\.message),
            ["Mensaje antiguo 1", "Mensaje antiguo 2", "Mensaje nuevo 1", "Mensaje nuevo 2"]
        )
        XCTAssertEqual(archived.document.messages.map(\.id), [1, 2, 3, 4])
        XCTAssertEqual(Set(archived.document.messages.map(\.chatId)).count, 1)
    }

    func testOverlappingMessagesAreNotDuplicatedDuringUpdate() throws {
        let fixture = try makeLibrary(
            exports: [
                ExportFixture(
                    versionID: "first",
                    chatID: 7,
                    jid: "family@g.us",
                    name: "Familia",
                    exportedAt: "2026-01-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 1, text: "A", date: "2026-01-01T10:00:00Z"),
                        MessageFixture(id: 2, text: "B", date: "2026-01-02T10:00:00Z")
                    ]
                ),
                ExportFixture(
                    versionID: "second",
                    chatID: 99,
                    jid: "family@g.us",
                    name: "Familia",
                    exportedAt: "2026-02-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 80, text: "B", date: "2026-01-02T10:00:00Z"),
                        MessageFixture(id: 81, text: "C", date: "2026-02-02T10:00:00Z")
                    ]
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let item = try XCTUnwrap(
            incorporateAllExports(in: fixture).first
        )
        let archived = try ConversationArchiveService.open(
            id: item.id,
            paths: fixture.session.paths
        )

        XCTAssertEqual(archived.document.messages.map(\.message), ["A", "B", "C"])
        XCTAssertEqual(archived.record.contributions.count, 2)
    }

    func testAuthorLIDChangeDoesNotDuplicateMessages() throws {
        let fixture = try makeLibrary(
            exports: [
                ExportFixture(
                    versionID: "old",
                    chatID: 7,
                    jid: "family@g.us",
                    name: "Familia",
                    exportedAt: "2026-01-10T12:00:00Z",
                    messages: [
                        MessageFixture(
                            id: 1,
                            text: "Mensaje compartido",
                            date: "2026-01-01T10:00:00Z",
                            authorJID: "34600111222@s.whatsapp.net",
                            authorPhone: "34600111222"
                        )
                    ]
                ),
                ExportFixture(
                    versionID: "new",
                    chatID: 7,
                    jid: "family@g.us",
                    name: "Familia",
                    exportedAt: "2026-02-10T12:00:00Z",
                    messages: [
                        MessageFixture(
                            id: 99,
                            text: "Mensaje compartido",
                            date: "2026-01-01T10:00:00Z",
                            authorJID: "90099974987905@lid",
                            authorPhone: "34600111222"
                        ),
                        MessageFixture(
                            id: 100,
                            text: "Mensaje nuevo",
                            date: "2026-02-01T10:00:00Z",
                            authorJID: "90099974987905@lid",
                            authorPhone: "34600111222"
                        )
                    ]
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let item = try XCTUnwrap(
            incorporateAllExports(in: fixture).first
        )
        let archived = try ConversationArchiveService.open(
            id: item.id,
            paths: fixture.session.paths
        )

        XCTAssertEqual(archived.document.messages.map(\.message), [
            "Mensaje compartido",
            "Mensaje nuevo"
        ])
        XCTAssertEqual(archived.record.contributions.count, 2)
    }

    func testRemovingOlderContributionKeepsTheNewerCompleteConversation() throws {
        let fixture = try makeLibrary(
            exports: [
                ExportFixture(
                    versionID: "old",
                    chatID: 7,
                    jid: "group@g.us",
                    name: "Grupo",
                    exportedAt: "2026-01-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 1, text: "A", date: "2026-01-01T10:00:00Z"),
                        MessageFixture(id: 2, text: "B", date: "2026-01-02T10:00:00Z")
                    ]
                ),
                ExportFixture(
                    versionID: "new",
                    chatID: 7,
                    jid: "group@g.us",
                    name: "Grupo",
                    exportedAt: "2026-02-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 10, text: "A", date: "2026-01-01T10:00:00Z"),
                        MessageFixture(id: 11, text: "B", date: "2026-01-02T10:00:00Z"),
                        MessageFixture(id: 12, text: "C", date: "2026-02-01T10:00:00Z")
                    ]
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let original = try XCTUnwrap(incorporateAllExports(in: fixture).first)

        let removal = try ConversationArchiveService.removeContribution(
            source: VersionChatID(versionID: "old", chatID: 7),
            from: fixture.session
        )
        let conversation = try XCTUnwrap(removal.conversation)
        let catalog = try ConversationArchiveService.catalog(in: removal.session)

        XCTAssertEqual(conversation.document.messages.map(\.message), ["A", "B", "C"])
        XCTAssertEqual(conversation.record.contributions.count, 1)
        XCTAssertNil(removal.session.version(id: "old"))
        XCTAssertNotNil(removal.session.version(id: "new"))
        XCTAssertEqual(catalog.count, 1)
        XCTAssertEqual(catalog.first?.contributionCount, 1)
        let remainingVersion = try XCTUnwrap(removal.session.version(id: "new"))
        let remainingDirectory = remainingVersion.exportsURL
            .appendingPathComponent("Chats/7", isDirectory: true)
        XCTAssertEqual(conversation.directoryURL, remainingDirectory)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: remainingDirectory.appendingPathComponent("archive.json").path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.session.paths.mergedChatsURL
                    .appendingPathComponent(original.id.rawValue, isDirectory: true).path
            )
        )
    }

    func testRemovingContributionSucceedsWhenMaterializedArchiveIsDamaged() throws {
        let fixture = try makeLibrary(
            exports: [
                ExportFixture(
                    versionID: "old",
                    chatID: 7,
                    jid: "group@g.us",
                    name: "Grupo",
                    exportedAt: "2026-01-10T12:00:00Z",
                    messages: [
                        MessageFixture(
                            id: 1,
                            text: "Audio antiguo",
                            date: "2026-01-01T10:00:00Z",
                            mediaFilename: "old.opus",
                            mediaData: Data("old-audio".utf8)
                        )
                    ]
                ),
                ExportFixture(
                    versionID: "new",
                    chatID: 7,
                    jid: "group@g.us",
                    name: "Grupo",
                    exportedAt: "2026-02-10T12:00:00Z",
                    messages: [
                        MessageFixture(
                            id: 2,
                            text: "Audio nuevo",
                            date: "2026-02-01T10:00:00Z",
                            mediaFilename: "new.opus",
                            mediaData: Data("new-audio".utf8)
                        )
                    ]
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let item = try XCTUnwrap(
            incorporateAllExports(in: fixture).first
        )
        let archived = try ConversationArchiveService.open(
            id: item.id,
            paths: fixture.session.paths
        )
        let missingFilename = try XCTUnwrap(archived.document.messages.first?.mediaFilename)
        try FileManager.default.removeItem(
            at: archived.mediaDirectoryURL.appendingPathComponent(missingFilename)
        )

        let removal = try ConversationArchiveService.removeContribution(
            source: VersionChatID(versionID: "old", chatID: 7),
            from: fixture.session
        )
        let conversation = try XCTUnwrap(removal.conversation)

        XCTAssertEqual(conversation.document.messages.map(\.message), ["Audio nuevo"])
        XCTAssertEqual(conversation.record.contributions.count, 1)
        XCTAssertNil(removal.session.version(id: "old"))
        XCTAssertNotNil(removal.session.version(id: "new"))
    }

    func testRemovingNewerContributionRestoresTheOlderConversation() throws {
        let fixture = try makeLibrary(
            exports: [
                ExportFixture(
                    versionID: "old",
                    chatID: 7,
                    jid: "group@g.us",
                    name: "Grupo",
                    exportedAt: "2026-01-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 1, text: "A", date: "2026-01-01T10:00:00Z"),
                        MessageFixture(id: 2, text: "B", date: "2026-01-02T10:00:00Z")
                    ]
                ),
                ExportFixture(
                    versionID: "new",
                    chatID: 7,
                    jid: "group@g.us",
                    name: "Grupo",
                    exportedAt: "2026-02-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 10, text: "A", date: "2026-01-01T10:00:00Z"),
                        MessageFixture(id: 11, text: "B", date: "2026-01-02T10:00:00Z"),
                        MessageFixture(id: 12, text: "C", date: "2026-02-01T10:00:00Z")
                    ]
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        _ = try incorporateAllExports(in: fixture)

        let removal = try ConversationArchiveService.removeContribution(
            source: VersionChatID(versionID: "new", chatID: 7),
            from: fixture.session
        )
        let conversation = try XCTUnwrap(removal.conversation)

        XCTAssertEqual(conversation.document.messages.map(\.message), ["A", "B"])
        XCTAssertEqual(conversation.record.contributions.count, 1)
        XCTAssertNotNil(removal.session.version(id: "old"))
        XCTAssertNil(removal.session.version(id: "new"))
    }

    func testRemovingOneOfThreeContributionsKeepsACombinedConversation() throws {
        let fixture = try makeLibrary(
            exports: [
                ExportFixture(
                    versionID: "first",
                    chatID: 7,
                    jid: "group@g.us",
                    name: "Grupo",
                    exportedAt: "2026-01-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 1, text: "A", date: "2026-01-01T10:00:00Z")
                    ]
                ),
                ExportFixture(
                    versionID: "second",
                    chatID: 7,
                    jid: "group@g.us",
                    name: "Grupo",
                    exportedAt: "2026-02-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 2, text: "B", date: "2026-02-01T10:00:00Z")
                    ]
                ),
                ExportFixture(
                    versionID: "third",
                    chatID: 7,
                    jid: "group@g.us",
                    name: "Grupo",
                    exportedAt: "2026-03-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 3, text: "C", date: "2026-03-01T10:00:00Z")
                    ]
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let original = try XCTUnwrap(incorporateAllExports(in: fixture).first)

        let removal = try ConversationArchiveService.removeContribution(
            source: VersionChatID(versionID: "second", chatID: 7),
            from: fixture.session
        )
        let conversation = try XCTUnwrap(removal.conversation)
        let catalog = try ConversationArchiveService.catalog(in: removal.session)

        XCTAssertEqual(conversation.record.id, original.id)
        XCTAssertEqual(conversation.record.contributions.count, 2)
        XCTAssertEqual(conversation.document.messages.map(\.message), ["A", "C"])
        XCTAssertEqual(
            conversation.directoryURL,
            fixture.session.paths.mergedChatsURL.appendingPathComponent(
                original.id.rawValue,
                isDirectory: true
            )
        )
        XCTAssertNil(removal.session.version(id: "second"))
        XCTAssertEqual(catalog.first?.contributionCount, 2)
        for versionID in ["first", "third"] {
            let version = try XCTUnwrap(removal.session.version(id: versionID))
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: version.exportsURL
                        .appendingPathComponent("Chats/7/archive.json").path
                )
            )
        }
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(atPath: fixture.rootURL.path)
                .contains { $0.hasPrefix(".removing-contribution-") }
        )
    }

    func testRemovingLastContributionRemovesTheConversation() throws {
        let fixture = try makeLibrary(
            exports: [
                ExportFixture(
                    versionID: "only",
                    chatID: 7,
                    jid: "34600111222@s.whatsapp.net",
                    name: "Ana",
                    exportedAt: "2026-01-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 1, text: "Hola", date: "2026-01-01T10:00:00Z")
                    ]
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let original = try XCTUnwrap(incorporateAllExports(in: fixture).first)
        let onlyVersion = try XCTUnwrap(fixture.session.version(id: "only"))
        let onlyDirectory = onlyVersion.exportsURL
            .appendingPathComponent("Chats/7", isDirectory: true)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: onlyDirectory.appendingPathComponent("archive.json").path
            )
        )

        let removal = try ConversationArchiveService.removeContribution(
            source: VersionChatID(versionID: "only", chatID: 7),
            from: fixture.session
        )

        XCTAssertNil(removal.conversation)
        XCTAssertTrue(removal.session.versions.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: onlyDirectory.path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.session.paths.mergedChatsURL
                    .appendingPathComponent(original.id.rawValue, isDirectory: true).path
            )
        )
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(
                atPath: fixture.session.paths.mergedChatsURL.path
            ).isEmpty
        )
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(atPath: fixture.rootURL.path)
                .contains { $0.hasPrefix(".removing-contribution-") }
        )
    }

    func testUpdatingSingleExportRestoresItsPreparedArchiveRecord() throws {
        let fixture = try makeLibrary(
            exports: [
                ExportFixture(
                    versionID: "only",
                    chatID: 7,
                    jid: "34600111222@s.whatsapp.net",
                    name: "Ana",
                    exportedAt: "2026-01-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 1, text: "Hola", date: "2026-01-01T10:00:00Z")
                    ]
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let originalItem = try XCTUnwrap(incorporateAllExports(in: fixture).first)
        let version = try XCTUnwrap(fixture.session.version(id: "only"))
        let exported = try version.exportStore.openChat(chatId: 7)
        let context = try ConversationArchiveService.prepareIncorporation(
            for: exported.document.chat,
            in: version,
            session: fixture.session
        )
        let archiveURL = exported.directoryURL.appendingPathComponent("archive.json")
        try FileManager.default.removeItem(at: archiveURL)

        let update = try ConversationArchiveService.incorporate(
            exported,
            source: VersionChatID(versionID: "only", chatID: 7),
            context: context,
            in: fixture.session
        )

        XCTAssertEqual(update.conversation.record.id, originalItem.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(
                atPath: fixture.session.paths.mergedChatsURL.path
            ).isEmpty
        )
    }

    func testPreparedSingleRecordCanBeRestoredAfterAnExportFailure() throws {
        let fixture = try makeLibrary(
            exports: [
                ExportFixture(
                    versionID: "only",
                    chatID: 7,
                    jid: "34600111222@s.whatsapp.net",
                    name: "Ana",
                    exportedAt: "2026-01-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 1, text: "Hola", date: "2026-01-01T10:00:00Z")
                    ]
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let original = try XCTUnwrap(incorporateAllExports(in: fixture).first)
        let version = try XCTUnwrap(fixture.session.version(id: "only"))
        let exported = try version.exportStore.openChat(chatId: 7)
        let context = try ConversationArchiveService.prepareIncorporation(
            for: exported.document.chat,
            in: version,
            session: fixture.session
        )
        let archiveURL = exported.directoryURL.appendingPathComponent("archive.json")
        try FileManager.default.removeItem(at: archiveURL)

        try ConversationArchiveService.restorePreparedRecord(
            from: context,
            in: fixture.session
        )
        let restored = try XCTUnwrap(ConversationArchiveService.catalog(in: fixture.session).first)

        XCTAssertEqual(restored.id, original.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(
                atPath: fixture.session.paths.mergedChatsURL.path
            ).isEmpty
        )
    }

    func testIncorporatingASecondBackupReplacesTheMaterializedArchiveAtomically() throws {
        let fixture = try makeLibrary(
            exports: [
                ExportFixture(
                    versionID: "first",
                    chatID: 10,
                    jid: "34600999888@s.whatsapp.net",
                    name: "Luis",
                    exportedAt: "2026-03-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 1, text: "Primero", date: "2026-03-01T10:00:00Z")
                    ]
                ),
                ExportFixture(
                    versionID: "second",
                    chatID: 90,
                    jid: "34600999888@s.whatsapp.net",
                    name: "Luis",
                    exportedAt: "2026-04-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 1, text: "Segundo", date: "2026-04-01T10:00:00Z")
                    ]
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let firstSelection = VersionChatID(versionID: "first", chatID: 10)
        let secondSelection = VersionChatID(versionID: "second", chatID: 90)
        let firstVersion = try XCTUnwrap(fixture.session.version(id: "first"))
        let secondVersion = try XCTUnwrap(fixture.session.version(id: "second"))
        let firstExport = try firstVersion.exportStore.openChat(chatId: 10)
        let firstContext = try ConversationArchiveService.prepareIncorporation(
            for: firstExport.document.chat,
            in: firstVersion,
            session: fixture.session
        )
        let first = try ConversationArchiveService.incorporate(
            firstExport,
            source: firstSelection,
            context: firstContext,
            in: fixture.session
        )
        let secondExport = try secondVersion.exportStore.openChat(chatId: 90)
        let secondContext = try ConversationArchiveService.prepareIncorporation(
            for: secondExport.document.chat,
            in: secondVersion,
            session: fixture.session
        )
        let second = try ConversationArchiveService.incorporate(
            secondExport,
            source: secondSelection,
            context: secondContext,
            in: fixture.session
        )

        XCTAssertEqual(first.conversation.document.messages.map(\.message), ["Primero"])
        XCTAssertEqual(first.conversation.directoryURL, firstExport.directoryURL)
        XCTAssertEqual(second.conversation.record.id, first.conversation.record.id)
        XCTAssertEqual(second.addedMessageCount, 1)
        XCTAssertEqual(second.conversation.document.messages.map(\.message), ["Primero", "Segundo"])
        XCTAssertEqual(
            try second.conversation.directoryURL.resourceValues(
                forKeys: [.isHiddenKey]
            ).isHidden,
            false
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: firstExport.directoryURL.appendingPathComponent("archive.json").path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: secondExport.directoryURL.appendingPathComponent("archive.json").path
            )
        )
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(atPath: fixture.session.paths.mergedChatsURL.path)
                .contains { $0.hasPrefix(".building-") }
        )
    }

    func testUpdatingAContributionRebuildsTheExistingCombinedConversation() throws {
        let fixture = try makeLibrary(
            exports: [
                ExportFixture(
                    versionID: "old",
                    chatID: 7,
                    jid: "group@g.us",
                    name: "Grupo",
                    exportedAt: "2026-01-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 1, text: "A", date: "2026-01-01T10:00:00Z")
                    ]
                ),
                ExportFixture(
                    versionID: "new",
                    chatID: 7,
                    jid: "group@g.us",
                    name: "Grupo",
                    exportedAt: "2026-02-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 2, text: "B", date: "2026-02-01T10:00:00Z")
                    ]
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let original = try XCTUnwrap(incorporateAllExports(in: fixture).first)
        let oldVersion = try XCTUnwrap(fixture.session.version(id: "old"))
        let oldExport = try oldVersion.exportStore.openChat(chatId: 7)
        let context = try ConversationArchiveService.prepareIncorporation(
            for: oldExport.document.chat,
            in: oldVersion,
            session: fixture.session
        )
        try write(
            ExportFixture(
                versionID: "old",
                chatID: 7,
                jid: "group@g.us",
                name: "Grupo",
                exportedAt: "2026-03-10T12:00:00Z",
                messages: [
                    MessageFixture(id: 1, text: "A", date: "2026-01-01T10:00:00Z"),
                    MessageFixture(id: 3, text: "C", date: "2026-03-01T10:00:00Z")
                ]
            ),
            to: oldVersion.exportsURL
        )
        let updatedExport = try oldVersion.exportStore.openChat(chatId: 7)

        let update = try ConversationArchiveService.incorporate(
            updatedExport,
            source: VersionChatID(versionID: "old", chatID: 7),
            context: context,
            in: fixture.session
        )

        XCTAssertEqual(update.conversation.record.id, original.id)
        XCTAssertEqual(update.conversation.record.contributions.count, 2)
        XCTAssertEqual(update.addedMessageCount, 1)
        XCTAssertEqual(update.conversation.document.messages.map(\.message), ["A", "B", "C"])
        XCTAssertEqual(
            update.conversation.directoryURL,
            fixture.session.paths.mergedChatsURL.appendingPathComponent(
                original.id.rawValue,
                isDirectory: true
            )
        )
        for versionID in ["old", "new"] {
            let version = try XCTUnwrap(fixture.session.version(id: versionID))
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: version.exportsURL
                        .appendingPathComponent("Chats/7/archive.json").path
                )
            )
        }
        let conversationEntries = try FileManager.default.contentsOfDirectory(
            atPath: fixture.session.paths.mergedChatsURL.path
        )
        XCTAssertFalse(conversationEntries.contains { $0.hasPrefix(".building-") })
        XCTAssertFalse(conversationEntries.contains { $0.hasPrefix(".replacing-") })
    }

    func testDifferentJIDsRemainSeparateEvenWhenNamesMatch() throws {
        let fixture = try makeLibrary(
            exports: [
                ExportFixture(
                    versionID: "first",
                    chatID: 7,
                    jid: "first@g.us",
                    name: "Familia",
                    exportedAt: "2026-01-10T12:00:00Z",
                    messages: []
                ),
                ExportFixture(
                    versionID: "second",
                    chatID: 8,
                    jid: "second@g.us",
                    name: "Familia",
                    exportedAt: "2026-02-10T12:00:00Z",
                    messages: []
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let catalog = try incorporateAllExports(in: fixture)

        XCTAssertEqual(catalog.count, 2)
        XCTAssertEqual(Set(catalog.map { $0.chat.contactJid }), ["first@g.us", "second@g.us"])
    }

    func testMediaWithSameFilenameAndDifferentContentsRemainDistinct() throws {
        let fixture = try makeLibrary(
            exports: [
                ExportFixture(
                    versionID: "old",
                    chatID: 3,
                    jid: "media@g.us",
                    name: "Media",
                    exportedAt: "2026-01-10T12:00:00Z",
                    messages: [
                        MessageFixture(
                            id: 1,
                            text: "Primera foto",
                            date: "2026-01-01T10:00:00Z",
                            mediaFilename: "photo.jpg",
                            mediaData: Data("old-photo".utf8)
                        )
                    ]
                ),
                ExportFixture(
                    versionID: "new",
                    chatID: 4,
                    jid: "media@g.us",
                    name: "Media",
                    exportedAt: "2026-02-10T12:00:00Z",
                    messages: [
                        MessageFixture(
                            id: 1,
                            text: "Segunda foto",
                            date: "2026-02-01T10:00:00Z",
                            mediaFilename: "photo.jpg",
                            mediaData: Data("new-photo".utf8)
                        )
                    ]
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let item = try XCTUnwrap(
            incorporateAllExports(in: fixture).first
        )
        let archived = try ConversationArchiveService.open(
            id: item.id,
            paths: fixture.session.paths
        )
        let filenames = archived.document.messages.compactMap(\.mediaFilename)
        let contents = try Set(filenames.map {
            try Data(contentsOf: archived.mediaDirectoryURL.appendingPathComponent($0))
        })
        let oldMaterializedFilename = try XCTUnwrap(filenames.first {
            (try? Data(contentsOf: archived.mediaDirectoryURL.appendingPathComponent($0)))
                == Data("old-photo".utf8)
        })
        let oldSourceURL = try XCTUnwrap(fixture.session.version(id: "old"))
            .exportsURL
            .appendingPathComponent("Chats/3/Media/photo.jpg")
        let sourceFileNumber = try FileManager.default.attributesOfItem(
            atPath: oldSourceURL.path
        )[.systemFileNumber] as? NSNumber
        let materializedFileNumber = try FileManager.default.attributesOfItem(
            atPath: archived.mediaDirectoryURL.appendingPathComponent(oldMaterializedFilename).path
        )[.systemFileNumber] as? NSNumber

        XCTAssertEqual(Set(filenames).count, 2)
        XCTAssertEqual(contents, [Data("old-photo".utf8), Data("new-photo".utf8)])
        XCTAssertNotEqual(sourceFileNumber, materializedFileNumber)
    }

    func testOpenRepairingRebuildsMissingMediaFromContributions() throws {
        let fixture = try makeLibrary(
            exports: [
                ExportFixture(
                    versionID: "old",
                    chatID: 3,
                    jid: "media@g.us",
                    name: "Media",
                    exportedAt: "2026-01-10T12:00:00Z",
                    messages: [
                        MessageFixture(
                            id: 1,
                            text: "Audio",
                            date: "2026-01-01T10:00:00Z",
                            mediaFilename: "voice.opus",
                            mediaData: Data("audio".utf8)
                        )
                    ]
                ),
                ExportFixture(
                    versionID: "new",
                    chatID: 4,
                    jid: "media@g.us",
                    name: "Media",
                    exportedAt: "2026-02-10T12:00:00Z",
                    messages: [
                        MessageFixture(
                            id: 80,
                            text: "Audio",
                            date: "2026-01-01T10:00:00Z",
                            mediaFilename: "voice.opus",
                            mediaData: Data("audio".utf8)
                        )
                    ]
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let item = try XCTUnwrap(
            incorporateAllExports(in: fixture).first
        )
        let archived = try ConversationArchiveService.open(
            id: item.id,
            paths: fixture.session.paths
        )
        let missingFilename = try XCTUnwrap(archived.document.messages.first?.mediaFilename)
        let missingURL = archived.mediaDirectoryURL.appendingPathComponent(missingFilename)
        try FileManager.default.removeItem(at: missingURL)

        XCTAssertThrowsError(
            try ConversationArchiveService.open(id: item.id, paths: fixture.session.paths)
        )

        let repaired = try ConversationArchiveService.openRepairing(
            id: item.id,
            in: fixture.session
        )

        XCTAssertEqual(repaired.document.messages.map(\.message), ["Audio"])
        XCTAssertEqual(repaired.record.contributions.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: missingURL.path))
    }

    private func makeLibrary(exports: [ExportFixture]) throws -> LibraryFixture {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let initial = try LibraryService.create(at: rootURL)
        let formatter = ISO8601DateFormatter()
        let records = try exports.enumerated().map { index, fixture in
            LibraryVersionRecord(
                id: fixture.versionID,
                sourceBackupIdentifier: "iphone-owner",
                sourceBackupCreationDate: try XCTUnwrap(formatter.date(from: fixture.exportedAt)),
                importedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)),
                exportDirectoryName: fixture.versionID
            )
        }
        var manifest = initial.manifest
        manifest.versions = records
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: initial.paths.manifestURL, options: .atomic)

        for fixture in exports {
            let record = try XCTUnwrap(records.first { $0.id == fixture.versionID })
            try write(fixture, to: initial.paths.exportURL(for: record))
        }
        return LibraryFixture(
            rootURL: rootURL,
            session: try LibraryService.open(selectedURL: rootURL)
        )
    }

    private func incorporateAllExports(
        in fixture: LibraryFixture
    ) throws -> [ExportedChatListItem] {
        for version in fixture.session.versions {
            for chat in version.chats {
                let source = VersionChatID(versionID: version.id, chatID: chat.id)
                let exported = try version.exportStore.openChat(chatId: chat.id)
                let context = try ConversationArchiveService.prepareIncorporation(
                    for: chat,
                    in: version,
                    session: fixture.session
                )
                _ = try ConversationArchiveService.incorporate(
                    exported,
                    source: source,
                    context: context,
                    in: fixture.session
                )
            }
        }
        return try ConversationArchiveService.catalog(in: fixture.session)
    }

    private func write(_ fixture: ExportFixture, to exportURL: URL) throws {
        let chatDirectory = exportURL.appendingPathComponent(
            "Chats/\(fixture.chatID)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: chatDirectory.appendingPathComponent("Media", isDirectory: true),
            withIntermediateDirectories: true
        )
        let chatType = fixture.jid.hasSuffix("@g.us") ? "group" : "individual"
        let lastDate = fixture.messages.last?.date ?? fixture.exportedAt
        let messages: [[String: Any]] = fixture.messages.map { message in
            var object: [String: Any] = [
                "id": message.id,
                "chatId": fixture.chatID,
                "message": message.text,
                "date": message.date,
                "isFromMe": false,
                "messageType": "Text"
            ]
            if let mediaFilename = message.mediaFilename {
                object["mediaFilename"] = mediaFilename
            }
            if let authorJID = message.authorJID, let authorPhone = message.authorPhone {
                object["author"] = [
                    "kind": "participant",
                    "displayName": "Participante",
                    "phone": authorPhone,
                    "jid": authorJID,
                    "source": authorJID.hasSuffix("@lid") ? "lidAccount" : "chatSession"
                ]
            }
            return object
        }
        for message in fixture.messages {
            if let filename = message.mediaFilename, let data = message.mediaData {
                try data.write(
                    to: chatDirectory
                        .appendingPathComponent("Media", isDirectory: true)
                        .appendingPathComponent(filename)
                )
            }
        }
        let document: [String: Any] = [
            "schemaVersion": 1,
            "exportedAt": fixture.exportedAt,
            "chat": [
                "id": fixture.chatID,
                "contactJid": fixture.jid,
                "name": fixture.name,
                "numberMessages": fixture.messages.count,
                "lastMessageDate": lastDate,
                "chatType": chatType,
                "isArchived": false,
                "mediaByteCount": 0
            ],
            "messages": messages,
            "contacts": []
        ]
        try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted])
            .write(to: chatDirectory.appendingPathComponent("chat.json"))
    }

    private func decodeChat(jid: String) throws -> ChatInfo {
        let object: [String: Any] = [
            "id": 1,
            "contactJid": jid,
            "name": "Conso",
            "numberMessages": 1,
            "lastMessageDate": "2026-07-16T13:43:00Z",
            "chatType": "individual",
            "isArchived": false,
            "mediaByteCount": 0
        ]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            ChatInfo.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }

    private func writeLIDDatabase(at url: URL, lid: String, phone: String) throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        guard let database else {
            throw NSError(domain: "ConversationArchiveServiceTests", code: 1)
        }
        defer { sqlite3_close(database) }
        let sql = """
            CREATE TABLE ZWAZACCOUNT (
                ZIDENTIFIER VARCHAR,
                ZPHONENUMBER VARCHAR
            );
            INSERT INTO ZWAZACCOUNT (ZIDENTIFIER, ZPHONENUMBER)
            VALUES ('\(lid)', '\(phone)');
            """
        XCTAssertEqual(sqlite3_exec(database, sql, nil, nil, nil), SQLITE_OK)
    }
}

private struct LibraryFixture {
    let rootURL: URL
    let session: LibrarySession
}

private struct ExportFixture {
    let versionID: String
    let chatID: Int
    let jid: String
    let name: String
    let exportedAt: String
    let messages: [MessageFixture]
}

private struct MessageFixture {
    let id: Int
    let text: String
    let date: String
    let mediaFilename: String?
    let mediaData: Data?
    let authorJID: String?
    let authorPhone: String?

    init(
        id: Int,
        text: String,
        date: String,
        mediaFilename: String? = nil,
        mediaData: Data? = nil,
        authorJID: String? = nil,
        authorPhone: String? = nil
    ) {
        self.id = id
        self.text = text
        self.date = date
        self.mediaFilename = mediaFilename
        self.mediaData = mediaData
        self.authorJID = authorJID
        self.authorPhone = authorPhone
    }
}
