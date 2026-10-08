import Foundation
import Observation

@MainActor @Observable final class AppServices {
    static let shared = AppServices()
    let settings = AppSettings()
    let registry = FileProviderRegistry()
    let clipboard = Clipboard()
    let toast = ToastCenter()
    let recents = RecentsStore()
    let favourites = FavouritesStore()
    let pictureLibrary = PictureLibrary()
    let positions = PlaybackPositionStore()
    let thumbnails = ThumbnailService()
    var activeVideo: VideoPlayerModel?
    let musicLibrary = MusicLibrary()
    let videoLibrary = VideoLibrary()
    let playlists = PlaylistStore()
    let nowPlaying = NowPlayingCenter()
    let player: AudioPlayer
    let transfers: TransferManager
    let remoteCache: RemoteCache
    let importer: ImportService
    let operations: FileOperations
    init() { transfers = TransferManager(settings: settings, registry: registry, toast: toast); remoteCache = RemoteCache(registry: registry, settings: settings, toast: toast, transfers: transfers); player = AudioPlayer(resolver: MediaSourceResolver(registry: registry, cache: remoteCache, settings: settings), positions: positions, recents: recents, toast: toast, nowPlaying: nowPlaying); operations = FileOperations(registry: registry, toast: toast, transfers: transfers); importer = ImportService(registry: registry, toast: toast) }
}
