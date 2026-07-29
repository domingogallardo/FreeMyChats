import AppKit
import SwiftUI

struct ConversationMediaGalleryView: View {
    @Environment(\.dismiss) private var dismiss

    let conversationName: String
    let items: [ConversationMediaItem]
    let navigateToMessage: (Int) -> Void

    @State private var filter: GalleryMediaFilter = .all
    @State private var selectedItemID: Int?

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 240), spacing: 14)
    ]

    var body: some View {
        ZStack {
            gallery
                .allowsHitTesting(selectedItemID == nil)
                .accessibilityHidden(selectedItemID != nil)

            if let selectedItem {
                ConversationMediaViewer(
                    item: selectedItem,
                    position: selectedPosition,
                    totalCount: filteredItems.count,
                    canSelectPrevious: canSelectPrevious,
                    canSelectNext: canSelectNext,
                    selectPrevious: selectPrevious,
                    selectNext: selectNext,
                    close: closeViewer,
                    navigateToMessage: navigateToMessage
                )
                .id(selectedItem.id)
                .transition(.opacity)
            }
        }
        .frame(
            minWidth: 820,
            idealWidth: 1_040,
            minHeight: 620,
            idealHeight: 760
        )
        .animation(.easeInOut(duration: 0.18), value: selectedItemID)
        .onMoveCommand { direction in
            guard selectedItemID != nil else { return }
            switch direction {
            case .left:
                selectPrevious()
            case .right:
                selectNext()
            default:
                break
            }
        }
        .onExitCommand {
            if selectedItemID == nil {
                dismiss()
            } else {
                closeViewer()
            }
        }
    }

    private var gallery: some View {
        VStack(spacing: 0) {
            galleryHeader
            Divider()

            if filteredItems.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(filteredItems) { item in
                            GalleryMediaCell(item: item) {
                                selectedItemID = item.id
                            }
                        }
                    }
                    .padding(18)
                }
            }
        }
    }

    private var galleryHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.title2)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text("Fotos y vídeos")
                    .font(.title2.bold())
                Text("\(conversationName) · \(mediaSummary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 16)

            if !items.isEmpty {
                Picker("Tipo de contenido", selection: $filter) {
                    ForEach(GalleryMediaFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 270)
                .accessibilityLabel("Filtrar fotos y vídeos")
            }

            Button {
                dismiss()
            } label: {
                Label("Cerrar galería", systemImage: "xmark")
            }
            .labelStyle(.iconOnly)
            .help("Cerrar galería")
            .accessibilityLabel("Cerrar galería")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var emptyState: some View {
        UnavailableContentView(
            emptyStateTitle,
            systemImage: filter == .video ? "video.slash" : "photo.on.rectangle.angled",
            description: emptyStateDescription
        )
    }

    private var emptyStateTitle: String {
        switch filter {
        case .all: return "No hay fotos ni vídeos"
        case .image: return "No hay fotos"
        case .video: return "No hay vídeos"
        }
    }

    private var emptyStateDescription: String {
        switch filter {
        case .all:
            return "Los archivos visuales de esta conversación aparecerán aquí."
        case .image:
            return "Esta conversación no contiene fotos."
        case .video:
            return "Esta conversación no contiene vídeos."
        }
    }

    private var filteredItems: [ConversationMediaItem] {
        switch filter {
        case .all:
            return items
        case .image:
            return items.filter { $0.kind == .image }
        case .video:
            return items.filter { $0.kind == .video }
        }
    }

    private var selectedItem: ConversationMediaItem? {
        guard let selectedItemID else { return nil }
        return filteredItems.first { $0.id == selectedItemID }
    }

    private var selectedIndex: Int? {
        guard let selectedItemID else { return nil }
        return filteredItems.firstIndex { $0.id == selectedItemID }
    }

    private var selectedPosition: Int {
        selectedIndex.map { $0 + 1 } ?? 0
    }

    private var canSelectPrevious: Bool {
        guard let selectedIndex else { return false }
        return selectedIndex > filteredItems.startIndex
    }

    private var canSelectNext: Bool {
        guard let selectedIndex else { return false }
        return selectedIndex < filteredItems.index(before: filteredItems.endIndex)
    }

    private var mediaSummary: String {
        let imageCount = items.filter { $0.kind == .image }.count
        let videoCount = items.count - imageCount
        return [
            countLabel(imageCount, singular: "foto", plural: "fotos"),
            countLabel(videoCount, singular: "vídeo", plural: "vídeos")
        ]
        .joined(separator: " · ")
    }

    private func countLabel(_ count: Int, singular: String, plural: String) -> String {
        "\(count.formatted()) \(count == 1 ? singular : plural)"
    }

    private func selectPrevious() {
        guard canSelectPrevious, let selectedIndex else { return }
        selectedItemID = filteredItems[filteredItems.index(before: selectedIndex)].id
    }

    private func selectNext() {
        guard canSelectNext, let selectedIndex else { return }
        selectedItemID = filteredItems[filteredItems.index(after: selectedIndex)].id
    }

    private func closeViewer() {
        selectedItemID = nil
    }
}

private enum GalleryMediaFilter: String, CaseIterable, Identifiable {
    case all
    case image
    case video

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Todo"
        case .image: return "Fotos"
        case .video: return "Vídeos"
        }
    }
}

private struct GalleryMediaCell: View {
    let item: ConversationMediaItem
    let select: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        GalleryMediaThumbnail(item: item)
                    }
                    .clipped()

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.caption ?? item.filename)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    HStack(spacing: 6) {
                        Image(systemName: item.kind == .video ? "video.fill" : "photo.fill")
                        Text(Self.dateFormatter.string(from: item.date))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(10)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.secondary.opacity(isHovering ? 0.13 : 0.08),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isHovering ? Color.accentColor.opacity(0.7) : Color.secondary.opacity(0.16),
                        lineWidth: isHovering ? 1.5 : 1
                    )
            }
            .shadow(
                color: .black.opacity(isHovering ? 0.14 : 0.06),
                radius: isHovering ? 7 : 3,
                y: 2
            )
            .scaleEffect(isHovering ? 1.012 : 1)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .help("Ampliar \(item.filename)")
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Abre el archivo en el visor")
    }

    private var accessibilityLabel: String {
        let kind = item.kind == .video ? "Vídeo" : "Foto"
        let title = item.caption ?? item.filename
        return "\(kind): \(title), \(Self.dateFormatter.string(from: item.date))"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct GalleryMediaThumbnail: View {
    let item: ConversationMediaItem

    @State private var image: NSImage?
    @State private var didFinishLoading = false

    var body: some View {
        ZStack {
            Color.secondary.opacity(0.08)

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else if didFinishLoading {
                Image(systemName: item.kind == .video ? "video.slash" : "photo.badge.exclamationmark")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
            }

            if item.kind == .video, image != nil {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 42))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.55))
                    .shadow(radius: 4)
            }
        }
        .clipped()
        .task(id: item.id) {
            image = nil
            didFinishLoading = false

            let loadedImage: NSImage?
            switch item.kind {
            case .image:
                loadedImage = await ImageThumbnailCache.shared.thumbnail(for: item.url)
            case .video:
                loadedImage = await VideoThumbnailCache.shared.thumbnail(for: item.url)
            }

            guard !Task.isCancelled else { return }
            image = loadedImage
            didFinishLoading = true
        }
    }
}

private struct ConversationMediaViewer: View {
    let item: ConversationMediaItem
    let position: Int
    let totalCount: Int
    let canSelectPrevious: Bool
    let canSelectNext: Bool
    let selectPrevious: () -> Void
    let selectNext: () -> Void
    let close: () -> Void
    let navigateToMessage: (Int) -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.94)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    viewerHeader

                    Group {
                        switch item.kind {
                        case .image:
                            GalleryImagePreview(url: item.url)
                        case .video:
                            VideoPlayerView(
                                url: item.url,
                                filename: item.filename,
                                expectedDuration: item.expectedDuration,
                                isLooping: MediaAttachmentPresentation.shouldLoopVideo(
                                    messageType: item.messageType
                                ),
                                displaySize: videoSize(in: geometry.size)
                            )
                        }
                    }
                    .id(item.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    viewerFooter
                }
                .padding(18)
            }
        }
        .foregroundStyle(.white)
        .accessibilityAddTraits(.isModal)
    }

    private var viewerHeader: some View {
        HStack(spacing: 12) {
            viewerButton(
                title: "Cerrar visor",
                systemImage: "xmark",
                action: close
            )

            VStack(spacing: 2) {
                Text(item.caption ?? item.filename)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(Self.dateFormatter.string(from: item.date))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity)

            viewerButton(
                title: "Abrir en otra aplicación",
                systemImage: "arrow.up.forward.app",
                action: { WorkspaceService.open(item.url) }
            )
        }
    }

    private var viewerFooter: some View {
        HStack(spacing: 16) {
            Button(action: selectPrevious) {
                Label("Anterior", systemImage: "chevron.left")
            }
            .disabled(!canSelectPrevious)

            Spacer()

            VStack(spacing: 5) {
                Text("\(position.formatted()) de \(totalCount.formatted())")
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()

                Button {
                    navigateToMessage(item.id)
                } label: {
                    Label(senderLabel, systemImage: "arrowshape.turn.up.left")
                        .font(.caption)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.11), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.78))
                .help("Ir a este mensaje en la conversación")
                .accessibilityLabel("\(senderLabel). Ir al mensaje en la conversación")
            }

            Spacer()

            Button(action: selectNext) {
                Label("Siguiente", systemImage: "chevron.right")
                    .labelStyle(.titleAndIcon)
            }
            .disabled(!canSelectNext)
        }
        .buttonStyle(.bordered)
        .tint(.white)
        .zIndex(1)
    }

    private var senderLabel: String {
        if item.isFromMe {
            return "Enviado por ti"
        }
        if let authorName = item.authorName, !authorName.isEmpty {
            return "Enviado por \(authorName)"
        }
        return item.kind == .video ? "Vídeo recibido" : "Foto recibida"
    }

    private func viewerButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.12), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }

    private func videoSize(in availableSize: CGSize) -> CGSize {
        let maximumWidth = max(360, availableSize.width - 96)
        let maximumHeight = max(220, availableSize.height - 210)
        let width = min(maximumWidth, maximumHeight * (16 / 9), 1_200)
        return CGSize(width: width, height: width * (9 / 16))
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct GalleryImagePreview: View {
    let url: URL

    @State private var image: NSImage?
    @State private var didFinishLoading = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else if didFinishLoading {
                VStack(spacing: 10) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 42))
                    Text("No se ha podido mostrar esta imagen.")
                }
                .foregroundStyle(.white.opacity(0.7))
            } else {
                ProgressView("Cargando imagen…")
                    .tint(.white)
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) {
            image = nil
            didFinishLoading = false
            let loadedImage = await ImageThumbnailCache.shared.preview(for: url)
            guard !Task.isCancelled else { return }
            image = loadedImage
            didFinishLoading = true
        }
    }
}
