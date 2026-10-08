import Foundation
import Security

final class WebDAVClient: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    let server: WebDAVServer
    private let password: String
    private lazy var session: URLSession = URLSession(configuration: configuration(), delegate: self, delegateQueue: nil)
    init(server: WebDAVServer, password: String) { self.server = server; self.password = password; super.init(); _ = session }
    func configuration() -> URLSessionConfiguration {
        let c = URLSessionConfiguration.default; c.timeoutIntervalForRequest = 30; c.timeoutIntervalForResource = 7 * 24 * 3600; c.httpMaximumConnectionsPerHost = 16; c.requestCachePolicy = .reloadIgnoringLocalCacheData; c.urlCache = nil; c.waitsForConnectivity = false; return c
    }
    var authHeader: String { "Basic " + Data((server.username + ":" + password).utf8).base64EncodedString() }
    func url(for path: String, isDirectory: Bool = false) -> URL {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#[]@!$&'()*+,;=%"))
        let components = PathUtil.components(path).map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0 }
        let base = server.baseURL.absoluteString.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        let suffix = components.joined(separator: "/")
        return URL(string: base + "/" + suffix + (isDirectory && !suffix.isEmpty ? "/" : "")) ?? server.baseURL
    }
    func authorizedRequest(_ url: URL, method: String) -> URLRequest { var request = URLRequest(url: url); request.httpMethod = method; request.setValue(authHeader, forHTTPHeaderField: "Authorization"); return request }
    static func validate(_ response: URLResponse, path: String, method: String? = nil) throws -> HTTPURLResponse {
        guard let response = response as? HTTPURLResponse else { throw FileProviderError.other("The server didn't return an HTTP response.") }
        switch response.statusCode {
        case 200, 201, 204, 206, 207: return response
        case 401: throw FileProviderError.unauthorized
        case 403: throw FileProviderError.forbidden
        case 404: throw FileProviderError.notFound(PathUtil.name(path))
        case 405: if method == "MKCOL" { throw FileProviderError.alreadyExists(PathUtil.name(path)) }; throw FileProviderError.http(405)
        case 412: throw FileProviderError.alreadyExists(PathUtil.name(path))
        case 409: throw FileProviderError.conflict("The destination folder doesn't exist.")
        case 423: throw FileProviderError.other("The file is locked.")
        case 507: throw FileProviderError.insufficientStorage
        default: throw FileProviderError.http(response.statusCode)
        }
    }
    private func send(_ request: URLRequest, path: String) async throws -> (Data, HTTPURLResponse) {
        do { let (data, response) = try await session.data(for: request); return (data, try Self.validate(response, path: path, method: request.httpMethod)) }
        catch let error as FileProviderError { throw error }
        catch { let error = error as NSError; if error.code == NSURLErrorCancelled { throw FileProviderError.cancelled }; if error.code == NSURLErrorUserAuthenticationRequired || error.code == NSURLErrorUserCancelledAuthentication { throw FileProviderError.unauthorized }; throw FileProviderError.network(error) }
    }
    func propfind(_ path: String, depth: Int) async throws -> [FileItem] {
        var request = authorizedRequest(url(for: path, isDirectory: depth > 0 || path == "/"), method: "PROPFIND")
        request.setValue(String(depth), forHTTPHeaderField: "Depth"); request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("<?xml version=\"1.0\" encoding=\"utf-8\"?><d:propfind xmlns:d=\"DAV:\"><d:prop><d:displayname/><d:resourcetype/><d:getcontentlength/><d:getlastmodified/><d:creationdate/><d:getetag/><d:getcontenttype/></d:prop></d:propfind>".utf8)
        let (data, _) = try await send(request, path: path)
        return try PropfindParser(server: server, requestedPath: path, includeSelf: depth == 0).parse(data)
    }
    func mkcol(_ path: String) async throws { _ = try await send(authorizedRequest(url(for: path, isDirectory: true), method: "MKCOL"), path: path) }
    func delete(_ path: String, isDirectory: Bool) async throws { _ = try await send(authorizedRequest(url(for: path, isDirectory: isDirectory), method: "DELETE"), path: path) }
    private func relocate(_ method: String, from: String, to: String, isDirectory: Bool, overwrite: Bool) async throws {
        if isDirectory && PathUtil.isAncestor(from, of: to) { throw FileProviderError.other("You can't move a folder into itself.") }
        var request = authorizedRequest(url(for: from, isDirectory: isDirectory), method: method)
        request.setValue(url(for: to, isDirectory: isDirectory).absoluteString, forHTTPHeaderField: "Destination"); request.setValue(overwrite ? "T" : "F", forHTTPHeaderField: "Overwrite")
        if method == "COPY" && isDirectory { request.setValue("infinity", forHTTPHeaderField: "Depth") }
        _ = try await send(request, path: to)
    }
    func move(from: String, to: String, isDirectory: Bool, overwrite: Bool) async throws { try await relocate("MOVE", from: from, to: to, isDirectory: isDirectory, overwrite: overwrite) }
    func copy(from: String, to: String, isDirectory: Bool, overwrite: Bool) async throws { try await relocate("COPY", from: from, to: to, isDirectory: isDirectory, overwrite: overwrite) }
    func put(data: Data, to path: String) async throws { var request = authorizedRequest(url(for: path), method: "PUT"); request.httpBody = data; _ = try await send(request, path: path) }
    func head(_ path: String) async throws -> (size: Int64?, etag: String?, acceptRanges: Bool, lastModified: Date?) {
        let (_, response) = try await session.data(for: authorizedRequest(url(for: path), method: "HEAD"))
        var http: HTTPURLResponse
        if (response as? HTTPURLResponse)?.statusCode == 405 {
            var request = authorizedRequest(url(for: path), method: "GET"); request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
            http = try await ResponseProbe(client: self).run(request)
            _ = try Self.validate(http, path: path)
        } else { http = try Self.validate(response, path: path) }
        let contentRange = http.value(forHTTPHeaderField: "Content-Range")?.split(separator: "/").last.flatMap { Int64($0) }
        return (contentRange ?? http.value(forHTTPHeaderField: "Content-Length").flatMap(Int64.init), PropfindParser.etag(http.value(forHTTPHeaderField: "ETag")), http.statusCode == 206 || http.value(forHTTPHeaderField: "Accept-Ranges")?.lowercased() == "bytes", PropfindParser.httpDate(http.value(forHTTPHeaderField: "Last-Modified")))
    }
    func supportsByteRanges(_ path: String) async throws -> Bool {
        var request = authorizedRequest(url(for: path), method: "GET")
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let response = try await ResponseProbe(client: self).run(request)
        _ = try Self.validate(response, path: path)
        guard response.statusCode == 206,
              let range = response.value(forHTTPHeaderField: "Content-Range"), range.hasPrefix("bytes 0-0/"),
              let total = Int64(range.dropFirst("bytes 0-0/".count)), total > 0 else { return false }
        return true
    }
    func download(_ path: String) async throws -> URL { let (url, response) = try await session.download(for: authorizedRequest(url(for: path), method: "GET")); _ = try Self.validate(response, path: path); return url }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) { authenticate(challenge, completion: completionHandler) }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) { authenticate(challenge, completion: completionHandler) }
    func authenticate(_ challenge: URLAuthenticationChallenge, completion: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.previousFailureCount == 0 else { completion(.cancelAuthenticationChallenge, nil); return }
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodHTTPDigest { completion(.useCredential, URLCredential(user: server.username, password: password, persistence: .forSession)) }
        else if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust && server.allowSelfSigned, let trust = challenge.protectionSpace.serverTrust { completion(.useCredential, URLCredential(trust: trust)) }
        else { completion(.performDefaultHandling, nil) }
    }
    func invalidate() { session.invalidateAndCancel() }
    deinit { session.invalidateAndCancel() }
}
private final class ResponseProbe: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let client: WebDAVClient
    private let lock = NSLock()
    private var continuation: CheckedContinuation<HTTPURLResponse, Error>?
    private var session: URLSession?
    private var cancelled = false
    init(client: WebDAVClient) { self.client = client }
    func run(_ request: URLRequest) async throws -> HTTPURLResponse {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if cancelled { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
                self.continuation = continuation
                let session = URLSession(configuration: client.configuration(), delegate: self, delegateQueue: nil)
                self.session = session
                session.dataTask(with: request).resume()
                lock.unlock()
            }
        } onCancel: { self.cancel() }
    }
    private func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
        finish(.failure(CancellationError()))
    }
    private func finish(_ result: Result<HTTPURLResponse, Error>) {
        lock.lock(); let continuation = continuation, session = session
        self.continuation = nil; self.session = nil; lock.unlock()
        session?.invalidateAndCancel(); continuation?.resume(with: result)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        completionHandler(.cancel)
        if let http = response as? HTTPURLResponse { finish(.success(http)) }
        else { finish(.failure(FileProviderError.other("Invalid response."))) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) { finish(.failure(error ?? FileProviderError.other("No response."))) }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) { client.authenticate(challenge, completion: completionHandler) }
}
