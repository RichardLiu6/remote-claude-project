import SwiftUI

/// Top toolbar for the terminal view — session name, connection status, voice toggle, clipboard.
/// Extracted from TerminalView in v5 for code organization.
struct TerminalToolbar: View {
    let sessionName: String
    let wsManager: WebSocketManager
    let voiceManager: VoiceManager
    let networkMonitor: NetworkMonitor
    let serverConfig: ServerConfig
    let inScrollMode: Bool

    var onDismiss: () -> Void
    var onShowSessionSwitcher: () -> Void
    var onShowClipboard: (String?) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.gray)
            }

            // Tappable session name for quick switching
            Button {
                onShowSessionSwitcher()
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(sessionName)
                            .font(.system(.subheadline, design: .monospaced))
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.gray)
                    }

                    HStack(spacing: 4) {
                        // Connection status indicator
                        connectionStatusDot

                        if let error = wsManager.connectionError {
                            Text(error)
                                .font(.caption2)
                                .foregroundColor(.orange)
                                .lineLimit(1)
                        } else {
                            Text(wsManager.connectionState.statusText)
                                .font(.caption2)
                                .foregroundColor(connectionStatusTextColor)
                        }

                        // Network type indicator
                        if !networkMonitor.isConnected {
                            Text("NO NET")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.red)
                                .cornerRadius(3)
                        }

                        if inScrollMode {
                            Text("SCROLL")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.black)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.yellow)
                                .cornerRadius(3)
                        }
                    }
                }
            }

            Spacer()

            // Clipboard bridge button
            Button {
                Task {
                    let bridge = ClipboardBridge(config: serverConfig)
                    let content = try? await bridge.fetchMacClipboard()
                    onShowClipboard(content)
                }
            } label: {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
            }

            // Voice toggle button
            Button {
                voiceManager.toggleVoice()
            } label: {
                Image(systemName: voiceManager.isVoiceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 16))
                    .foregroundColor(voiceManager.isVoiceEnabled ? .green : .gray)
            }

            if voiceManager.isPlaying {
                Image(systemName: "waveform")
                    .font(.system(size: 14))
                    .foregroundColor(.green)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(red: 0.1, green: 0.1, blue: 0.15))
    }

    // MARK: - Connection status visuals

    @ViewBuilder
    private var connectionStatusDot: some View {
        Circle()
            .fill(connectionDotColor)
            .frame(width: 6, height: 6)
    }

    private var connectionDotColor: SwiftUI.Color {
        switch wsManager.connectionState {
        case .connected:
            return .green
        case .connecting, .reconnecting:
            return .yellow
        case .disconnected:
            return .red
        }
    }

    private var connectionStatusTextColor: SwiftUI.Color {
        switch wsManager.connectionState {
        case .connected:
            return .gray
        case .connecting, .reconnecting:
            return .orange
        case .disconnected:
            return .red
        }
    }
}
