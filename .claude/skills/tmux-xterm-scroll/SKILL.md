---
name: tmux-xterm-scroll
description: |
  Fix mobile scroll in xterm.js + tmux terminals. Use when: (1) term.scrollLines() does nothing
  on mobile, (2) xterm.js viewportY is always 0 and buffer.length equals visible rows,
  (3) touch scroll handlers fire but terminal doesn't scroll, (4) building a web terminal
  connected to tmux via node-pty. Root cause: tmux manages its own scrollback buffer and
  only sends screen redraws to xterm.js, so xterm.js scrollback is always empty.
author: Claude Code
version: 1.0.0
date: 2026-03-07
---

# tmux + xterm.js Scroll Architecture

## Problem

When xterm.js connects to tmux (via node-pty WebSocket), mobile touch scroll does nothing.
`term.scrollLines()` is called but the terminal doesn't move. This affects any web terminal
that uses xterm.js as a frontend for tmux sessions.

## Context / Trigger Conditions

- `term.buffer.active.viewportY` is always 0
- `term.buffer.active.length` equals the visible row count (e.g., 24 or 60), not the full history
- Touch event handlers fire correctly (verified via debug indicators)
- `term.scrollLines(N)` executes without error but has no visible effect
- Terminal is connected to tmux via `node-pty spawn('tmux', ['attach', '-t', session])`
- `scrollback: 5000` is set but the buffer never fills

## Root Cause

**tmux is a full-screen application that manages its own scrollback buffer.** It sends escape
sequences to redraw the entire visible screen on every update. From xterm.js's perspective,
there is never any content that "scrolls off the top" — tmux always redraws in-place.

Therefore xterm.js's scrollback buffer stays permanently empty. `term.scrollLines()` correctly
reports "nothing to scroll" because, from its perspective, there isn't.

This is NOT a bug in xterm.js or in touch event handling. It's an architectural mismatch:
xterm.js thinks it's a simple terminal display, but the actual scroll history lives in tmux.

## Diagnostic

Add this to confirm:
```javascript
// If these values match visible rows, the buffer is empty
console.log('viewportY:', term.buffer.active.viewportY);  // Always 0
console.log('length:', term.buffer.active.length);          // = term.rows
console.log('baseY:', term.buffer.active.baseY);            // Always 0
```

## Solution

**Do NOT use `term.scrollLines()`.** Instead, send scroll commands to tmux.

### Option A: WebSocket control protocol (recommended)

1. Define a control message prefix (e.g., `\x01scroll:`)
2. Frontend translates touch gestures into scroll commands
3. Server parses control messages and runs tmux commands

**Frontend (index.html):**
```javascript
// Instead of term.scrollLines(n):
const dir = n > 0 ? 'up' : 'down';
wsSend('\x01scroll:' + dir + ':' + Math.abs(n));

// Tap to exit scroll mode:
wsSend('\x01scroll:exit');
```

**Server (server.js):**
```javascript
if (str.startsWith('\x01scroll:')) {
  const parts = str.slice(8).split(':');
  const tmux = '/opt/homebrew/bin/tmux';
  if (parts[0] === 'exit') {
    execSync(`${tmux} send-keys -t "${session}" -X cancel 2>/dev/null`);
  } else {
    const dir = parts[0] === 'up' ? 'scroll-up' : 'scroll-down';
    const n = Math.min(parseInt(parts[1]) || 1, 50);
    // copy-mode is idempotent
    execSync(`${tmux} copy-mode -t "${session}" 2>/dev/null; \
              ${tmux} send-keys -t "${session}" -X -N ${n} ${dir} 2>/dev/null`);
  }
  return;
}
```

### Option B: Send keystrokes through pty

Send `\x02[` (Ctrl-b + [) to enter copy-mode, arrow keys to scroll, `q` to exit.
Simpler but riskier (stray keystrokes can reach the app if state tracking is wrong).

## Touch Scroll Physics (iOS-native feel)

When implementing the touch-to-scroll translation:

- **Non-linear acceleration**: `pow(abs(px) / 6, 1.6)` — small swipe = 1 line, fast swipe = 30+ lines
- **Momentum decay**: 0.95 per frame (Apple standard), NOT 0.90 (too abrupt)
- **Throttle**: 40-50ms between server sends to avoid overwhelming tmux
- **Direction**: iOS natural scroll = invert deltaY (finger up → scroll-down)

## Verification

After implementing:
1. Swipe on mobile — terminal content should change (tmux redraws)
2. You'll see tmux copy-mode indicator (line position) at top-right
3. Tap to exit copy-mode — terminal returns to live output
4. Keyboard input works normally after exiting copy-mode

## Notes

- `tmux copy-mode -t session` is idempotent — safe to call on every scroll event
- `tmux send-keys -X -N 5 scroll-up` scrolls 5 lines without moving the copy-mode cursor
- `tmux send-keys -X cancel` exits copy-mode cleanly
- Server uses `mouse off` per-pane for xterm.js selection; scroll is handled via protocol instead
- CSS `touch-action: pan-y` can conflict — use `touch-action: none` on xterm elements when JS handles scroll

## Common Misdiagnoses

| Symptom | Wrong conclusion | Actual cause |
|---------|-----------------|--------------|
| viewportY = 0 | "Events not reaching handler" | Buffer is empty (tmux manages history) |
| scrollLines() no effect | "xterm.js bug" | Nothing in xterm.js buffer to scroll |
| touch-action: pan-y no scroll | "CSS conflict" | Browser tries native scroll on non-scrollable canvas |

## See Also

- `mobile-input-debug` skill — IME/keyboard input on mobile
- xterm.js Issue #594: "Support ballistic scrolling via touch"
- xterm.js Issue #5377: "Limited touch support on mobile devices"
