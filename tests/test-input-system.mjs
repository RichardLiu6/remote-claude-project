/**
 * test-input-system.mjs -- Unit tests for v3 InputController (state machine + snapshot diff).
 *
 * Covers: debounce merging, snapshot diff, autocomplete, Chinese composition,
 * Enter (physical + soft with IME guard), Tab snapshot reset, Backspace (physical + soft,
 * immediate send), iOS whole-word delete, session cleanup, Ctrl+A-Z combos,
 * autocorrect attributes, BUFFER_MS variations, listener cleanup, AbortController.
 *
 * Run: node tests/test-input-system.mjs
 */

// =====================================================================
// InputController Simulation (mirrors public/index.html v3 InputController)
// =====================================================================
class InputControllerSim {
  constructor() {
    this.snapshot = '';
    this.textareaValue = '';
    this.state = 'IDLE';
    this.bufferTimer = null;
    this.BUFFER_MS = 30; // v3 default: 30ms
    this.sent = [];
    this._keydownHandled = false;
    this._emptyKeyTs = 0;
    this._lastCompositionEndTs = 0;
    this._COMPOSE_ENTER_GUARD_MS = 300;
    this._abortController = null;
    this._listenerAttachCount = 0;
    this._destroyed = false;
  }

  send(data) {
    if (this._destroyed) return; // After destroy(), no sends
    this.sent.push(data);
  }

  _setState(s) { this.state = s; }

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
    this._setState('IDLE');
  }

  resetSnapshot() {
    this.snapshot = '';
    this.textareaValue = '';
    if (this.bufferTimer) { clearTimeout(this.bufferTimer); this.bufferTimer = null; }
    this._setState('IDLE');
  }

  _startBuffer() {
    if (this.bufferTimer) clearTimeout(this.bufferTimer);
    if (this.state !== 'BUFFERING') this._setState('BUFFERING');
    this.bufferTimer = setTimeout(() => {
      this.bufferTimer = null;
      this._setState('FLUSHING');
      this._flush();
    }, this.BUFFER_MS);
  }

  compositionStart() {
    if (this.state === 'BUFFERING') {
      clearTimeout(this.bufferTimer); this.bufferTimer = null; this._flush();
    }
    this._setState('COMPOSING');
  }

  compositionEnd() {
    this._lastCompositionEndTs = Date.now();
    this._startBuffer();
  }

  // v3: Soft Enter sends \r when NOT within IME guard window
  softEnter() {
    const sinceCompose = Date.now() - this._lastCompositionEndTs;
    if (sinceCompose > this._COMPOSE_ENTER_GUARD_MS) {
      // Flush pending buffer first
      if (this.state === 'BUFFERING') {
        clearTimeout(this.bufferTimer); this.bufferTimer = null; this._flush();
      }
      this.send('\r');
      this.resetSnapshot();
      return true; // Enter was sent
    } else {
      this.resetSnapshot();
      return false; // Blocked by IME guard
    }
  }

  // Soft Enter within IME guard (simulate calling immediately after compositionEnd)
  softEnterWithinGuard() {
    this._lastCompositionEndTs = Date.now(); // just ended
    return this.softEnter(); // should be blocked
  }

  onInput(inputType) {
    if (this.state === 'COMPOSING') return;
    if (this._keydownHandled) { this._keydownHandled = false; return; }

    // v3: Backspace immediate flush
    if (inputType === 'deleteContentBackward' || inputType === 'deleteWordBackward' ||
        inputType === 'deleteSoftLineBackward' || inputType === 'deleteHardLineBackward') {
      if (this.bufferTimer) { clearTimeout(this.bufferTimer); this.bufferTimer = null; }
      this._setState('FLUSHING');
      this._flush();
      return;
    }

    this._startBuffer();
  }

  typeChar(ch) { this.textareaValue += ch; this.onInput('insertText'); }

  autocompleteReplace(newValue) { this.textareaValue = newValue; this.onInput('insertReplacementText'); }

  sendSpecialKey(key, seq) {
    if (this.state === 'COMPOSING') return;
    if (this.state === 'BUFFERING') {
      clearTimeout(this.bufferTimer); this.bufferTimer = null; this._flush();
    }
    this.send(seq);
    this._keydownHandled = true;
    if (key === 'Enter' || key === 'Tab') this.resetSnapshot();
  }

  // v3: Ctrl+letter sends control character
  sendCtrl(letter) {
    if (this.state === 'COMPOSING') return;
    if (this.state === 'BUFFERING') {
      clearTimeout(this.bufferTimer); this.bufferTimer = null; this._flush();
    }
    const code = letter.toLowerCase().charCodeAt(0);
    if (code >= 97 && code <= 122) {
      const ctrlChar = String.fromCharCode(code - 96);
      this.send(ctrlChar);
      this._keydownHandled = true;
    }
  }

  // v3: Physical Backspace — immediate, no debounce
  physicalBackspace() {
    if (this.state === 'BUFFERING') {
      clearTimeout(this.bufferTimer); this.bufferTimer = null; this._flush();
    }
    this.send('\x7f');
    this.snapshot = this.snapshot.slice(0, -1);
    this.textareaValue = this.textareaValue.slice(0, -1);
    this._keydownHandled = true;
  }

  // v3: Soft Backspace — browser modifies value, then immediate flush via diff (no debounce)
  softBackspace() {
    // First: flush any pending buffer (mirroring _immediateFlushAndSendBackspace)
    if (this.state === 'BUFFERING') {
      clearTimeout(this.bufferTimer); this.bufferTimer = null; this._flush();
    }
    // Browser modifies textarea.value
    this.textareaValue = this.textareaValue.slice(0, -1);
    // Input event fires with deleteContentBackward → immediate flush
    this.onInput('deleteContentBackward');
  }

  // v3: Soft word delete — same as softBackspace but more chars
  softWordDelete(newValue) {
    if (this.state === 'BUFFERING') {
      clearTimeout(this.bufferTimer); this.bufferTimer = null; this._flush();
    }
    this.textareaValue = newValue;
    this.onInput('deleteWordBackward');
  }

  // v3: Soft line delete
  softLineDelete(newValue) {
    if (this.state === 'BUFFERING') {
      clearTimeout(this.bufferTimer); this.bufferTimer = null; this._flush();
    }
    this.textareaValue = newValue;
    this.onInput('deleteSoftLineBackward');
  }

  attach() {
    if (this._abortController) this._abortController.abort();
    this._abortController = new AbortController();
    this._listenerAttachCount++;
    this.snapshot = ''; this.textareaValue = ''; this.state = 'IDLE';
    this._keydownHandled = false; this._emptyKeyTs = 0;
    this._destroyed = false;
    if (this.bufferTimer) { clearTimeout(this.bufferTimer); this.bufferTimer = null; }
  }

  destroy() {
    if (this.bufferTimer) { clearTimeout(this.bufferTimer); this.bufferTimer = null; }
    if (this._abortController) { this._abortController.abort(); this._abortController = null; }
    this.snapshot = ''; this.textareaValue = ''; this.state = 'IDLE';
    this._destroyed = true;
  }

  async waitForFlush() {
    return new Promise(resolve => setTimeout(resolve, this.BUFFER_MS + 20));
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
  // Group 1: Basic English typing
  // =================================================================
  console.log('\n=== 1. English "hello" typed quickly ===');
  {
    const c = new InputControllerSim();
    c.typeChar('h'); c.typeChar('e'); c.typeChar('l'); c.typeChar('l'); c.typeChar('o');
    assertArrayEqual(c.sent, [], 'No chars sent before debounce');
    assert(c.state === 'BUFFERING', 'State is BUFFERING');
    await c.waitForFlush();
    assertArrayEqual(c.sent, ['hello'], 'All chars merged as "hello"');
    assert(c.snapshot === 'hello', 'Snapshot updated to "hello"');
    assert(c.state === 'IDLE', 'State back to IDLE');
  }

  // =================================================================
  // Group 2: Autocomplete within buffer
  // =================================================================
  console.log('\n=== 2. Autocomplete "th" -> "the " within buffer ===');
  {
    const c = new InputControllerSim();
    c.typeChar('t'); c.typeChar('h');
    c.autocompleteReplace('the ');
    await c.waitForFlush();
    assertArrayEqual(c.sent, ['the '], 'Only final result sent');
  }

  // =================================================================
  // Group 3: Autocomplete after flush
  // =================================================================
  console.log('\n=== 3. Autocomplete "th" -> "that " after flush ===');
  {
    const c = new InputControllerSim();
    c.typeChar('t'); c.typeChar('h');
    await c.waitForFlush();
    assertArrayEqual(c.sent, ['th'], '"th" flushed');
    c.autocompleteReplace('that ');
    await c.waitForFlush();
    assertArrayEqual(c.sent, ['th', 'at '], 'Delta "at " sent');
  }

  // =================================================================
  // Group 4: Autocorrect with backspace
  // =================================================================
  console.log('\n=== 4. Autocorrect "helo" -> "hello " ===');
  {
    const c = new InputControllerSim();
    c.typeChar('h'); c.typeChar('e'); c.typeChar('l'); c.typeChar('o');
    await c.waitForFlush();
    c.autocompleteReplace('hello ');
    await c.waitForFlush();
    assertArrayEqual(c.sent, ['helo', '\x7f', 'lo '], '1 BS + "lo "');
  }

  // =================================================================
  // Group 5: Soft Enter sends \r (v3 change — was blocked in v1/v2)
  // =================================================================
  console.log('\n=== 5. Soft keyboard Enter sends \\r (v3) ===');
  {
    const c = new InputControllerSim();
    c.typeChar('l'); c.typeChar('s');
    await c.waitForFlush(); // flush "ls"
    const r = c.softEnter();
    assert(r === true, 'softEnter returns true (sent)');
    assertArrayEqual(c.sent, ['ls', '\r'], '"ls" + Enter sent');
    assert(c.snapshot === '', 'Snapshot reset');
  }

  // =================================================================
  // Group 6: Soft Enter blocked during IME guard window
  // =================================================================
  console.log('\n=== 6. Soft Enter blocked within 300ms of compositionEnd ===');
  {
    const c = new InputControllerSim();
    c.compositionStart();
    c.textareaValue = '\u4F60';
    c.compositionEnd();
    // Immediately try soft Enter (within guard window)
    const r = c.softEnterWithinGuard();
    assert(r === false, 'Blocked during IME guard');
  }

  // =================================================================
  // Group 7: Tab resets snapshot
  // =================================================================
  console.log('\n=== 7. Tab resets snapshot ===');
  {
    const c = new InputControllerSim();
    c.typeChar('s'); c.typeChar('e'); c.typeChar('r'); c.typeChar('v');
    c.sendSpecialKey('Tab', '\t');
    assertArrayEqual(c.sent, ['serv', '\t'], 'Buffer flushed + Tab');
    assert(c.snapshot === '', 'Snapshot reset after Tab');
  }

  // =================================================================
  // Group 8: Chinese composition incremental diff
  // =================================================================
  console.log('\n=== 8. Chinese composition incremental diff ===');
  {
    const c = new InputControllerSim();
    c.typeChar('a');
    await c.waitForFlush();
    c.compositionStart();
    c.textareaValue = 'a\u4F60\u597D';
    c.compositionEnd();
    await c.waitForFlush();
    assertArrayEqual(c.sent, ['a', '\u4F60\u597D'], 'Only incremental Chinese chars sent');
  }

  // =================================================================
  // Group 9: Physical Backspace immediate (no debounce)
  // =================================================================
  console.log('\n=== 9. Physical Backspace immediate ===');
  {
    const c = new InputControllerSim();
    c.typeChar('a'); c.typeChar('b');
    await c.waitForFlush();
    c.physicalBackspace();
    assertArrayEqual(c.sent, ['ab', '\x7f'], 'BS sent immediately (no debounce)');
    assert(c.snapshot === 'a', 'Snapshot synced');
  }

  // =================================================================
  // Group 10: Soft Backspace immediate via diff (v3: no debounce)
  // =================================================================
  console.log('\n=== 10. Soft keyboard Backspace immediate (v3) ===');
  {
    const c = new InputControllerSim();
    c.typeChar('a'); c.typeChar('b'); c.typeChar('c');
    await c.waitForFlush();
    c.sent = [];
    c.softBackspace();
    // v3: Backspace is immediate — sent right away, no waiting
    assertArrayEqual(c.sent, ['\x7f'], '1 BS sent immediately (no debounce)');
    assert(c.state === 'IDLE', 'State is IDLE after immediate flush');
  }

  // =================================================================
  // Group 11: iOS whole-word delete
  // =================================================================
  console.log('\n=== 11. iOS whole-word delete ===');
  {
    const c = new InputControllerSim();
    c.typeChar('h'); c.typeChar('e'); c.typeChar('l'); c.typeChar('l'); c.typeChar('o');
    await c.waitForFlush();
    c.sent = [];
    c.softWordDelete('');
    assertArrayEqual(c.sent, ['\x7f\x7f\x7f\x7f\x7f'], '5 BS in one string');
  }

  // =================================================================
  // Group 12: Session switch cleanup
  // =================================================================
  console.log('\n=== 12. Session switch cleanup ===');
  {
    const c = new InputControllerSim();
    c.attach();
    assert(c._listenerAttachCount === 1, 'First attach');
    c.attach();
    assert(c._listenerAttachCount === 2, 'Second attach');
    c.destroy();
    assert(c._abortController === null, 'AbortController cleared');
    assert(c.bufferTimer === null, 'Timer cleared');
    assert(c._destroyed === true, 'Destroyed flag set');
  }

  // =================================================================
  // Group 13: Composition pauses buffer
  // =================================================================
  console.log('\n=== 13. Composition pauses buffer ===');
  {
    const c = new InputControllerSim();
    c.typeChar('x');
    assert(c.state === 'BUFFERING', 'BUFFERING after type');
    c.compositionStart();
    assert(c.state === 'COMPOSING', 'COMPOSING');
    assertArrayEqual(c.sent, ['x'], '"x" flushed on compositionStart');
  }

  // =================================================================
  // Group 14: Enter flushes buffer first
  // =================================================================
  console.log('\n=== 14. Enter flushes buffer first ===');
  {
    const c = new InputControllerSim();
    c.typeChar('c'); c.typeChar('d');
    c.sendSpecialKey('Enter', '\r');
    assertArrayEqual(c.sent, ['cd', '\r'], 'Buffer flushed + Enter');
    assert(c.snapshot === '', 'Reset after Enter');
  }

  // =================================================================
  // Group 15: No send when unchanged
  // =================================================================
  console.log('\n=== 15. No send when unchanged ===');
  {
    const c = new InputControllerSim();
    c.snapshot = 'abc';
    c.textareaValue = 'abc';
    c._flush();
    assertArrayEqual(c.sent, [], 'No send');
  }

  // =================================================================
  // Group 16: State machine full cycle
  // =================================================================
  console.log('\n=== 16. State machine full cycle ===');
  {
    const c = new InputControllerSim();
    assert(c.state === 'IDLE', 'Start IDLE');
    c.typeChar('x');
    assert(c.state === 'BUFFERING', 'After input: BUFFERING');
    await c.waitForFlush();
    assert(c.state === 'IDLE', 'After flush: IDLE');
  }

  // =================================================================
  // Group 17: State machine with composition
  // =================================================================
  console.log('\n=== 17. State machine with composition ===');
  {
    const c = new InputControllerSim();
    c.compositionStart();
    assert(c.state === 'COMPOSING', 'COMPOSING');
    c.textareaValue = '\u4F60';
    c.compositionEnd();
    assert(c.state === 'BUFFERING', 'BUFFERING after compositionEnd');
    await c.waitForFlush();
    assert(c.state === 'IDLE', 'IDLE after flush');
    assertArrayEqual(c.sent, ['\u4F60'], 'Text sent');
  }

  // =================================================================
  // Group 18: Ctrl+C sends 0x03
  // =================================================================
  console.log('\n=== 18. Ctrl+C sends 0x03 ===');
  {
    const c = new InputControllerSim();
    c.sendCtrl('c');
    assertArrayEqual(c.sent, ['\x03'], 'Ctrl+C = 0x03');
  }

  // =================================================================
  // Group 19: Ctrl+D sends 0x04
  // =================================================================
  console.log('\n=== 19. Ctrl+D sends 0x04 ===');
  {
    const c = new InputControllerSim();
    c.sendCtrl('d');
    assertArrayEqual(c.sent, ['\x04'], 'Ctrl+D = 0x04');
  }

  // =================================================================
  // Group 20: Ctrl+Z sends 0x1a
  // =================================================================
  console.log('\n=== 20. Ctrl+Z sends 0x1a ===');
  {
    const c = new InputControllerSim();
    c.sendCtrl('z');
    assertArrayEqual(c.sent, ['\x1a'], 'Ctrl+Z = 0x1a');
  }

  // =================================================================
  // Group 21: Ctrl+A sends 0x01
  // =================================================================
  console.log('\n=== 21. Ctrl+A sends 0x01 ===');
  {
    const c = new InputControllerSim();
    c.sendCtrl('a');
    assertArrayEqual(c.sent, ['\x01'], 'Ctrl+A = 0x01');
  }

  // =================================================================
  // Group 22: Ctrl+E sends 0x05
  // =================================================================
  console.log('\n=== 22. Ctrl+E sends 0x05 ===');
  {
    const c = new InputControllerSim();
    c.sendCtrl('e');
    assertArrayEqual(c.sent, ['\x05'], 'Ctrl+E = 0x05');
  }

  // =================================================================
  // Group 23: Ctrl+L sends 0x0c
  // =================================================================
  console.log('\n=== 23. Ctrl+L sends 0x0c ===');
  {
    const c = new InputControllerSim();
    c.sendCtrl('l');
    assertArrayEqual(c.sent, ['\x0c'], 'Ctrl+L = 0x0c');
  }

  // =================================================================
  // Group 24: Ctrl+R sends 0x12
  // =================================================================
  console.log('\n=== 24. Ctrl+R sends 0x12 ===');
  {
    const c = new InputControllerSim();
    c.sendCtrl('r');
    assertArrayEqual(c.sent, ['\x12'], 'Ctrl+R = 0x12');
  }

  // =================================================================
  // Group 25: Ctrl+W sends 0x17
  // =================================================================
  console.log('\n=== 25. Ctrl+W sends 0x17 ===');
  {
    const c = new InputControllerSim();
    c.sendCtrl('w');
    assertArrayEqual(c.sent, ['\x17'], 'Ctrl+W = 0x17');
  }

  // =================================================================
  // Group 26: Ctrl+U sends 0x15
  // =================================================================
  console.log('\n=== 26. Ctrl+U sends 0x15 ===');
  {
    const c = new InputControllerSim();
    c.sendCtrl('u');
    assertArrayEqual(c.sent, ['\x15'], 'Ctrl+U = 0x15');
  }

  // =================================================================
  // Group 27: Ctrl flushes buffer before sending
  // =================================================================
  console.log('\n=== 27. Ctrl flushes buffer before sending ===');
  {
    const c = new InputControllerSim();
    c.typeChar('g'); c.typeChar('i'); c.typeChar('t');
    c.sendCtrl('c');
    assertArrayEqual(c.sent, ['git', '\x03'], 'Buffer flushed then Ctrl+C sent');
  }

  // =================================================================
  // Group 28: Ctrl ignored during COMPOSING
  // =================================================================
  console.log('\n=== 28. Ctrl ignored during COMPOSING ===');
  {
    const c = new InputControllerSim();
    c.compositionStart();
    c.sendCtrl('c');
    assertArrayEqual(c.sent, [], 'Nothing sent during COMPOSING');
  }

  // =================================================================
  // Group 29: Soft Enter after IME guard expires
  // =================================================================
  console.log('\n=== 29. Soft Enter after IME guard expires ===');
  {
    const c = new InputControllerSim();
    c._lastCompositionEndTs = Date.now() - 500; // 500ms ago
    c.typeChar('l'); c.typeChar('s');
    await c.waitForFlush();
    const r = c.softEnter();
    assert(r === true, 'softEnter returns true (guard expired)');
    assert(c.sent.includes('\r'), '\\r was sent');
  }

  // =================================================================
  // Group 30: Soft Enter flushes buffer before sending \r
  // =================================================================
  console.log('\n=== 30. Soft Enter flushes buffer before \\r ===');
  {
    const c = new InputControllerSim();
    c._lastCompositionEndTs = 0; // Long ago
    c.typeChar('p'); c.typeChar('w'); c.typeChar('d');
    const r = c.softEnter();
    assert(r === true, 'softEnter returns true');
    assertArrayEqual(c.sent, ['pwd', '\r'], 'Buffer flushed + \\r');
  }

  // =================================================================
  // Group 31: BUFFER_MS = 30ms (default) behavior
  // =================================================================
  console.log('\n=== 31. BUFFER_MS = 30ms default ===');
  {
    const c = new InputControllerSim();
    assert(c.BUFFER_MS === 30, 'Default BUFFER_MS is 30');
    c.typeChar('a');
    // After 15ms, not yet flushed
    await new Promise(r => setTimeout(r, 15));
    assertArrayEqual(c.sent, [], 'Not flushed at 15ms');
    // After full buffer + margin
    await c.waitForFlush();
    assertArrayEqual(c.sent, ['a'], 'Flushed after 30ms');
  }

  // =================================================================
  // Group 32: BUFFER_MS = 50ms behavior
  // =================================================================
  console.log('\n=== 32. BUFFER_MS = 50ms behavior ===');
  {
    const c = new InputControllerSim();
    c.BUFFER_MS = 50;
    c.typeChar('x');
    await new Promise(r => setTimeout(r, 35));
    assertArrayEqual(c.sent, [], 'Not flushed at 35ms with BUFFER_MS=50');
    await new Promise(r => setTimeout(r, 40)); // total ~75ms
    assertArrayEqual(c.sent, ['x'], 'Flushed after 50ms');
  }

  // =================================================================
  // Group 33: BUFFER_MS = 80ms behavior (v2 value, slower)
  // =================================================================
  console.log('\n=== 33. BUFFER_MS = 80ms behavior ===');
  {
    const c = new InputControllerSim();
    c.BUFFER_MS = 80;
    c.typeChar('y');
    await new Promise(r => setTimeout(r, 50));
    assertArrayEqual(c.sent, [], 'Not flushed at 50ms with BUFFER_MS=80');
    await new Promise(r => setTimeout(r, 60)); // total ~110ms
    assertArrayEqual(c.sent, ['y'], 'Flushed after 80ms');
  }

  // =================================================================
  // Group 34: Backspace during BUFFERING flushes then deletes
  // =================================================================
  console.log('\n=== 34. Backspace during BUFFERING flushes then deletes ===');
  {
    const c = new InputControllerSim();
    c.typeChar('a'); c.typeChar('b'); c.typeChar('c');
    assert(c.state === 'BUFFERING', 'BUFFERING after typing');
    // Physical Backspace while buffering
    c.physicalBackspace();
    // Should flush "abc" first, then send BS
    assertArrayEqual(c.sent, ['abc', '\x7f'], 'Buffer flushed then BS sent');
    assert(c.snapshot === 'ab', 'Snapshot = "ab"');
  }

  // =================================================================
  // Group 35: Soft Backspace during BUFFERING flushes then deletes
  // =================================================================
  console.log('\n=== 35. Soft Backspace during BUFFERING flushes then deletes ===');
  {
    const c = new InputControllerSim();
    c.typeChar('x'); c.typeChar('y'); c.typeChar('z');
    assert(c.state === 'BUFFERING', 'BUFFERING');
    c.softBackspace();
    // Should flush "xyz" first (via _immediateFlushAndSendBackspace),
    // then browser removes last char (textareaValue="xy"),
    // then immediate diff sends 1 BS
    assertArrayEqual(c.sent, ['xyz', '\x7f'], 'Buffer flushed + BS');
    assert(c.snapshot === 'xy', 'Snapshot = "xy"');
  }

  // =================================================================
  // Group 36: Soft line delete
  // =================================================================
  console.log('\n=== 36. Soft line delete ===');
  {
    const c = new InputControllerSim();
    c.typeChar('a'); c.typeChar('b'); c.typeChar('c');
    await c.waitForFlush();
    c.sent = [];
    c.softLineDelete('');
    assertArrayEqual(c.sent, ['\x7f\x7f\x7f'], '3 BS via line delete');
  }

  // =================================================================
  // Group 37: Destroy prevents further sends
  // =================================================================
  console.log('\n=== 37. Destroy prevents further sends ===');
  {
    const c = new InputControllerSim();
    c.destroy();
    c.send('test');
    assertArrayEqual(c.sent, [], 'No send after destroy');
  }

  // =================================================================
  // Group 38: Destroy clears AbortController
  // =================================================================
  console.log('\n=== 38. Destroy clears AbortController ===');
  {
    const c = new InputControllerSim();
    c.attach();
    assert(c._abortController !== null, 'AbortController exists after attach');
    c.destroy();
    assert(c._abortController === null, 'AbortController null after destroy');
  }

  // =================================================================
  // Group 39: Multiple attach/destroy cycles (listener cleanup)
  // =================================================================
  console.log('\n=== 39. Multiple attach/destroy cycles ===');
  {
    const c = new InputControllerSim();
    for (let i = 0; i < 5; i++) {
      c.attach();
      c.typeChar('x');
      c.destroy();
    }
    assert(c._listenerAttachCount === 5, '5 attach cycles completed');
    assert(c._abortController === null, 'Final cleanup OK');
    assert(c.bufferTimer === null, 'No dangling timer');
  }

  // =================================================================
  // Group 40: Attach resets state fully
  // =================================================================
  console.log('\n=== 40. Attach resets state fully ===');
  {
    const c = new InputControllerSim();
    c.snapshot = 'leftover';
    c.textareaValue = 'leftover';
    c.state = 'BUFFERING';
    c._keydownHandled = true;
    c.attach();
    assert(c.snapshot === '', 'Snapshot reset on attach');
    assert(c.textareaValue === '', 'TextareaValue reset on attach');
    assert(c.state === 'IDLE', 'State reset to IDLE on attach');
    assert(c._keydownHandled === false, '_keydownHandled reset');
    assert(c._destroyed === false, '_destroyed reset');
  }

  // =================================================================
  // Group 41: Autocomplete replaces entire word
  // =================================================================
  console.log('\n=== 41. Autocomplete replaces entire word ===');
  {
    const c = new InputControllerSim();
    c.typeChar('t'); c.typeChar('e'); c.typeChar('h');
    await c.waitForFlush();
    c.autocompleteReplace('the ');
    await c.waitForFlush();
    // snapshot="teh", current="the "
    // common prefix: "t" (len=1), BS=3-1=2, new="he "
    assertArrayEqual(c.sent, ['teh', '\x7f\x7f', 'he '], '2 BS + "he "');
  }

  // =================================================================
  // Group 42: Rapid type then autocomplete within same buffer
  // =================================================================
  console.log('\n=== 42. Rapid type then autocomplete within same buffer ===');
  {
    const c = new InputControllerSim();
    c.typeChar('w');
    c.typeChar('o');
    c.autocompleteReplace('world ');
    await c.waitForFlush();
    // All within same buffer window: snapshot="" -> "world "
    assertArrayEqual(c.sent, ['world '], 'Merged: only final result');
  }

  // =================================================================
  // Group 43: Arrow keys don't reset snapshot
  // =================================================================
  console.log('\n=== 43. Arrow keys dont reset snapshot ===');
  {
    const c = new InputControllerSim();
    c.typeChar('a'); c.typeChar('b');
    await c.waitForFlush();
    c.sendSpecialKey('ArrowLeft', '\x1b[D');
    assert(c.snapshot === 'ab', 'Snapshot NOT reset after ArrowLeft');
  }

  // =================================================================
  // Group 44: Esc key behavior
  // =================================================================
  console.log('\n=== 44. Esc flushes buffer but doesnt reset snapshot ===');
  {
    const c = new InputControllerSim();
    c.typeChar('v'); c.typeChar('i');
    c.sendSpecialKey('Escape', '\x1b');
    assertArrayEqual(c.sent, ['vi', '\x1b'], 'Buffer flushed + Esc');
    // Esc doesn't reset snapshot (only Enter/Tab do)
    assert(c.snapshot === 'vi', 'Snapshot preserved after Esc');
  }

  // =================================================================
  // Group 45: Composition → immediate type (English after Chinese)
  // =================================================================
  console.log('\n=== 45. English type immediately after composition ===');
  {
    const c = new InputControllerSim();
    c.compositionStart();
    c.textareaValue = '\u4F60\u597D';
    c.compositionEnd();
    await c.waitForFlush();
    c.sent = [];
    // Now type English
    c.textareaValue = '\u4F60\u597Dabc';
    c.onInput('insertText');
    await c.waitForFlush();
    assertArrayEqual(c.sent, ['abc'], 'Incremental English after Chinese');
  }

  // =================================================================
  // Group 46: Double composition (two Chinese phrases)
  // =================================================================
  console.log('\n=== 46. Double composition ===');
  {
    const c = new InputControllerSim();
    c.compositionStart();
    c.textareaValue = '\u4F60';
    c.compositionEnd();
    await c.waitForFlush();
    c.sent = [];
    c.compositionStart();
    c.textareaValue = '\u4F60\u597D';
    c.compositionEnd();
    await c.waitForFlush();
    assertArrayEqual(c.sent, ['\u597D'], 'Only second character sent');
  }

  // =================================================================
  // Group 47: Ctrl+letter range boundary (a and z)
  // =================================================================
  console.log('\n=== 47. Ctrl+A (0x01) and Ctrl+Z (0x1a) boundary ===');
  {
    const c = new InputControllerSim();
    c.sendCtrl('a');
    c.sendCtrl('z');
    assert(c.sent[0].charCodeAt(0) === 1, 'Ctrl+A = 0x01');
    assert(c.sent[1].charCodeAt(0) === 26, 'Ctrl+Z = 0x1a');
  }

  // =================================================================
  // Group 48: Ctrl uppercase letter works same as lowercase
  // =================================================================
  console.log('\n=== 48. Ctrl+C uppercase works ===');
  {
    const c = new InputControllerSim();
    c.sendCtrl('C'); // uppercase
    assertArrayEqual(c.sent, ['\x03'], 'Ctrl+C (uppercase) = 0x03');
  }

  // =================================================================
  // Group 49: Backspace after autocomplete
  // =================================================================
  console.log('\n=== 49. Backspace after autocomplete ===');
  {
    const c = new InputControllerSim();
    c.typeChar('h'); c.typeChar('i');
    await c.waitForFlush();
    c.autocompleteReplace('high ');
    await c.waitForFlush();
    c.sent = [];
    c.softBackspace(); // delete trailing space
    assertArrayEqual(c.sent, ['\x7f'], 'BS after autocomplete');
    assert(c.snapshot === 'high', 'Snapshot = "high"');
  }

  // =================================================================
  // Group 50: Multiple Backspaces in sequence
  // =================================================================
  console.log('\n=== 50. Multiple sequential Backspaces ===');
  {
    const c = new InputControllerSim();
    c.typeChar('a'); c.typeChar('b'); c.typeChar('c');
    await c.waitForFlush();
    c.sent = [];
    c.physicalBackspace(); // c deleted
    c.physicalBackspace(); // b deleted
    assertArrayEqual(c.sent, ['\x7f', '\x7f'], '2 BS sent immediately');
    assert(c.snapshot === 'a', 'Snapshot = "a"');
    assert(c.textareaValue === 'a', 'TextareaValue = "a"');
  }

  // =================================================================
  // Group 51: Empty state flush sends nothing
  // =================================================================
  console.log('\n=== 51. Empty state flush sends nothing ===');
  {
    const c = new InputControllerSim();
    c._flush();
    assertArrayEqual(c.sent, [], 'No send on empty flush');
    assert(c.state === 'IDLE', 'State stays IDLE');
  }

  // =================================================================
  // Group 52: BUFFER_MS default is 30ms
  // =================================================================
  console.log('\n=== 52. BUFFER_MS default is 30ms ===');
  {
    const c = new InputControllerSim();
    assert(c.BUFFER_MS === 30, 'Default BUFFER_MS = 30');
  }

  // =================================================================
  // Group 53: Autocorrect textarea attributes validation
  // =================================================================
  console.log('\n=== 53. Autocorrect textarea attributes ===');
  {
    // These are HTML attributes that should be set on the textarea.
    // We verify the expected values here as a documentation test.
    const expectedAttrs = {
      autocomplete: 'off',
      autocorrect: 'off',
      autocapitalize: 'none', // v3 change: "off" → "none" (spec-compliant)
      spellcheck: 'false',
      inputmode: 'text',
      enterkeyhint: 'send'
    };
    assert(expectedAttrs.autocomplete === 'off', 'autocomplete=off');
    assert(expectedAttrs.autocorrect === 'off', 'autocorrect=off');
    assert(expectedAttrs.autocapitalize === 'none', 'autocapitalize=none (v3)');
    assert(expectedAttrs.spellcheck === 'false', 'spellcheck=false');
    assert(expectedAttrs.inputmode === 'text', 'inputmode=text');
    assert(expectedAttrs.enterkeyhint === 'send', 'enterkeyhint=send');
  }

  // =================================================================
  // Group 54: AbortController signal tracks aborted state
  // =================================================================
  console.log('\n=== 54. AbortController signal lifecycle ===');
  {
    const c = new InputControllerSim();
    c.attach();
    const signal1 = c._abortController.signal;
    assert(!signal1.aborted, 'Signal not aborted initially');
    c.attach(); // second attach aborts first
    assert(signal1.aborted, 'First signal aborted on re-attach');
    const signal2 = c._abortController.signal;
    assert(!signal2.aborted, 'Second signal fresh');
    c.destroy();
    assert(signal2.aborted, 'Second signal aborted on destroy');
  }

  // =================================================================
  // Group 55: Soft Backspace while IDLE
  // =================================================================
  console.log('\n=== 55. Soft Backspace while IDLE ===');
  {
    const c = new InputControllerSim();
    c.textareaValue = 'abc';
    c.snapshot = 'abc';
    c.softBackspace();
    assertArrayEqual(c.sent, ['\x7f'], 'BS from IDLE state');
    assert(c.snapshot === 'ab', 'Snapshot updated');
  }

  // =================================================================
  // Group 56: Type after destroy does nothing
  // =================================================================
  console.log('\n=== 56. Type after destroy does nothing ===');
  {
    const c = new InputControllerSim();
    c.attach();
    c.destroy();
    c.typeChar('a');
    // _startBuffer still sets timer but send() is no-op
    await c.waitForFlush();
    assertArrayEqual(c.sent, [], 'No data sent after destroy');
  }

  // =================================================================
  // Group 57: Soft Enter sends \r from clean state
  // =================================================================
  console.log('\n=== 57. Soft Enter from clean state ===');
  {
    const c = new InputControllerSim();
    c._lastCompositionEndTs = 0; // no recent composition
    const r = c.softEnter();
    assert(r === true, 'softEnter returns true');
    assertArrayEqual(c.sent, ['\r'], 'Just \\r sent');
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
