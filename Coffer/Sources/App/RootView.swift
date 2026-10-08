import SwiftUI

enum AppTab: Hashable { case files, tools }
struct RootView: View {
    @State private var navigator = Navigator()
    @Namespace private var playerNamespace
    @Namespace private var filesNamespace
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AudioPlayer.self) private var player
    @Environment(TransferManager.self) private var transfers
    @Environment(AppSettings.self) private var settings
    @Environment(FileOperations.self) private var operations
    @Environment(ImportService.self) private var importer
    @Environment(ToastCenter.self) private var toast
    var body: some View {
        @Bindable var player = player
        @Bindable var importer = importer
        TabView(selection: Binding(get: { navigator.tab }, set: { value in if value == .files && navigator.tab == .files { navigator.filesPath = NavigationPath() }; navigator.tab = value })) {
            Tab("Files", systemImage: "folder", value: AppTab.files) {
                NavigationStack(path: $navigator.filesPath) {
                    HomeView(namespace: filesNamespace).navigationDestination(for: BrowserRoute.self) { BrowserView(route: $0, namespace: filesNamespace) }
                        .navigationDestination(for: PreviewRoute.self) { route in PreviewRouter(route: route).navigationTransition(.zoom(sourceID: navigator.previewSourceID ?? route.item.id, in: filesNamespace)) }
                }
            }
            Tab("Tools", systemImage: "square.grid.2x2", value: AppTab.tools) { NavigationStack { ToolsView() } }
        }.tabViewBottomAccessory(isEnabled: player.hasItem || AppServices.shared.activeVideo?.isMinimized == true) {
            if let video = AppServices.shared.activeVideo, video.isMinimized { VideoMiniPlayerView(model: video) }
            else { MiniPlayerView(namespace: playerNamespace) }
        }.tabBarMinimizeBehavior(.onScrollDown)
            .task { importer.onReveal = { navigator.reveal(location: .local, path: $0) }; transfers.onShow = { navigator.showTransfers = true }; await AppServices.shared.registry.load(); await transfers.load(); await AppServices.shared.remoteCache.load(); AppServices.shared.registry.onRemove = { transfers.cancel(location: $0); AppServices.shared.remoteCache.remove(location: $0) }; await AppServices.shared.favourites.load(); await AppServices.shared.recents.load(); await AppServices.shared.positions.load(); await AppServices.shared.playlists.load(); await AppServices.shared.musicLibrary.load(); await AppServices.shared.videoLibrary.load(); await AppServices.shared.pictureLibrary.load(); try? await Task.sleep(for: .seconds(3)); await AppServices.shared.musicLibrary.scan(); await AppServices.shared.videoLibrary.scan(); await AppServices.shared.pictureLibrary.scan() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .inactive { AppServices.shared.activeVideo?.prepareForBackground() }
                else { transfers.setBackground(phase == .background); AppServices.shared.activeVideo?.setBackground(phase == .background) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .cofferDirectoryChanged)) { notification in
                guard let location = notification.userInfo?["location"] as? LocationID,
                      let path = notification.userInfo?["path"] as? String else { return }
                for index in [AppServices.shared.musicLibrary.index, AppServices.shared.videoLibrary.index, AppServices.shared.pictureLibrary.index] {
                    let sources = index.kind == .audio ? settings.musicSources : index.kind == .image ? settings.pictureSources : settings.videoSources
                    if location == .local || sources.contains(where: { $0.location == location && (PathUtil.isAncestor($0.path, of: path) || PathUtil.isAncestor(path, of: $0.path)) }) { index.requestRefresh() }
                }
            }
            .onChange(of: settings.backgroundVideoAudio) { _, enabled in AppServices.shared.activeVideo?.setBackgroundAudioEnabled(enabled) }
            .onChange(of: settings.preloadNextVideo) { _, _ in AppServices.shared.activeVideo?.updatePreloading() }
            .onChange(of: settings.streamRemoteMedia) { _, _ in AppServices.shared.activeVideo?.updatePreloading() }
            .onChange(of: settings.autoPiP) { _, _ in AppServices.shared.activeVideo?.updateAutomaticPictureInPicture() }
            .sheet(isPresented: Binding(get: { !navigator.playlistItems.isEmpty && !player.isFullScreenPresented && !navigator.videoPresented }, set: { if !$0 { navigator.playlistItems = [] } })) { AddToPlaylistSheet(refs: navigator.playlistItems) }
            .sheet(item: $navigator.thumbnailItem) { VideoThumbnailPreview(item: $0) }
            .sheet(isPresented: $navigator.showTransfers) { TransfersView() }
            .sheet(item: $importer.pending, onDismiss: { importer.cancelPending() }) { pending in ImportSheet(urls: pending.urls) }
            .overlay { if let video = AppServices.shared.activeVideo, video.isPiP && !navigator.videoPresented { VideoSurface(model: video).frame(width: 1, height: 1).allowsHitTesting(false) } }
            .fullScreenCover(isPresented: $navigator.videoPresented, onDismiss: { let video = AppServices.shared.activeVideo; video?.presentationDismissed(); if !navigator.videoPresented { OrientationController.restoreAppOrientation(); if video?.isClosed == true && AppServices.shared.activeVideo === video { AppServices.shared.activeVideo = nil } } }) { if let video = AppServices.shared.activeVideo { VideoPlayerView(model: video) } }
            .fullScreenCover(isPresented: $player.isFullScreenPresented) { MusicPlayerView().navigationTransition(.zoom(sourceID: "nowPlaying", in: playerNamespace)) }
            .fullScreenCover(item: $navigator.editorItem, onDismiss: { navigator.editorDraftID = nil }) { TextEditorView(item: $0, isDraft: navigator.editorDraftID == $0.id) }
            .preferredColorScheme(settings.theme.colorScheme)
            .overlay(alignment: .top) { if let message = toast.current { ToastView(toast: message, dismiss: toast.dismiss).transition(.move(edge: .top).combined(with: .opacity)) } }
            .sensoryFeedback(.success, trigger: toast.successTrigger)
            .fileConflictDialog(inPicker: false)
            // Presentation modifiers must inherit the same navigator as the tabs.
            .environment(navigator)
    }
}
