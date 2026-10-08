import Foundation

final class DirectoryCache: @unchecked Sendable {
    struct CachedListing: Codable { var items: [FileItem]; var fetchedAt: Date; var accessedAt: Date }
    private var listings: [String: CachedListing] = [:]
    private let lock = NSLock()
    private let store: JSONStore<[String: CachedListing]>
    init(location: LocationID) { store = JSONStore(fileName: "dir-cache-" + location.key + ".json") }
    func load() async { let saved = await Task.detached { self.store.load(default: [:]) }.value; install(saved) }
    private func install(_ saved: [String: CachedListing]) { lock.lock(); defer { lock.unlock() }; listings.merge(saved) { current, _ in current } }
    func get(_ path: String, freshOnly: Bool = false) -> [FileItem]? {
        lock.lock(); defer { lock.unlock() }
        guard var listing = listings[path], !freshOnly || Date().timeIntervalSince(listing.fetchedAt) < 30 else { return nil }
        listing.accessedAt = Date(); listings[path] = listing; return listing.items
    }
    func set(_ path: String, items: [FileItem]) {
        lock.lock(); defer { lock.unlock() }
        listings[path] = CachedListing(items: items, fetchedAt: Date(), accessedAt: Date())
        if listings.count > 300, let oldest = listings.min(by: { $0.value.accessedAt < $1.value.accessedAt })?.key { listings.removeValue(forKey: oldest) }
        store.save(listings)
    }
    func invalidate(_ paths: [String]) { lock.lock(); defer { lock.unlock() }; for path in paths { listings.removeValue(forKey: path) }; store.save(listings) }
}
