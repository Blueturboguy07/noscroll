/**
 * Rule health probes.
 *
 * The category's defining failure is selector rot: Instagram ships a redesign,
 * a hashed class rotates, and the blocker silently stops blocking. Users find
 * out before the developer does — that is why SocialLite's own marketing
 * screenshot still shows a Shorts shelf.
 *
 * Every rule declares expectMin. The engine counts what it actually matched and
 * reports anomalies. Combined with probe/ (scheduled Playwright runs against
 * live Instagram and YouTube), this turns rot from "a user complains eventually"
 * into "an alert fires within one cycle".
 */

import { send } from './bridge.js';
import type { Probe } from './types.js';

interface Record_ {
  ruleId: string;
  expected: number;
  actual: number;
  reported: boolean;
  onlyWhenSignedIn: boolean;
}

const records = new Map<string, Record_>();
let bundleVersion = 0;

export function configureProbe(version: number): void {
  bundleVersion = version;
  records.clear();
}

/** Called by the sweep with what a rule actually matched this pass. */
export function record(ruleId: string, probe: Probe | undefined, actual: number): void {
  if (!probe || probe.expectMin === undefined) return;
  const prev = records.get(ruleId);
  // Keep the best count seen for this route: a rule may legitimately match
  // nothing mid-render and match correctly a moment later.
  const best = Math.max(prev?.actual ?? 0, actual);
  records.set(ruleId, {
    ruleId,
    expected: probe.expectMin,
    actual: best,
    reported: prev?.reported ?? false,
    onlyWhenSignedIn: probe.onlyWhenSignedIn ?? false,
  });
}

/**
 * Flush after settle. A rule whose expectMin is >0 but matched 0 is the signal
 * that something upstream changed.
 */
export function flush(): void {
  for (const r of records.values()) {
    if (r.reported) continue;
    if (r.expected > 0 && r.actual === 0) {
      r.reported = true;
      send({
        type: 'probe',
        ruleId: r.ruleId,
        expected: r.expected,
        actual: r.actual,
        bundleVersion,
      });
    }
  }
}

/** Exposed for the Playwright probe harness to assert on directly. */
export function snapshot(): Array<{
  ruleId: string;
  expected: number;
  actual: number;
  onlyWhenSignedIn: boolean;
}> {
  return [...records.values()].map(({ ruleId, expected, actual, onlyWhenSignedIn }) => ({
    ruleId,
    expected,
    actual,
    onlyWhenSignedIn,
  }));
}
