import Foundation

enum FileProviderError: LocalizedError {
    case notFound(String), alreadyExists(String), invalidName, unauthorized, forbidden, insufficientStorage, conflict(String), http(Int), network(Error), cancelled, other(String)
    var errorDescription: String? {
        switch self {
        case .notFound(let name): return "\(name) no longer exists."
        case .alreadyExists(let name): return "An item named \"\(name)\" already exists."
        case .invalidName: return "That name isn't allowed."
        case .unauthorized: return "Wrong username or password."
        case .forbidden: return "You don't have permission to do that."
        case .insufficientStorage: return "Not enough storage."
        case .conflict(let message), .other(let message): return message
        case .http(let code): return "The server returned an error (\(code))."
        case .network(let error): return error.localizedDescription
        case .cancelled: return "Cancelled."
        }
    }
    static func mapped(_ error: Error, name: String) -> FileProviderError {
        if let error = error as? FileProviderError { return error }
        let e = error as NSError
        switch e.code {
        case NSFileNoSuchFileError, NSFileReadNoSuchFileError: return .notFound(name)
        case NSFileWriteFileExistsError: return .alreadyExists(name)
        case NSFileReadNoPermissionError, NSFileWriteNoPermissionError: return .forbidden
        case NSFileWriteOutOfSpaceError: return .insufficientStorage
        default: return .other(error.localizedDescription)
        }
    }
}
protocol FileProvider: AnyObject, Sendable {
    var location: LocationID { get }
    func list(_ dirPath: String) async throws -> [FileItem]
    func stat(_ path: String) async throws -> FileItem
    func createFolder(named name: String, in dirPath: String) async throws -> FileItem
    func createFile(named name: String, in dirPath: String, data: Data) async throws -> FileItem
    func rename(_ item: FileItem, to newName: String) async throws -> FileItem
    func delete(_ item: FileItem) async throws
    func copy(_ item: FileItem, toDir: String, newName: String, overwrite: Bool) async throws
    func move(_ item: FileItem, toDir: String, newName: String, overwrite: Bool) async throws
}

extension FileProvider {
    func recursiveList(_ path: String, limit: Int = 5000) async throws -> [FileItem] {
        var folders = [path]; var visited: Set<String> = []; var result: [FileItem] = []
        while let folder = folders.popLast() {
            try Task.checkCancellation(); guard visited.insert(folder).inserted else { continue }
            for item in try await list(folder) {
                guard result.count < limit else { return result }
                result.append(item); if item.isDirectory && !item.isHidden { folders.append(item.path) }
            }
        }
        return result
    }
}
