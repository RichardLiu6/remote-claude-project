# Touch Selection Redesign

## Goal
Replace the current overlay-based Select mode with in-place long-press + drag selection on the xterm.js canvas. Auto-copy on touchend. No mode switching, no overlay.

## Current Problems
- `#select-overlay` completely covers the terminal with a static text snapshot
- Modal experience: must enter/exit Select mode
- Text formatting doesn't match canvas (no colors, no cursor)
- Cannot see live terminal output while selecting

## New Design

### Gesture Flow
1. Long-press (500ms) on terminal → haptic feedback → selection starts at that cell
2. Drag without lifting → selection extends from start cell to current cell (xterm.js native highlight)
3. Lift finger → auto-copy to clipboard → "Copied!" toast (2s) → selection clears after 1s

### Touch-to-Cell Mapping
```
function touchToCell(touch) {
  const rect = terminalElement.getBoundingClientRect();
  const cellWidth = rect.width / term.cols;
  const cellHeight = rect.height / term.rows;
  const col = Math.floor((touch.clientX - rect.left) / cellWidth);
  const row = Math.floor((touch.clientY - rect.top) / cellHeight);
  return { row: clamp(row, 0, term.rows-1), col: clamp(col, 0, term.cols-1) };
}
```

### Selection via xterm.js API
- `term.select(startCol, startRow, length)` for highlighting
- `term.getSelection()` for text extraction
- `term.clearSelection()` for cleanup
- Multi-line length = `(endRow - startRow) * term.cols + (endCol - startCol)`

### Scroll vs Select Distinction
- Short swipe (finger moves >5px before 500ms) → scroll (existing behavior, unchanged)
- Long-press (500ms, finger stays within 5px) → enter selecting state
- Once selecting: touchmove extends selection, does NOT scroll

### Code Changes

**Remove:**
- `#select-overlay` div and CSS
- `selectMode` variable and all references
- `showSelectOverlay()` / `hideSelectOverlay()` functions
- "Select" button from quick-bar
- "Done" button's select mode handling
- `autoCopySelection()` (replaced by simpler clipboard write)

**Add:**
- `touchToCell(touch)` function
- `_isSelecting` / `_selStart` state variables
- Modified long-press handler: sets `_isSelecting = true`, records start cell
- Modified touchmove: when `_isSelecting`, compute end cell, call `term.select()`
- Modified touchend: when `_isSelecting`, copy `term.getSelection()`, show toast
- `showCopiedToast()` function — simple absolute-positioned div, fades out after 2s

### Toast UI
- Small "Copied!" badge, centered horizontally, near top of terminal
- Semi-transparent dark background, white text, rounded corners
- Appears on successful copy, fades out after 2s
- No DOM overhead when not shown
