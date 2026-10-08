import SwiftUI
struct PlaylistDetailView: View {
    let id: UUID
    @Environment(PlaylistStore.self) private var store
    @Environment(AudioPlayer.self) private var player
    @Environment(Navigator.self) private var navigator
    @State private var adding = false
    @State private var renaming = false
    @State private var unavailable: Set<String> = []
    @State private var deleting: IndexSet?
    private var playlist: Playlist? { store.playlists.first { $0.id == id } }
    var body: some View {
        Group { if let playlist { List {
            Section { VStack(spacing: 16) { PlaylistArtwork(playlist: playlist, size: 160); Button(playlist.name) { renaming = true }.font(.cofferTitle).foregroundStyle(Color.ink); Text(playlistSummary(playlist)).font(.cofferCaption).foregroundStyle(Color.inkSecondary); PlayButtons(refs: playlist.items, title: playlist.name, video: playlist.kind == .video) }.frame(maxWidth: .infinity).padding(.vertical, 20) }.listRowBackground(Color.clear)
            Section { ForEach(Array(playlist.items.enumerated()), id: \.offset) { at, ref in Button { if playlist.kind == .music { player.play(playlist.items, startAt: at, sourceTitle: playlist.name) } else { navigator.openVideo(playlist.items, index: at) } } label: { PlaylistEntryRow(ref: ref, kind: playlist.kind, unavailable: unavailable.contains(ref.id)) }.buttonStyle(.plain).contextMenu { FavouriteButton(item: ref.fileItem); if playlist.kind == .video { VideoThumbnailButton(item: ref.fileItem) }; Button("Show in Files", systemImage: "folder") { navigator.revealFile(ref.fileItem) } }.opacity(unavailable.contains(ref.id) ? 0.5 : 1) }.onMove { store.move(from: $0, to: $1, in: id) }.onDelete { deleting = $0 } }.listRowBackground(Color.canvas)
        }.paperList().navigationTitle(playlist.name).navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .topBarTrailing) { EditButton() }; ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Label("Add", systemImage: "plus") } } }.sheet(isPresented: $adding) { MediaPicker(kind: playlist.kind == .music ? .audio : .video) { store.add($0.map(MediaRef.init), to: id) } }.sheet(isPresented: $renaming) { PlaylistNameSheet(playlist: playlist) { name, _ in store.rename(id, to: name) } }.task(id: playlist.items) { var missing: Set<String> = []; for ref in playlist.items { do { _ = try await AppServices.shared.registry.provider(for: ref.location).stat(ref.path) } catch { missing.insert(ref.id) } }; unavailable = missing }
        } else { EmptyState(title: "Playlist Removed", symbol: "music.note.list", description: "This playlist is no longer available.").background(Color.canvas) } }
            .confirmationDialog("Remove selected items from this playlist?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) { Button("Remove", role: .destructive) { if let deleting { store.remove(at: deleting, from: id) }; deleting = nil }; Button("Cancel", role: .cancel) { deleting = nil } }
    }
}
struct PlaylistArtwork: View {
    let playlist: Playlist; let size: CGFloat
    var body: some View { ZStack { Color.surfaceSunken; if playlist.items.count >= 4 { VStack(spacing: 1) { ForEach(0..<2) { row in HStack(spacing: 1) { ForEach(0..<2) { col in let ref = playlist.items[row * 2 + col]; if playlist.kind == .music { ArtworkView(key: AppServices.shared.player.metadata[ref.id]?.artworkKey ?? AppServices.shared.musicLibrary.entries.first { $0.id == ref.id }?.metadata.artworkKey, size: size / 2) } else { PlaylistVideoThumbnail(item: playlistItem(ref)).frame(width: size / 2, height: size / 2) } } } } } } else { Image(systemName: playlist.kind == .music ? "music.note.list" : "play.rectangle.on.rectangle").font(.system(size: size * 0.35)).foregroundStyle(Color.inkTertiary) } }.frame(width: size, height: size).clipShape(.rect(cornerRadius: size > 100 ? 22 : 8)) }
}
@MainActor func playlistSummary(_ playlist: Playlist) -> String { let duration = playlist.items.reduce(0.0) { sum, ref in sum + (AppServices.shared.player.metadata[ref.id]?.duration ?? AppServices.shared.musicLibrary.entries.first { $0.id == ref.id }?.metadata.duration ?? AppServices.shared.videoLibrary.entries.first { $0.id == ref.id }?.metadata.duration ?? 0) }; return "\(playlist.items.count) \(playlist.kind == .music ? "songs" : "videos")" + (duration > 0 ? " · \(Int(duration / 3600)) hr \(Int(duration.truncatingRemainder(dividingBy: 3600) / 60)) min" : "") }

private struct PlaylistEntryRow: View {
    let ref: MediaRef; let kind: Playlist.Kind; let unavailable: Bool
    @Environment(AudioPlayer.self) private var player
    @Environment(MusicLibrary.self) private var music
    @Environment(VideoLibrary.self) private var videos
    @Environment(PlaybackPositionStore.self) private var positions
    private var metadata: TrackMetadata? { player.metadata[ref.id] ?? (kind == .music ? music.entries.first { $0.id == ref.id }?.metadata : videos.entries.first { $0.id == ref.id }?.metadata) }
    var body: some View {
        HStack(spacing: 12) {
            if kind == .music { ArtworkView(key: metadata?.artworkKey, size: 40).clipShape(.rect(cornerRadius: 6)) }
            else { PlaylistVideoThumbnail(item: playlistItem(ref)).frame(width: 64, height: 36).clipShape(.rect(cornerRadius: 6)) }
            VStack(alignment: .leading, spacing: 4) {
                MarqueeText(text: kind == .music ? metadata?.title ?? PathUtil.baseName(ref.name) : ref.name)
                Text(unavailable ? "Unavailable" : kind == .music ? metadata?.artist ?? "Unknown Artist" : metadata?.duration.map(Formatters.duration) ?? ref.path).font(.cofferCaption).foregroundStyle(Color.inkSecondary).lineLimit(1)
                if kind == .video, let record = positions.records[ref.id] { ProgressBar(value: record.time / max(1, record.duration), height: 3) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if kind == .music, let duration = metadata?.duration { Text(Formatters.duration(duration)).font(.cofferTimecode).foregroundStyle(Color.inkSecondary) }
        }
    }
}
private struct PlaylistVideoThumbnail: View {
    let item: FileItem
    @Environment(ThumbnailService.self) private var thumbnails
    @State private var image: UIImage?
    var body: some View {
        ZStack { Color.surfaceSunken; if let image { Image(uiImage: image).resizable().scaledToFill() } else { Image(systemName: "film").foregroundStyle(Color.inkTertiary) } }.clipped().task(id: item.id) { let result = await thumbnails.thumbnail(for: item); if !Task.isCancelled { image = result } }
    }
}

@MainActor private func playlistItem(_ ref: MediaRef) -> FileItem {
    AppServices.shared.videoLibrary.entries.first { $0.id == ref.id }?.item ?? AppServices.shared.positions.records[ref.id]?.item ?? ref.fileItem
}
