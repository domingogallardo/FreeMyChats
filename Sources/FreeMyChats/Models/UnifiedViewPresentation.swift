import Foundation

struct UnifiedViewAdditionPreview: Equatable, Identifiable {
    let id: UUID
    let selection: VersionChatID
    let chatName: String
    let existingContributionCount: Int
    let sourceMessageCount: Int
}

struct StoredCopyDeletionPreview: Equatable, Identifiable {
    let id: UUID
    let selection: VersionChatID
    let chatName: String
    let versionTitle: String
    let impact: ConversationRemovalMessageImpact
}

struct StoredCopyDetachmentPreview: Equatable, Identifiable {
    let id: UUID
    let selection: VersionChatID
    let chatName: String
    let versionTitle: String
    let impact: ConversationRemovalMessageImpact
}

enum UnifiedViewPresentation {
    static let catalogAdditionActionTitle = "Añadir al catálogo"
    static let catalogRemovalActionTitle = "Eliminar del catálogo"
    static let catalogRemovalConfirmationTitle = "¿Eliminar del catálogo?"

    static let explanation =
        "Una Vista unificada reúne en una sola cronología los mensajes de varios "
        + "chats de la misma conversación. Cada chat permanece guardado por separado "
        + "y puede eliminarse individualmente del catálogo. Si un mensaje aparece "
        + "en varios chats, se muestra una sola vez."

    static func additionTitle(chatName: String, existingContributionCount: Int) -> String {
        if existingContributionCount == 1 {
            return "¿Crear una Vista unificada de “\(chatName)”?"
        }
        return "¿Actualizar la Vista unificada de “\(chatName)”?"
    }

    static func additionMessage(
        existingContributionCount: Int,
        sourceMessageCount: Int
    ) -> String {
        let source = messageCount(sourceMessageCount)
        let messageImpact = "El chat que vas a añadir contiene \(source). Los mensajes "
            + "repetidos aparecerán una sola vez; al terminar verás cuántos mensajes "
            + "nuevos se han incorporado."
        if existingContributionCount == 1 {
            return "Esta conversación del catálogo ya incluye otro chat. Ambos chats se "
                + "conservarán por separado y sus mensajes se mostrarán juntos en una "
                + "Vista unificada.\n\n\(messageImpact)"
        }
        return "Esta conversación del catálogo ya incluye \(existingContributionCount) "
            + "chats en una Vista unificada. El nuevo chat se conservará por separado "
            + "y sus mensajes se añadirán a la misma cronología.\n\n\(messageImpact)"
    }

    static func additionButtonTitle(existingContributionCount _: Int) -> String {
        catalogAdditionActionTitle
    }

    static func additionActionTitle(addsToExistingConversation _: Bool) -> String {
        catalogAdditionActionTitle
    }

    static func contributionDescription(messageCount: Int) -> String {
        "Aporta \(messageCount.formatted()) mensajes a la conversación"
    }

    static func standaloneDetachmentMessage(chatName: String) -> String {
        "“\(chatName)” se eliminará del catálogo, pero podrá volver a añadirse "
            + "con “Añadir al catálogo”."
    }

    static func deletionTitle(contributionCount: Int) -> String {
        switch contributionCount {
        case 0:
            return "¿Borrar este chat extraído?"
        case 2:
            return "¿Borrar este chat guardado y deshacer la Vista unificada?"
        case 3...:
            return "¿Borrar este chat guardado de la Vista unificada?"
        default:
            return "¿Borrar este chat guardado?"
        }
    }

    static func deletionMessage(
        chatName: String,
        versionTitle: String,
        impact: ConversationRemovalMessageImpact
    ) -> String {
        let origin = "Se borrará el chat guardado “\(chatName)” procedente de “\(versionTitle)”. "
        let messageImpact = removalImpactMessage(impact)
        switch impact.contributionCount {
        case 0:
            return origin
                + "Este chat no forma parte de ninguna conversación del catálogo. "
                + "Se eliminará definitivamente de la biblioteca."
        case 2:
            return origin
                + "El otro chat no se modificará y seguirá guardado por separado. "
                + "Como solo quedará un chat, la Vista unificada desaparecerá. "
                + "\(messageImpact)"
        case 3...:
            let remainingCount = impact.contributionCount - 1
            return origin
                + "Los \(remainingCount) chats restantes no se modificarán y "
                + "seguirán guardados por separado. La Vista unificada se reconstruirá "
                + "con sus mensajes. \(messageImpact)"
        default:
            return origin
                + "Como es el único chat, la conversación desaparecerá del catálogo. "
                + messageImpact
        }
    }

    static func deletionButtonTitle(contributionCount: Int) -> String {
        switch contributionCount {
        case 0: return "Borrar chat"
        case 3...: return "Borrar y actualizar la vista"
        default: return "Borrar chat"
        }
    }

    static func detachmentTitle(contributionCount _: Int) -> String {
        catalogRemovalConfirmationTitle
    }

    static func detachmentMessage(
        chatName: String,
        versionTitle: String,
        impact: ConversationRemovalMessageImpact
    ) -> String {
        if impact.contributionCount == 1 {
            return standaloneDetachmentMessage(chatName: chatName)
        }
        let origin = "El chat guardado “\(chatName)” procedente de “\(versionTitle)” "
            + "se conservará extraído en su copia de WhatsApp, pero se eliminará del catálogo. "
            + "Podrás volver a incorporarlo con "
            + "“Añadir al catálogo”. "
        let messageImpact = detachmentImpactMessage(impact)
        if impact.contributionCount == 2 {
            return origin
                + "El otro chat tampoco se modificará. Como solo quedará un chat en la "
                + "conversación, la Vista unificada desaparecerá. \(messageImpact)"
        }
        let remainingCount = impact.contributionCount - 1
        return origin
            + "La Vista unificada se reconstruirá con los \(remainingCount) chats "
            + "restantes. \(messageImpact)"
    }

    static func incorporationCompletionMessage(
        chatName: String,
        previousContributionCount: Int,
        contributionCount: Int,
        addedMessageCount: Int,
        sourceWasAlreadyIncluded: Bool
    ) -> String {
        let action: String
        if previousContributionCount == 1, !sourceWasAlreadyIncluded {
            action = "Se ha creado la Vista unificada de “\(chatName)” con 2 chats. "
                + "Ambos siguen guardados por separado."
        } else {
            action = "Se ha actualizado la Vista unificada de “\(chatName)” con "
                + "\(contributionCount) chats. Todos siguen guardados por separado."
        }

        let change: String
        switch addedMessageCount {
        case 0:
            change = "No había mensajes nuevos que añadir."
        case 1:
            change = "Se ha añadido 1 mensaje nuevo."
        default:
            change = "Se han añadido \(addedMessageCount.formatted()) mensajes nuevos."
        }
        return "\(action) \(change)"
    }

    private static func removalImpactMessage(
        _ impact: ConversationRemovalMessageImpact
    ) -> String {
        let source = messageCount(impact.sourceMessageCount)
        if impact.contributionCount == 1 {
            return "Se eliminarán los \(source) de esta conversación guardada."
        }
        let result = messageCount(impact.resultingMessageCount)
        switch impact.removedMessageCount {
        case 0:
            return "Este chat contiene \(source), pero no desaparecerá ninguno de "
                + "la conversación porque todos están también en otros chats. "
                + "La conversación seguirá teniendo \(result)."
        case 1:
            return "Este chat contiene \(source). Al borrarlo, 1 mensaje exclusivo "
                + "dejará de aparecer en la conversación, que quedará con \(result)."
        default:
            return "Este chat contiene \(source). Al borrarlo, "
                + "\(impact.removedMessageCount.formatted()) mensajes exclusivos dejarán de "
                + "aparecer en la conversación, que quedará con \(result)."
        }
    }

    private static func detachmentImpactMessage(
        _ impact: ConversationRemovalMessageImpact
    ) -> String {
        let source = messageCount(impact.sourceMessageCount)
        let result = messageCount(impact.resultingMessageCount)
        switch impact.removedMessageCount {
        case 0:
            return "El chat extraído conservará sus \(source). No desaparecerá ningún mensaje "
                + "de la conversación porque todos están también en otros chats, "
                + "que seguirán mostrando \(result)."
        case 1:
            return "El chat extraído conservará sus \(source). Al eliminarlo del catálogo, "
                + "1 mensaje exclusivo "
                + "dejará de aparecer en la conversación, que quedará con \(result)."
        default:
            return "El chat extraído conservará sus \(source). Al eliminarlo del catálogo, "
                + "\(impact.removedMessageCount.formatted()) mensajes exclusivos dejarán de "
                + "aparecer en la conversación, que quedará con \(result)."
        }
    }

    private static func messageCount(_ count: Int) -> String {
        count == 1 ? "1 mensaje" : "\(count.formatted()) mensajes"
    }
}
