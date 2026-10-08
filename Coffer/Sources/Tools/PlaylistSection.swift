import SwiftUI

struct PlaylistSection: View {
    var kind: Playlist.Kind? = nil
    var query = ""
    var inList = false
    @Environment(PlaylistStore.self) private var store
    @Environment(AudioPlayer.self) private var player
    @Environment(Navigator.self) private var navigator
    @State private var creating = false
    @State private var renaming: Playlist?
    @State private var deleting: Playlist?
    private var playlists: [Playlist] {
        store.playlists.filter { (kind == nil || $0.kind == kind) && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }
    }
    var body: some View {
        Group {
            if inList {
                Section {
                    if playlists.isEmpty { emptyCard.listRowBackground(Color.clear) }
                    playlistRows
                } header: { header.textCase(nil) }
                .listRowBackground(Color.surface)
            } else {
                VStack(spacing: 12) {
                    header
                    if playlists.isEmpty { emptyCard }
                    playlistRows
                }
            }
        }
        .sheet(isPresented: $creating) {
            PlaylistNameSheet(kind: kind ?? .music, allowsKindSelection: kind == nil) { name, selectedKind in
                _ = store.create(name: name, kind: kind ?? selectedKind)
            }
        }
        .sheet(item: $renaming) { playlist in
            PlaylistNameSheet(playlist: playlist) { name, _ in store.rename(playlist.id, to: name) }
        }
        .confirmationDialog("Delete \"\(deleting?.name ?? "")\"?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete Playlist", role: .destructive) { if let deleting { store.delete(deleting.id) }; deleting = nil }
            Button("Cancel", role: .cancel) { deleting = nil }
        }
    }
    private var header: some View {
        HStack {
            SectionHeader(title: "Playlists")
            GlassIconButton(title: "New Playlist", symbol: "plus") { creating = true }.controlSize(.small)
        }
    }
    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(query.isEmpty ? emptyMessage : "No matching playlists").foregroundStyle(Color.inkSecondary)
            Button("New Playlist") { creating = true }.buttonStyle(.glass)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Color.surface, in: .rect(cornerRadius: 14))
    }
    private var playlistRows: some View {
        ForEach(playlists) { playlist in
            NavigationLink { PlaylistDetailView(id: playlist.id) } label: {
                HStack(spacing: 12) {
                    PlaylistArtwork(playlist: playlist, size: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(playlist.name).foregroundStyle(Color.ink)
                        Text(playlistSummary(playlist)).font(.cofferCaption).foregroundStyle(Color.inkSecondary)
                    }
                    Spacer()
                    if !inList { Image(systemName: "chevron.right").foregroundStyle(Color.inkTertiary) }
                }.padding(inList ? 0 : 12).background(inList ? Color.clear : Color.surface, in: .rect(cornerRadius: 14))
            }.buttonStyle(.plain).contextMenu {
                Button("Play", systemImage: "play.fill") { play(playlist, shuffle: false) }.disabled(playlist.items.isEmpty)
                Button("Shuffle", systemImage: "shuffle") { play(playlist, shuffle: true) }.disabled(playlist.items.isEmpty)
                Button("Rename", systemImage: "pencil") { renaming = playlist }
                Button("Delete", systemImage: "trash", role: .destructive) { deleting = playlist }
            }
        }
    }
    private var emptyMessage: String {
        switch kind {
        case .music: "Create a playlist to group songs from anywhere, including WebDAV."
        case .video: "Create a playlist to group videos from anywhere, including WebDAV."
        case nil: "Create a playlist to group songs or videos from anywhere, including WebDAV."
        }
    }
    private func play(_ playlist: Playlist, shuffle: Bool) {
        if playlist.kind == .video { navigator.openVideo(shuffle ? playlist.items.shuffled() : playlist.items) }
        else { player.setShuffle(shuffle); player.play(playlist.items, sourceTitle: playlist.name) }
    }
}
