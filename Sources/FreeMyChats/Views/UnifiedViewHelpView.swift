import SwiftUI

struct UnifiedViewHelpView: View {
    var sourceTitles: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Vista unificada", systemImage: "square.stack.3d.up")
                .font(.headline)

            Text(UnifiedViewPresentation.explanation)
                .fixedSize(horizontal: false, vertical: true)

            if !sourceTitles.isEmpty {
                Divider()

                Text("Aportaciones incluidas")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(Array(sourceTitles.enumerated()), id: \.offset) { _, title in
                    Label(title, systemImage: "externaldrive")
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
        .frame(width: 370, alignment: .leading)
    }
}
