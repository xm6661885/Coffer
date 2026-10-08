import SwiftUI

struct MusicPlayerView: View {
    @State private var actions = ViewActions()
    @Environment(AudioPlayer.self) private var player
    @Environment(Navigator.self) private var navigator
    @Environment(ToastCenter.self) private var toast
    @Environment(\.verticalSizeClass) private var verticalSize
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var info: FileItem?
    @State private var share: ShareRequest?
    @State private var artworkOffset: CGFloat = 0
    @State private var controlPulse = 0
    @State private var scrubbingTime: Double?
    var body: some View {
        @Bindable var player = player
        Group {
            GeometryReader { geometry in
            if typeSize.isAccessibilitySize || (geometry.size.height < 700 && geometry.size.width < geometry.size.height) { ScrollView { playerLayout(size: geometry.size).frame(minHeight: geometry.size.height) } }
            else { playerLayout(size: geometry.size).frame(maxHeight: .infinity) }
        }.sheet(isPresented: Binding(get: { !navigator.playlistItems.isEmpty }, set: { if !$0 { navigator.playlistItems = [] } })) { AddToPlaylistSheet(refs: navigator.playlistItems) }.sheet(isPresented: $player.showQueue) { QueueView() }.sheet(item: $info) { InfoSheet(item: $0) }.sheet(item: $share) { ActivityView(urls: $0.urls) }
        }.managedTasks(actions)
    }
    private func playerLayout(size: CGSize) -> some View {
            VStack(spacing: 12) {
                HStack {
                    GlassIconButton(title: "Close player", symbol: "chevron.down") { player.isFullScreenPresented = false }
                    Spacer(); if let source = player.sourceTitle { VStack { Text("Playing from").font(.caption2).foregroundStyle(Color.inkSecondary); Text(source).font(.cofferCaption).fontWeight(.semibold).lineLimit(1) } }; Spacer()
                    Menu { playerMenu } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.buttonStyle(.glass).buttonBorderShape(.circle).accessibilityLabel("More")
                }
                if size.width > size.height {
                    HStack(spacing: 32) { cover(size: min(size.height - 90, size.width * 0.4)); controls }
                } else { Spacer(minLength: 4); cover(size: min(size.width - 48, 360)); Spacer(minLength: 8); controls }
                Spacer(minLength: 0)
            }.padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 12).frame(maxWidth: .infinity).background(Color.canvas)
    }
    private func cover(size: CGFloat) -> some View {
        ArtworkView(key: player.current.flatMap { player.metadata[$0.id]?.artworkKey }, size: max(100, size)).clipShape(.rect(cornerRadius: 22))
            .shadow(color: Color.ink.opacity(0.12), radius: 18, y: 8)
            .scaleEffect(reduceMotion || player.isPlaying ? 1 : 0.86).offset(x: reduceMotion ? 0 : artworkOffset).animation(.smooth(duration: 0.45, extraBounce: 0.25), value: player.isPlaying)
            .gesture(DragGesture().onChanged { if abs($0.translation.width) > abs($0.translation.height) { artworkOffset = $0.translation.width * 0.5 } }.onEnded { event in if event.translation.width < -80 { player.next() } else if event.translation.width > 80 { player.previous() }; withAnimation(.snappy) { artworkOffset = 0 } })
    }
    private var controls: some View {
        VStack(spacing: verticalSize == .compact ? 8 : 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) { Text(player.current.flatMap { player.metadata[$0.id]?.title } ?? player.current?.name ?? "").font(.cofferTitle).foregroundStyle(Color.ink).lineLimit(1); Text(player.current.flatMap { player.metadata[$0.id]?.artist } ?? "Unknown Artist").foregroundStyle(Color.inkSecondary).lineLimit(1) }.frame(maxWidth: .infinity, alignment: .leading)
                Menu { ForEach([0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3], id: \.self) { rate in Button { player.rate = Float(rate) } label: { if player.rate == Float(rate) { Label("\(rate.formatted())x", systemImage: "checkmark") } else { Text("\(rate.formatted())x") } } } } label: { Text("\(Double(player.rate).formatted())x").font(.cofferTimecode) }.buttonStyle(.glass).accessibilityLabel("Playback speed")
            }
            VStack(spacing: 0) { Scrubber(current: player.currentTime, duration: player.duration, buffered: player.bufferedTime, onSeek: player.seek, onPreviewTime: { scrubbingTime = $0 }); HStack { Text(Formatters.duration(scrubbingTime ?? player.currentTime)); Spacer(); Text("-" + Formatters.duration(max(0, player.duration - (scrubbingTime ?? player.currentTime)))) }.font(.cofferTimecode).foregroundStyle(Color.inkSecondary) }
            HStack(spacing: verticalSize == .compact ? 28 : 48) {
                HoldSeekButton(symbol: "backward.fill", title: "Previous track", action: player.previous, skip: { player.skip(by: -2) })
                Button { player.togglePlayPause(); controlPulse += 1 } label: { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: verticalSize == .compact ? 32 : 48)).contentTransition(.symbolEffect(.replace)).symbolEffect(.bounce, value: controlPulse).frame(width: verticalSize == .compact ? 48 : 64, height: verticalSize == .compact ? 48 : 64) }.accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                HoldSeekButton(symbol: "forward.fill", title: "Next track", action: player.next, skip: { player.skip(by: 2) })
            }.buttonStyle(.plain).foregroundStyle(Color.ink)
            HStack {
                Button { player.setShuffle(!player.shuffle) } label: { Image(systemName: "shuffle").frame(width: 44, height: 44) }.foregroundStyle(player.shuffle ? Color.pinkInk : Color.inkSecondary).accessibilityLabel("Shuffle").accessibilityValue(player.shuffle ? "On" : "Off").overlay(alignment: .bottom) { if player.shuffle { Circle().fill(Color.pink).frame(width: 4, height: 4) } }
                Spacer(); Button { player.cycleRepeat() } label: { Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat").frame(width: 44, height: 44) }.foregroundStyle(player.repeatMode == .off ? Color.inkSecondary : Color.pinkInk).accessibilityLabel("Repeat").accessibilityValue(player.repeatMode.rawValue).overlay(alignment: .bottom) { if player.repeatMode != .off { Circle().fill(Color.pink).frame(width: 4, height: 4) } }
                Spacer(); SleepTimerMenu().labelStyle(.iconOnly).frame(width: 44, height: 44).foregroundStyle(player.sleepTimer == nil ? Color.inkSecondary : Color.pinkInk).overlay(alignment: .bottom) { if case .minutes(let end) = player.sleepTimer { TimelineView(.periodic(from: .now, by: 1)) { context in Text(Formatters.duration(max(0, end.timeIntervalSince(context.date)))).font(.caption2).foregroundStyle(Color.pinkInk).offset(y: 9) } } else if player.sleepTimer != nil { Circle().fill(Color.pink).frame(width: 4, height: 4) } }
                Spacer(); Button { player.showQueue = true } label: { Image(systemName: "list.bullet").frame(width: 44, height: 44) }.accessibilityLabel("Queue")
                Spacer(); AirPlayButton().frame(width: 44, height: 44).accessibilityLabel("AirPlay")
            }.buttonStyle(.plain).foregroundStyle(Color.inkSecondary)
            if case .loading = player.state { ProgressBar(value: player.loadingProgress) }
            if case .failed(let error) = player.state { Text(error).font(.cofferCaption).foregroundStyle(Color.danger) }
        }
    }
    @ViewBuilder private var playerMenu: some View {
        if let current = player.current {
            FavouriteButton(item: current.fileItem)
            Button("Add to Playlist…", systemImage: "text.badge.plus") { navigator.playlistItems = [current] }
            Button("Show in Files", systemImage: "folder") { player.isFullScreenPresented = false; navigator.revealFile(current.fileItem) }
            Button("Get Info", systemImage: "info.circle") { info = current.fileItem }
            Button("Share", systemImage: "square.and.arrow.up") { actions.submit { do { share = ShareRequest(urls: try await SharePreparation.urls(for: [current.fileItem])) } catch { toast.show(error: error) } } }
        }
        Divider(); Button("Skip Back 15 Seconds") { player.skip(by: -15) }; Button("Skip Forward 30 Seconds") { player.skip(by: 30) }
        Divider(); Button("Stop Playback", role: .destructive) { player.stop() }
    }
}
private struct HoldSeekButton: View {
    let symbol: String; let title: String; let action: () -> Void; let skip: () -> Void
    @State private var holding = false
    @State private var suppressTap = false
    @State private var pulse = 0
    @State private var actions = ViewActions()
    var body: some View {
        Button { if !suppressTap { action(); pulse += 1 } } label: { Image(systemName: symbol).font(.system(size: 32)).symbolEffect(.bounce, value: pulse).frame(width: 52, height: 52) }
            .accessibilityLabel(title)
            .onLongPressGesture(minimumDuration: 0.4, pressing: { pressing in if !pressing && holding { holding = false; actions.submit { try? await Task.sleep(for: .milliseconds(150)); suppressTap = false } } }, perform: { holding = true; suppressTap = true })
            .task(id: holding) { if holding { while !Task.isCancelled { skip(); try? await Task.sleep(for: .milliseconds(250)) } } }
            .managedTasks(actions)
    }
}
