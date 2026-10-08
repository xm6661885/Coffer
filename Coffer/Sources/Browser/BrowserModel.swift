import Foundation
import Observation
import SwiftUI

enum SearchScope: String { case folder, all }
@MainActor @Observable final class BrowserModel {
    let location: LocationID
    let path: String
    private(set) var items: [FileItem] = []
    var query = ""
    var selection = Set<FileItem.ID>()
    private(set) var isLoading = false
    private(set) var isStale = false
    private(set) var error: Error?
    var scope = SearchScope.folder
    private var searchResults: [FileItem] = []
    let registry: FileProviderRegistry
    let settings: AppSettings
    init(route: BrowserRoute, registry: FileProviderRegistry, settings: AppSettings) { location = route.location; path = route.path; self.registry = registry; self.settings = settings }
    convenience init(route: BrowserRoute) { self.init(route: route, registry: AppServices.shared.registry, settings: AppServices.shared.settings) }
    var visibleItems: [FileItem] {
        let source = scope == .all && !query.isEmpty ? searchResults : items
        return source.filter { (settings.showHiddenFiles || !$0.isHidden) && (query.isEmpty || $0.name.localizedStandardContains(query)) }.sorted { a, b in
            if settings.foldersOnTop && a.isDirectory != b.isDirectory { return a.isDirectory }
            var result = a.name.localizedStandardCompare(b.name)
            switch settings.sortKey {
            case .name: break
            case .date: if a.modified != b.modified { result = (a.modified ?? .distantPast) < (b.modified ?? .distantPast) ? .orderedAscending : .orderedDescending }
            case .size: if a.size != b.size { result = (a.size ?? 0) < (b.size ?? 0) ? .orderedAscending : .orderedDescending }
            case .kind: if a.kind != b.kind { result = a.kind.rawValue.compare(b.kind.rawValue) }
            }
            if result == .orderedSame { result = a.path.localizedStandardCompare(b.path) }
            return result == (settings.sortAscending ? .orderedAscending : .orderedDescending)
        }
    }
    var title: String { path == "/" ? registry.displayName(for: location) : PathUtil.name(path) }
    func load() async { if items.isEmpty { await reload() } }
    func reload(force: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true; defer { isLoading = false }
        do {
            let provider = try registry.provider(for: location)
            if let dav = provider as? WebDAVFileProvider, let cached = dav.cachedList(path), items.isEmpty { withAnimation(.smooth) { items = cached; isStale = true } }
            let result: [FileItem]
            if let dav = provider as? WebDAVFileProvider { result = try await dav.list(path, force: force) } else { result = try await provider.list(path) }; try Task.checkCancellation(); withAnimation(.smooth) { items = result; selection.formIntersection(Set(result.map(\.id))); error = nil; isStale = false } }
        catch is CancellationError { }
        catch { self.error = error; isStale = location.isRemote && !items.isEmpty }
    }
    func searchEverywhere() async {
        guard location == .local && scope == .all && !query.isEmpty else { searchResults = []; return }
        let query = query
        do { let results = try await registry.local.recursiveList(limit: 100_000); try Task.checkCancellation(); searchResults = Array(results.filter { $0.name.localizedStandardContains(query) }.prefix(500)) }
        catch is CancellationError { }
        catch { self.error = error }
    }
}
