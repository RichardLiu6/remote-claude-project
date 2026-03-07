import Foundation
import UIKit

/// Bridges the Mac clipboard to the iOS app via GET /api/clipboard.
///
/// Allows users to paste content from their Mac's clipboard into the terminal,
/// useful when text is copied on the Mac but needs to be pasted on the phone.
final class ClipboardBridge {

    private let config: ServerConfig

    init(config: ServerConfig) {
        self.config = config
    }

    /// Fetch the Mac's clipboard content from GET /api/clipboard.
    /// Returns the clipboard text or nil if unavailable.
    func fetchMacClipboard() async throws -> String? {
        let urlString = "\(config.baseURL)/api/clipboard"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        // Response can be JSON {"content": "..."} or plain text
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let content = json["content"] as? String {
            return content
        }

        return String(data: data, encoding: .utf8)
    }

    /// Fetch Mac clipboard and copy to iOS clipboard.
    func syncToiOS() async throws -> String? {
        let content = try await fetchMacClipboard()
        if let content = content, !content.isEmpty {
            await MainActor.run {
                UIPasteboard.general.string = content
            }
        }
        return content
    }
}
