import SwiftUI

/// Quick-action keys displayed above the keyboard.
/// Matches the Web terminal's quick-bar: Tab, ^C, Esc, Up, Down.
struct InputAccessoryBar: View {
    /// Callback when a key action is triggered.
    var onKey: (KeyAction) -> Void

    enum KeyAction {
        case tab
        case ctrlC
        case escape
        case arrowUp
        case arrowDown
        case ctrlD
        case ctrlZ
        case ctrlL

        /// The ANSI escape sequence or character to send via WebSocket.
        var ansiSequence: String {
            switch self {
            case .tab:      return "\t"
            case .ctrlC:    return "\u{03}"
            case .escape:   return "\u{1B}"
            case .arrowUp:  return "\u{1B}[A"
            case .arrowDown: return "\u{1B}[B"
            case .ctrlD:    return "\u{04}"
            case .ctrlZ:    return "\u{1A}"
            case .ctrlL:    return "\u{0C}"
            }
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                keyButton("Tab", icon: "arrow.right.to.line", action: .tab)
                keyButton("^C", icon: nil, action: .ctrlC)
                keyButton("Esc", icon: nil, action: .escape)

                Divider()
                    .frame(height: 24)
                    .background(Color.gray.opacity(0.3))

                keyButton(nil, icon: "arrow.up", action: .arrowUp)
                keyButton(nil, icon: "arrow.down", action: .arrowDown)

                Divider()
                    .frame(height: 24)
                    .background(Color.gray.opacity(0.3))

                keyButton("^D", icon: nil, action: .ctrlD)
                keyButton("^Z", icon: nil, action: .ctrlZ)
                keyButton("^L", icon: nil, action: .ctrlL)
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 44)
        .background(Color(red: 0.15, green: 0.15, blue: 0.2))
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
            .font(.system(size: 14, weight: .medium, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
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
