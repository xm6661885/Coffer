import AVKit
import Observation

@MainActor @Observable final class PiPController: NSObject, AVPictureInPictureControllerDelegate, AVPictureInPictureSampleBufferPlaybackDelegate {
    private(set) var controller: AVPictureInPictureController?
    @ObservationIgnored weak var model: VideoPlayerModel?
    private(set) var isPending = false
    @ObservationIgnored private var restoring = false
    @ObservationIgnored private var keepsPlayback = false
    @ObservationIgnored private var starting = false
    @ObservationIgnored private var cancelledStart = false
    @ObservationIgnored private var requestID = UUID()
    @ObservationIgnored private var pendingStart: Task<Void, Never>?
    @ObservationIgnored private var possibleObservation: NSKeyValueObservation?
    @ObservationIgnored private var startDeadline: Double?
    @ObservationIgnored private var restoreCompletion: ((Bool) -> Void)?
    @ObservationIgnored private var sourceUpdate: Task<Void, Never>?
    nonisolated private let playbackSnapshot = PiPPlaybackSnapshot()
    init(layer: AVPlayerLayer, model: VideoPlayerModel) {
        self.model = model
        controller = AVPictureInPictureController.isPictureInPictureSupported() ? AVPictureInPictureController(playerLayer: layer) : nil
        super.init(); observeController()
    }
    init(sampleBufferLayer: AVSampleBufferDisplayLayer, model: VideoPlayerModel) {
        self.model = model
        super.init()
        if AVPictureInPictureController.isPictureInPictureSupported() {
            controller = AVPictureInPictureController(contentSource: .init(sampleBufferDisplayLayer: sampleBufferLayer, playbackDelegate: self))
        }
        observeController()
    }
    private func observeController() {
        controller?.delegate = self; updateAutomaticStart(); updatePlaybackSnapshot()
        possibleObservation = controller?.observe(\.isPictureInPicturePossible, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.attemptStart() }
        }
    }
    func updateAutomaticStart() { controller?.canStartPictureInPictureAutomaticallyFromInline = model?.settings.autoPiP == true && model?.settings.backgroundVideoAudio == false }
    func start() {
        guard let model, !model.isClosed else { return }
        guard let controller else { model.toast.show("Picture in Picture isn't supported on this device."); return }
        guard !controller.isPictureInPictureActive, !isPending else { return }
        cancelledStart = false; isPending = true; starting = false; startDeadline = nil
        requestID = UUID(); let requestID = requestID, itemID = model.current.id
        let deadline = ProcessInfo.processInfo.systemUptime + 90
        model.holdControls()
        pendingStart = Task { [weak self] in
            var backgroundDeadline: Double?
            while !Task.isCancelled {
                guard let self, self.requestID == requestID, isPending else { return }
                guard let model = self.model, !model.isClosed, model.current.id == itemID else { cancelPendingStart(); return }
                let now = ProcessInfo.processInfo.systemUptime
                if model.isBackground && !controller.isPictureInPicturePossible {
                    if backgroundDeadline == nil { backgroundDeadline = now + 8 }
                    if let backgroundDeadline, now >= backgroundDeadline { cancelPendingStart(); model.continueAsAudio(); model.toast.show("Picture in Picture isn't available. Audio playback continues."); return }
                } else { backgroundDeadline = nil }
                if now >= deadline || (startDeadline.map { now >= $0 } ?? false) {
                    cancelPendingStart(); model.toast.show("Picture in Picture couldn't start. Tap again to retry."); return
                }
                attemptStart()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        attemptStart()
    }
    func playbackStateChanged() {
        updatePlaybackSnapshot(); updateContentSource(); controller?.invalidatePlaybackState(); attemptStart()
    }
    private func updatePlaybackSnapshot() {
        guard let model else { return }
        playbackSnapshot.set(duration: model.duration, paused: !model.isPlaying)
        (model.backend as? VLCBackend)?.updateVideoTimebase()
    }
    func updateContentSource() {
        guard let controller, let model, !model.isClosed else { return }
        let needsChange: Bool, ready: Bool
        if model.backend is AVPlayerBackend {
            needsChange = controller.contentSource?.playerLayer !== model.surface.avView.playerLayer
            ready = model.surface.avView.playerLayer.isReadyForDisplay
        } else if let backend = model.backend as? VLCBackend {
            needsChange = controller.contentSource?.sampleBufferDisplayLayer !== model.surface.sampleBufferLayer
            ready = (backend.videoOutput?.frameCount ?? 0) > 0
        } else { return }
        guard needsChange else { sourceUpdate?.cancel(); sourceUpdate = nil; if ready && model.pictureInPictureCanStart { model.pictureInPictureSourceUpdated() }; return }
        if controller.isPictureInPictureActive && !ready {
            if sourceUpdate == nil {
                sourceUpdate = Task { [weak self] in
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(100))
                        guard !Task.isCancelled, let self else { return }
                        updateContentSource()
                    }
                }
            }
            return
        }
        sourceUpdate?.cancel(); sourceUpdate = nil
        if model.backend is AVPlayerBackend { controller.contentSource = .init(playerLayer: model.surface.avView.playerLayer) }
        else { controller.contentSource = .init(sampleBufferDisplayLayer: model.surface.sampleBufferLayer, playbackDelegate: self) }
        model.pictureInPictureSourceUpdated()
    }
    private func attemptStart() {
        guard isPending, !starting, let controller, let model, !model.isClosed, model.pictureInPictureCanStart, !controller.isPictureInPictureActive, controller.isPictureInPicturePossible else { return }
        updateContentSource(); updatePlaybackSnapshot()
        starting = true; startDeadline = ProcessInfo.processInfo.systemUptime + 8
        controller.startPictureInPicture()
    }
    private func finishPendingStart() {
        requestID = UUID(); pendingStart?.cancel(); pendingStart = nil
        isPending = false; starting = false; startDeadline = nil
    }
    func cancelPendingStart() {
        let wasStarting = starting
        finishPendingStart()
        if wasStarting { cancelledStart = true; keepsPlayback = true; controller?.stopPictureInPicture() }
    }
    func restoreVideo() {
        guard controller?.isPictureInPictureActive == true || starting else { cancelPendingStart(); return }
        finishPendingStart(); restoring = true; controller?.stopPictureInPicture()
    }
    func stopKeepingPlayback() {
        let active = controller?.isPictureInPictureActive == true || starting
        cancelPendingStart()
        guard active else { return }
        keepsPlayback = true; controller?.stopPictureInPicture()
    }
    func stop() {
        sourceUpdate?.cancel(); sourceUpdate = nil
        restoreCompletion?(false); restoreCompletion = nil
        cancelPendingStart(); possibleObservation = nil
        controller?.stopPictureInPicture()
    }
    func completeRestoration() { restoreCompletion?(true); restoreCompletion = nil }
    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor [weak self] in guard let self, !cancelledStart else { return }; starting = true }
    }
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor [weak self] in
            guard let self, let model, !model.isClosed else { pictureInPictureController.stopPictureInPicture(); return }
            if cancelledStart { cancelledStart = false; keepsPlayback = true; finishPendingStart(); pictureInPictureController.stopPictureInPicture(); return }
            keepsPlayback = false; finishPendingStart(); model.didStartPiP()
            if model.isBackground && model.settings.backgroundVideoAudio { model.setBackground(true) }
        }
    }
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        Task { @MainActor [weak self] in
            guard let self, let model, !model.isClosed, !cancelledStart else { completionHandler(false); return }
            restoring = true; restoreCompletion?(false); restoreCompletion = completionHandler
            let alreadyPresented = model.navigator.videoPresented
            model.presentVideo(stopPiP: false)
            if alreadyPresented { completeRestoration() }
        }
    }
    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor [weak self] in
            guard let self, let model, !model.isClosed else { return }
            model.isPiP = false; finishPendingStart(); cancelledStart = false
            let restore = restoring, keep = keepsPlayback; restoring = false; keepsPlayback = false
            if !keep {
                if restore { model.presentVideo(stopPiP: false) }
                else { model.close() }
            }
            model.restoreNativeVLCOutputIfNeeded()
        }
    }
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, let model, !model.isClosed else { return }
            let wasCancelled = cancelledStart
            finishPendingStart(); cancelledStart = false; keepsPlayback = false
            if wasCancelled { return }
            if model.isBackground { model.continueAsAudio() }
            model.toast.show(error: error)
        }
    }
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        Task { @MainActor [weak self] in guard let model = self?.model, !model.isClosed else { return }; if playing { model.start() } else { model.pause() }; self?.playbackStateChanged() }
    }
    nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange { playbackSnapshot.range }
    nonisolated func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool { playbackSnapshot.paused }
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
        Task { @MainActor [weak self] in self?.playbackStateChanged() }
    }
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) {
        Task { @MainActor [weak self] in
            defer { completionHandler() }
            guard let self, let model, !model.isClosed else { return }
            await model.seekForPictureInPicture(by: skipInterval.seconds)
            playbackStateChanged()
        }
    }
}

// System playback queries may arrive off the main actor and require synchronous replies.
private final class PiPPlaybackSnapshot: @unchecked Sendable {
    private let lock = NSLock()
    private var duration = 0.0
    private var isPaused = true
    func set(duration: Double, paused: Bool) { lock.lock(); self.duration = duration; isPaused = paused; lock.unlock() }
    var range: CMTimeRange { lock.lock(); defer { lock.unlock() }; return CMTimeRange(start: .zero, duration: duration > 0 && duration.isFinite ? CMTime(seconds: duration, preferredTimescale: 600) : .positiveInfinity) }
    var paused: Bool { lock.lock(); defer { lock.unlock() }; return isPaused }
}
