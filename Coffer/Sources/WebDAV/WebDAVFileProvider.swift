import Foundation

final class WebDAVFileProvider: FileProvider, @unchecked Sendable {
    let location: LocationID
    let client: WebDAVClient
    let cache: DirectoryCache
    let report: @Sendable (String?) -> Void
    init(server: WebDAVServer, password: String, report: @escaping @Sendable (String?) -> Void = { _ in }) { location = .webdav(server.id); client = WebDAVClient(server: server, password: password); cache = DirectoryCache(location: location); self.report = report }
    func cachedList(_ path: String) -> [FileItem]? { cache.get(path) }
    func list(_ dirPath: String) async throws -> [FileItem] { try await list(dirPath, force: false) }
    func list(_ dirPath: String, force: Bool) async throws -> [FileItem] {
        if !force, let items = cache.get(dirPath, freshOnly: true) { return items }
        do { let items = try await client.propfind(dirPath, depth: 1); cache.set(dirPath, items: items); report(nil); return items }
        catch { report(error.localizedDescription); throw error }
    }
    func stat(_ path: String) async throws -> FileItem { guard let item = try await client.propfind(path, depth: 0).first(where: { $0.path == PathUtil.normalized(path) }) else { throw FileProviderError.notFound(PathUtil.name(path)) }; return item }
    private func validateName(_ name: String) throws { guard PathUtil.isValidName(name) else { throw FileProviderError.invalidName } }
    private func changed(_ paths: [String]) { cache.invalidate(paths); for path in paths { NotificationCenter.default.post(name: .cofferDirectoryChanged, object: nil, userInfo: ["location": location, "path": path]) } }
    func createFolder(named name: String, in dirPath: String) async throws -> FileItem { try validateName(name); let path = PathUtil.join(dirPath, name); try await client.mkcol(path); changed([dirPath]); return try await stat(path) }
    func createFile(named name: String, in dirPath: String, data: Data) async throws -> FileItem {
        try validateName(name); let path = PathUtil.join(dirPath, name)
        do { _ = try await stat(path); throw FileProviderError.alreadyExists(name) } catch FileProviderError.notFound { }
        try await client.put(data: data, to: path); changed([dirPath]); return try await stat(path)
    }
    func rename(_ item: FileItem, to newName: String) async throws -> FileItem { try validateName(newName); if item.name == newName { return item }; let path = PathUtil.join(item.parentPath, newName); try await client.move(from: item.path, to: path, isDirectory: item.isDirectory, overwrite: false); changed([item.parentPath]); return try await stat(path) }
    func delete(_ item: FileItem) async throws { guard item.path != "/" else { throw FileProviderError.forbidden }; try await client.delete(item.path, isDirectory: item.isDirectory); changed([item.parentPath]) }
    func copy(_ item: FileItem, toDir: String, newName: String, overwrite: Bool) async throws { try validateName(newName); try await client.copy(from: item.path, to: PathUtil.join(toDir, newName), isDirectory: item.isDirectory, overwrite: overwrite); changed([toDir]) }
    func move(_ item: FileItem, toDir: String, newName: String, overwrite: Bool) async throws { try validateName(newName); try await client.move(from: item.path, to: PathUtil.join(toDir, newName), isDirectory: item.isDirectory, overwrite: overwrite); changed([item.parentPath, toDir]) }
}
