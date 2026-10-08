import Foundation

enum PathUtil {
    static func components(_ path: String) -> [String] { path.split(separator: "/").map(String.init) }
    static func normalized(_ path: String) -> String { let parts = components(path); return parts.isEmpty ? "/" : "/" + parts.joined(separator: "/") }
    static func join(_ dir: String, _ name: String) -> String { normalized(dir + "/" + name) }
    static func parent(_ path: String) -> String { let parts = components(path).dropLast(); return parts.isEmpty ? "/" : "/" + parts.joined(separator: "/") }
    static func name(_ path: String) -> String { components(path).last ?? "" }
    static func ext(_ name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        return String(name[name.index(after: dot)...]).lowercased()
    }
    static func baseName(_ name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return name }
        return String(name[..<dot])
    }
    static func isAncestor(_ a: String, of b: String) -> Bool { let a = normalized(a), b = normalized(b); return a == "/" || a == b || b.hasPrefix(a + "/") }
    static func uniqueName(_ name: String, existing: Set<String>, isDirectory: Bool) -> String {
        let names = Set(existing.map { $0.lowercased() })
        if !names.contains(name.lowercased()) { return name }
        let stem = isDirectory ? name : baseName(name)
        let suffix = isDirectory || ext(name).isEmpty ? "" : String(name[stem.endIndex...])
        var n = 2
        while names.contains((stem + " \(n)" + suffix).lowercased()) { n += 1 }
        return stem + " \(n)" + suffix
    }
    static func isValidName(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !name.contains("/") && !name.contains("\0") && name != "." && name != ".." && name.utf8.count <= 255
    }
}
