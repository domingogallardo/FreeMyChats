import AppKit
import Foundation
import UniformTypeIdentifiers

enum DirectoryPicker {
    private static let portableConversationType = UTType(
        exportedAs: "com.domingogallardo.freemychats.portable-conversation",
        conformingTo: .zip
    )
    private static var portableConversationOpenTypes: [UTType] {
        guard let filenameType = UTType(filenameExtension: "fmcchat"),
              filenameType != portableConversationType else {
            return [portableConversationType]
        }
        return [portableConversationType, filenameType]
    }

    @MainActor
    static func choose(startingAt currentPath: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Selecciona la carpeta que contiene las copias de iPhone"
        panel.prompt = "Seleccionar"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: currentPath)
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    static func chooseExistingLibrary(startingAt currentPath: String? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Abre una biblioteca de Free My Chats"
        panel.message = "Selecciona la carpeta que contiene library.json. También se admiten bibliotecas antiguas."
        panel.prompt = "Abrir biblioteca"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if let currentPath {
            panel.directoryURL = URL(fileURLWithPath: currentPath)
        }
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    static func chooseNewLibrary(suggestedName: String = "Mi biblioteca Free My Chats") -> URL? {
        let panel = NSSavePanel()
        panel.title = "Crea una biblioteca de Free My Chats"
        panel.message = "Se crearán dentro el manifiesto y las carpetas internas de la biblioteca."
        panel.prompt = "Crear biblioteca"
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        panel.isExtensionHidden = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    static func choosePortableConversationArchive(startingAt directoryURL: URL? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Importa un chat exportado"
        panel.message = "Selecciona un archivo .fmcchat creado por Free My Chats."
        panel.prompt = "Importar"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = portableConversationOpenTypes
        panel.directoryURL = directoryURL
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    static func choosePortableConversationDestination(
        suggestedName: String,
        startingAt directoryURL: URL? = nil
    ) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Exportar conversación"
        panel.message = "Se creará un archivo autocontenido que se puede importar en otra biblioteca."
        panel.prompt = "Exportar"
        panel.allowedContentTypes = [portableConversationType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = suggestedName.hasSuffix(".fmcchat")
            ? suggestedName
            : "\(suggestedName).fmcchat"
        panel.directoryURL = directoryURL
        return panel.runModal() == .OK ? panel.url : nil
    }
}
