import Foundation
import Observation

@MainActor @Observable final class TextEditorModel {
    enum ConflictChoice { case overwrite, copy, cancel }
    var item: FileItem
    private(set) var isDraft: Bool
    var text = ""
    private(set) var saved = ""
    var encoding: String.Encoding = .utf8
    var crlf = false
    var loaded = false
    var readOnly = false
    var status = "Saved"
    var changedOutside = false
    var serverConflict = false
    var localConflict = false
    var saveFailure = false
    var failure: String?
    var previewURL: URL?
    private var originalData = Data()
    private var bom = Data()
    private var originalEncoding: String.Encoding = .utf8
    private var localURL: URL?
    private var knownModified: Date?
    private var knownSize: Int64?
    private var knownETag: String?
        private var saveCancelled = false
    private var saving: Task<Bool, Never>?
    private var conflictContinuation: CheckedContinuation<ConflictChoice, Never>?
    private let services: AppServices
    init(item: FileItem, services: AppServices, isDraft: Bool = false) { self.item = item; self.services = services; self.isDraft = isDraft }
    var edited: Bool { text != saved || status == "Edited" }
    func load() async {
        if isDraft { loaded = true; status = "Draft"; return }
        do {
            let actual = try await services.registry.provider(for: item.location).stat(item.path); item = actual; knownModified = actual.modified; knownSize = actual.size; knownETag = actual.etag
            let url = item.location.isRemote ? try await services.remoteCache.fetch(item, progress: { _ in }) : services.registry.local.url(for: item.path)
            localURL = url; readOnly = (actual.size ?? 0) > 10 * 1024 * 1024
            let data = try await TextDecoding.readPrefix(url, maxBytes: readOnly ? 5 * 1024 * 1024 : 10 * 1024 * 1024 + 1)
            originalData = data; let decoded = TextDecoding.decode(data); encoding = decoded.encoding; originalEncoding = encoding
            bom = TextEncoding.bom(data)
            crlf = decoded.text.contains("\r\n"); text = TextEncoding.normalized(decoded.text); saved = text; loaded = true; status = "Saved"; changedOutside = false; failure = nil
            services.recents.add(item)
        } catch { failure = error.localizedDescription; services.toast.show(error: error) }
    }
    func changed() { guard loaded && !readOnly else { return }; status = isDraft ? "Draft" : "Edited" }
    func changeEncoding(_ encoding: String.Encoding) { self.encoding = encoding; if isDraft { changed(); return }; let decoded = TextDecoding.decode(originalData, preferred: encoding); text = TextEncoding.normalized(decoded.text); changed() }
    func chooseConflict(_ choice: ConflictChoice) { serverConflict = false; localConflict = false; let continuation = conflictContinuation; conflictContinuation = nil; continuation?.resume(returning: choice) }
    func save(closing: Bool = false) async -> Bool {
        if !loaded || readOnly { return true }; if !edited && !isDraft { return true }
        if let saving { let result = await saving.value; if result && closing && edited { self.saving = nil; return await save(closing: true) }; return result }
        saveCancelled = false; let task = Task { await write() }; saving = task; let result = await task.value; saving = nil; if result && closing && edited { return await save(closing: true) }; if !result && closing && !serverConflict && !saveCancelled { saveFailure = true }; return result
    }
    private func write() async -> Bool {
        var url = localURL ?? (item.location.isRemote ? services.remoteCache.localURL(for: item) : services.registry.local.url(for: item.path))
        let revision = text
        let data: Data
        do { data = try TextEncoding.encode(revision, encoding: encoding, crlf: crlf, bom: bom, originalEncoding: originalEncoding) }
        catch { status = "Not saved"; failure = error.localizedDescription; services.toast.show(error: error); return false }
        status = "Saving…"
        do {
            if isDraft {
                let provider = try services.registry.provider(for: item.location)
                let updated = try await provider.createFile(named: item.name, in: item.parentPath, data: data)
                item = updated; knownModified = updated.modified; knownSize = updated.size; knownETag = updated.etag
                isDraft = false; localURL = url
                if item.location.isRemote { try await atomicWrite(data, url: url); try await services.remoteCache.recordUpdated(updated) }
            } else if let provider = try services.registry.provider(for: item.location) as? WebDAVFileProvider {
                let current: FileItem?
                do { current = try await provider.stat(item.path) } catch FileProviderError.notFound { current = nil }
                if let current, current.etag != knownETag || (current.etag == nil && current.modified != knownModified) {
                    let choice = await withCheckedContinuation { conflictContinuation = $0; serverConflict = true }
                    switch choice {
                    case .cancel: status = "Not saved"; saveCancelled = true; return false
                    case .overwrite: break
                    case .copy:
                        let extensionText = item.ext.isEmpty ? "" : "." + item.ext
                        let desired = PathUtil.baseName(item.name) + " (Conflict)" + extensionText
                        let names = Set(try await provider.list(item.parentPath).map(\.name)); let name = PathUtil.uniqueName(desired, existing: names, isDirectory: false)
                        let copyPath = PathUtil.join(item.parentPath, name)
                        item = FileItem(location: item.location, path: copyPath, name: name, isDirectory: false, size: Int64(data.count), modified: nil, created: nil, etag: nil, contentType: item.contentType); knownETag = nil; knownModified = nil; url = services.remoteCache.localURL(for: item); localURL = url
                    }
                }
                try await atomicWrite(data, url: url)
                if data.count > 5 * 1024 * 1024 { try await Uploader(client: provider.client, source: url, destination: item.path, onProgress: { _ in }).run() } else { try await provider.client.put(data: data, to: item.path) }
                let updated = try await provider.stat(item.path); item = updated; knownETag = updated.etag; knownModified = updated.modified; try await services.remoteCache.recordUpdated(updated)
            } else {
                let current = try await services.registry.local.stat(item.path)
                if current.modified != knownModified || current.size != knownSize {
                    changedOutside = true
                    let choice = await withCheckedContinuation { conflictContinuation = $0; localConflict = true }
                    if choice != .overwrite { status = "Not saved"; saveCancelled = true; return false }
                }
                try await atomicWrite(data, url: url); let updated = try await services.registry.local.stat(item.path); item = updated; knownModified = updated.modified; knownSize = updated.size }
            originalData = data; saved = revision; changedOutside = false; status = text == revision ? "Saved" : "Edited"; failure = nil
            services.operations.changed(item.location, item.parentPath); services.recents.add(item)
            return true
        } catch { status = "Not saved"; failure = error.localizedDescription; services.toast.show(error: error); return false }
    }
    private func atomicWrite(_ data: Data, url: URL) async throws { try await Task.detached { let fm = FileManager.default; try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true); let temporary = url.deletingLastPathComponent().appending(path: ".coffer-save-" + UUID().uuidString); do { try data.write(to: temporary, options: .atomic); if fm.fileExists(atPath: url.path) { _ = try fm.replaceItemAt(url, withItemAt: temporary) } else { try fm.moveItem(at: temporary, to: url) } } catch { try? fm.removeItem(at: temporary); throw error } }.value }
    func checkExternalChange() async {
        guard loaded && !isDraft && item.location == .local && saving == nil else { return }
        do { let current = try await services.registry.local.stat(item.path); if current.modified != knownModified || current.size != knownSize { if edited { changedOutside = true } else { await load() } } } catch { changedOutside = true }
    }
    func preparePreview() async { let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + "." + item.ext); do { let data = Data(text.utf8); try await Task.detached { try data.write(to: url, options: .atomic) }.value; previewURL = url } catch { services.toast.show(error: error) } }
    func nameDraft(_ name: String) { guard isDraft else { return }; item = FileItem(location: item.location, path: PathUtil.join(item.parentPath, name), name: name, isDirectory: false, size: 0, modified: nil, created: nil, etag: nil, contentType: "text/markdown") }
    func renamed(_ updated: FileItem) { item = updated; localURL = updated.location.isRemote ? services.remoteCache.localURL(for: updated) : services.registry.local.url(for: updated.path); Task { await load() } }
    func cancel() { chooseConflict(.cancel); if let previewURL { Task.detached { try? FileManager.default.removeItem(at: previewURL) } } }
}
