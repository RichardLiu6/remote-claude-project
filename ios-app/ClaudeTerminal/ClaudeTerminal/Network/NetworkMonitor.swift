import Foundation
import Network
import Combine

/// Monitors network path changes using NWPathMonitor.
///
/// v4: Detects WiFi/Cellular transitions and network loss/recovery.
/// Publishes state changes so WebSocketManager can trigger reconnection
/// immediately instead of waiting for the next receive timeout.
final class NetworkMonitor: ObservableObject {

    // MARK: - Published state

    @Published var isConnected: Bool = true
    @Published var connectionType: ConnectionType = .unknown

    enum ConnectionType: String {
        case wifi = "WiFi"
        case cellular = "Cellular"
        case wiredEthernet = "Ethernet"
        case unknown = "Unknown"
    }

    // MARK: - Callbacks

    /// Called when network becomes available after being unavailable.
    var onNetworkRestored: (() -> Void)?

    /// Called when network becomes unavailable.
    var onNetworkLost: (() -> Void)?

    // MARK: - Private

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.claudeterminal.networkmonitor", qos: .utility)
    private var wasConnected: Bool = true

    /// v6: Debounce timer to avoid rapid reconnects on flaky network transitions.
    private var debounceWorkItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 2.0

    // MARK: - Lifecycle

    init() {
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Public API

    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }

            let nowConnected = path.status == .satisfied
            let type = self.classifyPath(path)

            DispatchQueue.main.async {
                self.isConnected = nowConnected
                self.connectionType = type

                // v6: Cancel any pending debounce before scheduling a new one
                self.debounceWorkItem?.cancel()

                // Detect transitions
                if nowConnected && !self.wasConnected {
                    // Network restored — debounce before triggering reconnect
                    print("[network] restored (\(type.rawValue)), debouncing \(self.debounceInterval)s")
                    DebugLogStore.shared.log("Network restored (\(type.rawValue)), debouncing...", category: .network)
                    let work = DispatchWorkItem { [weak self] in
                        self?.onNetworkRestored?()
                    }
                    self.debounceWorkItem = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + self.debounceInterval, execute: work)
                } else if !nowConnected && self.wasConnected {
                    // Network lost — notify immediately (no debounce needed)
                    print("[network] lost")
                    DebugLogStore.shared.log("Network lost", category: .network)
                    self.onNetworkLost?()
                } else if nowConnected && self.wasConnected && type != .unknown {
                    // Network type changed (e.g. WiFi -> Cellular) — debounce
                    print("[network] path changed to \(type.rawValue), debouncing \(self.debounceInterval)s")
                    DebugLogStore.shared.log("Path changed to \(type.rawValue), debouncing...", category: .network)
                    let work = DispatchWorkItem { [weak self] in
                        self?.onNetworkRestored?()
                    }
                    self.debounceWorkItem = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + self.debounceInterval, execute: work)
                }

                self.wasConnected = nowConnected
            }
        }
        monitor.start(queue: queue)
    }

    func stopMonitoring() {
        monitor.cancel()
    }

    // MARK: - Private

    private func classifyPath(_ path: NWPath) -> ConnectionType {
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .wiredEthernet
        } else {
            return .unknown
        }
    }
}
