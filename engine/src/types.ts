/**
 * NoScroll rule bundle types.
 *
 * A bundle is DATA, not code. It is fetched from a CDN, ed25519-verified, and cached.
 * The engine is the interpreter; shipping a new rule must never require an app release.
 */

export type SurfaceKind =
  | 'dom-remove'
  | 'route-block'
  | 'route-rewrite'
  | 'isolate'
  | 'style';

/** How aggressively a matched node is suppressed. */
export type Suppression = 'remove' | 'hide';

export interface Probe {
  /**
   * Minimum number of nodes this rule is expected to match on a page where the
   * surface is present. The engine reports actual counts over the bridge; a
   * collapse to zero is how we detect selector rot BEFORE users do.
   */
  expectMin?: number;
  /** Warn if this rule has matched nothing for this long (e.g. "6h"). */
  warnIfZeroFor?: string;
  /** Routes on which this probe is meaningful. If absent, all non-auth routes. */
  onlyOnRoutes?: string[];
  /**
   * The surface only exists for a signed-in user, so `expectMin` is meaningless
   * otherwise. Logged-out m.youtube.com, for instance, renders three pivot-bar
   * items and no Shorts tab at all — a zero match there is correct, not rot.
   * The live probe skips these unless it has a session.
   */
  onlyWhenSignedIn?: boolean;
}

export interface SurfaceBase {
  kind: SurfaceKind;
  /**
   * Locked surfaces cannot be disabled by the user. This is the product's spine:
   * Block Reels / Block Explore / Block Shorts are always on, so there is no
   * "I'll just turn it off for a second" failure mode.
   */
  locked?: boolean;
  /** Default enabled state for unlocked surfaces. */
  defaultEnabled?: boolean;
  /** Human label shown in native settings UI. */
  label?: string;
  probe?: Probe;
  /** Provenance for vendored rules (licence compliance). */
  source?: string;
}

export interface DomRemoveSurface extends SurfaceBase {
  kind: 'dom-remove';
  selectors: string[];
  suppression?: Suppression;
  /**
   * Re-justify the parent flex container after removing a child. Removing one
   * nav icon otherwise misaligns the rest and leaves a dead tap zone.
   */
  afterRemove?: 'rejustify' | 'none';
  /** Only apply on routes matching these patterns. */
  onlyOnRoutes?: string[];
  /**
   * Requires MutationObserver: content arrives via background GraphQL into an
   * already-mounted shell with no URL change, so CSS+initial pass is not enough.
   */
  observe?: boolean;
  /** Selectors matching hashed/obfuscated classes must declare an expiry. */
  expiresAfter?: string;
}

export interface RouteBlockSurface extends SurfaceBase {
  kind: 'route-block';
  patterns: string[];
  redirect: string;
}

export interface RouteRewriteSurface extends SurfaceBase {
  kind: 'route-rewrite';
  /** Regex with capture groups, applied to pathname + search. */
  pattern: string;
  /** Replacement using $1-style references. */
  replacement: string;
}

export interface IsolateSurface extends SurfaceBase {
  kind: 'isolate';
  /** Routes that render exactly one item and must not advance to a next item. */
  patterns: string[];
  /** Where to send the user when they try to advance. */
  onAdvance: 'back' | 'redirect';
  redirect?: string;
}

export interface StyleSurface extends SurfaceBase {
  kind: 'style';
  css: string;
}

export type Surface =
  | DomRemoveSurface
  | RouteBlockSurface
  | RouteRewriteSurface
  | IsolateSurface
  | StyleSurface;

export interface Service {
  /** Host match patterns, e.g. "*://*.instagram.com/*". */
  match: string[];
  /**
   * Additional auth routes for this service. MERGED with the engine's hard-coded
   * list — a bundle can widen the allow-list but can never narrow it.
   */
  authAllowList?: string[];
  surfaces: Record<string, Surface>;
}

export interface RuleBundle {
  version: number;
  /** Engine versions below this must refuse the bundle and keep their cache. */
  minEngine: number;
  /** ed25519 signature over the canonical body. Verified natively, before injection. */
  signature?: string;
  services: Record<string, Service>;
}

/** Per-surface user settings, keyed "service.surface". Locked surfaces ignore this. */
export type Settings = Record<string, boolean>;

export interface EngineConfig {
  bundle: RuleBundle;
  settings: Settings;
  /** Opt-in, anonymous. Reports {ruleId, expected, actual, bundleVersion} only. */
  telemetry: boolean;
  debug?: boolean;
}

export type BridgeMessage =
  | { type: 'probe'; ruleId: string; expected: number; actual: number; bundleVersion: number }
  | { type: 'blocked'; ruleId: string; count: number }
  | { type: 'route'; path: string; blocked: boolean }
  | { type: 'auth-surface'; active: boolean }
  | { type: 'breakage'; ruleId: string; detail: string }
  | { type: 'ready'; bundleVersion: number; service: string };
