import Foundation
import SwiftUI
import AVFoundation
import AVKit
import MediaPlayer

@MainActor @Observable final class VideoPlayerModel {
    enum Gravity { case fit, fill }
    enum HUDStyle { case standard, skipLeft, skipRight, brightness, volume, speed }
    struct GestureHUD { var text: String; var value: Double?; var symbol: String?; var style: HUDStyle = .standard }
    let playlist: [MediaRef]
    var index: Int
    private(set) var backend: PlayerBackend = AVPlayerBackend()
    var state: PlaybackState = .idle
    var currentTime = 0.0; var duration = 0.0
    var rate: Float { didSet { backend.rate = rate; UserDefaults.standard.set(rate, forKey: "videoRate"); updateNowPlaying() } }
    var isLooping = false
    var controlsVisible = true
    var isLocked = false
    var videoGravity: Gravity = .fit { didSet { if !layerDetached { surface.configure(backend, fill: videoGravity == .fill) } } }
    var temporarySpeedBoost = false
    var gestureHUD: GestureHUD?
    var subtitleCues: [SubtitleParser.Cue] = []
    var externalSubtitlesEnabled = true
    var lastSubtitleTrack: Int?
    var resumeFrom: Double?
    var subtitle = ""
    var resolution: String?
    var downloadProgress = -1.0
    var isPiP = false
    var layerDetached = false
    var pip: PiPController?
    var remainingTime = true { didSet { UserDefaults.standard.set(remainingTime, forKey: "videoRemaining") } }
    let surface = VideoSurfaceHost(frame: .zero)
    let systemVolume = SystemVolume()
    let orientation = OrientationController()
    let settings: AppSettings; let toast: ToastCenter; let navigator: Navigator
    private let services: AppServices
    private var loading: Task<Void, Never>?
    private var preloading: Task<Void, Never>?
    private var preloadID = UUID()
    private var prefetched: (id: String, source: MediaSource, engine: PlaybackEngine)?
    private var preloadingSource: (id: String, source: MediaSource, engine: PlaybackEngine)?
    private var hiding: Task<Void, Never>?
    private var hudTask: Task<Void, Never>?
    private var pendingSeek: Double?
    private var pendingUserSeek: Double?
    private var hasUserSeek = false
    private var hasAVVideoPlayed = false
    private var requestedPiP = false
    private var lastSaved = Date.distantPast
    private var source: MediaSource?
    private var fallbackUsed = false
    private var consecutiveMissing = 0
    private var boostRate: Float = 1
    private var accumulatedSkip = 0.0
    private var skipTask: Task<Void, Never>?
    private var originalBrightness: CGFloat?
    private var notifications: [NSObjectProtocol] = []
    private var interrupted = false
    var externalSubtitleURLs: [URL] = []
    var sleepAtEnd = false
    private var sleepTask: Task<Void, Never>?
    private(set) var isClosed = false
    private(set) var isMinimized = false
    private(set) var isBackground = false
    private var resumeOnBackground = false
    private var restoreVideoOnForeground = false
    private var loadID = UUID()
    private var backendReady = false
    private var playWhenReady = true
    private var suspendedVideoTrack: Int32?
    private var retiringBackend: PlayerBackend?
    private var retiringStream: RemoteVideoStream?
    var retainsPlayback: Bool { isPiP || isMinimized }
    var current: MediaRef { playlist[index] }
    var isPlaying: Bool { playWhenReady && (state == .playing || state == .buffering || state == .loading) }
    var pictureInPicturePending: Bool { requestedPiP || pip?.isPending == true }
    var pictureInPictureCanStart: Bool { backendReady && !requestedPiP && ((backend as? VLCBackend).map { ($0.videoOutput?.frameCount ?? 0) > 0 } ?? (backend is AVPlayerBackend)) }
    init(playlist: [MediaRef], index: Int, navigator: Navigator, services: AppServices) {
        self.playlist = playlist; self.index = max(0, min(index, playlist.count - 1)); self.navigator = navigator; self.services = services; settings = services.settings; toast = services.toast
        rate = (UserDefaults.standard.object(forKey: "videoRate") as? Float) ?? 1
        remainingTime = (UserDefaults.standard.object(forKey: "videoRemaining") as? Bool) ?? true
        services.player.pause(); services.player.isFullScreenPresented = false
        systemVolume.onChange = { [weak self] value in
            guard let self, !isClosed, !isBackground, !isPiP, navigator.videoPresented else { return }
            showHUD("\(Int(value * 100))%", value: Double(value), symbol: value == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill", style: .volume)
        }
        notifications.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt; let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0; Task { @MainActor in guard let self else { return }; if type == AVAudioSession.InterruptionType.began.rawValue { self.interrupted = self.isPlaying; self.pause() } else { let resume = self.interrupted; self.interrupted = false; if options & AVAudioSession.InterruptionOptions.shouldResume.rawValue != 0 && resume { self.start() } } } })
        notifications.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in if note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { Task { @MainActor in self?.pause() } } })
    }
    func open() { guard state == .idle else { return }; if let screen = surface.window?.windowScene?.screen { originalBrightness = screen.brightness }; loadCurrent() }
    private func loadCurrent() {
        guard !isClosed else { return }
        holdControls(); cancelPictureInPictureRequest(); pendingUserSeek = nil; hasUserSeek = false; hasAVVideoPlayed = false
        if let staged = preloadingSource, staged.id == current.id { prefetched = staged; preloadingSource = nil }
        else { preloadingSource?.source.stream?.close(); preloadingSource = nil }
        loading?.cancel(); preloading?.cancel(); preloading = nil; preloadID = UUID(); loadID = UUID(); backendReady = false; playWhenReady = true
        backend.onStateChange = nil; backend.onTime = nil; backend.pause()
        currentTime = 0; duration = 0; subtitleCues = []; subtitle = ""; resolution = nil
        state = .loading; fallbackUsed = false
        if isPiP { if retiringStream == nil { retiringStream = source?.stream } else if source?.stream !== retiringStream { source?.stream?.close() } }
        else { source?.stream?.close() }
        source = nil; lastSubtitleTrack = nil; externalSubtitlesEnabled = true; pendingSeek = nil; resumeFrom = nil; downloadProgress = -1
        bindNowPlaying(); updateNowPlaying()
        let loadID = loadID
        let ref = current
        loading = Task {
            do {
                let resolver = MediaSourceResolver(registry: services.registry, cache: services.remoteCache, settings: settings)
                let source: MediaSource, engine: PlaybackEngine
                if let cached = prefetched, cached.id == ref.id {
                    source = cached.source; engine = cached.engine; prefetched = nil
                } else {
                    cancelPreload()
                    (source, engine) = try await resolver.resolve(ref) { self.downloadProgress = $0 }
                }
                try Task.checkCancellation(); self.source = source; source.stream?.activate()
                let chosen: PlayerBackend = engine == .avfoundation ? (backend as? AVPlayerBackend ?? retiringBackend as? AVPlayerBackend ?? AVPlayerBackend()) : (backend as? VLCBackend ?? retiringBackend as? VLCBackend ?? VLCBackend())
                try await configure(chosen, source: source)
                guard self.loadID == loadID, !isClosed else { return }; consecutiveMissing = 0; services.recents.add(ref.fileItem)
                if settings.resumePlayback && !hasUserSeek { let saved = services.positions.position(for: ref.id); pendingSeek = saved > 30 ? saved : nil }
                if source.isLocal {
                    let asset = AVURLAsset(url: source.url)
                    if let tracks = try? await asset.loadTracks(withMediaType: .video), let track = tracks.first, let size = try? await track.load(.naturalSize), let transform = try? await track.load(.preferredTransform) { let size = size.applying(transform); guard self.loadID == loadID, !Task.isCancelled else { return }; resolution = "\(Int(abs(size.width))) × \(Int(abs(size.height)))" }
                }
                await loadSiblingSubtitles(ref, loadID: loadID)
            } catch { guard !(error is CancellationError), !Task.isCancelled, self.loadID == loadID, !isClosed else { return }; if case FileProviderError.notFound = error, index + 1 < playlist.count, consecutiveMissing < 3 { consecutiveMissing += 1; toast.show("Skipped unavailable file: " + ref.name); index += 1; loadCurrent() } else if let reason = source?.stream?.failureReason { state = .failed(reason); toast.show(reason) } else if source != nil && backend is AVPlayerBackend && !fallbackUsed { await fallback() } else { state = .failed(error.localizedDescription); toast.show(error: error) } }
        }
    }
    private func configure(_ backend: PlayerBackend, source: MediaSource) async throws {
        let loadID = loadID
        if self.backend !== backend {
            self.backend.onStateChange = nil; self.backend.onTime = nil
            if retiringBackend === backend { self.backend.stop(); retiringBackend = nil }
            else if isPiP {
                // Keep the previous PiP source's last frame until the replacement
                // source is ready; AVKit stops PiP if its source changes too early.
                if retiringBackend == nil { retiringBackend = self.backend }
                else { self.backend.stop() }
            } else { self.backend.stop(); pip?.stop(); pip = nil }
            suspendedVideoTrack = nil
        }
        self.backend = backend; backend.rate = rate; backendReady = false
        if let vlc = backend as? VLCBackend {
            if isPiP || requestedPiP || (settings.autoPiP && !settings.backgroundVideoAudio) || vlc.sampleBufferLayer != nil { vlc.sampleBufferLayer = surface.sampleBufferLayer }
            vlc.onVideoOutputChange = { [weak self, weak vlc] in guard let self, self.backend === vlc, !isClosed else { return }; applyVideoOutput() }
        }
        backend.waitsForVideoFrame = !isMinimized && (!isBackground || isPiP)
        backend.onStateChange = { [weak self, weak backend] state in
            guard let self, let backend, !isClosed, self.loadID == loadID, self.backend === backend else { return }
            if !backendReady && (state == .paused || state == .playing || state == .buffering || state == .ended) { return }
            let state: PlaybackState = {
                if case .failed = state, let reason = source.stream?.failureReason { return .failed(reason) }
                return state
            }()
            self.state = state
            if case .failed = state {
                cancelPictureInPictureRequest()
                if backend is AVPlayerBackend && !hasAVVideoPlayed && !fallbackUsed && source.stream?.failureReason == nil { loading = Task { await self.fallback() } }
                else { controlsVisible = true }
            }
            if state == .buffering || state == .loading { holdControls() }
            if state == .playing {
                if backend is AVPlayerBackend && backend.waitsForVideoFrame { hasAVVideoPlayed = true }
                applyVideoOutput(); pip?.playbackStateChanged(); resetAutoHide(); preloadNextIfNeeded()
            }
            if state == .ended { ended() }
            pip?.playbackStateChanged()
            updateNowPlaying()
        }
        backend.onTime = { [weak self, weak backend] time, duration in
            guard let self, let backend, !isClosed, backendReady, self.loadID == loadID, self.backend === backend else { return }
            let durationChanged = self.duration != duration
            currentTime = time; self.duration = duration
            if let saved = pendingSeek, duration > 0 { pendingSeek = nil; if duration - saved > 30 { seek(to: saved); resumeFrom = saved; Task { [weak self] in try? await Task.sleep(for: .seconds(4)); guard self?.loadID == loadID else { return }; self?.resumeFrom = nil } } }
            if resolution == nil, let vlc = backend as? VLCBackend, vlc.videoSize.width > 0 {
                let size = vlc.videoSize; resolution = "\(Int(size.width)) × \(Int(size.height))"
            }
            pip?.playbackStateChanged()
            let at = time - backend.subtitleDelay
            subtitle = externalSubtitlesEnabled ? subtitleCues.filter { $0.start <= at && $0.end >= at }.map(\.text).joined(separator: "\n") : ""
            if Date().timeIntervalSince(lastSaved) >= 5 { savePosition(); updateNowPlaying() }
            else if durationChanged { updateNowPlaying() }
        }
        try await backend.load(source); try Task.checkCancellation()
        guard self.loadID == loadID, !isClosed, self.backend === backend else { throw CancellationError() }
        while let target = pendingUserSeek {
            pendingUserSeek = nil
            await backend.seek(to: target)
            try Task.checkCancellation()
            guard self.loadID == loadID, !isClosed, self.backend === backend else { throw CancellationError() }
        }
        backendReady = true
        if let av = backend as? AVPlayerBackend { av.player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible }
        applyVideoOutput()
        let session = AVAudioSession.sharedInstance(); try session.setCategory(.playback, mode: .moviePlayback); try session.setActive(true)
        bindNowPlaying(); if playWhenReady { backend.play() } else { state = .paused }
        if requestedPiP { requestedPiP = false; requestPictureInPicture() }
        updateNowPlaying(); resetAutoHide()
    }
    func updatePreloading() {
        if settings.preloadNextVideo && settings.streamRemoteMedia { if isPlaying { preloadNextIfNeeded() } }
        else { cancelPreload() }
    }
    private func cancelPreload() {
        preloading?.cancel(); preloading = nil; preloadID = UUID()
        prefetched?.source.stream?.close(); prefetched = nil
        preloadingSource?.source.stream?.close(); preloadingSource = nil
    }
    private func preloadNextIfNeeded() {
        guard !isClosed, settings.preloadNextVideo, settings.streamRemoteMedia,
              index + 1 < playlist.count, playlist[index + 1].location.isRemote else { cancelPreload(); return }
        let next = playlist[index + 1]
        guard prefetched?.id != next.id, preloading == nil else { return }
        let loadID = loadID
        preloadID = UUID(); let preloadID = preloadID
        preloading = Task { [weak self] in
            guard let self else { return }
            // Give the current video time to finish startup before using one connection for the next.
            do {
                try await Task.sleep(for: .seconds(2))
                guard !isClosed, self.loadID == loadID, self.preloadID == preloadID, settings.preloadNextVideo, settings.streamRemoteMedia else { return }
                let resolver = MediaSourceResolver(registry: services.registry, cache: services.remoteCache, settings: settings)
                let (source, engine) = try await resolver.resolve(next, preloadOnly: true)
                guard !Task.isCancelled, !isClosed, self.loadID == loadID, settings.preloadNextVideo, settings.streamRemoteMedia else { source.stream?.close(); return }
                preloadingSource = (next.id, source, engine)
                // Preload metadata and a small opening window, never a full offline download.
                if let stream = source.stream { try await stream.preloadOpening() }
                guard !Task.isCancelled, !isClosed, self.loadID == loadID, settings.preloadNextVideo else { if self.source?.stream !== source.stream && self.prefetched?.source.stream !== source.stream { source.stream?.close() }; return }
                prefetched = (next.id, source, engine); preloadingSource = nil
            } catch {
                // Optional prefetch failure is retried normally when the video is opened.
                if self.preloadID == preloadID { preloadingSource?.source.stream?.close(); preloadingSource = nil }
            }
            if self.preloadID == preloadID { preloading = nil }
        }
    }
    private func fallback() async {
        guard let source, !fallbackUsed, !isClosed else { return }; fallbackUsed = true
        let loadID = loadID
        backend.onStateChange = nil; backend.onTime = nil
        do { try await configure(VLCBackend(), source: source) }
        catch { guard !(error is CancellationError), !Task.isCancelled, !isClosed, self.loadID == loadID else { return }; state = .failed(error.localizedDescription); toast.show(error: error) }
    }
    func start() {
        guard !isClosed else { return }; playWhenReady = true
        guard backendReady else { return }
        do { try AVAudioSession.sharedInstance().setActive(true) } catch { toast.show(error: error); return }
        if state == .ended || (duration > 0 && currentTime >= duration - 0.05) {
            let backend = backend, loadID = loadID
            Task { await backend.seek(to: 0); guard !isClosed, self.loadID == loadID else { return }; currentTime = 0; backend.play(); updateNowPlaying() }
        } else { backend.play() }
        resetAutoHide(); updateNowPlaying()
    }
    func pause() { guard !isClosed else { return }; cancelPictureInPictureRequest(); playWhenReady = false; resumeOnBackground = false; backend.pause(); state = .paused; controlsVisible = true; hiding?.cancel(); savePosition(); updateNowPlaying() }
    func togglePlay() { isPlaying ? pause() : start() }
    func seek(to time: Double) {
        guard !isClosed else { return }
        let time = max(0, min(duration > 0 ? duration : time, time)), backend = backend, loadID = loadID
        hasUserSeek = true; pendingSeek = nil; resumeFrom = nil; currentTime = time
        guard backendReady else { pendingUserSeek = time; holdControls(); return }
        Task { await backend.seek(to: time); guard !isClosed, self.loadID == loadID else { return }; savePosition(); updateNowPlaying() }
        resetAutoHide()
    }
    func requestPictureInPicture() {
        guard !isClosed else { return }
        holdControls()
        if pictureInPicturePending { cancelPictureInPictureRequest(); resetAutoHide(); return }
        guard backendReady else { requestedPiP = true; return }
        guard AVPictureInPictureController.isPictureInPictureSupported() else { toast.show("Picture in Picture isn't supported on this device."); return }
        if let vlc = backend as? VLCBackend, vlc.videoOutput == nil {
            requestedPiP = true
            let loadID = loadID
            Task { [weak self, weak vlc] in
                guard let self, let vlc else { return }
                do {
                    try await vlc.prepareSampleBufferOutput(surface.sampleBufferLayer)
                    guard !isClosed, self.loadID == loadID, backend === vlc else { return }
                    applyVideoOutput()
                    guard requestedPiP else { return }
                    requestedPiP = false; pip?.start()
                } catch {
                    guard !isClosed, self.loadID == loadID, !(error is CancellationError) else { return }
                    requestedPiP = false; toast.show(error: error)
                }
            }
            return
        }
        applyVideoOutput()
        guard let pip else { toast.show("Picture in Picture isn't available yet."); return }
        pip.start()
    }
    private func cancelPictureInPictureRequest() { requestedPiP = false; pip?.cancelPendingStart() }
    func seekForPictureInPicture(by interval: Double) async {
        guard !isClosed, interval.isFinite else { return }
        let target = max(0, min(duration > 0 ? duration : currentTime + interval, currentTime + interval))
        let backend = backend, loadID = loadID
        hasUserSeek = true; pendingSeek = nil; resumeFrom = nil; currentTime = target
        if !backendReady { pendingUserSeek = target; return }
        await backend.seek(to: target)
        guard !isClosed, self.loadID == loadID else { return }
        (backend as? VLCBackend)?.updateVideoTimebase(); savePosition(); updateNowPlaying()
    }
    func pictureInPictureSourceUpdated() { retiringBackend?.stop(); retiringBackend = nil; retiringStream?.close(); retiringStream = nil }
    func restoreNativeVLCOutputIfNeeded() {
        guard !isClosed, !isPiP, !isBackground, !pictureInPicturePending, navigator.videoPresented,
              !(settings.autoPiP && !settings.backgroundVideoAudio), let vlc = backend as? VLCBackend, vlc.videoOutput != nil else { return }
        Task { [weak self, weak vlc] in
            guard let self, let vlc else { return }
            await vlc.restoreNativeVideoOutput()
            guard !isClosed, backend === vlc else { return }
            applyVideoOutput()
        }
    }
    func skip(by seconds: Double) { seek(to: currentTime + seconds) }
    func next() { guard !isClosed, index + 1 < playlist.count else { return }; savePosition(); index += 1; loadCurrent() }
    func previous() { guard !isClosed else { return }; guard index > 0 else { seek(to: 0); return }; savePosition(); index -= 1; loadCurrent() }
    private func ended() {
        services.positions.remove(current.id)
        if sleepAtEnd { pause(); sleepAtEnd = false }
        else if isLooping {
            let backend = backend, loadID = loadID
            Task { await backend.seek(to: 0); guard !isClosed, self.loadID == loadID else { return }; currentTime = 0; backend.play(); updateNowPlaying() }
        }
        else if index + 1 < playlist.count { next() }
        else { controlsVisible = true }
    }
    func savePosition() { lastSaved = Date(); if settings.resumePlayback && duration > 0 { if duration - currentTime < 10 { services.positions.remove(current.id) } else { services.positions.save(current.fileItem, time: currentTime, duration: duration) } } }
    func retry() { loadCurrent() }
    func holdControls() { hiding?.cancel(); controlsVisible = true }
    func setSleep(minutes: Int?) { sleepTask?.cancel(); sleepAtEnd = false; guard let minutes else { return }; sleepTask = Task { try? await Task.sleep(for: .seconds(Double(minutes * 60))); guard !Task.isCancelled else { return }; for step in (0..<12).reversed() { backend.volume = Float(step) / 12; try? await Task.sleep(for: .milliseconds(250)); if Task.isCancelled { backend.volume = 1; return } }; backend.pause(); backend.volume = 1; state = .paused; controlsVisible = true; updateNowPlaying() } }
    func resetAutoHide() { hiding?.cancel(); guard !isClosed, state == .playing, !pictureInPicturePending else { return }; hiding = Task { try? await Task.sleep(for: .seconds(isLocked ? 3 : 3.5)); guard !Task.isCancelled else { return }; withAnimation(.smooth) { controlsVisible = false } } }
    func scrubThumbnail(at time: Double) async -> UIImage? {
        guard !isClosed, let source else { return nil }
        return await services.thumbnails.previewFrame(source: source, time: time, duration: duration)
    }
    func showControls() { withAnimation(.smooth) { controlsVisible.toggle() }; if controlsVisible { resetAutoHide() } }
    func toggleLock() { isLocked.toggle(); controlsVisible = true; resetAutoHide() }
    func showHUD(_ text: String, value: Double? = nil, symbol: String? = nil, duration: Double = 1.2, style: HUDStyle = .standard) { hudTask?.cancel(); withAnimation(.snappy) { gestureHUD = GestureHUD(text: text, value: value, symbol: symbol, style: style) }; hudTask = Task { try? await Task.sleep(for: .seconds(duration)); guard !Task.isCancelled else { return }; withAnimation(.snappy) { gestureHUD = nil } } }
    func doubleTap(at fraction: CGFloat) { guard !isLocked else { return }; if fraction > 1.0 / 3 && fraction < 2.0 / 3 { togglePlay(); return }; let delta = Double(settings.skipInterval) * (fraction < 0.5 ? -1 : 1); accumulatedSkip += delta; showHUD("\(delta < 0 ? "« " : "")\(Int(abs(accumulatedSkip)))s\(delta > 0 ? " »" : "")", symbol: delta < 0 ? "gobackward" : "goforward", style: delta < 0 ? .skipLeft : .skipRight); skipTask?.cancel(); skipTask = Task { try? await Task.sleep(for: .seconds(1)); guard !Task.isCancelled else { return }; skip(by: accumulatedSkip); accumulatedSkip = 0 } }
    func boost(_ on: Bool, translation: CGFloat = 0) { guard !isLocked else { return }; if on { if !temporarySpeedBoost { boostRate = rate; UIImpactFeedbackGenerator(style: .light).impactOccurred() }; temporarySpeedBoost = true; let rates: [Float] = [1.5, 2, 2.5, 3]; let initial = rates.firstIndex(of: Float(settings.longPressSpeed)) ?? 1; backend.rate = rates[max(0, min(3, initial + Int(translation / 40)))]; showHUD("\(Double(backend.rate).formatted())x", symbol: "forward.fill", duration: 20, style: .speed) } else if temporarySpeedBoost { temporarySpeedBoost = false; backend.rate = boostRate; gestureHUD = nil; resetAutoHide() } }
    func prepareForBackground() {
        guard !isClosed, !isBackground else { return }
        resumeOnBackground = isPlaying
        pip?.updateAutomaticStart()
        if settings.backgroundVideoAudio && !isPiP { setVideoOutput(enabled: false) }
    }
    func setBackgroundAudioEnabled(_ enabled: Bool) {
        if settings.backgroundVideoAudio != enabled { settings.backgroundVideoAudio = enabled }
        updateAutomaticPictureInPicture()
        if isBackground { setBackground(true) }
        else if !enabled && isMinimized { presentVideo() }
    }
    func updateAutomaticPictureInPicture() {
        pip?.updateAutomaticStart()
        guard !isClosed, !isBackground, backendReady, settings.autoPiP, !settings.backgroundVideoAudio,
              let vlc = backend as? VLCBackend, vlc.videoOutput == nil else { return }
        let loadID = loadID
        Task { [weak self, weak vlc] in
            guard let self, let vlc else { return }
            do { try await vlc.prepareSampleBufferOutput(surface.sampleBufferLayer) }
            catch { guard !isClosed, self.loadID == loadID else { return }; toast.show(error: error) }
            guard !isClosed, self.loadID == loadID, backend === vlc else { return }
            applyVideoOutput()
        }
    }
    func setBackground(_ background: Bool) {
        guard !isClosed else { return }
        isBackground = background
        if background {
            savePosition()
            if settings.backgroundVideoAudio || isMinimized {
                isMinimized = true
                if settings.backgroundVideoAudio { restoreVideoOnForeground = false }
                pip?.stopKeepingPlayback(); isPiP = false
                setVideoOutput(enabled: false)
                navigator.videoPresented = false
                if resumeOnBackground && !interrupted && state == .paused { start() }
            } else if isPlaying || resumeOnBackground {
                if settings.autoPiP { if !isPiP && !pictureInPicturePending { requestPictureInPicture() } }
                else if !isPiP { pause() }
            }
        } else {
            resumeOnBackground = false
            if isPiP || restoreVideoOnForeground { presentVideo() }
            else if !isMinimized { applyVideoOutput() }
        }
        updateNowPlaying()
    }
    func exitPlayer() {
        guard !isClosed else { return }
        if settings.backgroundVideoAudio { continueAsAudio() }
        else { close() }
    }
    func continueAsAudio() {
        guard !isClosed else { return }
        cancelPictureInPictureRequest(); savePosition(); hiding?.cancel(); hudTask?.cancel(); gestureHUD = nil
        if !settings.backgroundVideoAudio { restoreVideoOnForeground = true }
        isMinimized = true; pip?.stopKeepingPlayback(); isPiP = false
        setVideoOutput(enabled: false); navigator.videoPresented = false; updateNowPlaying()
    }
    func presentVideo(stopPiP: Bool = true) {
        guard !isClosed else { return }
        isMinimized = false; restoreVideoOnForeground = false; navigator.videoPresented = true; controlsVisible = true
        if !isBackground { applyVideoOutput() }
        if stopPiP { pip?.restoreVideo() }
        updateNowPlaying(); resetAutoHide()
    }
    func presentationAppeared() { guard !isClosed && navigator.videoPresented else { return }; pip?.completeRestoration(); if !isBackground { applyVideoOutput(); restoreOrientation(); restoreNativeVLCOutputIfNeeded() } }
    func presentationDismissed() { if !navigator.videoPresented && !retainsPlayback { close() } }
    func didStartPiP() { guard !isClosed else { return }; isPiP = true; restoreVideoOnForeground = true; isMinimized = false; applyVideoOutput(); navigator.videoPresented = false }
    private func restoreOrientation() { if !isBackground, !isMinimized, navigator.videoPresented { orientation.resume() } }
    private func applyVideoOutput() { setVideoOutput(enabled: !isMinimized && (!isBackground || isPiP || !settings.backgroundVideoAudio)) }
    private func setVideoOutput(enabled: Bool) {
        if let av = backend as? AVPlayerBackend { av.displayLayer = enabled && !isPiP ? surface.avView.playerLayer : nil }
        layerDetached = !enabled
        backend.waitsForVideoFrame = enabled
        if let av = backend as? AVPlayerBackend {
            if enabled {
                surface.configure(backend, fill: videoGravity == .fill)
                if pip == nil { pip = PiPController(layer: surface.avView.playerLayer, model: self) }
                pip?.updateContentSource(); pip?.updateAutomaticStart()
            } else { surface.avView.playerLayer.player = nil }
            av.player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        } else if let vlc = backend as? VLCBackend {
            if enabled {
                surface.configure(backend, fill: videoGravity == .fill)
                if let suspendedVideoTrack { vlc.player.currentVideoTrackIndex = suspendedVideoTrack; self.suspendedVideoTrack = nil }
                if vlc.videoOutput != nil && pip == nil { pip = PiPController(sampleBufferLayer: surface.sampleBufferLayer, model: self) }
                pip?.updateContentSource(); pip?.updateAutomaticStart()
            } else {
                if vlc.player.currentVideoTrackIndex >= 0 { suspendedVideoTrack = vlc.player.currentVideoTrackIndex; vlc.player.currentVideoTrackIndex = -1 }
                vlc.player.drawable = nil
            }
        }
    }
    func addSubtitle(_ url: URL) async {
        let loadID = loadID
        do {
            if backend is VLCBackend { backend.addExternalSubtitle(url) }
            else { let cues = try await SubtitleParser.load(url); try Task.checkCancellation(); guard self.loadID == loadID, !isClosed else { return }; subtitleCues = cues; backend.addExternalSubtitle(url); backend.selectSubtitleTrack(nil); externalSubtitlesEnabled = true }
        } catch is CancellationError { } catch { toast.show(error: error) }
    }
    private func loadSiblingSubtitles(_ ref: MediaRef, loadID: UUID) async {
        do {
            let base = PathUtil.baseName(ref.name)
            let files = try await services.registry.provider(for: ref.location).list(PathUtil.parent(ref.path))
            try Task.checkCancellation(); guard self.loadID == loadID, !isClosed else { return }
            let subtitle = files.filter { ["srt", "ass", "ssa", "vtt"].contains($0.ext) && $0.name.hasPrefix(base + ".") }.sorted { $0.name < $1.name }.first
            if let subtitle {
                let url = subtitle.location == .local ? services.registry.local.url(for: subtitle.path) : try await services.remoteCache.fetch(subtitle, progress: { _ in })
                try Task.checkCancellation(); guard self.loadID == loadID, !isClosed else { return }; await addSubtitle(url)
            }
        } catch is CancellationError { } catch { toast.show(error: error) }
    }
    var selectedAudioTrack: Int? { (backend as? AVPlayerBackend)?.selectedAudioTrack ?? (backend as? VLCBackend)?.selectedAudioTrack }
    var selectedSubtitleTrack: Int? { (backend as? AVPlayerBackend)?.selectedSubtitleTrack ?? (backend as? VLCBackend)?.selectedSubtitleTrack }
    func selectAudioTrack(_ id: Int?) { backend.selectAudioTrack(id); resetAutoHide() }
    func selectSubtitleTrack(_ id: Int?) { if let id { lastSubtitleTrack = id }; backend.selectSubtitleTrack(id); externalSubtitlesEnabled = false; resetAutoHide() }
    func toggleSubtitles() {
        if !subtitleCues.isEmpty { externalSubtitlesEnabled.toggle() }
        else if let selected = selectedSubtitleTrack { lastSubtitleTrack = selected; backend.selectSubtitleTrack(nil) }
        else if let track = lastSubtitleTrack.flatMap({ id in backend.subtitleTracks.first { $0.id == id } }) ?? backend.subtitleTracks.first { backend.selectSubtitleTrack(track.id); lastSubtitleTrack = track.id }
    }
    private func bindNowPlaying() {
        let now = services.nowPlaying; now.removeCommands(); now.ownedByVideo = true
        let center = MPRemoteCommandCenter.shared()
        now.add(center.playCommand) { [weak self] _ in self?.start() }
        now.add(center.pauseCommand) { [weak self] _ in self?.pause() }
        now.add(center.togglePlayPauseCommand) { [weak self] _ in self?.togglePlay() }
        now.add(center.stopCommand) { [weak self] _ in self?.close() }
        now.add(center.changePlaybackPositionCommand) { [weak self] event in if let event = event as? MPChangePlaybackPositionCommandEvent { self?.seek(to: event.positionTime) } }
        now.add(center.nextTrackCommand) { [weak self] _ in self?.next() }
        now.add(center.previousTrackCommand) { [weak self] _ in self?.previous() }
        now.add(center.changePlaybackRateCommand) { [weak self] event in if let event = event as? MPChangePlaybackRateCommandEvent { self?.rate = event.playbackRate } }
        center.changePlaybackRateCommand.supportedPlaybackRates = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 3, 4]
        center.nextTrackCommand.isEnabled = index + 1 < playlist.count
    }
    private func updateNowPlaying() { services.nowPlaying.update(title: current.name, time: currentTime, duration: duration, rate: state == .playing ? rate : 0, defaultRate: rate, video: true, audioOnly: isMinimized || (isBackground && settings.backgroundVideoAudio), queueIndex: index, queueCount: playlist.count) }
    func close() {
        guard !isClosed else { return }; cancelPictureInPictureRequest(); isClosed = true; loadID = UUID(); backendReady = false; savePosition(); loading?.cancel(); sleepTask?.cancel(); hiding?.cancel(); hudTask?.cancel(); skipTask?.cancel(); backend.onStateChange = nil; backend.onTime = nil; backend.stop(); retiringBackend?.stop(); retiringBackend = nil; retiringStream?.close(); retiringStream = nil; source?.stream?.close(); source = nil; cancelPreload(); systemVolume.onChange = nil; pip?.stop(); pip = nil
        let subtitles = externalSubtitleURLs; Task.detached { for url in subtitles { try? FileManager.default.removeItem(at: url) } }
        for notification in notifications { NotificationCenter.default.removeObserver(notification) }; notifications = []
        if let originalBrightness, let screen = surface.window?.windowScene?.screen { screen.brightness = originalBrightness }; let wasPresented = navigator.videoPresented; navigator.videoPresented = false; if !wasPresented { orientation.restore(); if services.activeVideo === self { services.activeVideo = nil } }; services.nowPlaying.clear(); if services.player.hasItem { services.nowPlaying.bind(services.player); services.player.updateNowPlaying() }
    }
}
