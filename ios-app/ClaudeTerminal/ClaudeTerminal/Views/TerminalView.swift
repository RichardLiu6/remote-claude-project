import SwiftUI
import SwiftTerm

/// Full-screen terminal view that connects to a tmux session via WebSocket.
/// Uses SwiftTerm's TerminalView (UIKit) wrapped in UIViewRepresentable.
///
/// v2 additions:
///   - Touch scroll with non-linear acceleration + momentum
///   - Long-press text selection with copy
///   - Voice mode integration (AVAudioPlayer TTS)
///   - Notification monitoring
///   - Clipboard bridge (Mac clipboard access)
struct TerminalView: View {
    let sessionName: String
    let serverConfig: ServerConfig

    @StateObject private var wsManager: WebSocketManager
    @StateObject private var voiceManager: VoiceManager
    @StateObject private var notificationManager = NotificationManager()
    @Environment(\.dismiss) private var dismiss
    @State private var showDisconnectAlert = false
    @State private var showClipboardMenu = false
    @State private var macClipboardContent: String?
    @State private var inScrollMode = false

    init(sessionName: String, serverConfig: ServerConfig) {
        self.sessionName = sessionName
        self.serverConfig = serverConfig
        _wsManager = StateObject(wrappedValue: WebSocketManager(config: serverConfig))
        _voiceManager = StateObject(wrappedValue: VoiceManager(config: serverConfig))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar: session name + connection status + voice toggle + close button
            topBar

            // Terminal area with scroll gesture overlay
            SwiftTermView(
                wsManager: wsManager,
                notificationManager: notificationManager,
                serverConfig: serverConfig,
                inScrollMode: $inScrollMode
            )
            .ignoresSafeArea(.keyboard, edges: .bottom)

            // Quick-key bar above keyboard
            InputAccessoryBar { action in
                wsManager.sendInput(action.ansiSequence)
            }
        }
        .background(Color.black)
        .onAppear {
            wsManager.connect(session: sessionName)
            voiceManager.setSession(sessionName)
            notificationManager.setSession(sessionName)
            notificationManager.requestPermission()

            wsManager.onSessionEnded = {
                showDisconnectAlert = true
            }
            wsManager.onVoiceEvent = { payload in
                voiceManager.handleVoiceEvent(payload)
            }
            wsManager.onNotifyEvent = { payload in
                notificationManager.handleNotifyEvent(payload)
            }
        }
        .onDisappear {
            wsManager.disconnect()
            voiceManager.stop()
        }
        .alert("Session Ended", isPresented: $showDisconnectAlert) {
            Button("OK") { dismiss() }
        } message: {
            Text("The tmux session \"\(sessionName)\" has ended.")
        }
        .confirmationDialog("Paste", isPresented: $showClipboardMenu) {
            if let content = macClipboardContent, !content.isEmpty {
                Button("Paste Mac Clipboard") {
                    wsManager.sendInput(content)
                }
            }
            if let local = UIPasteboard.general.string, !local.isEmpty {
                Button("Paste iOS Clipboard") {
                    wsManager.sendInput(local)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Choose clipboard source")
        }
        .statusBarHidden(true)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 8) {
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

            Spacer()

            // Clipboard bridge button
            Button {
                Task {
                    let bridge = ClipboardBridge(config: serverConfig)
                    macClipboardContent = try? await bridge.fetchMacClipboard()
                    showClipboardMenu = true
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
}

// MARK: - SwiftTerm UIKit Wrapper

/// UIViewRepresentable wrapper for SwiftTerm's TerminalView.
/// v2: Adds touch scroll gesture handling, long-press selection, and notification scanning.
struct SwiftTermView: UIViewRepresentable {
    let wsManager: WebSocketManager
    let notificationManager: NotificationManager
    let serverConfig: ServerConfig
    @Binding var inScrollMode: Bool

    func makeUIView(context: Context) -> TerminalContainerView {
        let container = TerminalContainerView()
        let termView = container.terminalView

        // Terminal appearance based on theme
        applyTheme(serverConfig.theme, to: termView)

        // Use configured font size (fallback to iPad-appropriate size)
        let fontSize: CGFloat = serverConfig.fontSize > 0 ? serverConfig.fontSize :
            (UIDevice.current.userInterfaceIdiom == .pad ? 14 : 12)
        termView.font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

        // Set the delegate for user input and size changes
        termView.terminalDelegate = context.coordinator

        // Allow the terminal view to become first responder for keyboard input
        _ = termView.becomeFirstResponder()

        // Store references in coordinator
        context.coordinator.terminalView = termView
        context.coordinator.containerView = container

        // Configure scroll gesture handler
        let scrollHandler = container.scrollHandler
        scrollHandler.onScroll = { direction, lines in
            if direction == "exit" {
                wsManager.sendScroll(direction: "exit")
            } else {
                wsManager.sendScroll(direction: direction, lines: lines)
            }
        }
        scrollHandler.onTap = {
            _ = termView.becomeFirstResponder()
        }
        scrollHandler.onScrollModeChanged = { isScrolling in
            DispatchQueue.main.async {
                context.coordinator.updateScrollMode?(isScrolling)
            }
        }
        scrollHandler.onLongPress = {
            DispatchQueue.main.async {
                container.showSelectionOverlay(for: termView)
            }
        }

        // Store scroll mode update closure in coordinator
        context.coordinator.updateScrollMode = { isScrolling in
            self.inScrollMode = isScrolling
        }

        // Wire up WebSocket -> Terminal data feed + notification scanning
        wsManager.onTerminalData = { data in
            DispatchQueue.main.async {
                let bytes = ArraySlice<UInt8>([UInt8](data))
                context.coordinator.terminalView?.feed(byteArray: bytes)

                // Scan for notification patterns
                if let text = String(data: data, encoding: .utf8) {
                    context.coordinator.notificationManager?.scanTerminalOutput(text)
                }
            }
        }

        return container
    }

    func updateUIView(_ uiView: TerminalContainerView, context: Context) {
        // No dynamic updates needed
    }

    /// Apply terminal color theme.
    private func applyTheme(_ theme: TerminalTheme, to termView: SwiftTerm.TerminalView) {
        switch theme {
        case .dark:
            termView.nativeBackgroundColor = .black
            termView.nativeForegroundColor = .init(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0)
        case .light:
            termView.nativeBackgroundColor = .init(red: 1.0, green: 1.0, blue: 0.97, alpha: 1.0)
            termView.nativeForegroundColor = .init(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        case .solarized:
            termView.nativeBackgroundColor = .init(red: 0.0, green: 0.17, blue: 0.21, alpha: 1.0)
            termView.nativeForegroundColor = .init(red: 0.51, green: 0.58, blue: 0.59, alpha: 1.0)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(wsManager: wsManager, notificationManager: notificationManager)
    }

    class Coordinator: NSObject, SwiftTerm.TerminalViewDelegate {
        let wsManager: WebSocketManager
        weak var notificationManager: NotificationManager?
        weak var terminalView: SwiftTerm.TerminalView?
        weak var containerView: TerminalContainerView?
        var updateScrollMode: ((_ isScrolling: Bool) -> Void)?
        private var lastCols: Int = 0
        private var lastRows: Int = 0

        init(wsManager: WebSocketManager, notificationManager: NotificationManager) {
            self.wsManager = wsManager
            self.notificationManager = notificationManager
        }

        // MARK: - TerminalViewDelegate

        func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
            let bytes = Array(data)
            if let str = String(bytes: bytes, encoding: .utf8) {
                wsManager.sendInput(str)
            }
        }

        func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
            guard newCols != lastCols || newRows != lastRows else { return }
            guard newCols > 0 && newRows > 0 else { return }
            lastCols = newCols
            lastRows = newRows
            wsManager.sendResize(cols: newCols, rows: newRows)
        }

        func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) { }

        func scrolled(source: SwiftTerm.TerminalView, position: Double) { }

        func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {
            if let str = String(data: content, encoding: .utf8) {
                UIPasteboard.general.string = str
            }
        }

        func requestOpenLink(source: SwiftTerm.TerminalView, link: String, params: [String: String]) {
            if let url = URL(string: link) {
                UIApplication.shared.open(url)
            }
        }

        func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) { }

        func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) { }

        func bell(source: SwiftTerm.TerminalView) {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        }

        func iTermContent(source: SwiftTerm.TerminalView, content: ArraySlice<UInt8>) { }
    }
}

// MARK: - Terminal Container View

/// A UIView that contains both the SwiftTerm TerminalView and manages touch gestures.
/// Intercepts touch events for scroll/long-press while passing through to SwiftTerm for keyboard.
class TerminalContainerView: UIView {

    let terminalView: SwiftTerm.TerminalView
    let scrollHandler = ScrollGestureHandler()
    private var selectionOverlay: UITextView?

    override init(frame: CGRect) {
        terminalView = SwiftTerm.TerminalView(frame: frame)
        super.init(frame: frame)

        terminalView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(terminalView)
        NSLayoutConstraint.activate([
            terminalView.topAnchor.constraint(equalTo: topAnchor),
            terminalView.bottomAnchor.constraint(equalTo: bottomAnchor),
            terminalView.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    // MARK: - First responder passthrough

    override var canBecomeFirstResponder: Bool { true }

    // MARK: - Touch handling — route to scroll handler

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else {
            super.touchesBegan(touches, with: event)
            return
        }
        let point = touch.location(in: self)

        // If selection overlay is visible, let it handle touches
        if let overlay = selectionOverlay, !overlay.isHidden {
            super.touchesBegan(touches, with: event)
            return
        }

        scrollHandler.touchesBegan(at: point)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else {
            super.touchesMoved(touches, with: event)
            return
        }

        if let overlay = selectionOverlay, !overlay.isHidden {
            super.touchesMoved(touches, with: event)
            return
        }

        let point = touch.location(in: self)
        scrollHandler.touchesMoved(to: point)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let overlay = selectionOverlay, !overlay.isHidden {
            // Copy selected text and dismiss overlay
            if let selectedText = overlay.selectedTextRange,
               let text = overlay.text(in: selectedText), !text.isEmpty {
                UIPasteboard.general.string = text
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }
            super.touchesEnded(touches, with: event)
            return
        }

        scrollHandler.touchesEnded()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let overlay = selectionOverlay, !overlay.isHidden {
            super.touchesCancelled(touches, with: event)
            return
        }
        scrollHandler.touchesCancelled()
    }

    // MARK: - Selection Overlay

    /// Show a text selection overlay populated with the terminal buffer text.
    func showSelectionOverlay(for termView: SwiftTerm.TerminalView) {
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()

        // Get terminal buffer text using SwiftTerm's getText API
        let terminal = termView.getTerminal()
        let rows = terminal.rows
        let cols = terminal.cols

        // Use getText with Position for the full visible buffer
        let start = SwiftTerm.Position(col: 0, row: 0)
        let end = SwiftTerm.Position(col: cols - 1, row: rows - 1)
        let bufferText = terminal.getText(start: start, end: end)

        if let existing = selectionOverlay {
            existing.text = bufferText
            existing.isHidden = false
            existing.isSelectable = true
            existing.isEditable = false
            existing.selectAll(nil)
            bringSubviewToFront(existing)
            if let btn = viewWithTag(999) {
                bringSubviewToFront(btn)
            } else {
                addDismissButton()
            }
            return
        }

        // Create overlay
        let overlay = UITextView(frame: bounds)
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.85)
        overlay.textColor = UIColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0)
        overlay.font = termView.font
        overlay.text = bufferText
        overlay.isEditable = false
        overlay.isSelectable = true
        overlay.isScrollEnabled = true
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.dataDetectorTypes = []

        addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: topAnchor),
            overlay.bottomAnchor.constraint(equalTo: bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        selectionOverlay = overlay
        addDismissButton()
    }

    private func addDismissButton() {
        let dismissButton = UIButton(type: .system)
        dismissButton.setTitle("Done", for: .normal)
        dismissButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        dismissButton.setTitleColor(.white, for: .normal)
        dismissButton.backgroundColor = UIColor(red: 0.4, green: 0.2, blue: 0.6, alpha: 1.0)
        dismissButton.layer.cornerRadius = 16
        dismissButton.translatesAutoresizingMaskIntoConstraints = false
        dismissButton.tag = 999
        dismissButton.addTarget(self, action: #selector(dismissSelectionOverlay), for: .touchUpInside)

        addSubview(dismissButton)
        NSLayoutConstraint.activate([
            dismissButton.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            dismissButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            dismissButton.widthAnchor.constraint(equalToConstant: 60),
            dismissButton.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    @objc private func dismissSelectionOverlay() {
        // Copy any selected text before dismissing
        if let overlay = selectionOverlay,
           let selectedRange = overlay.selectedTextRange,
           let selectedText = overlay.text(in: selectedRange), !selectedText.isEmpty {
            UIPasteboard.general.string = selectedText
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }

        selectionOverlay?.isHidden = true
        // Remove the Done button
        viewWithTag(999)?.removeFromSuperview()

        // Re-focus the terminal for keyboard input
        _ = terminalView.becomeFirstResponder()
    }
}
