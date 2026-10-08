import Foundation
import CoreFoundation

enum TextDecoding {
    static var encodings: [(String, String.Encoding)] {
        func cf(_ encoding: CFStringEncodings) -> String.Encoding { String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(encoding.rawValue))) }
        return [("UTF-8", .utf8), ("UTF-16", .utf16), ("GB18030", cf(.GB_18030_2000)), ("Big5", cf(.big5)), ("Shift_JIS", .shiftJIS), ("EUC-KR", cf(.EUC_KR)), ("Windows-1252", .windowsCP1252), ("ISO-8859-1", .isoLatin1)]
    }
    static func decode(_ data: Data, preferred: String.Encoding? = nil) -> (text: String, encoding: String.Encoding) {
        if let preferred, let text = String(data: data, encoding: preferred) { return (text, preferred) }
        if data.starts(with: [0xEF, 0xBB, 0xBF]), let text = String(data: data.dropFirst(3), encoding: .utf8) { return (text, .utf8) }
        if data.starts(with: [0xFF, 0xFE]), let text = String(data: data, encoding: .utf16) { return (text, .utf16LittleEndian) }
        if data.starts(with: [0xFE, 0xFF]), let text = String(data: data, encoding: .utf16) { return (text, .utf16BigEndian) }
        if let text = String(data: data, encoding: .utf8) { return (text, .utf8) }
        var converted: NSString?; var lossy: ObjCBool = false
        let detected = NSString.stringEncoding(for: data, encodingOptions: [.suggestedEncodingsKey: encodings.dropFirst(2).map { NSNumber(value: $0.1.rawValue) }, .useOnlySuggestedEncodingsKey: false, .allowLossyKey: false], convertedString: &converted, usedLossyConversion: &lossy)
        if detected != 0, let converted { return (converted as String, String.Encoding(rawValue: detected)) }
        return (String(decoding: data, as: UTF8.self), .utf8)
    }
    static func readPrefix(_ url: URL, maxBytes: Int = 5 * 1024 * 1024) async throws -> Data {
        try await Task.detached { let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }; return try handle.read(upToCount: maxBytes) ?? Data() }.value
    }
}
