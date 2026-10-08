import Foundation

struct FileItem: Identifiable, Hashable, Codable, Sendable {
    let location: LocationID
    let path: String
    let name: String
    let isDirectory: Bool
    let size: Int64?
    let modified: Date?
    let created: Date?
    let etag: String?
    let contentType: String?
    var id: String { location.key + ":" + path }
    var ext: String { isDirectory ? "" : PathUtil.ext(name) }
    var kind: FileKind { isDirectory ? .folder : FileKind(ext: ext) }
    var isHidden: Bool { name.hasPrefix(".") }
    var parentPath: String { PathUtil.parent(path) }
}
