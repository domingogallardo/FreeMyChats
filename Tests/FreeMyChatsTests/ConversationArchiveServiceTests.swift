import Foundation
import SQLite3
import SwiftWABackupAPI
import XCTest
@testable import FreeMyChats

final class ConversationArchiveServiceTests: XCTestCase {
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

        let catalog = try ConversationArchiveService.synchronize(in: fixture.session)
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
            ConversationArchiveService.synchronize(in: fixture.session).first
        )
        let archived = try ConversationArchiveService.open(
            id: item.id,
            paths: fixture.session.paths
        )

        XCTAssertEqual(archived.document.messages.map(\.message), ["A", "B", "C"])
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
        _ = try ConversationArchiveService.synchronize(in: fixture.session)

        let removal = try ConversationArchiveService.removeContribution(
            source: VersionChatID(versionID: "old", chatID: 7),
            from: fixture.session
        )
        let conversation = try XCTUnwrap(removal.conversation)
        let catalog = try ConversationArchiveService.synchronize(in: removal.session)

        XCTAssertEqual(conversation.document.messages.map(\.message), ["A", "B", "C"])
        XCTAssertEqual(conversation.record.contributions.count, 1)
        XCTAssertNil(removal.session.version(id: "old"))
        XCTAssertNotNil(removal.session.version(id: "new"))
        XCTAssertEqual(catalog.count, 1)
        XCTAssertEqual(catalog.first?.contributionCount, 1)
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
        _ = try ConversationArchiveService.synchronize(in: fixture.session)

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
        _ = try ConversationArchiveService.synchronize(in: fixture.session)

        let removal = try ConversationArchiveService.removeContribution(
            source: VersionChatID(versionID: "only", chatID: 7),
            from: fixture.session
        )

        XCTAssertNil(removal.conversation)
        XCTAssertTrue(removal.session.versions.isEmpty)
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(
                atPath: fixture.session.paths.conversationsURL.path
            ).isEmpty
        )
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(atPath: fixture.rootURL.path)
                .contains { $0.hasPrefix(".removing-contribution-") }
        )
    }

    func testSynchronizeConsolidatesDuplicateArchiveRecords() throws {
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

        let originalItem = try XCTUnwrap(
            ConversationArchiveService.synchronize(in: fixture.session).first
        )
        let original = try ConversationArchiveService.open(
            id: originalItem.id,
            paths: fixture.session.paths
        )
        let duplicateID = ConversationArchiveID()
        let duplicateURL = fixture.session.paths.conversationsURL
            .appendingPathComponent(duplicateID.rawValue, isDirectory: true)
        try FileManager.default.copyItem(at: original.directoryURL, to: duplicateURL)
        let duplicateRecord = ConversationArchiveRecord(
            id: duplicateID,
            key: original.record.key,
            createdAt: original.record.createdAt.addingTimeInterval(1),
            updatedAt: original.record.updatedAt,
            contributions: original.record.contributions,
            summary: original.record.summary,
            contactJIDAliases: original.record.contactJIDAliases
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(duplicateRecord).write(
            to: duplicateURL.appendingPathComponent("archive.json"),
            options: .atomic
        )

        let catalog = try ConversationArchiveService.synchronize(in: fixture.session)

        XCTAssertEqual(catalog.count, 1)
        XCTAssertEqual(catalog.first?.id, originalItem.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: duplicateURL.path))
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
        let first = try ConversationArchiveService.incorporate(
            firstVersion.exportStore.openChat(chatId: 10),
            source: firstSelection,
            in: fixture.session
        )
        let second = try ConversationArchiveService.incorporate(
            secondVersion.exportStore.openChat(chatId: 90),
            source: secondSelection,
            in: fixture.session
        )

        XCTAssertEqual(first.conversation.document.messages.map(\.message), ["Primero"])
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
            try FileManager.default.contentsOfDirectory(atPath: fixture.session.paths.conversationsURL.path)
                .contains { $0.hasPrefix(".building-") }
        )
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

        let catalog = try ConversationArchiveService.synchronize(in: fixture.session)

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
            ConversationArchiveService.synchronize(in: fixture.session).first
        )
        let archived = try ConversationArchiveService.open(
            id: item.id,
            paths: fixture.session.paths
        )
        let filenames = archived.document.messages.compactMap(\.mediaFilename)
        let contents = try Set(filenames.map {
            try Data(contentsOf: archived.mediaDirectoryURL.appendingPathComponent($0))
        })

        XCTAssertEqual(Set(filenames).count, 2)
        XCTAssertEqual(contents, [Data("old-photo".utf8), Data("new-photo".utf8)])
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

    init(
        id: Int,
        text: String,
        date: String,
        mediaFilename: String? = nil,
        mediaData: Data? = nil
    ) {
        self.id = id
        self.text = text
        self.date = date
        self.mediaFilename = mediaFilename
        self.mediaData = mediaData
    }
}
