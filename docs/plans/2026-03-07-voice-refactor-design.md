# Voice System Refactor Design

Date: 2026-03-07

## Goal

Replace tmux session name with CC session_id as universal identifier. Unify voice toggle to `/voice` skill. Support dual channels: local (afplay) + web (WS broadcast).

## Flag Files

- `~/.claude/voice-local-{cc_session_id}` — Mac local afplay
- `~/.claude/voice-web-{cc_session_id}` — WS broadcast to browser
- `~/.claude/current-session-id` — written by hook on every UserPromptSubmit

## Data Flow

```
/voice command → UserPromptSubmit hook writes session_id → skill reads it → creates flag files
User message   → voice-inject.sh checks flags → injects voice instruction
CC stops       → voice-push.sh checks flags → local? afplay / web? POST server / both
```

## Changes

### 1. voice-inject.sh (UserPromptSubmit hook)
- Extract session_id from stdin JSON, write to ~/.claude/current-session-id
- Check voice-local-{id} or voice-web-{id} exists → inject instruction
- Remove tmux dependency (works in any environment)

### 2. voice-push.sh (Stop hook)
- Extract session_id from stdin JSON
- voice-local-{id} exists → edge-tts + afplay (local playback)
- voice-web-{id} exists → POST /voice-event (existing WS broadcast)
- Both → both

### 3. /voice skill (new)
- Read ~/.claude/current-session-id
- Args: local(l) / web(w) / both(b) / off, default=both
- Create/delete flag files
- Show status + hint available args

### 4. server.js
- Remove /api/voice-toggle, /api/voice-status, voiceFlagPath()
- Keep /voice-event POST + broadcastVoice() (web channel)

### 5. public/index.html
- Remove speaker button and voice-toggle/voice-status fetch
- Keep voicePlayer + WS voice message receiver

## Unchanged
- TTS engine (edge-tts, zh-CN-XiaoxiaoNeural)
- WS broadcast protocol (\x01voice: prefix)
- Frontend audio playback + unlock logic
- settings.json hook registration
