import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

final class PropfindParser: NSObject, XMLParserDelegate {
    private let server: WebDAVServer
    private let requestedPath: String
    private let includeSelf: Bool
    private var href = ""
    private var text = ""
    private var props: [String: String] = [:]
    private var responseProps: [String: String] = [:]
    private var status = ""
    private var collection = false
    private var inPropstat = false
    private(set) var items: [FileItem] = []
    init(server: WebDAVServer, requestedPath: String, includeSelf: Bool = false) { self.server = server; self.requestedPath = requestedPath; self.includeSelf = includeSelf }
    func parse(_ data: Data) throws -> [FileItem] {
        let parser = XMLParser(data: data); parser.shouldProcessNamespaces = true; parser.delegate = self
        guard parser.parse() else { throw FileProviderError.other("Couldn't read the server response. \(parser.parserError?.localizedDescription ?? "Invalid XML.")") }
        return items
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        text = ""
        switch elementName.lowercased() {
        case "response": href = ""; responseProps = [:]
        case "propstat": inPropstat = true; props = [:]; status = ""; collection = false
        case "collection": collection = true
        default: break
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName.lowercased() {
        case "href": if !inPropstat { href = value }
        case "status": if inPropstat { status = value }
        case "displayname", "getcontentlength", "getlastmodified", "creationdate", "getetag", "getcontenttype": if inPropstat { props[elementName.lowercased()] = value }
        case "propstat":
            if status.contains(" 200 ") { responseProps.merge(props) { _, new in new }; if collection { responseProps["collection"] = "1" } }
            inPropstat = false
        case "response": if let item = makeItem() { items.append(item) }
        default: break
        }
        text = ""
    }
    private func makeItem() -> FileItem? {
        guard !responseProps.isEmpty, let url = URL(string: href, relativeTo: server.baseURL), let decoded = url.path(percentEncoded: true).removingPercentEncoding else { return nil }
        let base = server.baseURL.path(percentEncoded: true).removingPercentEncoding ?? server.baseURL.path
        let basePath = base == "/" ? "" : base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let prefix = basePath.isEmpty ? "" : "/" + basePath
        guard decoded == prefix || decoded == prefix + "/" || decoded.hasPrefix(prefix + "/") else { return nil }
        let path = PathUtil.normalized(String(decoded.dropFirst(prefix.count)))
        guard includeSelf || path != PathUtil.normalized(requestedPath) else { return nil }
        let folder = responseProps["collection"] == "1"
        let name = path == "/" ? server.name : PathUtil.name(path)
        return FileItem(location: .webdav(server.id), path: path, name: name, isDirectory: folder, size: folder ? nil : responseProps["getcontentlength"].flatMap(Int64.init), modified: Self.httpDate(responseProps["getlastmodified"]), created: Self.isoDate(responseProps["creationdate"]), etag: Self.etag(responseProps["getetag"]), contentType: responseProps["getcontenttype"])
    }
    static func etag(_ value: String?) -> String? { guard var value, !value.isEmpty else { return nil }; if value.hasPrefix("W/") { value = String(value.dropFirst(2)) }; return value.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
    static func httpDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0)
        for pattern in ["EEE, dd MMM yyyy HH:mm:ss zzz", "EEEE, dd-MMM-yy HH:mm:ss zzz", "EEE MMM d HH:mm:ss yyyy"] { f.dateFormat = pattern; if let date = f.date(from: value) { return date } }
        return nil
    }
    private static func isoDate(_ value: String?) -> Date? { guard let value else { return nil }; let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; if let date = f.date(from: value) { return date }; f.formatOptions = [.withInternetDateTime]; return f.date(from: value) }
}
