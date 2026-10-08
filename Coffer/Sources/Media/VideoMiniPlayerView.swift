import SwiftUI

struct VideoMiniPlayerView: View {
    let model: VideoPlayerModel
    @Environment(ThumbnailService.self) private var thumbnails
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @State private var image: UIImage?
    var body: some View {
        HStack(spacing: 10) {
            Button { model.presentVideo() } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Color.surfaceSunken
                        if let image { Image(uiImage: image).resizable().scaledToFill() }
                        else { Image(systemName: "film").foregroundStyle(Color.inkTertiary) }
                    }.frame(width: placement == .inline ? 24 : 32, height: placement == .inline ? 24 : 32).clipped().clipShape(.rect(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 2) {
                        MarqueeText(text: model.current.name, style: .callout)
                        if placement != .inline { Text("Video Audio").font(.cofferCaption).foregroundStyle(Color.inkSecondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(.rect)
            }.accessibilityLabel("Back to video: " + model.current.name)
            Button { model.togglePlay() } label: {
                Group { if model.state == .loading || model.state == .buffering { ProgressView() } else { Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").contentTransition(.symbolEffect(.replace)) } }
                    .frame(width: 44, height: 44)
            }.accessibilityLabel(model.isPlaying ? "Pause video audio" : "Play video audio")
            if placement != .inline && model.index + 1 < model.playlist.count {
                Button { model.next() } label: { Image(systemName: "forward.fill").frame(width: 44, height: 44) }.accessibilityLabel("Next video")
            }
        }.foregroundStyle(Color.ink).buttonStyle(.plain).padding(.horizontal, 12).contentShape(.rect)
            .overlay(alignment: .bottomLeading) {
                GeometryReader { geometry in Rectangle().fill(Color.pink).frame(width: max(0, (geometry.size.width - 32) * min(1, model.currentTime / max(1, model.duration))), height: 2).padding(.leading, 16) }.frame(height: 2)
            }
            .contextMenu {
                Button("Back to Video", systemImage: "play.rectangle") { model.presentVideo() }
                Button("Stop Playback", systemImage: "xmark.circle", role: .destructive) { model.close() }
            }
            .task(id: model.current.id) { image = nil; let result = await thumbnails.thumbnail(for: model.current.fileItem); guard !Task.isCancelled else { return }; image = result }
    }
}
