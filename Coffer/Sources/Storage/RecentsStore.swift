import Foundation
import Observation
import SwiftUI

@MainActor @Observable final class RecentsStore {
    struct Entry: Identifiable, Codable { var item: FileItem; var opened = Date(); var id: String { item.id } }
    private(set) var entries: [Entry] = []
    private let store = JSONStore<[Entry]>(fileName: "recents.json")
    func load() async { let store = store; let saved = await Task.detached { store.load(default: []) }.value; if entries.isEmpty { entries = saved } }
    func add(_ item: FileItem) { entries.removeAll { $0.id == item.id }; entries.insert(Entry(item: item), at: 0); entries = Array(entries.prefix(50)); store.save(entries) }
    func remove(_ id: String) { withAnimation(.smooth) { entries.removeAll { $0.id == id } }; store.save(entries) }
    func clear() { withAnimation(.smooth) { entries.removeAll() }; store.save(entries) }
}
