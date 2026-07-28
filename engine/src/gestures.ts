/**
 * Gesture suppression for the isolated player.
 *
 * The signature feature: a friend sends you a reel in a DM. You can watch THAT
 * video. You cannot scroll to the next one. That is the difference between a
 * 30-second check-in and a 30-minute spiral.
 *
 * Every advance path must be made inert, not just vertical touch:
 *   - touch swipe          - wheel / trackpad
 *   - arrow keys, space, PageDown/PageUp, j/k
 *   - CSS scroll-snap paging
 *   - autoplay-next timers and <link rel=prefetch> of the next item
 *
 * On an advance attempt we REDIRECT BACK to the thread rather than silently
 * eating the gesture. A dead gesture reads as a broken app; a redirect reads as
 * intentional. (This is also SocialLite's observed behaviour.)
 */

export interface IsolateOptions {
  onAdvance: () => void;
  /** px of movement before a touch counts as an advance attempt */
  threshold?: number;
}

const ADVANCE_KEYS = new Set([
  'ArrowDown',
  'ArrowUp',
  'PageDown',
  'PageUp',
  ' ',
  'Spacebar',
  'j',
  'k',
]);

let teardown: Array<() => void> = [];
let active = false;

function stop(e: Event): void {
  e.preventDefault();
  e.stopPropagation();
}

export function isIsolationActive(): boolean {
  return active;
}

export function enableIsolation(opts: IsolateOptions): void {
  if (active) return;
  active = true;
  const threshold = opts.threshold ?? 24;
  let startY = 0;
  let fired = false;

  const fire = () => {
    if (fired) return;
    fired = true;
    // Debounce: one advance attempt should produce one navigation, not twenty.
    setTimeout(() => {
      fired = false;
    }, 800);
    opts.onAdvance();
  };

  const onTouchStart = (e: TouchEvent) => {
    startY = e.touches[0]?.clientY ?? 0;
    fired = false;
  };
  const onTouchMove = (e: TouchEvent) => {
    const y = e.touches[0]?.clientY ?? 0;
    if (Math.abs(y - startY) > threshold) {
      stop(e);
      fire();
    } else {
      stop(e);
    }
  };
  const onWheel = (e: WheelEvent) => {
    stop(e);
    if (Math.abs(e.deltaY) > 4) fire();
  };
  const onKey = (e: KeyboardEvent) => {
    if (!ADVANCE_KEYS.has(e.key)) return;
    stop(e);
    fire();
  };

  const add = <K extends keyof DocumentEventMap>(
    type: K,
    fn: (e: DocumentEventMap[K]) => void,
  ) => {
    const wrapped = fn as EventListener;
    document.addEventListener(type, wrapped, { capture: true, passive: false });
    teardown.push(() => document.removeEventListener(type, wrapped, { capture: true }));
  };

  add('touchstart', onTouchStart);
  add('touchmove', onTouchMove);
  add('wheel', onWheel);
  add('keydown', onKey);

  // Kill scroll-snap paging and overflow scrolling at the document level.
  const style = document.createElement('style');
  style.setAttribute('data-noscroll', 'isolation');
  style.textContent = `
    html, body { overflow: hidden !important; overscroll-behavior: none !important; }
    * { scroll-snap-type: none !important; }
  `;
  document.documentElement.appendChild(style);
  teardown.push(() => style.remove());

  // Drop prefetch/preload hints for the next item.
  const killPrefetch = () => {
    document
      .querySelectorAll('link[rel="prefetch"],link[rel="preload"][as="video"],link[rel="next"]')
      .forEach((n) => n.remove());
  };
  killPrefetch();
  const iv = setInterval(killPrefetch, 1000);
  teardown.push(() => clearInterval(iv));
}

export function disableIsolation(): void {
  if (!active) return;
  active = false;
  for (const fn of teardown) {
    try {
      fn();
    } catch {
      /* teardown must always complete */
    }
  }
  teardown = [];
}
