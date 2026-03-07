import SwiftUI
import SwiftTerm

/// UIViewRepresentable wrapper for SwiftTerm's TerminalView.
/// v3: Adds IME input proxy, improved haptics, and safe area handling.
/// v6: Extracted from TerminalView.swift for code organization.
struct SwiftTermView: UIViewRepresentable {
    let wsManager: WebSocketManager
    let notificationManager: NotificationManager
    let serverConfig: ServerConfig
    @Binding var inScrollMode: Bool
    /// v6: Toggle to trigger text selection overlay from quick-bar Select button.
    @Binding var triggerSelect: Bool

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
        // v6: Handle Select button trigger from quick-bar
        if triggerSelect {
            DispatchQueue.main.async {
                triggerSelect = false
                if let termView = context.coordinator.terminalView {
                    uiView.showSelectionOverlay(for: termView)
                }
            }
        }
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
            guard newCols > 0 && newRows > 0 else { return }

            // v6: Dynamic font auto-adaptation -- shrink fontSize until cols >= 70
            if newCols < 70 {
                adaptFontSize(terminalView: source, currentCols: newCols)
                return // adaptFontSize will trigger another sizeChanged with updated cols
            }

            guard newCols != lastCols || newRows != lastRows else { return }
            lastCols = newCols
            lastRows = newRows
            wsManager.sendResize(cols: newCols, rows: newRows)
        }

        /// v6: Loop-shrink fontSize (step 1pt, min 8pt) until terminal fits >= 70 columns.
        private func adaptFontSize(terminalView: SwiftTerm.TerminalView, currentCols: Int) {
            guard let currentFont = terminalView.font else { return }
            var fontSize = currentFont.pointSize

            // Avoid infinite loops: only shrink, never grow here
            let minFontSize: CGFloat = 8
            guard fontSize > minFontSize else { return }

            // Shrink by 1pt and let SwiftTerm recalculate
            fontSize -= 1
            fontSize = max(fontSize, minFontSize)
            terminalView.font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            DebugLogStore.shared.log("Font adapted: \(fontSize)pt (cols were \(currentCols) < 70)", category: .system)
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
