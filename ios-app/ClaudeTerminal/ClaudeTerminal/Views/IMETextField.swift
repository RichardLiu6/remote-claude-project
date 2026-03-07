import UIKit

/// An invisible UITextField that acts as the input proxy for the terminal.
/// This handles Chinese/Japanese/Korean IME composition correctly by using
/// UITextFieldDelegate to capture committed text and forward it to WebSocket.
///
/// Similar to the Web App's overlay-input textarea approach, but using native
/// UITextField which handles iOS IME composition natively without any hacks.
///
/// v6: Extracted from TerminalView.swift for code organization.
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
