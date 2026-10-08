import Foundation
import Observation
import SwiftUI

@MainActor @Observable final class FileProviderRegistry {
    let local = LocalFileProvider()
    private(set) var servers: [WebDAVServer] = []
    private(set) var connecting: Set<UUID> = []
    private var providers: [UUID: WebDAVFileProvider] = [:]
    private var passwords: [UUID: String] = [:]
    private let store = JSONStore<[WebDAVServer]>(fileName: "servers.json")
    var onRemove: ((LocationID) -> Void)?
    var locations: [LocationID] { [.local] + servers.map { .webdav($0.id) } }
    func load() async {
        let store = store
        let saved = await Task.detached { store.load(default: []) }.value
        let credentials = await Task.detached { Dictionary(uniqueKeysWithValues: saved.map { ($0.id, Keychain.get(account: $0.id.uuidString)) }) }.value
        if servers.isEmpty { servers = saved; passwords = credentials }
        for server in servers { if let provider = try? provider(for: .webdav(server.id)) as? WebDAVFileProvider { await provider.cache.load() } }
    }
    func provider(for location: LocationID) throws -> FileProvider {
        switch location {
        case .local: return local
        case .webdav(let id):
            if let existing = providers[id] { return existing }
            guard let server = servers.first(where: { $0.id == id }) else { throw FileProviderError.notFound("Server") }
            let provider = WebDAVFileProvider(server: server, password: passwords[id] ?? "") { [weak self] error in Task { @MainActor in self?.setError(id, error) } }
            providers[id] = provider; return provider
        }
    }
    func displayName(for location: LocationID) -> String { switch location { case .local: return "My iPhone"; case .webdav(let id): return servers.first { $0.id == id }?.name ?? "WebDAV" } }
    func server(for location: LocationID) -> WebDAVServer? { guard case .webdav(let id) = location else { return nil }; return servers.first { $0.id == id } }
    func password(for id: UUID) -> String { passwords[id] ?? "" }
    func add(_ server: WebDAVServer, password: String) async throws { try await update(server, password: password) }
    func update(_ server: WebDAVServer, password: String) async throws {
        try await Task.detached { try Keychain.set(password, account: server.id.uuidString) }.value
        passwords[server.id] = password; providers[server.id]?.client.invalidate(); providers[server.id] = nil
        withAnimation(.smooth) { if let index = servers.firstIndex(where: { $0.id == server.id }) { servers[index] = server } else { servers.append(server) } }; store.save(servers)
    }
    func remove(_ id: UUID) {
        let location = LocationID.webdav(id); onRemove?(location); withAnimation(.smooth) { servers.removeAll { $0.id == id } }; providers[id]?.client.invalidate(); providers[id] = nil; passwords[id] = nil; store.save(servers)
        Task.detached {
            Keychain.delete(account: id.uuidString)
            try? FileManager.default.removeItem(at: JSONStore<[String: DirectoryCache.CachedListing]>(fileName: "dir-cache-" + location.key + ".json").url)
            let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "Coffer/Remote/" + location.key)
            try? FileManager.default.removeItem(at: root)
        }
    }
    /// Drops the current session and probes the server again; the outcome updates `lastError` through the provider's report callback.
    func reconnect(_ id: UUID) async {
        guard let server = servers.first(where: { $0.id == id }), !connecting.contains(id) else { return }
        withAnimation(.smooth) { _ = connecting.insert(id) }
        defer { withAnimation(.smooth) { _ = connecting.remove(id) } }
        providers[id]?.client.invalidate(); providers[id] = nil
        guard let provider = try? provider(for: .webdav(id)) as? WebDAVFileProvider else { return }
        await provider.cache.load()
        _ = try? await provider.list(server.initialPath, force: true)
    }
    func move(from: IndexSet, to: Int) { servers.move(fromOffsets: from, toOffset: to); store.save(servers) }
    private func setError(_ id: UUID, _ error: String?) { guard let index = servers.firstIndex(where: { $0.id == id }), servers[index].lastError != error else { return }; servers[index].lastError = error; store.save(servers) }
}
