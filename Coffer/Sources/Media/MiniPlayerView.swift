import SwiftUI
import AVKit

struct ArtworkView: View {
    var key: String?; var size: CGFloat
    @State private var image: UIImage?
    var body: some View {
        ZStack { Color.surfaceSunken; if let image { Image(uiImage: image).resizable().scaledToFill() } else { Image(systemName: "music.note").font(.system(size: size * 0.35)).foregroundStyle(Color.inkTertiary) } }.frame(width: size, height: size).clipped()
            .task(id: key) { image = nil; if let key { let url = MetadataLoader.artworkRoot.appending(path: key); let loaded = await Task.detached { UIImage(contentsOfFile: url.path) }.value; if !Task.isCancelled { image = loaded } } }
    }
}
struct MiniPlayerView: View {
    let namespace: Namespace.ID
    @Environment(AudioPlayer.self) private var player
    @Environment(FileProviderRegistry.self) private var registry
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    var body: some View {
        HStack(spacing: 10) {
            ArtworkView(key: player.current.flatMap { player.metadata[$0.id]?.artworkKey }, size: placement == .inline ? 24 : 32).clipShape(.rect(cornerRadius: 6)).matchedTransitionSource(id: "nowPlaying", in: namespace)
            VStack(alignment: .leading, spacing: 2) { Text(player.current.flatMap { player.metadata[$0.id]?.title } ?? player.current?.name ?? "").font(.cofferCallout).fontWeight(.semibold).lineLimit(1); if placement != .inline { Text(player.current.flatMap { player.metadata[$0.id]?.artist } ?? player.sourceTitle ?? player.current.map { registry.displayName(for: $0.location) } ?? "").font(.cofferCaption).foregroundStyle(Color.inkSecondary).lineLimit(1) } }.frame(maxWidth: .infinity, alignment: .leading)
            Button { player.togglePlayPause() } label: { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").contentTransition(.symbolEffect(.replace)).frame(width: 44, height: 44) }.accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            if placement != .inline { Button { player.next() } label: { Image(systemName: "forward.fill").frame(width: 44, height: 44) }.accessibilityLabel("Next track") }
        }.foregroundStyle(Color.ink).buttonStyle(.plain).padding(.horizontal, 12).contentShape(.rect).onTapGesture { player.isFullScreenPresented = true }
            .overlay(alignment: .bottomLeading) { GeometryReader { g in Rectangle().fill(Color.pink).frame(width: max(0, (g.size.width - 32) * player.currentTime / max(1, player.duration)), height: 2).padding(.leading, 16) }.frame(height: 2) }
            .contextMenu { Button("Show Queue", systemImage: "list.bullet") { player.showQueue = true; player.isFullScreenPresented = true }; SleepTimerMenu(); Button("Stop Playback", systemImage: "xmark.circle", role: .destructive) { player.stop() } }
    }
}
struct SleepTimerMenu: View {
    @Environment(AudioPlayer.self) private var player
    var body: some View { Menu { Button("Off") { player.setSleep(minutes: nil) }; ForEach([15, 30, 45, 60], id: \.self) { minutes in Button(minutes == 60 ? "1 hour" : "\(minutes) min") { player.setSleep(minutes: minutes) } }; Button("End of track") { player.sleepAtEnd() } } label: { Label("Sleep Timer", systemImage: "moon.zzz") } }
}
struct AirPlayButton: UIViewRepresentable {
    var video = false
    func makeUIView(context: Context) -> AVRoutePickerView { let view = AVRoutePickerView(); view.prioritizesVideoDevices = video; view.tintColor = video ? UIColor(named: "PinkInk") : UIColor(named: "Ink"); view.activeTintColor = UIColor(named: "PinkInk"); return view }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) { uiView.prioritizesVideoDevices = video; uiView.tintColor = video ? UIColor(named: "PinkInk") : UIColor(named: "Ink"); uiView.activeTintColor = UIColor(named: "PinkInk") }
}
