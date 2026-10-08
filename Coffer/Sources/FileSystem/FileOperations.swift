import Foundation
import Observation

@MainActor @Observable final class FileOperations {
    enum ConflictChoice { case replace, keepBoth, skip, cancel }
    struct ConflictPrompt: Identifiable { var id = UUID(); let name: String; let remaining: Int; let resume: (ConflictChoice, Bool) -> Void }
    var conflict: ConflictPrompt?
    var conflictPickerCount = 0
    let registry: FileProviderRegistry
    let toast: ToastCenter
    let transfers: TransferManager
    var lastTransferSucceeded = false
    var lastTransferredIDs: Set<String> = []
    private var transferBusy = false
    private var transferWaiters: [CheckedContinuation<Void, Never>] = []
    private func releaseTransfer() { if transferWaiters.isEmpty { transferBusy = false } else { transferWaiters.removeFirst().resume() } }
    init(registry: FileProviderRegistry, toast: ToastCenter, transfers: TransferManager) { self.transfers = transfers; self.registry = registry; self.toast = toast }
    func changed(_ location: LocationID, _ path: String) { if let provider = try? registry.provider(for: location) as? WebDAVFileProvider { provider.cache.invalidate([path]) }; NotificationCenter.default.post(name: .cofferDirectoryChanged, object: nil, userInfo: ["location": location, "path": path]) }
    func createFolder(named: String, location: LocationID, in dir: String) async -> FileItem? {
        do { let item = try await registry.provider(for: location).createFolder(named: named, in: dir); changed(location, dir); toast.show("Created \"\(named)\"", symbol: "folder.badge.plus"); return item }
        catch { toast.show(error: error); return nil }
    }
    func createTextFile(named: String, location: LocationID, in dir: String) async -> FileItem? {
        do { let item = try await registry.provider(for: location).createFile(named: named, in: dir, data: Data()); changed(location, dir); return item }
        catch { toast.show(error: error); return nil }
    }
    func rename(_ item: FileItem, to newName: String) async -> FileItem? {
        do { let result = try await registry.provider(for: item.location).rename(item, to: newName); AppServices.shared.favourites.relocate(item, to: result); changed(item.location, item.parentPath); toast.show("Renamed", symbol: "checkmark"); return result }
        catch { toast.show(error: error); return nil }
    }
    func delete(_ items: [FileItem]) async {
        var failures = 0; var last: Error?
        for item in items {
            do { try await registry.provider(for: item.location).delete(item); AppServices.shared.favourites.removeTree(item); changed(item.location, item.parentPath) }
            catch { failures += 1; last = error }
        }
        if failures > 0 { toast.show("Couldn't delete \(failures) item\(failures == 1 ? "" : "s") — \(last?.localizedDescription ?? "")", symbol: "exclamationmark.triangle") }
    }
    func transfer(_ items: [FileItem], to destLocation: LocationID, destDir: String, move: Bool) async {
        if transferBusy { await withCheckedContinuation { transferWaiters.append($0) } } else { transferBusy = true }
        defer { releaseTransfer() }
        lastTransferSucceeded = false; lastTransferredIDs = []
        guard !Task.isCancelled else { return }
        do {
            let provider = try registry.provider(for: destLocation)
            var names = Set(try await provider.list(destDir).map(\.name)); var all: ConflictChoice?; var count = 0; var queued = 0
            names.formUnion(transfers.pendingNames(destLocation, in: destDir))
            for (index, item) in items.enumerated() {
                if Task.isCancelled { break }
                var name = item.name; var overwrite = false
                if item.location == destLocation && item.parentPath == destDir && !move { name = PathUtil.uniqueName(name, existing: names, isDirectory: item.isDirectory) }
                else if names.contains(where: { $0.lowercased() == name.lowercased() }) {
                    let choice: ConflictChoice
                    if let all { choice = all }
                    else {
                        let owner = UUID()
                        let result: (ConflictChoice, Bool) = await withTaskCancellationHandler(operation: { await withCheckedContinuation { continuation in
                            conflict = ConflictPrompt(id: owner, name: name, remaining: items.count - index - 1) { c, apply in self.conflict = nil; continuation.resume(returning: (c, apply)) }
                        }
                        }, onCancel: { Task { @MainActor in if self.conflict?.id == owner { self.conflict?.resume(.cancel, false) } } })
                        choice = result.0; if result.1 { all = choice }
                    }
                    switch choice { case .cancel: return; case .skip: continue; case .replace: overwrite = true; case .keepBoth: name = PathUtil.uniqueName(name, existing: names, isDirectory: item.isDirectory) }
                }
                if overwrite { await transfers.cancelDestination(destLocation, path: PathUtil.join(destDir, name)); guard !Task.isCancelled else { return } }
                if item.location != destLocation {
                    guard await transfers.enqueue(item, destination: destLocation, path: PathUtil.join(destDir, name), move: move) else { continue }
                    names.insert(name); queued += 1; lastTransferredIDs.insert(item.id); continue
                }
                do {
                    if move { try await provider.move(item, toDir: destDir, newName: name, overwrite: overwrite) } else { try await provider.copy(item, toDir: destDir, newName: name, overwrite: overwrite) }
                    if move, let updated = try? await provider.stat(PathUtil.join(destDir, name)) { AppServices.shared.favourites.relocate(item, to: updated) }; names.insert(name); count += 1; lastTransferredIDs.insert(item.id); changed(item.location, item.parentPath); changed(destLocation, destDir)
                } catch { toast.show(error: error) }
            }
            lastTransferSucceeded = count + queued == items.count
            if queued > 0 { toast.show("Added \(queued) transfers", actionTitle: "View", action: transfers.onShow) }
            if count > 0 { toast.show("\(move ? "Moved" : "Copied") \(count) items", symbol: "checkmark") }
        } catch { toast.show(error: error) }
    }
}
