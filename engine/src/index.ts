/**
 * NoScroll engine entry point.
 *
 * Bundled to a single IIFE and injected at documentStart by both native shells.
 * The native side sets window.__NOSCROLL_CONFIG before injection; if it is
 * absent (e.g. the Playwright probe harness) the engine waits to be started
 * manually via window.NoScroll.start().
 */

import { ENGINE_VERSION, start, stop, __internal } from './engine.js';
import { snapshot } from './probe.js';
import type { EngineConfig } from './types.js';

declare global {
  interface Window {
    __NOSCROLL_CONFIG?: EngineConfig;
    NoScroll?: {
      version: number;
      start(config: EngineConfig): boolean;
      stop(): void;
      probes(): Array<{ ruleId: string; expected: number; actual: number }>;
      __internal: typeof __internal;
    };
  }
}

const api = {
  version: ENGINE_VERSION,
  start,
  stop,
  probes: snapshot,
  __internal,
};

if (typeof window !== 'undefined') {
  window.NoScroll = api;
  const injected = window.__NOSCROLL_CONFIG;
  if (injected) start(injected);
}

export { start, stop, ENGINE_VERSION };
export type { EngineConfig };
