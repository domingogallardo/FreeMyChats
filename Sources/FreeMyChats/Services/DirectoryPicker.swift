import AppKit
import Foundation

enum DirectoryPicker {
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
        panel.message = "Selecciona la carpeta de la biblioteca o su carpeta Backup."
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
        panel.message = "Se crearán dentro las carpetas Backup y Exports."
        panel.prompt = "Crear biblioteca"
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        panel.isExtensionHidden = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}
