import Foundation

enum PlaybackState: Equatable { case idle, loading, playing, paused, buffering, ended, failed(String) }
struct MediaTrack: Identifiable, Hashable { let id: Int; let name: String }
struct MediaSource {
    let url: URL; let headers: [String: String]; let isLocal: Bool; let title: String
    let stream: RemoteVideoStream?
    init(url: URL, headers: [String: String], isLocal: Bool, title: String, stream: RemoteVideoStream? = nil) {
        self.url = url; self.headers = headers; self.isLocal = isLocal; self.title = title; self.stream = stream
    }
}
@MainActor protocol PlayerBackend: AnyObject {
    var onStateChange: ((PlaybackState) -> Void)? { get set }
    var onTime: ((Double, Double) -> Void)? { get set }
    func load(_ source: MediaSource) async throws
    func play(); func pause(); func seek(to seconds: Double) async
    var waitsForVideoFrame: Bool { get set }
    var rate: Float { get set }; var volume: Float { get set }
    var currentTime: Double { get }; var duration: Double { get }
    var audioTracks: [MediaTrack] { get }; var subtitleTracks: [MediaTrack] { get }
    func selectAudioTrack(_ id: Int?); func selectSubtitleTrack(_ id: Int?); func addExternalSubtitle(_ url: URL)
    var subtitleDelay: Double { get set }
    func stop()
}
