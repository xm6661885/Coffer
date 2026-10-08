import SwiftUI

struct VideoLibraryView: View {
    enum Sort: String, CaseIterable { case added = "Recently Added", name = "Name", duration = "Duration", size = "Size" }
    @Environment(VideoLibrary.self) private var library
    @Environment(Navigator.self) private var navigator
    @State private var query = ""
    @State private var folders = false
    @State private var sort: Sort = .added
    @AppStorage("videoLibraryLayout") private var layout: MediaLayout = .grid
    private var entries: [MediaIndexEntry] { sortedVideos(library.entries.filter { query.isEmpty || $0.item.name.localizedCaseInsensitiveContains(query) }, by: sort) }
    private var groups: [(folder: FileItem, entries: [MediaIndexEntry])] {
        let matches = Set(entries.map(\.id))
        return Dictionary(grouping: sortedVideos(library.entries, by: sort)) { BrowserRoute(location: $0.item.location, path: $0.item.parentPath) }
            .filter { $0.value.contains { matches.contains($0.id) } }
            .map { (folder: .folder(location: $0.key.location, path: $0.key.path), entries: $0.value) }
            .sorted { folderTitle($0.folder).localizedStandardCompare(folderTitle($1.folder)) == .orderedAscending }
    }
    private func folderTitle(_ folder: FileItem) -> String { AppServices.shared.registry.displayName(for: folder.location) + " › " + folder.path }
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Picker("Browse", selection: $folders) { Text("All").tag(false); Text("Folders").tag(true) }.pickerStyle(.segmented)
                if library.isScanning && !library.entries.isEmpty || library.index.error != nil { LibraryScanStatus(index: library.index) }
                if entries.isEmpty {
                    if library.entries.isEmpty {
                        if library.isScanning { LibraryScanStatus(index: library.index).padding(.vertical, 20) }
                        else {
                            ContentUnavailableView { Label("No videos yet", systemImage: "film") } description: {
                                Text("Add videos to My iPhone or choose a WebDAV video folder in Settings.")
                            } actions: { Button("Open Files") { navigator.tab = .files }.buttonStyle(.glass) }
                        }
                    } else { ContentUnavailableView("No matching videos", systemImage: "magnifyingglass", description: Text("Try a different video name.")) }
                } else if folders {
                    if layout == .list { LazyVStack(spacing: 12) { folderLinks } }
                    else { LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 16) { folderLinks } }
                } else { VideoGridView(entries: entries, layout: layout) }
                PlaylistSection(kind: .video, query: query)
            }.padding(20)
        }.background(Color.canvas).navigationTitle("Videos").searchable(text: $query, prompt: "Search videos and playlists")
            .refreshable { await library.scan(force: true) }.task { await library.index.scanIfNeeded() }.animation(.smooth, value: library.isScanning)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { LibraryRefreshButton(index: library.index) }; ToolbarItem(placement: .topBarTrailing) { MediaLayoutPicker(layout: $layout) }
                ToolbarItem(placement: .topBarTrailing) { Menu("Sort", systemImage: "arrow.up.arrow.down") { Picker("Sort", selection: $sort) { ForEach(Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) } } } }
            }.mediaUpload(kind: .videos)
    }
    private var folderLinks: some View {
        ForEach(groups, id: \.folder.id) { group in
            NavigationLink { VideoFolderView(folder: group.folder, title: folderTitle(group.folder), sort: sort) } label: {
                Group {
                    if layout == .list {
                        HStack {
                            Image(systemName: "folder").foregroundStyle(Color.pinkInk)
                            VStack(alignment: .leading, spacing: 4) { MarqueeText(text: folderTitle(group.folder)); Text("\(group.entries.count) videos").font(.cofferCaption).foregroundStyle(Color.inkSecondary) }.frame(maxWidth: .infinity, alignment: .leading)
                            Spacer(minLength: 8); Image(systemName: "chevron.right").foregroundStyle(Color.inkTertiary)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Image(systemName: "folder.fill").font(.system(size: 48)).foregroundStyle(Color.pinkInk).frame(maxWidth: .infinity, minHeight: 80)
                            MarqueeText(text: group.folder.name, style: .callout)
                            Text("\(group.entries.count) videos").font(.cofferCaption).foregroundStyle(Color.inkSecondary)
                        }
                    }
                }.padding(16).background(Color.surface, in: .rect(cornerRadius: 14))
            }.buttonStyle(.plain).contextMenu {
                FavouriteButton(item: group.folder)
                Button("Show in Files", systemImage: "folder") { navigator.reveal(location: group.folder.location, path: group.folder.path) }
            }
        }
    }
}
private struct VideoFolderView: View {
    let folder: FileItem
    let title: String
    let sort: VideoLibraryView.Sort
    @Environment(VideoLibrary.self) private var library
    @State private var query = ""
    @AppStorage("videoLibraryLayout") private var layout: MediaLayout = .grid
    private var visibleEntries: [MediaIndexEntry] {
        sortedVideos(library.entries.filter { $0.item.location == folder.location && $0.item.parentPath == folder.path && (query.isEmpty || $0.item.name.localizedCaseInsensitiveContains(query)) }, by: sort)
    }
    var body: some View {
        ScrollView {
            if visibleEntries.isEmpty {
                ContentUnavailableView(query.isEmpty ? "No videos yet" : "No matching videos", systemImage: "film", description: Text(query.isEmpty ? "Upload videos to this folder." : "Try a different video name.")).padding(20)
            } else { VideoGridView(entries: visibleEntries, layout: layout).padding(20) }
        }.background(Color.canvas).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search videos")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { MediaLayoutPicker(layout: $layout) } }
            .mediaUpload(kind: .videos, destination: BrowserRoute(location: folder.location, path: folder.path))
            .refreshable { await library.scan(force: true) }
    }
}
private func sortedVideos(_ entries: [MediaIndexEntry], by sort: VideoLibraryView.Sort) -> [MediaIndexEntry] {
    entries.sorted { a, b in switch sort { case .added: a.addedAt > b.addedAt; case .name: a.item.name.localizedStandardCompare(b.item.name) == .orderedAscending; case .duration: (a.metadata.duration ?? 0) > (b.metadata.duration ?? 0); case .size: (a.item.size ?? 0) > (b.item.size ?? 0) } }
}
struct VideoGridView: View {
    let entries: [MediaIndexEntry]
    var layout: MediaLayout = .grid
    @Environment(Navigator.self) private var navigator
    @Environment(PlaybackPositionStore.self) private var positions
    @State private var info: FileItem?
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    private var columns: [GridItem] { if typeSize.isAccessibilitySize { return [GridItem(.flexible())] }; return sizeClass == .compact ? [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)] : [GridItem(.adaptive(minimum: 170), spacing: 20)] }
    var body: some View {
        Group {
            if layout == .list { LazyVStack(spacing: 12) { ForEach(entries) { entryButton($0) } } }
            else { LazyVGrid(columns: columns, spacing: 20) { ForEach(entries) { entryButton($0) } } }
        }.sheet(item: $info) { InfoSheet(item: $0) }
    }
    private func entryButton(_ entry: MediaIndexEntry) -> some View {
        Button { navigator.openVideo(entries.map(\.ref), index: entries.firstIndex(where: { $0.id == entry.id }) ?? 0) } label: { VideoCard(entry: entry, layout: layout) }
            .buttonStyle(.plain).contextMenu {
                FavouriteButton(item: entry.item); VideoThumbnailButton(item: entry.item)
                Button("Play", systemImage: "play.fill") { navigator.openVideo(entries.map(\.ref), index: entries.firstIndex(where: { $0.id == entry.id }) ?? 0) }
                Button("Play from Beginning") { positions.remove(entry.id); navigator.openVideo([entry.ref]) }
                Button("Add to Playlist…", systemImage: "text.badge.plus") { navigator.playlistItems = [entry.ref] }
                Button("Mark as Watched", systemImage: "checkmark") { positions.remove(entry.id) }
                Button("Show in Files", systemImage: "folder") { navigator.revealFile(entry.item) }
                Button("Get Info", systemImage: "info.circle") { info = entry.item }
            }
    }
}
struct VideoCard: View {
    let entry: MediaIndexEntry
    var layout: MediaLayout = .grid
    @Environment(ThumbnailService.self) private var thumbnails
    @Environment(AppSettings.self) private var settings
    @Environment(PlaybackPositionStore.self) private var positions
    @State private var image: UIImage?
    var body: some View {
        Group {
            if layout == .list {
                HStack(spacing: 12) {
                    thumbnail.frame(width: 112)
                    VStack(alignment: .leading, spacing: 6) {
                        MarqueeText(text: entry.item.name, style: .callout)
                        Text(Formatters.bytes(entry.item.size)).font(.cofferCaption).foregroundStyle(Color.inkSecondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(10).background(Color.surface, in: .rect(cornerRadius: 14))
            } else {
                VStack(alignment: .leading, spacing: 8) { thumbnail; MarqueeText(text: entry.item.name, style: .caption1) }
            }
        }.task(id: entry.id + "-\(settings.loadVideoThumbnails)-\(settings.loadRemoteThumbnails)") { image = await thumbnails.thumbnail(for: entry.item, size: 480) }
    }
    private var thumbnail: some View {
        Color.surfaceSunken.aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay { GeometryReader { geometry in
                if let image { Image(uiImage: image).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped() }
                else { Image(systemName: "film").foregroundStyle(Color.inkTertiary).frame(width: geometry.size.width, height: geometry.size.height) }
            } }
            .overlay(alignment: .bottomTrailing) { if let duration = entry.metadata.duration { Text(Formatters.duration(duration)).font(.cofferTimecode).padding(4).glassEffect(.regular, in: .capsule).padding(4) } }
            .clipShape(.rect(cornerRadius: 14))
            .overlay(alignment: .bottom) { if let record = positions.records[entry.id] { ProgressBar(value: record.time / max(1, record.duration), height: 3) } }
    }
}
