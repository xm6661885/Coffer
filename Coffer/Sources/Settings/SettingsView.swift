import SwiftUI
struct SettingsView: View {
    @State private var actions = ViewActions()
    @Environment(AppSettings.self) private var settings
    @Environment(RemoteCache.self) private var cache
    @Environment(ThumbnailService.self) private var thumbnails
    @Environment(ToastCenter.self) private var toast
    @State private var clearing = false
    @State private var clearingThumbnails = false
    var body: some View {
        @Bindable var settings = settings
        Group {
            Form {
            Section { VStack(spacing: 8) { Image("CofferGlyph").resizable().renderingMode(.template).scaledToFit().frame(width: 48, height: 48).foregroundStyle(Color.pinkInk); Text("Coffer").font(.cofferTitle); Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "2"))").font(.cofferCaption).foregroundStyle(Color.inkSecondary) }.frame(maxWidth: .infinity).padding(.vertical, 16) }.listRowBackground(Color.clear)
            Section("Appearance") { Picker("Theme", selection: $settings.theme) { ForEach(ThemeChoice.allCases, id: \.self) { Text($0.rawValue).tag($0) } } }.listRowBackground(Color.surface)
            Section("Files") { Toggle("Show Hidden Files", isOn: $settings.showHiddenFiles); Toggle("Show File Extensions", isOn: $settings.showExtensions); Toggle("Folders on Top", isOn: $settings.foldersOnTop); Picker("Default View", selection: $settings.viewMode) { ForEach(ViewMode.allCases, id: \.self) { Text($0.rawValue).tag($0) } } }.listRowBackground(Color.surface)
            Section("Home") { Toggle("Show Recents", isOn: $settings.showRecents) }.listRowBackground(Color.surface)
            Section("Playback") {
                Toggle("Tap Audio Opens Player", isOn: $settings.tapAudioOpensPlayer)
                Picker("Skip Interval", selection: $settings.skipInterval) { ForEach([5, 10, 15, 30], id: \.self) { Text("\($0) seconds").tag($0) } }
                Picker("Long-Press Speed", selection: $settings.longPressSpeed) { ForEach([1.5, 2, 3], id: \.self) { Text("\($0.formatted())x").tag($0) } }
                Toggle("Auto Picture in Picture", isOn: $settings.autoPiP); Toggle("Play Video Audio in Background", isOn: $settings.backgroundVideoAudio); Toggle("Resume Playback", isOn: $settings.resumePlayback)
            }.listRowBackground(Color.surface)
            Section("Remote") { Toggle("Stream Remote Media", isOn: $settings.streamRemoteMedia); Toggle("Preload Next Video", isOn: $settings.preloadNextVideo); Toggle("Load Remote Thumbnails", isOn: $settings.loadRemoteThumbnails); Toggle("Video Thumbnails", isOn: $settings.loadVideoThumbnails) }.listRowBackground(Color.surface)
            Section("Library Sources") { NavigationLink("Music Sources") { MediaSourcesView(kind: .audio) }; NavigationLink("Video Sources") { MediaSourcesView(kind: .video) }; NavigationLink("Picture Sources") { MediaSourcesView(kind: .image) } }.listRowBackground(Color.surface)
            Section("Transfers") { Stepper("Simultaneous Transfers: \(settings.maxConcurrentTransfers)", value: $settings.maxConcurrentTransfers, in: 1...6); Toggle("Only on Wi-Fi", isOn: $settings.wifiOnly) }.listRowBackground(Color.surface)
            Section("Storage") { LabeledContent("Remote Cache", value: Formatters.bytes(cache.totalSize())); Picker("Cache Limit", selection: $settings.cacheLimit) { ForEach([500_000_000, 1_000_000_000, 2_000_000_000, 5_000_000_000, 10_000_000_000, 0] as [Int64], id: \.self) { limit in Text(limit == 0 ? "Unlimited" : Formatters.bytes(limit)).tag(limit) } }; Button("Clear Cache", role: .destructive) { clearing = true }; Button("Clear Thumbnails", role: .destructive) { clearingThumbnails = true } }.listRowBackground(Color.surface)
            Section("About") { NavigationLink("Licenses") { LicensesView() } }.listRowBackground(Color.surface)
        }.paperList().navigationTitle("Settings").confirmationDialog("Clear \(Formatters.bytes(cache.totalSize())) of cached files?", isPresented: $clearing, titleVisibility: .visible) { Button("Clear Cache", role: .destructive) { cache.clear(keepPinned: true); toast.show("Cache cleared", symbol: "checkmark") }; Button("Cancel", role: .cancel) { } } message: { Text("Keep offline files. Files made available offline won't be removed.") }
            .confirmationDialog("Clear thumbnails?", isPresented: $clearingThumbnails, titleVisibility: .visible) { Button("Clear Thumbnails", role: .destructive) { actions.submit { await thumbnails.clear(); toast.show("Thumbnails cleared", symbol: "checkmark") } }; Button("Cancel", role: .cancel) { } }
        }.managedTasks(actions)
    }
}
private struct MediaSourcesView: View {
    @State private var actions = ViewActions()
    let kind: FileKind
    @Environment(AppSettings.self) private var settings
    @Environment(FileProviderRegistry.self) private var registry
    @State private var adding = false
    @State private var removing: BrowserRoute?
    private var title: String { kind == .audio ? "Music Sources" : kind == .video ? "Video Sources" : "Picture Sources" }
    private var sources: [BrowserRoute] { kind == .audio ? settings.musicSources : kind == .video ? settings.videoSources : settings.pictureSources }
    var body: some View {
        List {
            Section { Label("My iPhone", systemImage: "iphone") } footer: { Text("All matching files in My iPhone are included automatically.") }.listRowBackground(Color.surface)
            Section {
                ForEach(sources, id: \.self) { route in
                    VStack(alignment: .leading, spacing: 4) { Text(registry.displayName(for: route.location)).foregroundStyle(Color.ink); Text(route.path).font(.cofferCaption).foregroundStyle(Color.inkSecondary) }
                        .swipeActions { Button("Remove", role: .destructive) { removing = route } }.listRowBackground(Color.surface)
                }
                Button("Add WebDAV Folder", systemImage: "plus") { adding = true }.disabled(registry.servers.isEmpty)
            } header: { Text("Additional Folders") } footer: { if registry.servers.isEmpty { Text("Add a WebDAV server in Files to include remote folders.") } }.listRowBackground(Color.surface)
        }.paperList().navigationTitle(title)
            .sheet(isPresented: $adding) {
                DestinationPicker(title: "Add Folder", allowedLocations: registry.locations.filter(\.isRemote)) { location, path in
                    let route = BrowserRoute(location: location, path: path)
                    if !sources.contains(route) { update(sources + [route]) }; await scan()
                }
            }
            .confirmationDialog("Remove this source?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                Button("Remove", role: .destructive) { if let removing { update(sources.filter { $0 != removing }) }; removing = nil; actions.submit { await scan() } }
                Button("Cancel", role: .cancel) { removing = nil }
            }.managedTasks(actions)
    }
    private func update(_ routes: [BrowserRoute]) { switch kind { case .audio: settings.musicSources = routes; case .video: settings.videoSources = routes; default: settings.pictureSources = routes } }
    private func scan() async { switch kind { case .audio: await AppServices.shared.musicLibrary.scan(); case .video: await AppServices.shared.videoLibrary.scan(); default: await AppServices.shared.pictureLibrary.scan() } }
}
