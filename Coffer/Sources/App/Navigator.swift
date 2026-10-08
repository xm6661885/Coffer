import SwiftUI
import Observation

@MainActor @Observable final class Navigator {
    var tab = AppTab.files
    var filesPath = NavigationPath()
    var showTransfers = false
    var thumbnailItem: FileItem?
    /// The photo currently paged to in an image preview, so the zoom transition closes onto its thumbnail.
    var previewSourceID: String?
    var videoPresented = false
    var playlistItems: [MediaRef] = []
    var editorItem: FileItem?
    var editorDraftID: String?
    func newDocument(_ item: FileItem) { editorDraftID = item.id; editorItem = item }
    func openFavourite(_ item: FileItem) {
        tab = .files
        if item.isDirectory { reveal(location: item.location, path: item.path) }
        else { reveal(location: item.location, path: item.parentPath); open(item, siblings: [item]) }
    }
    var highlightID: String?
    func reveal(location: LocationID, path: String) {
        tab = .files
        var navigation = NavigationPath()
        navigation.append(BrowserRoute(location: location, path: "/"))
        var dir = "/"
        for component in PathUtil.components(path) { dir = PathUtil.join(dir, component); navigation.append(BrowserRoute(location: location, path: dir)) }
        withAnimation(.smooth) { filesPath = navigation }
    }
    func openVideo(_ refs: [MediaRef], index: Int = 0) { guard !refs.isEmpty else { return }; AppServices.shared.activeVideo?.close(); AppServices.shared.activeVideo = VideoPlayerModel(playlist: refs, index: index, navigator: self, services: AppServices.shared); videoPresented = true }
    func revealFile(_ item: FileItem) { reveal(location: item.location, path: item.parentPath); highlightID = item.id }
    func open(_ item: FileItem, siblings: [FileItem]) {
        if item.isDirectory { filesPath.append(BrowserRoute(location: item.location, path: item.path)) }
        else if item.kind == .audio { let audio = siblings.filter { $0.kind == .audio }; let refs = (audio.isEmpty ? [item] : audio).map(MediaRef.init); AppServices.shared.player.play(refs, startAt: refs.firstIndex(of: MediaRef(item)) ?? 0, sourceTitle: item.parentPath == "/" ? AppServices.shared.registry.displayName(for: item.location) : PathUtil.name(item.parentPath)); if AppServices.shared.settings.tapAudioOpensPlayer { AppServices.shared.player.isFullScreenPresented = true } }
        else if item.kind == .video { let videos = siblings.filter { $0.kind == .video }; let refs = (videos.isEmpty ? [item] : videos).map(MediaRef.init); openVideo(refs, index: refs.firstIndex(of: MediaRef(item)) ?? 0) }
        else { filesPath.append(PreviewRoute(item: item, siblings: siblings)) }
    }
}
