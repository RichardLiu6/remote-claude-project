import SwiftUI

/// Session picker — the app's landing screen.
/// Fetches tmux sessions from GET /api/sessions and lets the user tap to connect.
///
/// v4: On launch, if a cached "last session" exists and is still active,
/// auto-connects to it for instant startup. User can still manually pick.
struct SessionPickerView: View {
    @State private var sessions: [TmuxSession] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedSession: TmuxSession?
    @State private var showSettings = false
    @State private var serverConfig = ServerConfig.load()
    @State private var hasAttemptedAutoConnect = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.1, green: 0.1, blue: 0.18)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Server address display
                    HStack {
                        Image(systemName: "server.rack")
                            .foregroundColor(.gray)
                        Text(verbatim: "\(serverConfig.host):\(serverConfig.port)")
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundColor(.gray)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    if isLoading {
                        Spacer()
                        ProgressView("Connecting...")
                            .foregroundColor(.white)
                        Spacer()
                    } else if let error = errorMessage {
                        Spacer()
                        VStack(spacing: 16) {
                            Image(systemName: "wifi.exclamationmark")
                                .font(.system(size: 48))
                                .foregroundColor(.red.opacity(0.7))
                            Text(error)
                                .foregroundColor(.red.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            Button("Retry") {
                                loadSessions()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                        }
                        Spacer()
                    } else if sessions.isEmpty {
                        Spacer()
                        VStack(spacing: 16) {
                            Image(systemName: "terminal")
                                .font(.system(size: 48))
                                .foregroundColor(.gray)
                            Text("No active tmux sessions")
                                .foregroundColor(.gray)
                            Text("Start a session with start-claude.sh on your Mac")
                                .font(.caption)
                                .foregroundColor(.gray.opacity(0.7))
                            Button("Refresh") {
                                loadSessions()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                        }
                        Spacer()
                    } else {
                        List(sessions) { session in
                            SessionRow(session: session)
                                .listRowBackground(Color(red: 0.09, green: 0.13, blue: 0.24))
                                .onTapGesture {
                                    selectedSession = session
                                }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Claude Terminal")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        loadSessions()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .fullScreenCover(item: $selectedSession) { session in
                TerminalView(sessionName: session.name, serverConfig: serverConfig)
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheet(config: $serverConfig) {
                    serverConfig.save()
                    loadSessions()
                }
            }
            .onAppear {
                serverConfig = ServerConfig.load()
                loadSessions()
            }
            .onReceive(NotificationCenter.default.publisher(for: .serverConfigDidChange)) { _ in
                serverConfig = ServerConfig.load()
                loadSessions()
            }
        }
    }

    private func loadSessions() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let fetched = try await WebSocketManager.fetchSessions(config: serverConfig)
                await MainActor.run {
                    sessions = fetched
                    isLoading = false

                    // v4: Auto-connect to last session on first load
                    if !hasAttemptedAutoConnect {
                        hasAttemptedAutoConnect = true
                        autoConnectIfPossible()
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Cannot reach server\n\(serverConfig.host):\(serverConfig.port)\n\n\(error.localizedDescription)"
                    isLoading = false
                    hasAttemptedAutoConnect = true
                }
            }
        }
    }

    /// v4: If the last-used session is still active, auto-connect to it.
    private func autoConnectIfPossible() {
        guard let lastSessionName = UserDefaults.standard.string(forKey: "last_session_name"),
              !lastSessionName.isEmpty else { return }

        // Check if the last session still exists in the fetched list
        if let session = sessions.first(where: { $0.name == lastSessionName }) {
            selectedSession = session
        }
    }
}

// MARK: - Session Row

private struct SessionRow: View {
    let session: TmuxSession

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "terminal.fill")
                        .foregroundColor(.green)
                    Text(session.name)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
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
            Image(systemName: "chevron.right")
                .foregroundColor(.gray.opacity(0.5))
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

// MARK: - Settings Sheet

private struct SettingsSheet: View {
    @Binding var config: ServerConfig
    var onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var hostText: String = ""
    @State private var portText: String = ""
    @State private var fontSize: CGFloat = ServerConfig.defaultFontSize
    @State private var selectedTheme: TerminalTheme = .dark

    var body: some View {
        NavigationStack {
            Form {
                Section("Server Connection") {
                    HStack {
                        Text("Host")
                            .frame(width: 50, alignment: .leading)
                        TextField("IP or hostname", text: $hostText)
                            .font(.system(.body, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.numbersAndPunctuation)
                    }
                    HStack {
                        Text("Port")
                            .frame(width: 50, alignment: .leading)
                        TextField("8022", text: $portText)
                            .font(.system(.body, design: .monospaced))
                            .keyboardType(.numberPad)
                    }
                }

                Section("Terminal") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Font Size")
                            Spacer()
                            Text("\(Int(fontSize)) pt")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $fontSize, in: 8...20, step: 1)
                            .tint(.purple)

                        // Preview
                        Text("AaBbCc 012 Hello World")
                            .font(.system(size: fontSize, design: .monospaced))
                            .foregroundColor(.green)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black)
                            .cornerRadius(6)
                    }

                    Picker("Theme", selection: $selectedTheme) {
                        ForEach(TerminalTheme.allCases) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("6.0")
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    Button("Reset to Defaults") {
                        hostText = ServerConfig.defaultHost
                        portText = String(ServerConfig.defaultPort)
                        fontSize = ServerConfig.defaultFontSize
                        selectedTheme = ServerConfig.defaultTheme
                    }
                    .foregroundColor(.orange)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        config.host = hostText.trimmingCharacters(in: .whitespaces)
                        config.port = Int(portText) ?? ServerConfig.defaultPort
                        config.fontSize = fontSize
                        config.theme = selectedTheme
                        onSave()
                        dismiss()
                    }
                }
            }
            .onAppear {
                hostText = config.host
                portText = String(config.port)
                fontSize = config.fontSize
                selectedTheme = config.theme
            }
        }
    }
}

#Preview {
    SessionPickerView()
        .preferredColorScheme(.dark)
}
