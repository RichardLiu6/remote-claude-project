import Foundation

/// Represents a tmux session returned by GET /api/sessions.
/// JSON shape: { "name": "claude", "created": 1700000000, "windows": 1 }
struct TmuxSession: Codable, Identifiable, Hashable {
    let name: String
    let created: Int
    let windows: Int

    var id: String { name }

    /// Human-readable creation time.
    var createdDate: Date {
        Date(timeIntervalSince1970: TimeInterval(created))
    }

    var createdDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: createdDate, relativeTo: Date())
    }
}
