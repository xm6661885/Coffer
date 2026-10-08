import Foundation

enum Formatters {
    static func bytes(_ value: Int64?) -> String { value.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "—" }
    static func date(_ date: Date?) -> String {
        guard let date else { return "—" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return date.formatted(.dateTime.hour().minute()) }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if calendar.component(.year, from: date) == calendar.component(.year, from: Date()) { return date.formatted(.dateTime.month(.abbreviated).day()) }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }
    static func duration(_ seconds: Double) -> String {
        let n = max(0, seconds.isFinite ? Int(seconds) : 0)
        return n >= 3600 ? String(format: "%d:%02d:%02d", n / 3600, n / 60 % 60, n % 60) : String(format: "%d:%02d", n / 60, n % 60)
    }
    static func relative(_ date: Date) -> String { date.formatted(.relative(presentation: .named)) }
}
