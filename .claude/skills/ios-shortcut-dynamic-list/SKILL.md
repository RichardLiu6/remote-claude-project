---
name: ios-shortcut-dynamic-list
description: |
  Pattern for making iOS Shortcuts dynamically fetch lists from shell scripts
  instead of hardcoding values. Use when: (1) start-claude.sh needs a new project
  added, (2) iOS Shortcut shows stale project list, (3) any SSH-driven Shortcut
  needs a dynamic picker. Solution: script self-parses its case statement and
  outputs newline-separated names, Shortcut uses Split Text + Choose from List.
author: Claude Code
version: 1.0.0
date: 2026-03-07
---

# iOS Shortcut Dynamic List

## Problem
Adding a new project to start-claude.sh requires also updating the iOS Shortcut
manually. Forgetting to sync leads to "Unknown project" errors.

## Context / Trigger Conditions
- Adding/removing projects from start-claude.sh case statement
- iOS Shortcut shows wrong or missing project options
- Any shell script that iOS Shortcuts needs to pick from

## Solution

### Shell side
Add a self-parsing command that extracts options from the script itself:
```bash
if [ "$1" = "projects" ]; then
    grep -E '^\s+\S+\)\s+DIR=' "$0" | sed 's/).*//' | sed 's/^ *//'
    exit 0
fi
```

### iOS Shortcut side
1. SSH -> `~/start-claude.sh projects` (get newline-separated list)
2. Split Text by New Lines
3. Choose from List (input = Split Text result, NOT Shell Script Result)
4. SSH -> `~/start-claude.sh [Chosen Item]`

### For batch operations (kill-pick)
```bash
if [ "$1" = "kill-pick" ]; then
    IFS=',' read -ra SESSIONS <<< "$2"
    for sess in "${SESSIONS[@]}"; do
        tmux send-keys -t "$sess" "/exit" Enter
    done
    sleep 3
    for sess in "${SESSIONS[@]}"; do
        tmux kill-session -t "$sess" 2>/dev/null && echo "Closed: $sess"
    done
    exit 0
fi
```
Shortcut: Choose (multi-select) -> Combine Text (comma) -> SSH kill-pick

## Verification
- `~/start-claude.sh projects` outputs one name per line
- Adding a new case branch automatically appears in Shortcut picker

## Notes
- iOS Shortcuts SSH may return \r\n; Split by New Lines handles both
- Choose from List input MUST be the Split result, not raw SSH output
- Use English-only project names to avoid SSH encoding issues
