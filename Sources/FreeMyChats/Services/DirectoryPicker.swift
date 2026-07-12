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
}
