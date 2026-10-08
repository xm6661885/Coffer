import SwiftUI

enum ToolRoute: Hashable { case music, videos, pictures, textEditor }
struct ToolsView: View {
    @Environment(MusicLibrary.self) private var music
    @Environment(VideoLibrary.self) private var videos
    @Environment(PictureLibrary.self) private var pictures
    @Environment(PlaybackPositionStore.self) private var positions
    @Environment(AudioPlayer.self) private var player
    @Environment(RecentsStore.self) private var recents
    @Environment(Navigator.self) private var navigator
    @Environment(\.dynamicTypeSize) private var typeSize
    @Namespace private var namespace
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    HStack(spacing: 12) { card(.music, title: "Music", symbol: "music.note", detail: music.isScanning ? "Scanning…" : "\(music.entries.count) songs"); card(.videos, title: "Videos", symbol: "film", detail: videos.isScanning ? "Scanning…" : "\(videos.entries.count) videos") }
                    HStack(spacing: 12) { card(.pictures, title: "Pictures", symbol: "photo.on.rectangle", detail: pictures.isScanning ? "Scanning…" : "\(pictures.entries.count) pictures"); card(.textEditor, title: "Markdown", symbol: "square.and.pencil", detail: "\(recents.entries.filter { $0.item.kind.isTextual }.count) recent") }
                }
                if !positions.recentVideos.isEmpty { VStack(alignment: .leading, spacing: 12) { SectionHeader(title: "Continue Watching"); ScrollView(.horizontal) { HStack(spacing: 16) { ForEach(positions.recentVideos) { record in Button { navigator.openVideo([MediaRef(record.item)]) } label: { VideoCard(entry: MediaIndexEntry(item: record.item, metadata: TrackMetadata(title: record.item.name, duration: record.duration))).frame(width: 160) }.buttonStyle(.plain).contextMenu { FavouriteButton(item: record.item); VideoThumbnailButton(item: record.item); Button("Remove from Continue Watching") { positions.remove(record.id) }; Button("Show in Files") { navigator.revealFile(record.item) } } } }.scrollIndicators(.hidden) } } }
                if !positions.recentAudio.isEmpty { VStack(alignment: .leading, spacing: 12) { SectionHeader(title: "Continue Listening"); ScrollView(.horizontal) { HStack(spacing: 16) { ForEach(positions.recentAudio) { record in Button { player.play([MediaRef(record.item)], sourceTitle: "Continue Listening") } label: { VStack(alignment: .leading) { ArtworkView(key: player.metadata[record.id]?.artworkKey ?? music.entries.first { $0.id == record.id }?.metadata.artworkKey, size: 120).clipShape(.rect(cornerRadius: 14)).overlay(alignment: .bottom) { ProgressBar(value: record.time / max(1, record.duration), height: 3) }; Text(record.item.name).font(.cofferCaption).lineLimit(2) }.frame(width: 120) }.buttonStyle(.plain).contextMenu { FavouriteButton(item: record.item); Button("Remove from Continue Listening") { positions.remove(record.id) }; Button("Show in Files") { navigator.revealFile(record.item) } } } }.scrollIndicators(.hidden) } } }
                PlaylistSection()
            }.padding(20)
        }.background(Color.canvas).navigationTitle("Tools").navigationDestination(for: ToolRoute.self) { route in Group { switch route { case .music: MusicLibraryView(); case .videos: VideoLibraryView(); case .pictures: PictureLibraryView(); case .textEditor: TextEditorHome() } }.navigationTransition(.zoom(sourceID: route, in: namespace)) }.toolbar { NavigationLink { SettingsView() } label: { Label("Settings", systemImage: "gear") } }
    }
    private func card(_ route: ToolRoute, title: String, symbol: String, detail: String, horizontal: Bool = false) -> some View {
        NavigationLink(value: route) { Group { if horizontal { HStack(spacing: 12) { Image(systemName: symbol).font(.system(size: 28)).foregroundStyle(Color.pinkInk); Text(title).font(.cofferHeadline).foregroundStyle(Color.ink); Spacer(); Text(detail).font(.cofferCaption).foregroundStyle(Color.inkSecondary); Image(systemName: "chevron.right").foregroundStyle(Color.inkTertiary) } } else { VStack(alignment: .leading, spacing: 8) { Image(systemName: symbol).font(.system(size: 28)).foregroundStyle(Color.pinkInk); Spacer(); Text(title).font(.cofferHeadline).foregroundStyle(Color.ink); Text(detail).font(.cofferCaption).foregroundStyle(Color.inkSecondary) }.frame(maxWidth: .infinity, alignment: .leading) } }.symbolRenderingMode(.hierarchical).padding(18).frame(height: typeSize.isAccessibilitySize ? nil : (horizontal ? 72 : 132)).frame(minHeight: horizontal ? 72 : 132).background(Color.surface, in: .rect(cornerRadius: 22)).overlay { RoundedRectangle(cornerRadius: 22).stroke(Color.hairline, lineWidth: 0.5) } }.buttonStyle(PressableCardStyle()).matchedTransitionSource(id: route, in: namespace)
    }
}
struct PressableCardStyle: ButtonStyle { @Environment(\.accessibilityReduceMotion) private var reduceMotion; func makeBody(configuration: Configuration) -> some View { configuration.label.scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1).animation(.snappy, value: configuration.isPressed) } }
