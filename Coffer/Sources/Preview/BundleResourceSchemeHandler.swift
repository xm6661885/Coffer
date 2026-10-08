import Foundation
import WebKit

// WKWebView blocks local script URLs supplied through loadHTMLString. Serve only
// the bundled renderer assets through an app-owned scheme with no network access.
final class BundleResourceSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "coffer-resource"
    static let origin = URL(string: "coffer-resource://bundle/")!
    private let root: URL
    private let cache = NSCache<NSURL, NSData>()
    init(root: URL = Bundle.main.resourceURL!) { self.root = root; super.init() }
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        do {
            guard let url = urlSchemeTask.request.url, url.host == "bundle" else { throw URLError(.badURL) }
            let file = root.appending(path: String(url.path.dropFirst())).standardizedFileURL
            let allowed = ["js": "application/javascript", "css": "text/css", "woff2": "font/woff2", "woff": "font/woff", "ttf": "font/ttf"]
            guard PathUtil.isAncestor(root.standardizedFileURL.path, of: file.path), let mime = allowed[file.pathExtension.lowercased()] else { throw URLError(.noPermissionsToReadFile) }
            let data: Data
            if let saved = cache.object(forKey: file as NSURL) { data = saved as Data }
            else { data = try Data(contentsOf: file); cache.setObject(data as NSData, forKey: file as NSURL) }
            urlSchemeTask.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: ["js", "css"].contains(file.pathExtension) ? "utf-8" : nil))
            urlSchemeTask.didReceive(data); urlSchemeTask.didFinish()
        } catch { urlSchemeTask.didFailWithError(error) }
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) { }
}
