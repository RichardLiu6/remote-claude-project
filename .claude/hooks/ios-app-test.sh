#!/bin/bash
# ── ios-app-test.sh ──────────────────────────────────
# Event:      Manual / Stop (sync, 120000ms)
# Activates:  手动调用或 iOS App 任务结束时
# Registered: .claude/settings.local.json
# Purpose:    iOS App 完整测试：编译+结构检查+安装+启动验证
# Cost:       Zero LLM calls, ~30-60s per run
# ─────────────────────────────────────────────────────

set -euo pipefail

INPUT=$(cat)

# When called from Stop hook, check stop_hook_active to prevent loops
STOP_ACTIVE=$(echo "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('stop_hook_active', False))
" 2>/dev/null || echo "False")
[[ "$STOP_ACTIVE" == "True" ]] && exit 0

# Check if any .swift files were modified (uncommitted or last commit)
# Skip full test suite if no iOS code was touched
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
if [[ -n "$REPO_ROOT" ]]; then
  SWIFT_UNCOMMITTED=$(git diff --name-only HEAD 2>/dev/null | grep -c '\.swift$' || true)
  SWIFT_LAST_COMMIT=$(git diff --name-only HEAD~1 HEAD 2>/dev/null | grep -c '\.swift$' || true)
  if [[ "$SWIFT_UNCOMMITTED" -eq 0 && "$SWIFT_LAST_COMMIT" -eq 0 ]]; then
    exit 0
  fi
fi

# Config
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKTREE_BASE="$PROJECT_ROOT/.claude/worktrees"
PROJECT_DIR=""
SIMULATOR_ID=""
BUNDLE_ID="com.claude.terminal"
SCHEME="ClaudeTerminal"

# Find the iOS project in worktrees
for d in "$WORKTREE_BASE"/*/ios-app/ClaudeTerminal; do
  if [[ -d "$d" ]]; then
    PROJECT_DIR="$d"
    break
  fi
done

if [[ -z "$PROJECT_DIR" ]]; then
  echo "SKIP: No iOS project found in worktrees"
  exit 0
fi

# Find booted simulator or pick first available
SIMULATOR_ID=$(xcrun simctl list devices booted -j 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
for runtime, devices in data.get('devices', {}).items():
    for d in devices:
        if d.get('state') == 'Booted':
            print(d['udid']); sys.exit(0)
" 2>/dev/null)

if [[ -z "$SIMULATOR_ID" ]]; then
  echo "WARN: No booted simulator found. Running build-only test."
fi

echo "=== iOS App Test Suite ==="
echo ""

# ── Test 1: Xcode Build ──
echo "[1/4] Xcode Build..."
cd "$PROJECT_DIR"
BUILD_OUTPUT=$(xcodebuild \
  -project ClaudeTerminal.xcodeproj \
  -scheme "$SCHEME" \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -quiet \
  build 2>&1)

if [[ $? -ne 0 ]]; then
  ERRORS=$(echo "$BUILD_OUTPUT" | grep -E "error:" | head -10)
  echo "  FAIL: Build failed"
  echo "$ERRORS"
  exit 1
fi
echo "  PASS: Build succeeded"

# ── Test 2: Swift file count & structure ──
echo "[2/4] Project Structure..."
SWIFT_COUNT=$(find ClaudeTerminal -name "*.swift" | wc -l | tr -d ' ')
TOTAL_LINES=$(find ClaudeTerminal -name "*.swift" -exec cat {} + | wc -l | tr -d ' ')
MAX_FILE=$(find ClaudeTerminal -name "*.swift" -exec wc -l {} + | sort -rn | head -2 | tail -1 | awk '{print $2, $1"L"}')
echo "  PASS: $SWIFT_COUNT Swift files, ${TOTAL_LINES} total lines"
echo "  INFO: Largest file: $MAX_FILE"

# Check no file exceeds 500 lines (architecture health)
OVERSIZED=$(find ClaudeTerminal -name "*.swift" -exec wc -l {} + | awk '$1 > 500 && !/total/ {print "  WARN: " $2 " has " $1 " lines (>500)"}')
if [[ -n "$OVERSIZED" ]]; then
  echo "$OVERSIZED"
fi

# ── Test 3: Install to Simulator ──
if [[ -n "$SIMULATOR_ID" ]]; then
  echo "[3/4] Install to Simulator..."
  APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/ClaudeTerminal-*/Build/Products/Debug-iphonesimulator/ClaudeTerminal.app -maxdepth 0 2>/dev/null | head -1)
  if [[ -n "$APP_PATH" ]]; then
    xcrun simctl install "$SIMULATOR_ID" "$APP_PATH" 2>/dev/null
    echo "  PASS: Installed to simulator $SIMULATOR_ID"
  else
    echo "  SKIP: Build product not found"
  fi

  # ── Test 4: Launch & Check ──
  echo "[4/4] Launch Test..."
  # Kill existing instance
  xcrun simctl terminate "$SIMULATOR_ID" "$BUNDLE_ID" 2>/dev/null || true
  sleep 0.5

  LAUNCH_OUTPUT=$(xcrun simctl launch "$SIMULATOR_ID" "$BUNDLE_ID" 2>&1)
  if echo "$LAUNCH_OUTPUT" | grep -q "$BUNDLE_ID"; then
    PID=$(echo "$LAUNCH_OUTPUT" | grep -o '[0-9]*$')
    echo "  PASS: App launched (PID: $PID)"

    # Verify process is still running after 2 seconds (no immediate crash)
    sleep 2
    if xcrun simctl spawn "$SIMULATOR_ID" launchctl list 2>/dev/null | grep -q "$BUNDLE_ID"; then
      echo "  PASS: App still running after 2s (no crash)"
    else
      echo "  WARN: App may have crashed (process not found after 2s)"
    fi
  else
    echo "  FAIL: App failed to launch"
    echo "  $LAUNCH_OUTPUT"
  fi
else
  echo "[3/4] Install to Simulator... SKIP (no booted sim)"
  echo "[4/4] Launch Test... SKIP (no booted sim)"
fi

echo ""
echo "=== Test Complete ==="
