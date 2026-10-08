import Foundation
import Observation

@MainActor @Observable final class RemoteCache {
    struct Record: Codable { var item: FileItem; var size: Int64; var accessed: Date }
    let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "Coffer/Remote")
    let registry: FileProviderRegistry
    let settings: AppSettings
    let toast: ToastCenter
    let transfers: TransferManager
    private var records: [String: Record] = [:]
    private var requests: [String: Task<URL, Error>] = [:]
    var pinned: Set<String> { didSet { UserDefaults.standard.set(Array(pinned), forKey: "offlineFiles") } }
    init(registry: FileProviderRegistry, settings: AppSettings, toast: ToastCenter, transfers: TransferManager) { self.transfers = transfers; self.registry = registry; self.settings = settings; self.toast = toast; pinned = Set(UserDefaults.standard.stringArray(forKey: "offlineFiles") ?? []) }
    func load() async {
        let root = root
        records = await Task.detached { Self.scan(root) }.value
        trim()
    }
    nonisolated private static func scan(_ root: URL) -> [String: Record] {
        var records: [String: Record] = [:]
        if let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let meta as URL in e where meta.lastPathComponent.hasSuffix(".meta.json") {
                guard let data = try? Data(contentsOf: meta), let record = try? JSONDecoder().decode(Record.self, from: data) else { continue }
                let file = meta.deletingLastPathComponent().appending(path: record.item.name)
                if FileManager.default.fileExists(atPath: file.path) { records[record.item.id] = record }
            }
        }
        return records
    }
    func localURL(for item: FileItem) -> URL { root.appending(path: item.location.key).appending(path: String(item.path.dropFirst())) }
    private func metaURL(_ item: FileItem) -> URL { localURL(for: item).deletingLastPathComponent().appending(path: "." + item.name + ".meta.json") }
    func isCached(_ item: FileItem) -> Bool { guard let record = records[item.id] else { return false }; return record.item.etag == item.etag && record.item.size == item.size && record.item.modified == item.modified }
    func cachedItem(for id: String) -> FileItem? { records[id]?.item }
    func fetch(_ item: FileItem, progress: @escaping (Double) -> Void) async throws -> URL {
        guard !item.isDirectory, !PathUtil.components(item.path).contains(where: { $0 == "." || $0 == ".." }) else { throw FileProviderError.invalidName }
        let destination = localURL(for: item)
        if isCached(item), await Task.detached(operation: { FileManager.default.fileExists(atPath: destination.path) }).value { records[item.id]?.accessed = Date(); progress(1); return destination }
        if let request = requests[item.id] { return try await request.value }
        _ = try registry.provider(for: item.location)
        let meta = metaURL(item)
        let request = Task { () throws -> URL in
            progress(-1)
            let id = transfers.enqueueCache(item)
            defer { transfers.removeCacheTask(id) }
            let downloaded = try await transfers.awaitCompletion(id, progress: progress)
            try Task.checkCancellation()
            let size = try await Task.detached { () -> Int64 in
                let fm = FileManager.default; try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                let size = Int64(try downloaded.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
                if let expected = item.size, expected != size { throw FileProviderError.other("The downloaded file size doesn't match.") }
                if downloaded != destination { if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }; try fm.moveItem(at: downloaded, to: destination) }
                let record = Record(item: item, size: size, accessed: Date()); try JSONEncoder().encode(record).write(to: meta, options: .atomic)
                return size
            }.value
            records[item.id] = Record(item: item, size: size, accessed: Date()); trim(excluding: [item.id]); progress(1); return destination
        }
        requests[item.id] = request
        defer { requests[item.id] = nil }
        return try await withTaskCancellationHandler(operation: { try await request.value }, onCancel: { request.cancel() })
    }
    func recordUpdated(_ item: FileItem) async throws {
        let file = localURL(for: item), meta = metaURL(item)
        let record = try await Task.detached { () -> Record in let size = Int64(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0); let record = Record(item: item, size: size, accessed: Date()); try JSONEncoder().encode(record).write(to: meta, options: .atomic); return record }.value
        records[item.id] = record
    }
    func cancel(_ item: FileItem) { requests[item.id]?.cancel() }
    func pin(_ item: FileItem) { Task { do { _ = try await fetch(item, progress: { _ in }); pinned.insert(item.id); toast.show("Downloaded", symbol: "checkmark") } catch { toast.show(error: error) } } }
    func unpin(_ item: FileItem) { pinned.remove(item.id); removeRecord(item.id) }
    func totalSize() -> Int64 { records.values.reduce(0) { $0 + $1.size } }
    func clear(keepPinned: Bool) { let ids = records.keys.filter { !keepPinned || !pinned.contains($0) }; for id in ids { removeRecord(id) } }
    func remove(location: LocationID) { for id in Array(records.keys) where records[id]?.item.location == location { requests[id]?.cancel(); removeRecord(id); pinned.remove(id) } }
    private func removeRecord(_ id: String) { guard let record = records.removeValue(forKey: id) else { return }; let file = localURL(for: record.item), meta = metaURL(record.item); Task.detached { try? FileManager.default.removeItem(at: file); try? FileManager.default.removeItem(at: meta) } }
    private func trim(excluding: Set<String> = []) {
        guard settings.cacheLimit > 0 else { return }
        let removable = records.values.filter { !pinned.contains($0.item.id) && !excluding.contains($0.item.id) && requests[$0.item.id] == nil && AppServices.shared.player.current?.id != $0.item.id && AppServices.shared.activeVideo?.current.id != $0.item.id }.sorted { $0.accessed < $1.accessed }
        var size = removable.reduce(Int64(0)) { $0 + $1.size }
        guard size > settings.cacheLimit else { return }
        for record in removable { removeRecord(record.item.id); size -= record.size; if size <= settings.cacheLimit * 8 / 10 { break } }
    }
}
