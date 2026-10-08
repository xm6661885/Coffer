import MediaPlayer
import UIKit

@MainActor final class NowPlayingCenter {
    private var targets: [(MPRemoteCommand, Any)] = []
    private var artworkKey: String?
    private var artwork: UIImage?
    private var artworkTask: Task<Void, Never>?
    var ownedByVideo = false
    func bind(_ player: AudioPlayer) {
        ownedByVideo = false; removeCommands()
        add(MPRemoteCommandCenter.shared().playCommand) { [weak player] _ in player?.start() }
        add(MPRemoteCommandCenter.shared().pauseCommand) { [weak player] _ in player?.pause() }
        add(MPRemoteCommandCenter.shared().togglePlayPauseCommand) { [weak player] _ in player?.togglePlayPause() }
        add(MPRemoteCommandCenter.shared().nextTrackCommand) { [weak player] _ in player?.next() }
        add(MPRemoteCommandCenter.shared().previousTrackCommand) { [weak player] _ in player?.previous() }
        add(MPRemoteCommandCenter.shared().changePlaybackPositionCommand) { [weak player] event in if let event = event as? MPChangePlaybackPositionCommandEvent { player?.seek(to: event.positionTime) } }
        let center = MPRemoteCommandCenter.shared(); center.changePlaybackRateCommand.supportedPlaybackRates = [0.5, 0.75, 1, 1.25, 1.5, 2]
        add(center.changePlaybackRateCommand) { [weak player] event in if let event = event as? MPChangePlaybackRateCommandEvent { player?.rate = event.playbackRate } }
        add(center.changeRepeatModeCommand) { [weak player] event in if let event = event as? MPChangeRepeatModeCommandEvent { player?.repeatMode = event.repeatType == .one ? .one : event.repeatType == .all ? .all : .off } }
        add(center.changeShuffleModeCommand) { [weak player] event in if let event = event as? MPChangeShuffleModeCommandEvent { player?.setShuffle(event.shuffleType != .off) } }
        center.skipForwardCommand.isEnabled = false; center.skipBackwardCommand.isEnabled = false
    }
    func add(_ command: MPRemoteCommand, handler: @escaping @MainActor (MPRemoteCommandEvent) -> Void) { command.isEnabled = true; let target = command.addTarget { event in Task { @MainActor in handler(event) }; return .success }; targets.append((command, target)) }
    func removeCommands() { for (command, target) in targets { command.removeTarget(target); command.isEnabled = false }; targets.removeAll() }
    func update(title: String, metadata: TrackMetadata? = nil, time: Double, duration: Double, rate: Float, defaultRate: Float, video: Bool = false, audioOnly: Bool = false, queueIndex: Int? = nil, queueCount: Int? = nil) {
        guard !ownedByVideo || video else { return }
        var info: [String: Any] = [MPMediaItemPropertyTitle: title, MPMediaItemPropertyPlaybackDuration: duration, MPNowPlayingInfoPropertyElapsedPlaybackTime: time, MPNowPlayingInfoPropertyPlaybackRate: rate, MPNowPlayingInfoPropertyDefaultPlaybackRate: defaultRate]
        info[MPNowPlayingInfoPropertyMediaType] = (video && !audioOnly ? MPNowPlayingInfoMediaType.video : .audio).rawValue
        if let queueIndex { info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = queueIndex }
        if let queueCount { info[MPNowPlayingInfoPropertyPlaybackQueueCount] = queueCount }
        if let artist = metadata?.artist { info[MPMediaItemPropertyArtist] = artist }; if let album = metadata?.album { info[MPMediaItemPropertyAlbumTitle] = album }
        let key = metadata?.artworkKey
        if key != artworkKey {
            artworkTask?.cancel(); artworkKey = key; artwork = nil
            if let key { let url = MetadataLoader.artworkRoot.appending(path: key); artworkTask = Task { [weak self] in
                let image = await Task.detached { UIImage(contentsOfFile: url.path) }.value
                guard let self, !Task.isCancelled, self.artworkKey == key, let image else { return }
                self.artwork = image
                if var info = MPNowPlayingInfoCenter.default().nowPlayingInfo { info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }; MPNowPlayingInfoCenter.default().nowPlayingInfo = info }
            } }
        }
        if let image = artwork { info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image } }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    func clear() { artworkTask?.cancel(); artwork = nil; artworkKey = nil; ownedByVideo = false; removeCommands(); MPNowPlayingInfoCenter.default().nowPlayingInfo = nil }
}
