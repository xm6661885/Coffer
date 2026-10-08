import Foundation
import Network

/// A bounded, authenticated range cache shared by AV and VLC through a loopback URL.
final class RemoteVideoStream: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "Coffer.video-stream")
    private let cache: VideoRangeCache
    private let issue = VideoStreamIssue()
    var failureReason: String? { issue.message }
    private let route = "/" + UUID().uuidString
    private let size: Int64
    private let ext: String
    private let lock = NSLock()
    private var connections: [UUID: VideoHTTPConnection] = [:]
    private var closed = false
    init(client: WebDAVClient, item: FileItem, preloadOnly: Bool = false) throws {
        size = item.size ?? 0; ext = item.ext
        guard size > 0 else { throw FileProviderError.other("The server didn't report this video's size.") }
        cache = VideoRangeCache(client: client, item: item, preloadOnly: preloadOnly, issue: issue)
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        parameters.requiredInterfaceType = .loopback
        listener = try NWListener(using: parameters, on: .any)
    }
    func start() async throws -> URL {
        let port: NWEndpoint.Port = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let result = VideoListenerResult(continuation)
                lock.lock()
                guard !closed else { lock.unlock(); result.finish(.failure(CancellationError())); return }
                listener.stateUpdateHandler = { [weak self] state in
                    switch state {
                    case .ready: if let port = self?.listener.port { result.finish(.success(port)) }
                    case .failed(let error): result.finish(.failure(error))
                    case .cancelled: result.finish(.failure(CancellationError()))
                    default: break
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
                listener.start(queue: queue)
                lock.unlock()
            }
        } onCancel: { self.close() }
        try Task.checkCancellation()
        Task { await cache.warm() }
        return URL(string: "http://127.0.0.1:\(port.rawValue)\(route).\(ext)")!
    }
    func preloadOpening() async throws { try await cache.preloadOpening() }
    func activate() { let cache = cache; Task { await cache.activate() } }
    private func accept(_ connection: NWConnection) {
        let id = UUID()
        let handler = VideoHTTPConnection(connection: connection, cache: cache, size: size, path: route + "." + ext) { [weak self] in
            guard let self else { return }; self.lock.lock(); self.connections.removeValue(forKey: id); self.lock.unlock()
        }
        lock.lock(); if closed || connections.count >= 8 { lock.unlock(); connection.cancel(); return }
        connections[id] = handler; lock.unlock(); handler.start(queue: queue)
    }
    func close() {
        lock.lock(); guard !closed else { lock.unlock(); return }; closed = true
        let connections = Array(connections.values); self.connections.removeAll(); lock.unlock()
        listener.cancel(); connections.forEach { $0.close() }
        let cache = cache; Task { await cache.close() }
    }
    deinit { close() }
}

private final class VideoListenerResult: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<NWEndpoint.Port, Error>?
    init(_ continuation: CheckedContinuation<NWEndpoint.Port, Error>) { self.continuation = continuation }
    func finish(_ result: Result<NWEndpoint.Port, Error>) {
        lock.lock(); let continuation = continuation; self.continuation = nil; lock.unlock(); continuation?.resume(with: result)
    }
}

private final class VideoStreamIssue: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    var message: String? { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ error: Error) {
        guard !(error is CancellationError), (error as NSError).code != NSURLErrorCancelled else { return }
        lock.lock(); value = error.localizedDescription; lock.unlock()
    }
}

private actor VideoRangeCache {
    private static let blockSize: Int64 = 256 * 1024
    private static let maximumBlocks = 128 // 32 MiB, independent of the file's total size.
    private let reader: VideoRangeReader
    private let size: Int64
    private var blocks: [Int64: Data] = [:]
    private var access: [Int64: UInt64] = [:]
    private var clock: UInt64 = 0
    private var pending: [Int64: Task<Data, Error>] = [:]
    private var speculative: Set<Int64> = []
    private var active = 0
    private var maximumActive: Int
    private var closed = false
    private var lastRead: Int64?
    init(client: WebDAVClient, item: FileItem, preloadOnly: Bool, issue: VideoStreamIssue) { size = item.size ?? 0; reader = VideoRangeReader(client: client, item: item, issue: issue); maximumActive = preloadOnly ? 1 : 3 }
    func warm() {
        prefetch(0); if size > Self.blockSize { prefetch((size - 1) / Self.blockSize) }
    }
    func activate() { maximumActive = 3 }
    func preloadOpening() async throws {
        for index: Int64 in 0..<4 where index * Self.blockSize < size {
            guard !closed, !Task.isCancelled else { return }
            _ = try await block(index)
        }
    }
    func read(at offset: Int64) async throws -> Data {
        try Task.checkCancellation(); guard !closed else { throw CancellationError() }
        let index = offset / Self.blockSize
        if let lastRead, abs(index - lastRead) > 4 {
            // A seek takes priority over obsolete read-ahead requests.
            for stale in Array(speculative) where stale < index || stale > index + 3 {
                pending[stale]?.cancel(); pending.removeValue(forKey: stale); speculative.remove(stale)
            }
        }
        lastRead = index; speculative.remove(index)
        // Only a small window is prefetched, using at most three upstream requests.
        for next in 1...3 where (index + Int64(next)) * Self.blockSize < size { prefetch(index + Int64(next)) }
        let data = try await block(index)
        let relative = Int(offset % Self.blockSize)
        return relative == 0 ? data : data.subdata(in: relative..<data.count)
    }
    private func prefetch(_ index: Int64) {
        guard !closed, blocks[index] == nil, pending[index] == nil else { return }
        speculative.insert(index)
        let task = makeTask(index); pending[index] = task
        Task { [weak self] in
            do { let data = try await task.value; await self?.store(data, index: index, task: task) }
            catch { await self?.discard(index, task: task) }
        }
    }
    private func makeTask(_ index: Int64) -> Task<Data, Error> {
        Task {
            while active >= maximumActive { try await Task.sleep(for: .milliseconds(10)) }
            try Task.checkCancellation(); guard !closed else { throw CancellationError() }
            active += 1
            do {
                let start = index * Self.blockSize, end = min(size - 1, (index + 1) * Self.blockSize - 1)
                let data = try await reader.read(start: start, end: end)
                active -= 1; return data
            } catch { active -= 1; throw error }
        }
    }
    private func block(_ index: Int64) async throws -> Data {
        clock += 1; access[index] = clock
        if let data = blocks[index] { return data }
        let task: Task<Data, Error>
        if let existing = pending[index] { task = existing }
        else { task = makeTask(index); pending[index] = task }
        do { let data = try await task.value; store(data, index: index, task: task); try Task.checkCancellation(); return data }
        catch { discard(index, task: task); throw error }
    }
    private func store(_ data: Data, index: Int64, task: Task<Data, Error>) {
        guard !closed, pending[index] == task else { return }
        pending.removeValue(forKey: index); speculative.remove(index)
        clock += 1; blocks[index] = data; access[index] = clock
        while blocks.count > Self.maximumBlocks, let oldest = blocks.keys.min(by: { (access[$0] ?? 0) < (access[$1] ?? 0) }) {
            blocks.removeValue(forKey: oldest); access.removeValue(forKey: oldest)
        }
    }
    private func discard(_ index: Int64, task: Task<Data, Error>) {
        if pending[index] == task { pending.removeValue(forKey: index); speculative.remove(index) }
    }
    func close() { closed = true; pending.values.forEach { $0.cancel() }; pending.removeAll(); blocks.removeAll(); access.removeAll(); reader.close() }
}

private final class VideoRangeReader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private final class Request {
        let start: Int64; let end: Int64
        let continuation: CheckedContinuation<Data, Error>
        var data = Data()
        init(start: Int64, end: Int64, continuation: CheckedContinuation<Data, Error>) {
            self.start = start; self.end = end; self.continuation = continuation
        }
    }
    private let client: WebDAVClient
    private let item: FileItem
    private let issue: VideoStreamIssue
    private let lock = NSLock()
    private var requests: [Int: Request] = [:]
    private var closed = false
    private lazy var session: URLSession = {
        let configuration = client.configuration(); configuration.httpMaximumConnectionsPerHost = 3
        configuration.timeoutIntervalForResource = 90
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        return URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }()
    init(client: WebDAVClient, item: FileItem, issue: VideoStreamIssue) { self.client = client; self.item = item; self.issue = issue; super.init(); _ = session }
    func read(start: Int64, end: Int64) async throws -> Data {
        var request = client.authorizedRequest(client.url(for: item.path), method: "GET")
        request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let task = session.dataTask(with: request)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if closed || Task.isCancelled { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
                requests[task.taskIdentifier] = Request(start: start, end: end, continuation: continuation)
                task.resume(); lock.unlock()
            }
        } onCancel: { self.finish(task, result: .failure(CancellationError())); task.cancel() }
    }
    private func finish(_ task: URLSessionTask, result: Result<Data, Error>) {
        lock.lock(); let request = requests.removeValue(forKey: task.taskIdentifier); lock.unlock()
        if case .failure(let error) = result, request != nil { issue.set(error) }
        request?.continuation.resume(with: result)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        lock.lock(); let request = requests[dataTask.taskIdentifier]; lock.unlock()
        do {
            guard let request else { throw CancellationError() }
            let http = try WebDAVClient.validate(response, path: item.path)
            guard http.statusCode == 206, http.value(forHTTPHeaderField: "Content-Range") == "bytes \(request.start)-\(request.end)/\(item.size ?? 0)",
                  http.value(forHTTPHeaderField: "Content-Encoding").map({ $0 == "identity" }) ?? true else {
                throw FileProviderError.other("This video changed or the server doesn't support byte-range streaming. Download it for offline playback.")
            }
            if let expected = item.etag, let actual = PropfindParser.etag(http.value(forHTTPHeaderField: "ETag")), actual != expected {
                throw FileProviderError.other("The video changed on the server. Close it and open it again.")
            }
            completionHandler(.allow)
        } catch { finish(dataTask, result: .failure(error)); completionHandler(.cancel) }
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard let request = requests[dataTask.taskIdentifier] else { lock.unlock(); return }
        let maximum = Int(request.end - request.start + 1)
        guard request.data.count + data.count <= maximum else { lock.unlock(); finish(dataTask, result: .failure(FileProviderError.other("Invalid video range response."))); dataTask.cancel(); return }
        request.data.append(data); lock.unlock()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock(); let request = requests[task.taskIdentifier]; lock.unlock()
        guard let request else { return }
        if let error { finish(task, result: .failure(error)) }
        else if request.data.count != Int(request.end - request.start + 1) { finish(task, result: .failure(FileProviderError.other("The video download was interrupted."))) }
        else { finish(task, result: .success(request.data)) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) { client.authenticate(challenge, completion: completionHandler) }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) { client.authenticate(challenge, completion: completionHandler) }
    func close() {
        lock.lock(); closed = true; let requests = Array(requests.values); self.requests.removeAll(); lock.unlock()
        session.invalidateAndCancel(); requests.forEach { $0.continuation.resume(throwing: CancellationError()) }
    }
}

private final class VideoHTTPConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let cache: VideoRangeCache
    private let size: Int64
    private let path: String
    private let finished: @Sendable () -> Void
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var closed = false
    init(connection: NWConnection, cache: VideoRangeCache, size: Int64, path: String, finished: @escaping @Sendable () -> Void) { self.connection = connection; self.cache = cache; self.size = size; self.path = path; self.finished = finished }
    func start(queue: DispatchQueue) {
        connection.stateUpdateHandler = { [weak self] state in if case .failed = state { self?.close() } }
        connection.start(queue: queue)
        let task = Task { [weak self] in guard let self else { return }; await self.serve() }
        lock.lock(); if closed { task.cancel() } else { self.task = task }; lock.unlock()
    }
    private func receive() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, complete, error in
                if let error { continuation.resume(throwing: error) }
                else if let data, !data.isEmpty { continuation.resume(returning: data) }
                else { continuation.resume(throwing: complete ? CancellationError() : FileProviderError.other("Empty video request.")) }
            }
        }
    }
    private func send(_ data: Data) async throws {
        try Task.checkCancellation()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in if let error { continuation.resume(throwing: error) } else { continuation.resume() } })
        }
    }
    private func serve() async {
        var sentHeaders = false
        do {
            var request = Data()
            while request.range(of: Data("\r\n\r\n".utf8)) == nil { request.append(try await receive()); guard request.count <= 16384 else { throw FileProviderError.other("Invalid video request.") } }
            let lines = String(decoding: request, as: UTF8.self).components(separatedBy: "\r\n")
            let first = lines[0].split(separator: " ")
            guard first.count == 3, first[1] == Substring(path), first[0] == "GET" || first[0] == "HEAD" else { throw FileProviderError.other("Invalid video request.") }
            var range: String?
            for line in lines.dropFirst() { if line.lowercased().hasPrefix("range:") { range = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces) } }
            var start: Int64 = 0, end = size - 1
            if let range {
                guard range.hasPrefix("bytes="), !range.contains(",") else { throw FileProviderError.other("Invalid video range.") }
                let parts = range.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
                guard parts.count == 2 else { throw FileProviderError.other("Invalid video range.") }
                if parts[0].isEmpty { guard let suffix = Int64(parts[1]), suffix > 0 else { throw FileProviderError.other("Invalid video range.") }; start = max(0, size - suffix) }
                else { guard let offset = Int64(parts[0]), offset >= 0 else { throw FileProviderError.other("Invalid video range.") }; start = offset; if !parts[1].isEmpty { guard let limit = Int64(parts[1]) else { throw FileProviderError.other("Invalid video range.") }; end = min(end, limit) } }
            }
            guard start < size, end >= start else {
                try await send(Data("HTTP/1.1 416 Range Not Satisfiable\r\nContent-Range: bytes */\(size)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)); close(); return
            }
            let firstBlock = first[0] == "HEAD" ? Data() : try await cache.read(at: start)
            let status = range == nil ? "200 OK" : "206 Partial Content"
            var headers = "HTTP/1.1 \(status)\r\nContent-Type: application/octet-stream\r\nAccept-Ranges: bytes\r\nContent-Length: \(end - start + 1)\r\nConnection: close\r\n"
            if range != nil { headers += "Content-Range: bytes \(start)-\(end)/\(size)\r\n" }
            try await send(Data((headers + "\r\n").utf8)); sentHeaders = true
            if first[0] == "GET" {
                var offset = start, data = firstBlock
                while offset <= end {
                    try Task.checkCancellation()
                    let count = min(data.count, Int(min(Int64(data.count), end - offset + 1)))
                    try await send(count == data.count ? data : Data(data.prefix(count))); offset += Int64(count)
                    if offset <= end { data = try await cache.read(at: offset) }
                }
            }
        } catch { if !sentHeaders, !Task.isCancelled { try? await send(Data("HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)) } }
        close()
    }
    func close() {
        lock.lock(); guard !closed else { lock.unlock(); return }; closed = true; let task = task; self.task = nil; lock.unlock()
        task?.cancel(); connection.cancel(); finished()
    }
}
