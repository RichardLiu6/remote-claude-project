import SwiftUI

/// Quick-action keys displayed above the keyboard.
/// v4: Full quick-bar matching Web terminal — NL first (user's #1 request),
/// plus left/right arrows, ^A/^E/^R for line editing.
struct InputAccessoryBar: View {
    /// Callback when a key action is triggered.
    var onKey: (KeyAction) -> Void

    /// Whether to hide the bar (e.g. when external keyboard is connected).
    var isHidden: Bool = false

    /// v5: Compact mode for landscape — reduced padding and height.
    var isCompact: Bool = false

    enum KeyAction {
        case newline      // NL — send Enter (\r), the #1 most-used key
        case tab
        case shiftTab     // Shift-Tab for reverse completion
        case ctrlC
        case escape
        case arrowLeft
        case arrowRight
        case arrowUp
        case arrowDown
        case ctrlA        // Beginning of line
        case ctrlE        // End of line
        case ctrlR        // Reverse search
        case ctrlD
        case ctrlZ
        case ctrlL
        case select       // v6: Trigger text selection mode

        /// The ANSI escape sequence or character to send via WebSocket.
        /// Returns empty string for non-input actions (e.g. select).
        var ansiSequence: String {
            switch self {
            case .newline:   return "\r"
            case .tab:       return "\t"
            case .shiftTab:  return "\u{1B}[Z"
            case .ctrlC:     return "\u{03}"
            case .escape:    return "\u{1B}"
            case .arrowLeft: return "\u{1B}[D"
            case .arrowRight: return "\u{1B}[C"
            case .arrowUp:   return "\u{1B}[A"
            case .arrowDown: return "\u{1B}[B"
            case .ctrlA:     return "\u{01}"
            case .ctrlE:     return "\u{05}"
            case .ctrlR:     return "\u{12}"
            case .ctrlD:     return "\u{04}"
            case .ctrlZ:     return "\u{1A}"
            case .ctrlL:     return "\u{0C}"
            case .select:    return ""
            }
        }

        /// Whether this action sends terminal input or triggers a UI action.
        var isTerminalInput: Bool { self != .select }
    }

    var body: some View {
        if !isHidden {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    // NL (newline/Enter) — first position, highlighted
                    nlButton

                    keyButton("Tab", icon: "arrow.right.to.line", action: .tab)
                    keyButton("^C", icon: nil, action: .ctrlC)
                    keyButton("Esc", icon: nil, action: .escape)

                    Divider()
                        .frame(height: 24)
                        .background(Color.gray.opacity(0.3))

                    keyButton(nil, icon: "arrow.left", action: .arrowLeft)
                    keyButton(nil, icon: "arrow.right", action: .arrowRight)
                    keyButton(nil, icon: "arrow.up", action: .arrowUp)
                    keyButton(nil, icon: "arrow.down", action: .arrowDown)

                    Divider()
                        .frame(height: 24)
                        .background(Color.gray.opacity(0.3))

                    // v6: Select button for text selection mode
                    selectButton

                    Divider()
                        .frame(height: 24)
                        .background(Color.gray.opacity(0.3))

                    keyButton("^A", icon: nil, action: .ctrlA)
                    keyButton("^E", icon: nil, action: .ctrlE)
                    keyButton("^R", icon: nil, action: .ctrlR)
                    keyButton("^D", icon: nil, action: .ctrlD)
                    keyButton("^Z", icon: nil, action: .ctrlZ)
                    keyButton("^L", icon: nil, action: .ctrlL)
                }
                .padding(.horizontal, 8)
            }
            .frame(height: isCompact ? 34 : 44)
            .background(Color(red: 0.15, green: 0.15, blue: 0.2))
        }
    }

    /// v6: Select button — visually distinct (purple tint) for text selection.
    private var selectButton: some View {
        Button {
            onKey(.select)
        } label: {
            Label("Sel", systemImage: "text.cursor")
                .font(.system(size: isCompact ? 12 : 14, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, isCompact ? 8 : 12)
                .padding(.vertical, isCompact ? 4 : 6)
                .background(Color(red: 0.35, green: 0.2, blue: 0.5))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    /// NL button — visually distinct (green tint) since it's the most-used key.
    private var nlButton: some View {
        Button {
            onKey(.newline)
        } label: {
            Text("NL")
                .font(.system(size: isCompact ? 12 : 14, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, isCompact ? 10 : 14)
                .padding(.vertical, isCompact ? 4 : 6)
                .background(Color(red: 0.2, green: 0.45, blue: 0.3))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func keyButton(_ label: String?, icon: String?, action: KeyAction) -> some View {
        Button {
            onKey(action)
        } label: {
            Group {
                if let icon = icon {
                    if let label = label {
                        Label(label, systemImage: icon)
                    } else {
                        Image(systemName: icon)
                    }
                } else {
                    Text(label ?? "")
                }
            }
            .font(.system(size: isCompact ? 12 : 14, weight: .medium, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, isCompact ? 8 : 12)
            .padding(.vertical, isCompact ? 4 : 6)
            .background(Color(red: 0.25, green: 0.25, blue: 0.35))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack {
        Spacer()
        InputAccessoryBar { action in
            print("Key: \(action)")
        }
    }
    .background(Color.black)
    .preferredColorScheme(.dark)
}
