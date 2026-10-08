import Foundation

final class Uploader: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let client: WebDAVClient
    let source: URL
    let destination: String
    let onProgress: @Sendable (Int64) -> Void
    var onRetry: (@Sendable (Int, Double) -> Void)?
    private let queue: OperationQueue
    private var session: URLSession!
    private var continuations: [Int: CheckedContinuation<Void, Error>] = [:]
    private let lock = NSLock()
    private var cancelled = false
    private var lastReport = Date.distantPast
    private var temporaryPath: String { PathUtil.join(PathUtil.parent(destination), "." + PathUtil.name(destination) + ".coffer-upload") }
    init(client: WebDAVClient, source: URL, destination: String, onProgress: @escaping @Sendable (Int64) -> Void) {
        self.client = client; self.source = source; self.destination = destination; self.onProgress = onProgress
        queue = OperationQueue(); queue.maxConcurrentOperationCount = 1; queue.qualityOfService = .utility
        super.init(); session = URLSession(configuration: client.configuration(), delegate: self, delegateQueue: queue)
    }
    func cancel() { lock.lock(); cancelled = true; lock.unlock(); session.invalidateAndCancel() }
    private func checkCancellation() throws { try Task.checkCancellation(); lock.lock(); let flag = cancelled; lock.unlock(); if flag { throw CancellationError() } }
    func run() async throws {
        defer { session.invalidateAndCancel() }
        do { try await withTaskCancellationHandler(operation: { try await upload() }, onCancel: { self.cancel() }) }
        catch {
            if error is CancellationError || (error as NSError).code == NSURLErrorCancelled { let client = client, temporary = temporaryPath; await Task.detached { try? await client.delete(temporary, isDirectory: false) }.value }
            throw error
        }
    }
    private func upload() async throws {
        let size = try await Task.detached { Int64(try self.source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }.value
        var path = "/"
        for component in PathUtil.components(PathUtil.parent(destination)) {
            try checkCancellation(); path = PathUtil.join(path, component)
            do { try await client.mkcol(path) } catch FileProviderError.alreadyExists { }
        }
        for attempt in 0..<5 {
            try checkCancellation()
            do {
                onProgress(0)
                try await sendFile()
                try checkCancellation()
                do { try await client.move(from: temporaryPath, to: destination, isDirectory: false, overwrite: true) }
                catch FileProviderError.alreadyExists { try await client.delete(destination, isDirectory: false); try await client.move(from: temporaryPath, to: destination, isDirectory: false, overwrite: false) }
                guard let item = try await client.propfind(destination, depth: 0).first, item.size == size else { throw FileProviderError.other("The uploaded file size doesn't match.") }
                onProgress(size); return
            } catch {
                try checkCancellation()
                guard attempt < 4 && SegmentedDownloader.retryable(error) else { throw error }
                let delay = min(30, pow(2, Double(attempt))) + Double.random(in: 0...1)
                onRetry?(attempt + 1, delay); try await Task.sleep(for: .seconds(delay))
            }
        }
    }
    private func sendFile() async throws {
        let request = client.authorizedRequest(client.url(for: temporaryPath), method: "PUT")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.addOperation {
                do { try self.checkCancellation() } catch { continuation.resume(throwing: error); return }
                let task = self.session.uploadTask(with: request, fromFile: self.source)
                self.continuations[task.taskIdentifier] = continuation; task.resume()
            }
        }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        if Date().timeIntervalSince(lastReport) >= 0.25 || totalBytesSent == totalBytesExpectedToSend { lastReport = Date(); onProgress(totalBytesSent) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let continuation = continuations.removeValue(forKey: task.taskIdentifier) else { return }
        do { if let error { throw FileProviderError.network(error) }; guard let response = task.response else { throw FileProviderError.other("No upload response.") }; _ = try WebDAVClient.validate(response, path: destination, method: "PUT"); continuation.resume() }
        catch { continuation.resume(throwing: error) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) { client.authenticate(challenge, completion: completionHandler) }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) { client.authenticate(challenge, completion: completionHandler) }
    deinit { session.invalidateAndCancel() }
}
