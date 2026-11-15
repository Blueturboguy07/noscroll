/**
 * Live smoke tests — the thing that turns selector rot from "a user eventually
 * complains" into "an alert fires within one cycle".
 *
 * Runs the REAL engine bundle against the REAL Instagram and YouTube, in a
 * mobile viewport, on a schedule (see .github/workflows/probe.yml). Golden-DOM
 * tests in engine/test/ prove the rules work against captured structure; these
 * prove they still work against what the platforms are shipping today.
 *
 * Logged-out coverage runs anywhere with no secrets. Logged-in coverage runs
 * only when PROBE_IG_STATE / PROBE_YT_STATE point at saved storage states —
 * never commit those, and use dedicated probe accounts, never a personal one.
 */

import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { expect, test, type Page } from '@playwright/test';

const ROOT = join(import.meta.dirname, '..');
// NOSCROLL_ENGINE: the engine file to test, relative to the repo root. CI points it at the copy the
// iOS app ships (ios/NoScroll/Resources/noscroll.js); the default is a fresh engine build.
const ENGINE = readFileSync(join(ROOT, process.env.NOSCROLL_ENGINE ?? 'engine/dist/noscroll.js'), 'utf8');

function bundle(service: string): string {
  return readFileSync(join(ROOT, `rules/${service}.json`), 'utf8');
}

/** Inject exactly what the shells inject, at document start. */
async function installEngine(page: Page, service: string, settings: Record<string, boolean> = {}): Promise<void> {
  await page.addInitScript({
    content: `
      window.__NOSCROLL_CONFIG = {
        bundle: ${bundle(service)},
        settings: ${JSON.stringify(settings)},
        telemetry: true
      };
      ${ENGINE}
    `,
  });
}

interface ProbeResult {
  ruleId: string;
  expected: number;
  actual: number;
  onlyWhenSignedIn: boolean;
}

async function probes(page: Page): Promise<ProbeResult[]> {
  return page.evaluate(() => (window as any).NoScroll?.probes?.() ?? []);
}

/**
 * Rules whose expectMin > 0 must have matched something.
 *
 * Rules flagged `onlyWhenSignedIn` are skipped without a session: the surface
 * genuinely is not on the page. Logged-out m.youtube.com renders three pivot-bar
 * items and no Shorts tab, so asserting a match there would fail forever and
 * teach everyone to ignore the probe.
 */
function assertNoRot(results: ProbeResult[], context: string, signedIn = false): void {
  const applicable = signedIn ? results : results.filter((r) => !r.onlyWhenSignedIn);
  const rotted = applicable.filter((r) => r.expected > 0 && r.actual === 0);
  expect(rotted, `selector rot in ${context}: ${JSON.stringify(rotted)}`).toEqual([]);
}

test.describe('YouTube', () => {
  test.beforeEach(async ({ page }) => {
    await installEngine(page, 'youtube');
  });

  /**
   * The Shorts tab, found by what a person sees (its title), not by our selectors: if the site
   * renames a class, this still sees the tab. Also returns the tab bar for the log, as proof of
   * what the live page drew.
   */
  async function tabBar(page: Page): Promise<Array<{ title: string; cls: string; visible: boolean }>> {
    return page.evaluate(() =>
      [...document.querySelectorAll('ytm-pivot-bar-item-renderer')].map((el) => {
        const r = (el as HTMLElement).getBoundingClientRect();
        const style = getComputedStyle(el as HTMLElement);
        return {
          title: (el.textContent ?? '').replace(/\s+/g, ' ').trim(),
          cls: el.querySelector('.pivot-bar-item-tab')?.className ?? '',
          visible: el.isConnected && r.width > 0 && r.height > 0 && style.display !== 'none' && style.visibility !== 'hidden',
        };
      }),
    );
  }

  async function waitForTabBar(page: Page): Promise<boolean> {
    try {
      await page.waitForSelector('ytm-pivot-bar-item-renderer', { state: 'attached', timeout: 20_000 });
      await page.waitForTimeout(2500); // the bar is redrawn when the page data arrives
      return true;
    } catch {
      return false;
    }
  }

  async function leavesShorts(page: Page, timeout = 15_000): Promise<string> {
    await page.waitForURL((u) => !u.pathname.startsWith('/shorts'), { timeout });
    return new URL(page.url()).pathname;
  }

  test('the live page has a Shorts tab, and the engine removes it', async ({ page, context }) => {
    // Control: the same page with NO engine (init scripts are per page).
    const control = await context.newPage();
    await control.goto('https://m.youtube.com/', { waitUntil: 'domcontentloaded' });
    const controlBar = (await waitForTabBar(control)) ? await tabBar(control) : [];
    await control.close();
    console.log(`youtube control tab bar: ${JSON.stringify(controlBar)}`);
    const controlHasShorts = controlBar.some((t) => t.title === 'Shorts' && t.visible);

    await page.goto('https://m.youtube.com/', { waitUntil: 'domcontentloaded' });
    expect(await waitForTabBar(page), 'm.youtube.com drew no tab bar: the probe cannot check the Shorts tab').toBe(true);
    const bar = await tabBar(page);
    const nav = (await probes(page)).find((p) => p.ruleId === 'youtube.shorts-nav');
    console.log(`youtube tab bar with the engine: ${JSON.stringify(bar)}; shorts-nav removed ${nav?.actual ?? 0}`);

    expect(bar.filter((t) => t.title === 'Shorts' && t.visible), 'a Shorts tab is still visible').toEqual([]);
    expect(bar.some((t) => t.visible), 'the other tabs must stay').toBe(true);
    if (controlHasShorts) {
      expect(nav?.actual ?? 0, 'the Remove Shorts tab rule matched nothing on a page that has the tab').toBeGreaterThan(0);
    } else {
      test.info().annotations.push({ type: 'note', description: 'the control page drew no Shorts tab today' });
    }
  });

  test('the Shorts tab address (/shorts/, no video id) goes home', async ({ page }) => {
    await page.goto('https://m.youtube.com/shorts/', { waitUntil: 'domcontentloaded' });
    expect(await leavesShorts(page)).toBe('/');
  });

  test('a Short address (/shorts/<id>) does not stay on Shorts', async ({ page }) => {
    // The server sends an id that is not a Short to /watch (303); a real Short loads at /shorts/<id>
    // and the engine sends it home. Either way the page must leave /shorts.
    await page.goto('https://m.youtube.com/shorts/dQw4w9WgXcQ', { waitUntil: 'domcontentloaded' });
    expect(await leavesShorts(page)).not.toMatch(/^\/shorts/);
  });

  test('an in-page move to /shorts/ (pushState) goes home', async ({ page }) => {
    await page.goto('https://m.youtube.com/', { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(2000);
    await page.evaluate(() => history.pushState({}, '', '/shorts/'));
    expect(await leavesShorts(page, 10_000)).toBe('/');

    // The same through the prototype, which skips a patched history object.
    await page.waitForTimeout(2000);
    await page.evaluate(() => History.prototype.pushState.call(history, {}, '', '/shorts/dQw4w9WgXcQ'));
    expect(await leavesShorts(page, 10_000)).toBe('/');
  });

  test('a tap on the Shorts tab does not open Shorts', async ({ context }) => {
    // Show the tab on purpose (Remove Shorts tab off), so the tap itself can be tested.
    const page = await context.newPage();
    await installEngine(page, 'youtube', { 'youtube.shorts-nav': false });
    await page.goto('https://m.youtube.com/', { waitUntil: 'domcontentloaded' });
    const drawn = await waitForTabBar(page);
    const tab = page.locator('ytm-pivot-bar-item-renderer', { hasText: /^\s*Shorts\s*$/ });
    test.skip(!drawn || (await tab.count()) === 0, 'the live page drew no Shorts tab to tap today');
    await tab.first().click();
    await page.waitForTimeout(4000);
    expect(new URL(page.url()).pathname, 'the tap opened a Shorts page').not.toMatch(/^\/shorts/);
  });

  test('home has no Shorts shelf link', async ({ page }) => {
    await page.goto('https://m.youtube.com/', { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(4000);

    const shortsLinks = await page.locator("a[href^='/shorts']").evaluateAll(
      (els) => els.filter((e) => (e as HTMLElement).getBoundingClientRect().height > 0).length,
    );
    expect(shortsLinks, 'a visible /shorts link survived on the home feed').toBe(0);

    assertNoRot(await probes(page), 'youtube home');
  });

  test('the engine reports ready', async ({ page }) => {
    await page.goto('https://m.youtube.com/', { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(2000);
    const version = await page.evaluate(() => (window as any).NoScroll?.version);
    expect(version).toBe(1);
  });
});

test.describe('Instagram', () => {
  test.beforeEach(async ({ page }) => {
    await installEngine(page, 'instagram');
  });

  /**
   * Regression: at document-start `document.documentElement` and `document.head`
   * are BOTH null. The engine used to throw on its first action and die
   * silently, blocking nothing — on both iOS and Android, since both inject at
   * document-start. A test DOM always has a documentElement, so only a real
   * browser can catch this.
   */
  test('the engine survives document-start injection and installs its CSS', async ({ page }) => {
    const errors: string[] = [];
    page.on('pageerror', (e) => errors.push(e.message));

    await page.goto('https://www.instagram.com/', { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(3000);

    expect(errors, 'the engine must not throw at document-start').toEqual([]);
    // A signed-out runner often gets the login form at "/": a page with a password field is a
    // sign-in page, and there the engine must be inert (no CSS at all).
    const signInPage = (await page.locator("input[type='password']").count()) > 0;
    await expect(page.locator('#noscroll-css')).toHaveCount(signInPage ? 0 : 1);
  });

  test('the engine is INERT on the login page', async ({ page, context }) => {
    // The invariant, verified against the real page: on an auth surface nothing
    // is injected, nothing is removed, and the password field is untouched.
    const LOGIN = 'https://www.instagram.com/accounts/login/';
    await page.goto(LOGIN, { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(3000);

    const styleInjected = await page.locator('#noscroll-css').count();
    expect(styleInjected, 'blocking CSS must never be injected on an auth surface').toBe(0);

    const passwordField = await page.locator("input[type='password']").count();
    if (passwordField === 0) {
      // Instagram does not always serve the login form to a headless browser on
      // a datacenter IP. Load the same URL in a control page that has NO engine
      // (init scripts are per-page, so a sibling page in this context is clean).
      // Form missing there too: the platform withheld it and there is nothing
      // to assert. Form present there but not here: the engine removed it,
      // which is the exact regression this test exists to catch.
      const control = await context.newPage();
      await control.goto(LOGIN, { waitUntil: 'domcontentloaded' });
      await control.waitForTimeout(3000);
      const controlField = await control.locator("input[type='password']").count();
      const landed = `${control.url()} (${await control.title()})`;
      await control.close();
      test.skip(controlField === 0, `Instagram did not serve the login form to this runner; it landed on ${landed}`);
    }
    expect(passwordField, 'the login form must be intact').toBeGreaterThan(0);
  });

  test('reels routes redirect away', async ({ page }) => {
    await page.goto('https://www.instagram.com/reels/', { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(3000);
    expect(page.url()).not.toContain('/reels');
  });

  const igState = process.env.PROBE_IG_STATE;
  test.describe('logged in', () => {
    test.skip(!igState || !existsSync(igState ?? ''), 'set PROBE_IG_STATE to a saved storage state');
    test.use({ storageState: igState });

    test('feed has no Reels tab and no suggested posts', async ({ page }) => {
      await page.goto('https://www.instagram.com/', { waitUntil: 'domcontentloaded' });
      await page.waitForTimeout(5000);

      expect(await page.locator("nav a[href^='/reels']").count()).toBe(0);
      expect(await page.locator("[aria-label='Suggested for you']").count()).toBe(0);

      assertNoRot(await probes(page), 'instagram feed', true);
    });
  });
});
