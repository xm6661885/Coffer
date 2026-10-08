import Foundation
import Observation

@MainActor @Observable final class PlaybackPositionStore {
    struct Record: Codable, Identifiable { var id: String; var item: FileItem; var time: Double; var duration: Double; var updated = Date() }
    private(set) var records: [String: Record] = [:]
    struct Session: Codable { var queue: [MediaRef]; var originalQueue: [MediaRef]; var index: Int; var time: Double; var sourceTitle: String? }
    struct Snapshot: Codable { var records: [String: Record]; var lastSession: Session? }
    var lastSession: Session? { didSet { persist() } }
    private let store = JSONStore<Snapshot>(fileName: "positions.json")
    private func persist() { store.save(Snapshot(records: records, lastSession: lastSession)) }
    func load() async { let store = store; let value = await Task.detached { store.load(default: Snapshot(records: [:], lastSession: nil)) }.value; if records.isEmpty { records = value.records; lastSession = value.lastSession } }
    func position(for id: String) -> Double { records[id]?.time ?? 0 }
    func save(_ item: FileItem, time: Double, duration: Double) { records[item.id] = Record(id: item.id, item: item, time: time, duration: duration); persist() }
    func remove(_ id: String) { records.removeValue(forKey: id); persist() }
    var recentVideos: [Record] { Array(records.values.filter { $0.item.kind == .video && $0.time > 0 }.sorted { $0.updated > $1.updated }.prefix(10)) }
    var recentAudio: [Record] { Array(records.values.filter { $0.item.kind == .audio && $0.duration > 1200 && $0.time > 0 }.sorted { $0.updated > $1.updated }.prefix(10)) }
}
