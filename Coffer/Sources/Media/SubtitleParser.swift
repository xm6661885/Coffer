import Foundation

enum SubtitleParser {
    struct Cue: Hashable, Sendable { let start: Double; let end: Double; let text: String }
    static func parse(_ text: String, ext: String) -> [Cue] {
        let text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if ["ass", "ssa"].contains(ext.lowercased()) {
            return text.components(separatedBy: "\n").compactMap { line in
                guard line.lowercased().hasPrefix("dialogue:") else { return nil }
                let fields = line.dropFirst(9).split(separator: ",", maxSplits: 9, omittingEmptySubsequences: false)
                guard fields.count == 10, let start = time(String(fields[1])), let end = time(String(fields[2])) else { return nil }
                let text = String(fields[9]).replacingOccurrences(of: "\\N", with: "\n").replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: #"\{[^}]*\}"#, with: "", options: .regularExpression)
                return Cue(start: start, end: end, text: clean(text))
            }.sorted { $0.start < $1.start }
        }
        return text.components(separatedBy: "\n\n").compactMap { block in
            let lines = block.components(separatedBy: "\n")
            guard let at = lines.firstIndex(where: { $0.contains("-->") }) else { return nil }
            let parts = lines[at].components(separatedBy: "-->")
            guard parts.count == 2, let start = time(parts[0].trimmingCharacters(in: .whitespaces)), let end = time(parts[1].trimmingCharacters(in: .whitespaces).components(separatedBy: " ")[0]), end >= start else { return nil }
            return Cue(start: start, end: end, text: clean(lines.dropFirst(at + 1).joined(separator: "\n")))
        }.sorted { $0.start < $1.start }
    }
    private static func clean(_ text: String) -> String { text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression).replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").trimmingCharacters(in: .whitespacesAndNewlines) }
    static func time(_ value: String) -> Double? { let pieces = value.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".").split(separator: ":").compactMap { Double($0) }; guard pieces.count == 2 || pieces.count == 3 else { return nil }; return pieces.count == 3 ? pieces[0] * 3600 + pieces[1] * 60 + pieces[2] : pieces[0] * 60 + pieces[1] }
    static func load(_ url: URL) async throws -> [Cue] { try await Task.detached { let data = try Data(contentsOf: url, options: .mappedIfSafe); return parse(TextDecoding.decode(data).text, ext: url.pathExtension) }.value }
}
