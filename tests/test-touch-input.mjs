/**
 * test-touch-input.mjs -- Tests for touch+input cross-scenario interactions
 * on a mobile web terminal.
 *
 * Covers: swipe then type, long-press select then type, fallbackCopy keyboard
 * behavior, typing interrupted by swipe, Chinese IME during swipe.
 *
 * Run: node tests/test-touch-input.mjs
 */

// =====================================================================
// InputControllerSim (simplified state machine simulation)
// =====================================================================
class InputControllerSim {
  constructor() {
    this.snapshot = '';
    this.textareaValue = '';
    this.state = 'IDLE';
    this.bufferTimer = null;
    this.BUFFER_MS = 30;
    this.sent = [];
    this._keydownHandled = false;
    this._lastCompositionEndTs = 0;
    this._COMPOSE_ENTER_GUARD_MS = 300;
  }

  send(data) {
    this.sent.push(data);
  }

  _computeDiff() {
    const prev = this.snapshot;
    const curr = this.textareaValue;
    let commonLen = 0;
    const minLen = Math.min(prev.length, curr.length);
    while (commonLen < minLen && prev[commonLen] === curr[commonLen]) commonLen++;
    return { backspaces: prev.length - commonLen, newText: curr.slice(commonLen) };
  }

  _flush() {
    const { backspaces, newText } = this._computeDiff();
    if (backspaces > 0) this.send('\x7f'.repeat(backspaces));
    if (newText) this.send(newText);
    this.snapshot = this.textareaValue;
    this.state = 'IDLE';
  }

  resetSnapshot() {
    this.snapshot = '';
    this.textareaValue = '';
    if (this.bufferTimer) { clearTimeout(this.bufferTimer); this.bufferTimer = null; }
    this.state = 'IDLE';
  }

  _startBuffer() {
    if (this.bufferTimer) clearTimeout(this.bufferTimer);
    if (this.state !== 'BUFFERING') this.state = 'BUFFERING';
    this.bufferTimer = setTimeout(() => {
      this.bufferTimer = null;
      this.state = 'FLUSHING';
      this._flush();
    }, this.BUFFER_MS);
  }

  typeChar(ch) {
    this.textareaValue += ch;
    this._onInput('insertText');
  }

  _onInput(inputType) {
    if (this.state === 'COMPOSING') return;
    if (this._keydownHandled) { this._keydownHandled = false; return; }
    this._startBuffer();
  }

  compositionStart() {
    if (this.state === 'BUFFERING') {
      clearTimeout(this.bufferTimer); this.bufferTimer = null; this._flush();
    }
    this.state = 'COMPOSING';
  }

  compositionEnd() {
    this._lastCompositionEndTs = Date.now();
    this._startBuffer();
  }

  softEnter() {
    const sinceCompose = Date.now() - this._lastCompositionEndTs;
    if (sinceCompose > this._COMPOSE_ENTER_GUARD_MS) {
      if (this.state === 'BUFFERING') {
        clearTimeout(this.bufferTimer); this.bufferTimer = null; this._flush();
      }
      this.send('\r');
      this.resetSnapshot();
      return true;
    } else {
      this.resetSnapshot();
      return false;
    }
  }

  async waitForFlush() {
    return new Promise(resolve => setTimeout(resolve, this.BUFFER_MS + 20));
  }
}

// =====================================================================
// TouchInputSim (models touch handler state from the app)
// =====================================================================
class TouchInputSim {
  constructor() {
    this.ic = new InputControllerSim();
    this._isSelecting = false;
    this._touchMoved = false;
    this._keyboardOpen = false;
    this._inScrollMode = false;
    this._pointerEvents = '';  // '' = normal, 'none' = blocked
    this._longPressTimer = null;
    this._focusTarget = null;   // tracks whether focus was called
    this._fallbackCopyUsed = false;
    this._hasClipboardAPI = false;
    this.scrollSent = [];
  }

  // --- Touch event handlers (mirror index.html logic) ---

  touchstart() {
    this._touchMoved = false;
    this._isSelecting = false;
    // Safety: restore pointerEvents in case previous selection left it stuck
    this._pointerEvents = '';
    // Cancel any existing long press timer
    if (this._longPressTimer) {
      clearTimeout(this._longPressTimer);
      this._longPressTimer = null;
    }
    // Start new long press timer (only if we are in the terminal area)
    this._longPressTimer = 'pending'; // placeholder for timer ID
  }

  touchmoveScroll(deltaY) {
    // If currently selecting, extend selection instead of scrolling
    if (this._isSelecting) return;

    if (deltaY > 5) {
      this._touchMoved = true;
      // Cancel long press
      if (this._longPressTimer) {
        clearTimeout(this._longPressTimer);
        this._longPressTimer = null;
      }
      this._inScrollMode = true;
      this.scrollSent.push('scroll:' + deltaY);
    }
  }

  touchmoveSelect() {
    // Called during drag when _isSelecting is true
    // Selection extension happens here but we just track state
  }

  touchend() {
    // Cancel long press timer
    if (this._longPressTimer) {
      if (typeof this._longPressTimer === 'number') clearTimeout(this._longPressTimer);
      this._longPressTimer = null;
    }

    // If was selecting, auto-copy and finish
    if (this._isSelecting) {
      this._isSelecting = false;
      // Restore pointer events on xterm screen
      this._pointerEvents = '';
      // Copy to clipboard
      if (this._hasClipboardAPI) {
        // navigator.clipboard.writeText available
        this._fallbackCopyUsed = false;
      } else {
        // HTTP mode: use fallbackCopy
        this._fallbackCopyUsed = true;
      }
      // Selection touchend returns early — NO focus
      return;
    }

    if (!this._touchMoved) {
      // Tap: exit scroll mode and open keyboard
      if (this._inScrollMode) {
        this._inScrollMode = false;
      }
      this._focusTarget = 'overlayInput';
      this._keyboardOpen = true;
    } else {
      // Swipe happened — if keyboard was open, re-focus to keep input working
      if (this._keyboardOpen) {
        this._focusTarget = 'overlayInput';
      }
    }
  }

  fireLongPressTimer() {
    // Manually trigger the long press callback
    this._longPressTimer = null;
    this._isSelecting = true;
    this._pointerEvents = 'none';  // Block xterm.js pointer events during selection
  }

  type(text) {
    // Simulate typing characters through InputController
    for (const ch of text) {
      this.ic.typeChar(ch);
    }
  }

  async waitForFlush() {
    return this.ic.waitForFlush();
  }
}

// =====================================================================
// Test runner
// =====================================================================
let passed = 0, failed = 0;

function assert(condition, msg) {
  if (condition) { passed++; console.log(`  PASS: ${msg}`); }
  else { failed++; console.error(`  FAIL: ${msg}`); }
}

function assertArrayEqual(actual, expected, msg) {
  const a = JSON.stringify(actual), e = JSON.stringify(expected);
  if (a === e) { passed++; console.log(`  PASS: ${msg}`); }
  else { failed++; console.error(`  FAIL: ${msg}\n    expected: ${e}\n    actual:   ${a}`); }
}

async function runTests() {

  // =================================================================
  // Scenario 1: Swipe then type
  // =================================================================

  console.log('\n=== 1A. Swipe with keyboard closed -> no focus after swipe -> tap to exit scroll -> focus -> type "ls" ===');
  {
    const t = new TouchInputSim();
    t._keyboardOpen = false;

    // Swipe gesture
    t.touchstart();
    t.touchmoveScroll(30);
    t._focusTarget = null;
    t.touchend();

    assert(t._touchMoved === true, 'touchMoved set after swipe');
    assert(t._inScrollMode === true, 'In scroll mode after swipe');
    assert(t._focusTarget === null, 'No focus after swipe (keyboard was closed)');

    // Tap to exit scroll mode
    t.touchstart();
    t._focusTarget = null;
    t.touchend();

    assert(t._inScrollMode === false, 'Scroll mode exited after tap');
    assert(t._focusTarget === 'overlayInput', 'Focus triggered after tap');
    assert(t._keyboardOpen === true, 'Keyboard now open');

    // Type "ls"
    t.type('ls');
    await t.waitForFlush();
    assertArrayEqual(t.ic.sent, ['ls'], 'Sends ["ls"]');
  }

  console.log('\n=== 1B. Swipe with keyboard open -> auto re-focus -> type "pwd" ===');
  {
    const t = new TouchInputSim();
    t._keyboardOpen = true;

    // Swipe gesture
    t.touchstart();
    t.touchmoveScroll(20);
    t._focusTarget = null;
    t.touchend();

    assert(t._touchMoved === true, 'touchMoved set');
    assert(t._focusTarget === 'overlayInput', 'Auto re-focus when keyboard was open');

    // Type "pwd"
    t.type('pwd');
    await t.waitForFlush();
    assertArrayEqual(t.ic.sent, ['pwd'], 'Sends ["pwd"]');
  }

  console.log('\n=== 1C. Multiple swipes -> still in scroll mode -> tap to exit -> type "cd /" ===');
  {
    const t = new TouchInputSim();
    t._keyboardOpen = false;

    // First swipe
    t.touchstart();
    t.touchmoveScroll(40);
    t.touchend();

    // Second swipe
    t.touchstart();
    t.touchmoveScroll(60);
    t.touchend();

    assert(t._inScrollMode === true, 'Still in scroll mode after multiple swipes');
    assert(t.scrollSent.length === 2, 'Two scroll events sent');

    // Tap to exit
    t.touchstart();
    t._focusTarget = null;
    t.touchend();

    assert(t._inScrollMode === false, 'Scroll mode exited');
    assert(t._focusTarget === 'overlayInput', 'Focus triggered');

    // Type "cd /"
    t.type('cd /');
    await t.waitForFlush();
    assertArrayEqual(t.ic.sent, ['cd /'], 'Sends ["cd /"]');
  }

  // =================================================================
  // Scenario 2: Long-press select then type
  // =================================================================

  console.log('\n=== 2A. Long press + release -> pointerEvents restored -> no focus -> tap -> focus -> type "echo hi" ===');
  {
    const t = new TouchInputSim();

    // Long press: touchstart -> wait -> fireLongPressTimer -> touchend
    t.touchstart();
    t.fireLongPressTimer();

    assert(t._isSelecting === true, 'Selecting after long press');
    assert(t._pointerEvents === 'none', 'pointerEvents blocked during selection');

    // Release
    t._focusTarget = null;
    t.touchend();

    assert(t._isSelecting === false, 'Selection ended on touchend');
    assert(t._pointerEvents === '', 'pointerEvents restored after selection');
    assert(t._focusTarget === null, 'No focus after selection touchend (returns early)');

    // Tap to get focus
    t.touchstart();
    t._focusTarget = null;
    t.touchend();

    assert(t._focusTarget === 'overlayInput', 'Focus after tap');

    // Type "echo hi"
    t.type('echo hi');
    await t.waitForFlush();
    assertArrayEqual(t.ic.sent, ['echo hi'], 'Sends ["echo hi"]');
  }

  console.log('\n=== 2B. Long press + drag + release -> touchMoved stays false -> pointerEvents restored -> no focus ===');
  {
    const t = new TouchInputSim();

    // Long press: touchstart -> fireLongPressTimer -> drag (touchmoveSelect) -> touchend
    t.touchstart();
    t.fireLongPressTimer();

    assert(t._isSelecting === true, 'Selecting after long press');

    // Drag while selecting (touchmoveSelect doesn't set _touchMoved)
    t.touchmoveSelect();
    t.touchmoveSelect();

    assert(t._touchMoved === false, 'touchMoved stays false during selection drag');

    // Release
    t._focusTarget = null;
    t.touchend();

    assert(t._isSelecting === false, 'Selection ended');
    assert(t._pointerEvents === '', 'pointerEvents restored');
    assert(t._focusTarget === null, 'No focus after selection (early return)');
  }

  console.log('\n=== 2C. Safety reset -- pointerEvents stuck from interrupted selection -> touchstart resets it ===');
  {
    const t = new TouchInputSim();

    // Simulate stuck state: pointerEvents left as 'none' from interrupted selection
    t._pointerEvents = 'none';

    // New touchstart should reset it
    t.touchstart();

    assert(t._pointerEvents === '', 'pointerEvents reset by touchstart safety check');

    // Can now tap to focus
    t._focusTarget = null;
    t.touchend();

    assert(t._focusTarget === 'overlayInput', 'Can focus after safety reset');
  }

  // =================================================================
  // Scenario 3: fallbackCopy keyboard behavior
  // =================================================================

  console.log('\n=== 3A. HTTP mode (no Clipboard API) -> fallbackCopy used -> no focus triggered ===');
  {
    const t = new TouchInputSim();
    t._hasClipboardAPI = false;  // HTTP mode

    // Long press select + release
    t.touchstart();
    t.fireLongPressTimer();
    t._focusTarget = null;
    t.touchend();

    assert(t._fallbackCopyUsed === true, 'fallbackCopy used in HTTP mode');
    assert(t._focusTarget === null, 'No focus triggered after selection (early return)');
  }

  console.log('\n=== 3B. HTTPS mode -> fallbackCopy NOT used ===');
  {
    const t = new TouchInputSim();
    t._hasClipboardAPI = true;  // HTTPS mode

    // Long press select + release
    t.touchstart();
    t.fireLongPressTimer();
    t.touchend();

    assert(t._fallbackCopyUsed === false, 'fallbackCopy NOT used in HTTPS mode');
  }

  console.log('\n=== 3C. After fallbackCopy, next tap still works -> can type "hello" ===');
  {
    const t = new TouchInputSim();
    t._hasClipboardAPI = false;

    // Long press select + release (fallbackCopy fires)
    t.touchstart();
    t.fireLongPressTimer();
    t.touchend();

    assert(t._fallbackCopyUsed === true, 'fallbackCopy was used');

    // Next tap should work normally
    t.touchstart();
    t._focusTarget = null;
    t.touchend();

    assert(t._focusTarget === 'overlayInput', 'Focus works after fallbackCopy');

    // Type "hello"
    t.type('hello');
    await t.waitForFlush();
    assertArrayEqual(t.ic.sent, ['hello'], 'Sends ["hello"]');
  }

  // =================================================================
  // Scenario 4: Typing interrupted by swipe
  // =================================================================

  console.log('\n=== 4A. Type "gi", flush, swipe (keyboard open), type "t status" -> sends ["gi", "t status"] ===');
  {
    const t = new TouchInputSim();
    t._keyboardOpen = true;

    // Type "gi" and flush
    t.type('gi');
    await t.waitForFlush();
    assertArrayEqual(t.ic.sent, ['gi'], 'First flush: "gi"');

    // Swipe (keyboard stays open)
    t.touchstart();
    t.touchmoveScroll(25);
    t.touchend();

    assert(t._keyboardOpen === true, 'Keyboard still open');

    // Type "t status"
    t.type('t status');
    await t.waitForFlush();
    assertArrayEqual(t.ic.sent, ['gi', 't status'], 'Sends ["gi", "t status"]');
  }

  console.log('\n=== 4B. Type "he" during BUFFERING, swipe, buffer still flushes -> type "llo" -> sends ["he", "llo"] ===');
  {
    const t = new TouchInputSim();
    t._keyboardOpen = true;

    // Type "he" (enters BUFFERING, timer is running)
    t.type('he');
    assert(t.ic.state === 'BUFFERING', 'State is BUFFERING after typing "he"');

    // Swipe happens (does NOT cancel the buffer timer — touch handlers don't touch IC state)
    t.touchstart();
    t.touchmoveScroll(30);
    t.touchend();

    // Buffer timer fires naturally
    await t.waitForFlush();
    assertArrayEqual(t.ic.sent, ['he'], '"he" flushed by buffer timer');

    // Type "llo"
    t.type('llo');
    await t.waitForFlush();
    assertArrayEqual(t.ic.sent, ['he', 'llo'], 'Sends ["he", "llo"]');
  }

  console.log('\n=== 4C. Chinese IME composing, swipe, still COMPOSING after swipe, finish composition -> sends ["\u4F60"] ===');
  {
    const t = new TouchInputSim();
    t._keyboardOpen = true;

    // Start Chinese composition
    t.ic.compositionStart();
    assert(t.ic.state === 'COMPOSING', 'State is COMPOSING');

    // Swipe during composition (touch handlers don't affect IC state)
    t.touchstart();
    t.touchmoveScroll(20);
    t.touchend();

    // Still composing after swipe
    assert(t.ic.state === 'COMPOSING', 'Still COMPOSING after swipe');

    // Finish composition
    t.ic.textareaValue = '\u4F60';
    t.ic.compositionEnd();
    await t.waitForFlush();
    assertArrayEqual(t.ic.sent, ['\u4F60'], 'Sends ["\u4F60"]');
  }

  // =================================================================
  // Summary
  // =================================================================
  console.log('\n' + '='.repeat(50));
  console.log(`Results: ${passed} passed, ${failed} failed`);
  if (failed > 0) process.exit(1);
  else console.log('All tests passed!');
}

runTests().catch(e => { console.error('Test error:', e); process.exit(1); });
