import Foundation
import AVFoundation

@MainActor final class VLCBackend: NSObject, PlayerBackend, VLCMediaPlayerDelegate {
    private static let library = VLCLibrary(options: ["--stats"])
    private(set) var player = VLCMediaPlayer(library: VLCBackend.library)
    private(set) var videoOutput: VLCVideoOutput?
    var sampleBufferLayer: AVSampleBufferDisplayLayer?
    var onVideoOutputChange: (() -> Void)?
    private var loadedSource: MediaSource?
    private var changingOutput = false
    private var primePausedFrame = false
    private var subtitleSources: [URL] = []
    private var restoredTracks: (audio: Int?, subtitle: Int?, delay: Double)?
    var onStateChange: ((PlaybackState) -> Void)?
    var onTime: ((Double, Double) -> Void)?
    var rate: Float = 1 { didSet { player.rate = rate } }
    private var desiredVolume: Float = 1
    private var preparation: Task<Void, Never>?
    private var loadID = UUID()
    private var monitoring: Task<Void, Never>?
    private var frameHealth = VideoFrameWatchdog(minimumFrameWait: 3)
    private var lastDisplayed: Int32 = 0
    private var hasFrameRate = false
    private var reportedState: PlaybackState = .idle
    private var wantsPlayback = false
    private var framePrepared = false
    private var seekTarget: Double?
    private var preparationTime = 0.0
    var surfaceIsVisible: (() -> Bool)?
    var waitsForVideoFrame = false {
        didSet {
            guard waitsForVideoFrame != oldValue else { return }
            cancelPreparation(); framePrepared = false
            if wantsPlayback { play() }
        }
    }
    var volume: Float { get { desiredVolume } set { desiredVolume = max(0, min(1, newValue)); player.audio?.volume = preparation == nil ? Int32(desiredVolume * 100) : 0 } }
    var currentTime: Double { Double(player.time.intValue) / 1000 }
    var duration: Double { Double(player.media?.length.intValue ?? 0) / 1000 }
    var subtitleDelay: Double { get { Double(player.currentVideoSubTitleDelay) / 1_000_000 } set { restoredTracks?.delay = newValue; player.currentVideoSubTitleDelay = Int(newValue * 1_000_000) } }
    var audioTracks: [MediaTrack] { tracks(player.audioTrackIndexes, names: player.audioTrackNames) }
    var subtitleTracks: [MediaTrack] { tracks(player.videoSubTitlesIndexes, names: player.videoSubTitlesNames).filter { $0.id >= 0 } }
    var selectedAudioTrack: Int? { player.currentAudioTrackIndex >= 0 ? Int(player.currentAudioTrackIndex) : nil }
    var selectedSubtitleTrack: Int? { player.currentVideoSubTitleIndex >= 0 ? Int(player.currentVideoSubTitleIndex) : nil }
    override init() { super.init(); player.delegate = self }
    private func tracks(_ indexes: [Any]?, names: [Any]?) -> [MediaTrack] { zip(indexes ?? [], names ?? []).compactMap { id, name in guard let id = id as? NSNumber, let name = name as? String else { return nil }; return MediaTrack(id: id.intValue, name: name) } }
    func load(_ source: MediaSource) async throws {
        stop(); loadedSource = source; publish(.loading)
        player = VLCMediaPlayer(library: VLCBackend.library); player.delegate = self
        if let sampleBufferLayer {
            videoOutput = VLCVideoOutput(displayLayer: sampleBufferLayer)
            videoOutput?.attach(to: player)
        }
        configureMedia(source)
    }
    private func configureMedia(_ source: MediaSource, startTime: Double = 0) {
        var url = source.url
        if !source.isLocal, let header = source.headers["Authorization"], header.hasPrefix("Basic "), let data = Data(base64Encoded: String(header.dropFirst(6))), let credentials = String(data: data, encoding: .utf8), let colon = credentials.firstIndex(of: ":"), var components = URLComponents(url: url, resolvingAgainstBaseURL: false) { components.user = String(credentials[..<colon]); components.password = String(credentials[credentials.index(after: colon)...]); if let secured = components.url { url = secured } }
        let media = VLCMedia(url: url); media.addOption(":http-user-agent=Coffer"); media.addOption(source.isLocal ? ":file-caching=300" : ":network-caching=1200"); if !source.isLocal { media.addOption(":http-reconnect") }
        if startTime > 0 { media.addOption(":start-time=\(startTime)") }
        player.media = media; seekTarget = startTime
    }
    func prepareSampleBufferOutput(_ layer: AVSampleBufferDisplayLayer) async throws {
        guard videoOutput == nil, !changingOutput, let loadedSource else { return }
        await changeVideoOutput(layer, source: loadedSource)
    }
    func restoreNativeVideoOutput() async {
        guard videoOutput != nil, !changingOutput, let loadedSource else { return }
        await changeVideoOutput(nil, source: loadedSource)
    }
    private func changeVideoOutput(_ layer: AVSampleBufferDisplayLayer?, source: MediaSource) async {
        let loadID = loadID, target = max(0, currentTime)
        changingOutput = true; defer { if self.loadID == loadID { changingOutput = false } }
        let audioTrack = selectedAudioTrack, subtitleTrack = selectedSubtitleTrack, delay = subtitleDelay
        let retired = player, retiredOutput = videoOutput
        retired.delegate = nil; retired.pause(); monitoring?.cancel(); monitoring = nil; cancelPreparation()
        framePrepared = false; preparationTime = target
        sampleBufferLayer = layer
        player = VLCMediaPlayer(library: VLCBackend.library); player.delegate = self
        videoOutput = layer.map { VLCVideoOutput(displayLayer: $0) }; videoOutput?.attach(to: player)
        onVideoOutputChange?()
        configureMedia(source, startTime: target)
        for url in subtitleSources { player.addPlaybackSlave(url, type: .subtitle, enforce: true) }
        restoredTracks = (audioTrack, subtitleTrack, delay)
        publish(.buffering)
        await withCheckedContinuation { continuation in VLCVideoOutput.retire(retired, output: retiredOutput) { continuation.resume() } }
        guard self.loadID == loadID else { return }
        if wantsPlayback { beginPlayback() }
        else if waitsForVideoFrame { primePausedFrame = true; beginPlayback() }
        else { player.pause(); publish(.paused) }
    }
    func play() {
        primePausedFrame = false
        guard !changingOutput else { wantsPlayback = true; return }
        beginPlayback()
    }
    private func beginPlayback() {
        wantsPlayback = true
        if waitsForVideoFrame && !framePrepared {
            guard preparation == nil else { return }
            let loadID = loadID, startTime = seekTarget ?? max(0, currentTime)
            seekTarget = nil; preparationTime = startTime
            let displayed = displayedFrames
            // VLC must run to render a frame; freeze reported progress and mute audio until a picture is displayed.
            player.audio?.isMuted = true; player.audio?.volume = 0
            preparation = Task { [weak self] in
                guard let self else { return }
                let deadline = Date().addingTimeInterval(90)
                var appliedSeek = startTime <= 0
                while !Task.isCancelled, self.loadID == loadID, wantsPlayback {
                    if !appliedSeek, player.hasVideoOut, player.isSeekable {
                        appliedSeek = true
                        if abs(currentTime - startTime) > 0.5 { player.time = VLCTime(int: Int32(max(0, min(Double(Int32.max), startTime * 1000)))) }
                    }
                    if player.hasVideoOut, videoSize.width > 0, videoSize.height > 0, displayedFrames > displayed, currentTime >= startTime, surfaceIsVisible?() ?? true {
                        framePrepared = true; preparation = nil
                        if let restoredTracks { self.restoredTracks = nil; if let audio = restoredTracks.audio { selectAudioTrack(audio) }; selectSubtitleTrack(restoredTracks.subtitle); subtitleDelay = restoredTracks.delay }
                        if primePausedFrame { primePausedFrame = false; wantsPlayback = false; player.pause(); publish(.paused) }
                        else { player.play(); player.rate = rate; startMonitoring(); publish(.playing) }
                        player.audio?.volume = Int32(desiredVolume * 100); player.audio?.isMuted = false
                        return
                    }
                    if player.state == .ended {
                        wantsPlayback = false; monitoring?.cancel(); monitoring = nil; cancelPreparation(); publish(.ended); return
                    }
                    if player.state == .error || Date() >= deadline {
                        wantsPlayback = false; player.pause(); cancelPreparation()
                        publish(.failed("The video output couldn't be loaded. Check the connection or download this file for offline playback.")); return
                    }
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
            player.play(); player.rate = rate; publish(.buffering)
        } else { player.play(); player.rate = rate; startMonitoring() }
    }
    private func publish(_ state: PlaybackState) {
        guard reportedState != state else { return }
        reportedState = state; onStateChange?(state)
    }
    private func startMonitoring() {
        frameHealth.reset(at: currentTime)
        lastDisplayed = displayedFrames
        guard monitoring == nil else { return }
        monitoring = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.checkPlayback()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }
    private func checkPlayback() {
        guard wantsPlayback, preparation == nil else { return }
        if player.state == .ended || player.state == .error { reconcileState(); return }
        guard waitsForVideoFrame, surfaceIsVisible?() ?? true else { frameHealth.reset(at: currentTime); reconcileState(); return }
        if !hasFrameRate, let track = (player.media?.tracksInformation as? [[String: Any]])?.first(where: { $0[VLCMediaTracksInformationType] as? String == VLCMediaTracksInformationTypeVideo }),
           let numerator = track[VLCMediaTracksInformationFrameRate] as? NSNumber,
           let denominator = track[VLCMediaTracksInformationFrameRateDenominator] as? NSNumber,
           numerator.doubleValue > 0, denominator.doubleValue > 0 {
            frameHealth.frameInterval = denominator.doubleValue / numerator.doubleValue
            hasFrameRate = true
        }
        let displayed = displayedFrames
        let frameTime = displayed > lastDisplayed && player.hasVideoOut ? currentTime : nil
        lastDisplayed = displayed
        switch frameHealth.observe(clock: currentTime, frameTime: frameTime, rate: rate) {
        case .stalled:
            let target = frameHealth.lastVideoTime
            player.pause(); framePrepared = false; seekTarget = target
            player.time = VLCTime(int: Int32(max(0, min(Double(Int32.max), target * 1000))))
            // Restart from the last displayed position; the existing preparation gate mutes until rendering recovers.
            play()
        case .waiting: publish(.buffering)
        case .advancing:
            // Time and rendered-picture progress can recover even when VLC omits its playing notification.
            if frameTime != nil { publish(.playing) }
        }
    }
    private func reconcileState() {
        if preparation != nil { if wantsPlayback { publish(.buffering) }; return }
        if !wantsPlayback {
            if case .failed = reportedState { return }
            if reportedState != .ended && reportedState != .loading { publish(.paused) }
            return
        }
        switch player.state {
        case .opening: publish(.loading)
        case .buffering: publish(.buffering)
        case .playing: if wantsPlayback { publish(.playing) }
        case .paused: if !wantsPlayback { publish(.paused) } else { publish(.buffering) }
        case .ended: wantsPlayback = false; monitoring?.cancel(); monitoring = nil; publish(.ended)
        case .error: wantsPlayback = false; monitoring?.cancel(); monitoring = nil; publish(.failed("Couldn't decode this file."))
        default: break
        }
    }
    private func cancelPreparation() {
        preparation?.cancel(); preparation = nil
        player.audio?.volume = Int32(desiredVolume * 100); player.audio?.isMuted = false
    }
    var videoSize: CGSize { videoOutput?.videoSize ?? player.videoSize }
    private var displayedFrames: Int32 { videoOutput.map { Int32(clamping: $0.frameCount) } ?? (player.media?.statistics.displayedPictures ?? 0) }
    func updateVideoTimebase() { videoOutput?.setPlaybackTime(preparation != nil || changingOutput ? preparationTime : (seekTarget ?? currentTime), rate: wantsPlayback && preparation == nil && reportedState == .playing ? rate : 0) }
    func pause() { wantsPlayback = false; primePausedFrame = false; monitoring?.cancel(); monitoring = nil; player.pause(); cancelPreparation(); publish(.paused); updateVideoTimebase() }
    func seek(to seconds: Double) async {
        player.pause(); cancelPreparation(); framePrepared = false
        seekTarget = max(0, seconds)
        player.time = VLCTime(int: Int32(max(0, min(Double(Int32.max), seconds * 1000))))
        if wantsPlayback { play() }
        else if waitsForVideoFrame && !changingOutput { primePausedFrame = true; beginPlayback() }
        updateVideoTimebase()
    }
    func selectAudioTrack(_ id: Int?) { restoredTracks?.audio = id; player.currentAudioTrackIndex = Int32(id ?? -1) }
    func selectSubtitleTrack(_ id: Int?) { restoredTracks?.subtitle = id; player.currentVideoSubTitleIndex = Int32(id ?? -1) }
    func addExternalSubtitle(_ url: URL) { if !subtitleSources.contains(url) { subtitleSources.append(url) }; player.addPlaybackSlave(url, type: .subtitle, enforce: true) }
    func stop() {
        loadID = UUID(); wantsPlayback = false; changingOutput = false; primePausedFrame = false; monitoring?.cancel(); monitoring = nil
        frameHealth = VideoFrameWatchdog(minimumFrameWait: 3); hasFrameRate = false; framePrepared = false; seekTarget = nil
        cancelPreparation(); player.delegate = nil; player.pause()
        VLCVideoOutput.retire(player, output: videoOutput) { }
        videoOutput = nil; loadedSource = nil; subtitleSources = []; restoredTracks = nil
    }
    nonisolated func mediaPlayerStateChanged(_ aNotification: Notification) { Task { @MainActor [weak self] in guard let self, aNotification.object as? VLCMediaPlayer === player else { return }; reconcileState(); updateVideoTimebase() } }
    nonisolated func mediaPlayerTimeChanged(_ aNotification: Notification) { Task { @MainActor [weak self] in guard let self, aNotification.object as? VLCMediaPlayer === player else { return }; updateVideoTimebase(); onTime?(preparation == nil && !changingOutput ? currentTime : preparationTime, duration) } }
}
