import Foundation

struct WebDAVServer: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var baseURL: URL
    var username: String
    var initialPath = "/"
    var allowSelfSigned = false
    var connectionsPerDownload = 4
    var lastError: String?
}
