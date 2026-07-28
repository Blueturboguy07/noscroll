/**
 * THE INVARIANT TEST.
 *
 * If this file fails, CI fails and nothing ships. It enforces the single rule
 * that keeps NoScroll both correct (a hidden security interstitial bricks login
 * with no visible error) and clear of Apple 5.1.1(vi), which treats credential
 * harvesting as developer-program removal rather than a rejection.
 */

import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { beforeEach, describe, expect, it } from 'vitest';
import {
  authPatternsForTest,
  extendAuthAllowList,
  isAuthSurface,
  resetAuthAllowList,
} from '../src/authguard.js';
import { start, stop } from '../src/engine.js';
import type { RuleBundle } from '../src/types.js';

const RULES_DIR = join(import.meta.dirname, '..', '..', 'rules');

function loadBundles(): Array<[string, RuleBundle]> {
  return readdirSync(RULES_DIR)
    .filter((f) => f.endsWith('.json'))
    .map((f) => [f, JSON.parse(readFileSync(join(RULES_DIR, f), 'utf8')) as RuleBundle]);
}

/** Routes that must be untouchable, per service. */
const AUTH_ROUTES = [
  '/accounts/login/',
  '/accounts/login/two_factor?next=%2F',
  '/accounts/onetap/',
  '/accounts/signup/',
  '/accounts/password/reset/',
  '/challenge/',
  '/challenge/action/AymgVFkC/',
  '/oauth/authorize',
  '/emailsignup/',
  '/signin',
  '/ServiceLogin?continue=x',
];

describe('auth guard', () => {
  beforeEach(() => {
    resetAuthAllowList();
    stop();
  });

  it('recognises every known auth route', () => {
    for (const path of AUTH_ROUTES) {
      expect(isAuthSurface({ hostname: 'www.instagram.com', pathname: path.split('?')[0] }), path)
        .toBe(true);
    }
  });

  it('recognises whole-host auth surfaces', () => {
    for (const host of ['accounts.google.com', 'appleid.apple.com']) {
      expect(isAuthSurface({ hostname: host, pathname: '/' }), host).toBe(true);
    }
  });

  it('does not treat ordinary content routes as auth surfaces', () => {
    for (const p of ['/', '/reels/', '/explore/', '/direct/inbox/', '/p/Cabc123/', '/watch']) {
      expect(isAuthSurface({ hostname: 'www.instagram.com', pathname: p }), p).toBe(false);
    }
  });

  it('a bundle may WIDEN the allow-list but never narrow it', () => {
    const before = authPatternsForTest().length;
    extendAuthAllowList(['^/custom-login']);
    expect(authPatternsForTest().length).toBe(before + 1);
    // core patterns survive
    expect(isAuthSurface({ hostname: 'x.instagram.com', pathname: '/accounts/login/' })).toBe(true);
    expect(isAuthSurface({ hostname: 'x.instagram.com', pathname: '/custom-login' })).toBe(true);
  });

  it('malformed bundle patterns cannot break or widen the guard', () => {
    extendAuthAllowList(['([unclosed']);
    expect(isAuthSurface({ hostname: 'www.instagram.com', pathname: '/' })).toBe(false);
    expect(isAuthSurface({ hostname: 'www.instagram.com', pathname: '/accounts/login/' })).toBe(true);
  });

  /**
   * The real invariant: no SHIPPED rule may target an auth route. This is what
   * catches a well-meaning future contributor adding `^/accounts/` to a
   * route-block rule.
   */
  it('NO shipped rule targets an auth surface', () => {
    for (const [file, bundle] of loadBundles()) {
      for (const [svcName, svc] of Object.entries(bundle.services)) {
        resetAuthAllowList();
        extendAuthAllowList(svc.authAllowList);
        for (const [name, surface] of Object.entries(svc.surfaces)) {
          const id = `${file}:${svcName}.${name}`;
          const patterns: string[] = [];
          if (surface.kind === 'route-block') patterns.push(...surface.patterns);
          if (surface.kind === 'isolate') patterns.push(...surface.patterns);
          if (surface.kind === 'route-rewrite') patterns.push(surface.pattern);

          for (const route of AUTH_ROUTES) {
            const path = route.split('?')[0];
            for (const p of patterns) {
              let re: RegExp;
              try {
                re = new RegExp(p, 'i');
              } catch {
                throw new Error(`${id}: invalid pattern ${p}`);
              }
              expect(re.test(path), `${id} must not match auth route ${path} (pattern ${p})`)
                .toBe(false);
            }
          }
        }
      }
    }
  });

  it('engine is fully inert on an auth surface: no style, no observer', () => {
    const bundle: RuleBundle = {
      version: 1,
      minEngine: 1,
      services: {
        instagram: {
          match: ['*://*.instagram.com/*'],
          surfaces: {
            everything: {
              kind: 'dom-remove',
              locked: true,
              selectors: ['div'],
            },
          },
        },
      },
    };

    document.body.innerHTML = '<div id="login-form"><input type="password" /></div>';
    // happy-dom lets us set the URL directly
    window.happyDOM?.setURL?.('https://www.instagram.com/accounts/login/');

    const ok = start({ bundle, settings: {}, telemetry: false });
    expect(ok).toBe(true);

    // Nothing injected...
    expect(document.getElementById('noscroll-css')).toBeNull();
    // ...and nothing removed, even though the rule says "remove every div".
    expect(document.getElementById('login-form')).not.toBeNull();
    expect(document.querySelector('input[type=password]')).not.toBeNull();
  });
});

declare global {
  interface Window {
    happyDOM?: { setURL?(url: string): void };
  }
}
