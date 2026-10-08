import AVFoundation

@MainActor final class AVPlayerBackend: PlayerBackend {
    let player = AVPlayer()
    var onStateChange: ((PlaybackState) -> Void)?
    var onTime: ((Double, Double) -> Void)?
    var rate: Float = 1 {
        didSet {
            player.defaultRate = rate
            if preparation != nil { cancelPreparation(); if wantsPlayback { play() } }
            else if player.rate != 0 { player.rate = rate }
        }
    }
    var volume: Float { get { player.volume } set { player.volume = newValue } }
    var subtitleDelay = 0.0
    var externalSubtitle: URL?
    private var statusObservation: NSKeyValueObservation?
    private var controlObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var timeObserver: Any?
    private var audioGroup: AVMediaSelectionGroup?
    private var subtitleGroup: AVMediaSelectionGroup?
    private var loadID = UUID()
    private var preparation: Task<Void, Never>?
    private var metadata: Task<Void, Never>?
    private var monitoring: Task<Void, Never>?
    private var recovery: Task<Void, Never>?
    private var frameHealth = VideoFrameWatchdog()
    private var reportedState: PlaybackState = .idle
    private var loadingAsset: AVURLAsset?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var wantsPlayback = false
    private var framePrepared = false
    weak var displayLayer: AVPlayerLayer?
    var surfaceIsVisible: (() -> Bool)?
    private var isRemote = false
    private var seekID = UUID()
    private var isSeeking = false
    var waitsForVideoFrame = false {
        didSet {
            guard waitsForVideoFrame != oldValue else { return }
            cancelPreparation()
            framePrepared = false
            if wantsPlayback && !isSeeking { play() }
        }
    }
    var currentTime: Double { max(0, player.currentTime().seconds.isFinite ? player.currentTime().seconds : 0) }
    var duration: Double { let value = player.currentItem?.duration.seconds ?? 0; return value.isFinite ? max(0, value) : 0 }
    var bufferedTime: Double? { player.currentItem?.loadedTimeRanges.map { $0.timeRangeValue }.first(where: { CMTimeRangeContainsTime($0, time: player.currentTime()) }).map { CMTimeRangeGetEnd($0).seconds } }
    var audioTracks: [MediaTrack] { (audioGroup?.options ?? []).enumerated().map { MediaTrack(id: $0.offset, name: $0.element.displayName) } }
    var subtitleTracks: [MediaTrack] { (subtitleGroup?.options ?? []).enumerated().map { MediaTrack(id: $0.offset, name: $0.element.displayName) } }
    var selectedAudioTrack: Int? { selected(in: audioGroup) }
    var selectedSubtitleTrack: Int? { selected(in: subtitleGroup) }
    private func selected(in group: AVMediaSelectionGroup?) -> Int? { guard let group, let option = player.currentItem?.currentMediaSelection.selectedMediaOption(in: group) else { return nil }; return group.options.firstIndex(of: option) }
    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 4), queue: .main) { [weak self] _ in Task { @MainActor in guard let self else { return }; self.onTime?(self.preparation != nil || self.isSeeking ? self.frameHealth.lastVideoTime : self.currentTime, self.duration) } }
        controlObservation = player.observe(\.timeControlStatus) { [weak self] _, _ in
            Task { @MainActor in self?.reconcileState() }
        }
    }
    func load(_ source: MediaSource) async throws {
        let loadID = UUID(); self.loadID = loadID
        wantsPlayback = false; cancelMonitoring(); cancelPreparation(); metadata?.cancel(); metadata = nil; frameHealth = VideoFrameWatchdog()
        seekID = UUID(); isSeeking = false; framePrepared = false; videoOutput = nil; isRemote = !source.isLocal
        loadingAsset?.cancelLoading(); loadingAsset = nil
        player.currentItem?.asset.cancelLoading()
        player.pause(); statusObservation = nil; audioGroup = nil; subtitleGroup = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver); self.endObserver = nil }
        publish(.loading)
        let asset = AVURLAsset(url: source.url, options: source.headers.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": source.headers])
        loadingAsset = asset
        let playable = try await asset.load(.isPlayable)
        try Task.checkCancellation(); guard self.loadID == loadID else { throw CancellationError() }
        guard playable else { throw FileProviderError.other("This format requires VLC.") }
        let item = AVPlayerItem(asset: asset); item.audioTimePitchAlgorithm = .timeDomain
        // Buffer a short startup window; grow the forward buffer once playback starts.
        item.preferredForwardBufferDuration = isRemote ? 0.5 : 0
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in Task { @MainActor in guard let self, self.loadID == loadID, self.player.currentItem === item else { return }; if item.status == .failed { self.publish(.failed(item.error?.localizedDescription ?? "Couldn't open this file.")) } } }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self, weak item] _ in Task { @MainActor in guard let self, self.loadID == loadID, let item, self.player.currentItem === item else { return }; self.wantsPlayback = false; self.cancelMonitoring(); self.publish(.ended) } }
        player.replaceCurrentItem(with: item); player.defaultRate = rate
        // Track menus must not delay opening a large remote file.
        metadata = Task { [weak self, weak item] in
            async let audio = try? asset.loadMediaSelectionGroup(for: .audible)
            async let subtitles = try? asset.loadMediaSelectionGroup(for: .legible)
            async let videoTracks = try? asset.loadTracks(withMediaType: .video)
            let groups = await (audio, subtitles)
            let frameRate = try? await videoTracks?.first?.load(.nominalFrameRate)
            guard let self, let item, !Task.isCancelled, self.loadID == loadID, self.player.currentItem === item else { return }
            self.audioGroup = groups.0; self.subtitleGroup = groups.1
            if let frameRate, frameRate > 0 { self.frameHealth.frameInterval = 1 / Double(frameRate) }
        }
    }
    func play() {
        wantsPlayback = true
        guard let item = player.currentItem, !isSeeking else { return }
        if waitsForVideoFrame && !framePrepared {
            guard preparation == nil else { return }
            player.pause()
            let output = makeVideoOutput(for: item)
            let loadID = loadID
            publish(.buffering)
            preparation = Task { [weak self, weak item] in
                guard let self, let item else { return }
                let deadline = Date().addingTimeInterval(90)
                while item.status == .unknown || player.status == .unknown {
                    guard !Task.isCancelled, self.loadID == loadID, wantsPlayback else { return }
                    if Date() >= deadline { failPreparation(); return }
                    try? await Task.sleep(for: .milliseconds(50))
                }
                guard !Task.isCancelled, self.loadID == loadID, player.currentItem === item, wantsPlayback else { return }
                guard item.status == .readyToPlay, player.status == .readyToPlay else { failPreparation(); return }
                var primed = false
                player.preroll(atRate: rate) { [weak self] finished in
                    Task { @MainActor in guard let self, self.loadID == loadID, self.videoOutput === output else { return }; primed = finished }
                }
                var decoded = false
                while !Task.isCancelled, self.loadID == loadID, wantsPlayback {
                    // Decode one frame without advancing the playback clock or emitting audio.
                    if primed, !decoded { decoded = output.pixelBufferAndDisplayTime(forItemTime: player.currentTime()).pixelBuffer != nil }
                    if decoded, displayLayer == nil || (displayLayer?.isReadyForDisplay == true && (surfaceIsVisible?() ?? true)) {
                        framePrepared = true; preparation = nil
                        beginPlayback(); return
                    }
                    if item.status == .failed || Date() >= deadline { failPreparation(); return }
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
        } else { beginPlayback() }
    }
    private func beginPlayback() {
        guard wantsPlayback, !isSeeking else { return }
        if isRemote { player.currentItem?.preferredForwardBufferDuration = 4 }
        player.defaultRate = rate
        // Setting rate respects automaticallyWaitsToMinimizeStalling; playImmediately does not.
        player.rate = rate
        startMonitoring()
        reconcileState()
    }
    private func publish(_ state: PlaybackState) {
        guard reportedState != state else { return }
        reportedState = state; onStateChange?(state)
    }
    private func reconcileState() {
        guard player.currentItem != nil else { return }
        if preparation != nil || isSeeking || recovery != nil { if wantsPlayback { publish(.buffering) }; return }
        if !wantsPlayback {
            if case .failed = reportedState { return }
            if reportedState != .ended && reportedState != .loading { publish(.paused) }
            return
        }
        switch player.timeControlStatus {
        case .playing: publish(.playing)
        case .waitingToPlayAtSpecifiedRate: publish(.buffering)
        case .paused: publish(.buffering)
        @unknown default: break
        }
    }
    private func makeVideoOutput(for item: AVPlayerItem) -> AVPlayerItemVideoOutput {
        if let videoOutput { return videoOutput }
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: .init())
        output.suppressesPlayerRendering = false
        videoOutput = output; item.add(output)
        return output
    }
    private func startMonitoring() {
        frameHealth.reset(at: currentTime)
        if waitsForVideoFrame, let item = player.currentItem { _ = makeVideoOutput(for: item) }
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
        guard wantsPlayback, preparation == nil, !isSeeking, recovery == nil, let item = player.currentItem, item.status == .readyToPlay else { return }
        // PiP and external playback own their rendering; background audio deliberately has no video output.
        guard waitsForVideoFrame, displayLayer != nil, !player.isExternalPlaybackActive, surfaceIsVisible?() ?? true else {
            frameHealth.reset(at: currentTime); reconcileState(); return
        }
        let output = makeVideoOutput(for: item), time = player.currentTime()
        let frame = output.hasNewPixelBuffer(forItemTime: time) ? output.pixelBufferAndDisplayTime(forItemTime: time) : nil
        let frameTime = frame?.pixelBuffer == nil ? nil : frame?.itemTimeForDisplay.seconds
        switch frameHealth.observe(clock: currentTime, frameTime: frameTime, rate: rate) {
        case .stalled:
            let target = frameHealth.lastVideoTime, loadID = loadID
            player.pause(); publish(.buffering)
            recovery = Task { [weak self] in
                guard let self else { return }
                await seek(to: target)
                guard !Task.isCancelled, self.loadID == loadID else { return }
                recovery = nil
            }
        case .waiting: publish(.buffering)
        case .advancing: reconcileState()
        }
    }
    private func cancelMonitoring() {
        monitoring?.cancel(); monitoring = nil; recovery?.cancel(); recovery = nil
    }
    private func failPreparation() {
        wantsPlayback = false; cancelMonitoring(); cancelPreparation(); player.pause()
        publish(.failed("The video frame couldn't be loaded. Check the connection or download this file for offline playback."))
    }
    private func cancelPreparation() {
        preparation?.cancel(); preparation = nil; player.cancelPendingPrerolls()
        if let videoOutput { player.currentItem?.remove(videoOutput); self.videoOutput = nil }
    }
    func pause() { wantsPlayback = false; cancelMonitoring(); cancelPreparation(); player.pause(); publish(.paused) }
    func seek(to seconds: Double) async {
        cancelPreparation(); framePrepared = false; isSeeking = true
        let seekID = UUID(), loadID = loadID; self.seekID = seekID
        player.pause(); player.currentItem?.cancelPendingSeeks()
        frameHealth.reset(at: max(0, duration > 0 ? min(duration, seconds) : seconds))
        if wantsPlayback { publish(.buffering) }
        // A small tolerance avoids decoding a long GOP from an exact remote timestamp.
        let tolerance = isRemote ? CMTime(seconds: 0.5, preferredTimescale: 600) : .zero
        await player.seek(to: CMTime(seconds: max(0, duration > 0 ? min(duration, seconds) : seconds), preferredTimescale: 600), toleranceBefore: tolerance, toleranceAfter: tolerance)
        guard self.loadID == loadID, self.seekID == seekID else { return }
        isSeeking = false
        if wantsPlayback { play() }
    }
    func selectAudioTrack(_ id: Int?) { select(id, group: audioGroup) }
    func selectSubtitleTrack(_ id: Int?) { select(id, group: subtitleGroup) }
    private func select(_ id: Int?, group: AVMediaSelectionGroup?) { guard let group else { return }; let option = id.flatMap { group.options.indices.contains($0) ? group.options[$0] : nil }; player.currentItem?.select(option, in: group) }
    func addExternalSubtitle(_ url: URL) { externalSubtitle = url }
    func stop() { loadID = UUID(); seekID = UUID(); isSeeking = false; wantsPlayback = false; cancelMonitoring(); cancelPreparation(); metadata?.cancel(); metadata = nil; frameHealth = VideoFrameWatchdog(); loadingAsset?.cancelLoading(); loadingAsset = nil; player.currentItem?.asset.cancelLoading(); player.pause(); player.replaceCurrentItem(with: nil); statusObservation = nil; audioGroup = nil; subtitleGroup = nil; if let endObserver { NotificationCenter.default.removeObserver(endObserver); self.endObserver = nil } }
    deinit { if let timeObserver { player.removeTimeObserver(timeObserver) }; if let endObserver { NotificationCenter.default.removeObserver(endObserver) } }
}
