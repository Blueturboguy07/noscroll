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
const ENGINE = readFileSync(join(ROOT, 'engine/dist/noscroll.js'), 'utf8');

function bundle(service: string): string {
  return readFileSync(join(ROOT, `rules/${service}.json`), 'utf8');
}

/** Inject exactly what the shells inject, at document start. */
async function installEngine(page: Page, service: string): Promise<void> {
  await page.addInitScript({
    content: `
      window.__NOSCROLL_CONFIG = {
        bundle: ${bundle(service)},
        settings: {},
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

  test('the /shorts -> /watch rewrite lands on the same video', async ({ page }) => {
    // A stable, long-lived Short would be ideal; instead assert the mechanism:
    // any /shorts/<id> must end up on /watch?v=<id>.
    await page.goto('https://m.youtube.com/shorts/dQw4w9WgXcQ', { waitUntil: 'domcontentloaded' });
    await page.waitForURL(/\/watch\?v=dQw4w9WgXcQ/, { timeout: 15_000 });
    expect(page.url()).toContain('/watch?v=dQw4w9WgXcQ');
  });

  test('home has no Shorts shelf and no Shorts tab', async ({ page }) => {
    await page.goto('https://m.youtube.com/', { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(4000);

    const shortsLinks = await page.locator("a[href^='/shorts']").count();
    expect(shortsLinks, 'a /shorts link survived on the home feed').toBe(0);

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
    await expect(page.locator('#noscroll-css')).toHaveCount(1);
  });

  test('the engine is INERT on the login page', async ({ page }) => {
    // The invariant, verified against the real page: on an auth surface nothing
    // is injected, nothing is removed, and the password field is untouched.
    await page.goto('https://www.instagram.com/accounts/login/', {
      waitUntil: 'domcontentloaded',
    });
    await page.waitForTimeout(3000);

    const styleInjected = await page.locator('#noscroll-css').count();
    expect(styleInjected, 'blocking CSS must never be injected on an auth surface').toBe(0);

    const passwordField = await page.locator("input[type='password']").count();
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
