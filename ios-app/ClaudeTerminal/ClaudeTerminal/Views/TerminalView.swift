import SwiftUI
import SwiftTerm

/// Full-screen terminal view that connects to a tmux session via WebSocket.
/// Uses SwiftTerm's TerminalView (UIKit) wrapped in UIViewRepresentable.
struct TerminalView: View {
    let sessionName: String
    let serverConfig: ServerConfig

    @StateObject private var wsManager: WebSocketManager
    @Environment(\.dismiss) private var dismiss
    @State private var showDisconnectAlert = false

    init(sessionName: String, serverConfig: ServerConfig) {
        self.sessionName = sessionName
        self.serverConfig = serverConfig
        _wsManager = StateObject(wrappedValue: WebSocketManager(config: serverConfig))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar: session name + connection status + close button
            topBar

            // Terminal area
            SwiftTermView(wsManager: wsManager)
                .ignoresSafeArea(.keyboard, edges: .bottom)

            // Quick-key bar above keyboard
            InputAccessoryBar { action in
                wsManager.sendInput(action.ansiSequence)
            }
        }
        .background(Color.black)
        .onAppear {
            wsManager.connect(session: sessionName)
            wsManager.onSessionEnded = {
                showDisconnectAlert = true
            }
        }
        .onDisappear {
            wsManager.disconnect()
        }
        .alert("Session Ended", isPresented: $showDisconnectAlert) {
            Button("OK") { dismiss() }
        } message: {
            Text("The tmux session \"\(sessionName)\" has ended.")
        }
        .statusBarHidden(true)
    }

    private var topBar: some View {
        HStack {
            Button {
                wsManager.disconnect()
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.gray)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(sessionName)
                    .font(.system(.subheadline, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                HStack(spacing: 4) {
                    Circle()
                        .fill(wsManager.isConnected ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                    if let error = wsManager.connectionError {
                        Text(error)
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .lineLimit(1)
                    } else {
                        Text(wsManager.isConnected ? "Connected" : "Disconnected")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(red: 0.1, green: 0.1, blue: 0.15))
    }
}

// MARK: - SwiftTerm UIKit Wrapper

/// UIViewRepresentable wrapper for SwiftTerm's TerminalView.
/// Bridges SwiftTerm <-> WebSocketManager bidirectionally:
///   - WebSocket data -> SwiftTerm terminal.feed()
///   - SwiftTerm user input -> WebSocket send
///   - SwiftTerm size change -> WebSocket resize control frame
struct SwiftTermView: UIViewRepresentable {
    let wsManager: WebSocketManager

    func makeUIView(context: Context) -> SwiftTerm.TerminalView {
        let termView = SwiftTerm.TerminalView(frame: .zero)

        // Terminal appearance
        termView.nativeBackgroundColor = .black
        termView.nativeForegroundColor = .init(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0)

        // Use a readable monospace font
        let fontSize: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 14 : 12
        termView.font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

        // Set the delegate for user input and size changes
        termView.terminalDelegate = context.coordinator

        // Allow the terminal view to become first responder for keyboard input
        _ = termView.becomeFirstResponder()

        // Store reference in coordinator for data feeding
        context.coordinator.terminalView = termView

        // Wire up WebSocket -> Terminal data feed
        wsManager.onTerminalData = { data in
            DispatchQueue.main.async {
                let bytes = ArraySlice<UInt8>([UInt8](data))
                context.coordinator.terminalView?.feed(byteArray: bytes)
            }
        }

        return termView
    }

    func updateUIView(_ uiView: SwiftTerm.TerminalView, context: Context) {
        // No dynamic updates needed — all state flows through callbacks
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(wsManager: wsManager)
    }

    class Coordinator: NSObject, SwiftTerm.TerminalViewDelegate {
        let wsManager: WebSocketManager
        weak var terminalView: SwiftTerm.TerminalView?
        private var lastCols: Int = 0
        private var lastRows: Int = 0

        init(wsManager: WebSocketManager) {
            self.wsManager = wsManager
        }

        // MARK: - TerminalViewDelegate

        /// Called when the user types in the terminal. Forward to WebSocket.
        func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
            let bytes = Array(data)
            if let str = String(bytes: bytes, encoding: .utf8) {
                wsManager.sendInput(str)
            }
        }

        /// Called when the terminal view size changes (e.g., rotation, keyboard).
        func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
            // Avoid sending duplicate resize events
            guard newCols != lastCols || newRows != lastRows else { return }
            guard newCols > 0 && newRows > 0 else { return }
            lastCols = newCols
            lastRows = newRows
            wsManager.sendResize(cols: newCols, rows: newRows)
        }

        /// Called when the terminal sets the title (via ANSI escape).
        func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {
            // Could update the navigation title in the future
        }

        /// Called when the terminal requests scrollback content.
        func scrolled(source: SwiftTerm.TerminalView, position: Double) {
            // Scrollback is managed by tmux, not SwiftTerm
        }

        /// Called when the clipboard should be set.
        func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {
            if let str = String(data: content, encoding: .utf8) {
                UIPasteboard.general.string = str
            }
        }

        /// Called to request the selection/clipboard content for paste.
        func requestOpenLink(source: SwiftTerm.TerminalView, link: String, params: [String : String]) {
            if let url = URL(string: link) {
                UIApplication.shared.open(url)
            }
        }

        /// Called when the host finishes running a command (OSC 7).
        func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {
            // Not used in tmux-attached mode
        }

        func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {
            // Content range changed — no action needed
        }

        /// Bell sound triggered by terminal.
        func bell(source: SwiftTerm.TerminalView) {
            // Haptic feedback on bell
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        }

        func iTermContent(source: SwiftTerm.TerminalView, content: ArraySlice<UInt8>) {
            // iTerm inline images — not supported for now
        }
    }
}
