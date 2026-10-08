import Foundation
import Observation
import AVFoundation

struct MediaIndexEntry: Identifiable, Codable, Hashable, Sendable {
    var item: FileItem; var metadata: TrackMetadata; var addedAt = Date(); var width: Double?; var height: Double?
    var id: String { item.id }; var ref: MediaRef { MediaRef(item) }
}
@MainActor @Observable final class MediaLibraryIndex {
    private(set) var entries: [MediaIndexEntry] = []
    private(set) var isScanning = false
    private(set) var error: String?
    private(set) var scanStatus: String?
    private(set) var scanProgress: Double?
    private var pendingRefresh = false
    private var hasScanned = false
    private var refreshTask: Task<Void, Never>?
    let kind: FileKind
    let store: JSONStore<[MediaIndexEntry]>
    init(kind: FileKind) { self.kind = kind; store = JSONStore(fileName: kind == .audio ? "music-index.json" : kind == .image ? "picture-index.json" : "video-index.json") }
    func load() async { let store = store; entries = await Task.detached { store.load(default: []) }.value }
    func requestRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            guard let self else { return }
            refreshTask = nil
            await scan()
        }
    }
    /// Automatic scan for view appearance: runs once per launch; later updates come from directory-change notifications or a manual refresh.
    func scanIfNeeded() async { if !hasScanned && !isScanning { await scan() } }
    func scan(force: Bool = false) async {
        guard !isScanning else { pendingRefresh = true; return }
        error = nil; isScanning = true; hasScanned = true; scanProgress = nil; scanStatus = "Looking for files…"
        defer {
            isScanning = false; scanStatus = nil; scanProgress = nil
            if pendingRefresh { pendingRefresh = false; requestRefresh() }
        }
        let services = AppServices.shared
        var files: [FileItem] = []
        do { files = try await services.registry.local.recursiveList("/", limit: 100_000).filter { $0.kind == kind } } catch { self.error = error.localizedDescription }
        for source in kind == .audio ? services.settings.musicSources : kind == .image ? services.settings.pictureSources : services.settings.videoSources {
            scanStatus = "Checking " + services.registry.displayName(for: source.location) + "…"
            do { files += try await listing(try services.registry.provider(for: source.location), source.path, limit: 5000, fresh: force).filter { $0.kind == kind } } catch { self.error = error.localizedDescription; files += entries.filter { $0.item.location == source.location && PathUtil.isAncestor(source.path, of: $0.item.path) }.map(\.item) }
        }
        let old = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        var unique: [String: FileItem] = [:]; for item in files { unique[item.id] = item }
        let list = Array(unique.values).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        var fresh: [MediaIndexEntry] = []; entries = list.compactMap { old[$0.id] }
        scanStatus = "Updating library…"; scanProgress = list.isEmpty ? nil : 0
        await withTaskGroup(of: MediaIndexEntry?.self) { group in
            var next = 0; var done = 0
            func add(_ item: FileItem) { group.addTask { @MainActor in
                if Task.isCancelled { return nil }
                if !force, let saved = old[item.id], saved.item.modified == item.modified && saved.item.size == item.size { var saved = saved; if let metadata = services.player.metadata[item.id] { saved.metadata = metadata }; return saved }
                var result = MediaIndexEntry(item: item, metadata: TrackMetadata(title: PathUtil.baseName(item.name)), addedAt: old[item.id]?.addedAt ?? Date())
                if item.location == .local && self.kind != .image {
                    let url = services.registry.local.url(for: item.path); result.metadata = await MetadataLoader().load(MediaRef(item), url: url)
                    if self.kind == .video { let asset = AVURLAsset(url: url); if let tracks = try? await asset.loadTracks(withMediaType: .video), let track = tracks.first, let size = try? await track.load(.naturalSize), let transform = try? await track.load(.preferredTransform) { let size = size.applying(transform); result.width = abs(size.width); result.height = abs(size.height) } else { let media = VLCMedia(url: url); media.parse(options: VLCMediaParsingOptions(rawValue: 0), timeout: 3000); for _ in 0..<30 { if media.parsedStatus.rawValue != 0 { break }; try? await Task.sleep(for: .milliseconds(100)) }; do { for track in media.tracksInformation { if let info = track as? [String: Any], let width = info[VLCMediaTracksInformationVideoWidth] as? NSNumber, let height = info[VLCMediaTracksInformationVideoHeight] as? NSNumber { result.width = width.doubleValue; result.height = height.doubleValue; break } } } } }
                } else if let metadata = services.player.metadata[item.id] { result.metadata = metadata }
                return result
            } }
            while next < min(4, list.count) { add(list[next]); next += 1 }
            for await result in group { done += 1; if !list.isEmpty { scanProgress = Double(done) / Double(list.count) }; if let result { fresh.append(result); if let index = entries.firstIndex(where: { $0.id == result.id }) { entries[index] = result } else { entries.append(result) } }; if next < list.count && !Task.isCancelled { add(list[next]); next += 1 } }
        }
        if !Task.isCancelled { entries = fresh; store.save(entries) }
    }
    /// Walks a folder tree; when `fresh` is set, remote listings bypass the directory cache so new server-side files are found.
    private func listing(_ provider: FileProvider, _ path: String, limit: Int, fresh: Bool) async throws -> [FileItem] {
        guard fresh, let remote = provider as? WebDAVFileProvider else { return try await provider.recursiveList(path, limit: limit) }
        var folders = [path]; var visited: Set<String> = []; var result: [FileItem] = []
        while let folder = folders.popLast() {
            try Task.checkCancellation(); guard visited.insert(folder).inserted else { continue }
            scanStatus = "Checking " + (folder == "/" ? AppServices.shared.registry.displayName(for: remote.location) : PathUtil.name(folder)) + "…"
            for item in try await remote.list(folder, force: true) {
                guard result.count < limit else { return result }
                result.append(item); if item.isDirectory && !item.isHidden { folders.append(item.path) }
            }
        }
        return result
    }
    func backfill(_ metadata: [String: TrackMetadata]) { for index in entries.indices { if let value = metadata[entries[index].id] { entries[index].metadata = value } }; store.save(entries) }
}
