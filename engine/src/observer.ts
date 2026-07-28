/**
 * Mutation observation.
 *
 * This module exists because of one fact: Instagram's suggested and algorithmic
 * in-feed content arrives via background GraphQL into an already-mounted shell,
 * with NO URL change at all. There is no route to block and no navigation event
 * to hook. URL rules are structurally insufficient for that surface, and no
 * quantity of them will ever be enough.
 *
 * This is also the surface SocialLite visibly leaks on.
 */

export type SweepFn = () => void;

let observer: MutationObserver | null = null;
let scheduled = false;
let sweeps: SweepFn[] = [];

/** rAF-batched so a burst of mutations costs one sweep, not hundreds. */
function schedule(): void {
  if (scheduled) return;
  scheduled = true;
  const run = () => {
    scheduled = false;
    for (const s of sweeps) {
      try {
        s();
      } catch {
        /* a failing rule must not stop the rest of the sweep */
      }
    }
  };
  if (typeof requestAnimationFrame === 'function') requestAnimationFrame(run);
  else setTimeout(run, 16);
}

export function registerSweep(fn: SweepFn): void {
  sweeps.push(fn);
}

export function clearSweeps(): void {
  sweeps = [];
}

export function startObserver(root: Node | null = document.documentElement): void {
  if (observer) return;

  // At document-start there is no documentElement yet — observing null throws.
  // Wait for it on `document` itself, which always exists.
  if (!root) {
    const boot = new MutationObserver(() => {
      if (!document.documentElement) return;
      boot.disconnect();
      startObserver(document.documentElement);
    });
    boot.observe(document, { childList: true, subtree: true });
    return;
  }
  observer = new MutationObserver((records) => {
    // Cheap filter: only sweep when nodes were actually added, or when an
    // attribute we key selectors off changed.
    for (const r of records) {
      if (r.type === 'childList' && r.addedNodes.length > 0) return schedule();
      if (r.type === 'attributes') return schedule();
    }
  });
  observer.observe(root as Node, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ['href', 'aria-label', 'role', 'aria-hidden', 'data-testid'],
  });
  schedule();
}

export function stopObserver(): void {
  observer?.disconnect();
  observer = null;
}

/** Force a sweep — used on route change and after settle delays. */
export function sweepNow(): void {
  schedule();
}
