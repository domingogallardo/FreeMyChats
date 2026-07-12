import Foundation
import SwiftWABackupAPI

@MainActor
@available(macOS 14.0, *)
final class BackupInspectionStore: ObservableObject {
    static let defaultPath = NSString(
        string: "~/Library/Application Support/MobileSync/Backup/"
    ).expandingTildeInPath

    @Published var rootPath = defaultPath
    @Published private(set) var rows: [BackupInspectionRow] = []
    @Published private(set) var isInspecting = false
    @Published private(set) var errorMessage: String?

    func inspect() {
        let path = rootPath
        isInspecting = true
        errorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result {
                try IPhoneBackupManager(iPhoneBackupsPath: path)
                    .inspectIPhoneBackups()
                    .map(BackupInspectionRow.init)
                    .sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
            }

            DispatchQueue.main.async {
                guard let self else { return }
                self.isInspecting = false
                switch result {
                case .success(let rows):
                    self.rows = rows
                case .failure(let error):
                    self.rows = []
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
