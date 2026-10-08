import Foundation
import UniformTypeIdentifiers

enum UploadFileKind: Sendable { case files, music, videos, pictures
    var fileKind: FileKind? { switch self { case .files: nil; case .music: .audio; case .videos: .video; case .pictures: .image } }
    var extensions: [String] { switch self { case .files: []; case .music: FileKind.audioExtensions; case .videos: FileKind.videoExtensions; case .pictures: FileKind.imageExtensions } }
    var allowedContentTypes: [UTType] {
        let base: UTType = switch self { case .files: .item; case .music: .audio; case .videos: .movie; case .pictures: .image }
        return [base] + extensions.compactMap { UTType(filenameExtension: $0) }
    }
    var requirement: String { switch self { case .files: "Choose files to upload."; case .music: "Choose audio files only."; case .videos: "Choose video files only."; case .pictures: "Choose image files only." } }
    func accepts(name: String, isDirectory: Bool) -> Bool {
        guard let fileKind else { return true }
        return !isDirectory && FileKind(ext: PathUtil.ext(name)) == fileKind
    }
    /// Rechecks selections, including providers that ignore the picker's type filter.
    func validate(_ urls: [URL]) async throws {
        let invalid = try await Task.detached {
            var invalid: [String] = []
            for url in urls {
                try Task.checkCancellation()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let values = try url.resourceValues(forKeys: [.isDirectoryKey])
                if !accepts(name: url.lastPathComponent, isDirectory: values.isDirectory == true) { invalid.append(url.lastPathComponent) }
            }
            return invalid
        }.value
        if !invalid.isEmpty { throw FileProviderError.other(requirement + "\n" + invalid.prefix(3).joined(separator: "\n")) }
    }
}
