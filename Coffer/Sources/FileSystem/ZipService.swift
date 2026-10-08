import Foundation
import ZIPFoundation

enum ZipService {
    static func archive(_ url: URL) throws -> Archive {
        let archive = try Archive(url: url, accessMode: .read)
        if archive.contains(where: { $0.path.contains("\u{FFFD}") }), let gb = TextDecoding.encodings.first(where: { $0.0 == "GB18030" })?.1 { return try Archive(url: url, accessMode: .read, pathEncoding: gb) }
        return archive
    }
    static func compress(items: [URL], into dir: URL, name: String, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let reporting = Progress(); var lastReport = Date.distantPast
            let observation = reporting.observe(\.fractionCompleted, options: [.new]) { value, _ in if Date().timeIntervalSince(lastReport) > 0.25 || value.fractionCompleted >= 1 { lastReport = Date(); progress(value.fractionCompleted) } }
            defer { observation.invalidate() }
            let existing = Set(try fm.contentsOfDirectory(atPath: dir.path))
            let destination = dir.appending(path: PathUtil.uniqueName(name, existing: existing, isDirectory: false))
            if items.count == 1, let source = items.first { try fm.zipItem(at: source, to: destination, shouldKeepParent: true, compressionMethod: .deflate, progress: reporting) }
            else {
                let temp = fm.temporaryDirectory.appending(path: UUID().uuidString)
                try fm.createDirectory(at: temp, withIntermediateDirectories: true)
                defer { try? fm.removeItem(at: temp) }
                var names: Set<String> = []
                for source in items {
                    let folder = (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                    let name = PathUtil.uniqueName(source.lastPathComponent, existing: names, isDirectory: folder)
                    try fm.copyItem(at: source, to: temp.appending(path: name)); names.insert(name)
                }
                try fm.zipItem(at: temp, to: destination, shouldKeepParent: false, compressionMethod: .deflate, progress: reporting)
            }
            progress(1); return destination
        }.value
    }
    static func uncompress(_ url: URL, into dir: URL, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let name = PathUtil.uniqueName(PathUtil.baseName(url.lastPathComponent), existing: Set(try fm.contentsOfDirectory(atPath: dir.path)), isDirectory: true)
            let destination = dir.appending(path: name)
            try fm.createDirectory(at: destination, withIntermediateDirectories: false)
            do {
                let archive = try archive(url)
                let entries = Array(archive)
                for (index, entry) in entries.enumerated() {
                    try Task.checkCancellation()
                    let target = destination.appending(path: entry.path).standardizedFileURL
                    guard PathUtil.isAncestor(destination.path, of: target.resolvingSymlinksInPath().path) else { throw FileProviderError.invalidName }
                    _ = try archive.extract(entry, to: target)
                    progress(Double(index + 1) / Double(max(1, entries.count)))
                }
            } catch { try? fm.removeItem(at: destination); throw error }
            return destination
        }.value
    }
}
