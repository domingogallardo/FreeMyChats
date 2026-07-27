import Foundation
import SwiftWABackupAPI
import XCTest
@testable import FreeMyChats

final class MessageReactionPresentationTests: XCTestCase {
    func testGroupsEqualEmojisAndKeepsTheirAuthors() throws {
        let groups = MessageReactionGroup.grouped(
            try reactions(
                """
                [
                  {
                    "emoji": "❤️",
                    "author": {
                      "kind": "participant",
                      "displayName": "Ana",
                      "phone": "34111111111",
                      "jid": "34111111111@s.whatsapp.net",
                      "source": "addressBook"
                    }
                  },
                  {
                    "emoji": "👍",
                    "author": {
                      "kind": "me",
                      "displayName": "Domingo",
                      "phone": "34222222222",
                      "jid": "34222222222@s.whatsapp.net",
                      "source": "owner"
                    }
                  },
                  {
                    "emoji": "❤️",
                    "author": {
                      "kind": "participant",
                      "displayName": "Luis",
                      "phone": "34333333333",
                      "jid": "34333333333@s.whatsapp.net",
                      "source": "addressBook"
                    }
                  }
                ]
                """
            )
        )

        XCTAssertEqual(groups.map(\.emoji), ["❤️", "👍"])
        XCTAssertEqual(groups[0].authors.map(\.displayName), ["Ana", "Luis"])
        XCTAssertEqual(groups[1].authors.map(\.displayName), ["Tú"])
        XCTAssertTrue(groups[1].authors[0].isCurrentUser)
    }

    func testDeduplicatesTheSameAuthorAndUsesIdentityFallbacks() throws {
        let groups = MessageReactionGroup.grouped(
            try reactions(
                """
                [
                  {
                    "emoji": "😂",
                    "author": {
                      "kind": "participant",
                      "displayName": null,
                      "phone": "34111111111",
                      "jid": null,
                      "source": "messageJid"
                    }
                  },
                  {
                    "emoji": "😂",
                    "author": {
                      "kind": "participant",
                      "displayName": null,
                      "phone": "34111111111",
                      "jid": null,
                      "source": "messageJid"
                    }
                  },
                  {
                    "emoji": "😂",
                    "author": {
                      "kind": "participant",
                      "displayName": null,
                      "phone": null,
                      "jid": null,
                      "source": "messageJid"
                    }
                  },
                  {
                    "emoji": "   ",
                    "author": {
                      "kind": "participant",
                      "displayName": "Ignorada",
                      "phone": null,
                      "jid": null,
                      "source": "pushName"
                    }
                  }
                ]
                """
            )
        )

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(
            groups[0].authors.map(\.displayName),
            ["34111111111", "Participante sin identificar"]
        )
    }

    private func reactions(_ json: String) throws -> [Reaction] {
        try JSONDecoder().decode([Reaction].self, from: Data(json.utf8))
    }
}
