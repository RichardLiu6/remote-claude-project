# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Web-based terminal for remotely controlling Claude Code sessions via tmux. Designed for mobile access over Tailscale.

## Architecture

```
Phone Browser (http://Tailscale-IP:8022)
  ├── GET /              → xterm.js frontend (session picker + terminal)
  ├── GET /api/sessions  → list tmux sessions (JSON)
  ├── POST /voice-event  → Edge TTS voice push (C1 Hook)
  ├── GET /api/voice-status?session=X  → per-session voice status
  ├── POST /api/voice-toggle           → per-session voice on/off
  └── WS  /ws?session=X  → node-pty spawns `tmux attach -t X`
```

**Stack**: Express + ws (WebSocket) + node-pty on backend; xterm.js via CDN on frontend. Single-file frontend (`public/index.html`).

## Commands

```bash
node server.js           # Start server on port 8022
npm install              # Install deps (express, ws, node-pty)
bash tests/test-cold-start.sh  # Test cold-start scenario (kills existing sessions)
```

No build step. No bundler. `start-claude.sh` is symlinked: `~/start-claude.sh` → `./start-claude.sh`.

## Key Design Decisions

- **node-pty uses absolute tmux path** `/opt/homebrew/bin/tmux` (node-pty doesn't inherit shell PATH)
- **Port 8022** (avoids conflict with dev servers on 3000)
- **On-demand lifecycle**: `~/start-claude.sh` starts/stops the web terminal server alongside tmux sessions
- **tmux mouse off per-pane**: server.js runs `tmux set-option -t session -p mouse off` on connect so xterm.js handles selection/scroll natively (tmux `mouse on` hijacks mouse events)
- **tmux `window-size smallest`**: dots appear if multiple clients with different sizes connect — use one device per session

## Mobile Input System (v2)

- xterm `disableStdin: true` on mobile; transparent off-screen textarea captures keyboard input
- Floating quick-bar above keyboard via visualViewport API; uses `mousedown` preventDefault (not `touchstart`) to keep keyboard open without blocking horizontal scroll
  - Quick-bar keys: Enter, Tab, S-Tab, arrows, ^C, ^D, ^Z, ^A, ^E, ^L, ^R, Esc, /
- **InputController class** with 4-state machine (IDLE/COMPOSING/BUFFERING/FLUSHING):
  - All input (English, Chinese, autocomplete, soft-keyboard Backspace) goes through 150ms debounce
  - On debounce expiry, `_flush()` diffs `snapshot` vs `textarea.value`, sends minimal backspaces + new text
  - `keydown`: Ctrl+key sends control char directly; special keys (Enter/Tab/Esc/arrows) flush buffer then send immediately; physical Backspace sends immediately
  - `beforeinput`: soft-keyboard Enter sends `\r` (non-composing) or blocks (during IME); Delete forward sends `\x1b[3~`
  - `compositionstart`: pauses debounce; `compositionend`: resumes debounce (diff handles incremental send)
  - `destroy()` method aborts all listeners via AbortController -- no event listener leaks on session switch
  - textarea has `inputmode="text"` and `autocorrect="off" autocapitalize="off"` attributes
- **v2 changes from v1**: soft Enter sends `\r` (was blocked), Tab/Enter reset snapshot, Ctrl+key support, AbortController cleanup, quick-bar expanded with modifier keys
- **In-place text selection**: long-press (500ms) + drag to select text directly on xterm.js canvas via `term.select()` API. Auto-copies to clipboard on touchend with "Copied!" toast. No overlay, no mode switching
- **Dynamic font sizing**: after `fitAddon.fit()`, if `term.cols < 70`, fontSize auto-reduces (14->10) to fit config screens. Mobile padding reduced to 2px
## Session Startup Rule

Every session in this project MUST begin by reading `docs/remote-claude-setup-guide.md` to understand the current state of the remote workflow, and update it when changes are made to architecture, scripts, or design decisions.

## Authentication

`start-claude.sh` 从 `~/.claude-oauth-token` 读取 OAuth token 并 export 为 `CLAUDE_CODE_OAUTH_TOKEN`，供 Claude Code 无头认证。Token 过期后只需更新该文件内容，新 session 自动生效。

## Gotchas

**node-pty spawn-helper**: The binary at `node_modules/node-pty/prebuilds/darwin-arm64/spawn-helper` must have execute permission. If `posix_spawnp failed`:
```bash
chmod +x node_modules/node-pty/prebuilds/darwin-arm64/spawn-helper
```

**CJK rendering**: node-pty env must include `LANG` and `LC_ALL` (nohup-started processes lose locale). Both `start-claude.sh` (`export LANG`) and `server.js` (node-pty env option) set these explicitly. Without them, Chinese characters render as underscores.

**SSH cold-start**: `start_web_terminal()` in start-claude.sh uses double-subshell with full fd redirect `(cd ... && nohup node server.js </dev/null >/dev/null 2>&1 &) </dev/null >/dev/null 2>&1` — required because iOS Shortcuts SSH tracks child process file descriptors and hangs otherwise.

## Second Brain

项目记忆：`second-brain/TODO.md`（活跃任务）、`DONE.md`（归档）、`long-term.md`（随记索引）。详情放 `docs/`。用 `/sb` 查看 dashboard。
