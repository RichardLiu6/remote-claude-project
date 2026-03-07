#!/bin/bash
# ── post-edit-swift-build.sh ─────────────────────────
# Event:      PostToolUse (sync, 60000ms)
# Activates:  Edit|Write on .swift files in ios-app/
# Registered: .claude/settings.local.json
# Purpose:    Swift 文件编辑后自动 xcodebuild 编译验证
# Cost:       Zero LLM calls, ~10-30s per build
# ─────────────────────────────────────────────────────

INPUT=$(cat)

FILE_PATH=$(python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('tool_input', {}).get('file_path', ''))
" <<< "$INPUT" 2>/dev/null)

# Only check .swift files under ios-app/
[[ "$FILE_PATH" != *.swift ]] && exit 0
[[ "$FILE_PATH" != *ios-app/* ]] && exit 0
[[ ! -f "$FILE_PATH" ]] && exit 0

# Find the Xcode project directory
PROJECT_DIR="$(dirname "$FILE_PATH")"
while [[ "$PROJECT_DIR" != "/" ]]; do
  if ls "$PROJECT_DIR"/*.xcodeproj 1>/dev/null 2>&1; then
    break
  fi
  PROJECT_DIR="$(dirname "$PROJECT_DIR")"
done

[[ "$PROJECT_DIR" == "/" ]] && exit 0

# Run xcodebuild (quiet mode, simulator target)
cd "$PROJECT_DIR"
BUILD_OUTPUT=$(xcodebuild \
  -project ClaudeTerminal.xcodeproj \
  -scheme ClaudeTerminal \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -quiet \
  build 2>&1)

BUILD_EXIT=$?

if [[ $BUILD_EXIT -ne 0 ]]; then
  # Extract only error lines for concise output
  ERRORS=$(echo "$BUILD_OUTPUT" | grep -E "error:" | head -5)
  echo "Xcode build FAILED after editing $(basename "$FILE_PATH"):"
  echo "$ERRORS"
  exit 1
fi
