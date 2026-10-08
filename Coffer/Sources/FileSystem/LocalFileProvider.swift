import Foundation

final class LocalFileProvider: FileProvider, @unchecked Sendable {
    let location: LocationID = .local
    let rootURL: URL
    init(rootURL: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]) { self.rootURL = rootURL }
    func url(for path: String) -> URL { path == "/" ? rootURL : rootURL.appending(path: String(path.dropFirst())) }
    private func checkedURL(_ path: String) throws -> URL {
        guard path.hasPrefix("/"), !PathUtil.components(path).contains(where: { $0 == ".." || $0 == "." }) else { throw FileProviderError.invalidName }
        let result = url(for: path)
        guard PathUtil.isAncestor(rootURL.resolvingSymlinksInPath().path, of: result.resolvingSymlinksInPath().path) else { throw FileProviderError.forbidden }
        return result
    }
    private func item(_ path: String) throws -> FileItem {
        let u = try checkedURL(path)
        let v = try u.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey])
        let isDirectory = v.isSymbolicLink == true ? (try u.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true : v.isDirectory == true
        return FileItem(location: .local, path: PathUtil.normalized(path), name: path == "/" ? "My iPhone" : PathUtil.name(path), isDirectory: isDirectory, size: isDirectory ? nil : v.fileSize.map(Int64.init), modified: v.contentModificationDate, created: v.creationDate, etag: nil, contentType: nil)
    }
    private func perform<T>(_ name: String, _ action: @escaping @Sendable () throws -> T) async throws -> T {
        do { return try await Task.detached(priority: .userInitiated) { try action() }.value }
        catch { throw FileProviderError.mapped(error, name: name) }
    }
    func list(_ dirPath: String) async throws -> [FileItem] {
        try await perform(PathUtil.name(dirPath)) {
            let urls = try FileManager.default.contentsOfDirectory(at: self.checkedURL(dirPath), includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey, .isSymbolicLinkKey])
            return try urls.compactMap { u in let i = try self.item(PathUtil.join(dirPath, u.lastPathComponent)); return dirPath == "/" && i.name == "Inbox" && i.isDirectory ? nil : i }
        }
    }
    func stat(_ path: String) async throws -> FileItem { try await perform(PathUtil.name(path)) { try self.item(path) } }
    func createFolder(named name: String, in dirPath: String) async throws -> FileItem {
        try await perform(name) {
            guard PathUtil.isValidName(name) else { throw FileProviderError.invalidName }
            let path = PathUtil.join(dirPath, name), u = try self.checkedURL(path)
            guard !FileManager.default.fileExists(atPath: u.path) else { throw FileProviderError.alreadyExists(name) }
            try FileManager.default.createDirectory(at: u, withIntermediateDirectories: false)
            return try self.item(path)
        }
    }
    func createFile(named name: String, in dirPath: String, data: Data) async throws -> FileItem {
        try await perform(name) {
            guard PathUtil.isValidName(name) else { throw FileProviderError.invalidName }
            let path = PathUtil.join(dirPath, name); try data.write(to: self.checkedURL(path), options: .withoutOverwriting)
            return try self.item(path)
        }
    }
    func rename(_ item: FileItem, to newName: String) async throws -> FileItem {
        try await perform(newName) {
            guard PathUtil.isValidName(newName), item.path != "/" else { throw FileProviderError.invalidName }
            if newName == item.name { return item }
            let fm = FileManager.default, src = try self.checkedURL(item.path), destPath = PathUtil.join(item.parentPath, newName), dst = try self.checkedURL(destPath)
            if item.name.lowercased() == newName.lowercased() {
                let temp = src.deletingLastPathComponent().appending(path: "." + UUID().uuidString)
                try fm.moveItem(at: src, to: temp)
                do { try fm.moveItem(at: temp, to: dst) } catch { try? fm.moveItem(at: temp, to: src); throw error }
            } else {
                guard !fm.fileExists(atPath: dst.path) else { throw FileProviderError.alreadyExists(newName) }
                try fm.moveItem(at: src, to: dst)
            }
            return try self.item(destPath)
        }
    }
    func delete(_ item: FileItem) async throws { try await perform(item.name) { guard item.path != "/" else { throw FileProviderError.forbidden }; try FileManager.default.removeItem(at: self.checkedURL(item.path)) } }
    private func relocate(_ item: FileItem, dir: String, name: String, overwrite: Bool, move: Bool) async throws {
        try await perform(name) {
            guard PathUtil.isValidName(name), item.path != "/" else { throw FileProviderError.invalidName }
            let target = PathUtil.join(dir, name)
            if item.isDirectory && PathUtil.isAncestor(item.path, of: target) { throw FileProviderError.other("You can't move a folder into itself.") }
            if target == item.path { throw FileProviderError.other("The source and destination are the same.") }
            let fm = FileManager.default, src = try self.checkedURL(item.path), dst = try self.checkedURL(target)
            let existed = fm.fileExists(atPath: dst.path)
            guard !existed || overwrite else { throw FileProviderError.alreadyExists(name) }
            let stage = dst.deletingLastPathComponent().appending(path: ".coffer-operation-" + UUID().uuidString)
            let backup = dst.deletingLastPathComponent().appending(path: ".coffer-replace-" + UUID().uuidString)
            do {
                if move { try fm.moveItem(at: src, to: stage) } else { try fm.copyItem(at: src, to: stage) }
                if existed { try fm.moveItem(at: dst, to: backup) }
                do { try fm.moveItem(at: stage, to: dst) }
                catch { if existed { try? fm.moveItem(at: backup, to: dst) }; throw error }
                if existed { try? fm.removeItem(at: backup) }
            } catch {
                if move && fm.fileExists(atPath: stage.path) && !fm.fileExists(atPath: src.path) { try? fm.moveItem(at: stage, to: src) }
                else { try? fm.removeItem(at: stage) }
                throw error
            }
        }
    }
    func copy(_ item: FileItem, toDir: String, newName: String, overwrite: Bool) async throws { try await relocate(item, dir: toDir, name: newName, overwrite: overwrite, move: false) }
    func move(_ item: FileItem, toDir: String, newName: String, overwrite: Bool) async throws { try await relocate(item, dir: toDir, name: newName, overwrite: overwrite, move: true) }
    func recursiveList(_ path: String = "/", limit: Int = 5000) async throws -> [FileItem] {
        try await perform(PathUtil.name(path)) {
            let u = try self.checkedURL(path)
            guard let enumerator = FileManager.default.enumerator(at: u, includingPropertiesForKeys: [.isDirectoryKey], options: []) else { return [] }
            var result: [FileItem] = []
            for case let url as URL in enumerator {
                try Task.checkCancellation()
                let p = "/" + String(url.path.dropFirst(self.rootURL.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if PathUtil.isAncestor("/Inbox", of: p) { enumerator.skipDescendants(); continue }
                result.append(try self.item(p)); if result.count >= limit { break }
            }
            return result
        }
    }
}
