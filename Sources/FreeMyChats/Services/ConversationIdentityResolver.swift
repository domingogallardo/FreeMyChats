import Foundation
import SQLite3
import SwiftWABackupAPI

struct ResolvedConversationIdentity {
    let primaryKey: ConversationIdentityKey
    let keys: Set<ConversationIdentityKey>
}

struct ConversationIdentityResolver {
    private let phoneJIDByLID: [String: String]

    init(backupURL: URL?) {
        guard let backupURL else {
            phoneJIDByLID = [:]
            return
        }
        phoneJIDByLID = Self.loadMappings(
            from: backupURL.appendingPathComponent("LID.sqlite")
        )
    }

    init(phoneJIDByLID: [String: String]) {
        self.phoneJIDByLID = Dictionary(uniqueKeysWithValues: phoneJIDByLID.map {
            (Self.normalizedJID($0.key), Self.normalizedJID($0.value))
        })
    }

    func identity(for chat: ChatInfo) -> ResolvedConversationIdentity {
        resolvedIdentity(for: chat, participantJIDs: [])
    }

    func identity(for document: StoredChatDocument) -> ResolvedConversationIdentity {
        let participantJIDs: Set<String>
        if document.chat.chatType == .individual {
            participantJIDs = Set(document.messages.compactMap { message in
                guard !message.isFromMe,
                      message.author?.kind == .participant,
                      let jid = message.author?.jid else { return nil }
                let normalized = Self.normalizedJID(jid)
                guard normalized.hasSuffix("@s.whatsapp.net")
                        || normalized.hasSuffix("@lid") else {
                    return nil
                }
                return normalized
            })
        } else {
            participantJIDs = []
        }
        return resolvedIdentity(
            for: document.chat,
            participantJIDs: participantJIDs
        )
    }

    private func resolvedIdentity(
        for chat: ChatInfo,
        participantJIDs: Set<String>
    ) -> ResolvedConversationIdentity {
        let rawKey = ConversationIdentityKey(chat: chat)
        var contactJIDs = participantJIDs
        contactJIDs.insert(rawKey.contactJID)
        for jid in Array(contactJIDs) {
            if let phoneJID = phoneJIDByLID[jid] {
                contactJIDs.insert(phoneJID)
            }
        }

        let keys = Set(contactJIDs.map {
            ConversationIdentityKey(
                chatType: chat.chatType,
                contactJID: $0
            )
        })
        let phoneJIDs = contactJIDs.filter {
            $0.hasSuffix("@s.whatsapp.net")
        }
        let primaryJID: String
        if let mappedPhoneJID = phoneJIDByLID[rawKey.contactJID] {
            primaryJID = mappedPhoneJID
        } else if rawKey.contactJID.hasSuffix("@s.whatsapp.net") {
            primaryJID = rawKey.contactJID
        } else if phoneJIDs.count == 1, let phoneJID = phoneJIDs.first {
            primaryJID = phoneJID
        } else {
            primaryJID = rawKey.contactJID
        }
        let primaryKey = ConversationIdentityKey(
            chatType: chat.chatType,
            contactJID: primaryJID
        )
        return ResolvedConversationIdentity(
            primaryKey: primaryKey,
            keys: keys
        )
    }

    private static func loadMappings(from databaseURL: URL) -> [String: String] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return [:] }

        var database: OpaquePointer?
        guard sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
            nil
        ) == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            return [:]
        }
        defer { sqlite3_close(database) }

        let query = """
            SELECT ZIDENTIFIER, ZPHONENUMBER
            FROM ZWAZACCOUNT
            WHERE ZIDENTIFIER LIKE '%@lid'
              AND ZPHONENUMBER IS NOT NULL
              AND ZPHONENUMBER != ''
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            if let statement { sqlite3_finalize(statement) }
            return [:]
        }
        defer { sqlite3_finalize(statement) }

        var mappings: [String: String] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let rawLID = sqlite3_column_text(statement, 0),
                  let rawPhone = sqlite3_column_text(statement, 1) else { continue }
            let lid = normalizedJID(String(cString: rawLID))
            let phone = String(cString: rawPhone).filter(\.isNumber)
            guard !lid.isEmpty, !phone.isEmpty else { continue }
            mappings[lid] = "\(phone)@s.whatsapp.net"
        }
        return mappings
    }

    private static func normalizedJID(_ jid: String) -> String {
        jid.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
