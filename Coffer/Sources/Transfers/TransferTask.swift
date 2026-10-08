import Foundation

struct TransferTask: Identifiable, Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case download, upload, cache }
    enum State: String, Codable, Sendable { case queued, running, paused, waitingForNetwork, failed, completed, cancelled }
    var id = UUID()
    var kind: Kind
    var source: FileItem
    var destLocation: LocationID
    var destPath: String
    var deleteSourceOnSuccess = false
    var totalBytes: Int64
    var completedBytes: Int64
    var state: State = .queued
    var attempts = 0
    var lastError: String?
    var createdAt = Date()
    var finishedAt: Date?
    var etag: String?
    var segments: [Segment] = []
    var destinationVerified = false
    var sourceURL: URL?
    var groupID: UUID?
    var retryAt: Date?
    struct Segment: Codable, Hashable, Sendable { var index: Int; var start: Int64; var end: Int64; var done: Int64 }
    var isActive: Bool { [.queued, .running, .paused, .waitingForNetwork].contains(state) }
}
struct TransferGroup: Identifiable, Codable, Hashable, Sendable {
    var id = UUID(); var name: String; var taskIDs: [UUID] = []; var sourceDirectories: [FileItem] = []; var move = false; var isExpanded = false; var finished = false
    var targetLocation: LocationID?
    var stagePath: String?
    var finalPath: String?
    var installed = false
    var lastError: String?
}
