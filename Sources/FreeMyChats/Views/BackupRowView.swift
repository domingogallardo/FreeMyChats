import SwiftUI

@available(macOS 14.0, *)
struct BackupRowView: View {
    let row: BackupInspectionRow
    let addToLibrary: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.id)
                        .font(.headline)
                        .textSelection(.enabled)
                    Text(row.creationDate.map(Self.dateFormatter.string) ?? "Fecha desconocida")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(
                    title: whatsAppTitle,
                    systemImage: whatsAppIcon,
                    color: whatsAppColor
                )
                StatusBadge(
                    title: encryptionTitle,
                    systemImage: encryptionIcon,
                    color: encryptionColor
                )
            }

            Text(row.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            if let detail = row.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Añadir a la biblioteca", action: addToLibrary)
                    .buttonStyle(.borderedProminent)
                    .disabled(!row.canCreateLibrary)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    private var whatsAppTitle: String {
        switch row.whatsAppState {
        case .present: return "WhatsApp: sí"
        case .absent: return "WhatsApp: no"
        case .unknown: return "WhatsApp: desconocido"
        }
    }

    private var whatsAppIcon: String {
        switch row.whatsAppState {
        case .present: return "checkmark.circle.fill"
        case .absent: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }

    private var whatsAppColor: Color {
        switch row.whatsAppState {
        case .present: return .green
        case .absent: return .red
        case .unknown: return .orange
        }
    }

    private var encryptionTitle: String {
        switch row.encryptionState {
        case true: return "Encriptada"
        case false: return "Sin encriptar"
        case nil: return "Cifrado desconocido"
        }
    }

    private var encryptionIcon: String {
        switch row.encryptionState {
        case true: return "lock.fill"
        case false: return "lock.open.fill"
        case nil: return "questionmark.diamond.fill"
        }
    }

    private var encryptionColor: Color {
        switch row.encryptionState {
        case true: return .orange
        case false: return .green
        case nil: return .secondary
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

@available(macOS 14.0, *)
private struct StatusBadge: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
    }
}
