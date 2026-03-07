/**
 * test-input-system.mjs -- Unit tests for unified debounce input model (v1 rewrite).
 *
 * Simulates the InputController logic from public/index.html.
 * Tests cover: debounce merging, snapshot diff, autocomplete, Chinese composition,
 * Enter blocking, Tab snapshot reset, soft/physical Backspace, session cleanup.
 *
 * Run: node tests/test-input-system.mjs
 */

class InputControllerSim {
  constructor() {
    this.snapshot = '';
    this.textareaValue = '';
    this.state = 'IDLE';
    this.bufferTimer = null;
    this.BUFFER_MS = 150;
    this.sent = [];
    this._keydownHandled = false;
    this._emptyKeyTs = 0;
    this._abortController = null;
    this._listenerAttachCount = 0;
  }

  send(data) { this.sent.push(data); }

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

  compositionEnd() { this._startBuffer(); }

  // Soft keyboard Enter: ALWAYS blocked (v1 spec)
  softEnter() {
    this.resetSnapshot();
    return false;
  }

  onInput() {
    if (this.state === 'COMPOSING') return;
    if (this._keydownHandled) { this._keydownHandled = false; return; }
    this._startBuffer();
  }

  typeChar(ch) { this.textareaValue += ch; this.onInput(); }

  autocompleteReplace(newValue) { this.textareaValue = newValue; this.onInput(); }

  sendSpecialKey(key, seq) {
    if (this.state === 'COMPOSING') return;
    if (this.state === 'BUFFERING') {
      clearTimeout(this.bufferTimer); this.bufferTimer = null; this._flush();
    }
    this.send(seq);
    this._keydownHandled = true;
    if (key === 'Enter' || key === 'Tab') this.resetSnapshot();
  }

  physicalBackspace() {
    if (this.state === 'BUFFERING') {
      clearTimeout(this.bufferTimer); this.bufferTimer = null; this._flush();
    }
    this.send('\x7f');
    this.snapshot = this.snapshot.slice(0, -1);
    this.textareaValue = this.textareaValue.slice(0, -1);
    this._keydownHandled = true;
  }

  softBackspace() { this.textareaValue = this.textareaValue.slice(0, -1); this.onInput(); }

  softWordDelete(newValue) { this.textareaValue = newValue; this.onInput(); }

  attach() {
    if (this._abortController) this._abortController.abort();
    this._abortController = new AbortController();
    this._listenerAttachCount++;
    this.snapshot = ''; this.textareaValue = ''; this.state = 'IDLE';
    this._keydownHandled = false; this._emptyKeyTs = 0;
    if (this.bufferTimer) { clearTimeout(this.bufferTimer); this.bufferTimer = null; }
  }

  destroy() {
    if (this.bufferTimer) { clearTimeout(this.bufferTimer); this.bufferTimer = null; }
    if (this._abortController) { this._abortController.abort(); this._abortController = null; }
    this.snapshot = ''; this.textareaValue = ''; this.state = 'IDLE';
  }

  async waitForFlush() {
    return new Promise(resolve => setTimeout(resolve, this.BUFFER_MS + 20));
  }
}

// --- Test runner ---
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

  console.log('\n=== 1. English "hello" typed quickly ===');
  {
    const c = new InputControllerSim();
    c.typeChar('h'); c.typeChar('e'); c.typeChar('l'); c.typeChar('l'); c.typeChar('o');
    assertArrayEqual(c.sent, [], 'No chars sent before debounce');
    assert(c.state === 'BUFFERING', 'State is BUFFERING');
    await c.waitForFlush();
    assertArrayEqual(c.sent, ['hello'], 'All chars sent as "hello"');
    assert(c.snapshot === 'hello', 'Snapshot updated');
    assert(c.state === 'IDLE', 'State back to IDLE');
  }

  console.log('\n=== 2. Autocomplete "th" -> "the " within buffer ===');
  {
    const c = new InputControllerSim();
    c.typeChar('t'); c.typeChar('h');
    c.autocompleteReplace('the ');
    await c.waitForFlush();
    assertArrayEqual(c.sent, ['the '], 'Only final result sent');
  }

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

  console.log('\n=== 4. Autocorrect "helo" -> "hello " ===');
  {
    const c = new InputControllerSim();
    c.typeChar('h'); c.typeChar('e'); c.typeChar('l'); c.typeChar('o');
    await c.waitForFlush();
    c.autocompleteReplace('hello ');
    await c.waitForFlush();
    assertArrayEqual(c.sent, ['helo', '\x7f', 'lo '], '1 BS + "lo "');
  }

  console.log('\n=== 5. Soft keyboard Enter ALWAYS blocked ===');
  {
    const c = new InputControllerSim();
    c.typeChar('l'); c.typeChar('s');
    const r = c.softEnter();
    assert(r === false, 'softEnter returns false');
    assertArrayEqual(c.sent, [], 'Nothing sent');
    assert(c.snapshot === '', 'Snapshot reset');
  }

  console.log('\n=== 6. Soft Enter blocked during composition too ===');
  {
    const c = new InputControllerSim();
    c.compositionStart();
    const r = c.softEnter();
    assert(r === false, 'Blocked during composition');
    assertArrayEqual(c.sent, [], 'Nothing sent');
  }

  console.log('\n=== 7. Tab resets snapshot ===');
  {
    const c = new InputControllerSim();
    c.typeChar('s'); c.typeChar('e'); c.typeChar('r'); c.typeChar('v');
    c.sendSpecialKey('Tab', '\t');
    assertArrayEqual(c.sent, ['serv', '\t'], 'Buffer flushed + Tab');
    assert(c.snapshot === '', 'Snapshot reset after Tab');
  }

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

  console.log('\n=== 9. Physical Backspace immediate ===');
  {
    const c = new InputControllerSim();
    c.typeChar('a'); c.typeChar('b');
    await c.waitForFlush();
    c.physicalBackspace();
    assertArrayEqual(c.sent, ['ab', '\x7f'], 'BS sent immediately');
    assert(c.snapshot === 'a', 'Snapshot synced');
  }

  console.log('\n=== 10. Soft keyboard Backspace via diff ===');
  {
    const c = new InputControllerSim();
    c.typeChar('a'); c.typeChar('b'); c.typeChar('c');
    await c.waitForFlush();
    c.sent = [];
    c.softBackspace();
    assert(c.sent.length === 0, 'Not sent immediately');
    await c.waitForFlush();
    assertArrayEqual(c.sent, ['\x7f'], '1 BS via diff');
  }

  console.log('\n=== 11. iOS whole-word delete ===');
  {
    const c = new InputControllerSim();
    c.typeChar('h'); c.typeChar('e'); c.typeChar('l'); c.typeChar('l'); c.typeChar('o');
    await c.waitForFlush();
    c.sent = [];
    c.softWordDelete('');
    await c.waitForFlush();
    assertArrayEqual(c.sent, ['\x7f\x7f\x7f\x7f\x7f'], '5 BS in one string');
  }

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
  }

  console.log('\n=== 13. Composition pauses buffer ===');
  {
    const c = new InputControllerSim();
    c.typeChar('x');
    assert(c.state === 'BUFFERING', 'BUFFERING after type');
    c.compositionStart();
    assert(c.state === 'COMPOSING', 'COMPOSING');
    assertArrayEqual(c.sent, ['x'], '"x" flushed on compositionStart');
  }

  console.log('\n=== 14. Enter flushes buffer first ===');
  {
    const c = new InputControllerSim();
    c.typeChar('c'); c.typeChar('d');
    c.sendSpecialKey('Enter', '\r');
    assertArrayEqual(c.sent, ['cd', '\r'], 'Buffer flushed + Enter');
    assert(c.snapshot === '', 'Reset after Enter');
  }

  console.log('\n=== 15. No send when unchanged ===');
  {
    const c = new InputControllerSim();
    c.snapshot = 'abc';
    c.textareaValue = 'abc';
    c._flush();
    assertArrayEqual(c.sent, [], 'No send');
  }

  console.log('\n=== 16. State machine full cycle ===');
  {
    const c = new InputControllerSim();
    assert(c.state === 'IDLE', 'Start IDLE');
    c.typeChar('x');
    assert(c.state === 'BUFFERING', 'After input: BUFFERING');
    await c.waitForFlush();
    assert(c.state === 'IDLE', 'After flush: IDLE');
  }

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

  console.log('\n' + '='.repeat(50));
  console.log(`Results: ${passed} passed, ${failed} failed`);
  if (failed > 0) process.exit(1);
  else console.log('All tests passed!');
}

runTests().catch(e => { console.error('Test error:', e); process.exit(1); });
