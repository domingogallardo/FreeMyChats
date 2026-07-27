import Foundation
import SwiftWABackupAPI

struct MessageReactionGroup: Equatable, Identifiable {
    let emoji: String
    let authors: [MessageReactionAuthor]

    var id: String { emoji }

    static func grouped(_ reactions: [Reaction]) -> [Self] {
        var emojiOrder: [String] = []
        var authorsByEmoji: [String: [MessageReactionAuthor]] = [:]
        var authorIDsByEmoji: [String: Set<String>] = [:]

        for (index, reaction) in reactions.enumerated() {
            let emoji = reaction.emoji.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !emoji.isEmpty else { continue }

            if authorsByEmoji[emoji] == nil {
                emojiOrder.append(emoji)
                authorsByEmoji[emoji] = []
                authorIDsByEmoji[emoji] = []
            }

            let author = MessageReactionAuthor(
                reaction.author,
                unknownIdentityIndex: index
            )
            guard authorIDsByEmoji[emoji]?.insert(author.id).inserted == true else {
                continue
            }
            authorsByEmoji[emoji, default: []].append(author)
        }

        return emojiOrder.map {
            MessageReactionGroup(emoji: $0, authors: authorsByEmoji[$0] ?? [])
        }
    }
}

struct MessageReactionAuthor: Equatable, Identifiable {
    let id: String
    let displayName: String
    let isCurrentUser: Bool

    init(_ author: MessageAuthor, unknownIdentityIndex: Int) {
        if author.kind == .me {
            id = "current-user"
            displayName = "Tú"
            isCurrentUser = true
            return
        }

        let name = author.displayName?.nonEmptyReactionValue
        let phone = author.phone?.nonEmptyReactionValue
        let jid = author.jid?.nonEmptyReactionValue

        if let jid {
            id = "jid:\(jid.lowercased())"
        } else if let phone {
            id = "phone:\(phone)"
        } else if let name {
            id = "name:\(name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil))"
        } else {
            id = "unknown:\(unknownIdentityIndex)"
        }

        displayName = name ?? phone ?? jid ?? "Participante sin identificar"
        isCurrentUser = false
    }
}

private extension String {
    var nonEmptyReactionValue: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
