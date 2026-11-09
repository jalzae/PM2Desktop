import Foundation

enum Fmt {
    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .memory)
    }

    static func cpu(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }

    static func uptime(since: Date?) -> String {
        guard let since else { return "—" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: since, relativeTo: Date())
    }

    static func time(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .omitted, time: .standard)
    }
}
