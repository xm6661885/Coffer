import Foundation

enum TextEncoding {
    static func normalized(_ text: String) -> String { text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n") }
    static func bom(_ data: Data) -> Data { for prefix: [UInt8] in [[0xEF, 0xBB, 0xBF], [0xFF, 0xFE], [0xFE, 0xFF]] { if data.starts(with: prefix) { return Data(prefix) } }; return Data() }
    static func encode(_ text: String, encoding: String.Encoding, crlf: Bool, bom: Data, originalEncoding: String.Encoding) throws -> Data {
        let normalized = normalized(text); let output = crlf ? normalized.replacingOccurrences(of: "\n", with: "\r\n") : normalized
        guard var data = output.data(using: encoding, allowLossyConversion: false) else { throw FileProviderError.other("Some characters can't be saved in this encoding.") }
        if encoding == originalEncoding && !bom.isEmpty && !data.starts(with: bom) { data = bom + data }
        return data
    }
}
