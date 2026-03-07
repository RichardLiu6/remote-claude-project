import SwiftUI
import SwiftTerm

/// Full-screen terminal view that connects to a tmux session via WebSocket.
/// Uses SwiftTerm's TerminalView (UIKit) wrapped in UIViewRepresentable.
///
/// v3 additions:
///   - Fixed isConnected timing (only true after first message)
///   - Session end detection with reconnect option
///   - Chinese/IME input via overlay UITextField proxy
///   - Connection status indicator (green/yellow/red)
///   - Haptic feedback (bell, connect/disconnect, quick-bar)
///   - Safe area adaptation (notch, home indicator, landscape)
///
/// v4 additions:
///   - NWPathMonitor network awareness (auto-reconnect on WiFi/Cellular change)
///   - Foreground/background reconnect via scenePhase
///   - Session switcher without leaving terminal
///   - External keyboard detection (hide quick-bar)
///
/// v5 refactor:
///   - Top bar extracted to TerminalToolbar.swift
///   - Session switcher extracted to SessionSwitcher.swift
///   - Landscape optimization (auto-hide top bar)
struct TerminalView: View {
    @State var sessionName: String
    let serverConfig: ServerConfig

    @StateObject private var wsManager: WebSocketManager
    @StateObject private var voiceManager: VoiceManager
    @StateObject private var notificationManager = NotificationManager()
    @StateObject private var networkMonitor = NetworkMonitor()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var showDisconnectAlert = false
    @State private var showClipboardMenu = false
    @State private var macClipboardContent: String?
    @State private var inScrollMode = false
    @State private var disconnectAlertReason: DisconnectReason = .none
    @State private var showSessionSwitcher = false
    @State private var availableSessions: [TmuxSession] = []
    @State private var hasExternalKeyboard = false
    @State private var isLandscape = false
    @StateObject private var uploadManager: FileUploadManager
    @State private var showUploadSourcePicker = false
    @State private var showPhotoPicker = false
    @State private var showDocumentPicker = false

    init(sessionName: String, serverConfig: ServerConfig) {
        self._sessionName = State(initialValue: sessionName)
        self.serverConfig = serverConfig
        _wsManager = StateObject(wrappedValue: WebSocketManager(config: serverConfig))
        _voiceManager = StateObject(wrappedValue: VoiceManager(config: serverConfig))
        _uploadManager = StateObject(wrappedValue: FileUploadManager(config: serverConfig))
    }

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height

            VStack(spacing: 0) {
                // v5: Hide top bar in landscape for maximum terminal space
                if !landscape {
                    TerminalToolbar(
                        sessionName: sessionName,
                        wsManager: wsManager,
                        voiceManager: voiceManager,
                        networkMonitor: networkMonitor,
                        serverConfig: serverConfig,
                        inScrollMode: inScrollMode,
                        uploadManager: uploadManager,
                        onDismiss: {
                            wsManager.disconnect()
                            dismiss()
                        },
                        onShowSessionSwitcher: {
                            Task {
                                availableSessions = (try? await WebSocketManager.fetchSessions(config: serverConfig)) ?? []
                                showSessionSwitcher = true
                            }
                        },
                        onShowClipboard: { content in
                            macClipboardContent = content
                            showClipboardMenu = true
                        },
                        onShowUploadPicker: {
                            showUploadSourcePicker = true
                        }
                    )
                    .padding(.top, geometry.safeAreaInsets.top)
                }

                // Terminal area with scroll gesture overlay
                SwiftTermView(
                    wsManager: wsManager,
                    notificationManager: notificationManager,
                    serverConfig: serverConfig,
                    inScrollMode: $inScrollMode
                )
                .ignoresSafeArea(.keyboard, edges: .bottom)

                // Quick-key bar above keyboard (hidden when external keyboard connected)
                // v5: Compact layout in landscape
                InputAccessoryBar(onKey: { action in
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    wsManager.sendInput(action.ansiSequence)
                }, isHidden: hasExternalKeyboard, isCompact: landscape)
                .padding(.bottom, geometry.safeAreaInsets.bottom)
            }
            .padding(.leading, geometry.safeAreaInsets.leading)
            .padding(.trailing, geometry.safeAreaInsets.trailing)
            .onChange(of: landscape) { newValue in
                isLandscape = newValue
            }
        }
        .background(Color.black)
        .edgesIgnoringSafeArea(.all)
        .onAppear {
            wsManager.connect(session: sessionName)
            voiceManager.setSession(sessionName)
            notificationManager.setSession(sessionName)
            notificationManager.requestPermission()

            UserDefaults.standard.set(sessionName, forKey: "last_session_name")

            wsManager.onSessionEnded = {
                disconnectAlertReason = .sessionEnded
                showDisconnectAlert = true
            }
            wsManager.onVoiceEvent = { payload in
                voiceManager.handleVoiceEvent(payload)
            }
            wsManager.onNotifyEvent = { payload in
                notificationManager.handleNotifyEvent(payload)
            }
            wsManager.onConnectionStateChanged = { newState in
                switch newState {
                case .connected:
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                case .disconnected:
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.warning)
                default:
                    break
                }
            }

            networkMonitor.onNetworkRestored = { [weak wsManager] in
                guard let ws = wsManager else { return }
                if !ws.connectionState.isConnected {
                    print("[network] triggering reconnect after network restored")
                    ws.reconnect()
                }
            }
            networkMonitor.onNetworkLost = { [weak wsManager] in
                print("[network] network lost, WebSocket will detect on next receive")
                _ = wsManager
            }

            setupExternalKeyboardDetection()
        }
        .onDisappear {
            wsManager.disconnect()
            voiceManager.stop()
            networkMonitor.stopMonitoring()
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                if !wsManager.connectionState.isConnected {
                    print("[lifecycle] app returned to foreground, reconnecting...")
                    wsManager.reconnect()
                }
            }
        }
        .alert(alertTitle, isPresented: $showDisconnectAlert) {
            if disconnectAlertReason == .sessionEnded {
                Button("Back to Sessions") { dismiss() }
                Button("Reconnect") {
                    wsManager.reconnect()
                }
            } else {
                Button("OK") { dismiss() }
                Button("Retry") {
                    wsManager.reconnect()
                }
            }
        } message: {
            Text(alertMessage)
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
        .sheet(isPresented: $showSessionSwitcher) {
            SessionSwitcherSheet(
                currentSession: sessionName,
                sessions: availableSessions,
                onSelect: { newSession in
                    switchToSession(newSession)
                }
            )
            .presentationDetents([.medium])
        }
        // v5: Upload source picker
        .confirmationDialog("Upload File", isPresented: $showUploadSourcePicker) {
            Button("Photo Library") {
                showPhotoPicker = true
            }
            Button("Files") {
                showDocumentPicker = true
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Choose file source")
        }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPicker { image, filename in
                uploadManager.uploadImage(image, filename: filename)
            }
        }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPicker { url, filename in
                uploadManager.uploadFile(url: url, filename: filename)
            }
        }
        // v5: Swipe down from top edge to show toolbar in landscape
        .gesture(
            isLandscape ?
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if value.translation.height > 50 && value.startLocation.y < 44 {
                        // Swipe down from top edge — show session switcher as proxy for toolbar actions
                        Task {
                            availableSessions = (try? await WebSocketManager.fetchSessions(config: serverConfig)) ?? []
                            showSessionSwitcher = true
                        }
                    }
                }
            : nil
        )
        .statusBarHidden(true)
    }

    // MARK: - Session switching

    private func switchToSession(_ newSessionName: String) {
        guard newSessionName != sessionName else { return }
        wsManager.disconnect()
        sessionName = newSessionName
        voiceManager.setSession(newSessionName)
        notificationManager.setSession(newSessionName)
        UserDefaults.standard.set(newSessionName, forKey: "last_session_name")
        wsManager.connect(session: newSessionName)
    }

    // MARK: - External keyboard detection

    private func setupExternalKeyboardDetection() {
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                hasExternalKeyboard = frame.height < 100
            }
        }
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { _ in
            hasExternalKeyboard = false
        }
    }

    // MARK: - Alert content

    private var alertTitle: String {
        switch disconnectAlertReason {
        case .sessionEnded:
            return "Session Ended"
        case .networkError:
            return "Connection Lost"
        case .serverUnreachable:
            return "Server Unreachable"
        case .maxRetriesExceeded:
            return "Connection Failed"
        case .none:
            return "Disconnected"
        }
    }

    private var alertMessage: String {
        switch disconnectAlertReason {
        case .sessionEnded:
            return "The tmux session \"\(sessionName)\" has ended or was closed on the server."
        case .networkError(let msg):
            return "Lost connection to \"\(sessionName)\": \(msg)"
        case .serverUnreachable:
            return "Cannot reach the server. Check your network connection and Tailscale status."
        case .maxRetriesExceeded:
            return "Failed to reconnect after maximum retries. The server may be down."
        case .none:
            return "Connection was closed."
        }
    }
}

// MARK: - SwiftTerm UIKit Wrapper

/// UIViewRepresentable wrapper for SwiftTerm's TerminalView.
/// v3: Adds IME input proxy, improved haptics, and safe area handling.
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

        // Configure the IME input proxy
        container.configureIMEProxy(wsManager: wsManager)

        // Focus the IME text field for keyboard input
        _ = container.imeTextField.becomeFirstResponder()

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
            _ = container.imeTextField.becomeFirstResponder()
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
/// v3: Adds IME input proxy via UITextField overlay.
class TerminalContainerView: UIView {

    let terminalView: SwiftTerm.TerminalView
    let scrollHandler = ScrollGestureHandler()
    let imeTextField = IMETextField()
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

        // Add IME text field (invisible, positioned off-screen for input capture)
        imeTextField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imeTextField)
        NSLayoutConstraint.activate([
            imeTextField.leadingAnchor.constraint(equalTo: leadingAnchor),
            imeTextField.topAnchor.constraint(equalTo: topAnchor, constant: -50),
            imeTextField.widthAnchor.constraint(equalToConstant: 1),
            imeTextField.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    /// Configure the IME text field to send input through WebSocket.
    func configureIMEProxy(wsManager: WebSocketManager) {
        imeTextField.onCommitText = { text in
            wsManager.sendInput(text)
        }
        imeTextField.onSpecialKey = { key in
            wsManager.sendInput(key)
        }
    }

    // MARK: - First responder passthrough

    override var canBecomeFirstResponder: Bool { true }

    // MARK: - Touch handling -- route to scroll handler

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
        // Heavy haptic feedback for long press selection
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
            dismissButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 8),
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

        // Re-focus the IME text field for keyboard input
        _ = imeTextField.becomeFirstResponder()
    }
}

// MARK: - IME Input Proxy TextField

/// An invisible UITextField that acts as the input proxy for the terminal.
/// This handles Chinese/Japanese/Korean IME composition correctly by using
/// UITextFieldDelegate to capture committed text and forward it to WebSocket.
///
/// Similar to the Web App's overlay-input textarea approach, but using native
/// UITextField which handles iOS IME composition natively without any hacks.
class IMETextField: UITextField, UITextFieldDelegate {

    /// Called when text is committed (after IME composition completes).
    var onCommitText: ((String) -> Void)?

    /// Called for special keys (backspace, enter, etc.).
    var onSpecialKey: ((String) -> Void)?

    /// Track the previous text value for diff-based input detection.
    private var previousText: String = ""

    /// Whether we are currently in an IME composition.
    private var isComposing: Bool {
        return markedTextRange != nil
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupTextField()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTextField()
    }

    private func setupTextField() {
        delegate = self
        // Make the text field invisible but functional
        backgroundColor = .clear
        textColor = .clear
        tintColor = .clear
        autocapitalizationType = .none
        autocorrectionType = .no
        spellCheckingType = .no
        smartQuotesType = .no
        smartDashesType = .no
        smartInsertDeleteType = .no
        // Allow any keyboard type - important for IME
        keyboardType = .default
        returnKeyType = .default
        // Enable keyboard
        isHidden = false
        // Prevent the text field from scrolling into view
        isAccessibilityElement = false

        // Listen for text changes
        addTarget(self, action: #selector(textDidChange), for: .editingChanged)
    }

    // Keep the field always available for input
    override var canBecomeFirstResponder: Bool { true }
    override var canResignFirstResponder: Bool { true }

    // MARK: - Text change detection (diff-based, like Web App)

    @objc private func textDidChange() {
        guard !isComposing else {
            // Still composing (marked text visible), don't send yet
            return
        }

        let currentText = text ?? ""
        let prevText = previousText

        if currentText.count > prevText.count {
            // Characters were added
            let newChars = String(currentText.dropFirst(prevText.count))
            if !newChars.isEmpty {
                onCommitText?(newChars)
            }
        } else if currentText.count < prevText.count {
            // Characters were deleted (backspace)
            let deleteCount = prevText.count - currentText.count
            for _ in 0..<deleteCount {
                onSpecialKey?("\u{7F}") // DEL (backspace)
            }
        }

        previousText = currentText

        // Periodically reset the text field to prevent it from growing indefinitely
        if currentText.count > 100 {
            text = ""
            previousText = ""
        }
    }

    // MARK: - UITextFieldDelegate

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        // Enter key
        onSpecialKey?("\r")
        return false
    }

    // Handle special keys via deleteBackward override
    override func deleteBackward() {
        if (text ?? "").isEmpty {
            // Text field is empty but backspace was pressed
            onSpecialKey?("\u{7F}")
        }
        super.deleteBackward()
    }

    // Handle key commands for special keys (arrows, tab, escape)
    override var keyCommands: [UIKeyCommand]? {
        var commands: [UIKeyCommand] = [
            UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(handleArrowUp)),
            UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(handleArrowDown)),
            UIKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: [], action: #selector(handleArrowLeft)),
            UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [], action: #selector(handleArrowRight)),
            UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(handleEscape)),
            UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(handleTab)),
        ]

        // Ctrl key combinations
        let ctrlKeys: [String] = [
            "a", "b", "c", "d", "e", "f", "k", "l", "n", "p", "r", "u", "w", "z",
        ]
        for key in ctrlKeys {
            commands.append(UIKeyCommand(input: key, modifierFlags: .control, action: #selector(handleCtrlKey(_:))))
        }

        return commands
    }

    @objc private func handleArrowUp() { onSpecialKey?("\u{1B}[A") }
    @objc private func handleArrowDown() { onSpecialKey?("\u{1B}[B") }
    @objc private func handleArrowRight() { onSpecialKey?("\u{1B}[C") }
    @objc private func handleArrowLeft() { onSpecialKey?("\u{1B}[D") }
    @objc private func handleEscape() { onSpecialKey?("\u{1B}") }
    @objc private func handleTab() { onSpecialKey?("\t") }

    @objc private func handleCtrlKey(_ command: UIKeyCommand) {
        guard let input = command.input, let char = input.first else { return }
        // Convert letter to control code: 'a' -> 0x01, 'c' -> 0x03, etc.
        let controlCode = Int(char.asciiValue ?? 0) - Int(Character("a").asciiValue ?? 0) + 1
        if controlCode >= 1 && controlCode <= 26 {
            onSpecialKey?(String(UnicodeScalar(controlCode)!))
        }
    }
}
