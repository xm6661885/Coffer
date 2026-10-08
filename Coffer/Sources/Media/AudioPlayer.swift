import Foundation
import SwiftUI
import AVFAudio
import AVFoundation
import Observation

@MainActor @Observable final class AudioPlayer {
    enum RepeatMode: String, Codable { case off, all, one }
    enum SleepTimer { case minutes(Date), endOfTrack }
    private(set) var queue: [MediaRef] = []
    private var originalQueue: [MediaRef] = []
    private(set) var index = 0
    var current: MediaRef? { queue.indices.contains(index) ? queue[index] : nil }
    private(set) var metadata: [String: TrackMetadata] = [:]
    private(set) var state: PlaybackState = .idle
    private(set) var currentTime = 0.0
    private(set) var duration = 0.0
    var isPlaying: Bool { state == .playing || state == .buffering }
    var hasItem: Bool { current != nil }
    var isFullScreenPresented = false
    var showQueue = false
    var rate: Float { didSet { backend?.rate = rate; UserDefaults.standard.set(rate, forKey: "audioRate"); updateNowPlaying() } }
    var repeatMode: RepeatMode { didSet { UserDefaults.standard.set(repeatMode.rawValue, forKey: "audioRepeat"); updateNowPlaying() } }
    private(set) var shuffle: Bool
    var bufferedTime: Double? { (backend as? AVPlayerBackend)?.bufferedTime }
    var sleepTimer: SleepTimer?
    var sourceTitle: String?
    var loadingProgress = -1.0
    let resolver: MediaSourceResolver
    let positions: PlaybackPositionStore
    let recents: RecentsStore
    let toast: ToastCenter
    let nowPlaying: NowPlayingCenter
    private var backend: PlayerBackend?
    private var loading: Task<Void, Never>?
    private var sleepTask: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var notifications: [NSObjectProtocol] = []
    private var source: MediaSource?
    private var usedFallback = false
    private var metadataReady = false
    private var metadataRefreshID: String?
    private var failures = 0
    private var lastSaved = Date.distantPast
    private var wasPlaying = false
    private var pendingSeek: Double?
    init(resolver: MediaSourceResolver, positions: PlaybackPositionStore, recents: RecentsStore, toast: ToastCenter, nowPlaying: NowPlayingCenter) {
        self.resolver = resolver; self.positions = positions; self.recents = recents; self.toast = toast; self.nowPlaying = nowPlaying
        let defaults = UserDefaults.standard
        rate = (defaults.object(forKey: "audioRate") as? Float) ?? 1
        repeatMode = RepeatMode(rawValue: defaults.string(forKey: "audioRepeat") ?? "") ?? .off
        shuffle = defaults.bool(forKey: "audioShuffle")
        notifications.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt; let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor in guard let self else { return }; if type == AVAudioSession.InterruptionType.began.rawValue { self.wasPlaying = self.isPlaying; self.pause() } else if options & AVAudioSession.InterruptionOptions.shouldResume.rawValue != 0 && self.wasPlaying { self.start() } }
        })
        notifications.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt; if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { Task { @MainActor in self?.pause() } } })
    }
    func restoreSession() {
        guard let session = positions.lastSession, !session.queue.isEmpty else { return }
        queue = session.queue; originalQueue = session.originalQueue; index = min(session.index, queue.count - 1); sourceTitle = session.sourceTitle
        loadCurrent(play: false, restoreTime: session.time)
    }
    func play(_ refs: [MediaRef], startAt: Int = 0, sourceTitle: String? = nil) {
        guard !refs.isEmpty else { return }
        savePosition(); queue = refs; originalQueue = refs; index = max(0, min(startAt, refs.count - 1)); self.sourceTitle = sourceTitle; failures = 0
        if shuffle { let first = queue[index]; queue = [first] + queue.enumerated().filter { $0.offset != index }.map(\.element).shuffled(); index = 0 }
        loadCurrent(play: true)
    }
    private func loadCurrent(play: Bool, restoreTime: Double? = nil) {
        loading?.cancel(); backend?.onStateChange = nil; backend?.stop(); backend = nil; source = nil; currentTime = 0; duration = 0; state = .loading; usedFallback = false; metadataReady = false; metadataRefreshID = nil; pendingSeek = restoreTime
        guard let ref = current else { return }
        metadata[ref.id] = metadata[ref.id] ?? TrackMetadata(title: PathUtil.baseName(ref.name))
        loading = Task {
            do {
                let (source, engine) = try await resolver.resolve(ref) { self.loadingProgress = $0 }
                try Task.checkCancellation(); guard current?.id == ref.id else { return }; self.source = source
                let backend: PlayerBackend = engine == .avfoundation ? AVPlayerBackend() : VLCBackend()
                try await configure(backend, source: source, play: play)
                let meta = await MetadataLoader().load(ref, url: source.isLocal ? source.url : nil)
                guard !Task.isCancelled && current?.id == ref.id else { return }; metadata[ref.id] = meta; metadataReady = true
                if pendingSeek == nil, (meta.duration ?? 0) > 1200, resolver.settings.resumePlayback { let saved = positions.position(for: ref.id); if saved > 0 && (meta.duration ?? 0) - saved > 10 { pendingSeek = saved } }
                if let saved = pendingSeek, saved > 0 { pendingSeek = nil; await backend.seek(to: saved); currentTime = saved }
                recents.add(ref.fileItem); if !nowPlaying.ownedByVideo { nowPlaying.bind(self) }; updateNowPlaying(); savePosition()
            } catch { guard !Task.isCancelled else { return }; if backend is AVPlayerBackend && !usedFallback { await fallback(play: play) } else { failed() } }
        }
    }
    private func configure(_ backend: PlayerBackend, source: MediaSource, play: Bool) async throws {
        self.backend = backend; backend.rate = rate
        backend.onStateChange = { [weak self] newState in
            guard let self else { return }
            if case .failed = newState { if self.backend is AVPlayerBackend && !usedFallback { loading = Task { await self.fallback(play: true) } } else { failed() }; return }
            state = newState
            if newState == .playing { failures = 0 }
            if newState == .ended { ended() }
            updateNowPlaying()
        }
        backend.onTime = { [weak self] time, duration in
            guard let self else { return }; currentTime = time; self.duration = duration
            if let saved = pendingSeek, duration > 0 { pendingSeek = nil; seek(to: saved) }
            if metadataReady && self.source?.isLocal == false { refreshStreamMetadata() }
            if Date().timeIntervalSince(lastSaved) >= 5 { savePosition() }
        }
        try await backend.load(source); try Task.checkCancellation()
        if play { start() } else { state = .paused }
    }
    private func fallback(play: Bool) async {
        guard let source, !usedFallback else { failed(); return }; usedFallback = true
        backend?.onStateChange = nil; backend?.stop()
        do { try await configure(VLCBackend(), source: source, play: play) } catch { failed() }
    }
    private func refreshStreamMetadata() {
        guard let current, metadataRefreshID != current.id else { return }
        if let backend = backend as? AVPlayerBackend, let asset = backend.player.currentItem?.asset {
            metadataRefreshID = current.id
            Task { [weak self] in let result = await MetadataLoader().load(current, url: nil, asset: asset); guard let self, self.current?.id == current.id else { return }; self.metadata[current.id] = result; self.updateNowPlaying() }
        } else if let backend = backend as? VLCBackend, let media = backend.player.media, media.metaData.title != nil || media.metaData.artist != nil {
            metadataRefreshID = current.id
            metadata[current.id] = TrackMetadata(title: media.metaData.title ?? PathUtil.baseName(current.name), artist: media.metaData.artist, album: media.metaData.album, duration: backend.duration > 0 ? backend.duration : nil)
            updateNowPlaying()
        }
    }
    private func failed() {
        guard let current else { return }; toast.show("Couldn't play \"\(current.name)\"", symbol: "exclamationmark.triangle"); failures += 1
        if failures >= 3 || index + 1 >= queue.count { backend?.pause(); state = .failed("Couldn't play this file."); updateNowPlaying() }
        else { index += 1; loadCurrent(play: true) }
    }
    func start() {
        AppServices.shared.activeVideo?.close()
        do { let session = AVAudioSession.sharedInstance(); try session.setCategory(.playback, mode: .default); try session.setActive(true); backend?.play(); state = .playing; nowPlaying.bind(self); updateNowPlaying() } catch { toast.show(error: error) }
    }
    func pause() { backend?.pause(); if hasItem { state = .paused }; savePosition(); updateNowPlaying() }
    func togglePlayPause() { isPlaying ? pause() : start() }
    func seek(to time: Double) { let time = max(0, duration > 0 ? min(duration, time) : time); currentTime = time; Task { await backend?.seek(to: time); savePosition(); updateNowPlaying() } }
    func skip(by seconds: Double) { seek(to: currentTime + seconds) }
    func next() { savePosition(); if index + 1 < queue.count { index += 1; loadCurrent(play: true) } else if repeatMode == .all { index = 0; loadCurrent(play: true) } else { seek(to: 0); pause() } }
    func previous() { if currentTime > 3 { seek(to: 0) } else if index > 0 { savePosition(); index -= 1; loadCurrent(play: true) } else if repeatMode == .all { index = max(0, queue.count - 1); loadCurrent(play: true) } else { seek(to: 0) } }
    private func ended() { if case .endOfTrack = sleepTimer { fadeAndPause(); seek(to: 0) } else if repeatMode == .one { seek(to: 0); start() } else { next() } }
    func playNext(_ refs: [MediaRef]) { if queue.isEmpty { play(refs); return }; queue.insert(contentsOf: refs, at: min(index + 1, queue.count)); originalQueue.append(contentsOf: refs); savePosition() }
    func addToQueue(_ refs: [MediaRef]) { if queue.isEmpty { play(refs); return }; queue.append(contentsOf: refs); originalQueue.append(contentsOf: refs); savePosition() }
    func remove(at offsets: IndexSet) {
        let active = current; let removed = offsets.filter { queue.indices.contains($0) }.map { queue[$0] }; queue.remove(atOffsets: offsets); for ref in removed { if let at = originalQueue.firstIndex(of: ref) { originalQueue.remove(at: at) } }
        if queue.isEmpty { stop() } else if let active, let at = queue.firstIndex(of: active) { index = at; savePosition() } else { index = min(index, queue.count - 1); loadCurrent(play: true) }
    }
    func move(from offsets: IndexSet, to destination: Int) { let active = current; queue.move(fromOffsets: offsets, toOffset: destination); if let active, let at = queue.firstIndex(of: active) { index = at }; if !shuffle { originalQueue = queue }; savePosition() }
    func jump(to index: Int) { guard queue.indices.contains(index) else { return }; savePosition(); self.index = index; loadCurrent(play: true) }
    func setShuffle(_ on: Bool) {
        guard shuffle != on else { return }; let active = current; shuffle = on; UserDefaults.standard.set(on, forKey: "audioShuffle")
        if on, let active { queue = [active] + queue.enumerated().filter { $0.offset != index }.map(\.element).shuffled(); index = 0 }
        else { queue = originalQueue; index = active.flatMap { queue.firstIndex(of: $0) } ?? 0 }
        savePosition(); updateNowPlaying()
    }
    func cycleRepeat() { repeatMode = repeatMode == .off ? .all : repeatMode == .all ? .one : .off }
    func setSleep(minutes: Int?) {
        sleepTask?.cancel(); guard let minutes else { sleepTimer = nil; return }; let date = Date().addingTimeInterval(Double(minutes * 60)); sleepTimer = .minutes(date)
        sleepTask = Task { try? await Task.sleep(for: .seconds(Double(minutes * 60))); guard !Task.isCancelled else { return }; fadeAndPause() }
    }
    func sleepAtEnd() { sleepTask?.cancel(); sleepTimer = .endOfTrack }
    private func fadeAndPause() { sleepTask = Task { for step in (0..<12).reversed() { backend?.volume = Float(step) / 12; try? await Task.sleep(for: .milliseconds(250)); if Task.isCancelled { backend?.volume = 1; return } }; pause(); backend?.volume = 1; sleepTimer = nil } }
    func clearUpNext() { if index + 1 < queue.count { remove(at: IndexSet((index + 1)..<queue.count)) } }
    func stop() { savePosition(); loading?.cancel(); sleepTask?.cancel(); sleepTimer = nil; backend?.onStateChange = nil; backend?.stop(); backend = nil; queue = []; originalQueue = []; index = 0; currentTime = 0; duration = 0; state = .idle; isFullScreenPresented = false; positions.lastSession = nil; nowPlaying.clear() }
    func savePosition() { lastSaved = Date(); if let current, duration > 1200 { positions.save(current.fileItem, time: duration - currentTime < 10 ? 0 : currentTime, duration: duration) }; positions.lastSession = .init(queue: queue, originalQueue: originalQueue, index: index, time: currentTime, sourceTitle: sourceTitle) }
    func updateNowPlaying() { guard let current else { return }; nowPlaying.update(title: metadata[current.id]?.title ?? PathUtil.baseName(current.name), metadata: metadata[current.id], time: currentTime, duration: duration, rate: isPlaying ? rate : 0, defaultRate: rate) }
    deinit { for notification in notifications { NotificationCenter.default.removeObserver(notification) } }
}
