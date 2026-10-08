import Foundation

@MainActor struct MediaSourceResolver {
    let registry: FileProviderRegistry; let cache: RemoteCache; let settings: AppSettings
    func resolve(_ ref: MediaRef, preloadOnly: Bool = false, progress: @escaping (Double) -> Void = { _ in }) async throws -> (MediaSource, PlaybackEngine) {
        let item: FileItem
        do {
            let provider = try registry.provider(for: ref.location)
            if let dav = provider as? WebDAVFileProvider,
               let fresh = dav.cache.get(PathUtil.parent(ref.path), freshOnly: true)?.first(where: { $0.path == PathUtil.normalized(ref.path) }) { item = fresh }
            else { item = try await provider.stat(ref.path) }
        }
        catch {
            if ref.location.isRemote, let cached = cache.cachedItem(for: ref.id) {
                let url = cache.localURL(for: cached)
                if await Task.detached(operation: { FileManager.default.fileExists(atPath: url.path) }).value { return (MediaSource(url: url, headers: [:], isLocal: true, title: ref.name), FileKind.engine(forExt: cached.ext)) }
            }
            throw error
        }
        let engine = FileKind.engine(forExt: item.ext)
        if ref.location == .local { return (MediaSource(url: registry.local.url(for: ref.path), headers: [:], isLocal: true, title: ref.name), engine) }
        if cache.isCached(item) { return (MediaSource(url: cache.localURL(for: item), headers: [:], isLocal: true, title: ref.name), engine) }
        guard let provider = try registry.provider(for: ref.location) as? WebDAVFileProvider else { throw FileProviderError.notFound(ref.name) }
        if settings.streamRemoteMedia {
            if item.kind == .video, (item.size ?? 0) > 0 {
                let stream = try RemoteVideoStream(client: provider.client, item: item, preloadOnly: preloadOnly)
                do { return (MediaSource(url: try await stream.start(), headers: [:], isLocal: false, title: ref.name, stream: stream), engine) }
                catch { stream.close(); throw error }
            }
            if !provider.client.server.allowSelfSigned {
                return (MediaSource(url: provider.client.url(for: ref.path), headers: ["Authorization": provider.client.authHeader], isLocal: false, title: ref.name), engine)
            }
        }
        guard !preloadOnly else { throw FileProviderError.other("This video cannot be preloaded without downloading it.") }
        return (MediaSource(url: try await cache.fetch(item, progress: progress), headers: [:], isLocal: true, title: ref.name), engine)
    }
}
