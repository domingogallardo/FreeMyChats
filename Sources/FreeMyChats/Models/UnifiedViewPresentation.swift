import Foundation

struct UnifiedViewAdditionPreview: Equatable, Identifiable {
    let id: UUID
    let selection: VersionChatID
    let chatName: String
    let existingContributionCount: Int
    let sourceMessageCount: Int
    let requiresExtraction: Bool
}

struct StoredCopyDeletionPreview: Equatable, Identifiable {
    let id: UUID
    let selection: VersionChatID
    let chatName: String
    let versionTitle: String
    let hasSourceBackup: Bool
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

    static func additionTitle(chatName: String, existingContributionCount _: Int) -> String {
        "¿Añadir “\(chatName)” al catálogo?"
    }

    static func additionMessage(
        existingContributionCount: Int,
        sourceMessageCount _: Int,
        requiresExtraction: Bool
    ) -> String {
        let messageImpact = "Los mensajes repetidos aparecerán una sola vez; al terminar "
            + "verás cuántos mensajes nuevos se han incorporado."
        let source = requiresExtraction
            ? "Este chat se extraerá de la copia de WhatsApp y se conservará por separado. "
            : "Este chat extraído se conservará por separado. "
        if existingContributionCount == 1 {
            return source + "Sus mensajes se mostrarán junto a los del otro chat en una "
                + "Vista unificada.\n\n\(messageImpact)"
        }
        return source + "Sus mensajes se añadirán a la "
            + "Vista unificada.\n\n\(messageImpact)"
    }

    static func additionButtonTitle(
        existingContributionCount _: Int,
        requiresExtraction: Bool
    ) -> String {
        requiresExtraction ? "Extraer y añadir al catálogo" : catalogAdditionActionTitle
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

    static func deletionTitle(contributionCount: Int, hasSourceBackup: Bool) -> String {
        if contributionCount == 0, !hasSourceBackup {
            return "¿Borrar definitivamente este chat extraído?"
        }
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
        hasSourceBackup: Bool,
        impact: ConversationRemovalMessageImpact
    ) -> String {
        let origin = "Se borrará el chat guardado “\(chatName)” procedente de “\(versionTitle)”. "
        let messageImpact = removalImpactMessage(impact)
        let recovery: String
        if hasSourceBackup {
            recovery = "La copia de WhatsApp sigue disponible, por lo que podrás volver a "
                + "extraerlo con “Añadir al catálogo”."
        } else {
            recovery = "La copia de WhatsApp ya no está disponible. Si lo borras, no podrás "
                + "recuperar este chat."
        }
        switch impact.contributionCount {
        case 0:
            let removal = hasSourceBackup
                ? "Sus mensajes y archivos se eliminarán de la biblioteca. "
                : "Sus mensajes y archivos se eliminarán definitivamente de la biblioteca. "
            return origin + removal + recovery
        default:
            return origin + messageImpact + " " + recovery
        }
    }

    static func deletionButtonTitle(
        contributionCount: Int,
        hasSourceBackup: Bool
    ) -> String {
        if !hasSourceBackup {
            return "Borrar definitivamente"
        }
        switch contributionCount {
        case 0: return "Borrar chat extraído"
        case 3...: return "Borrar y reconstruir la vista"
        default: return "Borrar chat guardado"
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
        return origin + detachmentImpactMessage(impact)
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
            action = "Se ha creado la Vista unificada de “\(chatName)” con 2 chats."
        } else {
            action = "Se ha actualizado la Vista unificada de “\(chatName)” con "
                + "\(contributionCount) chats."
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

    static func automaticallyRemovedPreviousChatsNotice(count: Int) -> String? {
        switch count {
        case 0:
            return nil
        case 1:
            return "El chat anterior se ha eliminado automáticamente del catálogo porque "
                + "ya no aporta ningún mensaje."
        default:
            return "\(count.formatted()) chats anteriores se han eliminado automáticamente "
                + "del catálogo porque ya no aportan ningún mensaje."
        }
    }

    static func redundantPreviousVersionsNotice(count: Int) -> String? {
        switch count {
        case 0:
            return nil
        case 1:
            return "Una versión anterior ha dejado de aportar mensajes. Puedes eliminarla "
                + "del catálogo sin que desaparezca ningún mensaje de la Vista unificada."
        default:
            return "\(count.formatted()) versiones anteriores han dejado de aportar mensajes. "
                + "Puedes eliminarlas del catálogo sin que desaparezca ningún mensaje de la "
                + "Vista unificada."
        }
    }

    private static func removalImpactMessage(
        _ impact: ConversationRemovalMessageImpact
    ) -> String {
        let source = messageCount(impact.sourceMessageCount)
        if impact.contributionCount == 1 {
            if impact.sourceMessageCount == 1 {
                return "Al borrarlo, la conversación desaparecerá del catálogo junto con "
                    + "su único mensaje."
            }
            return "Al borrarlo, la conversación desaparecerá del catálogo junto con sus "
                + "\(source)."
        }
        let result = messageCount(impact.resultingMessageCount)
        switch impact.removedMessageCount {
        case 0:
            return "Al borrarlo, ningún mensaje dejará de aparecer en la conversación "
                + "porque todos están también en otros chats; seguirá teniendo \(result)."
        case 1:
            return "Al borrarlo, 1 mensaje exclusivo dejará de aparecer en la conversación, "
                + "que quedará con \(result)."
        default:
            return "Al borrarlo, \(impact.removedMessageCount.formatted()) mensajes "
                + "exclusivos dejarán de aparecer en la conversación, que quedará con "
                + "\(result)."
        }
    }

    private static func detachmentImpactMessage(
        _ impact: ConversationRemovalMessageImpact
    ) -> String {
        let result = messageCount(impact.resultingMessageCount)
        switch impact.removedMessageCount {
        case 0:
            return "Al eliminarlo del catálogo, ningún mensaje dejará de aparecer en la "
                + "conversación porque todos están también en otros chats; seguirá teniendo "
                + "\(result)."
        case 1:
            return "Al eliminarlo del catálogo, 1 mensaje exclusivo dejará de aparecer "
                + "en la conversación, que quedará con \(result)."
        default:
            return "Al eliminarlo del catálogo, \(impact.removedMessageCount.formatted()) "
                + "mensajes exclusivos dejarán de aparecer en la conversación, que quedará "
                + "con \(result)."
        }
    }

    private static func messageCount(_ count: Int) -> String {
        count == 1 ? "1 mensaje" : "\(count.formatted()) mensajes"
    }
}
