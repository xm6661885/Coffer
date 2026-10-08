import Foundation
import Observation
import Network
import UIKit
import SwiftUI

@MainActor @Observable final class TransferManager {
    struct Snapshot: Codable { var tasks: [TransferTask]; var groups: [UUID: TransferGroup] }
    private(set) var tasks: [TransferTask] = []
    private(set) var groups: [UUID: TransferGroup] = [:]
    private(set) var speed = 0.0
    private(set) var taskSpeeds: [UUID: Double] = [:]
    let settings: AppSettings
    let registry: FileProviderRegistry
    let toast: ToastCenter
    var onShow: (() -> Void)?
    private let store = JSONStore<Snapshot>(fileName: "transfers.json")
    private var workers: [UUID: Task<Void, Never>] = [:]
    private var downloaders: [UUID: SegmentedDownloader] = [:]
    private var uploaders: [UUID: Uploader] = [:]
    private var waiters: [UUID: CheckedContinuation<URL, Error>] = [:]
    private var progressCallbacks: [UUID: (Double) -> Void] = [:]
    private var persistence: Task<Void, Never>?
    private let monitor = NWPathMonitor()
    private var recovery: Task<Void, Never>?
    private var online = true
    private var cellular = false
    private var timer: Timer?
    private var previousBytes: [UUID: Int64] = [:]
    private var samples: [Double] = []
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var backgroundExpired = false
    private var finishingGroups: Set<UUID> = []
    var activeCount: Int { tasks.filter { $0.kind != .cache && $0.isActive }.count }
    var overallProgress: Double { let tasks = tasks.filter { $0.kind != .cache && $0.isActive }; let total = tasks.reduce(Int64(0)) { $0 + $1.totalBytes }; return total > 0 ? min(1, Double(tasks.reduce(Int64(0)) { $0 + $1.completedBytes }) / Double(total)) : 0 }
    init(settings: AppSettings, registry: FileProviderRegistry, toast: ToastCenter) {
        self.settings = settings; self.registry = registry; self.toast = toast
        monitor.pathUpdateHandler = { [weak self] path in Task { @MainActor in self?.networkChanged(online: path.status == .satisfied, cellular: path.usesInterfaceType(.cellular)) } }
        monitor.start(queue: DispatchQueue(label: "app.coffer.network"))
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
    }
    func load() async {
        let store = store
        let saved = await Task.detached { store.load(default: Snapshot(tasks: [], groups: [:])) }.value
        if tasks.isEmpty {
            tasks = saved.tasks.filter { $0.groupID.flatMap { saved.groups[$0]?.finished } == false || $0.finishedAt == nil || Date().timeIntervalSince($0.finishedAt!) < 7 * 24 * 3600 }.map { var task = $0; if task.state == .running { task.state = .queued }; return task }
            groups = saved.groups
        }
        for id in Array(groups.keys) { await finishGroup(id) }
        schedule()
    }
    private func persist() {
        guard persistence == nil else { return }
        persistence = Task { try? await Task.sleep(for: .seconds(1)); guard !Task.isCancelled else { return }; store.save(Snapshot(tasks: tasks.filter { $0.kind != .cache }, groups: groups)); persistence = nil }
    }
    private func tick() {
        var total = 0.0
        for task in tasks where task.state == .running {
            let delta = max(0, task.completedBytes - (previousBytes[task.id] ?? task.completedBytes)); previousBytes[task.id] = task.completedBytes
            taskSpeeds[task.id] = Double(delta); total += Double(delta)
        }
        samples.append(total); if samples.count > 3 { samples.removeFirst() }; withAnimation(.smooth) { speed = samples.reduce(0, +) / Double(max(1, samples.count)) }
        for task in tasks where task.state == .waitingForNetwork && eligible(task) { setState(task.id, .queued) }
        for task in tasks where task.state == .running && !eligible(task) { setState(task.id, .waitingForNetwork); workers[task.id]?.cancel(); downloaders[task.id]?.cancel(); uploaders[task.id]?.cancel() }
        schedule()
    }
    private func eligible(_ task: TransferTask) -> Bool { online && (task.kind == .cache || !settings.wifiOnly || !cellular) }
    private func schedule() {
        guard !backgroundExpired else { return }
        var count = tasks.filter { $0.state == .running && $0.kind != .cache }.count
        let candidates = tasks.filter { $0.state == .queued }.sorted { if ($0.kind == .cache) != ($1.kind == .cache) { return $0.kind == .cache }; return $0.createdAt < $1.createdAt }
        for task in candidates {
            if !eligible(task) { setState(task.id, .waitingForNetwork); continue }
            guard workers[task.id] == nil else { continue }
            if task.kind != .cache && count >= max(1, min(6, settings.maxConcurrentTransfers)) { continue }
            if task.kind != .cache && tasks.contains(where: { $0.id != task.id && $0.kind != .cache && workers[$0.id] != nil && $0.destLocation == task.destLocation && $0.destPath == task.destPath }) { continue }
            setState(task.id, .running); previousBytes[task.id] = task.completedBytes
            workers[task.id] = Task { await run(task.id) }; if task.kind != .cache { count += 1 }
        }
    }
    private func setState(_ id: UUID, _ state: TransferTask.State, error: String? = nil) { guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }; tasks[index].state = state; tasks[index].lastError = error; if [.completed, .cancelled].contains(state) { tasks[index].finishedAt = Date() }; persist() }
    func pause(_ id: UUID) { guard let task = tasks.first(where: { $0.id == id }), task.isActive else { return }; setState(id, .paused); workers[id]?.cancel(); downloaders[id]?.cancel(); uploaders[id]?.cancel() }
    func resume(_ id: UUID) { guard let index = tasks.firstIndex(where: { $0.id == id }), [.paused, .waitingForNetwork, .failed].contains(tasks[index].state) else { return }; tasks[index].retryAt = nil; setState(id, .queued); schedule() }
    func retry(_ id: UUID) { resume(id) }
    func cancel(_ id: UUID) {
        guard let task = tasks.first(where: { $0.id == id }), task.state != .completed else { return }
        setState(id, .cancelled); workers[id]?.cancel(); downloaders[id]?.cancel(); uploaders[id]?.cancel(); finishWaiter(id, result: .failure(FileProviderError.cancelled))
        if workers[id] == nil { cleanPartial(id); cleanImport(task.sourceURL) }; schedule()
    }
    func cancel(location: LocationID) { for task in tasks where task.source.location == location || task.destLocation == location { cancel(task.id) } }
    func pauseAll() { for task in tasks where task.isActive { pause(task.id) } }
    func resumeAll() { for task in tasks where [.paused, .waitingForNetwork].contains(task.state) { resume(task.id) } }
    func clearFinished() { withAnimation(.smooth) { tasks.removeAll { [.completed, .cancelled].contains($0.state) && ($0.groupID == nil || groups[$0.groupID!]?.finished != false) }; groups = groups.filter { !$0.value.finished } }; persist() }
    func remove(_ id: UUID) { guard tasks.first(where: { $0.id == id })?.state == .completed else { cancel(id); return }; guard let task = tasks.first(where: { $0.id == id }), task.groupID == nil || groups[task.groupID!]?.finished != false else { return }; withAnimation(.smooth) { tasks.removeAll { $0.id == id } }; persist() }
    func progress(for id: UUID) -> Double { guard let task = tasks.first(where: { $0.id == id }) else { return 0 }; return task.totalBytes > 0 ? min(1, Double(task.completedBytes) / Double(task.totalBytes)) : -1 }
    func task(forDest location: LocationID, path: String) -> TransferTask? { tasks.first { $0.destLocation == location && $0.destPath == path && $0.isActive } }
    func pendingNames(_ location: LocationID, in directory: String) -> Set<String> {
        let files = tasks.filter { $0.kind != .cache && $0.groupID == nil && $0.destLocation == location && PathUtil.parent($0.destPath) == directory && ($0.isActive || $0.state == .failed) }.map { PathUtil.name($0.destPath) }
        let folders = groups.values.filter { !$0.finished && $0.targetLocation == location && $0.finalPath.map { PathUtil.parent($0) == directory } == true }.compactMap { $0.finalPath.map(PathUtil.name) }
        return Set(files + folders)
    }
    func cancelDestination(_ location: LocationID, path: String) async {
        let matching = tasks.filter { $0.kind != .cache && $0.groupID == nil && $0.destLocation == location && $0.destPath == path && ($0.isActive || $0.state == .failed) }
        let running = matching.compactMap { workers[$0.id] }
        for task in matching { cancel(task.id) }
        let folders = groups.values.filter { !$0.finished && $0.targetLocation == location && $0.finalPath == path }
        let folderWorkers = folders.flatMap { $0.taskIDs.compactMap { workers[$0] } }
        for group in folders { cancelGroup(group.id) }
        for worker in running + folderWorkers { await worker.value }
    }
    private func cleanImport(_ source: URL?) {
        guard let source else { return }
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "Coffer/Imports")
        guard source.path.hasPrefix(root.path + "/") else { return }
        let name = String(source.path.dropFirst(root.path.count + 1)).components(separatedBy: "/")[0]
        guard UUID(uuidString: name) != nil else { return }
        let directory = root.appending(path: name)
        guard !tasks.contains(where: { $0.sourceURL?.path.hasPrefix(directory.path + "/") == true && ($0.isActive || $0.state == .failed || workers[$0.id] != nil) }) else { return }
        Task.detached { try? FileManager.default.removeItem(at: directory) }
    }
    private func changed(_ location: LocationID, _ path: String) { if let provider = try? registry.provider(for: location) as? WebDAVFileProvider { provider.cache.invalidate([path]) }; NotificationCenter.default.post(name: .cofferDirectoryChanged, object: nil, userInfo: ["location": location, "path": path]) }
    private func partDirectory(_ id: UUID) -> URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "Coffer/Partial/" + id.uuidString) }
    private func cleanPartial(_ id: UUID) { let directory = partDirectory(id); Task.detached { try? FileManager.default.removeItem(at: directory) } }
    private func networkChanged(online: Bool, cellular: Bool) {
        self.online = online; self.cellular = cellular; recovery?.cancel()
        for task in tasks where task.isActive && !eligible(task) { setState(task.id, .waitingForNetwork); workers[task.id]?.cancel(); downloaders[task.id]?.cancel(); uploaders[task.id]?.cancel() }
        if online { recovery = Task { try? await Task.sleep(for: .seconds(2)); guard !Task.isCancelled else { return }; for task in tasks where task.state == .waitingForNetwork && eligible(task) { setState(task.id, .queued) }; schedule() } }
    }
    func setBackground(_ background: Bool) {
        if !background { backgroundExpired = false; if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid }; schedule(); return }
        guard activeCount > 0 && backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "transfers") { [weak self] in Task { @MainActor in
            guard let self else { return }; self.backgroundExpired = true
            for task in self.tasks where task.state == .running { self.setState(task.id, .queued); self.workers[task.id]?.cancel(); self.downloaders[task.id]?.cancel(); self.uploaders[task.id]?.cancel() }
            self.store.save(Snapshot(tasks: self.tasks.filter { $0.kind != .cache }, groups: self.groups))
            if self.backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(self.backgroundTask); self.backgroundTask = .invalid }
        } }
    }
    func enqueueDownload(_ item: FileItem, toLocal dirPath: String) async { await enqueue(item, destination: .local, path: PathUtil.join(dirPath, item.name), move: false) }
    func enqueueUpload(_ localItem: FileItem, to location: LocationID, dirPath: String) async { await enqueue(localItem, destination: location, path: PathUtil.join(dirPath, localItem.name), move: false) }
    @discardableResult func enqueue(_ item: FileItem, destination: LocationID, path: String, move: Bool) async -> Bool {
        var expansionGroup: UUID?
        do {
            if item.isDirectory {
                var group = TransferGroup(name: item.name, sourceDirectories: [item], move: move)
                group.targetLocation = destination; group.finalPath = path
                group.stagePath = PathUtil.join(PathUtil.parent(path), ".coffer-transfer-" + group.id.uuidString)
                let id = group.id; expansionGroup = id; groups[id] = group
                let source = try registry.provider(for: item.location), target = try registry.provider(for: destination)
                var folders: [(FileItem, String)] = [(item, group.stagePath!)]
                while let (folder, destinationPath) = folders.popLast() {
                    try Task.checkCancellation(); guard groups[id]?.finished != true else { throw FileProviderError.cancelled }
                    do { _ = try await target.createFolder(named: PathUtil.name(destinationPath), in: PathUtil.parent(destinationPath)) } catch FileProviderError.alreadyExists { }
                    for child in try await source.list(folder.path) {
                        let childPath = PathUtil.join(destinationPath, child.name)
                        if child.isDirectory { group.sourceDirectories.append(child); folders.append((child, childPath)) }
                        else {
                            let task = makeTask(child, destination: destination, path: childPath, move: false, group: id)
                            group.taskIDs.append(task.id); tasks.append(task)
                        }
                    }
                    guard groups[id]?.finished != true else { throw FileProviderError.cancelled }; groups[id] = group
                }
                group.isExpanded = true; groups[id] = group; await finishGroup(id)
            } else { tasks.append(makeTask(item, destination: destination, path: path, move: move, group: nil)) }
            store.save(Snapshot(tasks: tasks.filter { $0.kind != .cache }, groups: groups)); schedule(); return true
        } catch { if let id = expansionGroup { groups[id]?.lastError = error.localizedDescription; for task in tasks where task.groupID == id { pause(task.id) }; persist() }; toast.show(error: error); return false }
    }
    private func makeTask(_ item: FileItem, destination: LocationID, path: String, move: Bool, group: UUID?) -> TransferTask {
        TransferTask(kind: destination == .local ? .download : .upload, source: item, destLocation: destination, destPath: path, deleteSourceOnSuccess: move, totalBytes: (item.size ?? 0) * (item.location.isRemote && destination.isRemote ? 2 : 1), completedBytes: 0, etag: item.etag, groupID: group)
    }
    func enqueueCache(_ item: FileItem) -> UUID {
        if let existing = tasks.first(where: { $0.kind == .cache && $0.source.id == item.id && $0.isActive }) { return existing.id }
        let task = TransferTask(kind: .cache, source: item, destLocation: item.location, destPath: item.path, totalBytes: item.size ?? 0, completedBytes: 0, etag: item.etag)
        tasks.append(task); schedule(); return task.id
    }
    func awaitCompletion(_ id: UUID, progress: @escaping (Double) -> Void) async throws -> URL {
        guard let task = tasks.first(where: { $0.id == id }) else { throw FileProviderError.cancelled }
        if task.state == .completed { return cacheURL(task.source) }
        if [.failed, .cancelled].contains(task.state) { throw FileProviderError.other(task.lastError ?? "Cancelled.") }
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in waiters[id] = continuation; progressCallbacks[id] = progress; progress(self.progress(for: id)) }
        }, onCancel: { Task { @MainActor in self.cancel(id) } })
    }
    func removeCacheTask(_ id: UUID) { if tasks.first(where: { $0.id == id })?.kind == .cache && workers[id] == nil { tasks.removeAll { $0.id == id } } }
    private func cacheURL(_ item: FileItem) -> URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "Coffer/Remote/" + item.location.key).appending(path: String(item.path.dropFirst())) }
    private func finishWaiter(_ id: UUID, result: Result<URL, Error>) { let continuation = waiters.removeValue(forKey: id); progressCallbacks[id] = nil; continuation?.resume(with: result) }
    private func update(_ id: UUID, bytes: Int64, segments: [TransferTask.Segment]? = nil, total: Int64? = nil, etag: String? = nil) {
        guard let index = tasks.firstIndex(where: { $0.id == id }), tasks[index].state != .cancelled else { return }
        tasks[index].completedBytes = bytes; if let segments { tasks[index].segments = segments }; if let total { tasks[index].totalBytes = total }; if let etag { tasks[index].etag = etag }
        tasks[index].retryAt = nil; progressCallbacks[id]?(progress(for: id)); persist()
    }
    private func retrying(_ id: UUID, attempt: Int, delay: Double) { guard let index = tasks.firstIndex(where: { $0.id == id }), tasks[index].state == .running else { return }; tasks[index].attempts = attempt; tasks[index].retryAt = Date().addingTimeInterval(delay); persist() }
    private func download(_ task: TransferTask, multiplier: Int64 = 1) async throws -> URL {
        guard let provider = try registry.provider(for: task.source.location) as? WebDAVFileProvider else { throw FileProviderError.notFound("Server") }
        let downloader = SegmentedDownloader(task: task, client: provider.client, partDir: partDirectory(task.id), connections: provider.client.server.connectionsPerDownload) { segments in
            let bytes = segments.reduce(Int64(0)) { $0 + $1.done }, total = segments.reduce(Int64(0)) { $0 + max(0, $1.end - $1.start + 1) }
            Task { @MainActor in self.update(task.id, bytes: bytes, segments: segments, total: total > 0 ? total * multiplier : nil) }
        }
        downloader.onMetadata = { total, etag in Task { @MainActor in if let index = self.tasks.firstIndex(where: { $0.id == task.id }) { self.tasks[index].etag = etag; if let total { self.tasks[index].totalBytes = total * multiplier }; self.persist() } } }
        downloader.onRetry = { attempt, delay in Task { @MainActor in self.retrying(task.id, attempt: attempt, delay: delay) } }
        downloaders[task.id] = downloader
        let url = try await downloader.run()
        let size = try await Task.detached { Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }.value
        update(task.id, bytes: size, total: size * multiplier)
        return url
    }
    private func run(_ id: UUID) async {
        defer { workers[id] = nil; downloaders[id] = nil; uploaders[id] = nil; if let task = tasks.first(where: { $0.id == id }) { if task.state == .cancelled { cleanPartial(id) }; cleanImport(task.sourceURL) }; schedule() }
        guard let original = tasks.first(where: { $0.id == id }) else { return }
        do {
            if !original.destinationVerified {
                if original.kind == .download || original.kind == .cache {
                    let downloaded = try await download(original)
                    try Task.checkCancellation()
                    let destination = original.kind == .cache ? cacheURL(original.source) : registry.local.url(for: original.destPath)
                    try await install(downloaded, to: destination)
                } else {
                    let source: URL; let offset: Int64
                    if original.source.location.isRemote { var downloadTask = original; downloadTask.totalBytes = original.source.size ?? original.totalBytes / 2; source = try await download(downloadTask, multiplier: 2); let actualSize = Int64((try? await Task.detached { try source.resourceValues(forKeys: [.fileSizeKey]).fileSize }.value) ?? 0); offset = original.source.size ?? actualSize }
                    else { source = original.sourceURL ?? registry.local.url(for: original.source.path); offset = 0 }
                    guard let provider = try registry.provider(for: original.destLocation) as? WebDAVFileProvider else { throw FileProviderError.notFound("Server") }
                    let uploader = Uploader(client: provider.client, source: source, destination: original.destPath) { bytes in Task { @MainActor in self.update(id, bytes: offset + bytes) } }
                    uploader.onRetry = { attempt, delay in Task { @MainActor in self.retrying(id, attempt: attempt, delay: delay) } }
                    uploaders[id] = uploader; try await uploader.run()
                }
                guard let index = tasks.firstIndex(where: { $0.id == id }) else { throw CancellationError() }
                tasks[index].destinationVerified = true
                if original.kind != .cache { try await store.saveAndWait(Snapshot(tasks: tasks.filter { $0.kind != .cache }, groups: groups)) }
            }
            try Task.checkCancellation()
            if original.deleteSourceOnSuccess {
                let destination = try await registry.provider(for: original.destLocation).stat(original.destPath)
                let expected = original.source.size ?? tasks.first(where: { $0.id == id }).map { $0.totalBytes / (original.source.location.isRemote && original.destLocation.isRemote ? 2 : 1) }
                guard destination.size == expected else { throw FileProviderError.conflict("The destination changed. The source wasn't deleted.") }
                let provider = try registry.provider(for: original.source.location)
                do {
                    let current = try await provider.stat(original.source.path)
                    guard current.size == original.source.size && (original.source.etag != nil ? current.etag == original.source.etag : current.modified == original.source.modified) else { throw FileProviderError.conflict("The source changed and wasn't deleted. Copy it again to move the updated file.") }
                    try await provider.delete(current)
                } catch FileProviderError.notFound { }
            }
            if original.deleteSourceOnSuccess, let updated = try? await registry.provider(for: original.destLocation).stat(original.destPath) { AppServices.shared.favourites.relocate(original.source, to: updated) }
            setState(id, .completed)
            if let index = tasks.firstIndex(where: { $0.id == id }) { tasks[index].completedBytes = tasks[index].totalBytes; tasks[index].retryAt = nil }
            cleanPartial(id)
            changed(original.destLocation, PathUtil.parent(original.destPath))
            if original.deleteSourceOnSuccess { NotificationCenter.default.post(name: .cofferDirectoryChanged, object: nil, userInfo: ["location": original.source.location, "path": original.source.parentPath]) }
            if original.kind == .cache { finishWaiter(id, result: .success(cacheURL(original.source))) }
            else if let group = original.groupID { await finishGroup(group) }
            else { toast.show(original.kind == .download ? "Downloaded" : "Uploaded", symbol: "checkmark") }
            persist()
        } catch {
            if tasks.first(where: { $0.id == id })?.state == .running { setState(id, .failed, error: error.localizedDescription); finishWaiter(id, result: .failure(error)) }
        }
    }

    private func install(_ source: URL, to destination: URL) async throws {
        try await Task.detached {
            let fm = FileManager.default
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: destination.path) { _ = try fm.replaceItemAt(destination, withItemAt: source) }
            else { try fm.moveItem(at: source, to: destination) }
        }.value
    }
    func retryGroup(_ id: UUID) { Task { guard let group = groups[id] else { return }; if !group.isExpanded, let source = group.sourceDirectories.first, let location = group.targetLocation, let path = group.finalPath { cancelGroup(id); _ = await enqueue(source, destination: location, path: path, move: group.move) } else { await finishGroup(id) } } }
    func cancelGroup(_ id: UUID) {
        guard var group = groups[id] else { return }
        for task in group.taskIDs { if !group.installed && tasks.first(where: { $0.id == task })?.state == .completed { setState(task, .cancelled) } else { cancel(task) } }
        if !group.installed, let location = group.targetLocation, let path = group.stagePath { let active = group.taskIDs.compactMap { workers[$0] }; Task { for worker in active { await worker.value }; if let provider = try? registry.provider(for: location), let item = try? await provider.stat(path) { try? await provider.delete(item) } } }
        group.finished = true; group.lastError = nil; groups[id] = group; persist()
    }
    private func finishGroup(_ id: UUID) async {
        guard var group = groups[id], group.isExpanded, !group.finished, !finishingGroups.contains(id),
              group.taskIDs.allSatisfy({ id in tasks.contains { $0.id == id && $0.state == .completed } }) else { return }
        finishingGroups.insert(id); defer { finishingGroups.remove(id) }
        do {
            if !group.installed, let location = group.targetLocation, let stagePath = group.stagePath, let finalPath = group.finalPath {
                let provider = try registry.provider(for: location)
                if location == .local {
                    let source = registry.local.url(for: stagePath), destination = registry.local.url(for: finalPath)
                    try await Task.detached {
                        let fm = FileManager.default; let backup = destination.deletingLastPathComponent().appending(path: ".coffer-replace-" + UUID().uuidString)
                        let existed = fm.fileExists(atPath: destination.path)
                        if existed { try fm.moveItem(at: destination, to: backup) }
                        do { try fm.moveItem(at: source, to: destination); if existed { try fm.removeItem(at: backup) } }
                        catch { if existed && !fm.fileExists(atPath: destination.path) { try? fm.moveItem(at: backup, to: destination) }; throw error }
                    }.value
                } else {
                    let stage = try await provider.stat(stagePath)
                    try await provider.move(stage, toDir: PathUtil.parent(finalPath), newName: PathUtil.name(finalPath), overwrite: true)
                }
                group.installed = true; group.finished = groups[id]?.finished ?? group.finished; groups[id] = group
                for index in tasks.indices where tasks[index].groupID == id { tasks[index].destPath = finalPath + String(tasks[index].destPath.dropFirst(stagePath.count)) }
                try await store.saveAndWait(Snapshot(tasks: tasks.filter { $0.kind != .cache }, groups: groups))
                changed(location, PathUtil.parent(finalPath))
            }
            guard groups[id]?.finished != true else { return }
            if group.move {
                for taskID in group.taskIDs {
                    guard groups[id]?.finished != true else { return }
                    guard let task = tasks.first(where: { $0.id == taskID }) else { continue }
                    if let location = group.targetLocation {
                        let destination = try await registry.provider(for: location).stat(task.destPath)
                        let expected = task.source.size ?? task.totalBytes / (task.source.location.isRemote && task.destLocation.isRemote ? 2 : 1)
                        guard destination.size == expected else { throw FileProviderError.conflict("A destination file changed. Its source wasn't deleted.") }
                    }
                    let provider = try registry.provider(for: task.source.location)
                    do { let current = try await provider.stat(task.source.path)
                        guard current.size == task.source.size && (task.source.etag != nil ? current.etag == task.source.etag : current.modified == task.source.modified) else { throw FileProviderError.conflict("A source file changed and wasn't deleted. Copy it again to move the updated file.") }
                        try await provider.delete(current)
                    } catch FileProviderError.notFound { }
                    if let updated = try? await registry.provider(for: task.destLocation).stat(task.destPath) { AppServices.shared.favourites.relocate(task.source, to: updated) }
                }
                for directory in group.sourceDirectories.reversed() {
                    let provider = try registry.provider(for: directory.location)
                    do { if try await provider.list(directory.path).isEmpty {
                        try await provider.delete(directory)
                        if let root = group.sourceDirectories.first, let location = group.targetLocation, let final = group.finalPath {
                            let path = final + String(directory.path.dropFirst(root.path.count))
                            if let updated = try? await registry.provider(for: location).stat(path) { AppServices.shared.favourites.relocate(directory, to: updated) }
                        }
                    } } catch FileProviderError.notFound { }
                }
            }
            group.finished = true; group.lastError = nil; groups[id] = group
            let downloaded = group.targetLocation == .local || group.taskIDs.first.flatMap { id in tasks.first { $0.id == id } }?.kind == .download
            toast.show("\(downloaded ? "Downloaded" : "Uploaded") \"\(group.name)\" (\(group.taskIDs.count) files)", symbol: "checkmark")
        } catch { if groups[id]?.finished != true { group.lastError = error.localizedDescription; groups[id] = group; toast.show(error: error) } }
        persist()
    }
    @discardableResult func enqueueExternalUploads(_ urls: [URL], to location: LocationID, dirPath: String) async -> Int {
        var count = 0
        var accepted = 0
        let target: FileProvider
        var names: Set<String>
        do { target = try registry.provider(for: location); names = Set(try await target.list(dirPath).map(\.name)); names.formUnion(pendingNames(location, in: dirPath)) }
        catch { toast.show(error: error); return 0 }
        for url in urls {
            var importStage: URL?; var expanding: UUID?
            do {
                let stage = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "Coffer/Imports/" + UUID().uuidString)
                importStage = stage
                let copy = stage.appending(path: url.lastPathComponent)
                try await Task.detached {
                    let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
                    var failure: Error?; var coordinationError: NSError?
                    NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { source in do { try FileManager.default.copyItem(at: source, to: copy) } catch { failure = error } }
                    if let error = coordinationError ?? failure { throw error }
                }.value
                let source = LocalFileProvider(rootURL: stage)
                let item = try await source.stat("/" + url.lastPathComponent)
                names.formUnion(pendingNames(location, in: dirPath))
                let name = PathUtil.uniqueName(item.name, existing: names, isDirectory: item.isDirectory)
                names.insert(name)
                if item.isDirectory {
                    let id = UUID(); expanding = id
                    var group = TransferGroup(id: id, name: name)
                    group.targetLocation = location; group.finalPath = PathUtil.join(dirPath, name)
                    group.stagePath = PathUtil.join(dirPath, ".coffer-transfer-" + id.uuidString)
                    groups[id] = group
                    var folders: [(FileItem, String)] = [(item, group.stagePath!)]
                    while let (folder, path) = folders.popLast() {
                        do { _ = try await target.createFolder(named: PathUtil.name(path), in: PathUtil.parent(path)) } catch FileProviderError.alreadyExists { }
                        for child in try await source.list(folder.path) {
                            let dest = PathUtil.join(path, child.name)
                            if child.isDirectory { folders.append((child, dest)) }
                            else { var task = makeTask(child, destination: location, path: dest, move: false, group: id); task.sourceURL = source.url(for: child.path); group.taskIDs.append(task.id); tasks.append(task); count += 1; groups[id] = group }
                        }
                    }
                    group.isExpanded = true; groups[id] = group; await finishGroup(id)
                    if group.taskIDs.isEmpty { await Task.detached { try? FileManager.default.removeItem(at: stage) }.value }
                } else { var task = makeTask(item, destination: location, path: PathUtil.join(dirPath, name), move: false, group: nil); task.sourceURL = copy; tasks.append(task); count += 1 }
                accepted += 1
            } catch { if let id = expanding { cancelGroup(id) }; if let stage = importStage { await Task.detached { try? FileManager.default.removeItem(at: stage) }.value }; toast.show(error: error) }
        }
        persist(); schedule()
        if count > 0 { toast.show("Added \(count) transfers", actionTitle: "View", action: onShow) }
        return accepted
    }
}
