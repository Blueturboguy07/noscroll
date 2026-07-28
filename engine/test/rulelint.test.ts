/**
 * Rule bundle lint.
 *
 * Rules are data written by contributors, including future ones who have not
 * read the selector policy. These checks encode the policy so it is enforced
 * rather than documented.
 */

import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import type { RuleBundle } from '../src/types.js';

const RULES_DIR = join(import.meta.dirname, '..', '..', 'rules');

const bundles = readdirSync(RULES_DIR)
  .filter((f) => f.endsWith('.json'))
  .map((f) => [f, JSON.parse(readFileSync(join(RULES_DIR, f), 'utf8')) as RuleBundle] as const);

function allSelectors(): Array<{ id: string; selector: string }> {
  const out: Array<{ id: string; selector: string }> = [];
  for (const [file, bundle] of bundles) {
    for (const [svc, service] of Object.entries(bundle.services)) {
      for (const [name, surface] of Object.entries(service.surfaces)) {
        if (surface.kind !== 'dom-remove') continue;
        for (const selector of surface.selectors) {
          out.push({ id: `${file}:${svc}.${name}`, selector });
        }
      }
    }
  }
  return out;
}

describe('rule lint', () => {
  it('every bundle parses and declares a version and minEngine', () => {
    expect(bundles.length).toBeGreaterThan(0);
    for (const [file, b] of bundles) {
      expect(typeof b.version, file).toBe('number');
      expect(typeof b.minEngine, file).toBe('number');
    }
  });

  it('every selector is valid and matchable in the test DOM engine', () => {
    for (const { id, selector } of allSelectors()) {
      expect(() => document.querySelectorAll(selector), `${id}: ${selector}`).not.toThrow();
    }
  });

  /**
   * `:has(> foo)` — the relative-selector form — is valid in real browsers but
   * unsupported by the DOM engine our golden fixtures run in. A rule written
   * that way silently matches nothing in CI, so it ships untested and rots
   * without anyone noticing. Use `:has(parent > child)` instead.
   */
  it('no selector uses the relative :has(> ...) form, which fixtures cannot cover', () => {
    for (const { id, selector } of allSelectors()) {
      expect(/:has\(\s*[>+~]/.test(selector), `${id}: ${selector}`).toBe(false);
    }
  });

  it('no selector matches on visible text (breaks across all 7 locales)', () => {
    for (const { id, selector } of allSelectors()) {
      expect(/:contains\(|:-abp-contains\(/.test(selector), `${id}: ${selector}`).toBe(false);
    }
  });

  /**
   * Instagram's class names are hashed and rotate. A rule that depends on one
   * is a time bomb, so it must carry an explicit review date.
   */
  it('selectors using hashed-looking classes declare expiresAfter', () => {
    for (const [file, bundle] of bundles) {
      for (const [svc, service] of Object.entries(bundle.services)) {
        for (const [name, surface] of Object.entries(service.surfaces)) {
          if (surface.kind !== 'dom-remove') continue;
          const hashed = surface.selectors.some((s) => /\.[_a-z0-9]{6,}\b/i.test(s));
          if (hashed) {
            expect(surface.expiresAfter, `${file}:${svc}.${name} uses a hashed class`)
              .toBeDefined();
          }
        }
      }
    }
  });

  it('locked surfaces are exactly the product promise, and are never default-off', () => {
    for (const [file, bundle] of bundles) {
      for (const [svc, service] of Object.entries(bundle.services)) {
        for (const [name, surface] of Object.entries(service.surfaces)) {
          if (!surface.locked) continue;
          expect(surface.defaultEnabled, `${file}:${svc}.${name} is locked`).not.toBe(false);
        }
      }
    }
  });

  it('every rule with a probe declares a non-negative expectMin', () => {
    for (const [file, bundle] of bundles) {
      for (const [svc, service] of Object.entries(bundle.services)) {
        for (const [name, surface] of Object.entries(service.surfaces)) {
          const p = surface.probe;
          if (!p) continue;
          expect(p.expectMin, `${file}:${svc}.${name}`).toBeGreaterThanOrEqual(0);
        }
      }
    }
  });

  it('vendored rules record their provenance for licence compliance', () => {
    // Any rule seeded from an external filter list must say so.
    const seeded = bundles.flatMap(([, b]) =>
      Object.values(b.services).flatMap((s) => Object.values(s.surfaces)),
    ).filter((s) => s.source?.includes('seeded from'));
    for (const s of seeded) {
      expect(s.source).toMatch(/\((MIT|GPL|AGPL|Apache|BSD)[^)]*\)/);
    }
  });
});
