/**
 * test-touch-input-e2e.mjs
 *
 * Playwright-based DOM-layer integration test for mobile touch+input interaction.
 * Uses iPhone 14 emulation against the real server at http://localhost:8022.
 *
 * Prerequisites:
 *   - Server running: node server.js
 *   - At least one active tmux session
 *   - Playwright installed: npm i playwright
 *
 * Run:
 *   node tests/test-touch-input-e2e.mjs
 */

import { chromium, devices } from 'playwright';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------
const BASE = 'http://localhost:8022';
const iPhone = devices['iPhone 14'];

// ---------------------------------------------------------------------------
// Reporting
// ---------------------------------------------------------------------------
let passCount = 0;
let failCount = 0;

function report(pass, scenario, detail = '') {
  if (pass) {
    passCount++;
    console.log(`  PASS  ${scenario}${detail ? ' — ' + detail : ''}`);
  } else {
    failCount++;
    console.log(`  FAIL  ${scenario}${detail ? ' — ' + detail : ''}`);
  }
}

// ---------------------------------------------------------------------------
// setupPage helper
// ---------------------------------------------------------------------------
async function setupPage(browser) {
  const context = await browser.newContext({
    ...iPhone,
    hasTouch: true,
  });
  const page = await context.newPage();

  // Navigate and wait for the session picker
  await page.goto(BASE);
  await page.waitForSelector('#picker');

  // Pick the first available tmux session (skip placeholder option)
  const sessionValue = await page.evaluate(() => {
    const select = document.querySelector('#picker');
    for (const opt of select.options) {
      if (opt.value && opt.value !== '' && !opt.disabled) {
        select.value = opt.value;
        return opt.value;
      }
    }
    return null;
  });

  if (!sessionValue) {
    throw new Error('No tmux session available in #picker');
  }

  // Click the connect button
  const connectBtn = await page.$('button#connectBtn') || await page.$('button');
  await connectBtn.click();

  // Wait for terminal to render
  await page.waitForSelector('.xterm-screen');
  await page.waitForTimeout(500);

  // Inject send logger — hooks window._ws.send to capture outgoing data
  await page.evaluate(() => {
    window._testSendLog = [];
    if (window._ws && typeof window._ws.send === 'function') {
      const origSend = window._ws.send.bind(window._ws);
      window._ws.send = (data) => {
        window._testSendLog.push(data);
        return origSend(data);
      };
    }
  });

  return { context, page, sessionValue };
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
(async () => {
  console.log('Launching Playwright (iPhone 14 emulation)…\n');
  const browser = await chromium.launch({ headless: true });

  let context, page, sessionValue;
  try {
    ({ context, page, sessionValue } = await setupPage(browser));
    console.log(`Connected to session: ${sessionValue}\n`);
  } catch (err) {
    console.error('Setup failed:', err.message);
    process.exit(1);
  }

  // -----------------------------------------------------------------------
  // E2E 1: Tap + Type
  // -----------------------------------------------------------------------
  console.log('E2E 1: Tap + Type');
  try {
    const box = await page.locator('.xterm-screen').boundingBox();
    await page.touchscreen.tap(box.x + box.width / 2, box.y + box.height / 2);
    await page.waitForTimeout(200);

    const activeIsOverlay = await page.evaluate(() => {
      const el = document.activeElement;
      return el && (el.id === 'overlay-input' || el.classList.contains('overlay-input'));
    });
    report(activeIsOverlay, 'Tap focuses overlay-input');

    const kbAccessible = await page.evaluate(() => typeof window._keyboardOpen !== 'undefined');
    report(kbAccessible, '_keyboardOpen is accessible');
  } catch (err) {
    report(false, 'Tap + Type', err.message);
  }

  // -----------------------------------------------------------------------
  // E2E 2: pointerEvents state
  // -----------------------------------------------------------------------
  console.log('\nE2E 2: pointerEvents state');
  try {
    const pe = await page.evaluate(() => {
      const screen = document.querySelector('.xterm-screen');
      return screen ? screen.style.pointerEvents : null;
    });
    report(pe === '', 'pointerEvents is empty string on load', `got "${pe}"`);
  } catch (err) {
    report(false, 'pointerEvents state', err.message);
  }

  // -----------------------------------------------------------------------
  // E2E 3: InputController state
  // -----------------------------------------------------------------------
  console.log('\nE2E 3: InputController state');
  try {
    const exists = await page.evaluate(() => !!window._inputController);
    report(exists, 'window._inputController exists');

    if (exists) {
      const state = await page.evaluate(() => window._inputController.state);
      report(state === 'IDLE', 'Initial state is IDLE', `got "${state}"`);

      const snapshotEmpty = await page.evaluate(() => window._inputController.snapshot === '');
      report(snapshotEmpty, 'Initial snapshot is empty');

      const hasAbort = await page.evaluate(() =>
        window._inputController._abortController instanceof AbortController
        || window._inputController.abortController instanceof AbortController
      );
      report(hasAbort, 'Has AbortController');
    } else {
      report(false, 'Initial state is IDLE', 'controller missing');
      report(false, 'Initial snapshot is empty', 'controller missing');
      report(false, 'Has AbortController', 'controller missing');
    }
  } catch (err) {
    report(false, 'InputController state', err.message);
  }

  // -----------------------------------------------------------------------
  // E2E 4: Swipe scroll
  // -----------------------------------------------------------------------
  console.log('\nE2E 4: Swipe scroll');
  try {
    const box = await page.locator('.xterm-screen').boundingBox();
    report(!!box, '.xterm-screen bounding box obtained', `${box.width}x${box.height}`);

    const scrollModeType = await page.evaluate(() => typeof window._inScrollMode);
    report(scrollModeType === 'boolean', '_inScrollMode is accessible (boolean)', `typeof = ${scrollModeType}`);
  } catch (err) {
    report(false, 'Swipe scroll', err.message);
  }

  // -----------------------------------------------------------------------
  // E2E 5: fallbackCopy safety
  // -----------------------------------------------------------------------
  console.log('\nE2E 5: fallbackCopy safety');
  try {
    const html = await page.content();

    const hasFallbackCopy = html.includes('function fallbackCopy');
    report(hasFallbackCopy, 'HTML contains "function fallbackCopy"');

    const hasReadonly = html.includes("ta.setAttribute('readonly'")
      || html.includes('ta.setAttribute("readonly"')
      || html.includes('ta.readOnly = true')
      || html.includes('ta.readOnly=true');
    report(hasReadonly, 'fallbackCopy textarea has readonly attribute (may FAIL until fix applied)');
  } catch (err) {
    report(false, 'fallbackCopy safety', err.message);
  }

  // -----------------------------------------------------------------------
  // E2E 6: touchstart safety reset
  // -----------------------------------------------------------------------
  console.log('\nE2E 6: touchstart safety reset');
  try {
    const html = await page.content();

    const hasPointerReset = html.includes("screen.style.pointerEvents = ''")
      || html.includes('screen.style.pointerEvents = ""')
      || html.includes("screen.style.pointerEvents=''")
      || html.includes('screen.style.pointerEvents=""');
    report(hasPointerReset, 'HTML contains pointerEvents safety reset code');
  } catch (err) {
    report(false, 'touchstart safety reset', err.message);
  }

  // -----------------------------------------------------------------------
  // Summary
  // -----------------------------------------------------------------------
  console.log('\n' + '='.repeat(50));
  console.log(`Summary: ${passCount} PASS, ${failCount} FAIL (total ${passCount + failCount})`);
  console.log('='.repeat(50));

  await context.close();
  await browser.close();

  process.exit(failCount > 0 ? 1 : 0);
})();
