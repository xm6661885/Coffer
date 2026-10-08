import SwiftUI

@main
struct CofferApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    init() {
        let large = UIFont.preferredFont(forTextStyle: .largeTitle).fontDescriptor.withDesign(.serif) ?? UIFont.preferredFont(forTextStyle: .largeTitle).fontDescriptor
        let inline = UIFont.preferredFont(forTextStyle: .headline).fontDescriptor.withDesign(.serif) ?? UIFont.preferredFont(forTextStyle: .headline).fontDescriptor
        UINavigationBar.appearance().largeTitleTextAttributes = [.font: UIFont(descriptor: large.withSymbolicTraits(.traitBold) ?? large, size: 0)]
        UINavigationBar.appearance().titleTextAttributes = [.font: UIFont(descriptor: inline, size: 0)]
    }
    var body: some Scene {
        WindowGroup {
            RootView().tint(.pinkInk)
                .environment(AppServices.shared.favourites).environment(AppServices.shared.pictureLibrary).environment(AppServices.shared.settings).environment(AppServices.shared.registry)
                .environment(AppServices.shared.operations).environment(AppServices.shared.clipboard)
                .environment(AppServices.shared.toast).environment(AppServices.shared.recents).environment(AppServices.shared.importer).environment(AppServices.shared.positions).environment(AppServices.shared.thumbnails).environment(AppServices.shared.remoteCache).environment(AppServices.shared.transfers).environment(AppServices.shared.player).environment(AppServices.shared.musicLibrary).environment(AppServices.shared.videoLibrary).environment(AppServices.shared.playlists)
                .onOpenURL { AppServices.shared.importer.handleOpenURL($0) }
        }
    }
}
