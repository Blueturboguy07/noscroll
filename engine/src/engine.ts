/**
 * NoScroll engine — the interpreter for a rule bundle.
 *
 * Runs identically inside WKWebView (iOS) and Android WebView. Injected at
 * documentStart. Everything platform-specific lives in the native shells.
 *
 * Order of operations matters:
 *   1. auth check      — if this is a login/challenge surface, do NOTHING at all
 *   2. CSS first       — hide locked surfaces before first paint (no Reel flash)
 *   3. route rules     — rewrite/block, including SPA pushState navigation
 *   4. DOM sweep       — remove nodes for real
 *   5. observe         — repeat on every mutation, for content with no URL
 */

import { extendAuthAllowList, isAuthSurface, resetAuthAllowList } from './authguard.js';
import { configureBridge, send } from './bridge.js';
import { clearSweeps, registerSweep, startObserver, stopObserver, sweepNow } from './observer.js';
import { configureProbe, flush, record } from './probe.js';
import { compile, installRouteHooks, matchesAny, onRouteChange, rewrite } from './routes.js';
import { disableIsolation, enableIsolation } from './gestures.js';
import type {
  DomRemoveSurface,
  EngineConfig,
  IsolateSurface,
  RouteBlockSurface,
  RouteRewriteSurface,
  RuleBundle,
  Service,
  StyleSurface,
  Surface,
} from './types.js';

export const ENGINE_VERSION = 1;

const STYLE_ID = 'noscroll-css';

let cfg: EngineConfig | null = null;
let serviceName = '';
let service: Service | null = null;
let inert = false;

function matchesService(svc: Service): boolean {
  for (const pattern of svc.match) {
    // "*://*.instagram.com/*" -> hostname test
    const m = /^\*:\/\/(?:\*\.)?([^/]+)\/\*$/.exec(pattern);
    if (!m) continue;
    const host = m[1].toLowerCase();
    const h = location.hostname.toLowerCase();
    if (h === host || h.endsWith('.' + host)) return true;
  }
  return false;
}

function pickService(bundle: RuleBundle): [string, Service] | null {
  for (const [name, svc] of Object.entries(bundle.services)) {
    if (matchesService(svc)) return [name, svc];
  }
  return null;
}

function surfaceId(name: string): string {
  return `${serviceName}.${name}`;
}

/** Locked surfaces ignore user settings entirely — that is what "locked" means. */
function isEnabled(name: string, s: Surface): boolean {
  if (s.locked) return true;
  const explicit = cfg?.settings[surfaceId(name)];
  if (typeof explicit === 'boolean') return explicit;
  return s.defaultEnabled ?? false;
}

/* ------------------------------------------------------------------ CSS */

/**
 * CSS-first. Without this a Reel is painted and then removed, and the flicker is
 * exactly what makes a blocker feel broken. Injected at documentStart, before
 * the app has rendered anything.
 */
function buildCss(): string {
  if (!service) return '';
  const chunks: string[] = [];
  for (const [name, s] of Object.entries(service.surfaces)) {
    if (!isEnabled(name, s)) continue;
    if (s.kind === 'dom-remove') {
      const sel = (s as DomRemoveSurface).selectors.join(',\n');
      if (sel.trim()) chunks.push(`${sel} { display: none !important; }`);
    } else if (s.kind === 'style') {
      chunks.push((s as StyleSurface).css);
    }
  }
  return chunks.join('\n');
}

/**
 * At document-start — which is exactly when both shells inject us — `document`
 * has NO documentElement and NO head yet. Both are null. Touching either one
 * throws, and because that happens on the engine's first action, the whole
 * engine dies silently and nothing is ever blocked.
 *
 * This cannot be caught by the golden-DOM tests: a test DOM always has a
 * documentElement. It was found by the live probe against instagram.com, which
 * is the reason that probe exists.
 */
function whenRootExists(fn: () => void): void {
  if (document.documentElement) {
    fn();
    return;
  }
  const boot = new MutationObserver(() => {
    if (!document.documentElement) return;
    boot.disconnect();
    fn();
  });
  boot.observe(document, { childList: true, subtree: true });
}

function applyCss(): void {
  const host = document.head ?? document.documentElement;
  if (!host) {
    whenRootExists(applyCss);
    return;
  }
  const css = buildCss();
  let el = document.getElementById(STYLE_ID) as HTMLStyleElement | null;
  if (!el) {
    el = document.createElement('style');
    el.id = STYLE_ID;
    el.textContent = css;
    host.appendChild(el);
    return;
  }
  el.textContent = css;
}

function removeCss(): void {
  document.getElementById(STYLE_ID)?.remove();
}

/* ------------------------------------------------------------- DOM sweep */

/**
 * Cheap signed-out detection. A login link on the page is the reliable tell on
 * both Instagram and YouTube, and it needs no cookie access (session cookies are
 * httpOnly and invisible to us by design).
 */
function isSignedOut(): boolean {
  const hints = service?.signedOutWhen;
  if (!hints || hints.length === 0) return false;
  for (const sel of hints) {
    try {
      if (document.querySelector(sel)) return true;
    } catch {
      /* a malformed hint must not break probing */
    }
  }
  return false;
}

function rejustify(parent: Element | null): void {
  if (!parent) return;
  const style = getComputedStyle(parent);
  if (style.display === 'flex' || style.display === 'inline-flex') {
    (parent as HTMLElement).style.justifyContent = 'space-around';
  }
}

function sweepDom(): void {
  if (!service || inert) return;
  const path = location.pathname + location.search;

  for (const [name, s] of Object.entries(service.surfaces)) {
    if (s.kind !== 'dom-remove') continue;
    if (!isEnabled(name, s)) continue;
    const rule = s as DomRemoveSurface;

    if (rule.onlyOnRoutes && !matchesAny(path, compile(rule.onlyOnRoutes))) continue;

    let count = 0;
    for (const sel of rule.selectors) {
      let nodes: NodeListOf<Element>;
      try {
        nodes = document.querySelectorAll(sel);
      } catch {
        // An invalid selector in a bundle must not take down the sweep.
        continue;
      }
      for (const n of nodes) {
        count++;
        const parent = n.parentElement;
        if (rule.suppression === 'hide') {
          (n as HTMLElement).style.setProperty('display', 'none', 'important');
        } else {
          n.remove();
        }
        // Removing one nav icon otherwise misaligns the rest and leaves a dead
        // tap zone where the icon used to be.
        if (rule.afterRemove === 'rejustify') rejustify(parent);
      }
    }
    record(surfaceId(name), rule.probe, count);
    if (count > 0) send({ type: 'blocked', ruleId: surfaceId(name), count });
  }
}

/* ------------------------------------------------------------- routing */

function handleRoute(path: string): void {
  if (!service) return;

  // Re-check on EVERY route change: an SPA can navigate from a feed into a
  // login challenge without a page load, and the engine must go inert.
  const nowInert = isAuthSurface(location);
  if (nowInert !== inert) {
    inert = nowInert;
    send({ type: 'auth-surface', active: inert });
    if (inert) {
      removeCss();
      stopObserver();
      disableIsolation();
      return;
    }
    applyCss();
    startObserver();
  }
  if (inert) return;

  // 1. rewrites (cheapest, most robust): /shorts/<id> -> /watch?v=<id>
  for (const [name, s] of Object.entries(service.surfaces)) {
    if (s.kind !== 'route-rewrite' || !isEnabled(name, s)) continue;
    const r = s as RouteRewriteSurface;
    const next = rewrite(path, r.pattern, r.replacement);
    if (next) {
      send({ type: 'route', path, blocked: true });
      location.replace(next);
      return;
    }
  }

  // 2. hard blocks.
  // Belt and braces: even though the engine is already inert on auth surfaces,
  // re-check the path here so a mistake in a future bundle (an over-broad
  // catch-all like DMs-Only, say) can never redirect a user away from a login
  // or security-challenge page.
  for (const [name, s] of Object.entries(service.surfaces)) {
    if (s.kind !== 'route-block' || !isEnabled(name, s)) continue;
    const r = s as RouteBlockSurface;
    if (isAuthSurface({ hostname: location.hostname, pathname: path.split('?')[0] })) break;
    if (matchesAny(path, compile(r.patterns))) {
      send({ type: 'route', path, blocked: true });
      location.replace(r.redirect);
      return;
    }
  }

  // 3. isolation: one item plays, nothing advances
  let isolate: IsolateSurface | null = null;
  for (const [name, s] of Object.entries(service.surfaces)) {
    if (s.kind !== 'isolate' || !isEnabled(name, s)) continue;
    const r = s as IsolateSurface;
    if (matchesAny(path, compile(r.patterns))) {
      isolate = r;
      break;
    }
  }
  if (isolate) {
    const target = isolate;
    enableIsolation({
      onAdvance: () => {
        if (target.onAdvance === 'redirect' && target.redirect) location.assign(target.redirect);
        else history.back();
      },
    });
  } else {
    disableIsolation();
  }

  send({ type: 'route', path, blocked: false });
  // Synchronous first pass: CSS has already hidden the locked surfaces, but the
  // nodes must actually come out before the user can interact with them. rAF
  // batching then handles every subsequent mutation.
  sweepDom();
  sweepNow();
  setTimeout(() => flush(isSignedOut()), 2500);
}

/* ---------------------------------------------------------------- start */

export function start(config: EngineConfig): boolean {
  cfg = config;
  resetAuthAllowList();
  configureBridge(config.telemetry);
  configureProbe(config.bundle.version);

  if (config.bundle.minEngine > ENGINE_VERSION) return false;

  const picked = pickService(config.bundle);
  if (!picked) return false;
  [serviceName, service] = picked;

  extendAuthAllowList(service.authAllowList);

  inert = isAuthSurface(location);
  if (inert) {
    // Nothing is injected, nothing is observed, nothing is read. See authguard.ts.
    send({ type: 'auth-surface', active: true });
    installRouteHooks();
    onRouteChange(handleRoute);
    return true;
  }

  applyCss();
  clearSweeps();
  registerSweep(sweepDom);
  startObserver();
  installRouteHooks();
  onRouteChange(handleRoute);

  handleRoute(location.pathname + location.search);
  send({ type: 'ready', bundleVersion: config.bundle.version, service: serviceName });
  return true;
}

export function stop(): void {
  stopObserver();
  disableIsolation();
  removeCss();
  clearSweeps();
  cfg = null;
  service = null;
  serviceName = '';
  inert = false;
}

/** Test/debug surface. */
export const __internal = { sweepDom, handleRoute, buildCss, isEnabled };
