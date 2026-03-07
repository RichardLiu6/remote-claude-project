import SwiftUI

@main
struct ClaudeTerminalApp: App {
    var body: some Scene {
        WindowGroup {
            SessionPickerView()
                .preferredColorScheme(.dark)
        }
    }
}
