import AppKit
import Foundation

enum WorkspaceService {
    @MainActor
    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @MainActor
    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    @MainActor
    static func openFullDiskAccessSettings() {
        if let privacyURL = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ), NSWorkspace.shared.open(privacyURL) {
            return
        }

        NSWorkspace.shared.open(
            URL(fileURLWithPath: "/System/Applications/System Settings.app", isDirectory: true)
        )
    }

    @MainActor
    static func quitApplication() {
        NSApp.terminate(nil)
    }

    @MainActor
    static func openMap(latitude: Double, longitude: Double) {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "ll", value: "\(latitude),\(longitude)"),
            URLQueryItem(name: "q", value: "Ubicación del mensaje")
        ]
        if let url = components?.url {
            NSWorkspace.shared.open(url)
        }
    }
}
