/**
 * Route interception for single-page apps.
 *
 * Instagram and YouTube are SPAs. Clicking a post changes the URL via
 * history.pushState with NO HTTP navigation, which means the native layer's
 * WKNavigationDelegate.decidePolicyFor / WebViewClient.shouldOverrideUrlLoading
 * never fires. Native URL interception alone therefore cannot see most navigation
 * inside these apps — this shim is what makes route rules work at all.
 */

export type RouteListener = (path: string) => void;

const listeners = new Set<RouteListener>();
let installed = false;
let lastPath = '';

function currentPath(): string {
  return location.pathname + location.search;
}

function emit(): void {
  const p = currentPath();
  if (p === lastPath) return;
  lastPath = p;
  for (const fn of listeners) {
    try {
      fn(p);
    } catch {
      /* one bad listener must not stop the others */
    }
  }
}

export function onRouteChange(fn: RouteListener): () => void {
  listeners.add(fn);
  return () => listeners.delete(fn);
}

export function installRouteHooks(): void {
  if (installed) return;
  installed = true;
  lastPath = currentPath();

  const origPush = history.pushState;
  const origReplace = history.replaceState;

  history.pushState = function (this: History, ...args: Parameters<History['pushState']>) {
    const r = origPush.apply(this, args);
    emit();
    return r;
  };

  history.replaceState = function (this: History, ...args: Parameters<History['replaceState']>) {
    const r = origReplace.apply(this, args);
    emit();
    return r;
  };

  addEventListener('popstate', emit);
  addEventListener('hashchange', emit);

  // Belt and braces: some frameworks mutate history via internal paths we
  // haven't patched. A cheap poll catches those without a MutationObserver.
  setInterval(emit, 400);
}

/** Compile a bundle's string patterns once. */
export function compile(patterns: string[]): RegExp[] {
  const out: RegExp[] = [];
  for (const p of patterns) {
    try {
      out.push(new RegExp(p, 'i'));
    } catch {
      /* skip malformed pattern rather than breaking the whole bundle */
    }
  }
  return out;
}

export function matchesAny(path: string, res: RegExp[]): boolean {
  return res.some((r) => r.test(path));
}

/**
 * Apply a rewrite. Used for the single cheapest win in the product:
 * YouTube /shorts/<id> -> /watch?v=<id> is the same video, same CDN, same
 * metadata. /shorts is purely a front-end player skin.
 */
export function rewrite(path: string, pattern: string, replacement: string): string | null {
  let re: RegExp;
  try {
    re = new RegExp(pattern, 'i');
  } catch {
    return null;
  }
  if (!re.test(path)) return null;
  const next = path.replace(re, replacement);
  return next === path ? null : next;
}
