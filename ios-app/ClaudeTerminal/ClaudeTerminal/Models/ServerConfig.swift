import Foundation

/// Server connection configuration.
/// Default points to Tailscale IP; can be changed at runtime via Settings.
struct ServerConfig {
    /// Default Tailscale IP for the Mac running server.js
    static let defaultHost = "100.81.22.113"
    static let defaultPort = 8022

    var host: String
    var port: Int

    var baseURL: String {
        "http://\(host):\(port)"
    }

    var wsURL: String {
        "ws://\(host):\(port)"
    }

    init(host: String = ServerConfig.defaultHost, port: Int = ServerConfig.defaultPort) {
        self.host = host
        self.port = port
    }

    // MARK: - Persistence

    private static let hostKey = "server_host"
    private static let portKey = "server_port"

    /// Load saved config from UserDefaults, or return defaults.
    static func load() -> ServerConfig {
        let defaults = UserDefaults.standard
        let host = defaults.string(forKey: hostKey) ?? defaultHost
        let port = defaults.integer(forKey: portKey)
        return ServerConfig(
            host: host,
            port: port > 0 ? port : defaultPort
        )
    }

    /// Save current config to UserDefaults.
    func save() {
        let defaults = UserDefaults.standard
        defaults.set(host, forKey: ServerConfig.hostKey)
        defaults.set(port, forKey: ServerConfig.portKey)
    }
}
