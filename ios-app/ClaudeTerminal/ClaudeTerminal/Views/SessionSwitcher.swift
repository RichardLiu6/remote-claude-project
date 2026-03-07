import SwiftUI

/// A half-sheet that lets the user switch tmux sessions without leaving the terminal.
/// Tap a different session to disconnect current and connect to the new one.
/// Extracted from TerminalView in v5 for code organization.
struct SessionSwitcherSheet: View {
    let currentSession: String
    let sessions: [TmuxSession]
    var onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(sessions) { session in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "terminal.fill")
                                .foregroundColor(session.name == currentSession ? .green : .gray)
                            Text(session.name)
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(session.name == currentSession ? .bold : .medium)
                                .foregroundColor(.white)
                        }
                        HStack(spacing: 12) {
                            Label("\(session.windows) window\(session.windows == 1 ? "" : "s")",
                                  systemImage: "rectangle.split.3x1")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Text(session.createdDescription)
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    Spacer()
                    if session.name == currentSession {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture {
                    if session.name != currentSession {
                        dismiss()
                        onSelect(session.name)
                    }
                }
                .listRowBackground(
                    session.name == currentSession
                        ? Color(red: 0.1, green: 0.2, blue: 0.15)
                        : Color(red: 0.09, green: 0.13, blue: 0.24)
                )
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.1, green: 0.1, blue: 0.18))
            .navigationTitle("Switch Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
