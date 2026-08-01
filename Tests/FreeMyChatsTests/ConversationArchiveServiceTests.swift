import Foundation
import SQLite3
import SwiftWABackupAPI
import XCTest
@testable import FreeMyChats

final class ConversationArchiveServiceTests: XCTestCase {
    func testCatalogOpensSingleConversationDirectlyFromItsStoredChat() throws {
        let fixture = try makeLibrary(
            storedChats: [
                StoredChatFixture(
                    versionID: "single",
                    chatID: 7,
                    jid: "family@g.us",
                    name: "Familia",
                    storedAt: "2026-01-10T12:00:00Z",
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
        let stored = try version.storedChatStore.openChat(chatId: 7)
        let context = try ConversationArchiveService.prepareIncorporation(
            for: stored.document.chat,
            in: version,
            session: fixture.session
        )
        let update = try ConversationArchiveService.incorporate(
            stored,
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
        XCTAssertEqual(
            item.contributionSources,
            [VersionChatID(versionID: "single", chatID: 7)]
        )
        XCTAssertEqual(
            item.preferredPhotoSource,
            VersionChatID(versionID: "single", chatID: 7)
        )
        XCTAssertEqual(item.directoryURL.standardizedFileURL, stored.directoryURL.standardizedFileURL)
        XCTAssertEqual(opened.directoryURL.standardizedFileURL, stored.directoryURL.standardizedFileURL)
        XCTAssertEqual(opened.document.messages.map(\.message), ["Mensaje único"])
        XCTAssertEqual(opened.record.contributions.first?.messageCount, 1)
        XCTAssertEqual(opened.record.contributions.first?.exclusiveMessageCount, 1)
        XCTAssertEqual(opened.record.contributions.first?.contributedMessageCount, 1)
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(
                atPath: fixture.session.paths.mergedChatsURL.path
            ).isEmpty
        )
    }

    func testCatalogOpensCombinedConversationFromMergedChatsDirectory() throws {
        let fixture = try makeLibrary(
            storedChats: [
                StoredChatFixture(
                    versionID: "old",
                    chatID: 7,
                    jid: "family@g.us",
                    name: "Familia",
                    storedAt: "2026-01-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 1, text: "A", date: "2026-01-01T10:00:00Z")
                    ]
                ),
                StoredChatFixture(
                    versionID: "new",
                    chatID: 8,
                    jid: "family@g.us",
                    name: "Familia",
                    storedAt: "2026-02-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 2, text: "B", date: "2026-02-01T10:00:00Z")
                    ]
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let catalog = try incorporateAllStoredChats(in: fixture)
        let item = try XCTUnwrap(catalog.first)
        let opened = try ConversationArchiveService.openRepairing(
            item: item,
            in: fixture.session
        )
        let reopened = try ConversationArchiveService.openRepairing(
            item: item,
            in: fixture.session
        )

        XCTAssertEqual(catalog.count, 1)
        XCTAssertEqual(item.contributionCount, 2)
        XCTAssertEqual(
            Set(item.contributionSources),
            Set([
                VersionChatID(versionID: "old", chatID: 7),
                VersionChatID(versionID: "new", chatID: 8)
            ])
        )
        XCTAssertEqual(
            item.preferredPhotoSource,
            VersionChatID(versionID: "new", chatID: 8)
        )
        XCTAssertEqual(
            item.directoryURL.standardizedFileURL,
            fixture.session.paths.mergedChatsURL
                .appendingPathComponent(item.id.rawValue, isDirectory: true)
                .standardizedFileURL
        )
        XCTAssertEqual(opened.document.messages.map(\.message), ["A", "B"])
        XCTAssertNotEqual(opened.contentRevisionID, reopened.contentRevisionID)
    }

    func testUnifiedViewCompositionReportsSwiftWABackupAPIProgress() throws {
        let fixture = try makeLibrary(
            storedChats: [
                StoredChatFixture(
                    versionID: "old",
                    chatID: 7,
                    jid: "family@g.us",
                    name: "Familia",
                    storedAt: "2026-01-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 1, text: "A", date: "2026-01-01T10:00:00Z")
                    ]
                ),
                StoredChatFixture(
                    versionID: "new",
                    chatID: 8,
                    jid: "family@g.us",
                    name: "Familia",
                    storedAt: "2026-02-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 2, text: "B", date: "2026-02-01T10:00:00Z")
                    ]
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let oldVersion = try XCTUnwrap(fixture.session.version(id: "old"))
        let oldStoredChat = try oldVersion.storedChatStore.openChat(chatId: 7)
        let oldContext = try ConversationArchiveService.prepareIncorporation(
            for: oldStoredChat.document.chat,
            in: oldVersion,
            session: fixture.session
        )
        _ = try ConversationArchiveService.incorporate(
            oldStoredChat,
            source: VersionChatID(versionID: "old", chatID: 7),
            context: oldContext,
            in: fixture.session
        )

        let newVersion = try XCTUnwrap(fixture.session.version(id: "new"))
        let newStoredChat = try newVersion.storedChatStore.openChat(chatId: 8)
        let newContext = try ConversationArchiveService.prepareIncorporation(
            for: newStoredChat.document.chat,
            in: newVersion,
            session: fixture.session
        )
        var phases: [WABackupProgress.Phase] = []
        _ = try ConversationArchiveService.incorporate(
            newStoredChat,
            source: VersionChatID(versionID: "new", chatID: 8),
            context: newContext,
            in: fixture.session
        ) { phases.append($0.phase) }

        XCTAssertTrue(phases.contains(.validatingConversationSources))
        XCTAssertTrue(phases.contains(.canonicalizingConversationMessages))
        XCTAssertTrue(phases.contains(.classifyingConversationComposition))
        XCTAssertTrue(phases.contains(.materializingConversation))
        XCTAssertEqual(phases.last, .completed)
    }

    func testStagesOppositeIndividualPerspectiveRelativeToLocalTarget() throws {
        let fixture = try makeLibrary(
            storedChats: oppositeIndividualStoredChats()
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let targetVersion = try XCTUnwrap(fixture.session.version(id: "local"))
        let sourceVersion = try XCTUnwrap(fixture.session.version(id: "received"))
        let targetStoredChat = try targetVersion.storedChatStore.openChat(chatId: 10)
        let sourceStoredChat = try sourceVersion.storedChatStore.openChat(chatId: 20)
        let target = try ConversationSource(
            id: ConversationSourceID(rawValue: "local"),
            storedChat: targetStoredChat
        )
        let source = try ConversationSource(
            id: ConversationSourceID(rawValue: "received"),
            storedChat: sourceStoredChat
        )
        let destination = fixture.rootURL.appendingPathComponent("import-staging")
        var phases: [WABackupProgress.Phase] = []

        let result = try ConversationArchiveService.stageCrossPerspectiveComposition(
            sources: [source, target],
            targetSourceID: target.id,
            targetChatID: 77,
            destinationDirectory: destination,
            progress: { phases.append($0.phase) }
        )

        XCTAssertEqual(result.document.chat.id, 77)
        XCTAssertEqual(result.document.chat.contactJid, "34600000002@s.whatsapp.net")
        XCTAssertEqual(result.document.messages.count, 5)
        XCTAssertEqual(
            result.document.messages.map(\.isFromMe),
            [true, false, true, false, true]
        )
        XCTAssertEqual(result.document.messages[3].author?.kind, .participant)
        XCTAssertEqual(result.document.messages[4].author?.kind, .me)
        XCTAssertTrue(phases.contains(.inferringConversationPerspectives))
        XCTAssertTrue(phases.contains(.aligningConversationMessages))
        XCTAssertTrue(phases.contains(.materializingConversation))
        XCTAssertEqual(phases.last, .completed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("chat.json").path))
    }

    func testCreatesInspectsAndExtractsPortableConversationThroughAppBoundary() throws {
        let fixture = try makeLibrary(storedChats: oppositeIndividualStoredChats())
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let receivedVersion = try XCTUnwrap(fixture.session.version(id: "received"))
        let receivedStoredChat = try receivedVersion.storedChatStore.openChat(chatId: 20)
        let context = try ConversationArchiveService.prepareIncorporation(
            for: receivedStoredChat.document.chat,
            in: receivedVersion,
            session: fixture.session
        )
        let update = try ConversationArchiveService.incorporate(
            receivedStoredChat,
            source: VersionChatID(versionID: "received", chatID: 20),
            context: context,
            in: fixture.session
        )
        let archiveURL = fixture.rootURL.appendingPathComponent("received.fmcchat")
        let extractionURL = fixture.rootURL.appendingPathComponent("received-portable")
        var creationPhases: [WABackupProgress.Phase] = []

        let created = try ConversationArchiveService.createPortableConversationArchive(
            from: update.conversation,
            producerVersion: "test",
            destinationURL: archiveURL,
            progress: { creationPhases.append($0.phase) }
        )
        let inspected = try ConversationArchiveService.inspectPortableConversationArchive(
            at: archiveURL
        )
        let extracted = try ConversationArchiveService.extractPortableConversationArchive(
            at: archiveURL,
            to: extractionURL
        )
        let imported = try extracted.makeConversationSource(
            id: ConversationSourceID(rawValue: "portable")
        )

        XCTAssertEqual(created.archiveSHA256, inspected.archiveSHA256)
        XCTAssertEqual(created.manifest.producer.name, "Free My Chats")
        XCTAssertEqual(created.manifest.producer.version, "test")
        XCTAssertEqual(extracted.document.messages.count, 5)
        XCTAssertEqual(imported.kind, .portableDocument)
        XCTAssertTrue(creationPhases.contains(.creatingPortableConversationArchive))
        XCTAssertEqual(creationPhases.last, .completed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: extracted.documentURL.path))
    }

    func testPortableSourceUsesSameCrossPerspectiveCompositionPathAsLocalStoredChat() throws {
        let fixture = try makeLibrary(storedChats: oppositeIndividualStoredChats())
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let localStoredChat = try XCTUnwrap(fixture.session.version(id: "local"))
            .storedChatStore.openChat(chatId: 10)
        let receivedStoredChat = try XCTUnwrap(fixture.session.version(id: "received"))
            .storedChatStore.openChat(chatId: 20)
        let local = try ConversationSource(
            id: ConversationSourceID(rawValue: "local"),
            storedChat: localStoredChat
        )
        let received = try ConversationSource(
            id: ConversationSourceID(rawValue: "received"),
            storedChat: receivedStoredChat
        )
        let archiveURL = fixture.rootURL.appendingPathComponent("received.fmcchat")
        _ = try ConversationArchiveService.createPortableConversationArchive(
            from: received,
            producerVersion: "test",
            destinationURL: archiveURL
        )
        let portableDirectory =
            try ConversationArchiveService.extractPortableConversationArchive(
                at: archiveURL,
                to: fixture.rootURL.appendingPathComponent("portable")
            )
        let portable = try portableDirectory.makeConversationSource(
            id: ConversationSourceID(rawValue: "portable-received")
        )

        let result = try ConversationArchiveService.stageCrossPerspectiveComposition(
            sources: [portable, local],
            targetSourceID: local.id,
            targetChatID: 77,
            destinationDirectory: fixture.rootURL.appendingPathComponent("portable-staging")
        )

        XCTAssertEqual(result.document.messages.count, 5)
        XCTAssertEqual(
            result.document.messages.map(\.message),
            [
                "First shared individual",
                "Second shared individual",
                "Third shared individual",
                "Exclusive from B",
                "Exclusive from A"
            ]
        )
        XCTAssertEqual(
            result.document.messages.map(\.isFromMe),
            [true, false, true, false, true]
        )
        XCTAssertEqual(result.document.chat.contactJid, "34600000002@s.whatsapp.net")
    }

    func testImportedConversationPersistsAndExportsAsPartOfTheUnifiedView() throws {
        let fixture = try makeLibrary(storedChats: oppositeIndividualStoredChats())
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let localVersion = try XCTUnwrap(fixture.session.version(id: "local"))
        let receivedVersion = try XCTUnwrap(fixture.session.version(id: "received"))
        let localChat = try XCTUnwrap(localVersion.chats.first)
        let localStored = try localVersion.storedChatStore.openChat(chatId: localChat.id)
        let context = try ConversationArchiveService.prepareIncorporation(
            for: localChat,
            in: localVersion,
            session: fixture.session
        )
        _ = try ConversationArchiveService.incorporate(
            localStored,
            source: VersionChatID(versionID: localVersion.id, chatID: localChat.id),
            context: context,
            in: fixture.session
        )

        let receivedStored = try receivedVersion.storedChatStore.openChat(chatId: 20)
        let receivedSource = try ConversationSource(
            id: ConversationSourceID(rawValue: "received"),
            storedChat: receivedStored
        )
        let archiveURL = fixture.rootURL.appendingPathComponent("received.fmcchat")
        _ = try ConversationArchiveService.createPortableConversationArchive(
            from: receivedSource,
            producerVersion: "test",
            destinationURL: archiveURL
        )

        let result = try ConversationArchiveService.importPortableConversationArchive(
            at: archiveURL,
            into: fixture.session
        )
        let importedURL = fixture.session.paths.importedChatsURL
            .appendingPathComponent(result.importedContribution.relativeDirectory)
        let catalog = try ConversationArchiveService.catalog(in: result.session)
        let item = try XCTUnwrap(catalog.first)
        let reopenedSession = try LibraryService.open(selectedURL: fixture.rootURL)
        let reopened = try ConversationArchiveService.openRepairing(
            id: item.id,
            in: reopenedSession
        )

        XCTAssertEqual(result.session.manifest.schemaVersion, LibraryManifest.currentSchemaVersion)
        XCTAssertEqual(result.conversation.document.messages.count, 5)
        XCTAssertEqual(result.addedMessageCount, 2)
        XCTAssertEqual(result.conversation.record.contributions.count, 1)
        XCTAssertEqual(result.conversation.record.importedContributions.count, 1)
        XCTAssertEqual(
            result.conversation.record.contributions.first?.contributedMessageCount,
            3
        )
        XCTAssertEqual(result.importedContribution.contributedMessageCount, 2)
        XCTAssertEqual(
            result.conversation.record.contributions.compactMap(\.contributedMessageCount)
                .reduce(0, +)
                + result.conversation.record.importedContributions
                    .compactMap(\.contributedMessageCount).reduce(0, +),
            result.conversation.document.messages.count
        )
        XCTAssertEqual(item.localContributionCount, 1)
        XCTAssertEqual(item.importedContributionCount, 1)
        XCTAssertEqual(reopened.document.messages.count, 5)
        XCTAssertTrue(FileManager.default.fileExists(atPath: importedURL.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: importedURL.appendingPathComponent("manifest.json").path
            )
        )

        let unifiedArchiveURL = fixture.rootURL.appendingPathComponent(
            "unified-conversation.fmcchat"
        )
        let exported = try ConversationArchiveService.createPortableConversationArchive(
            for: item.id,
            in: result.session,
            producerVersion: "test",
            destinationURL: unifiedArchiveURL
        )
        let exportedDirectory =
            try ConversationArchiveService.extractPortableConversationArchive(
                at: unifiedArchiveURL,
                to: fixture.rootURL.appendingPathComponent("exported-unified-conversation")
            )

        XCTAssertEqual(exported.manifest.messageCount, 5)
        XCTAssertEqual(exportedDirectory.document.messages.count, 5)
        XCTAssertEqual(
            exportedDirectory.document.messages.map(\.text),
            result.conversation.document.messages.map(\.message)
        )

        XCTAssertThrowsError(
            try ConversationArchiveService.importPortableConversationArchive(
                at: archiveURL,
                into: result.session
            )
        ) { error in
            guard case ConversationArchiveError.importedConversationAlreadyExists = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testImportsPortableGroupIntoItsExistingConversation() throws {
        let fixture = try makeLibrary(storedChats: oppositeGroupStoredChats())
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let localVersion = try XCTUnwrap(fixture.session.version(id: "local-group"))
        let receivedVersion = try XCTUnwrap(fixture.session.version(id: "received-group"))
        let localChat = try XCTUnwrap(localVersion.chats.first)
        let localStored = try localVersion.storedChatStore.openChat(chatId: localChat.id)
        let context = try ConversationArchiveService.prepareIncorporation(
            for: localChat,
            in: localVersion,
            session: fixture.session
        )
        _ = try ConversationArchiveService.incorporate(
            localStored,
            source: VersionChatID(versionID: localVersion.id, chatID: localChat.id),
            context: context,
            in: fixture.session
        )

        let receivedStored = try receivedVersion.storedChatStore.openChat(chatId: 40)
        let archiveURL = fixture.rootURL.appendingPathComponent("received-group.fmcchat")
        _ = try ConversationArchiveService.createPortableConversationArchive(
            from: ConversationSource(
                id: ConversationSourceID(rawValue: "received-group"),
                storedChat: receivedStored
            ),
            producerVersion: "test",
            destinationURL: archiveURL
        )

        let result = try ConversationArchiveService.importPortableConversationArchive(
            at: archiveURL,
            into: fixture.session
        )

        XCTAssertEqual(result.conversation.document.chat.name, "Familia")
        XCTAssertEqual(result.conversation.document.messages.count, 6)
        XCTAssertEqual(result.addedMessageCount, 3)
        XCTAssertEqual(result.importedContribution.displayName, "Familia recibida")
        XCTAssertEqual(result.conversation.record.totalContributionCount, 2)
    }

    func testImportCombinesDisjointLocalFragmentsBeforeCrossPerspectiveComposition() throws {
        let fixtures = oppositeGroupStoredChats() + [
            StoredChatFixture(
                versionID: "local-group-new",
                chatID: 31,
                jid: "family@g.us",
                name: "Familia",
                storedAt: "2026-02-10T12:00:00Z",
                messages: [
                    MessageFixture(
                        id: 31,
                        text: "Exclusive future local",
                        date: "2026-02-01T10:00:00Z",
                        isFromMe: true
                    )
                ]
            )
        ]
        let fixture = try makeLibrary(storedChats: fixtures)
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let oldVersion = try XCTUnwrap(fixture.session.version(id: "local-group"))
        let newVersion = try XCTUnwrap(fixture.session.version(id: "local-group-new"))
        let receivedVersion = try XCTUnwrap(fixture.session.version(id: "received-group"))

        for version in [oldVersion, newVersion] {
            let chat = try XCTUnwrap(version.chats.first)
            let stored = try version.storedChatStore.openChat(chatId: chat.id)
            _ = try ConversationArchiveService.incorporate(
                stored,
                source: VersionChatID(versionID: version.id, chatID: chat.id),
                context: ConversationArchiveService.prepareIncorporation(
                    for: chat,
                    in: version,
                    session: fixture.session
                ),
                in: fixture.session
            )
        }

        let receivedStored = try receivedVersion.storedChatStore.openChat(chatId: 40)
        let archiveURL = fixture.rootURL.appendingPathComponent("received-group.fmcchat")
        _ = try ConversationArchiveService.createPortableConversationArchive(
            from: ConversationSource(
                id: ConversationSourceID(rawValue: "received-group"),
                storedChat: receivedStored
            ),
            producerVersion: "test",
            destinationURL: archiveURL
        )

        let result = try ConversationArchiveService.importPortableConversationArchive(
            at: archiveURL,
            into: fixture.session
        )
        let localContributions = Dictionary(
            uniqueKeysWithValues: result.conversation.record.contributions.map {
                ($0.source.versionID, $0)
            }
        )

        XCTAssertEqual(result.conversation.document.chat.id, 31)
        XCTAssertEqual(result.conversation.document.messages.count, 7)
        XCTAssertEqual(result.addedMessageCount, 3)
        XCTAssertEqual(result.conversation.record.contributions.count, 2)
        XCTAssertEqual(result.conversation.record.importedContributions.count, 1)
        XCTAssertEqual(localContributions["local-group"]?.messageCount, 3)
        XCTAssertEqual(localContributions["local-group"]?.exclusiveMessageCount, 0)
        XCTAssertEqual(localContributions["local-group"]?.contributedMessageCount, 3)
        XCTAssertEqual(localContributions["local-group-new"]?.messageCount, 1)
        XCTAssertEqual(localContributions["local-group-new"]?.exclusiveMessageCount, 1)
        XCTAssertEqual(localContributions["local-group-new"]?.contributedMessageCount, 1)
        XCTAssertEqual(result.importedContribution.messageCount, 6)
        XCTAssertEqual(result.importedContribution.exclusiveMessageCount, 3)
        XCTAssertEqual(result.importedContribution.contributedMessageCount, 3)
        XCTAssertTrue(
            result.conversation.document.messages.contains {
                $0.message == "Exclusive future local"
            }
        )
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(
                atPath: fixture.session.paths.mergedChatsURL.path
            ).contains { $0.hasPrefix(".combining-local-") }
        )
    }

    func testImportRejectsAnArchiveThatMatchesSeveralExistingConversations() throws {
        let localMessages = [
            MessageFixture(
                id: 1,
                text: "First shared individual",
                date: "2026-01-01T10:00:01Z",
                isFromMe: true
            ),
            MessageFixture(
                id: 2,
                text: "Second shared individual",
                date: "2026-01-01T10:00:02Z"
            ),
            MessageFixture(
                id: 3,
                text: "Third shared individual",
                date: "2026-01-01T10:00:03Z",
                isFromMe: true
            )
        ]
        let fixture = try makeLibrary(
            storedChats: [
                StoredChatFixture(
                    versionID: "local-b",
                    chatID: 10,
                    jid: "34600000002@s.whatsapp.net",
                    name: "B",
                    storedAt: "2026-01-10T12:00:00Z",
                    messages: localMessages
                ),
                StoredChatFixture(
                    versionID: "local-c",
                    chatID: 30,
                    jid: "34600000003@s.whatsapp.net",
                    name: "C",
                    storedAt: "2026-01-11T12:00:00Z",
                    messages: localMessages
                ),
                oppositeIndividualStoredChats()[1]
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        for versionID in ["local-b", "local-c"] {
            let version = try XCTUnwrap(fixture.session.version(id: versionID))
            let chat = try XCTUnwrap(version.chats.first)
            let stored = try version.storedChatStore.openChat(chatId: chat.id)
            let context = try ConversationArchiveService.prepareIncorporation(
                for: chat,
                in: version,
                session: fixture.session
            )
            _ = try ConversationArchiveService.incorporate(
                stored,
                source: VersionChatID(versionID: versionID, chatID: chat.id),
                context: context,
                in: fixture.session
            )
        }

        let received = try XCTUnwrap(fixture.session.version(id: "received"))
            .storedChatStore.openChat(chatId: 20)
        let archiveURL = fixture.rootURL.appendingPathComponent("ambiguous.fmcchat")
        _ = try ConversationArchiveService.createPortableConversationArchive(
            from: ConversationSource(
                id: ConversationSourceID(rawValue: "received"),
                storedChat: received
            ),
            producerVersion: "test",
            destinationURL: archiveURL
        )

        XCTAssertThrowsError(
            try ConversationArchiveService.importPortableConversationArchive(
                at: archiveURL,
                into: fixture.session
            )
        ) { error in
            guard case ConversationArchiveError.ambiguousMatchingConversations(let names) = error
            else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(Set(names), Set(["B", "C"]))
        }
        XCTAssertTrue(
            (try? FileManager.default.contentsOfDirectory(
                atPath: fixture.session.paths.importedChatsURL.path
            ).isEmpty) == true
        )
    }

    func testImportedChatCanBeDetachedReincorporatedAndThenDeleted() throws {
        let fixture = try makeLibrary(storedChats: oppositeIndividualStoredChats())
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let localVersion = try XCTUnwrap(fixture.session.version(id: "local"))
        let receivedVersion = try XCTUnwrap(fixture.session.version(id: "received"))
        let localChat = try XCTUnwrap(localVersion.chats.first)
        let localStored = try localVersion.storedChatStore.openChat(chatId: localChat.id)
        let context = try ConversationArchiveService.prepareIncorporation(
            for: localChat,
            in: localVersion,
            session: fixture.session
        )
        _ = try ConversationArchiveService.incorporate(
            localStored,
            source: VersionChatID(versionID: localVersion.id, chatID: localChat.id),
            context: context,
            in: fixture.session
        )
        let receivedStored = try receivedVersion.storedChatStore.openChat(chatId: 20)
        let archiveURL = fixture.rootURL.appendingPathComponent("received.fmcchat")
        _ = try ConversationArchiveService.createPortableConversationArchive(
            from: ConversationSource(
                id: ConversationSourceID(rawValue: "received"),
                storedChat: receivedStored
            ),
            producerVersion: "test",
            destinationURL: archiveURL
        )
        let imported = try ConversationArchiveService.importPortableConversationArchive(
            at: archiveURL,
            into: fixture.session
        )

        XCTAssertThrowsError(
            try ConversationArchiveService.removeContribution(
                source: VersionChatID(versionID: localVersion.id, chatID: localChat.id),
                from: imported.session
            )
        ) { error in
            guard case ConversationArchiveError.cannotRemoveLastLocalContribution = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        let localDetachment = try ConversationArchiveService.detachContribution(
            source: VersionChatID(versionID: localVersion.id, chatID: localChat.id),
            from: imported.session
        )
        let importedOnlyConversation = try XCTUnwrap(localDetachment.conversation)
        XCTAssertTrue(importedOnlyConversation.record.contributions.isEmpty)
        XCTAssertEqual(importedOnlyConversation.record.importedContributions.count, 1)
        let importedOnlyItem = try XCTUnwrap(
            ConversationArchiveService.catalog(in: imported.session).first
        )
        let reopenedImportedOnly = try ConversationArchiveService.openRepairing(
            item: importedOnlyItem,
            in: imported.session
        )
        XCTAssertEqual(reopenedImportedOnly.record.importedContributions.count, 1)
        XCTAssertTrue(reopenedImportedOnly.record.contributions.isEmpty)

        let onlyImportedDetachment =
            try ConversationArchiveService.detachImportedContribution(
                id: imported.importedContribution.id,
                from: imported.session
            )
        XCTAssertNil(onlyImportedDetachment.conversation)
        XCTAssertTrue(try ConversationArchiveService.catalog(in: imported.session).isEmpty)

        let importedOnlyReincorporation =
            try ConversationArchiveService.incorporateDetachedImportedContribution(
                id: imported.importedContribution.id,
                into: imported.session
            )
        XCTAssertTrue(importedOnlyReincorporation.conversation.record.contributions.isEmpty)
        XCTAssertEqual(
            importedOnlyReincorporation.conversation.record.importedContributions.count,
            1
        )

        let localContext = try ConversationArchiveService.prepareIncorporation(
            for: localChat,
            in: localVersion,
            session: imported.session
        )
        let localReincorporation = try ConversationArchiveService.incorporate(
            localStored,
            source: VersionChatID(versionID: localVersion.id, chatID: localChat.id),
            context: localContext,
            in: imported.session
        )
        XCTAssertFalse(localReincorporation.incorporatedSource)
        XCTAssertTrue(localReincorporation.conversation.record.contributions.isEmpty)
        XCTAssertEqual(
            localReincorporation.conversation.record.importedContributions.count,
            1
        )

        let detachment = try ConversationArchiveService.detachImportedContribution(
            id: imported.importedContribution.id,
            from: imported.session
        )
        let importedURL = fixture.session.paths.importedChatsURL
            .appendingPathComponent(imported.importedContribution.relativeDirectory)
        let mergedURL = fixture.session.paths.mergedChatsURL
            .appendingPathComponent(imported.conversation.record.id.rawValue)

        XCTAssertNil(detachment.conversation)
        XCTAssertTrue(try ConversationArchiveService.catalog(in: imported.session).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: importedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: mergedURL.path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: localStored.directoryURL.appendingPathComponent("archive.json").path
            )
        )
        let detached = try XCTUnwrap(
            ConversationArchiveService.detachedImportedChats(in: imported.session).first
        )
        XCTAssertEqual(detached.id, imported.importedContribution.id)
        XCTAssertFalse(detached.isInConversation)

        XCTAssertThrowsError(
            try ConversationArchiveService.importPortableConversationArchive(
                at: archiveURL,
                into: imported.session
            )
        ) { error in
            guard case ConversationArchiveError.importedConversationAlreadyExists = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        let reincorporation =
            try ConversationArchiveService.incorporateDetachedImportedContribution(
                id: detached.id,
                into: imported.session
            )
        XCTAssertEqual(reincorporation.conversation.document.messages.count, 5)
        XCTAssertEqual(reincorporation.conversation.record.importedContributions.count, 1)
        XCTAssertTrue(
            try ConversationArchiveService.detachedImportedChats(in: imported.session).isEmpty
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: importedURL.path))

        _ = try ConversationArchiveService.detachImportedContribution(
            id: imported.importedContribution.id,
            from: imported.session
        )
        try ConversationArchiveService.deleteDetachedImportedContribution(
            id: imported.importedContribution.id,
            from: imported.session
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: importedURL.path))
        XCTAssertTrue(
            try ConversationArchiveService.detachedImportedChats(in: imported.session).isEmpty
        )
    }

    func testAddingNewLocalCopyAfterImportPreservesImportedContribution() throws {
        let fixtures = [
            StoredChatFixture(
                versionID: "local-old",
                chatID: 10,
                jid: "34600000002@s.whatsapp.net",
                name: "B",
                storedAt: "2026-01-10T12:00:00Z",
                messages: [
                    MessageFixture(id: 1, text: "First shared individual", date: "2026-01-01T10:00:01Z", isFromMe: true),
                    MessageFixture(id: 2, text: "Second shared individual", date: "2026-01-01T10:00:02Z"),
                    MessageFixture(id: 3, text: "Third shared individual", date: "2026-01-01T10:00:03Z", isFromMe: true)
                ]
            ),
            StoredChatFixture(
                versionID: "local-new",
                chatID: 11,
                jid: "34600000002@s.whatsapp.net",
                name: "B",
                storedAt: "2026-03-10T12:00:00Z",
                messages: [
                    MessageFixture(id: 21, text: "First shared individual", date: "2026-01-01T10:00:01Z", isFromMe: true),
                    MessageFixture(id: 22, text: "Second shared individual", date: "2026-01-01T10:00:02Z"),
                    MessageFixture(id: 23, text: "Third shared individual", date: "2026-01-01T10:00:03Z", isFromMe: true),
                    MessageFixture(id: 24, text: "Exclusive new local", date: "2026-01-01T10:00:06Z", isFromMe: true)
                ]
            ),
            oppositeIndividualStoredChats()[1]
        ]
        let fixture = try makeLibrary(storedChats: fixtures)
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let oldVersion = try XCTUnwrap(fixture.session.version(id: "local-old"))
        let newVersion = try XCTUnwrap(fixture.session.version(id: "local-new"))
        let receivedVersion = try XCTUnwrap(fixture.session.version(id: "received"))
        let oldChat = try XCTUnwrap(oldVersion.chats.first)
        _ = try ConversationArchiveService.incorporate(
            oldVersion.storedChatStore.openChat(chatId: oldChat.id),
            source: VersionChatID(versionID: oldVersion.id, chatID: oldChat.id),
            context: ConversationArchiveService.prepareIncorporation(
                for: oldChat,
                in: oldVersion,
                session: fixture.session
            ),
            in: fixture.session
        )
        let receivedStored = try receivedVersion.storedChatStore.openChat(chatId: 20)
        let archiveURL = fixture.rootURL.appendingPathComponent("received.fmcchat")
        _ = try ConversationArchiveService.createPortableConversationArchive(
            from: ConversationSource(
                id: ConversationSourceID(rawValue: "received"),
                storedChat: receivedStored
            ),
            producerVersion: "test",
            destinationURL: archiveURL
        )
        let imported = try ConversationArchiveService.importPortableConversationArchive(
            at: archiveURL,
            into: fixture.session
        )
        let newChat = try XCTUnwrap(newVersion.chats.first)
        let update = try ConversationArchiveService.incorporate(
            newVersion.storedChatStore.openChat(chatId: newChat.id),
            source: VersionChatID(versionID: newVersion.id, chatID: newChat.id),
            context: ConversationArchiveService.prepareIncorporation(
                for: newChat,
                in: newVersion,
                session: imported.session
            ),
            in: imported.session
        )
        let importedURL = fixture.session.paths.importedChatsURL
            .appendingPathComponent(imported.importedContribution.relativeDirectory)

        XCTAssertEqual(update.conversation.record.contributions.count, 2)
        XCTAssertEqual(update.conversation.record.importedContributions.count, 1)
        XCTAssertEqual(update.conversation.document.messages.count, 6)
        XCTAssertEqual(
            update.conversation.record.contributions.first {
                $0.source.versionID == "local-old"
            }?.contributedMessageCount,
            3
        )
        XCTAssertEqual(
            update.conversation.record.contributions.first {
                $0.source.versionID == "local-new"
            }?.contributedMessageCount,
            1
        )
        XCTAssertEqual(
            update.conversation.record.importedContributions.first?.contributedMessageCount,
            2
        )
        XCTAssertTrue(
            update.conversation.document.messages.contains {
                $0.message == "Exclusive new local"
            }
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: importedURL.path))
    }

    func testImportRejectsPortableConversationWithoutExistingMatch() throws {
        let fixture = try makeLibrary(
            storedChats: [
                StoredChatFixture(
                    versionID: "local",
                    chatID: 10,
                    jid: "local-group@g.us",
                    name: "Grupo local",
                    storedAt: "2026-01-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 1, text: "Local A", date: "2026-01-01T10:00:01Z"),
                        MessageFixture(id: 2, text: "Local B", date: "2026-01-01T10:00:02Z"),
                        MessageFixture(id: 3, text: "Local C", date: "2026-01-01T10:00:03Z")
                    ]
                ),
                StoredChatFixture(
                    versionID: "other",
                    chatID: 20,
                    jid: "other-group@g.us",
                    name: "Otro grupo",
                    storedAt: "2026-02-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 11, text: "Other A", date: "2026-01-01T10:00:01Z"),
                        MessageFixture(id: 12, text: "Other B", date: "2026-01-01T10:00:02Z"),
                        MessageFixture(id: 13, text: "Other C", date: "2026-01-01T10:00:03Z")
                    ]
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let localVersion = try XCTUnwrap(fixture.session.version(id: "local"))
        let localChat = try XCTUnwrap(localVersion.chats.first)
        _ = try ConversationArchiveService.incorporate(
            localVersion.storedChatStore.openChat(chatId: localChat.id),
            source: VersionChatID(versionID: "local", chatID: localChat.id),
            context: ConversationArchiveService.prepareIncorporation(
                for: localChat,
                in: localVersion,
                session: fixture.session
            ),
            in: fixture.session
        )
        let otherStored = try XCTUnwrap(fixture.session.version(id: "other"))
            .storedChatStore.openChat(chatId: 20)
        let archiveURL = fixture.rootURL.appendingPathComponent("other.fmcchat")
        _ = try ConversationArchiveService.createPortableConversationArchive(
            from: ConversationSource(
                id: ConversationSourceID(rawValue: "other"),
                storedChat: otherStored
            ),
            producerVersion: "test",
            destinationURL: archiveURL
        )

        XCTAssertThrowsError(
            try ConversationArchiveService.importPortableConversationArchive(
                at: archiveURL,
                into: fixture.session
            )
        ) { error in
            guard case ConversationArchiveError.noMatchingConversation = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertTrue(
            (try FileManager.default.contentsOfDirectory(
                at: fixture.session.paths.importedChatsURL,
                includingPropertiesForKeys: nil
            )).isEmpty
        )
    }

    func testStagesOppositeGroupPerspectiveWithSeveralAuthors() throws {
        let fixture = try makeLibrary(
            storedChats: oppositeGroupStoredChats()
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let targetVersion = try XCTUnwrap(fixture.session.version(id: "local-group"))
        let sourceVersion = try XCTUnwrap(fixture.session.version(id: "received-group"))
        let targetStoredChat = try targetVersion.storedChatStore.openChat(chatId: 30)
        let sourceStoredChat = try sourceVersion.storedChatStore.openChat(chatId: 40)
        let target = try ConversationSource(
            id: ConversationSourceID(rawValue: "local-group"),
            storedChat: targetStoredChat
        )
        let source = try ConversationSource(
            id: ConversationSourceID(rawValue: "received-group"),
            storedChat: sourceStoredChat
        )

        let result = try ConversationArchiveService.stageCrossPerspectiveComposition(
            sources: [target, source],
            targetSourceID: target.id,
            targetChatID: 88,
            destinationDirectory: fixture.rootURL.appendingPathComponent("group-import-staging")
        )

        XCTAssertEqual(result.document.messages.count, 6)
        XCTAssertEqual(result.document.messages.map(\.isFromMe), [true, false, true, false, true, false])
        XCTAssertEqual(result.document.messages[3].author?.phone, "34600000002")
        XCTAssertEqual(result.document.messages[4].author?.kind, .me)
        XCTAssertEqual(result.document.messages[5].author?.phone, "34600000003")
    }

    func testRejectedCrossPerspectiveStagingLeavesNoOutput() throws {
        let fixture = try makeLibrary(
            storedChats: [
                StoredChatFixture(
                    versionID: "local",
                    chatID: 10,
                    jid: "family@g.us",
                    name: "Familia",
                    storedAt: "2026-01-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 1, text: "Only shared", date: "2026-01-01T10:00:01Z")
                    ]
                ),
                StoredChatFixture(
                    versionID: "received",
                    chatID: 20,
                    jid: "family@g.us",
                    name: "Familia",
                    storedAt: "2026-02-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 11, text: "Only shared", date: "2026-01-01T10:00:01Z")
                    ]
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let targetStoredChat = try XCTUnwrap(fixture.session.version(id: "local"))
            .storedChatStore.openChat(chatId: 10)
        let sourceStoredChat = try XCTUnwrap(fixture.session.version(id: "received"))
            .storedChatStore.openChat(chatId: 20)
        let target = try ConversationSource(
            id: ConversationSourceID(rawValue: "local"),
            storedChat: targetStoredChat
        )
        let source = try ConversationSource(
            id: ConversationSourceID(rawValue: "received"),
            storedChat: sourceStoredChat
        )
        let destination = fixture.rootURL.appendingPathComponent("rejected-staging")

        XCTAssertThrowsError(
            try ConversationArchiveService.stageCrossPerspectiveComposition(
                sources: [target, source],
                targetSourceID: target.id,
                targetChatID: 1,
                destinationDirectory: destination
            )
        ) { error in
            guard case ConversationCompositionError.crossPerspectiveCompositionRejected = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
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

    func testStoredLIDChatLearnsPhoneAliasWhenAddedBeforeOlderPhoneChat() throws {
        let phoneJID = "34608100195@s.whatsapp.net"
        let lidJID = "54950012932116@lid"
        let fixture = try makeLibrary(
            storedChats: [
                StoredChatFixture(
                    versionID: "recent",
                    chatID: 762,
                    jid: lidJID,
                    name: "Instituto Juan Gil Albert",
                    storedAt: "2026-07-23T10:16:50Z",
                    messages: [
                        MessageFixture(
                            id: 183500,
                            text: "Mensaje reciente",
                            date: "2026-07-22T13:42:16Z",
                            authorJID: phoneJID,
                            authorPhone: "34608100195"
                        )
                    ]
                ),
                StoredChatFixture(
                    versionID: "old",
                    chatID: 548,
                    jid: phoneJID,
                    name: "Instituto Juan Gil Albert",
                    storedAt: "2026-07-20T16:42:54Z",
                    messages: [
                        MessageFixture(
                            id: 182949,
                            text: "Mensaje antiguo",
                            date: "2026-07-16T09:58:01Z",
                            authorJID: phoneJID,
                            authorPhone: "34608100195"
                        )
                    ]
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let recentVersion = try XCTUnwrap(fixture.session.version(id: "recent"))
        let recent = try recentVersion.storedChatStore.openChat(chatId: 762)
        let recentSource = VersionChatID(versionID: "recent", chatID: 762)
        let recentUpdate = try ConversationArchiveService.incorporate(
            recent,
            source: recentSource,
            context: ConversationArchiveService.prepareIncorporation(
                for: recent.document.chat,
                in: recentVersion,
                session: fixture.session
            ),
            in: fixture.session
        )

        XCTAssertEqual(recentUpdate.conversation.record.key.contactJID, phoneJID)
        XCTAssertEqual(
            recentUpdate.conversation.record.identityKeys,
            Set([
                ConversationIdentityKey(chatType: .individual, contactJID: phoneJID),
                ConversationIdentityKey(chatType: .individual, contactJID: lidJID)
            ])
        )

        let oldVersion = try XCTUnwrap(fixture.session.version(id: "old"))
        let old = try oldVersion.storedChatStore.openChat(chatId: 548)
        let oldSource = VersionChatID(versionID: "old", chatID: 548)
        let oldContext = try ConversationArchiveService.prepareIncorporation(
            for: old.document.chat,
            in: oldVersion,
            session: fixture.session
        )

        XCTAssertEqual(oldContext.record?.id, recentUpdate.conversation.record.id)

        _ = try ConversationArchiveService.incorporate(
            old,
            source: oldSource,
            context: oldContext,
            in: fixture.session
        )
        let catalog = try ConversationArchiveService.catalog(in: fixture.session)

        XCTAssertEqual(catalog.count, 1)
        XCTAssertEqual(catalog.first?.contributionCount, 2)
        XCTAssertEqual(
            Set(catalog.first?.contributionSources ?? []),
            Set([recentSource, oldSource])
        )
    }

    func testSuccessiveStoredChatsFromSameOwnerBecomeOneConversation() throws {
        let fixture = try makeLibrary(
            storedChats: [
                StoredChatFixture(
                    versionID: "january",
                    chatID: 7,
                    jid: "34600111222@s.whatsapp.net",
                    name: "Ana",
                    storedAt: "2026-01-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 101, text: "Mensaje antiguo 1", date: "2026-01-01T10:00:00Z"),
                        MessageFixture(id: 102, text: "Mensaje antiguo 2", date: "2026-01-02T10:00:00Z")
                    ]
                ),
                StoredChatFixture(
                    versionID: "july",
                    chatID: 42,
                    jid: "34600111222@s.whatsapp.net",
                    name: "Ana",
                    storedAt: "2026-07-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 1, text: "Mensaje nuevo 1", date: "2026-07-01T10:00:00Z"),
                        MessageFixture(id: 2, text: "Mensaje nuevo 2", date: "2026-07-02T10:00:00Z")
                    ]
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let catalog = try incorporateAllStoredChats(in: fixture)
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
            storedChats: [
                StoredChatFixture(
                    versionID: "first",
                    chatID: 7,
                    jid: "family@g.us",
                    name: "Familia",
                    storedAt: "2026-01-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 1, text: "A", date: "2026-01-01T10:00:00Z"),
                        MessageFixture(id: 2, text: "B", date: "2026-01-02T10:00:00Z")
                    ]
                ),
                StoredChatFixture(
                    versionID: "second",
                    chatID: 99,
                    jid: "family@g.us",
                    name: "Familia",
                    storedAt: "2026-02-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 80, text: "B", date: "2026-01-02T10:00:00Z"),
                        MessageFixture(id: 81, text: "C", date: "2026-02-02T10:00:00Z")
                    ]
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let item = try XCTUnwrap(
            incorporateAllStoredChats(in: fixture).first
        )
        let archived = try ConversationArchiveService.open(
            id: item.id,
            paths: fixture.session.paths
        )

        XCTAssertEqual(archived.document.messages.map(\.message), ["A", "B", "C"])
        XCTAssertEqual(archived.record.contributions.count, 2)
    }

    func testStoredContributionCountsReflectThreeStoredChats() throws {
        let fixture = try makeLibrary(
            storedChats: [
                StoredChatFixture(
                    versionID: "a",
                    chatID: 7,
                    jid: "family@g.us",
                    name: "Familia",
                    storedAt: "2026-01-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 1, text: "A", date: "2026-01-01T10:00:00Z"),
                        MessageFixture(id: 2, text: "B", date: "2026-01-02T10:00:00Z")
                    ]
                ),
                StoredChatFixture(
                    versionID: "b",
                    chatID: 7,
                    jid: "family@g.us",
                    name: "Familia",
                    storedAt: "2026-02-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 10, text: "B", date: "2026-01-02T10:00:00Z"),
                        MessageFixture(id: 11, text: "C", date: "2026-02-01T10:00:00Z")
                    ]
                ),
                StoredChatFixture(
                    versionID: "c",
                    chatID: 7,
                    jid: "family@g.us",
                    name: "Familia",
                    storedAt: "2026-03-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 20, text: "C", date: "2026-02-01T10:00:00Z"),
                        MessageFixture(id: 21, text: "D", date: "2026-03-01T10:00:00Z")
                    ]
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let item = try XCTUnwrap(incorporateAllStoredChats(in: fixture).first)
        let archived = try ConversationArchiveService.open(
            id: item.id,
            paths: fixture.session.paths
        )
        let contributions = Dictionary(
            uniqueKeysWithValues: archived.record.contributions.map { ($0.source.versionID, $0) }
        )
        XCTAssertEqual(contributions["a"]?.messageCount, 2)
        XCTAssertEqual(contributions["a"]?.exclusiveMessageCount, 1)
        XCTAssertEqual(contributions["a"]?.contributedMessageCount, 2)
        XCTAssertEqual(contributions["b"]?.messageCount, 2)
        XCTAssertEqual(contributions["b"]?.exclusiveMessageCount, 0)
        XCTAssertEqual(contributions["b"]?.contributedMessageCount, 1)
        XCTAssertEqual(contributions["c"]?.messageCount, 2)
        XCTAssertEqual(contributions["c"]?.exclusiveMessageCount, 1)
        XCTAssertEqual(contributions["c"]?.contributedMessageCount, 1)
        XCTAssertEqual(
            contributions.values.compactMap(\.contributedMessageCount).reduce(0, +),
            archived.document.messages.count
        )

        let bImpact = try XCTUnwrap(ConversationArchiveService.storedRemovalMessageImpact(
            of: VersionChatID(versionID: "b", chatID: 7),
            in: fixture.session
        ))
        XCTAssertEqual(bImpact.sourceMessageCount, 2)
        XCTAssertEqual(bImpact.removedMessageCount, 0)
        XCTAssertEqual(bImpact.resultingMessageCount, 4)

        let cImpact = try XCTUnwrap(ConversationArchiveService.storedRemovalMessageImpact(
            of: VersionChatID(versionID: "c", chatID: 7),
            in: fixture.session
        ))
        XCTAssertEqual(cImpact.sourceMessageCount, 2)
        XCTAssertEqual(cImpact.removedMessageCount, 1)
        XCTAssertEqual(cImpact.resultingMessageCount, 3)
    }

    func testAddingSupersetChatAutomaticallyRemovesPreviousChatFromCatalog() throws {
        let fixture = try makeLibrary(
            storedChats: [
                StoredChatFixture(
                    versionID: "old",
                    chatID: 7,
                    jid: "family@g.us",
                    name: "Familia",
                    storedAt: "2026-01-10T12:00:00Z",
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
                StoredChatFixture(
                    versionID: "new",
                    chatID: 7,
                    jid: "family@g.us",
                    name: "Familia",
                    storedAt: "2026-02-10T12:00:00Z",
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

        let oldVersion = try XCTUnwrap(fixture.session.version(id: "old"))
        let newVersion = try XCTUnwrap(fixture.session.version(id: "new"))
        let oldStored = try oldVersion.storedChatStore.openChat(chatId: 7)
        _ = try ConversationArchiveService.incorporate(
            oldStored,
            source: VersionChatID(versionID: "old", chatID: 7),
            context: ConversationArchiveService.prepareIncorporation(
                for: oldStored.document.chat,
                in: oldVersion,
                session: fixture.session
            ),
            in: fixture.session
        )
        let newStored = try newVersion.storedChatStore.openChat(chatId: 7)
        let update = try ConversationArchiveService.incorporate(
            newStored,
            source: VersionChatID(versionID: "new", chatID: 7),
            context: ConversationArchiveService.prepareIncorporation(
                for: newStored.document.chat,
                in: newVersion,
                session: fixture.session
            ),
            in: fixture.session
        )
        let item = try XCTUnwrap(ConversationArchiveService.catalog(in: fixture.session).first)
        let archived = try ConversationArchiveService.openRepairing(
            item: item,
            in: fixture.session
        )

        XCTAssertEqual(archived.document.messages.map(\.message), [
            "Mensaje compartido",
            "Mensaje nuevo"
        ])
        XCTAssertEqual(update.automaticallyRemovedContributionCount, 1)
        XCTAssertEqual(archived.record.contributions.map(\.source), [
            VersionChatID(versionID: "new", chatID: 7)
        ])
        XCTAssertEqual(item.contributionCount, 1)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: oldStored.directoryURL.appendingPathComponent("archive.json").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: oldStored.directoryURL.appendingPathComponent("chat.json").path
            )
        )
    }

    func testAddingChatWithoutNewMessagesLeavesCatalogUnchanged() throws {
        let fixture = try makeLibrary(
            storedChats: [
                StoredChatFixture(
                    versionID: "existing",
                    chatID: 7,
                    jid: "family@g.us",
                    name: "Familia",
                    storedAt: "2026-01-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 1, text: "A", date: "2026-01-01T10:00:00Z"),
                        MessageFixture(id: 2, text: "B", date: "2026-01-02T10:00:00Z")
                    ]
                ),
                StoredChatFixture(
                    versionID: "duplicate",
                    chatID: 7,
                    jid: "family@g.us",
                    name: "Familia",
                    storedAt: "2026-02-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 10, text: "A", date: "2026-01-01T10:00:00Z"),
                        MessageFixture(id: 20, text: "B", date: "2026-01-02T10:00:00Z")
                    ]
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let existingVersion = try XCTUnwrap(fixture.session.version(id: "existing"))
        let existingStored = try existingVersion.storedChatStore.openChat(chatId: 7)
        let existingUpdate = try ConversationArchiveService.incorporate(
            existingStored,
            source: VersionChatID(versionID: "existing", chatID: 7),
            context: ConversationArchiveService.prepareIncorporation(
                for: existingStored.document.chat,
                in: existingVersion,
                session: fixture.session
            ),
            in: fixture.session
        )
        let catalogBeforeAddition = try XCTUnwrap(
            ConversationArchiveService.catalog(in: fixture.session).first
        )

        let duplicateVersion = try XCTUnwrap(fixture.session.version(id: "duplicate"))
        let duplicateStored = try duplicateVersion.storedChatStore.openChat(chatId: 7)
        let update = try ConversationArchiveService.incorporate(
            duplicateStored,
            source: VersionChatID(versionID: "duplicate", chatID: 7),
            context: ConversationArchiveService.prepareIncorporation(
                for: duplicateStored.document.chat,
                in: duplicateVersion,
                session: fixture.session
            ),
            in: fixture.session
        )
        let catalog = try ConversationArchiveService.catalog(in: fixture.session)
        let item = try XCTUnwrap(catalog.first)

        XCTAssertFalse(update.incorporatedSource)
        XCTAssertEqual(update.addedMessageCount, 0)
        XCTAssertEqual(update.automaticallyRemovedContributionCount, 0)
        XCTAssertEqual(update.conversation.record.id, existingUpdate.conversation.record.id)
        XCTAssertEqual(item.updatedAt, catalogBeforeAddition.updatedAt)
        XCTAssertEqual(update.conversation.document.messages.map(\.message), ["A", "B"])
        XCTAssertEqual(item.contributionSources, [
            VersionChatID(versionID: "existing", chatID: 7)
        ])
        XCTAssertEqual(item.contributionCount, 1)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: existingStored.directoryURL.appendingPathComponent("archive.json").path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: duplicateStored.directoryURL.appendingPathComponent("archive.json").path
            )
        )
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(
                atPath: fixture.session.paths.mergedChatsURL.path
            ).isEmpty
        )
    }

    func testDetachingOneOfTwoContributionsKeepsTheCopyExtractedOutsideTheCatalog() throws {
        let fixture = try makeLibrary(
            storedChats: [
                StoredChatFixture(
                    versionID: "old",
                    chatID: 7,
                    jid: "group@g.us",
                    name: "Grupo",
                    storedAt: "2026-01-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 1, text: "A", date: "2026-01-01T10:00:00Z"),
                        MessageFixture(id: 2, text: "B", date: "2026-01-02T10:00:00Z")
                    ]
                ),
                StoredChatFixture(
                    versionID: "new",
                    chatID: 7,
                    jid: "group@g.us",
                    name: "Grupo",
                    storedAt: "2026-02-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 11, text: "B", date: "2026-01-02T10:00:00Z"),
                        MessageFixture(id: 12, text: "C", date: "2026-02-01T10:00:00Z")
                    ]
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let original = try XCTUnwrap(incorporateAllStoredChats(in: fixture).first)

        let detachment = try ConversationArchiveService.detachContribution(
            source: VersionChatID(versionID: "old", chatID: 7),
            from: fixture.session
        )
        let remainingConversation = try XCTUnwrap(detachment.conversation)
        let catalog = try ConversationArchiveService.catalog(in: fixture.session)

        XCTAssertEqual(remainingConversation.record.id, original.id)
        XCTAssertEqual(
            remainingConversation.record.contributions.map(\.source),
            [VersionChatID(versionID: "new", chatID: 7)]
        )
        XCTAssertEqual(remainingConversation.document.messages.map(\.message), ["B", "C"])
        XCTAssertNotNil(fixture.session.version(id: "old"))
        XCTAssertNotNil(fixture.session.version(id: "new"))
        XCTAssertEqual(catalog.count, 1)
        XCTAssertEqual(catalog.first?.contributionCount, 1)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.session.paths.mergedChatsURL
                    .appendingPathComponent(original.id.rawValue, isDirectory: true).path
            )
        )
        let oldVersion = try XCTUnwrap(fixture.session.version(id: "old"))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: oldVersion.storedChatsURL
                    .appendingPathComponent("Chats/7/chat.json").path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: oldVersion.storedChatsURL
                    .appendingPathComponent("Chats/7/archive.json").path
            )
        )
        let newVersion = try XCTUnwrap(fixture.session.version(id: "new"))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: newVersion.storedChatsURL
                    .appendingPathComponent("Chats/7/archive.json").path
            )
        )
        XCTAssertEqual(
            try ConversationArchiveService.incorporatedContributionSources(
                in: fixture.session
            ),
            [VersionChatID(versionID: "new", chatID: 7)]
        )
    }

    func testDetachingTheOnlyContributionKeepsTheChatExtractedOutsideTheCatalog() throws {
        let fixture = try makeLibrary(
            storedChats: [
                StoredChatFixture(
                    versionID: "only",
                    chatID: 7,
                    jid: "group@g.us",
                    name: "Grupo",
                    storedAt: "2026-01-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 1, text: "A", date: "2026-01-01T10:00:00Z")
                    ]
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        _ = try XCTUnwrap(incorporateAllStoredChats(in: fixture).first)
        let selection = VersionChatID(versionID: "only", chatID: 7)

        let detachment = try ConversationArchiveService.detachContribution(
            source: selection,
            from: fixture.session
        )
        let version = try XCTUnwrap(fixture.session.version(id: "only"))
        let chatURL = version.storedChatsURL.appendingPathComponent("Chats/7")

        XCTAssertNil(detachment.conversation)
        XCTAssertTrue(try ConversationArchiveService.catalog(in: fixture.session).isEmpty)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: chatURL.appendingPathComponent("chat.json").path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: chatURL.appendingPathComponent("archive.json").path
            )
        )
        XCTAssertFalse(
            try ConversationArchiveService.incorporatedContributionSources(
                in: fixture.session
            ).contains(selection)
        )

        let stored = try version.storedChatStore.openChat(chatId: selection.chatID)
        let context = try ConversationArchiveService.prepareIncorporation(
            for: stored.document.chat,
            in: version,
            session: fixture.session
        )
        XCTAssertNil(context.record)

        let update = try ConversationArchiveService.incorporate(
            stored,
            source: selection,
            context: context,
            in: fixture.session
        )
        let restoredCatalog = try ConversationArchiveService.catalog(in: fixture.session)

        XCTAssertEqual(update.conversation.record.contributions.map(\.source), [selection])
        XCTAssertEqual(update.conversation.document.messages.map(\.message), ["A"])
        XCTAssertEqual(restoredCatalog.count, 1)
        XCTAssertEqual(restoredCatalog.first?.contributionCount, 1)
        XCTAssertTrue(
            try ConversationArchiveService.incorporatedContributionSources(
                in: fixture.session
            ).contains(selection)
        )
    }

    func testDetachedExtractedCopyCanBeAddedBackToTheUnifiedConversation() throws {
        let fixture = try makeLibrary(
            storedChats: [
                StoredChatFixture(
                    versionID: "first",
                    chatID: 7,
                    jid: "group@g.us",
                    name: "Grupo",
                    storedAt: "2026-01-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 1, text: "A", date: "2026-01-01T10:00:00Z")
                    ]
                ),
                StoredChatFixture(
                    versionID: "second",
                    chatID: 7,
                    jid: "group@g.us",
                    name: "Grupo",
                    storedAt: "2026-02-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 2, text: "B", date: "2026-02-01T10:00:00Z")
                    ]
                ),
                StoredChatFixture(
                    versionID: "third",
                    chatID: 7,
                    jid: "group@g.us",
                    name: "Grupo",
                    storedAt: "2026-03-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 3, text: "C", date: "2026-03-01T10:00:00Z")
                    ]
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let original = try XCTUnwrap(incorporateAllStoredChats(in: fixture).first)

        let detachment = try ConversationArchiveService.detachContribution(
            source: VersionChatID(versionID: "second", chatID: 7),
            from: fixture.session
        )
        let remainingConversation = try XCTUnwrap(detachment.conversation)
        let catalog = try ConversationArchiveService.catalog(in: fixture.session)

        XCTAssertEqual(remainingConversation.record.id, original.id)
        XCTAssertEqual(
            Set(remainingConversation.record.contributions.map(\.source)),
            Set([
                VersionChatID(versionID: "first", chatID: 7),
                VersionChatID(versionID: "third", chatID: 7)
            ])
        )
        XCTAssertEqual(remainingConversation.document.messages.map(\.message), ["A", "C"])
        XCTAssertEqual(
            catalog.map(\.contributionCount),
            [2]
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: fixture.session.paths.mergedChatsURL
                    .appendingPathComponent(original.id.rawValue, isDirectory: true).path
            )
        )
        let detachedVersion = try XCTUnwrap(fixture.session.version(id: "second"))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: detachedVersion.storedChatsURL
                    .appendingPathComponent("Chats/7/archive.json").path
            )
        )
        let stored = try detachedVersion.storedChatStore.openChat(chatId: 7)
        let context = try ConversationArchiveService.prepareIncorporation(
            for: stored.document.chat,
            in: detachedVersion,
            session: fixture.session
        )
        let update = try ConversationArchiveService.incorporate(
            stored,
            source: VersionChatID(versionID: "second", chatID: 7),
            context: context,
            in: fixture.session
        )
        let restoredCatalog = try ConversationArchiveService.catalog(in: fixture.session)

        XCTAssertEqual(update.conversation.record.id, original.id)
        XCTAssertEqual(update.conversation.document.messages.map(\.message), ["A", "B", "C"])
        XCTAssertEqual(update.conversation.record.contributions.count, 3)
        XCTAssertEqual(restoredCatalog.count, 1)
        XCTAssertEqual(restoredCatalog.first?.contributionCount, 3)
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(atPath: fixture.rootURL.path)
                .contains { $0.hasPrefix(".detaching-contribution-") }
        )
    }

    func testRemovingOlderContributionKeepsTheNewerCompleteConversation() throws {
        let fixture = try makeLibrary(
            storedChats: [
                StoredChatFixture(
                    versionID: "old",
                    chatID: 7,
                    jid: "group@g.us",
                    name: "Grupo",
                    storedAt: "2026-01-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 1, text: "A", date: "2026-01-01T10:00:00Z"),
                        MessageFixture(id: 2, text: "B", date: "2026-01-02T10:00:00Z")
                    ]
                ),
                StoredChatFixture(
                    versionID: "new",
                    chatID: 7,
                    jid: "group@g.us",
                    name: "Grupo",
                    storedAt: "2026-02-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 11, text: "B", date: "2026-01-02T10:00:00Z"),
                        MessageFixture(id: 12, text: "C", date: "2026-02-01T10:00:00Z")
                    ]
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let original = try XCTUnwrap(incorporateAllStoredChats(in: fixture).first)

        let removal = try ConversationArchiveService.removeContribution(
            source: VersionChatID(versionID: "old", chatID: 7),
            from: fixture.session
        )
        let conversation = try XCTUnwrap(removal.conversation)
        let catalog = try ConversationArchiveService.catalog(in: removal.session)

        XCTAssertEqual(conversation.document.messages.map(\.message), ["B", "C"])
        XCTAssertEqual(conversation.record.contributions.count, 1)
        XCTAssertEqual(conversation.record.contributions.first?.messageCount, 2)
        XCTAssertEqual(conversation.record.contributions.first?.exclusiveMessageCount, 2)
        XCTAssertNil(removal.session.version(id: "old"))
        XCTAssertNotNil(removal.session.version(id: "new"))
        XCTAssertEqual(catalog.count, 1)
        XCTAssertEqual(catalog.first?.contributionCount, 1)
        let remainingVersion = try XCTUnwrap(removal.session.version(id: "new"))
        let remainingDirectory = remainingVersion.storedChatsURL
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
            storedChats: [
                StoredChatFixture(
                    versionID: "old",
                    chatID: 7,
                    jid: "group@g.us",
                    name: "Grupo",
                    storedAt: "2026-01-10T12:00:00Z",
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
                StoredChatFixture(
                    versionID: "new",
                    chatID: 7,
                    jid: "group@g.us",
                    name: "Grupo",
                    storedAt: "2026-02-10T12:00:00Z",
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
            incorporateAllStoredChats(in: fixture).first
        )
        let archived = try ConversationArchiveService.open(
            id: item.id,
            paths: fixture.session.paths
        )
        let missingFilename = try XCTUnwrap(archived.document.messages.first?.mediaFilename)
        try FileManager.default.removeItem(
            at: archived.mediaDirectoryURL.appendingPathComponent(missingFilename)
        )

        let impact = try ConversationArchiveService.removalMessageImpact(
            of: VersionChatID(versionID: "old", chatID: 7),
            in: fixture.session
        )
        XCTAssertEqual(impact.removedMessageCount, 1)
        XCTAssertEqual(impact.resultingMessageCount, 1)

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
            storedChats: [
                StoredChatFixture(
                    versionID: "old",
                    chatID: 7,
                    jid: "group@g.us",
                    name: "Grupo",
                    storedAt: "2026-01-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 1, text: "A", date: "2026-01-01T10:00:00Z"),
                        MessageFixture(id: 2, text: "B", date: "2026-01-02T10:00:00Z")
                    ]
                ),
                StoredChatFixture(
                    versionID: "new",
                    chatID: 7,
                    jid: "group@g.us",
                    name: "Grupo",
                    storedAt: "2026-02-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 11, text: "B", date: "2026-01-02T10:00:00Z"),
                        MessageFixture(id: 12, text: "C", date: "2026-02-01T10:00:00Z")
                    ]
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        _ = try incorporateAllStoredChats(in: fixture)

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
            storedChats: [
                StoredChatFixture(
                    versionID: "first",
                    chatID: 7,
                    jid: "group@g.us",
                    name: "Grupo",
                    storedAt: "2026-01-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 1, text: "A", date: "2026-01-01T10:00:00Z")
                    ]
                ),
                StoredChatFixture(
                    versionID: "second",
                    chatID: 7,
                    jid: "group@g.us",
                    name: "Grupo",
                    storedAt: "2026-02-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 2, text: "B", date: "2026-02-01T10:00:00Z")
                    ]
                ),
                StoredChatFixture(
                    versionID: "third",
                    chatID: 7,
                    jid: "group@g.us",
                    name: "Grupo",
                    storedAt: "2026-03-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 3, text: "C", date: "2026-03-01T10:00:00Z")
                    ]
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let original = try XCTUnwrap(incorporateAllStoredChats(in: fixture).first)

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
                    atPath: version.storedChatsURL
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
            storedChats: [
                StoredChatFixture(
                    versionID: "only",
                    chatID: 7,
                    jid: "34600111222@s.whatsapp.net",
                    name: "Ana",
                    storedAt: "2026-01-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 1, text: "Hola", date: "2026-01-01T10:00:00Z")
                    ]
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let original = try XCTUnwrap(incorporateAllStoredChats(in: fixture).first)
        let onlyVersion = try XCTUnwrap(fixture.session.version(id: "only"))
        let onlyDirectory = onlyVersion.storedChatsURL
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

    func testUpdatingSingleStoredChatRestoresItsPreparedArchiveRecord() throws {
        let fixture = try makeLibrary(
            storedChats: [
                StoredChatFixture(
                    versionID: "only",
                    chatID: 7,
                    jid: "34600111222@s.whatsapp.net",
                    name: "Ana",
                    storedAt: "2026-01-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 1, text: "Hola", date: "2026-01-01T10:00:00Z")
                    ]
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let originalItem = try XCTUnwrap(incorporateAllStoredChats(in: fixture).first)
        let version = try XCTUnwrap(fixture.session.version(id: "only"))
        let stored = try version.storedChatStore.openChat(chatId: 7)
        let context = try ConversationArchiveService.prepareIncorporation(
            for: stored.document.chat,
            in: version,
            session: fixture.session
        )
        let archiveURL = stored.directoryURL.appendingPathComponent("archive.json")
        try FileManager.default.removeItem(at: archiveURL)

        let update = try ConversationArchiveService.incorporate(
            stored,
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

    func testPreparedSingleRecordCanBeRestoredAfterAStoredChatFailure() throws {
        let fixture = try makeLibrary(
            storedChats: [
                StoredChatFixture(
                    versionID: "only",
                    chatID: 7,
                    jid: "34600111222@s.whatsapp.net",
                    name: "Ana",
                    storedAt: "2026-01-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 1, text: "Hola", date: "2026-01-01T10:00:00Z")
                    ]
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let original = try XCTUnwrap(incorporateAllStoredChats(in: fixture).first)
        let version = try XCTUnwrap(fixture.session.version(id: "only"))
        let stored = try version.storedChatStore.openChat(chatId: 7)
        let context = try ConversationArchiveService.prepareIncorporation(
            for: stored.document.chat,
            in: version,
            session: fixture.session
        )
        let archiveURL = stored.directoryURL.appendingPathComponent("archive.json")
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
            storedChats: [
                StoredChatFixture(
                    versionID: "first",
                    chatID: 10,
                    jid: "34600999888@s.whatsapp.net",
                    name: "Luis",
                    storedAt: "2026-03-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 1, text: "Primero", date: "2026-03-01T10:00:00Z")
                    ]
                ),
                StoredChatFixture(
                    versionID: "second",
                    chatID: 90,
                    jid: "34600999888@s.whatsapp.net",
                    name: "Luis",
                    storedAt: "2026-04-10T12:00:00Z",
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
        let firstStoredChat = try firstVersion.storedChatStore.openChat(chatId: 10)
        let firstContext = try ConversationArchiveService.prepareIncorporation(
            for: firstStoredChat.document.chat,
            in: firstVersion,
            session: fixture.session
        )
        let first = try ConversationArchiveService.incorporate(
            firstStoredChat,
            source: firstSelection,
            context: firstContext,
            in: fixture.session
        )
        let secondStoredChat = try secondVersion.storedChatStore.openChat(chatId: 90)
        let secondContext = try ConversationArchiveService.prepareIncorporation(
            for: secondStoredChat.document.chat,
            in: secondVersion,
            session: fixture.session
        )
        let second = try ConversationArchiveService.incorporate(
            secondStoredChat,
            source: secondSelection,
            context: secondContext,
            in: fixture.session
        )

        XCTAssertEqual(first.conversation.document.messages.map(\.message), ["Primero"])
        XCTAssertEqual(first.conversation.directoryURL, firstStoredChat.directoryURL)
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
                atPath: firstStoredChat.directoryURL.appendingPathComponent("archive.json").path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: secondStoredChat.directoryURL.appendingPathComponent("archive.json").path
            )
        )
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(atPath: fixture.session.paths.mergedChatsURL.path)
                .contains { $0.hasPrefix(".building-") }
        )
    }

    func testUpdatingAContributionRebuildsTheExistingCombinedConversation() throws {
        let fixture = try makeLibrary(
            storedChats: [
                StoredChatFixture(
                    versionID: "old",
                    chatID: 7,
                    jid: "group@g.us",
                    name: "Grupo",
                    storedAt: "2026-01-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 1, text: "A", date: "2026-01-01T10:00:00Z")
                    ]
                ),
                StoredChatFixture(
                    versionID: "new",
                    chatID: 7,
                    jid: "group@g.us",
                    name: "Grupo",
                    storedAt: "2026-02-10T12:00:00Z",
                    messages: [
                        MessageFixture(id: 2, text: "B", date: "2026-02-01T10:00:00Z")
                    ]
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let original = try XCTUnwrap(incorporateAllStoredChats(in: fixture).first)
        let oldVersion = try XCTUnwrap(fixture.session.version(id: "old"))
        let oldStoredChat = try oldVersion.storedChatStore.openChat(chatId: 7)
        let context = try ConversationArchiveService.prepareIncorporation(
            for: oldStoredChat.document.chat,
            in: oldVersion,
            session: fixture.session
        )
        try write(
            StoredChatFixture(
                versionID: "old",
                chatID: 7,
                jid: "group@g.us",
                name: "Grupo",
                storedAt: "2026-03-10T12:00:00Z",
                messages: [
                    MessageFixture(id: 1, text: "A", date: "2026-01-01T10:00:00Z"),
                    MessageFixture(id: 3, text: "C", date: "2026-03-01T10:00:00Z")
                ]
            ),
            to: oldVersion.storedChatsURL
        )
        let updatedStoredChat = try oldVersion.storedChatStore.openChat(chatId: 7)

        let update = try ConversationArchiveService.incorporate(
            updatedStoredChat,
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
                    atPath: version.storedChatsURL
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
            storedChats: [
                StoredChatFixture(
                    versionID: "first",
                    chatID: 7,
                    jid: "first@g.us",
                    name: "Familia",
                    storedAt: "2026-01-10T12:00:00Z",
                    messages: []
                ),
                StoredChatFixture(
                    versionID: "second",
                    chatID: 8,
                    jid: "second@g.us",
                    name: "Familia",
                    storedAt: "2026-02-10T12:00:00Z",
                    messages: []
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let catalog = try incorporateAllStoredChats(in: fixture)

        XCTAssertEqual(catalog.count, 2)
        XCTAssertEqual(Set(catalog.map { $0.chat.contactJid }), ["first@g.us", "second@g.us"])
    }

    func testMediaWithSameFilenameAndDifferentContentsRemainDistinct() throws {
        let fixture = try makeLibrary(
            storedChats: [
                StoredChatFixture(
                    versionID: "old",
                    chatID: 3,
                    jid: "media@g.us",
                    name: "Media",
                    storedAt: "2026-01-10T12:00:00Z",
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
                StoredChatFixture(
                    versionID: "new",
                    chatID: 4,
                    jid: "media@g.us",
                    name: "Media",
                    storedAt: "2026-02-10T12:00:00Z",
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
            incorporateAllStoredChats(in: fixture).first
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
            .storedChatsURL
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
            storedChats: [
                StoredChatFixture(
                    versionID: "old",
                    chatID: 3,
                    jid: "media@g.us",
                    name: "Media",
                    storedAt: "2026-01-10T12:00:00Z",
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
                StoredChatFixture(
                    versionID: "new",
                    chatID: 4,
                    jid: "media@g.us",
                    name: "Media",
                    storedAt: "2026-02-10T12:00:00Z",
                    messages: [
                        MessageFixture(
                            id: 80,
                            text: "Audio",
                            date: "2026-02-01T10:00:00Z",
                            mediaFilename: "voice.opus",
                            mediaData: Data("audio".utf8)
                        )
                    ]
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let item = try XCTUnwrap(
            incorporateAllStoredChats(in: fixture).first
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

        XCTAssertEqual(repaired.document.messages.map(\.message), ["Audio", "Audio"])
        XCTAssertEqual(repaired.record.contributions.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: missingURL.path))
    }

    private func makeLibrary(storedChats: [StoredChatFixture]) throws -> LibraryFixture {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let initial = try LibraryService.create(at: rootURL)
        let formatter = ISO8601DateFormatter()
        let records = try storedChats.enumerated().map { index, fixture in
            LibraryVersionRecord(
                id: fixture.versionID,
                sourceBackupIdentifier: "iphone-owner",
                sourceBackupCreationDate: try XCTUnwrap(formatter.date(from: fixture.storedAt)),
                importedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)),
                storageDirectoryName: fixture.versionID
            )
        }
        var manifest = initial.manifest
        manifest.versions = records
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: initial.paths.manifestURL, options: .atomic)

        for fixture in storedChats {
            let record = try XCTUnwrap(records.first { $0.id == fixture.versionID })
            try write(fixture, to: initial.paths.storedChatURL(for: record))
        }
        return LibraryFixture(
            rootURL: rootURL,
            session: try LibraryService.open(selectedURL: rootURL)
        )
    }

    private func oppositeIndividualStoredChats() -> [StoredChatFixture] {
        [
            StoredChatFixture(
                versionID: "local",
                chatID: 10,
                jid: "34600000002@s.whatsapp.net",
                name: "B",
                storedAt: "2026-01-10T12:00:00Z",
                messages: [
                    MessageFixture(id: 1, text: "First shared individual", date: "2026-01-01T10:00:01Z", isFromMe: true),
                    MessageFixture(id: 2, text: "Second shared individual", date: "2026-01-01T10:00:02Z"),
                    MessageFixture(id: 3, text: "Third shared individual", date: "2026-01-01T10:00:03Z", isFromMe: true)
                ]
            ),
            StoredChatFixture(
                versionID: "received",
                chatID: 20,
                jid: "34600000001@s.whatsapp.net",
                name: "A",
                storedAt: "2026-02-10T12:00:00Z",
                messages: [
                    MessageFixture(id: 11, text: "First shared individual", date: "2026-01-01T10:00:01Z"),
                    MessageFixture(id: 12, text: "Second shared individual", date: "2026-01-01T10:00:02Z", isFromMe: true),
                    MessageFixture(id: 13, text: "Third shared individual", date: "2026-01-01T10:00:03Z"),
                    MessageFixture(id: 14, text: "Exclusive from B", date: "2026-01-01T10:00:04Z", isFromMe: true),
                    MessageFixture(id: 15, text: "Exclusive from A", date: "2026-01-01T10:00:05Z")
                ]
            )
        ]
    }

    private func oppositeGroupStoredChats() -> [StoredChatFixture] {
        [
            StoredChatFixture(
                versionID: "local-group",
                chatID: 30,
                jid: "family@g.us",
                name: "Familia",
                storedAt: "2026-01-10T12:00:00Z",
                messages: [
                    MessageFixture(id: 1, text: "First shared group", date: "2026-01-01T10:00:01Z", isFromMe: true),
                    MessageFixture(
                        id: 2,
                        text: "Second shared group",
                        date: "2026-01-01T10:00:02Z",
                        authorJID: "34600000002@s.whatsapp.net",
                        authorPhone: "34600000002"
                    ),
                    MessageFixture(id: 3, text: "Third shared group", date: "2026-01-01T10:00:03Z", isFromMe: true)
                ]
            ),
            StoredChatFixture(
                versionID: "received-group",
                chatID: 40,
                jid: "family@g.us",
                name: "Familia recibida",
                storedAt: "2026-02-10T12:00:00Z",
                messages: [
                    MessageFixture(id: 11, text: "First shared group", date: "2026-01-01T10:00:01Z", authorJID: "34600000001@s.whatsapp.net", authorPhone: "34600000001"),
                    MessageFixture(id: 12, text: "Second shared group", date: "2026-01-01T10:00:02Z", isFromMe: true),
                    MessageFixture(id: 13, text: "Third shared group", date: "2026-01-01T10:00:03Z", authorJID: "34600000001@s.whatsapp.net", authorPhone: "34600000001"),
                    MessageFixture(id: 14, text: "Exclusive from B", date: "2026-01-01T10:00:04Z", isFromMe: true),
                    MessageFixture(id: 15, text: "Exclusive from A", date: "2026-01-01T10:00:05Z", authorJID: "34600000001@s.whatsapp.net", authorPhone: "34600000001"),
                    MessageFixture(id: 16, text: "Exclusive from C", date: "2026-01-01T10:00:06Z", authorJID: "34600000003@s.whatsapp.net", authorPhone: "34600000003")
                ]
            )
        ]
    }

    private func incorporateAllStoredChats(
        in fixture: LibraryFixture
    ) throws -> [ConversationCatalogItem] {
        for version in fixture.session.versions {
            for chat in version.chats {
                let source = VersionChatID(versionID: version.id, chatID: chat.id)
                let stored = try version.storedChatStore.openChat(chatId: chat.id)
                let context = try ConversationArchiveService.prepareIncorporation(
                    for: chat,
                    in: version,
                    session: fixture.session
                )
                _ = try ConversationArchiveService.incorporate(
                    stored,
                    source: source,
                    context: context,
                    in: fixture.session
                )
            }
        }
        return try ConversationArchiveService.catalog(in: fixture.session)
    }

    private func write(_ fixture: StoredChatFixture, to storedChatURL: URL) throws {
        let chatDirectory = storedChatURL.appendingPathComponent(
            "Chats/\(fixture.chatID)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: chatDirectory.appendingPathComponent("Media", isDirectory: true),
            withIntermediateDirectories: true
        )
        let chatType = fixture.jid.hasSuffix("@g.us") ? "group" : "individual"
        let lastDate = fixture.messages.last?.date ?? fixture.storedAt
        let messages: [[String: Any]] = fixture.messages.map { message in
            var object: [String: Any] = [
                "id": message.id,
                "chatId": fixture.chatID,
                "message": message.text,
                "date": message.date,
                "isFromMe": message.isFromMe,
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
            "schemaVersion": 2,
            "storedAt": fixture.storedAt,
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

private struct StoredChatFixture {
    let versionID: String
    let chatID: Int
    let jid: String
    let name: String
    let storedAt: String
    let messages: [MessageFixture]
}

private struct MessageFixture {
    let id: Int
    let text: String
    let date: String
    let isFromMe: Bool
    let mediaFilename: String?
    let mediaData: Data?
    let authorJID: String?
    let authorPhone: String?

    init(
        id: Int,
        text: String,
        date: String,
        isFromMe: Bool = false,
        mediaFilename: String? = nil,
        mediaData: Data? = nil,
        authorJID: String? = nil,
        authorPhone: String? = nil
    ) {
        self.id = id
        self.text = text
        self.date = date
        self.isFromMe = isFromMe
        self.mediaFilename = mediaFilename
        self.mediaData = mediaData
        self.authorJID = authorJID
        self.authorPhone = authorPhone
    }
}
