import Foundation
import Observation
import SwiftUI

@MainActor @Observable final class FavouritesStore {
    private(set) var items: [FileItem] = []
    private let store = JSONStore<[FileItem]>(fileName: "favourites.json")
    private var loaded = false
    func load() async {
        guard !loaded else { return }
        // Load synchronously before the first interaction so an early favourite is never lost.
        items = store.load(default: []); loaded = true
    }
    func contains(_ item: FileItem) -> Bool { items.contains { $0.id == item.id } }
    func toggle(_ item: FileItem) {
        if !loaded { items = store.load(default: []); loaded = true }
        withAnimation(.smooth) {
            if contains(item) { items.removeAll { $0.id == item.id } } else { items.append(item) }
        }
        store.save(items)
    }
    func removeTree(_ item: FileItem) {
        items.removeAll { $0.location == item.location && ($0.path == item.path || (item.isDirectory && PathUtil.isAncestor(item.path, of: $0.path))) }
        store.save(items)
    }
    func relocate(_ original: FileItem, to updated: FileItem) {
        items = items.map { saved in
            guard saved.location == original.location else { return saved }
            if saved.path == original.path { return updated }
            guard original.isDirectory && PathUtil.isAncestor(original.path, of: saved.path) else { return saved }
            let suffix = String(saved.path.dropFirst(original.path.count))
            return FileItem(location: updated.location, path: updated.path + suffix, name: saved.name, isDirectory: saved.isDirectory, size: saved.size, modified: saved.modified, created: saved.created, etag: nil, contentType: saved.contentType)
        }
        var seen = Set<String>(); items = items.filter { seen.insert($0.id).inserted }; store.save(items)
    }
}

struct FavouriteButton: View {
    let item: FileItem
    @Environment(FavouritesStore.self) private var favourites
    var body: some View {
        Button(favourites.contains(item) ? "Remove from Favourites" : "Add to Favourites", systemImage: favourites.contains(item) ? "star.slash" : "star") { favourites.toggle(item) }
    }
}

extension FileItem {
    @MainActor static func folder(location: LocationID, path: String) -> FileItem {
        FileItem(location: location, path: path, name: path == "/" ? AppServices.shared.registry.displayName(for: location) : PathUtil.name(path), isDirectory: true, size: nil, modified: nil, created: nil, etag: nil, contentType: nil)
    }
}
