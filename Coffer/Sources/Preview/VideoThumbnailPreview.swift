import SwiftUI

struct VideoThumbnailButton: View {
    let item: FileItem
    @Environment(Navigator.self) private var navigator
    var body: some View { Button("Preview Thumbnail", systemImage: "photo") { navigator.thumbnailItem = item } }
}
struct VideoThumbnailPreview: View {
    let item: FileItem
    @Environment(ThumbnailService.self) private var thumbnails
    @Environment(AppSettings.self) private var settings
    @Environment(Navigator.self) private var navigator
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var loading = true
    var body: some View {
        NavigationStack {
            Group {
                if let image { Image(uiImage: image).resizable().scaledToFit().padding(20) }
                else if loading { ProgressView("Loading thumbnail…") }
                else { ContentUnavailableView("No thumbnail available", systemImage: "film", description: Text(settings.loadVideoThumbnails ? "This video could not provide a preview frame. For remote videos, enable remote thumbnails in Settings." : "Enable Video Thumbnails in Settings.")) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.canvas).navigationTitle(item.name).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }; ToolbarItem(placement: .topBarTrailing) { FavouriteButton(item: item) } }
                .safeAreaInset(edge: .bottom) { Button("Play Video", systemImage: "play.fill") { navigator.thumbnailItem = nil; navigator.openVideo([MediaRef(item)]) }.buttonStyle(.glassProminent).padding() }
                .task(id: item.id) { image = await thumbnails.thumbnail(for: item, size: 960); loading = false }
        }
    }
}
