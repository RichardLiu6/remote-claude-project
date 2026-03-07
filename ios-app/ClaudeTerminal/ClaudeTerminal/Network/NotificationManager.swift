import Foundation
import UserNotifications
import UIKit

/// Monitors terminal output for completion patterns and sends local notifications.
///
/// Watched patterns (matching Web App behavior):
///   - Text containing specific emoji or keywords indicating task completion
///   - Server-sent \x01notify: control frames
///
/// Only fires notifications when the app is backgrounded to avoid interrupting active use.
final class NotificationManager: ObservableObject {

    // MARK: - Published state

    @Published var isEnabled = true
    @Published var hasPermission = false

    // MARK: - Configuration

    /// Patterns that trigger a notification when found in terminal output.
    private let completionPatterns: [String] = [
        "\u{2705}",   // Checkmark emoji
        "\u{2728}",   // Sparkles emoji
        "\u{1F389}",  // Party emoji
        "Task completed",
        "task completed",
        "Build succeeded",
        "All tests passed",
    ]

    // Rate limiting: at most one notification every 10 seconds
    private var lastNotificationTime: Date = .distantPast
    private let notificationCooldown: TimeInterval = 10.0

    private var sessionName: String = ""

    // MARK: - Init

    init() {
        checkPermission()
    }

    // MARK: - Public API

    /// Set the session name for notification context.
    func setSession(_ name: String) {
        self.sessionName = name
    }

    /// Request notification permissions.
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.hasPermission = granted
                DebugLogStore.shared.log("Notification permission: \(granted ? "granted" : "denied")", category: .system)
            }
            if let error = error {
                print("[notify] permission error: \(error.localizedDescription)")
                DebugLogStore.shared.log("Notification permission error: \(error.localizedDescription)", category: .error)
            }
        }
    }

    /// Check current permission status.
    func checkPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.hasPermission = settings.authorizationStatus == .authorized
            }
        }
    }

    /// Scan terminal output text for completion patterns.
    /// Call this with each chunk of terminal data received.
    func scanTerminalOutput(_ text: String) {
        guard isEnabled, hasPermission else { return }

        // Only notify when app is not in foreground
        guard UIApplication.shared.applicationState != .active else { return }

        // Check rate limit
        let now = Date()
        guard now.timeIntervalSince(lastNotificationTime) > notificationCooldown else { return }

        // Check for completion patterns
        for pattern in completionPatterns {
            if text.contains(pattern) {
                lastNotificationTime = now
                DebugLogStore.shared.log("Completion pattern matched, sending notification", category: .system)
                sendNotification(
                    title: "Claude Terminal",
                    body: "Task completed in session \"\(sessionName)\""
                )
                return
            }
        }
    }

    /// Handle a server-sent notification control frame.
    /// Expected JSON: {"title": "...", "body": "...", "sound": true}
    func handleNotifyEvent(_ payload: [String: Any]) {
        guard isEnabled, hasPermission else { return }

        let title = payload["title"] as? String ?? "Claude Terminal"
        let body = payload["body"] as? String ?? "Notification from session \"\(sessionName)\""

        DebugLogStore.shared.log("Notify event: \(title) - \(body.prefix(40))", category: .system)
        sendNotification(title: title, body: body)
    }

    // MARK: - Private

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[notify] send error: \(error.localizedDescription)")
                DebugLogStore.shared.log("Notification send error: \(error.localizedDescription)", category: .error)
            }
        }
    }
}
