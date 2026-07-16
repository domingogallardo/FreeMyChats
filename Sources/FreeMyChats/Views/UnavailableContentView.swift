import SwiftUI

/// A Ventura-compatible empty/error state with the same role as
/// `ContentUnavailableView`, which was introduced in macOS 14.
struct UnavailableContentView<Actions: View>: View {
    let title: String
    let systemImage: String
    let description: String
    private let actions: Actions

    init(
        _ title: String,
        systemImage: String,
        description: String,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 42))
                .foregroundStyle(.secondary)

            VStack(spacing: 7) {
                Text(title)
                    .font(.title2.bold())
                Text(description)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }

            actions
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension UnavailableContentView where Actions == EmptyView {
    init(_ title: String, systemImage: String, description: String) {
        self.init(title, systemImage: systemImage, description: description) {
            EmptyView()
        }
    }
}
