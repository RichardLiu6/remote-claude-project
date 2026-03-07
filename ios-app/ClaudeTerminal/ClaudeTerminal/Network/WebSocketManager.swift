import Foundation
import Combine
import UIKit

/// Control frame prefix used by the server protocol.
/// All control frames start with \x01 followed by a type identifier and colon.
private let controlPrefix: Character = "\u{01}"

/// Reason the WebSocket disconnected.
enum DisconnectReason: Equatable {
    case none
    case sessionEnded
    case networkError(String)
    case serverUnreachable
    case maxRetriesExceeded

    var displayText: String {
        switch self {
        case .none: return ""
        case .sessionEnded: return "Session ended"
        case .networkError(let msg): return "Network error: \(msg)"
        case .serverUnreachable: return "Server unreachable"
        case .maxRetriesExceeded: return "Connection lost after max retries"
        }
    }
}

/// Connection state for the UI status indicator.
enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int, maxAttempts: Int)

    var statusText: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .reconnecting(let attempt, let max): return "Reconnecting (\(attempt)/\(max))..."
        }
    }

    var statusColor: String {
        switch self {
        case .connected: return "green"
        case .connecting, .reconnecting: return "yellow"
        case .disconnected: return "red"
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

/// Manages URLSessionWebSocketTask lifecycle, reconnection, and protocol parsing.
///
/// Protocol (matches server.js exactly -- zero server changes):
///   Client -> Server:
///     - Plain text = keyboard input (pty.write)
///     - "\x01resize:{\"cols\":80,\"rows\":24}" = terminal resize
///   Server -> Client:
///     - Plain text = ANSI terminal output (feed to SwiftTerm)
///     - "\x01voice:{...}" = TTS push (intercept, don't feed to terminal)
///     - "\x01notify:{...}" = notification push
final class WebSocketManager: ObservableObject {

    // MARK: - Published state

    @Published var connectionState: ConnectionState = .disconnected
    @Published var disconnectReason: DisconnectReason = .none
    @Published var connectionError: String?

    /// Convenience for backward compatibility.
    var isConnected: Bool { connectionState.isConnected }

    // MARK: - Callbacks

    /// Called when terminal data arrives (ANSI output to feed into SwiftTerm).
    var onTerminalData: ((Data) -> Void)?

    /// Called when a voice control frame arrives.
    var onVoiceEvent: (([String: Any]) -> Void)?

    /// Called when a notification control frame arrives.
    var onNotifyEvent: (([String: Any]) -> Void)?

    /// Called when the session ends (server closed WebSocket for session termination).
    var onSessionEnded: (() -> Void)?

    /// Called when connection state changes (for haptic feedback).
    var onConnectionStateChanged: ((ConnectionState) -> Void)?

    // MARK: - Private

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private let config: ServerConfig
    private var sessionName: String?
    private var isIntentionalDisconnect = false
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 10
    private let baseReconnectDelay: TimeInterval = 1.0
    private var hasReceivedFirstMessage = false
    private var sessionEndedByServer = false

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
        sessionEndedByServer = false
        reconnectAttempts = 0
        hasReceivedFirstMessage = false
        establishConnection()
    }

    /// Gracefully disconnect.
    func disconnect() {
        isIntentionalDisconnect = true
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        updateConnectionState(.disconnected)
    }

    /// Send keyboard input text to the server (plain text -> pty.write).
    func sendInput(_ text: String) {
        guard let task = webSocketTask, connectionState.isConnected else { return }
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

        // Update state to connecting (or reconnecting)
        if reconnectAttempts > 0 {
            updateConnectionState(.reconnecting(attempt: reconnectAttempts, maxAttempts: maxReconnectAttempts))
        } else {
            updateConnectionState(.connecting)
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

        // NOTE: isConnected is NOT set here. It will be set to true
        // only after the first message is successfully received,
        // confirming the WebSocket handshake is complete.
        hasReceivedFirstMessage = false

        print("[ws] connecting to \(urlString)")
        receiveMessage()
        startPing()
    }

    private func updateConnectionState(_ newState: ConnectionState) {
        DispatchQueue.main.async {
            let oldState = self.connectionState
            self.connectionState = newState

            // Clear error on successful connection
            if case .connected = newState {
                self.connectionError = nil
                self.disconnectReason = .none
                self.reconnectAttempts = 0
            }

            // Notify listener of state change (for haptics)
            if oldState != newState {
                self.onConnectionStateChanged?(newState)
            }
        }
    }

    // MARK: - Message receiving

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                // First message received = connection confirmed
                if !self.hasReceivedFirstMessage {
                    self.hasReceivedFirstMessage = true
                    self.updateConnectionState(.connected)
                }
                self.handleMessage(message)
                // Continue listening
                self.receiveMessage()

            case .failure(let error):
                print("[ws] receive error: \(error.localizedDescription)")
                self.handleDisconnect(error: error)
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            parseTextMessage(text)

        case .data(let data):
            // Binary data -- treat as terminal output
            onTerminalData?(data)

        @unknown default:
            break
        }
    }

    /// Parse a text message. Check for control frame prefix \x01.
    private func parseTextMessage(_ text: String) {
        guard let first = text.first, first == controlPrefix else {
            // Plain text -- terminal ANSI output
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
            let jsonStr = String(content.dropFirst(7))
            if let data = jsonStr.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                onNotifyEvent?(json)
            }
        } else {
            // Unknown control frame -- ignore
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

    private func handleDisconnect(error: Error? = nil) {
        updateConnectionState(.disconnected)

        guard !isIntentionalDisconnect else { return }

        // Check if this is a session-ended close (server closed the socket cleanly).
        // When tmux session ends, server.js closes the WebSocket with code 1000 or 1001.
        // URLSessionWebSocketTask reports this as a URLError with code .unknown or specific
        // WebSocket close codes.
        if let urlError = error as? URLError {
            let code = urlError.code
            if code == .cancelled || code == .unknown {
                // Heuristic: if we were connected and got a clean close, the session likely ended
                if hasReceivedFirstMessage && !sessionEndedByServer {
                    sessionEndedByServer = true
                    DispatchQueue.main.async {
                        self.disconnectReason = .sessionEnded
                        self.onSessionEnded?()
                    }
                    return // Don't auto-reconnect for ended sessions
                }
            }
        }

        // Also detect POSIXError for broken pipe / connection reset
        let nsError = error as NSError?
        let errorDomain = nsError?.domain ?? ""
        let errorCode = nsError?.code ?? 0

        // ECONNREFUSED (61), ECONNRESET (54), EPIPE (32)
        if errorDomain == NSPOSIXErrorDomain && (errorCode == 61 || errorCode == 54 || errorCode == 32) {
            if hasReceivedFirstMessage {
                // Was connected, then lost connection - could be session end
                sessionEndedByServer = true
                DispatchQueue.main.async {
                    self.disconnectReason = .sessionEnded
                    self.onSessionEnded?()
                }
                return
            } else {
                DispatchQueue.main.async {
                    self.disconnectReason = .serverUnreachable
                }
            }
        }

        reconnectAttempts += 1
        if reconnectAttempts > maxReconnectAttempts {
            DispatchQueue.main.async {
                self.disconnectReason = .maxRetriesExceeded
                self.connectionError = "Connection lost after \(self.maxReconnectAttempts) retries"
            }
            return
        }

        // Exponential backoff with jitter: base * 2^attempt + random(0..1)
        let delay = baseReconnectDelay * pow(2.0, Double(min(reconnectAttempts - 1, 5)))
            + Double.random(in: 0...1)

        print("[ws] reconnecting in \(String(format: "%.1f", delay))s (attempt \(reconnectAttempts)/\(maxReconnectAttempts))")

        let reason = error?.localizedDescription ?? "Unknown"
        DispatchQueue.main.async {
            self.disconnectReason = .networkError(reason)
            self.connectionError = "Reconnecting... (\(self.reconnectAttempts)/\(self.maxReconnectAttempts))"
        }

        updateConnectionState(.reconnecting(attempt: reconnectAttempts, maxAttempts: maxReconnectAttempts))

        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, !self.isIntentionalDisconnect else { return }
            self.hasReceivedFirstMessage = false
            self.establishConnection()
        }
    }

    /// Manually trigger a reconnection attempt (e.g., from a "Reconnect" button).
    func reconnect() {
        guard let _ = sessionName else { return }
        isIntentionalDisconnect = false
        sessionEndedByServer = false
        reconnectAttempts = 0
        hasReceivedFirstMessage = false

        // Cancel existing task
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil

        establishConnection()
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
