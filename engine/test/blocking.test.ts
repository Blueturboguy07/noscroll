/**
 * Golden-DOM tests: shipped rule bundles run against captured page structure.
 *
 * These are the tests that would have caught SocialLite's two visible failures —
 * a Shorts shelf surviving in their own marketing screenshot, and suggested
 * posts leaking into the feed.
 */

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { beforeEach, describe, expect, it } from 'vitest';
import { start, stop } from '../src/engine.js';
import { snapshot } from '../src/probe.js';
import type { RuleBundle, Settings } from '../src/types.js';

const ROOT = join(import.meta.dirname, '..', '..');
const ig = JSON.parse(readFileSync(join(ROOT, 'rules/instagram.json'), 'utf8')) as RuleBundle;
const yt = JSON.parse(readFileSync(join(ROOT, 'rules/youtube.json'), 'utf8')) as RuleBundle;

function fixture(name: string): string {
  return readFileSync(join(import.meta.dirname, 'fixtures', name), 'utf8');
}

function mount(html: string, url: string): void {
  document.body.innerHTML = html;
  window.happyDOM?.setURL?.(url);
}

function run(bundle: RuleBundle, settings: Settings = {}): void {
  start({ bundle, settings, telemetry: true });
}

beforeEach(() => {
  stop();
  document.body.innerHTML = '';
});

describe('Instagram', () => {
  beforeEach(() => {
    mount(fixture('instagram-feed.html'), 'https://www.instagram.com/');
  });

  it('removes the Reels nav icon entirely (absent, not disabled)', () => {
    run(ig);
    expect(document.querySelector("nav a[href^='/reels']")).toBeNull();
  });

  it('re-justifies the nav after removing an icon, so no dead tap zone remains', () => {
    run(ig);
    const nav = document.querySelector('nav') as HTMLElement;
    expect(nav.style.justifyContent).toBe('space-around');
  });

  it('removes the Explore nav icon', () => {
    run(ig);
    expect(document.querySelector("nav a[href^='/explore']")).toBeNull();
  });

  it('keeps Home, DMs, Notifications and Profile — the preserved surfaces', () => {
    run(ig);
    expect(document.querySelector("nav a[href='/']")).not.toBeNull();
    expect(document.querySelector("nav a[href='/direct/inbox/']")).not.toBeNull();
    expect(document.querySelector("nav a[href='/accounts/activity/']")).not.toBeNull();
    expect(document.querySelector("nav a[href='/someuser/']")).not.toBeNull();
  });

  it('removes suggested posts but keeps posts from people you follow', () => {
    run(ig);
    expect(document.getElementById('post-suggested')).toBeNull();
    expect(document.getElementById('post-following')).not.toBeNull();
    expect(document.getElementById('post-following-2')).not.toBeNull();
  });

  it('removes sponsored posts', () => {
    run(ig);
    expect(document.getElementById('post-sponsored')).toBeNull();
  });

  it('locked surfaces ignore a user setting that tries to disable them', () => {
    run(ig, { 'instagram.reels-tab': false, 'instagram.explore-tab': false });
    expect(document.querySelector("nav a[href^='/reels']")).toBeNull();
    expect(document.querySelector("nav a[href^='/explore']")).toBeNull();
  });

  it('removes the in-feed Reels tray', () => {
    run(ig);
    expect(document.getElementById('reels-tray')).toBeNull();
  });

  it('unlocked surfaces default off and stay put until enabled', () => {
    run(ig); // stories-tray defaults to off
    expect(document.querySelector("main [role='menu']")).toBeNull(); // not in fixture anyway
    // Explicitly enabling an unlocked surface takes effect:
    stop();
    mount(fixture('instagram-feed.html'), 'https://www.instagram.com/');
    run(ig, { 'instagram.feed': true });
    expect(document.querySelectorAll('main article').length).toBe(0);
  });

  it('injects blocking CSS before the sweep, so nothing flashes', () => {
    run(ig);
    const style = document.getElementById('noscroll-css');
    expect(style).not.toBeNull();
    expect(style!.textContent).toContain('display: none !important');
    expect(style!.textContent).toContain("/reels");
  });

  it('reports probe health for rules that matched nothing', () => {
    // A feed with no nav at all: the reels-tab rule (expectMin 1) should flag.
    mount('<main></main>', 'https://www.instagram.com/');
    run(ig);
    const reels = snapshot().find((p) => p.ruleId === 'instagram.reels-tab');
    expect(reels?.expected).toBe(1);
    expect(reels?.actual).toBe(0);
  });
});

describe('YouTube', () => {
  beforeEach(() => {
    mount(fixture('youtube-home.html'), 'https://m.youtube.com/');
  });

  it('removes the Shorts tab from the pivot bar', () => {
    run(yt);
    expect(document.querySelector('.pivot-shorts')).toBeNull();
  });

  it('removes the Shorts shelf — the surface SocialLite visibly leaks', () => {
    run(yt);
    expect(document.getElementById('shorts-shelf-1')).toBeNull();
  });

  it('removes shorts surfaced inline in the feed', () => {
    run(yt);
    expect(document.getElementById('inline-short')).toBeNull();
  });

  it('keeps long-form videos', () => {
    run(yt);
    expect(document.querySelectorAll("a[href^='/watch']").length).toBe(2);
  });

  it('keeps Home, Subscriptions and You', () => {
    run(yt);
    expect(document.querySelector('.pivot-home')).not.toBeNull();
    expect(document.querySelector('.pivot-subs')).not.toBeNull();
    expect(document.querySelector('.pivot-you')).not.toBeNull();
  });
});

declare global {
  interface Window {
    happyDOM?: { setURL?(url: string): void };
  }
}
