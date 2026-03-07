import SwiftUI

/// First-launch onboarding flow.
/// 3 pages: Connect -> Control -> Features, then configure Tailscale IP.
/// Stores completion in UserDefaults so it only shows once.
struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var currentPage = 0
    @State private var tailscaleIP: String = ServerConfig.defaultHost
    @State private var tailscalePort: String = String(ServerConfig.defaultPort)

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "link.circle.fill",
            iconColor: .purple,
            title: "Connect",
            subtitle: "Secure Remote Access",
            description: "Connect to your Mac running Claude Code via Tailscale VPN. Your terminal sessions are encrypted end-to-end over the Tailscale network."
        ),
        OnboardingPage(
            icon: "terminal.fill",
            iconColor: .green,
            title: "Control",
            subtitle: "Full Terminal Power",
            description: "Switch between tmux sessions, send keyboard input with the quick-bar, scroll through output, and copy text with long-press. All from your phone."
        ),
        OnboardingPage(
            icon: "wand.and.stars",
            iconColor: .cyan,
            title: "Features",
            subtitle: "More Than a Terminal",
            description: "Voice mode reads Claude's replies aloud. File upload sends photos and documents. Clipboard bridge shares text between devices. Push notifications alert you when tasks complete."
        ),
    ]

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.1)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Skip button
                HStack {
                    Spacer()
                    if currentPage < pages.count {
                        Button("Skip") {
                            completeOnboarding()
                        }
                        .font(.system(.body, weight: .medium))
                        .foregroundColor(.gray)
                        .padding(.trailing, 20)
                        .padding(.top, 12)
                    }
                }

                Spacer()

                if currentPage < pages.count {
                    // Content pages
                    pageContent(pages[currentPage])
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                        .id(currentPage)
                } else {
                    // Configuration page
                    configPage
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }

                Spacer()

                // Page indicator + navigation
                VStack(spacing: 20) {
                    // Page dots
                    HStack(spacing: 8) {
                        ForEach(0...pages.count, id: \.self) { index in
                            Circle()
                                .fill(index == currentPage ? Color.purple : Color.gray.opacity(0.4))
                                .frame(width: index == currentPage ? 10 : 7, height: index == currentPage ? 10 : 7)
                                .animation(.easeInOut(duration: 0.2), value: currentPage)
                        }
                    }

                    // Navigation button
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            if currentPage <= pages.count - 1 {
                                currentPage += 1
                            } else {
                                completeOnboarding()
                            }
                        }
                    } label: {
                        Text(currentPage < pages.count ? "Next" : "Get Started")
                            .font(.system(.headline, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [Color(red: 0.45, green: 0.2, blue: 0.7), Color(red: 0.3, green: 0.1, blue: 0.55)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(14)
                    }
                    .padding(.horizontal, 40)
                }
                .padding(.bottom, 50)
            }
        }
    }

    // MARK: - Page content

    private func pageContent(_ page: OnboardingPage) -> some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: page.icon)
                .font(.system(size: 72, weight: .thin))
                .foregroundStyle(
                    LinearGradient(
                        colors: [page.iconColor, page.iconColor.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 100)

            // Title
            VStack(spacing: 6) {
                Text(page.title)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(page.subtitle)
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundColor(.purple.opacity(0.8))
            }

            // Description
            Text(page.description)
                .font(.system(.body))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .lineSpacing(4)
        }
    }

    // MARK: - Configuration page

    private var configPage: some View {
        VStack(spacing: 24) {
            Image(systemName: "gear.circle.fill")
                .font(.system(size: 72, weight: .thin))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange, .orange.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 100)

            VStack(spacing: 6) {
                Text("Setup")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("Configure Your Server")
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundColor(.orange.opacity(0.8))
            }

            Text("Enter your Mac's Tailscale IP address. You can change this later in Settings.")
                .font(.system(.body))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .lineSpacing(4)

            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "network")
                        .foregroundColor(.purple)
                        .frame(width: 30)
                    TextField("Tailscale IP (e.g. 100.x.x.x)", text: $tailscaleIP)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.white)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.numbersAndPunctuation)
                }
                .padding()
                .background(Color(red: 0.12, green: 0.12, blue: 0.18))
                .cornerRadius(12)

                HStack {
                    Image(systemName: "number")
                        .foregroundColor(.purple)
                        .frame(width: 30)
                    TextField("Port (default: 8022)", text: $tailscalePort)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.white)
                        .keyboardType(.numberPad)
                }
                .padding()
                .background(Color(red: 0.12, green: 0.12, blue: 0.18))
                .cornerRadius(12)
            }
            .padding(.horizontal, 40)
        }
    }

    // MARK: - Completion

    private func completeOnboarding() {
        // Save server config if user changed it
        let host = tailscaleIP.trimmingCharacters(in: .whitespaces)
        let port = Int(tailscalePort) ?? ServerConfig.defaultPort
        if !host.isEmpty {
            let config = ServerConfig(host: host, port: port)
            config.save()
        }

        // Mark onboarding as complete
        UserDefaults.standard.set(true, forKey: "onboarding_completed")
        isPresented = false
    }
}

// MARK: - Data model

private struct OnboardingPage {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let description: String
}
