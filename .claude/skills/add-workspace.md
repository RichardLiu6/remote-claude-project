---
name: add-workspace
description: Add a new project workspace to start-claude.sh and iPhone Shortcuts so it can be remotely launched. Use when the user wants to add a new folder/project to the remote launch system.
---

# Add Workspace to Remote Launch System

## Steps

1. **Read current `start-claude.sh`** to see existing case entries
2. **Ask the user for**:
   - Project folder path (absolute or relative to ~)
   - English alias for tmux session name (e.g., `my-app`)
   - Case label (the name used in iPhone Shortcuts list, e.g., `my-project`)
3. **Add a new case entry** in the `case "$PROJECT" in` block of `start-claude.sh`:
   ```
   case-label)  DIR=~/path/to/project; ALIAS="english-alias" ;;
   ```
4. **Tell the user** to add the case label to their iPhone Shortcuts "Choose from List" action — no other Shortcut changes needed (SSH command, Open URL all stay the same)
5. **If the new project has a CLAUDE.md**, consider adding a Session Startup Rule if there's a key doc that should always be read

## Conventions

- Alias must be English (no Chinese) to avoid SSH encoding issues
- Alias should be short — it becomes the tmux session prefix (e.g., `remote-cc-1430`)
- Case label should match the folder name for clarity
- `start-claude.sh` lives at `~/start-claude.sh` (symlinked from this repo)
