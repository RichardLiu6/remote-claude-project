# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Web-based terminal for remotely controlling Claude Code sessions via tmux. Designed for mobile access over Tailscale.

## Architecture

```
Phone Browser (http://Tailscale-IP:8022)
  ├── GET /              → xterm.js frontend (session picker + terminal)
  ├── GET /api/sessions  → list tmux sessions (JSON)
  ├── POST /voice-event  → reserved for voice push (C1 Hook)
  └── WS  /ws?session=X  → node-pty spawns `tmux attach -t X`
```

**Stack**: Express + ws (WebSocket) + node-pty on backend; xterm.js via CDN on frontend. Single-file frontend (`public/index.html`).

## Commands

```bash
node server.js           # Start server on port 8022
npm install              # Install deps (express, ws, node-pty)
```

No build step. No tests. No bundler.

## Key Design Decisions

- **node-pty uses absolute tmux path** `/opt/homebrew/bin/tmux` (node-pty doesn't inherit shell PATH)
- **Port 8022** (avoids conflict with dev servers on 3000)
- **Mobile input**: xterm `disableStdin: true` on mobile; uses bottom input bar with three-layer event handling (keydown → beforeinput → input) for IME + Android keyCode 229 compatibility
- **On-demand lifecycle**: `~/start-claude.sh` starts/stops the web terminal server alongside tmux sessions
- **tmux `window-size smallest`**: dots appear if multiple clients with different sizes connect to the same session — use one device per session

## node-pty Gotcha

The `spawn-helper` binary at `node_modules/node-pty/prebuilds/darwin-arm64/spawn-helper` must have execute permission. If `posix_spawnp failed`, run:
```bash
chmod +x node_modules/node-pty/prebuilds/darwin-arm64/spawn-helper
```
