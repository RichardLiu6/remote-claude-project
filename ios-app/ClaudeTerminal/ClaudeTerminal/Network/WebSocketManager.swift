import Foundation
import Combine

/// Control frame prefix used by the server protocol.
/// All control frames start with \x01 followed by a type identifier and colon.
private let controlPrefix: Character = "\u{01}"

/// Manages URLSessionWebSocketTask lifecycle, reconnection, and protocol parsing.
///
/// Protocol (matches server.js exactly — zero server changes):
///   Client -> Server:
///     - Plain text = keyboard input (pty.write)
///     - "\x01resize:{\"cols\":80,\"rows\":24}" = terminal resize
///   Server -> Client:
///     - Plain text = ANSI terminal output (feed to SwiftTerm)
///     - "\x01voice:{...}" = TTS push (intercept, don't feed to terminal)
///     - "\x01notify:{...}" = notification push
final class WebSocketManager: ObservableObject {

    // MARK: - Published state

    @Published var isConnected = false
    @Published var connectionError: String?

    // MARK: - Callbacks

    /// Called when terminal data arrives (ANSI output to feed into SwiftTerm).
    var onTerminalData: ((Data) -> Void)?

    /// Called when a voice control frame arrives.
    var onVoiceEvent: (([String: Any]) -> Void)?

    /// Called when the session ends (server sent "[session ended]").
    var onSessionEnded: (() -> Void)?

    // MARK: - Private

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private let config: ServerConfig
    private var sessionName: String?
    private var isIntentionalDisconnect = false
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 10
    private let baseReconnectDelay: TimeInterval = 1.0

    // MARK: - Init

    init(config: ServerConfig = .load()) {
        self.config = config
    }

    deinit {
        disconnect()
    }

    // MARK: - Public API

    /// Connect to a tmux session via WebSocket.
    func connect(session sessionName: String) {
        self.sessionName = sessionName
        isIntentionalDisconnect = false
        reconnectAttempts = 0
        establishConnection()
    }

    /// Gracefully disconnect.
    func disconnect() {
        isIntentionalDisconnect = true
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        DispatchQueue.main.async {
            self.isConnected = false
        }
    }

    /// Send keyboard input text to the server (plain text -> pty.write).
    func sendInput(_ text: String) {
        guard let task = webSocketTask else { return }
        task.send(.string(text)) { error in
            if let error = error {
                print("[ws] send error: \(error.localizedDescription)")
            }
        }
    }

    /// Send a terminal resize control frame.
    func sendResize(cols: Int, rows: Int) {
        let msg = "\u{01}resize:{\"cols\":\(cols),\"rows\":\(rows)}"
        guard let task = webSocketTask else { return }
        task.send(.string(msg)) { error in
            if let error = error {
                print("[ws] resize send error: \(error.localizedDescription)")
            }
        }
    }

    /// Send a scroll control frame.
    func sendScroll(direction: String, lines: Int = 3) {
        let msg: String
        if direction == "exit" {
            msg = "\u{01}scroll:exit"
        } else {
            msg = "\u{01}scroll:\(direction):\(lines)"
        }
        guard let task = webSocketTask else { return }
        task.send(.string(msg)) { error in
            if let error = error {
                print("[ws] scroll send error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Connection lifecycle

    private func establishConnection() {
        guard let sessionName = sessionName else { return }

        let urlString = "\(config.wsURL)/ws?session=\(sessionName)"
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async {
                self.connectionError = "Invalid URL: \(urlString)"
            }
            return
        }

        // Create a new URLSession for each connection to avoid stale delegate issues
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        // Keep-alive ping interval
        configuration.timeoutIntervalForRequest = 300
        session = URLSession(configuration: configuration)

        let task = session!.webSocketTask(with: url)
        // Set maximum message size to 16MB to handle large terminal output
        task.maximumMessageSize = 16 * 1024 * 1024
        self.webSocketTask = task

        task.resume()

        DispatchQueue.main.async {
            self.isConnected = true
            self.connectionError = nil
            self.reconnectAttempts = 0
        }

        print("[ws] connecting to \(urlString)")
        receiveMessage()
        startPing()
    }

    // MARK: - Message receiving

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                self.handleMessage(message)
                // Continue listening
                self.receiveMessage()

            case .failure(let error):
                print("[ws] receive error: \(error.localizedDescription)")
                self.handleDisconnect()
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            parseTextMessage(text)

        case .data(let data):
            // Binary data — treat as terminal output
            onTerminalData?(data)

        @unknown default:
            break
        }
    }

    /// Parse a text message. Check for control frame prefix \x01.
    private func parseTextMessage(_ text: String) {
        guard let first = text.first, first == controlPrefix else {
            // Plain text — terminal ANSI output
            if let data = text.data(using: .utf8) {
                onTerminalData?(data)
            }
            return
        }

        // Control frame: \x01type:payload
        let content = String(text.dropFirst()) // remove \x01
        if content.hasPrefix("voice:") {
            let jsonStr = String(content.dropFirst(6))
            if let data = jsonStr.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                onVoiceEvent?(json)
            }
        } else if content.hasPrefix("notify:") {
            // Future: handle notification control frames
            let jsonStr = String(content.dropFirst(7))
            print("[ws] notification: \(jsonStr)")
        } else {
            // Unknown control frame — ignore
            print("[ws] unknown control frame: \(content.prefix(20))...")
        }
    }

    // MARK: - Keep-alive ping

    private func startPing() {
        guard let task = webSocketTask else { return }
        // Send ping every 30 seconds to keep the connection alive
        DispatchQueue.global().asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self = self,
                  self.webSocketTask === task else { return }
            task.sendPing { error in
                if let error = error {
                    print("[ws] ping error: \(error.localizedDescription)")
                } else {
                    self.startPing()
                }
            }
        }
    }

    // MARK: - Reconnection

    private func handleDisconnect() {
        DispatchQueue.main.async {
            self.isConnected = false
        }

        guard !isIntentionalDisconnect else { return }

        reconnectAttempts += 1
        if reconnectAttempts > maxReconnectAttempts {
            DispatchQueue.main.async {
                self.connectionError = "Connection lost after \(self.maxReconnectAttempts) retries"
            }
            return
        }

        // Exponential backoff with jitter: base * 2^attempt + random(0..1)
        let delay = baseReconnectDelay * pow(2.0, Double(min(reconnectAttempts - 1, 5)))
            + Double.random(in: 0...1)

        print("[ws] reconnecting in \(String(format: "%.1f", delay))s (attempt \(reconnectAttempts)/\(maxReconnectAttempts))")

        DispatchQueue.main.async {
            self.connectionError = "Reconnecting... (\(self.reconnectAttempts)/\(self.maxReconnectAttempts))"
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, !self.isIntentionalDisconnect else { return }
            self.establishConnection()
        }
    }
}

// MARK: - Session API

extension WebSocketManager {
    /// Fetch tmux sessions from the REST API.
    static func fetchSessions(config: ServerConfig = .load()) async throws -> [TmuxSession] {
        let url = URL(string: "\(config.baseURL)/api/sessions")!
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode([TmuxSession].self, from: data)
    }
}
