import Foundation

enum LocationID: Hashable, Codable, Sendable {
    case local
    case webdav(UUID)
    var key: String { switch self { case .local: return "local"; case .webdav(let id): return "dav-" + id.uuidString } }
    var isRemote: Bool { if case .webdav = self { return true }; return false }
}
struct BrowserRoute: Hashable, Codable, Sendable { let location: LocationID; let path: String }
struct PreviewRoute: Hashable { let item: FileItem; let siblings: [FileItem] }
extension Notification.Name { static let cofferDirectoryChanged = Notification.Name("cofferDirectoryChanged") }
