import SwiftUI

struct OperationProgressView: View {
    let operation: AppOperation

    var body: some View {
        VStack(spacing: 12) {
            if let fraction = operation.fractionCompleted {
                ProgressView(value: fraction)
                    .frame(maxWidth: 320)
            } else {
                ProgressView()
                    .controlSize(.large)
            }
            Text(operation.title)
                .font(.headline)
            if let detail = operation.detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }
        }
        .padding(28)
    }
}
