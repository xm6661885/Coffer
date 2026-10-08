import SwiftUI
struct MusicLibraryView: View {
    enum Mode: String, CaseIterable { case songs = "Songs", albums = "Albums", artists = "Artists", folders = "Folders" }
    @Environment(MusicLibrary.self) private var library
    @Environment(AudioPlayer.self) private var player
    @Environment(Navigator.self) private var navigator
    @State private var query = ""
    @State private var mode: Mode = .songs
    private var entries: [MediaIndexEntry] { library.entries.filter { query.isEmpty || ($0.metadata.title + ($0.metadata.artist ?? "") + ($0.metadata.album ?? "")).localizedCaseInsensitiveContains(query) }.sorted { $0.metadata.title.localizedStandardCompare($1.metadata.title) == .orderedAscending } }
    var body: some View {
        List {
            Section {
                Picker("Browse", selection: $mode) { ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                if mode == .songs && !entries.isEmpty { PlayButtons(refs: entries.map(\.ref), title: "Music") }
                if library.isScanning && !library.entries.isEmpty || library.index.error != nil { LibraryScanStatus(index: library.index) }
            }.listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20)).listRowBackground(Color.clear).listRowSeparator(.hidden)
            if entries.isEmpty {
                Section {
                    if library.entries.isEmpty {
                        if library.isScanning { LibraryScanStatus(index: library.index).padding(.vertical, 20) }
                        else {
                            ContentUnavailableView { Label("No music yet", systemImage: "music.note") } description: {
                                Text("Add audio files to My iPhone or choose a WebDAV music folder in Settings.")
                            } actions: { Button("Open Files") { navigator.tab = .files }.buttonStyle(.glass) }
                        }
                    } else { ContentUnavailableView("No matching songs", systemImage: "magnifyingglass", description: Text("Try a different song, artist, or album.")) }
                }.listRowBackground(Color.clear).listRowSeparator(.hidden)
            } else {
                libraryContents
            }
            PlaylistSection(kind: .music, query: query, inList: true)
        }.paperList().listSectionSpacing(12).navigationTitle("Music").searchable(text: $query, prompt: "Search songs, artists, albums, playlists").refreshable { await library.scan(force: true) }.task { await library.index.scanIfNeeded() }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { LibraryRefreshButton(index: library.index) } }
            .animation(.smooth, value: library.isScanning)
            .mediaUpload(kind: .music)
            .onChange(of: player.metadata) { _, value in library.index.backfill(value) }
    }
    @ViewBuilder private var libraryContents: some View {
        switch mode {
        case .songs:
            Section { ForEach(entries) { entry in SongLibraryRow(entry: entry, refs: entries.map(\.ref), sourceTitle: "Music") } }.listRowBackground(Color.canvas)
        case .albums:
            Section { LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                ForEach(groups, id: \.id) { group in
                    NavigationLink { LibrarySongList(title: group.title, entries: group.value, album: true) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            ArtworkView(key: group.value.first?.metadata.artworkKey, size: 140).clipShape(.rect(cornerRadius: 14))
                            MarqueeText(text: group.title, style: .callout)
                            Text(group.value.first?.metadata.artist ?? "Unknown Artist").font(.cofferCaption).foregroundStyle(Color.inkSecondary).lineLimit(1)
                        }
                    }
                }
            } }.listRowBackground(Color.canvas)
        case .artists, .folders:
            Section { ForEach(groups, id: \.id) { group in
                NavigationLink { LibrarySongList(title: group.title, entries: group.value, folder: mode == .folders ? group.value.first.map { BrowserRoute(location: $0.item.location, path: $0.item.parentPath) } : nil) } label: {
                    VStack(alignment: .leading) {
                        MarqueeText(text: group.title)
                        Text("\(group.value.count) songs").font(.cofferCaption).foregroundStyle(Color.inkSecondary)
                    }
                }.contextMenu { if mode == .folders, let first = group.value.first { FavouriteButton(item: .folder(location: first.item.location, path: first.item.parentPath)) } }
            } }.listRowBackground(Color.canvas)
        }
    }
    private var groups: [(id: String, title: String, value: [MediaIndexEntry])] {
        let grouped = Dictionary(grouping: entries, by: groupKey)
        var result: [(id: String, title: String, value: [MediaIndexEntry])] = []
        for (key, items) in grouped {
            let title: String
            if mode == .albums { title = items.first?.metadata.album ?? "Unknown Album" }
            else if mode == .folders, let item = items.first?.item { title = AppServices.shared.registry.displayName(for: item.location) + " › " + (item.parentPath == "/" ? "Root" : item.parentPath) }
            else { title = key }
            let sorted = library.entries.filter { groupKey($0) == key }.sorted(by: trackOrder)
            result.append((id: key, title: title, value: sorted))
        }
        return result.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    private func groupKey(_ entry: MediaIndexEntry) -> String {
        switch mode {
        case .albums: (entry.metadata.album ?? "Unknown Album") + "\u{001F}" + (entry.metadata.artist ?? "Unknown Artist")
        case .artists: entry.metadata.artist ?? "Unknown Artist"
        default: entry.item.location.key + "\u{001F}" + entry.item.parentPath
        }
    }
    private func trackOrder(_ a: MediaIndexEntry, _ b: MediaIndexEntry) -> Bool {
        if mode == .albums && a.metadata.trackNumber != b.metadata.trackNumber { return (a.metadata.trackNumber ?? Int.max) < (b.metadata.trackNumber ?? Int.max) }
        return a.item.name.localizedStandardCompare(b.item.name) == .orderedAscending
    }
}
struct LibrarySongList: View {
    let title: String
    let entries: [MediaIndexEntry]
    var album = false
    var folder: BrowserRoute? = nil
    @Environment(MusicLibrary.self) private var library
    @AppStorage("musicFolderLayout") private var layout: MediaLayout = .list
    @State private var query = ""
    private var currentEntries: [MediaIndexEntry] {
        library.entries.filter { entry in
            if let folder { return entry.item.location == folder.location && entry.item.parentPath == folder.path }
            if album { return (entry.metadata.album ?? "Unknown Album") == title && (entry.metadata.artist ?? "Unknown Artist") == (entries.first?.metadata.artist ?? "Unknown Artist") }
            return (entry.metadata.artist ?? "Unknown Artist") == title
        }.sorted { a, b in
            if album && a.metadata.trackNumber != b.metadata.trackNumber { return (a.metadata.trackNumber ?? Int.max) < (b.metadata.trackNumber ?? Int.max) }
            return a.item.name.localizedStandardCompare(b.item.name) == .orderedAscending
        }
    }
    private var visibleEntries: [MediaIndexEntry] {
        currentEntries.filter {
            query.isEmpty || ($0.item.name + " " + $0.metadata.title + " " + ($0.metadata.artist ?? "") + " " + ($0.metadata.album ?? "")).localizedCaseInsensitiveContains(query)
        }
    }
    var body: some View {
        List {
            if album {
                Section {
                    VStack(spacing: 12) {
                        ArtworkView(key: entries.first?.metadata.artworkKey, size: 160).clipShape(.rect(cornerRadius: 22))
                        Text(title).font(.cofferTitle).foregroundStyle(Color.ink)
                        Text(entries.first?.metadata.artist ?? "Unknown Artist").foregroundStyle(Color.inkSecondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 20)
                }.listRowBackground(Color.clear)
            }
            if visibleEntries.isEmpty {
                Section {
                    ContentUnavailableView(query.isEmpty ? "No songs yet" : "No matching songs", systemImage: "music.note", description: Text(query.isEmpty ? "Upload audio files to this folder." : "Try a different song, artist, or album."))
                }.listRowBackground(Color.clear).listRowSeparator(.hidden)
            } else {
                Section { PlayButtons(refs: visibleEntries.map(\.ref), title: title) }
                    .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
                Section {
                    if layout == .list {
                        ForEach(visibleEntries) { entry in SongLibraryRow(entry: entry, refs: visibleEntries.map(\.ref), sourceTitle: title) }
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 20) {
                            ForEach(visibleEntries) { entry in SongLibraryRow(entry: entry, refs: visibleEntries.map(\.ref), sourceTitle: title, grid: true) }
                        }.padding(.vertical, 8)
                    }
                }.listRowBackground(Color.canvas)
            }
        }.paperList().listSectionSpacing(12).navigationTitle(title)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search songs, artists, albums")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { MediaLayoutPicker(layout: $layout) } }
            .mediaUpload(kind: .music, destination: folder)
            .refreshable { await library.scan(force: true) }
    }
}
struct SongLibraryRow: View {
    let entry: MediaIndexEntry; let refs: [MediaRef]; let sourceTitle: String
    var grid = false
    @Environment(AudioPlayer.self) private var player
    @Environment(Navigator.self) private var navigator
    @State private var info = false
    var body: some View {
        Button { player.play(refs, startAt: refs.firstIndex(of: entry.ref) ?? 0, sourceTitle: sourceTitle) } label: {
            Group {
                if grid {
                    VStack(alignment: .leading, spacing: 8) {
                        ArtworkView(key: entry.metadata.artworkKey, size: 120).clipShape(.rect(cornerRadius: 14)).frame(maxWidth: .infinity)
                        MarqueeText(text: entry.metadata.title, style: .callout, color: player.current?.id == entry.id ? .pinkInk : .ink)
                        MarqueeText(text: entry.metadata.artist ?? "Unknown Artist", style: .caption1, color: .inkSecondary)
                    }
                } else {
                    HStack(spacing: 12) {
                        ArtworkView(key: entry.metadata.artworkKey, size: 44).clipShape(.rect(cornerRadius: 6)).overlay { if player.current?.id == entry.id { Image(systemName: "waveform").foregroundStyle(Color.pinkInk).symbolEffect(.variableColor, isActive: player.isPlaying) } }
                        VStack(alignment: .leading, spacing: 4) {
                            MarqueeText(text: entry.metadata.title, color: player.current?.id == entry.id ? .pinkInk : .ink)
                            Text((entry.metadata.artist ?? "Unknown Artist") + " · " + (entry.metadata.album ?? "Unknown Album")).font(.cofferCaption).foregroundStyle(Color.inkSecondary).lineLimit(1)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        if let duration = entry.metadata.duration { Text(Formatters.duration(duration)).font(.cofferTimecode).foregroundStyle(Color.inkSecondary) }
                    }.frame(minHeight: 56)
                }
            }
        }.buttonStyle(.plain).contextMenu {
            FavouriteButton(item: entry.item)
            Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") { player.playNext([entry.ref]) }; Button("Add to Queue", systemImage: "text.badge.plus") { player.addToQueue([entry.ref]) }; Button("Add to Playlist…", systemImage: "music.note.list") { navigator.playlistItems = [entry.ref] }; Button("Show in Files", systemImage: "folder") { navigator.revealFile(entry.item) }; Button("Get Info", systemImage: "info.circle") { info = true }
        }.sheet(isPresented: $info) { InfoSheet(item: entry.item) }
    }
}
struct PlayButtons: View {
    let refs: [MediaRef]; let title: String; var video = false
    @Environment(AudioPlayer.self) private var player
    @Environment(Navigator.self) private var navigator
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        Group {
            if typeSize.isAccessibilitySize { VStack(spacing: 8) { playButton; shuffleButton } }
            else { HStack(spacing: 8) { playButton; shuffleButton } }
        }.font(.subheadline.weight(.semibold)).controlSize(.regular).frame(maxWidth: .infinity).disabled(refs.isEmpty)
    }
    private var playButton: some View {
        Button { play(shuffle: false) } label: {
            Label("Play", systemImage: "play.fill").foregroundStyle(Color.onPink).frame(maxWidth: .infinity)
        }.buttonStyle(.glassProminent).tint(.pink).buttonBorderShape(.capsule).frame(maxWidth: .infinity)
    }
    private var shuffleButton: some View {
        Button { play(shuffle: true) } label: {
            Label("Shuffle", systemImage: "shuffle").frame(maxWidth: .infinity)
        }.buttonStyle(.glass).buttonBorderShape(.capsule).frame(maxWidth: .infinity)
    }
    private func play(shuffle: Bool) { if video { navigator.openVideo(shuffle ? refs.shuffled() : refs) } else { player.setShuffle(shuffle); player.play(refs, sourceTitle: title) } }
}
