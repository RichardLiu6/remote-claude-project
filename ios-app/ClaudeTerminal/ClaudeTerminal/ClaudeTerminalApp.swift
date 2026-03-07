import SwiftUI
import UIKit

// MARK: - Shake gesture notification

extension Notification.Name {
    static let deviceDidShake = Notification.Name("deviceDidShake")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
}

@main
struct ClaudeTerminalApp: App {
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "onboarding_completed")

    var body: some Scene {
        WindowGroup {
            SessionPickerView()
                .preferredColorScheme(.dark)
                .fullScreenCover(isPresented: $showOnboarding) {
                    OnboardingView(isPresented: $showOnboarding)
                        .preferredColorScheme(.dark)
                }
        }
    }
}
