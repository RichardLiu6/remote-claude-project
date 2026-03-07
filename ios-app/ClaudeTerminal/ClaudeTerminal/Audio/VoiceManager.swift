import Foundation
import AVFoundation
import Combine

/// Manages TTS voice playback for the Claude Terminal.
///
/// Receives voice events from WebSocket control frames (\x01voice:{"url":"...","text":"..."}),
/// downloads the mp3 file from the server, and plays it via AVAudioPlayer.
///
/// Also manages the voice toggle state via POST /api/voice-toggle and GET /api/voice-status.
final class VoiceManager: NSObject, ObservableObject, AVAudioPlayerDelegate {

    // MARK: - Published state

    @Published var isVoiceEnabled = false
    @Published var isPlaying = false
    @Published var lastSpokenText: String?

    // MARK: - Private

    private var audioPlayer: AVAudioPlayer?
    private var serverConfig: ServerConfig
    private var sessionName: String?
    private var downloadTask: URLSessionDataTask?

    // MARK: - Init

    init(config: ServerConfig) {
        self.serverConfig = config
        super.init()
        configureAudioSession()
    }

    // MARK: - Audio Session

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            DebugLogStore.shared.log("Audio session configured", category: .voice)
        } catch {
            print("[voice] audio session setup error: \(error.localizedDescription)")
            DebugLogStore.shared.log("Audio session error: \(error.localizedDescription)", category: .error)
        }
    }

    // MARK: - Public API

    /// Set the current session name (used for voice toggle API calls).
    func setSession(_ name: String) {
        self.sessionName = name
        fetchVoiceStatus()
    }

    /// Handle a voice event received from WebSocket.
    /// Expected JSON: {"url": "/audio/xxx.mp3", "text": "spoken text"}
    func handleVoiceEvent(_ payload: [String: Any]) {
        guard isVoiceEnabled else { return }
        guard let urlPath = payload["url"] as? String else { return }

        let text = payload["text"] as? String
        DebugLogStore.shared.log("Voice event: \(text?.prefix(50) ?? urlPath)", category: .voice)
        DispatchQueue.main.async {
            self.lastSpokenText = text
        }

        // Build full URL from server config
        let fullURL: String
        if urlPath.hasPrefix("http") {
            fullURL = urlPath
        } else {
            fullURL = "\(serverConfig.baseURL)\(urlPath)"
        }

        guard let url = URL(string: fullURL) else {
            print("[voice] invalid URL: \(fullURL)")
            return
        }

        // Cancel any in-progress download
        downloadTask?.cancel()

        // Download and play
        downloadTask = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                if (error as NSError).code != NSURLErrorCancelled {
                    print("[voice] download error: \(error.localizedDescription)")
                }
                return
            }

            guard let data = data, !data.isEmpty else {
                print("[voice] empty audio data")
                return
            }

            DispatchQueue.main.async {
                self.playAudioData(data)
            }
        }
        downloadTask?.resume()
    }

    /// Toggle voice on/off via POST /api/voice-toggle.
    func toggleVoice() {
        guard let sessionName = sessionName else { return }
        DebugLogStore.shared.log("Voice toggle requested for session: \(sessionName)", category: .voice)

        let urlString = "\(serverConfig.baseURL)/api/voice-toggle"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["session": sessionName]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                print("[voice] toggle error: \(error.localizedDescription)")
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let enabled = json["voice"] as? Bool else {
                return
            }

            DispatchQueue.main.async {
                self?.isVoiceEnabled = enabled
                DebugLogStore.shared.log("Voice toggled: \(enabled ? "ON" : "OFF")", category: .voice)
            }
        }.resume()
    }

    /// Fetch current voice status from GET /api/voice-status.
    func fetchVoiceStatus() {
        guard let sessionName = sessionName else { return }

        let urlString = "\(serverConfig.baseURL)/api/voice-status?session=\(sessionName)"
        guard let url = URL(string: urlString) else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            if let error = error {
                print("[voice] status fetch error: \(error.localizedDescription)")
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let enabled = json["voice"] as? Bool else {
                return
            }

            DispatchQueue.main.async {
                self?.isVoiceEnabled = enabled
            }
        }.resume()
    }

    /// Stop playback and clean up.
    func stop() {
        downloadTask?.cancel()
        audioPlayer?.stop()
        audioPlayer = nil
        DispatchQueue.main.async {
            self.isPlaying = false
        }
    }

    // MARK: - Private playback

    private func playAudioData(_ data: Data) {
        do {
            audioPlayer?.stop()
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            player.prepareToPlay()
            player.play()
            audioPlayer = player
            isPlaying = true
            DebugLogStore.shared.log("Playing audio (\(data.count) bytes)", category: .voice)
        } catch {
            print("[voice] playback error: \(error.localizedDescription)")
            DebugLogStore.shared.log("Playback error: \(error.localizedDescription)", category: .error)
            isPlaying = false
        }
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = false
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("[voice] decode error: \(error?.localizedDescription ?? "unknown")")
        DispatchQueue.main.async {
            self.isPlaying = false
        }
    }
}
