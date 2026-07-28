import AppKit
import SwiftUI

struct LocalImageAvatar: View {
    let photoURL: URL?
    let name: String
    let size: CGFloat

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle().fill(.quaternary)
                    Text(String(name.prefix(1)).uppercased())
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: photoURL) {
            image = nil
            guard let photoURL else { return }
            let loadedImage = await ImageThumbnailCache.shared.thumbnail(for: photoURL)
            guard !Task.isCancelled else { return }
            image = loadedImage
        }
    }
}
