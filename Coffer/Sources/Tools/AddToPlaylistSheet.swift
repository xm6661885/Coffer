import SwiftUI

struct AddToPlaylistSheet: View {
    let refs: [MediaRef]
    @Environment(PlaylistStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var creating = false
    private var kind: Playlist.Kind { refs.contains { $0.fileItem.kind == .audio } ? .music : .video }
    private var matching: [MediaRef] { refs.filter { $0.fileItem.kind == (kind == .music ? .audio : .video) } }
    var body: some View {
        NavigationStack { List {
            Button("New Playlist…", systemImage: "plus") { creating = true }
            ForEach(store.playlists.filter { $0.kind == kind }) { playlist in Button { store.add(matching, to: playlist.id); dismiss() } label: { Label(playlist.name, systemImage: kind == .music ? "music.note.list" : "play.rectangle.on.rectangle").foregroundStyle(Color.ink) } }
        }.paperList().navigationTitle("Add to Playlist").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }.sheet(isPresented: $creating) { PlaylistNameSheet(kind: kind) { name, kind in let playlist = store.create(name: name, kind: kind); store.add(matching, to: playlist.id); dismiss() } } }.presentationDetents([.medium, .large]).presentationBackground(Color.canvas)
    }
}
struct PlaylistNameSheet: View {
    var playlist: Playlist? = nil
    var kind: Playlist.Kind = .music
    var allowsKindSelection = true
    let onSave: (String, Playlist.Kind) -> Void
    @Environment(PlaylistStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selection: TextSelection?
    @State private var selectedKind: Playlist.Kind = .music
    @FocusState private var focused: Bool
    var body: some View {
        NavigationStack { Form { TextField("Name", text: $name, selection: $selection).focused($focused); if playlist == nil && allowsKindSelection { Picker("Type", selection: $selectedKind) { Text("Music").tag(Playlist.Kind.music); Text("Video").tag(Playlist.Kind.video) }.pickerStyle(.segmented) } }.paperList().navigationTitle(playlist == nil ? "New Playlist" : "Rename Playlist").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button(playlist == nil ? "Create" : "Save") { onSave(name.trimmingCharacters(in: .whitespacesAndNewlines), selectedKind); dismiss() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } }.task { selectedKind = playlist?.kind ?? kind; if let playlist { name = playlist.name } else { var number = 1; while store.playlists.contains(where: { $0.name == "Playlist \(number)" }) { number += 1 }; name = "Playlist \(number)" }; focused = true; selection = TextSelection(range: name.startIndex..<name.endIndex) } }.presentationDetents([.height(260)]).presentationBackground(Color.canvas)
    }
}
