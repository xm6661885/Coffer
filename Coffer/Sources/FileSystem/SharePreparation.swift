import Foundation

@MainActor enum SharePreparation {
    static func urls(for items: [FileItem]) async throws -> [URL] {
        let services = AppServices.shared
        var result: [URL] = []
        if items.contains(where: { $0.location.isRemote }) { services.toast.show("Preparing…", symbol: "square.and.arrow.up") }
        for item in items {
            if item.location == .local { result.append(services.registry.local.url(for: item.path)) }
            else if !item.isDirectory { result.append(try await services.remoteCache.fetch(item) { value in if value >= 0 { services.toast.show("Preparing… \(Int(value * 100))%", symbol: "square.and.arrow.up") } }) }
            else {
                let provider = try services.registry.provider(for: item.location)
                let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: item.name)
                try await Task.detached { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }.value
                var pending: [(String, URL)] = [(item.path, root)]; var count = 0
                while let (path, directory) = pending.popLast() {
                    for child in try await provider.list(path) {
                        try Task.checkCancellation(); count += 1
                        guard count <= 5000 else { throw FileProviderError.other("This folder has too many files to share at once.") }
                        let target = directory.appending(path: child.name)
                        if child.isDirectory { try await Task.detached { try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true) }.value; pending.append((child.path, target)) }
                        else { let cached = try await services.remoteCache.fetch(child, progress: { _ in }); try await Task.detached { try FileManager.default.copyItem(at: cached, to: target) }.value }
                    }
                }
                result.append(root)
            }
        }
        return result
    }
}
