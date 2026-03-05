#!/bin/bash
# ── pre-edit-protect-critical.sh ─────────────────────
# Event:      PreToolUse (sync, 3000ms)
# Activates:  Edit on start-claude.sh / server.js
# Registered: .claude/settings.local.json
# Purpose:    编辑关键文件时输出 gotcha 提醒，避免误改
# Cost:       Zero LLM calls, instant
# ─────────────────────────────────────────────────────

INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('tool_input', {}).get('file_path', ''))
" 2>/dev/null)

case "$FILE_PATH" in
  *start-claude.sh)
    echo "start-claude.sh gotchas: (1) ~/start-claude.sh is a symlink (2) OAuth token from ~/.claude-oauth-token (3) nohup double-subshell fd redirect required for iOS Shortcuts SSH"
    ;;
  *server.js)
    echo "server.js gotchas: (1) tmux path hardcoded /opt/homebrew/bin/tmux (node-pty no PATH) (2) LANG/LC_ALL must be explicit (CJK renders as underscores otherwise) (3) mouse off per-pane logic required"
    ;;
esac
