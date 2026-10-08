import SwiftUI

struct PictureAlbumRoute: Hashable { let location: LocationID; let path: String }

extension EnvironmentValues { @Entry var pictureNamespace: Namespace.ID? = nil }

struct PictureLibraryView: View {
    @Environment(PictureLibrary.self) private var library
    @Environment(Navigator.self) private var navigator
    @State private var query = ""
    @Namespace private var namespace
    @State private var albums = false
    @AppStorage("pictureLibraryLayout") private var layout: MediaLayout = .grid
    private var entries: [MediaIndexEntry] {
        allEntries.filter { query.isEmpty || $0.item.name.localizedCaseInsensitiveContains(query) || $0.item.parentPath.localizedCaseInsensitiveContains(query) }
    }
    private var allEntries: [MediaIndexEntry] { sortedPictures(library.entries) }
    private var groups: [(folder: FileItem, entries: [MediaIndexEntry])] {
        let matches = Set(entries.map(\.id))
        return Dictionary(grouping: allEntries) { BrowserRoute(location: $0.item.location, path: $0.item.parentPath) }
            .filter { $0.value.contains { matches.contains($0.id) } }
            .map { (folder: .folder(location: $0.key.location, path: $0.key.path), entries: $0.value) }
            .sorted { $0.folder.name.localizedStandardCompare($1.folder.name) == .orderedAscending }
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Picker("Browse", selection: $albums) { Text("All Photos").tag(false); Text("Albums").tag(true) }.pickerStyle(.segmented).padding(.horizontal, 20)
                if library.isScanning && !library.entries.isEmpty || library.index.error != nil { LibraryScanStatus(index: library.index).padding(.horizontal, 20) }
                if entries.isEmpty {
                    if library.isScanning { LibraryScanStatus(index: library.index).padding(20) }
                    else { ContentUnavailableView { Label(query.isEmpty ? "No pictures yet" : "No matching pictures", systemImage: "photo.on.rectangle") } description: { Text(query.isEmpty ? "Add pictures to My iPhone or choose a picture folder in Settings." : "Try a different name.") } actions: { if query.isEmpty { Button("Open Files") { navigator.tab = .files }.buttonStyle(.glass) } } }
                } else if albums {
                    Group {
                        if layout == .list { LazyVStack(spacing: 12) { albumLinks } }
                        else { LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 20) { albumLinks } }
                    }.padding(.horizontal, 20)
                } else { PictureGrid(entries: entries, layout: layout) }
                if !entries.isEmpty { Text("\(entries.count) Pictures").font(.cofferCaption).foregroundStyle(Color.inkSecondary) }
            }.padding(.vertical, 20)
        }.background(Color.canvas).navigationTitle("Pictures").searchable(text: $query, prompt: "Search pictures")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { LibraryRefreshButton(index: library.index) }; ToolbarItem(placement: .topBarTrailing) { MediaLayoutPicker(layout: $layout) } }
            .mediaUpload(kind: .pictures)
            .refreshable { await library.scan(force: true) }.task { await library.index.scanIfNeeded() }.animation(.smooth, value: library.isScanning)
            .environment(\.pictureNamespace, namespace)
            .navigationDestination(for: PictureAlbumRoute.self) { route in
                PictureAlbumView(folder: .folder(location: route.location, path: route.path)).environment(\.pictureNamespace, namespace).navigationTransition(.automatic)
            }
            .navigationDestination(for: PreviewRoute.self) { route in PreviewRouter(route: route).navigationTransition(.zoom(sourceID: navigator.previewSourceID ?? route.item.id, in: namespace)) }
    }
    private var albumLinks: some View {
        ForEach(groups, id: \.folder.id) { group in
            NavigationLink(value: PictureAlbumRoute(location: group.folder.location, path: group.folder.path)) {
                Group {
                    if layout == .list {
                        HStack(spacing: 12) {
                            PictureTile(item: group.entries[0].item).frame(width: 56, height: 56).clipShape(.rect(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 6) {
                                MarqueeText(text: group.folder.name, style: .callout)
                                albumSummary(group)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right").foregroundStyle(Color.inkTertiary)
                        }.padding(10).background(Color.surface, in: .rect(cornerRadius: 14))
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            PictureTile(item: group.entries[0].item).clipShape(.rect(cornerRadius: 14))
                            MarqueeText(text: group.folder.name, style: .headline)
                            albumSummary(group)
                        }
                    }
                }
            }.buttonStyle(.plain).contextMenu {
                FavouriteButton(item: group.folder)
                Button("Show in Files", systemImage: "folder") { navigator.reveal(location: group.folder.location, path: group.folder.path) }
            }
        }
    }
    private func albumSummary(_ group: (folder: FileItem, entries: [MediaIndexEntry])) -> some View {
        Text("\(group.entries.count) pictures · \(AppServices.shared.registry.displayName(for: group.folder.location))").font(.cofferCaption).foregroundStyle(Color.inkSecondary).lineLimit(1)
    }
}
private struct PictureAlbumView: View {
    let folder: FileItem
    @Environment(PictureLibrary.self) private var library
    @State private var query = ""
    @AppStorage("pictureLibraryLayout") private var layout: MediaLayout = .grid
    private var visibleEntries: [MediaIndexEntry] {
        sortedPictures(library.entries.filter { $0.item.location == folder.location && $0.item.parentPath == folder.path && (query.isEmpty || $0.item.name.localizedCaseInsensitiveContains(query)) })
    }
    var body: some View {
        ScrollView {
            if visibleEntries.isEmpty {
                ContentUnavailableView(query.isEmpty ? "No pictures yet" : "No matching pictures", systemImage: "photo", description: Text(query.isEmpty ? "Upload pictures to this folder." : "Try a different picture name.")).padding(20)
            } else { PictureGrid(entries: visibleEntries, layout: layout).padding(.vertical, 12) }
        }.background(Color.canvas).navigationTitle(folder.name).navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search pictures")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { MediaLayoutPicker(layout: $layout) }
                ToolbarItem(placement: .topBarTrailing) { FavouriteButton(item: folder) }
            }.mediaUpload(kind: .pictures, destination: BrowserRoute(location: folder.location, path: folder.path))
            .refreshable { await library.scan(force: true) }
    }
}
private func sortedPictures(_ entries: [MediaIndexEntry]) -> [MediaIndexEntry] { entries.sorted { ($0.item.modified ?? $0.addedAt) > ($1.item.modified ?? $1.addedAt) } }
private struct PictureGrid: View {
    let entries: [MediaIndexEntry]
    var layout: MediaLayout = .grid
    @Environment(Navigator.self) private var navigator
    @Environment(\.pictureNamespace) private var namespace
    @Namespace private var fallbackNamespace
    var body: some View {
        Group {
            if layout == .list { LazyVStack(spacing: 12) { ForEach(entries) { pictureLink($0) } }.padding(.horizontal, 20) }
            else { LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 2)], spacing: 2) { ForEach(entries) { pictureLink($0) } } }
        }
    }
    private func pictureLink(_ entry: MediaIndexEntry) -> some View {
        NavigationLink(value: PreviewRoute(item: entry.item, siblings: entries.map(\.item))) {
            if layout == .list {
                HStack(spacing: 12) {
                    PictureTile(item: entry.item).frame(width: 56, height: 56).clipShape(.rect(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 5) {
                        MarqueeText(text: entry.item.name, style: .callout)
                        Text(Formatters.bytes(entry.item.size)).font(.cofferCaption).foregroundStyle(Color.inkSecondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(10).background(Color.surface, in: .rect(cornerRadius: 14))
            } else { PictureTile(item: entry.item) }
        }.buttonStyle(.plain).matchedTransitionSource(id: entry.item.id, in: namespace ?? fallbackNamespace).contextMenu {
            FavouriteButton(item: entry.item)
            Button("Show in Files", systemImage: "folder") { navigator.revealFile(entry.item) }
        }
    }
}
private struct PictureTile: View {
    let item: FileItem
    @Environment(ThumbnailService.self) private var thumbnails
    @State private var image: UIImage?
    var body: some View {
        Color.surfaceSunken.aspectRatio(1, contentMode: .fit).overlay { GeometryReader { geometry in
            if let image { Image(uiImage: image).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped() }
            else { Image(systemName: "photo").foregroundStyle(Color.inkTertiary).frame(width: geometry.size.width, height: geometry.size.height) }
        } }.clipped().accessibilityLabel(item.name).task(id: item.id) { image = await thumbnails.thumbnail(for: item, size: 240) }
    }
}
