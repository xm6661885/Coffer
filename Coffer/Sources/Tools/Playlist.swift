import Foundation
import SwiftUI
import Observation

struct Playlist: Identifiable, Codable, Hashable {
    enum Kind: String, Codable { case music, video }
    var id = UUID(); var name: String; var kind: Kind; var items: [MediaRef]; var created = Date(); var modified = Date()
}
@MainActor @Observable final class PlaylistStore {
    private(set) var playlists: [Playlist] = []
    private let store = JSONStore<[Playlist]>(fileName: "playlists.json")
    func load() async { let store = store; let values = await Task.detached { store.load(default: []) }.value; if playlists.isEmpty { playlists = values } }
    func create(name: String, kind: Playlist.Kind) -> Playlist { let playlist = Playlist(name: name, kind: kind, items: []); withAnimation(.smooth) { playlists.append(playlist) }; store.save(playlists); return playlist }
    func rename(_ id: UUID, to name: String) { guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }; playlists[index].name = name; playlists[index].modified = Date(); store.save(playlists) }
    func delete(_ id: UUID) { withAnimation(.smooth) { playlists.removeAll { $0.id == id } }; store.save(playlists) }
    func add(_ refs: [MediaRef], to id: UUID) { guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }; let before = playlists[index].items.count; var ids = Set(playlists[index].items.map(\.id)); for ref in refs where ids.insert(ref.id).inserted { playlists[index].items.append(ref) }; playlists[index].modified = Date(); store.save(playlists); AppServices.shared.toast.show("Added \(playlists[index].items.count - before) items to \"\(playlists[index].name)\"", symbol: "checkmark") }
    func remove(at offsets: IndexSet, from id: UUID) { guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }; playlists[index].items.remove(atOffsets: offsets); playlists[index].modified = Date(); store.save(playlists) }
    func move(from offsets: IndexSet, to destination: Int, in id: UUID) { guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }; playlists[index].items.move(fromOffsets: offsets, toOffset: destination); playlists[index].modified = Date(); store.save(playlists) }
}
