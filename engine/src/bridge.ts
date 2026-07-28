/**
 * Native bridge. One message schema, two transports.
 *
 * PRIVACY BOUNDARY: messages carry rule ids and counts only. Never a URL, never
 * page content, never anything derived from what the user is looking at. This is
 * what makes the claim in docs/PRIVACY.md verifiable rather than merely asserted.
 */

import type { BridgeMessage } from './types.js';

interface WebKitBridge {
  messageHandlers?: Record<string, { postMessage(msg: unknown): void }>;
}

declare global {
  interface Window {
    webkit?: WebKitBridge;
    NoScrollAndroid?: { postMessage(json: string): void };
    __noscrollSink?: (m: BridgeMessage) => void; // test sink
  }
}

let telemetryEnabled = false;

export function configureBridge(telemetry: boolean): void {
  telemetryEnabled = telemetry;
}

/** Message types that are diagnostics and therefore gated on opt-in telemetry. */
const TELEMETRY_TYPES = new Set(['probe', 'blocked', 'breakage']);

export function send(msg: BridgeMessage): void {
  if (TELEMETRY_TYPES.has(msg.type) && !telemetryEnabled) return;

  // Test sink takes precedence so the suite can assert on messages.
  if (typeof window !== 'undefined' && window.__noscrollSink) {
    window.__noscrollSink(msg);
    return;
  }
  try {
    const ios = window.webkit?.messageHandlers?.noscroll;
    if (ios) {
      ios.postMessage(msg);
      return;
    }
    const android = window.NoScrollAndroid;
    if (android) {
      android.postMessage(JSON.stringify(msg));
      return;
    }
  } catch {
    /* the bridge is diagnostics; it must never break blocking */
  }
}
