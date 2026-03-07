# Claude Terminal - iOS Native App

iOS native terminal app for remotely controlling Claude Code tmux sessions. Replaces the Web terminal (xterm.js) to eliminate iOS Safari workarounds.

## Prerequisites

- Xcode 15.0+
- iOS 16.0+ deployment target
- Mac running `server.js` accessible via Tailscale (default: `100.81.22.113:8022`)

## Open in Xcode

```bash
open ios-app/ClaudeTerminal/ClaudeTerminal.xcodeproj
```

Xcode will automatically resolve the SwiftTerm Swift Package dependency on first open. Wait for package resolution to complete before building.

## Build & Run

1. Open the `.xcodeproj` file in Xcode
2. Wait for Swift Package Manager to resolve SwiftTerm dependency
3. Select your iOS device or simulator as the run destination
4. Press Cmd+R to build and run
5. On first launch, the app connects to the default Tailscale IP; tap the gear icon to change

## Project Structure

```
ClaudeTerminal/
  ClaudeTerminalApp.swift          -- App entry point (SwiftUI)
  Views/
    SessionPickerView.swift        -- Landing screen: lists tmux sessions from GET /api/sessions
    TerminalView.swift             -- SwiftTerm terminal + WebSocket bridge (UIViewRepresentable)
    InputAccessoryBar.swift        -- Quick-key bar: Tab / ^C / Esc / Up / Down / ^D / ^Z / ^L
  Network/
    WebSocketManager.swift         -- URLSessionWebSocketTask with reconnection + protocol parsing
  Models/
    ServerConfig.swift             -- Server host/port config with UserDefaults persistence
    SessionModel.swift             -- TmuxSession Codable model
  Assets.xcassets/                 -- App icon, accent color
  Preview Content/                 -- SwiftUI preview assets
```

## WebSocket Protocol (unchanged from server.js)

The app uses the exact same protocol as the Web terminal. **server.js requires zero modifications.**

### Client -> Server
- Plain text = keyboard input (`pty.write`)
- `\x01resize:{"cols":80,"rows":24}` = terminal resize
- `\x01scroll:up:N` / `\x01scroll:down:N` / `\x01scroll:exit` = scroll control

### Server -> Client
- Plain text = ANSI terminal output (fed to SwiftTerm)
- `\x01voice:{...}` = TTS push (intercepted, not sent to terminal)
- `\x01notify:{...}` = notification push

## Phase 1 MVP Scope

- [x] SwiftUI app with dark theme
- [x] Session picker (GET /api/sessions)
- [x] SwiftTerm terminal rendering (ANSI colors, cursor, scroll)
- [x] WebSocket connection via URLSessionWebSocketTask
- [x] Keyboard input forwarding
- [x] Terminal resize events
- [x] Reconnection with exponential backoff (max 10 retries)
- [x] Quick-key bar (Tab, ^C, Esc, arrows, ^D, ^Z, ^L)
- [x] Server address configuration (Settings sheet with persistence)

## Signing (for personal device)

For development, use "Automatically manage signing" in Xcode with your free Apple ID. The app will be valid for 7 days and needs re-signing after expiry. For permanent use, enroll in the Apple Developer Program ($99/year).
