#!/bin/bash
# =============================================================================
# test-cold-start.sh - iPhone Shortcut Cold-Start Simulation
# =============================================================================
#
# What this tests:
#   Simulates the exact sequence that happens when the iPhone shortcut triggers
#   ~/start-claude.sh for the first time (cold start): no tmux sessions exist,
#   the web terminal server on port 8022 is not running, and everything must
#   spin up from zero.
#
# Why it matters:
#   The iPhone shortcut calls start-claude.sh over SSH. If the script takes
#   longer than ~2 seconds, the Shortcuts app shows a spinner or times out,
#   which breaks the user experience. This test asserts the cold-start path
#   completes within that budget.
#
# What it checks:
#   1. Pre-condition: server on 8022 is stopped after kill-all
#   2. Pre-condition: no tmux sessions remain after kill-all
#   3. Cold start completes in under 2 seconds
#   4. Web terminal server is listening on port 8022
#   5. A tmux session was created with the expected naming pattern
#   6. Cleanup: session and server are properly torn down
#
# Usage:
#   ./tests/test-cold-start.sh
#
# =============================================================================

set -euo pipefail

SCRIPT="$HOME/start-claude.sh"
PORT=8022
PROJECT="实时更新学习Claude"
SESSION_PREFIX="claude-learn-"
MAX_COLD_START_SECONDS=2

# Counters
PASSED=0
FAILED=0
TOTAL=0

# Colors (if terminal supports them)
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
else
    GREEN=''
    RED=''
    YELLOW=''
    NC=''
fi

# --- Helpers ---

check() {
    local description="$1"
    local result="$2"  # 0 = pass, non-zero = fail
    TOTAL=$((TOTAL + 1))
    if [ "$result" -eq 0 ]; then
        PASSED=$((PASSED + 1))
        printf "  ${GREEN}PASS${NC}  %s\n" "$description"
    else
        FAILED=$((FAILED + 1))
        printf "  ${RED}FAIL${NC}  %s\n" "$description"
    fi
}

port_listening() {
    lsof -i :"$PORT" -sTCP:LISTEN &>/dev/null
}

get_test_sessions() {
    tmux list-sessions -F '#{session_name}' 2>/dev/null | grep "^claude-learn-" || true
}

# --- Pre-flight ---

echo ""
echo "========================================"
echo "  Cold-Start Test for start-claude.sh"
echo "========================================"
echo ""

if [ ! -x "$SCRIPT" ]; then
    printf "${RED}ERROR${NC}: %s not found or not executable\n" "$SCRIPT"
    exit 1
fi

# --- Phase 1: Teardown (ensure clean slate) ---

echo "[Phase 1] Teardown - ensure clean slate"

# Kill all existing sessions to simulate cold state
# Use kill-server directly to avoid the 2-second sleep in kill-all
# (kill-all sends /exit + sleeps, which is for graceful CC shutdown)
tmux kill-server 2>/dev/null || true

# Kill any lingering web terminal server
pkill -f "node.*server.js" 2>/dev/null || true
sleep 0.5

# Verify port 8022 is free
if port_listening; then
    check "Port $PORT is free after teardown" 1
    printf "  ${YELLOW}NOTE${NC}: Something else is using port $PORT. Aborting.\n"
    exit 1
else
    check "Port $PORT is free after teardown" 0
fi

# Verify no tmux sessions
SESSION_COUNT=$(tmux list-sessions 2>/dev/null | wc -l | tr -d ' ') || SESSION_COUNT=0
check "No tmux sessions after teardown" "$( [ "${SESSION_COUNT:-0}" -eq 0 ] && echo 0 || echo 1 )"

echo ""

# --- Phase 2: Cold Start ---

echo "[Phase 2] Cold start - run start-claude.sh from zero"

SECONDS=0
OUTPUT=$("$SCRIPT" "$PROJECT" 2>&1)
ELAPSED=$SECONDS

echo "  Output: $OUTPUT"
printf "  Elapsed: %d second(s)\n" "$ELAPSED"

check "Cold start completed in under ${MAX_COLD_START_SECONDS}s (took ${ELAPSED}s)" \
    "$( [ "$ELAPSED" -lt "$MAX_COLD_START_SECONDS" ] && echo 0 || echo 1 )"

# Give server a moment to bind the port
sleep 0.5

# Verify server is listening
if port_listening; then
    check "Web terminal server is listening on port $PORT" 0
else
    check "Web terminal server is listening on port $PORT" 1
fi

# Verify tmux session was created with expected prefix
CREATED_SESSIONS=$(get_test_sessions)
if [ -n "$CREATED_SESSIONS" ]; then
    check "Tmux session created with prefix '${SESSION_PREFIX}'" 0
    printf "  Session(s): %s\n" "$CREATED_SESSIONS"
else
    check "Tmux session created with prefix '${SESSION_PREFIX}'" 1
fi

echo ""

# --- Phase 3: Cleanup ---

echo "[Phase 3] Cleanup"

# Kill the test session(s)
for sess in $CREATED_SESSIONS; do
    tmux kill-session -t "$sess" 2>/dev/null || true
done

# Stop web terminal if no sessions remain
REMAINING=$(tmux list-sessions 2>/dev/null | wc -l | tr -d ' ') || REMAINING=0
if [ "${REMAINING:-0}" -eq 0 ]; then
    pkill -f "node.*server.js" 2>/dev/null || true
    sleep 0.3
fi

# Verify cleanup
REMAINING_SESSIONS=$(get_test_sessions)
if [ -z "$REMAINING_SESSIONS" ]; then
    check "Test session(s) cleaned up" 0
else
    check "Test session(s) cleaned up" 1
fi

echo ""

# --- Summary ---

echo "========================================"
printf "  Results: ${GREEN}%d passed${NC}, ${RED}%d failed${NC}, %d total\n" "$PASSED" "$FAILED" "$TOTAL"
echo "========================================"
echo ""

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi

exit 0
