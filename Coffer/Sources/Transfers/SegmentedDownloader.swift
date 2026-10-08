import Foundation

private enum DownloadFailure: Error { case rangeIgnored }
final class SegmentedDownloader: @unchecked Sendable {
    let task: TransferTask
    let client: WebDAVClient
    let partDir: URL
    let connections: Int
    let onProgress: @Sendable ([TransferTask.Segment]) -> Void
    var onMetadata: (@Sendable (Int64?, String?) -> Void)?
    var onRetry: (@Sendable (Int, Double) -> Void)?
    private let lock = NSLock()
    private var segments: [TransferTask.Segment] = []
    private var delegate: SegmentDelegate?
    private var cancelled = false
    private var lastReport = Date.distantPast
    init(task: TransferTask, client: WebDAVClient, partDir: URL, connections: Int, onProgress: @escaping @Sendable ([TransferTask.Segment]) -> Void) { self.task = task; self.client = client; self.partDir = partDir; self.connections = max(1, min(8, connections)); self.onProgress = onProgress }
    func cancel() { lock.lock(); cancelled = true; let delegate = delegate; lock.unlock(); delegate?.cancel() }
    private func checkCancellation() throws { try Task.checkCancellation(); lock.lock(); let cancelled = cancelled; lock.unlock(); if cancelled { throw CancellationError() } }
    private func snapshot() -> [TransferTask.Segment] { lock.lock(); defer { lock.unlock() }; return segments }
    private func install(_ value: [TransferTask.Segment]) { lock.lock(); segments = value; lock.unlock(); onProgress(value) }
    private func updated(_ segment: TransferTask.Segment, force: Bool) {
        lock.lock()
        if let index = segments.firstIndex(where: { $0.index == segment.index }) { segments[index] = segment }
        let report = force || Date().timeIntervalSince(lastReport) >= 0.25
        let value = segments; if report { lastReport = Date() }; lock.unlock()
        if report { onProgress(value) }
    }
    func run() async throws -> URL {
        try await withTaskCancellationHandler(operation: { try await execute() }, onCancel: { self.cancel() })
    }
    private func execute() async throws -> URL {
        try checkCancellation()
        let metadata = try await client.head(task.source.path)
        let size = metadata.size ?? task.source.size
        onMetadata?(size, metadata.etag)
        var ranges = metadata.acceptRanges && size != nil && (size ?? 0) > 0
        let resumable = ranges && !task.segments.isEmpty && task.etag == metadata.etag && (metadata.etag != nil || task.totalBytes == size)
        install(try await prepare(size: size, ranges: ranges, resume: resumable))
        if size == 0 { let url = partDir.appending(path: "merged"); try await Task.detached { try Data().write(to: url) }.value; return url }
        do { try await downloadSegments(ranges: ranges, etag: metadata.etag) }
        catch DownloadFailure.rangeIgnored {
            try checkCancellation(); ranges = false
            install(try await prepare(size: size, ranges: false, resume: false))
            try await downloadSegments(ranges: false, etag: metadata.etag)
        }
        try checkCancellation()
        let segments = snapshot(), partDir = partDir
        return try await Task.detached {
            let output = partDir.appending(path: "merged")
            guard FileManager.default.createFile(atPath: output.path, contents: nil) else { throw FileProviderError.insufficientStorage }
            let writer = try FileHandle(forWritingTo: output); defer { try? writer.close() }
            var count: Int64 = 0
            for segment in segments.sorted(by: { $0.index < $1.index }) {
                let reader = try FileHandle(forReadingFrom: partDir.appending(path: "seg-\(segment.index)")); defer { try? reader.close() }
                while let data = try reader.read(upToCount: 4 * 1024 * 1024), !data.isEmpty { try Task.checkCancellation(); try writer.write(contentsOf: data); count += Int64(data.count) }
            }
            try writer.synchronize()
            if let size, count != size { throw FileProviderError.other("The downloaded file size doesn't match.") }
            return output
        }.value
    }
    private func prepare(size: Int64?, ranges: Bool, resume: Bool) async throws -> [TransferTask.Segment] {
        let partDir = partDir, old = task.segments, connections = connections
        return try await Task.detached {
            let fm = FileManager.default
            if !resume { try? fm.removeItem(at: partDir) }
            try fm.createDirectory(at: partDir, withIntermediateDirectories: true)
            if resume {
                return try old.map { segment in
                    var result = segment
                    let file = partDir.appending(path: "seg-\(segment.index)")
                    let done = Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                    guard done <= segment.end - segment.start + 1 else { throw FileProviderError.other("A download segment is invalid.") }
                    result.done = done; return result
                }
            }
            let size = size ?? 0
            let count = !ranges || size < 8 * 1024 * 1024 ? 1 : min(connections, max(1, Int(size / (4 * 1024 * 1024))))
            return (0..<count).map { index in
                let start = size * Int64(index) / Int64(count), end = size == 0 ? -1 : size * Int64(index + 1) / Int64(count) - 1
                return TransferTask.Segment(index: index, start: start, end: end, done: 0)
            }
        }.value
    }
    private func downloadSegments(ranges: Bool, etag: String?) async throws {
        let delegate = SegmentDelegate(client: client)
        if attach(delegate) { delegate.cancel(); throw CancellationError() }
        defer { delegate.cancel(); setDelegate(nil) }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for segment in snapshot() {
                if segment.end >= 0 && segment.done == segment.end - segment.start + 1 { continue }
                group.addTask { try await self.download(segment.index, ranges: ranges, etag: etag, delegate: delegate) }
            }
            for try await _ in group { }
        }
    }
    private func attach(_ value: SegmentDelegate) -> Bool { lock.lock(); defer { lock.unlock() }; delegate = value; return cancelled }
    private func setDelegate(_ delegate: SegmentDelegate?) { lock.lock(); self.delegate = delegate; lock.unlock() }
    private func download(_ index: Int, ranges: Bool, etag: String?, delegate: SegmentDelegate) async throws {
        for attempt in 0..<8 {
            try checkCancellation()
            guard let segment = snapshot().first(where: { $0.index == index }) else { throw FileProviderError.other("Missing download segment.") }
            var request = client.authorizedRequest(client.url(for: task.source.path), method: "GET")
            if ranges { request.setValue("bytes=\(segment.start + segment.done)-\(segment.end)", forHTTPHeaderField: "Range"); if let etag { request.setValue("\"\(etag)\"", forHTTPHeaderField: "If-Range") } }
            else if segment.done > 0 { install(try await prepare(size: task.totalBytes > 0 ? task.totalBytes : nil, ranges: false, resume: false)) }
            let current = snapshot().first { $0.index == index } ?? segment
            do { try await delegate.fetch(request, segment: current, file: partDir.appending(path: "seg-\(index)"), ranges: ranges) { value, force in self.updated(value, force: force) }; return }
            catch DownloadFailure.rangeIgnored { throw DownloadFailure.rangeIgnored }
            catch {
                try checkCancellation()
                guard attempt < 7 && Self.retryable(error) else { throw error }
                let delay = min(30, pow(2, Double(attempt))) + Double.random(in: 0...1)
                onRetry?(attempt + 1, delay); try await Task.sleep(for: .seconds(delay))
            }
        }
    }
    static func retryable(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        if let error = error as? FileProviderError { switch error { case .http(let code): return code >= 500; case .network: return true; default: return false } }
        return (error as NSError).domain == NSURLErrorDomain
    }
}
private final class RequestCancellation: @unchecked Sendable {
    private let lock = NSLock(); private var task: URLSessionTask?; private var cancelled = false
    func install(_ task: URLSessionTask) { lock.lock(); self.task = task; let cancelled = cancelled; lock.unlock(); if cancelled { task.cancel() } }
    func cancel() { lock.lock(); cancelled = true; let task = task; lock.unlock(); task?.cancel() }
}
private final class SegmentDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private final class Context {
        var segment: TransferTask.Segment
        let handle: FileHandle
        let ranges: Bool
        let continuation: CheckedContinuation<Void, Error>
        let progress: @Sendable (TransferTask.Segment, Bool) -> Void
        var buffer = Data(); var failure: Error?
        init(segment: TransferTask.Segment, handle: FileHandle, ranges: Bool, continuation: CheckedContinuation<Void, Error>, progress: @escaping @Sendable (TransferTask.Segment, Bool) -> Void) { self.segment = segment; self.handle = handle; self.ranges = ranges; self.continuation = continuation; self.progress = progress }
        func flush(force: Bool) throws {
            if !buffer.isEmpty { try handle.write(contentsOf: buffer); segment.done += Int64(buffer.count); buffer.removeAll(keepingCapacity: true) }
            progress(segment, force)
        }
    }
    let client: WebDAVClient
    let queue: OperationQueue
    private var contexts: [Int: Context] = [:]
    private var session: URLSession!
    init(client: WebDAVClient) {
        self.client = client; queue = OperationQueue(); queue.maxConcurrentOperationCount = 1; queue.qualityOfService = .utility
        super.init(); session = URLSession(configuration: client.configuration(), delegate: self, delegateQueue: queue)
    }
    func cancel() { session.invalidateAndCancel() }
    func fetch(_ request: URLRequest, segment: TransferTask.Segment, file: URL, ranges: Bool, progress: @escaping @Sendable (TransferTask.Segment, Bool) -> Void) async throws {
        let cancellation = RequestCancellation()
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                queue.addOperation {
                    do {
                        let fm = FileManager.default
                        if !fm.fileExists(atPath: file.path) { guard fm.createFile(atPath: file.path, contents: nil) else { throw FileProviderError.insufficientStorage } }
                        let handle = try FileHandle(forWritingTo: file); try handle.seekToEnd()
                        let task = self.session.dataTask(with: request)
                        self.contexts[task.taskIdentifier] = Context(segment: segment, handle: handle, ranges: ranges, continuation: continuation, progress: progress)
                        cancellation.install(task); task.resume()
                    } catch { continuation.resume(throwing: error) }
                }
            }
        }, onCancel: { cancellation.cancel() })
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let context = contexts[dataTask.taskIdentifier] else { completionHandler(.cancel); return }
        do {
            let response = try WebDAVClient.validate(response, path: dataTask.originalRequest?.url?.lastPathComponent ?? "File")
            if context.ranges {
                if response.statusCode == 200 { throw DownloadFailure.rangeIgnored }
                guard response.statusCode == 206, let value = response.value(forHTTPHeaderField: "Content-Range"), let range = Self.byteRange(value), range.0 == context.segment.start + context.segment.done, range.1 == context.segment.end else { throw FileProviderError.other("The server returned an invalid byte range.") }
            } else {
                guard response.statusCode == 200 else { throw FileProviderError.other("The server returned an incomplete download.") }
                if response.expectedContentLength >= 0 { context.segment.end = response.expectedContentLength - 1 }
            }
            completionHandler(.allow)
        } catch { context.failure = error; completionHandler(.cancel) }
    }
    private static func byteRange(_ value: String) -> (Int64, Int64)? {
        let pieces = value.replacingOccurrences(of: "bytes ", with: "").split(separator: "/").first?.split(separator: "-")
        guard let pieces, pieces.count == 2, let start = Int64(pieces[0]), let end = Int64(pieces[1]) else { return nil }; return (start, end)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let context = contexts[dataTask.taskIdentifier], context.failure == nil else { return }
        do {
            let prospective = context.segment.done + Int64(context.buffer.count) + Int64(data.count)
            if context.segment.end >= 0 && prospective > context.segment.end - context.segment.start + 1 { throw FileProviderError.other("A download segment is larger than expected.") }
            context.buffer.append(data)
            if context.buffer.count >= 256 * 1024 { try context.flush(force: false) }
        } catch { context.failure = error; dataTask.cancel() }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let context = contexts.removeValue(forKey: task.taskIdentifier) else { return }
        do {
            try context.flush(force: true); try context.handle.synchronize(); try context.handle.close()
            if let failure = context.failure ?? error { throw failure }
            if context.segment.end >= 0 && context.segment.done != context.segment.end - context.segment.start + 1 { throw FileProviderError.network(URLError(.networkConnectionLost)) }
            if context.segment.end < 0 { context.segment.end = context.segment.done - 1; context.progress(context.segment, true) }
            context.continuation.resume()
        } catch { try? context.handle.close(); context.continuation.resume(throwing: error) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) { client.authenticate(challenge, completion: completionHandler) }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) { client.authenticate(challenge, completion: completionHandler) }
}
