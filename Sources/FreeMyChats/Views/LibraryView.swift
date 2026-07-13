import SwiftUI

@available(macOS 14.0, *)
struct LibraryView: View {
    @ObservedObject var store: FreeMyChatsStore

    var body: some View {
        NavigationSplitView {
            ChatSidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 470)
        } detail: {
            ConversationView(store: store)
                .navigationTitle("")
        }
        .sheet(isPresented: $store.isShowingBackupImporter) {
            BackupDiscoveryView(store: store)
                .frame(minWidth: 780, minHeight: 580)
        }
        .overlay {
            if let operation = blockingOperation {
                OperationProgressView(operation: operation)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.regularMaterial)
            }
        }
    }

    private var blockingOperation: AppOperation? {
        guard let operation = store.operation else { return nil }
        switch operation.kind {
        case .openingLibrary, .deletingBackup, .loadingChats:
            return operation
        case .discovering, .creatingLibrary, .addingBackup, .exportingChat:
            return nil
        }
    }
}
