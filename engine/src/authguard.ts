/**
 * THE INVARIANT.
 *
 *   The engine MUST NOT hide, remove, restyle, or observe any node on an auth surface.
 *
 * Two reasons, both load-bearing:
 *
 *  1. Correctness. A hiding rule that swallows Instagram's own security interstitial
 *     bricks login with no visible error. This is the exact shape of bug that produces
 *     "this app stole my account" reviews.
 *
 *  2. Policy. Apple 5.1.1(vi) treats credential harvesting as *developer-program
 *     removal*, not a rejection. Never touching an auth surface is what keeps us
 *     provably clear of it — the engine cannot read a login field it refuses to look at.
 *
 * This list is hard-coded. A rule bundle may WIDEN it (authAllowList) but can never
 * narrow it. Enforced by test/authguard.test.ts, which fails CI on violation.
 */

/** Auth routes, matched against pathname. Never overridable. */
const CORE_AUTH_PATTERNS: RegExp[] = [
  // Instagram
  /^\/accounts\//i,
  /^\/challenge\//i,
  /^\/oauth\//i,
  /^\/two_factor/i,
  /^\/emailsignup/i,
  /^\/recover\//i,
  // YouTube / Google
  /^\/signin/i,
  /^\/logout/i,
  /^\/ServiceLogin/i,
  // Generic
  /^\/login/i,
  /^\/signup/i,
  /^\/register/i,
  /^\/2fa/i,
  /^\/verify/i,
];

/** Hosts that are entirely auth surfaces — the engine never runs on them at all. */
const CORE_AUTH_HOSTS: RegExp[] = [
  /(^|\.)accounts\.google\.com$/i,
  /(^|\.)accounts\.youtube\.com$/i,
  /(^|\.)login\.microsoftonline\.com$/i,
  /(^|\.)appleid\.apple\.com$/i,
];

let extraPatterns: RegExp[] = [];

/**
 * Widen the allow-list from a bundle. Additive only — this can never remove a
 * core pattern, by construction.
 */
export function extendAuthAllowList(patterns: string[] | undefined): void {
  if (!patterns) return;
  for (const p of patterns) {
    try {
      extraPatterns.push(new RegExp(p, 'i'));
    } catch {
      /* a malformed bundle pattern must never widen or break the guard */
    }
  }
}

export function resetAuthAllowList(): void {
  extraPatterns = [];
}

/** True if the given location is an auth surface. The engine must be inert here. */
export function isAuthSurface(loc: { hostname: string; pathname: string }): boolean {
  for (const h of CORE_AUTH_HOSTS) if (h.test(loc.hostname)) return true;
  for (const p of CORE_AUTH_PATTERNS) if (p.test(loc.pathname)) return true;
  for (const p of extraPatterns) if (p.test(loc.pathname)) return true;
  return false;
}

/**
 * Exported for the CI invariant test: no rule in any shipped bundle may target a
 * path that isAuthSurface() would protect.
 */
export function authPatternsForTest(): RegExp[] {
  return [...CORE_AUTH_PATTERNS, ...extraPatterns];
}

export function authHostsForTest(): RegExp[] {
  return [...CORE_AUTH_HOSTS];
}
