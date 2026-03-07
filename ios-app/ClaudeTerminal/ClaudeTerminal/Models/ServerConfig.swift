import Foundation

/// Terminal theme options.
enum TerminalTheme: String, CaseIterable, Identifiable {
    case dark = "Dark"
    case light = "Light"
    case solarized = "Solarized"

    var id: String { rawValue }
}

/// Server connection and app configuration.
/// Default points to Tailscale IP; can be changed at runtime via Settings.
struct ServerConfig {
    /// Default Tailscale IP for the Mac running server.js
    static let defaultHost = "100.81.22.113"
    static let defaultPort = 8022
    static let defaultFontSize: CGFloat = 12
    static let defaultTheme: TerminalTheme = .dark

    var host: String
    var port: Int
    var fontSize: CGFloat
    var theme: TerminalTheme

    var baseURL: String {
        "http://\(host):\(port)"
    }

    var wsURL: String {
        "ws://\(host):\(port)"
    }

    init(
        host: String = ServerConfig.defaultHost,
        port: Int = ServerConfig.defaultPort,
        fontSize: CGFloat = ServerConfig.defaultFontSize,
        theme: TerminalTheme = ServerConfig.defaultTheme
    ) {
        self.host = host
        self.port = port
        self.fontSize = fontSize
        self.theme = theme
    }

    // MARK: - Persistence

    private static let hostKey = "server_host"
    private static let portKey = "server_port"
    private static let fontSizeKey = "terminal_font_size"
    private static let themeKey = "terminal_theme"

    /// Load saved config from UserDefaults, or return defaults.
    static func load() -> ServerConfig {
        let defaults = UserDefaults.standard
        let host = defaults.string(forKey: hostKey) ?? defaultHost
        let port = defaults.integer(forKey: portKey)
        let fontSize = defaults.double(forKey: fontSizeKey)
        let themeRaw = defaults.string(forKey: themeKey) ?? defaultTheme.rawValue
        let theme = TerminalTheme(rawValue: themeRaw) ?? defaultTheme

        return ServerConfig(
            host: host,
            port: port > 0 ? port : defaultPort,
            fontSize: fontSize > 0 ? CGFloat(fontSize) : defaultFontSize,
            theme: theme
        )
    }

    /// Save current config to UserDefaults.
    func save() {
        let defaults = UserDefaults.standard
        defaults.set(host, forKey: ServerConfig.hostKey)
        defaults.set(port, forKey: ServerConfig.portKey)
        defaults.set(Double(fontSize), forKey: ServerConfig.fontSizeKey)
        defaults.set(theme.rawValue, forKey: ServerConfig.themeKey)
    }
}
