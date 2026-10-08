import SwiftUI
import UniformTypeIdentifiers

struct VideoPlayerView: View {
    @State private var actions = ViewActions()
    let model: VideoPlayerModel
    @State private var importSubtitle = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var info = false
    @State private var scrubbingTime: Double?
    var body: some View {
        Group {
            GeometryReader { geometry in
            ZStack {
                VideoSurface(model: model).ignoresSafeArea()
                VideoGestureLayer(model: model).ignoresSafeArea()
                if !model.subtitle.isEmpty { Text(model.subtitle).font(.system(size: max(16, geometry.size.height * 0.05), weight: .semibold)).foregroundStyle(.white).multilineTextAlignment(.center).frame(maxWidth: geometry.size.width * 0.85).position(x: geometry.size.width / 2, y: geometry.size.height * (model.controlsVisible ? 0.7 : 0.86)).allowsHitTesting(false).animation(.easeInOut(duration: reduceMotion ? 0.1 : 0.28), value: model.controlsVisible) }
                controls(size: geometry.size)
                    .compositingGroup().opacity(model.controlsVisible && !model.isLocked ? 1 : 0)
                    .allowsHitTesting(model.controlsVisible && !model.isLocked && !model.isClosed)
                    .accessibilityHidden(!model.controlsVisible || model.isLocked)
                    .animation(.easeInOut(duration: reduceMotion ? 0.1 : 0.28), value: model.controlsVisible && !model.isLocked)
                HStack { glassButton(title: model.isLocked ? "Unlock" : "Lock", symbol: model.isLocked ? "lock.fill" : "lock.open", size: 44) { model.toggleLock() }; Spacer() }.padding(.horizontal, 12).compositingGroup().opacity(model.controlsVisible ? 1 : 0).allowsHitTesting(model.controlsVisible && !model.isClosed).accessibilityHidden(!model.controlsVisible).animation(.easeInOut(duration: reduceMotion ? 0.1 : 0.28), value: model.controlsVisible)
                if let hud = model.gestureHUD { VideoGestureHUD(hud: hud).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: hudAlignment(hud.style)).padding(hud.style == .speed ? 64 : 32).allowsHitTesting(false).transition(.scale(scale: 0.9).combined(with: .opacity)) }
                if let message = failure { VStack { Text(message).foregroundStyle(Color.white); Button("Try Again") { model.retry() }.buttonStyle(.glass); Button("Close") { model.close() }.buttonStyle(.glass) }.padding(20).glassEffect(.regular, in: .rect(cornerRadius: 18)) }
                if let resumed = model.resumeFrom { VStack { Spacer(); HStack { Button { model.resumeFrom = nil; model.seek(to: 0) } label: { Text("Resumed from \(Formatters.duration(resumed)) · Start Over").font(.cofferCaption).padding(12) }.buttonStyle(.glass); Spacer() }.padding(20) } }

            }.background(Color.black).tint(Color.pinkInk)
        }.persistentSystemOverlays(.hidden).statusBarHidden(true).preferredColorScheme(.dark)
            .task { model.open() }
            .onAppear { model.presentationAppeared() }
            .sheet(isPresented: $info) { InfoSheet(item: model.current.fileItem) }
            .fileImporter(isPresented: $importSubtitle, allowedContentTypes: [.item]) { result in
                switch result {
                case .success(let url): actions.submit {
                    do { guard ["srt", "ass", "ssa", "vtt"].contains(url.pathExtension.lowercased()) else { throw FileProviderError.other("Choose an SRT, VTT, ASS or SSA subtitle.") }
                        let copy = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + "." + url.pathExtension)
                        try await Task.detached { let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }; try FileManager.default.copyItem(at: url, to: copy) }.value
                        model.externalSubtitleURLs.append(copy); await model.addSubtitle(copy)
                    } catch { model.toast.show(error: error) }
                }
                case .failure(let error): model.toast.show(error: error)
                }
            }
        }.overlay(alignment: .top) {
            if let message = model.toast.current {
                ToastView(toast: message, dismiss: model.toast.dismiss).padding(.top, 64)
                    .allowsHitTesting(message.action != nil).transition(.move(edge: .top).combined(with: .opacity))
            }
        }.managedTasks(actions)
    }
    private var failure: String? { if case .failed(let message) = model.state { return message }; return nil }
    private func controls(size: CGSize) -> some View {
        VStack {
            HStack(spacing: 12) {
                glassButton(title: model.settings.backgroundVideoAudio ? "Continue as audio" : "Close video", symbol: "xmark", size: 44) { model.exitPlayer() }
                VStack(alignment: .leading, spacing: 4) { MarqueeText(text: model.current.name, style: .headline, color: .white); if let resolution = model.resolution { Text(resolution).font(.cofferCaption).foregroundStyle(Color.white.opacity(0.7)) } }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 6).glassEffect(.regular, in: .rect(cornerRadius: 12))
                GlassEffectContainer { HStack(spacing: 10) {
                    Button { model.requestPictureInPicture() } label: {
                        Group {
                            if model.pictureInPicturePending { ProgressView().tint(Color.pinkInk).accessibilityHidden(true) }
                            else { Image(systemName: "pip.enter").font(.system(size: 17, weight: .semibold)) }
                        }.frame(width: 44, height: 44).contentShape(.circle)
                    }.buttonStyle(.plain).foregroundStyle(Color.pinkInk).glassEffect(.regular.interactive(), in: .circle)
                        .accessibilityLabel(model.pictureInPicturePending ? "Cancel Picture in Picture" : "Picture in Picture")
                    if model.backend is AVPlayerBackend { AirPlayButton(video: true).frame(width: 44, height: 44).glassEffect(.regular, in: .circle) }
                    Menu { options } label: { Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44) }.buttonStyle(.plain).foregroundStyle(Color.pinkInk).glassEffect(.regular.interactive(), in: .circle).accessibilityLabel("Video options").simultaneousGesture(TapGesture().onEnded { model.holdControls() })
                } }
            }
            Spacer()
            HStack(spacing: 24) {
                glassButton(title: "Skip back \(model.settings.skipInterval) seconds", symbol: "gobackward.\(model.settings.skipInterval)", size: 52) { model.skip(by: -Double(model.settings.skipInterval)) }
                Button { model.togglePlay() } label: { Group { if model.isPlaying && (model.state == .buffering || model.state == .loading) { ProgressView().tint(Color.pinkInk).accessibilityHidden(true) } else { Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 30)).contentTransition(.symbolEffect(.replace)) } }.foregroundStyle(Color.pinkInk).frame(width: 72, height: 72).contentShape(.circle) }.buttonStyle(.plain).glassEffect(.regular.interactive(), in: .circle).accessibilityLabel(model.isPlaying ? "Pause" : "Play")
                glassButton(title: "Skip forward \(model.settings.skipInterval) seconds", symbol: "goforward.\(model.settings.skipInterval)", size: 52) { model.skip(by: Double(model.settings.skipInterval)) }
            }
            Spacer()
            VStack(spacing: 4) {
                HStack { Text(Formatters.duration(scrubbingTime ?? model.currentTime)); Spacer(); Button(model.remainingTime ? "-" + Formatters.duration(max(0, model.duration - (scrubbingTime ?? model.currentTime))) : Formatters.duration(model.duration)) { model.remainingTime.toggle() }.foregroundStyle(Color.pinkInk).frame(minHeight: 44) }.font(.cofferTimecode)
                Scrubber(current: model.currentTime, duration: model.duration, buffered: (model.backend as? AVPlayerBackend)?.bufferedTime, onScrubbingChanged: { active in active ? model.holdControls() : model.resetAutoHide() }, onSeek: model.seek, style: .video, onPreviewTime: { scrubbingTime = $0 }, showsTimePreview: !model.settings.loadVideoThumbnails)
                    .overlay(alignment: .top) { if let time = scrubbingTime, model.settings.loadVideoThumbnails {
                        GeometryReader { geometry in
                            VideoScrubPreview(model: model, time: time)
                                .frame(width: 144).position(x: max(72, min(geometry.size.width - 72, geometry.size.width * time / max(1, model.duration))), y: -65)
                        }.allowsHitTesting(false)
                    } }
                GlassEffectContainer { HStack(spacing: 10) {
                    Menu { ForEach([0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 3, 4], id: \.self) { rate in Button { model.rate = Float(rate); model.resetAutoHide() } label: { if model.rate == Float(rate) { Label("\(rate.formatted())x", systemImage: "checkmark") } else { Text("\(rate.formatted())x") } } } } label: { Text("\(Double(model.rate).formatted())x").font(.cofferTimecode).fontWeight(.semibold).frame(width: 52, height: 44) }.buttonStyle(.plain).foregroundStyle(Color.pinkInk).glassEffect(.regular.interactive(), in: .capsule).accessibilityLabel("Playback speed").simultaneousGesture(TapGesture().onEnded { model.holdControls() })
                    glassButton(title: "Loop video", symbol: model.isLooping ? "repeat.1" : "repeat", size: 44, color: model.isLooping ? .pink : .pinkInk) { model.isLooping.toggle(); model.resetAutoHide() }
                    glassButton(title: "Subtitles", symbol: "captions.bubble", size: 44) { if model.backend.subtitleTracks.isEmpty && model.subtitleCues.isEmpty { importSubtitle = true; model.holdControls() } else { model.toggleSubtitles(); model.resetAutoHide() } }
                    glassButton(title: "Rotate video", symbol: "rotate.right", size: 44) { model.orientation.toggle(); model.resetAutoHide() }
                    glassButton(title: "Fit or fill", symbol: model.videoGravity == .fit ? "rectangle.arrowtriangle.2.outward" : "rectangle.arrowtriangle.2.inward", size: 44) { model.videoGravity = model.videoGravity == .fit ? .fill : .fit; model.resetAutoHide() }
                    Spacer(minLength: 0)
                    if model.index + 1 < model.playlist.count { glassButton(title: "Next video", symbol: "forward.end.fill", size: 44) { model.next() } }
                } }
            }.padding(10).glassEffect(.regular, in: .rect(cornerRadius: 20))
        }.foregroundStyle(Color.white).tint(Color.pinkInk).padding(12)
    }
    private func hudAlignment(_ style: VideoPlayerModel.HUDStyle) -> Alignment { switch style { case .skipLeft, .brightness: .leading; case .skipRight, .volume: .trailing; case .speed: .top; default: .center } }
    private func glassButton(title: String, symbol: String, size: CGFloat, color: Color = .pinkInk, action: @escaping () -> Void) -> some View { Button(action: action) { Image(systemName: symbol).font(.system(size: size > 44 ? 22 : 17, weight: .semibold)).frame(width: size, height: size).contentShape(.circle) }.buttonStyle(.plain).foregroundStyle(color).glassEffect(.regular.interactive(), in: .circle).accessibilityLabel(title) }
    @ViewBuilder private var options: some View {
        FavouriteButton(item: model.current.fileItem)
        Toggle("Background Audio", isOn: Binding(get: { model.settings.backgroundVideoAudio }, set: { model.setBackgroundAudioEnabled($0) }))
        Divider()
        Menu("Audio Track") { ForEach(model.backend.audioTracks) { track in Button { model.selectAudioTrack(track.id) } label: { if model.selectedAudioTrack == track.id { Label(track.name, systemImage: "checkmark") } else { Text(track.name) } } } }
        Menu("Subtitles") { Button { model.selectSubtitleTrack(nil) } label: { if model.selectedSubtitleTrack == nil && (!model.externalSubtitlesEnabled || model.subtitleCues.isEmpty) { Label("Off", systemImage: "checkmark") } else { Text("Off") } }; ForEach(model.backend.subtitleTracks) { track in Button { model.selectSubtitleTrack(track.id) } label: { if model.selectedSubtitleTrack == track.id && (!model.externalSubtitlesEnabled || model.subtitleCues.isEmpty) { Label(track.name, systemImage: "checkmark") } else { Text(track.name) } } }; if !model.subtitleCues.isEmpty { Button { model.externalSubtitlesEnabled = true; model.backend.selectSubtitleTrack(nil); model.resetAutoHide() } label: { if model.externalSubtitlesEnabled { Label("External Subtitle", systemImage: "checkmark") } else { Text("External Subtitle") } } }; Button("Add from Files…") { importSubtitle = true } }
        Menu("Subtitle Delay (\(model.backend.subtitleDelay.formatted())s)") { ForEach([-1.0, -0.5, -0.1, 0, 0.1, 0.5, 1], id: \.self) { delta in Button(delta == 0 ? "Reset" : (delta > 0 ? "+" : "") + delta.formatted() + "s") { model.backend.subtitleDelay = delta == 0 ? 0 : model.backend.subtitleDelay + delta; model.resetAutoHide() } } }
        Menu("Sleep Timer") { Button("Off") { model.setSleep(minutes: nil) }; ForEach([15, 30, 45, 60], id: \.self) { minutes in Button(minutes == 60 ? "1 hour" : "\(minutes) min") { model.setSleep(minutes: minutes) } }; Button("End of track") { model.sleepAtEnd = true } }
        Button("Show in Files", systemImage: "folder") { let current = model.current.fileItem; model.close(); model.navigator.revealFile(current) }
        Button("Get Info", systemImage: "info.circle") { info = true }
    }
}

private struct VideoGestureHUD: View {
    let hud: VideoPlayerModel.GestureHUD
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ripple = false
    var body: some View {
        Group {
            switch hud.style {
            case .skipLeft, .skipRight:
                VStack(spacing: 10) { Image(systemName: hud.symbol ?? "goforward").font(.title); Text(hud.text).font(.cofferTimecode) }.frame(width: 120, height: 120).glassEffect(.regular, in: .circle)
                    .overlay { Circle().stroke(Color.white.opacity(ripple ? 0 : 0.5), lineWidth: 1).scaleEffect(ripple && !reduceMotion ? 1.4 : 1).animation(.snappy(duration: 0.6), value: ripple) }.onAppear { ripple = true }.onChange(of: hud.text) { _, _ in ripple.toggle() }
            case .brightness, .volume:
                VStack(spacing: 12) { Image(systemName: hud.symbol ?? "speaker.wave.2.fill").font(.title2); GeometryReader { g in Capsule().fill(Color.white.opacity(0.25)).overlay(alignment: .bottom) { Capsule().fill(Color.pink).frame(height: g.size.height * max(0, min(1, hud.value ?? 0))) } }.frame(width: 6, height: 100); Text(hud.text).font(.cofferTimecode) }.padding(16).glassEffect(.regular, in: .rect(cornerRadius: 18))
            case .speed:
                HStack(spacing: 8) { Text(hud.text); Image(systemName: "forward.fill") }.font(.cofferTimecode).padding(.horizontal, 16).padding(.vertical, 12).glassEffect(.regular, in: .capsule)
            default:
                VStack(spacing: 12) { if let symbol = hud.symbol { Image(systemName: symbol).font(.title2) }; Text(hud.text).font(.cofferTimecode).fontWeight(.semibold); if let value = hud.value { ProgressBar(value: value).frame(width: 140) } }.padding(16).glassEffect(.regular, in: .rect(cornerRadius: 18))
            }
        }.foregroundStyle(Color.pinkInk)
    }
}
