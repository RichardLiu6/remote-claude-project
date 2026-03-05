#!/bin/bash
# ── post-edit-syntax-check.sh ────────────────────────
# Event:      PostToolUse (sync, 5000ms)
# Activates:  Edit|Write on .js files
# Registered: .claude/settings.local.json
# Purpose:    JS 文件编辑后自动 node --check 语法验证
# Cost:       Zero LLM calls, <100ms per check
# ─────────────────────────────────────────────────────

INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('tool_input', {}).get('file_path', ''))
" 2>/dev/null)

# Only check .js files
[[ "$FILE_PATH" != *.js ]] && exit 0
[[ ! -f "$FILE_PATH" ]] && exit 0

# Run syntax check
if ! node --check "$FILE_PATH" 2>&1; then
  echo "Syntax error in $FILE_PATH"
  exit 1
fi
