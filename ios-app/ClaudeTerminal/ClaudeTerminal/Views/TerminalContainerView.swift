import UIKit
import SwiftTerm

/// A UIView that contains both the SwiftTerm TerminalView and manages touch gestures.
/// Intercepts touch events for scroll/long-press while passing through to SwiftTerm for keyboard.
/// v3: Adds IME input proxy via UITextField overlay.
/// v6: Extracted from TerminalView.swift for code organization.
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
