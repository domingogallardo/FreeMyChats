import Foundation

struct UnifiedViewExportPreview: Equatable, Identifiable {
    let id: UUID
    let selection: VersionChatID
    let chatName: String
    let existingContributionCount: Int
    let sourceMessageCount: Int
}

struct ExportDeletionPreview: Equatable, Identifiable {
    let id: UUID
    let selection: VersionChatID
    let chatName: String
    let versionTitle: String
    let impact: ConversationRemovalMessageImpact
}

enum UnifiedViewPresentation {
    static let explanation =
        "Una Vista unificada reúne en una sola cronología los mensajes de varias "
        + "exportaciones de la misma conversación. Las exportaciones originales "
        + "permanecen guardadas por separado y pueden borrarse individualmente. "
        + "Si un mensaje aparece en varias exportaciones, se muestra una sola vez."

    static func exportTitle(chatName: String, existingContributionCount: Int) -> String {
        if existingContributionCount == 1 {
            return "¿Crear una Vista unificada de “\(chatName)”?"
        }
        return "¿Actualizar la Vista unificada de “\(chatName)”?"
    }

    static func exportMessage(
        existingContributionCount: Int,
        sourceMessageCount: Int
    ) -> String {
        let source = messageCount(sourceMessageCount)
        let messageImpact = "La nueva exportación contiene \(source) y puede añadir hasta "
            + "\(source) a la Vista unificada. Los mensajes que ya estén en otra exportación "
            + "se mostrarán una sola vez. Al terminar se indicará cuántos mensajes nuevos "
            + "se han añadido realmente."
        if existingContributionCount == 1 {
            return "Esta conversación ya está exportada desde otra copia de WhatsApp. "
                + "Si continúas, ambas exportaciones seguirán guardadas por separado y "
                + "Free My Chats creará una Vista unificada que reúne sus mensajes en "
                + "una sola cronología. \(messageImpact)"
        }
        return "Esta conversación ya tiene una Vista unificada creada a partir de "
            + "\(existingContributionCount) exportaciones. La nueva exportación se "
            + "guardará por separado y la Vista unificada se actualizará con los "
            + "mensajes de todas ellas. \(messageImpact)"
    }

    static func exportButtonTitle(existingContributionCount: Int) -> String {
        existingContributionCount == 1
            ? "Crear Vista unificada"
            : "Exportar y actualizar"
    }

    static func deletionTitle(contributionCount: Int) -> String {
        switch contributionCount {
        case 2:
            return "¿Borrar esta exportación y deshacer la Vista unificada?"
        case 3...:
            return "¿Borrar esta exportación de la Vista unificada?"
        default:
            return "¿Borrar esta exportación?"
        }
    }

    static func deletionMessage(
        chatName: String,
        versionTitle: String,
        impact: ConversationRemovalMessageImpact
    ) -> String {
        let origin = "Se borrará la exportación de “\(chatName)” procedente de “\(versionTitle)”. "
        let messageImpact = removalImpactMessage(impact)
        switch impact.contributionCount {
        case 2:
            return origin
                + "La otra exportación no se modificará y seguirá guardada por separado. "
                + "Como solo quedará una exportación, la Vista unificada desaparecerá y "
                + "el catálogo mostrará directamente la exportación restante. \(messageImpact)"
        case 3...:
            let remainingCount = impact.contributionCount - 1
            return origin
                + "Las \(remainingCount) exportaciones restantes no se modificarán y "
                + "seguirán guardadas por separado. La Vista unificada se reconstruirá "
                + "con sus mensajes. \(messageImpact)"
        default:
            return origin
                + "Como es la única exportación, la conversación desaparecerá del catálogo. "
                + messageImpact
        }
    }

    static func deletionButtonTitle(contributionCount: Int) -> String {
        contributionCount > 2 ? "Borrar y actualizar la vista" : "Borrar exportación"
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
            action = "Se ha creado la Vista unificada de “\(chatName)” a partir de 2 exportaciones. "
                + "Ambas siguen guardadas por separado."
        } else {
            action = "Se ha actualizado la Vista unificada de “\(chatName)” con "
                + "\(contributionCount) exportaciones. Todas siguen guardadas por separado."
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
            return "Esta exportación contiene \(source), pero no desaparecerá ninguno de "
                + "la conversación guardada porque todos están también en otras exportaciones. "
                + "La conversación seguirá teniendo \(result)."
        case 1:
            return "Esta exportación contiene \(source). Al borrarla, 1 mensaje exclusivo "
                + "dejará de aparecer en la conversación guardada, que quedará con \(result)."
        default:
            return "Esta exportación contiene \(source). Al borrarla, "
                + "\(impact.removedMessageCount.formatted()) mensajes exclusivos dejarán de "
                + "aparecer en la conversación guardada, que quedará con \(result)."
        }
    }

    private static func messageCount(_ count: Int) -> String {
        count == 1 ? "1 mensaje" : "\(count.formatted()) mensajes"
    }
}
