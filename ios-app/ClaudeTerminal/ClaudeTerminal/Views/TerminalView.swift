import SwiftUI
import SwiftTerm

/// Full-screen terminal view connecting to a tmux session via WebSocket.
/// v6: SwiftTermView, TerminalContainerView, IMETextField extracted to own files.
///     Added disconnect overlay and landscape mini status bar.
struct TerminalView: View {
    @State var sessionName: String
    let serverConfig: ServerConfig
    @StateObject private var wsManager: WebSocketManager
    @StateObject private var voiceManager: VoiceManager
    @StateObject private var notificationManager = NotificationManager()
    @StateObject private var networkMonitor = NetworkMonitor()
    @StateObject private var uploadManager: FileUploadManager
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
    @State private var showUploadSourcePicker = false
    @State private var showPhotoPicker = false
    @State private var showDocumentPicker = false
    @State private var showDebugPanel = false
    @State private var triggerSelect = false
    @State private var keyboardHeight: CGFloat = 0
    @ObservedObject private var debugLogStore = DebugLogStore.shared

    init(sessionName: String, serverConfig: ServerConfig) {
        self._sessionName = State(initialValue: sessionName)
        self.serverConfig = serverConfig
        _wsManager = StateObject(wrappedValue: WebSocketManager(config: serverConfig))
        _voiceManager = StateObject(wrappedValue: VoiceManager(config: serverConfig))
        _uploadManager = StateObject(wrappedValue: FileUploadManager(config: serverConfig))
    }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                VStack(spacing: 0) {
                    if !landscape {
                        TerminalToolbar(
                            sessionName: sessionName, wsManager: wsManager,
                            voiceManager: voiceManager, networkMonitor: networkMonitor,
                            serverConfig: serverConfig, inScrollMode: inScrollMode,
                            uploadManager: uploadManager,
                            onDismiss: { wsManager.disconnect(); dismiss() },
                            onShowSessionSwitcher: { showSessionSwitcherAction() },
                            onShowClipboard: { macClipboardContent = $0; showClipboardMenu = true },
                            onShowUploadPicker: { showUploadSourcePicker = true }
                        ).padding(.top, geo.safeAreaInsets.top)
                    }
                    if landscape { landscapeMiniStatusBar }
                    SwiftTermView(wsManager: wsManager, notificationManager: notificationManager,
                                  serverConfig: serverConfig, inScrollMode: $inScrollMode,
                                  triggerSelect: $triggerSelect)
                    InputAccessoryBar(onKey: { action in
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        if action == .select {
                            triggerSelect = true
                        } else {
                            wsManager.sendInput(action.ansiSequence)
                        }
                    }, isHidden: hasExternalKeyboard, isCompact: landscape)
                    .padding(.bottom, keyboardHeight > 0 ? keyboardHeight : geo.safeAreaInsets.bottom)
                }
                .padding(.leading, geo.safeAreaInsets.leading)
                .padding(.trailing, geo.safeAreaInsets.trailing)
                .onChange(of: landscape) { isLandscape = $0 }
                disconnectOverlay
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .background(Color.black).edgesIgnoringSafeArea(.all)
        .onAppear { onViewAppear() }
        .onDisappear { onViewDisappear() }
        .onChange(of: scenePhase) { phase in
            if phase == .active && !wsManager.connectionState.isConnected { wsManager.reconnect() }
        }
        .alert(alertTitle, isPresented: $showDisconnectAlert) { alertButtons } message: { Text(alertMessage) }
        .confirmationDialog("Paste", isPresented: $showClipboardMenu) { clipboardDialogButtons } message: { Text("Choose clipboard source") }
        .sheet(isPresented: $showSessionSwitcher) {
            SessionSwitcherSheet(currentSession: sessionName, sessions: availableSessions,
                                 onSelect: { switchToSession($0) }).presentationDetents([.medium])
        }
        .confirmationDialog("Upload File", isPresented: $showUploadSourcePicker) { uploadDialogButtons } message: { Text("Choose file source") }
        .sheet(isPresented: $showPhotoPicker) { PhotoPicker { img, name in uploadManager.uploadImage(img, filename: name) } }
        .sheet(isPresented: $showDocumentPicker) { DocumentPicker { url, name in uploadManager.uploadFile(url: url, filename: name) } }
        .sheet(isPresented: $showDebugPanel) { DebugLogPanel(logStore: debugLogStore, isPresented: $showDebugPanel).presentationDetents([.medium, .large]) }
        .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in showDebugPanel = true }
        .overlay(alignment: .top) { landscapeSwipeOverlay }
        .statusBarHidden(true)
    }

    // MARK: - v6: Landscape mini status bar
    private var landscapeMiniStatusBar: some View {
        HStack(spacing: 6) {
            Circle().fill(connectionDotColor).frame(width: 6, height: 6)
            Text(sessionName).font(.system(size: 10, design: .monospaced)).foregroundColor(.gray)
            if inScrollMode {
                Text("SCROLL").font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.black).padding(.horizontal, 3).padding(.vertical, 1)
                    .background(Color.yellow).cornerRadius(2)
            }
            Spacer()
            Text(wsManager.connectionState.statusText).font(.system(size: 9, design: .monospaced)).foregroundColor(.gray)
        }
        .padding(.horizontal, 8).frame(height: 16).background(Color.black.opacity(0.6))
    }

    // MARK: - v6: Disconnect overlay
    @ViewBuilder private var disconnectOverlay: some View {
        if !wsManager.connectionState.isConnected && wsManager.connectionState != .connecting {
            ZStack {
                Color.black.opacity(0.5).ignoresSafeArea()
                VStack(spacing: 8) {
                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                    Text(wsManager.connectionState.statusText).font(.system(.caption, design: .monospaced)).foregroundColor(.white)
                }
            }.allowsHitTesting(false)
        }
    }

    private var connectionDotColor: SwiftUI.Color {
        switch wsManager.connectionState {
        case .connected: return .green
        case .connecting, .reconnecting: return .yellow
        case .disconnected: return .red
        }
    }

    // MARK: - Lifecycle
    private func onViewAppear() {
        wsManager.connect(session: sessionName)
        voiceManager.setSession(sessionName)
        notificationManager.setSession(sessionName)
        notificationManager.requestPermission()
        UserDefaults.standard.set(sessionName, forKey: "last_session_name")
        wsManager.onSessionEnded = { disconnectAlertReason = .sessionEnded; showDisconnectAlert = true }
        wsManager.onVoiceEvent = { voiceManager.handleVoiceEvent($0) }
        wsManager.onNotifyEvent = { notificationManager.handleNotifyEvent($0) }
        wsManager.onConnectionStateChanged = { state in
            if case .connected = state { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            if case .disconnected = state { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
        }
        networkMonitor.onNetworkRestored = { [weak wsManager] in
            guard let ws = wsManager, !ws.connectionState.isConnected else { return }
            ws.reconnect()
        }
        networkMonitor.onNetworkLost = { _ = wsManager }
        setupExternalKeyboardDetection()
    }

    private func onViewDisappear() {
        wsManager.disconnect(); voiceManager.stop(); networkMonitor.stopMonitoring()
    }

    // MARK: - Session switching
    private func switchToSession(_ name: String) {
        guard name != sessionName else { return }
        wsManager.disconnect(); sessionName = name
        voiceManager.setSession(name); notificationManager.setSession(name)
        UserDefaults.standard.set(name, forKey: "last_session_name")
        wsManager.connect(session: name)
    }

    private func showSessionSwitcherAction() {
        Task { availableSessions = (try? await WebSocketManager.fetchSessions(config: serverConfig)) ?? []; showSessionSwitcher = true }
    }

    // MARK: - Keyboard tracking
    private func setupExternalKeyboardDetection() {
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { n in
            if let f = n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                hasExternalKeyboard = f.height < 100
                withAnimation(.easeOut(duration: 0.25)) { keyboardHeight = f.height }
            }
        }
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { _ in
            hasExternalKeyboard = false
            withAnimation(.easeOut(duration: 0.25)) { keyboardHeight = 0 }
        }
    }

    @ViewBuilder private var landscapeSwipeOverlay: some View {
        if isLandscape {
            Color.clear
                .contentShape(Rectangle())
                .frame(height: 44)
                .gesture(DragGesture(minimumDistance: 30).onEnded { v in
                    if v.translation.height > 50 { showSessionSwitcherAction() }
                })
        }
    }

    // MARK: - Alert content
    @ViewBuilder private var alertButtons: some View {
        if disconnectAlertReason == .sessionEnded {
            Button("Back to Sessions") { dismiss() }; Button("Reconnect") { wsManager.reconnect() }
        } else {
            Button("OK") { dismiss() }; Button("Retry") { wsManager.reconnect() }
        }
    }
    private var alertTitle: String {
        switch disconnectAlertReason {
        case .sessionEnded: return "Session Ended"
        case .networkError: return "Connection Lost"
        case .serverUnreachable: return "Server Unreachable"
        case .maxRetriesExceeded: return "Connection Failed"
        case .none: return "Disconnected"
        }
    }
    private var alertMessage: String {
        switch disconnectAlertReason {
        case .sessionEnded: return "Session \"\(sessionName)\" ended."
        case .networkError(let m): return "Lost connection: \(m)"
        case .serverUnreachable: return "Cannot reach server. Check network and Tailscale."
        case .maxRetriesExceeded: return "Failed after max retries. Server may be down."
        case .none: return "Connection was closed."
        }
    }
    @ViewBuilder private var clipboardDialogButtons: some View {
        if let c = macClipboardContent, !c.isEmpty { Button("Paste Mac Clipboard") { wsManager.sendInput(c) } }
        if let l = UIPasteboard.general.string, !l.isEmpty { Button("Paste iOS Clipboard") { wsManager.sendInput(l) } }
        Button("Cancel", role: .cancel) { }
    }
    @ViewBuilder private var uploadDialogButtons: some View {
        Button("Photo Library") { showPhotoPicker = true }
        Button("Files") { showDocumentPicker = true }
        Button("Cancel", role: .cancel) { }
    }
}
