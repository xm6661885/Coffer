import Foundation
import Observation
import CoreTransferable
import UniformTypeIdentifiers

@MainActor @Observable final class ImportService {
    struct PendingImport: Identifiable { let id = UUID(); var urls: [URL] }
    var pending: PendingImport?
    private(set) var lastImportedURLs: Set<URL> = []
    private var incoming: [URL] = []
    private var merge: Task<Void, Never>?
    let registry: FileProviderRegistry
    let toast: ToastCenter
    var onReveal: ((String) -> Void)?
    init(registry: FileProviderRegistry, toast: ToastCenter) { self.registry = registry; self.toast = toast }
    func handleOpenURL(_ url: URL) {
        guard url.isFileURL else { toast.show("This link isn't a file."); return }
        incoming.append(url); merge?.cancel()
        merge = Task { try? await Task.sleep(for: .milliseconds(500)); guard !Task.isCancelled else { return }; if pending != nil { pending?.urls.append(contentsOf: incoming) } else { pending = PendingImport(urls: incoming) }; incoming.removeAll() }
    }
    func importFiles(_ urls: [URL], to dirPath: String, move: Bool) async -> [FileItem] {
        var result: [FileItem] = []; lastImportedURLs = []
        do {
            let local = registry.local
            var names = Set(try await local.list(dirPath).map(\.name))
            for url in urls {
                if Task.isCancelled { break }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    let folder = (try? await Task.detached { try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true }.value) ?? false
                    let name = PathUtil.uniqueName(url.lastPathComponent, existing: names, isDirectory: folder)
                    let destination = local.url(for: PathUtil.join(dirPath, name))
                    try await Task.detached {
                        let fm = FileManager.default
                        let inbox = local.rootURL.appending(path: "Inbox").standardizedFileURL.path
                        if PathUtil.isAncestor(inbox, of: url.standardizedFileURL.path) || (move && PathUtil.isAncestor(fm.temporaryDirectory.path, of: url.path)) { try fm.moveItem(at: url, to: destination) }
                        else {
                            var coordinationError: NSError?; var operationError: Error?
                            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in do { try fm.copyItem(at: readURL, to: destination) } catch { operationError = error } }
                            if let error = coordinationError ?? operationError as NSError? { throw error }
                        }
                        let inboxURL = local.rootURL.appending(path: "Inbox")
                        if let children = try? fm.contentsOfDirectory(atPath: inboxURL.path), children.isEmpty { try? fm.removeItem(at: inboxURL) }
                    }.value
                    let item = try await local.stat(PathUtil.join(dirPath, name)); result.append(item); lastImportedURLs.insert(url); names.insert(name)
                } catch { toast.show(error: error) }
            }
            NotificationCenter.default.post(name: .cofferDirectoryChanged, object: nil, userInfo: ["location": LocationID.local, "path": dirPath])
            let count = result.count
            if count > 0 { toast.show("Imported \(count) item(s)", symbol: "tray.and.arrow.down", actionTitle: "Show") { [weak self] in self?.onReveal?(dirPath) } }
        } catch { toast.show(error: error) }
        return result
    }
    func cancelPending() {
        let urls = pending?.urls ?? []; pending = nil; let inbox = registry.local.rootURL.appending(path: "Inbox").path
        Task.detached { for url in urls where PathUtil.isAncestor(inbox, of: url.path) { try? FileManager.default.removeItem(at: url) } }
    }
}
struct FileTransferable: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .item) { received in
            let destination = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: received.file.lastPathComponent)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return FileTransferable(url: destination)
        }
    }
}
