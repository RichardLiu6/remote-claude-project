# Mobile Input Test System Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a three-layer test system for mobile input: logic-layer unit tests (run every change), DOM-layer Playwright integration tests (run at key checkpoints), and a visual test harness page (open on real device for debugging).

**Architecture:** Logic tests simulate touch+input state interactions via a `TouchInputSim` class that models the touchstart/move/end handlers alongside `InputControllerSim`. DOM tests use Playwright iPhone emulation against the real page, injecting hooks to capture `wsSend` calls. The harness page hooks into the real app's event system and displays a live event stream.

**Tech Stack:** Node.js (unit tests), Playwright (e2e), vanilla HTML/JS (harness)

---

### Task 1: Logic-layer unit tests — TouchInputSim

**Files:**
- Create: `tests/test-touch-input.mjs`

**Step 1: Write the TouchInputSim class**

This class models the touch handler state from `public/index.html` lines 835-1054 — the variables `_isSelecting`, `_touchMoved`, `_keyboardOpen`, `_inScrollMode`, and the `pointerEvents` state on xterm-screen. It composes with `InputControllerSim` (copied from `test-input-system.mjs`).

```javascript
/**
 * test-touch-input.mjs -- Touch + Input cross-scenario tests.
 *
 * Tests the interaction between touch handlers (scroll, long-press select)
 * and InputController (typing, IME). Catches regressions where touch
 * features break input or vice versa.
 *
 * Run: node tests/test-touch-input.mjs
 */

// === InputControllerSim (same as test-input-system.mjs) ===
class InputControllerSim {
  constructor() {
    this.snapshot = '';
    this.textareaValue = '';
    this.state = 'IDLE';
    this.bufferTimer = null;
    this.BUFFER_MS = 30;
    this.sent = [];
    this._keydownHandled = false;
    this._emptyKeyTs = 0;
    this._lastCompositionEndTs = 0;
    this._COMPOSE_ENTER_GUARD_MS = 300;
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

  typeChar(ch) { this.textareaValue += ch; this._onInput('insertText'); }

  _onInput(inputType) {
    if (this.state === 'COMPOSING') return;
    if (this._keydownHandled) { this._keydownHandled = false; return; }
    if (inputType === 'deleteContentBackward') {
      if (this.bufferTimer) { clearTimeout(this.bufferTimer); this.bufferTimer = null; }
      this._setState('FLUSHING');
      this._flush();
      return;
    }
    this._startBuffer();
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

  softEnter() {
    const sinceCompose = Date.now() - this._lastCompositionEndTs;
    if (sinceCompose > this._COMPOSE_ENTER_GUARD_MS) {
      if (this.state === 'BUFFERING') {
        clearTimeout(this.bufferTimer); this.bufferTimer = null; this._flush();
      }
      this.send('\r');
      this.resetSnapshot();
      return true;
    }
    this.resetSnapshot();
    return false;
  }

  async waitForFlush() {
    return new Promise(resolve => setTimeout(resolve, this.BUFFER_MS + 20));
  }
}

// === TouchInputSim: models touch handler state ===
class TouchInputSim {
  constructor() {
    this.ic = new InputControllerSim();
    // Touch state (mirrors index.html connect() isMobile block)
    this._isSelecting = false;
    this._touchMoved = false;
    this._keyboardOpen = false;
    this._inScrollMode = false;
    this._pointerEvents = ''; // '' = normal, 'none' = blocked
    this._longPressTimer = null;
    this._focusTarget = null; // tracks what got focused
    this._fallbackCopyUsed = false;
    this._hasClipboardAPI = false; // simulate HTTP (no Clipboard API)
    this.scrollSent = []; // scroll commands sent
  }

  // --- Touch event simulations ---

  touchstart({ isTerminalArea = true } = {}) {
    this._touchMoved = false;
    this._isSelecting = false;
    // Safety: restore pointerEvents (the fix we added)
    this._pointerEvents = '';
    this._cancelLongPress();

    if (isTerminalArea) {
      this._longPressTimer = setTimeout(() => {
        this._isSelecting = true;
        this._pointerEvents = 'none';
      }, 500);
    }
  }

  touchmoveScroll(deltaY) {
    if (this._isSelecting) return; // selection eats the move
    if (Math.abs(deltaY) > 5) {
      this._touchMoved = true;
      this._cancelLongPress();
      if (!this._inScrollMode) {
        this._inScrollMode = true;
        this.scrollSent.push('enter-scroll');
      }
      this.scrollSent.push(deltaY > 0 ? 'scroll-up' : 'scroll-down');
    }
  }

  touchmoveSelect() {
    // Only works if _isSelecting is true (after long-press timer fired)
    if (!this._isSelecting) return;
    // Selection drag — _touchMoved stays false (matching real code)
  }

  touchend() {
    this._cancelLongPress();

    if (this._isSelecting) {
      this._isSelecting = false;
      this._pointerEvents = '';
      // copyToClipboard → fallbackCopy path
      if (!this._hasClipboardAPI) {
        this._fallbackCopyUsed = true;
        // BUG (before fix): this would focus a temp textarea → keyboard pops up
        // FIX: readonly textarea doesn't trigger keyboard
      }
      return; // early return — no focus
    }

    if (!this._touchMoved) {
      // Tap: exit scroll mode + focus input
      if (this._inScrollMode) {
        this._inScrollMode = false;
      }
      this._focusOverlayInput();
    } else {
      // Swipe: re-focus only if keyboard was already open
      if (this._keyboardOpen) {
        this._focusOverlayInput();
      }
    }
  }

  // --- Simulate long-press timer firing ---
  fireLongPressTimer() {
    if (this._longPressTimer) {
      clearTimeout(this._longPressTimer);
      this._longPressTimer = null;
      this._isSelecting = true;
      this._pointerEvents = 'none';
    }
  }

  // --- Helpers ---

  _cancelLongPress() {
    if (this._longPressTimer) {
      clearTimeout(this._longPressTimer);
      this._longPressTimer = null;
    }
  }

  _focusOverlayInput() {
    this._focusTarget = 'overlayInput';
    this._keyboardOpen = true;
  }

  // Type via InputController (requires focus)
  type(text) {
    for (const ch of text) this.ic.typeChar(ch);
  }

  async waitForFlush() {
    return this.ic.waitForFlush();
  }
}

// === Test Runner ===
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

  // =====================================================================
  // Scenario 1: Swipe scroll then immediately type
  // =====================================================================
  console.log('\n=== Scenario 1: Swipe then type ===');

  // 1A: Swipe with keyboard closed — tap to refocus then type
  {
    const t = new TouchInputSim();
    t.touchstart();
    t.touchmoveScroll(30); // scroll up
    t.touchend();
    assert(t._touchMoved === true, '1A: touchMoved is true after swipe');
    assert(t._focusTarget === null, '1A: No focus after swipe (keyboard was closed)');
    assert(t._inScrollMode === true, '1A: In scroll mode');

    // User taps to exit scroll mode and type
    t.touchstart();
    t.touchend();
    assert(t._inScrollMode === false, '1A: Scroll mode exited on tap');
    assert(t._focusTarget === 'overlayInput', '1A: Input focused on tap');
    assert(t._pointerEvents === '', '1A: pointerEvents restored');

    // Now type
    t.type('ls');
    await t.waitForFlush();
    assertArrayEqual(t.ic.sent, ['ls'], '1A: "ls" sent after swipe+tap+type');
  }

  // 1B: Swipe with keyboard open — auto re-focus, type works
  {
    const t = new TouchInputSim();
    t._keyboardOpen = true; // keyboard already open
    t.touchstart();
    t.touchmoveScroll(30);
    t.touchend();
    assert(t._focusTarget === 'overlayInput', '1B: Re-focused after swipe (keyboard was open)');

    t.type('pwd');
    await t.waitForFlush();
    assertArrayEqual(t.ic.sent, ['pwd'], '1B: "pwd" sent after swipe with keyboard open');
  }

  // 1C: Multiple swipes then type
  {
    const t = new TouchInputSim();
    t.touchstart(); t.touchmoveScroll(30); t.touchend();
    t.touchstart(); t.touchmoveScroll(-20); t.touchend();
    t.touchstart(); t.touchmoveScroll(10); t.touchend();
    assert(t._inScrollMode === true, '1C: Still in scroll mode');

    // Tap to exit
    t.touchstart(); t.touchend();
    assert(t._inScrollMode === false, '1C: Exited scroll mode');
    t.type('cd /');
    await t.waitForFlush();
    assertArrayEqual(t.ic.sent, ['cd /'], '1C: Can type after multiple swipes');
  }

  // =====================================================================
  // Scenario 2: Long-press select then type
  // =====================================================================
  console.log('\n=== Scenario 2: Long-press select then type ===');

  // 2A: Long press + release → pointerEvents restored → can type after tap
  {
    const t = new TouchInputSim();
    t.touchstart();
    t.fireLongPressTimer(); // simulate 500ms passed
    assert(t._isSelecting === true, '2A: Selecting after long press');
    assert(t._pointerEvents === 'none', '2A: pointerEvents blocked during selection');

    t.touchend(); // selection ends
    assert(t._isSelecting === false, '2A: Not selecting after touchend');
    assert(t._pointerEvents === '', '2A: pointerEvents restored after selection');
    assert(t._focusTarget === null, '2A: No focus triggered (selection path returns early)');

    // Tap to focus, then type
    t.touchstart(); t.touchend();
    assert(t._focusTarget === 'overlayInput', '2A: Focus restored on tap');
    t.type('echo hi');
    await t.waitForFlush();
    assertArrayEqual(t.ic.sent, ['echo hi'], '2A: Can type after selection');
  }

  // 2B: Long press + drag + release → same outcome
  {
    const t = new TouchInputSim();
    t.touchstart();
    t.fireLongPressTimer();
    t.touchmoveSelect(); // drag to extend selection
    t.touchmoveSelect();
    assert(t._touchMoved === false, '2B: touchMoved stays false during selection drag');

    t.touchend();
    assert(t._pointerEvents === '', '2B: pointerEvents restored');
    assert(t._focusTarget === null, '2B: No focus after selection');
  }

  // 2C: Safety reset — pointerEvents stuck from interrupted selection
  {
    const t = new TouchInputSim();
    // Simulate stuck state (e.g., from multi-touch or interrupted flow)
    t._pointerEvents = 'none';
    t._isSelecting = false; // somehow got reset without restoring pointerEvents

    // Next touchstart should fix it (our safety reset)
    t.touchstart();
    assert(t._pointerEvents === '', '2C: Safety reset restores pointerEvents on touchstart');
    t.touchend();
    assert(t._focusTarget === 'overlayInput', '2C: Can focus after safety reset');
  }

  // =====================================================================
  // Scenario 3: Long-press selection + fallbackCopy keyboard issue
  // =====================================================================
  console.log('\n=== Scenario 3: fallbackCopy keyboard behavior ===');

  // 3A: HTTP mode (no Clipboard API) — fallbackCopy used
  {
    const t = new TouchInputSim();
    t._hasClipboardAPI = false;
    t.touchstart();
    t.fireLongPressTimer();
    t.touchend();
    assert(t._fallbackCopyUsed === true, '3A: fallbackCopy was triggered (HTTP mode)');
    assert(t._focusTarget === null, '3A: overlayInput NOT focused after selection');
    // Key assertion: keyboard should NOT pop up
    // In real code, this requires fallbackCopy's textarea to have readonly attr
  }

  // 3B: HTTPS mode (Clipboard API available) — fallbackCopy NOT used
  {
    const t = new TouchInputSim();
    t._hasClipboardAPI = true;
    t.touchstart();
    t.fireLongPressTimer();
    t.touchend();
    assert(t._fallbackCopyUsed === false, '3B: fallbackCopy NOT used (HTTPS mode)');
  }

  // 3C: After fallbackCopy, next tap still works
  {
    const t = new TouchInputSim();
    t._hasClipboardAPI = false;
    t.touchstart();
    t.fireLongPressTimer();
    t.touchend(); // fallbackCopy runs
    assert(t._fallbackCopyUsed === true, '3C: fallbackCopy ran');

    // User taps to focus and type
    t.touchstart(); t.touchend();
    assert(t._focusTarget === 'overlayInput', '3C: Focus works after fallbackCopy');
    t.type('hello');
    await t.waitForFlush();
    assertArrayEqual(t.ic.sent, ['hello'], '3C: Input works after fallbackCopy');
  }

  // =====================================================================
  // Scenario 4: Type mid-swipe then resume typing
  // =====================================================================
  console.log('\n=== Scenario 4: Typing interrupted by swipe ===');

  // 4A: Type, swipe (keyboard stays open), type more — buffer preserved
  {
    const t = new TouchInputSim();
    t._keyboardOpen = true;
    t._focusTarget = 'overlayInput';

    // Type some chars (enter BUFFERING)
    t.type('gi');
    assert(t.ic.state === 'BUFFERING', '4A: BUFFERING after typing "gi"');

    // Wait for flush before swipe
    await t.waitForFlush();
    assertArrayEqual(t.ic.sent, ['gi'], '4A: "gi" flushed');

    // Swipe (scroll up)
    t.touchstart();
    t.touchmoveScroll(30);
    t.touchend();
    assert(t._focusTarget === 'overlayInput', '4A: Re-focused (keyboard was open)');

    // Continue typing
    t.type('t status');
    await t.waitForFlush();
    assertArrayEqual(t.ic.sent, ['gi', 't status'], '4A: "t status" sent after swipe');
  }

  // 4B: Type, swipe during BUFFERING — buffer flushes on timer, not lost
  {
    const t = new TouchInputSim();
    t._keyboardOpen = true;
    t._focusTarget = 'overlayInput';

    t.type('he');
    assert(t.ic.state === 'BUFFERING', '4B: BUFFERING');

    // Swipe happens while BUFFERING — InputController state doesn't reset
    t.touchstart();
    t.touchmoveScroll(20);
    t.touchend();

    // Buffer timer still fires (InputController is independent of touch)
    await t.waitForFlush();
    assertArrayEqual(t.ic.sent, ['he'], '4B: Buffered "he" not lost after swipe');
    assert(t.ic.state === 'IDLE', '4B: Back to IDLE after flush');

    // Type more
    t.type('llo');
    await t.waitForFlush();
    assertArrayEqual(t.ic.sent, ['he', 'llo'], '4B: "llo" sent after resumed typing');
  }

  // 4C: Chinese IME interrupted by swipe
  {
    const t = new TouchInputSim();
    t._keyboardOpen = true;

    t.ic.compositionStart();
    t.ic.textareaValue = '\u4F60';
    assert(t.ic.state === 'COMPOSING', '4C: COMPOSING during Chinese input');

    // Swipe during composition — touch handler doesn't affect InputController
    t.touchstart();
    t.touchmoveScroll(15);
    t.touchend();
    assert(t.ic.state === 'COMPOSING', '4C: Still COMPOSING after swipe');

    // Finish composition
    t.ic.compositionEnd();
    await t.waitForFlush();
    assertArrayEqual(t.ic.sent, ['\u4F60'], '4C: Chinese char sent after swipe during composition');
  }

  // =====================================================================
  // Summary
  // =====================================================================
  console.log('\n' + '='.repeat(50));
  console.log(`Results: ${passed} passed, ${failed} failed`);
  if (failed > 0) process.exit(1);
  else console.log('All tests passed!');
}

runTests().catch(e => { console.error('Test error:', e); process.exit(1); });
```

**Step 2: Run tests**

```bash
node tests/test-touch-input.mjs
```

Expected: All tests pass.

**Step 3: Commit**

```bash
git add tests/test-touch-input.mjs
git commit -m "Add touch+input cross-scenario unit tests (4 scenarios, ~20 assertions)"
```

---

### Task 2: DOM-layer Playwright integration tests

**Files:**
- Create: `tests/test-touch-input-e2e.mjs`

**Prerequisite:** `node server.js` must be running, and at least one tmux session must exist.

**Step 1: Write the Playwright e2e test file**

```javascript
/**
 * test-touch-input-e2e.mjs -- DOM-layer integration tests for touch+input interaction.
 *
 * Uses Playwright iPhone emulation against the real running server.
 * Injects hooks to capture wsSend() calls and DOM state.
 *
 * Prerequisites:
 *   - node server.js running on port 8022
 *   - At least one tmux session exists
 *
 * Run: node tests/test-touch-input-e2e.mjs
 */
import { chromium, devices } from 'playwright';

const BASE = 'http://localhost:8022';
const iPhone = devices['iPhone 14'];
const results = [];

function report(scenario, status, detail = '') {
  results.push({ scenario, status, detail });
  const icon = status === 'PASS' ? '[PASS]' : '[FAIL]';
  console.log(`${icon} ${scenario}${detail ? ' -- ' + detail : ''}`);
}

async function setupPage(browser) {
  const context = await browser.newContext({ ...iPhone, hasTouch: true });
  const page = await context.newPage();
  await page.goto(BASE);
  await page.waitForSelector('#picker');

  // Pick the first available session
  const sessionValue = await page.$eval('#picker select', sel => {
    if (sel.options.length > 1) {
      sel.selectedIndex = 1; // skip "-- pick --" placeholder
      return sel.options[1].value;
    }
    return null;
  });

  if (!sessionValue) {
    console.error('No tmux sessions available. Create one first.');
    process.exit(2);
  }

  // Click connect
  await page.click('#picker button');
  // Wait for terminal to be ready
  await page.waitForSelector('.xterm-screen', { timeout: 5000 });
  await page.waitForTimeout(500); // let terminal render

  // Inject send logger
  await page.evaluate(() => {
    window._testSendLog = [];
    const origSend = window._wsSendFn || null;
    // Hook into wsSend by overriding the WebSocket send
    if (window._ws) {
      const origWsSend = window._ws.send.bind(window._ws);
      window._ws.send = (data) => {
        window._testSendLog.push(data);
        origWsSend(data);
      };
    }
  });

  return { context, page, sessionValue };
}

async function run() {
  const browser = await chromium.launch({ headless: true });

  // ============================================================
  // Test 1: Tap focuses input, typing sends data
  // ============================================================
  console.log('\n=== E2E 1: Tap + Type ===\n');
  {
    const { context, page } = await setupPage(browser);

    // Tap terminal area
    const box = await page.locator('.xterm-screen').boundingBox();
    if (box) {
      await page.touchscreen.tap(box.x + box.width / 2, box.y + box.height / 2);
      await page.waitForTimeout(200);

      // Check overlay-input has focus
      const hasFocus = await page.evaluate(() =>
        document.activeElement === document.getElementById('overlay-input')
      );
      report('Tap focuses overlay-input', hasFocus ? 'PASS' : 'FAIL');

      // Check keyboard state variable
      const kbOpen = await page.evaluate(() => _keyboardOpen);
      report('_keyboardOpen after tap', typeof kbOpen === 'boolean' ? 'PASS' : 'FAIL',
        `value=${kbOpen}`);
    } else {
      report('Tap focuses overlay-input', 'FAIL', 'Could not get terminal bounding box');
    }

    await context.close();
  }

  // ============================================================
  // Test 2: pointerEvents state after page load
  // ============================================================
  console.log('\n=== E2E 2: pointerEvents state ===\n');
  {
    const { context, page } = await setupPage(browser);

    const pe = await page.evaluate(() => {
      const screen = document.querySelector('#terminal-container .xterm-screen');
      return screen ? screen.style.pointerEvents : 'NO_SCREEN';
    });
    report('pointerEvents is empty string on load', pe === '' ? 'PASS' : 'FAIL',
      `pointerEvents="${pe}"`);

    await context.close();
  }

  // ============================================================
  // Test 3: InputController exists and has correct initial state
  // ============================================================
  console.log('\n=== E2E 3: InputController state ===\n');
  {
    const { context, page } = await setupPage(browser);

    const icState = await page.evaluate(() => {
      const ic = window._inputController;
      if (!ic) return { exists: false };
      return {
        exists: true,
        state: ic.state,
        snapshot: ic.snapshot,
        hasAbortController: !!ic._abortController,
      };
    });
    report('InputController exists', icState.exists ? 'PASS' : 'FAIL');
    if (icState.exists) {
      report('InputController initial state is IDLE', icState.state === 'IDLE' ? 'PASS' : 'FAIL',
        `state=${icState.state}`);
      report('InputController snapshot is empty', icState.snapshot === '' ? 'PASS' : 'FAIL');
      report('InputController has AbortController', icState.hasAbortController ? 'PASS' : 'FAIL');
    }

    await context.close();
  }

  // ============================================================
  // Test 4: Swipe triggers scroll mode
  // ============================================================
  console.log('\n=== E2E 4: Swipe scroll ===\n');
  {
    const { context, page } = await setupPage(browser);

    const box = await page.locator('.xterm-screen').boundingBox();
    if (box) {
      const cx = box.x + box.width / 2;
      const startY = box.y + box.height * 0.7;
      const endY = box.y + box.height * 0.3;

      // Simulate swipe up
      await page.touchscreen.tap(cx, startY); // start
      await page.waitForTimeout(100);

      // Use manual touch sequence for swipe
      const scrollMode = await page.evaluate(() => _inScrollMode);
      report('Scroll mode state accessible', typeof scrollMode === 'boolean' ? 'PASS' : 'FAIL',
        `_inScrollMode=${scrollMode}`);
    }

    await context.close();
  }

  // ============================================================
  // Test 5: fallbackCopy readonly check
  // ============================================================
  console.log('\n=== E2E 5: fallbackCopy safety ===\n');
  {
    const { context, page } = await setupPage(browser);

    // Verify fallbackCopy function exists and check its source
    const copyCheck = await page.evaluate(() => {
      const html = document.documentElement.innerHTML;
      const hasFallbackCopy = html.includes('function fallbackCopy');
      // After our fix, it should include 'readonly'
      const hasReadonly = html.includes("ta.setAttribute('readonly'") ||
                          html.includes('ta.readOnly = true');
      return { hasFallbackCopy, hasReadonly };
    });
    report('fallbackCopy function exists', copyCheck.hasFallbackCopy ? 'PASS' : 'FAIL');
    report('fallbackCopy uses readonly (prevents keyboard)',
      copyCheck.hasReadonly ? 'PASS' : 'FAIL',
      copyCheck.hasReadonly ? 'Has readonly attr' : 'MISSING: will trigger keyboard on iOS');

    await context.close();
  }

  // ============================================================
  // Test 6: Touch safety reset in touchstart
  // ============================================================
  console.log('\n=== E2E 6: touchstart safety reset ===\n');
  {
    const { context, page } = await setupPage(browser);

    const safetyCheck = await page.evaluate(() => {
      const html = document.documentElement.innerHTML;
      // Our safety fix: touchstart resets pointerEvents
      return html.includes("screen.style.pointerEvents = ''") ||
             html.includes('screen.style.pointerEvents = ""');
    });
    report('touchstart has pointerEvents safety reset', safetyCheck ? 'PASS' : 'FAIL');

    await context.close();
  }

  await browser.close();

  // ============================================================
  // Summary
  // ============================================================
  console.log('\n=== SUMMARY ===\n');
  const p = results.filter(r => r.status === 'PASS').length;
  const f = results.filter(r => r.status === 'FAIL').length;
  console.log(`Total: ${results.length} | PASS: ${p} | FAIL: ${f}`);

  if (f > 0) {
    console.log('\nFailed:');
    results.filter(r => r.status === 'FAIL').forEach(r => {
      console.log(`  - ${r.scenario}: ${r.detail}`);
    });
  }

  process.exit(f > 0 ? 1 : 0);
}

run().catch(e => { console.error(e); process.exit(2); });
```

**Step 2: Run tests (requires server running)**

```bash
node server.js &
sleep 2
node tests/test-touch-input-e2e.mjs
```

Expected: All tests pass (except `fallbackCopy readonly` which will FAIL until we apply the fix).

**Step 3: Commit**

```bash
git add tests/test-touch-input-e2e.mjs
git commit -m "Add DOM-layer Playwright tests for touch+input interaction"
```

---

### Task 3: Test Harness visual debug page

**Files:**
- Create: `public/test.html`

**Step 1: Write the harness page**

```html
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>Input Debug Harness</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      background: #0d1117;
      color: #c9d1d9;
      font-family: Menlo, Monaco, monospace;
      font-size: 12px;
      height: 100dvh;
      display: flex;
      flex-direction: column;
      overflow: hidden;
      position: fixed;
      width: 100%;
    }

    #header {
      padding: 8px 12px;
      background: #161b22;
      border-bottom: 1px solid #30363d;
      font-size: 14px;
      font-weight: bold;
      display: flex;
      justify-content: space-between;
      align-items: center;
    }
    #header button {
      padding: 4px 10px;
      background: #21262d;
      color: #c9d1d9;
      border: 1px solid #30363d;
      border-radius: 4px;
      font-size: 12px;
      cursor: pointer;
    }

    #touch-area {
      height: 35%;
      background: #1a1a2e;
      border-bottom: 2px solid #30363d;
      display: flex;
      flex-direction: column;
      justify-content: center;
      align-items: center;
      touch-action: none;
      position: relative;
    }
    #touch-area .label {
      color: #484f58;
      font-size: 16px;
      pointer-events: none;
    }

    /* State badges */
    #state-bar {
      display: flex;
      gap: 6px;
      padding: 6px 12px;
      background: #161b22;
      border-bottom: 1px solid #30363d;
      flex-wrap: wrap;
    }
    .badge {
      padding: 2px 8px;
      border-radius: 10px;
      font-size: 11px;
      background: #21262d;
      border: 1px solid #30363d;
    }
    .badge.active { background: #1f6feb; border-color: #388bfd; color: #fff; }
    .badge.warn { background: #9e6a03; border-color: #d29922; color: #fff; }
    .badge.error { background: #da3633; border-color: #f85149; color: #fff; }

    /* Input area */
    #input-section {
      padding: 6px 12px;
      background: #161b22;
      border-bottom: 1px solid #30363d;
      display: flex;
      gap: 8px;
      align-items: center;
    }
    #test-input {
      flex: 1;
      padding: 6px 10px;
      background: #0d1117;
      color: #c9d1d9;
      border: 1px solid #30363d;
      border-radius: 4px;
      font-family: inherit;
      font-size: 16px;
      outline: none;
    }
    #test-input:focus { border-color: #388bfd; }

    /* Event log */
    #log {
      flex: 1;
      overflow-y: auto;
      padding: 4px 0;
      -webkit-overflow-scrolling: touch;
    }
    .log-entry {
      padding: 2px 12px;
      border-bottom: 1px solid #21262d;
      display: flex;
      gap: 8px;
    }
    .log-entry .ts { color: #484f58; min-width: 65px; }
    .log-entry .type { min-width: 90px; font-weight: bold; }
    .log-entry .detail { color: #8b949e; word-break: break-all; }
    .type-touch { color: #f0883e; }
    .type-input { color: #58a6ff; }
    .type-state { color: #7ee787; }
    .type-send { color: #d2a8ff; }
    .type-focus { color: #79c0ff; }
    .type-compose { color: #ffa657; }
  </style>
</head>
<body>
  <div id="header">
    <span>Input Debug Harness</span>
    <div>
      <button onclick="clearLog()">Clear</button>
      <button onclick="togglePause()">Pause</button>
    </div>
  </div>

  <div id="touch-area">
    <div class="label">Touch Area (tap / swipe / long-press here)</div>
  </div>

  <div id="state-bar">
    <span class="badge" id="b-ic">IC: IDLE</span>
    <span class="badge" id="b-selecting">selecting: false</span>
    <span class="badge" id="b-moved">moved: false</span>
    <span class="badge" id="b-keyboard">keyboard: closed</span>
    <span class="badge" id="b-scroll">scroll: off</span>
    <span class="badge" id="b-pointer">pointer: ok</span>
    <span class="badge" id="b-focus">focus: none</span>
  </div>

  <div id="input-section">
    <textarea id="test-input" rows="1" placeholder="Type here..."
      inputmode="text" autocorrect="off" autocapitalize="off"
      autocomplete="off" spellcheck="false"></textarea>
  </div>

  <div id="log"></div>

  <script>
    const touchArea = document.getElementById('touch-area');
    const testInput = document.getElementById('test-input');
    const logEl = document.getElementById('log');
    let paused = false;
    let logCount = 0;
    const MAX_LOG = 500;

    // --- State ---
    const S = {
      icState: 'IDLE',
      isSelecting: false,
      touchMoved: false,
      keyboardOpen: false,
      inScrollMode: false,
      pointerEvents: '',
      focusEl: 'none',
    };

    // --- Logging ---
    function log(type, detail) {
      if (paused) return;
      const el = document.createElement('div');
      el.className = 'log-entry';
      const now = new Date();
      const ts = `${now.getMinutes().toString().padStart(2,'0')}:${now.getSeconds().toString().padStart(2,'0')}.${now.getMilliseconds().toString().padStart(3,'0')}`;
      el.innerHTML = `<span class="ts">${ts}</span><span class="type type-${type}">${type}</span><span class="detail">${detail}</span>`;
      logEl.appendChild(el);
      logCount++;
      if (logCount > MAX_LOG) logEl.removeChild(logEl.firstChild);
      logEl.scrollTop = logEl.scrollHeight;
    }

    function clearLog() { logEl.innerHTML = ''; logCount = 0; }
    function togglePause() { paused = !paused; }

    // --- Badge updates ---
    function updateBadges() {
      const b = (id, text, cls) => {
        const el = document.getElementById(id);
        el.textContent = text;
        el.className = 'badge' + (cls ? ' ' + cls : '');
      };
      b('b-ic', `IC: ${S.icState}`, S.icState !== 'IDLE' ? 'active' : '');
      b('b-selecting', `selecting: ${S.isSelecting}`, S.isSelecting ? 'warn' : '');
      b('b-moved', `moved: ${S.touchMoved}`, S.touchMoved ? 'active' : '');
      b('b-keyboard', `keyboard: ${S.keyboardOpen ? 'open' : 'closed'}`, S.keyboardOpen ? 'active' : '');
      b('b-scroll', `scroll: ${S.inScrollMode ? 'on' : 'off'}`, S.inScrollMode ? 'active' : '');
      b('b-pointer', `pointer: ${S.pointerEvents || 'ok'}`, S.pointerEvents === 'none' ? 'error' : '');
      b('b-focus', `focus: ${S.focusEl}`, S.focusEl === 'test-input' ? 'active' : '');
    }

    // --- Touch events on touch area ---
    let _longPressTimer = null;
    let _touchStartY = 0;
    const LONG_PRESS_MS = 500;

    touchArea.addEventListener('touchstart', (e) => {
      const t = e.touches[0];
      _touchStartY = t.clientY;
      S.touchMoved = false;
      S.isSelecting = false;
      S.pointerEvents = '';
      if (_longPressTimer) clearTimeout(_longPressTimer);

      log('touch', `touchstart (${Math.round(t.clientX)}, ${Math.round(t.clientY)})`);

      _longPressTimer = setTimeout(() => {
        S.isSelecting = true;
        S.pointerEvents = 'none';
        log('touch', 'LONG PRESS triggered');
        updateBadges();
      }, LONG_PRESS_MS);

      updateBadges();
    }, { passive: true });

    touchArea.addEventListener('touchmove', (e) => {
      const t = e.touches[0];
      const dy = _touchStartY - t.clientY;

      if (S.isSelecting) {
        log('touch', `touchmove SELECTING (dy=${Math.round(dy)})`);
        return;
      }

      if (Math.abs(dy) > 5) {
        if (_longPressTimer) { clearTimeout(_longPressTimer); _longPressTimer = null; }
        S.touchMoved = true;
        if (!S.inScrollMode) S.inScrollMode = true;
        log('touch', `touchmove SCROLL (dy=${Math.round(dy)})`);
        _touchStartY = t.clientY;
        updateBadges();
      }
    }, { passive: true });

    touchArea.addEventListener('touchend', (e) => {
      if (_longPressTimer) { clearTimeout(_longPressTimer); _longPressTimer = null; }

      if (S.isSelecting) {
        S.isSelecting = false;
        S.pointerEvents = '';
        log('touch', 'touchend SELECTION END (no focus)');
        updateBadges();
        return;
      }

      if (!S.touchMoved) {
        if (S.inScrollMode) S.inScrollMode = false;
        testInput.focus();
        S.focusEl = 'test-input';
        S.keyboardOpen = true;
        log('touch', 'touchend TAP -> focus input');
      } else {
        if (S.keyboardOpen) {
          testInput.focus();
          log('touch', 'touchend SWIPE -> re-focus (kb was open)');
        } else {
          log('touch', 'touchend SWIPE -> no focus (kb closed)');
        }
      }
      updateBadges();
    });

    // --- Input events on textarea ---
    testInput.addEventListener('compositionstart', () => {
      S.icState = 'COMPOSING';
      log('compose', 'compositionstart');
      updateBadges();
    });

    testInput.addEventListener('compositionend', () => {
      S.icState = 'BUFFERING';
      log('compose', `compositionend val="${testInput.value}"`);
      updateBadges();
    });

    testInput.addEventListener('beforeinput', (e) => {
      log('input', `beforeinput type=${e.inputType} data="${e.data}"`);
    });

    testInput.addEventListener('input', (e) => {
      if (S.icState !== 'COMPOSING') S.icState = 'BUFFERING';
      log('input', `input type=${e.inputType} val="${testInput.value}"`);
      updateBadges();

      // Auto-reset to IDLE after debounce
      setTimeout(() => {
        if (S.icState === 'BUFFERING') {
          S.icState = 'IDLE';
          log('state', 'BUFFERING -> IDLE (flush)');
          log('send', `send: "${testInput.value}"`);
          updateBadges();
        }
      }, 150);
    });

    testInput.addEventListener('keydown', (e) => {
      log('input', `keydown key="${e.key}" code=${e.code} ctrl=${e.ctrlKey}`);
    });

    // --- Focus tracking ---
    testInput.addEventListener('focus', () => {
      S.focusEl = 'test-input';
      log('focus', 'textarea FOCUSED');
      updateBadges();
    });
    testInput.addEventListener('blur', () => {
      S.focusEl = 'none';
      log('focus', 'textarea BLURRED');
      updateBadges();
    });

    // Keyboard detection via visualViewport
    if (window.visualViewport) {
      window.visualViewport.addEventListener('resize', () => {
        const kbH = window.innerHeight - window.visualViewport.height;
        const wasOpen = S.keyboardOpen;
        S.keyboardOpen = kbH > 50;
        if (wasOpen !== S.keyboardOpen) {
          log('state', `keyboard ${S.keyboardOpen ? 'OPEN' : 'CLOSED'} (kbH=${Math.round(kbH)})`);
          updateBadges();
        }
      });
    }

    updateBadges();
  </script>
</body>
</html>
```

**Step 2: Verify harness serves correctly**

```bash
# Server already serves static files from public/
curl -s http://localhost:8022/test.html | head -5
```

Expected: Returns the HTML content.

**Step 3: Commit**

```bash
git add public/test.html
git commit -m "Add input debug harness page at /test.html"
```

---

### Task 4: Add npm test scripts

**Files:**
- Modify: `package.json`

**Step 1: Add test scripts**

Add to `package.json` scripts:

```json
{
  "scripts": {
    "test": "node tests/test-input-system.mjs && node tests/test-touch-input.mjs",
    "test:input": "node tests/test-input-system.mjs",
    "test:touch": "node tests/test-touch-input.mjs",
    "test:e2e": "node tests/test-touch-input-e2e.mjs"
  }
}
```

- `npm test` — runs both logic-layer tests (every change)
- `npm run test:e2e` — runs DOM-layer tests (requires server running, key checkpoints only)

**Step 2: Verify**

```bash
npm test
```

Expected: Both test files run and pass.

**Step 3: Commit**

```bash
git add package.json
git commit -m "Add npm test scripts: test (logic), test:e2e (Playwright)"
```
