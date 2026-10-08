import Foundation
struct MediaRef: Codable, Hashable, Identifiable, Sendable {
    var location: LocationID; var path: String; var name: String
    var id: String { location.key + ":" + path }
    init(_ item: FileItem) { location = item.location; path = item.path; name = item.name }
    var fileItem: FileItem { FileItem(location: location, path: path, name: name, isDirectory: false, size: nil, modified: nil, created: nil, etag: nil, contentType: nil) }
}
struct TrackMetadata: Codable, Hashable, Sendable { var title: String; var artist: String?; var album: String?; var duration: Double?; var artworkKey: String?; var trackNumber: Int? }
