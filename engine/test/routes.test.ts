/**
 * Route rules: rewrites, blocks, and the isolated player.
 */

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { compile, matchesAny, rewrite } from '../src/routes.js';
import type { RuleBundle, RouteBlockSurface, IsolateSurface } from '../src/types.js';

const ROOT = join(import.meta.dirname, '..', '..');
const ig = JSON.parse(readFileSync(join(ROOT, 'rules/instagram.json'), 'utf8')) as RuleBundle;
const yt = JSON.parse(readFileSync(join(ROOT, 'rules/youtube.json'), 'utf8')) as RuleBundle;

const ytShorts = yt.services.youtube.surfaces['shorts-route'] as RouteBlockSurface;
const igReels = ig.services.instagram.surfaces['reels-route'] as RouteBlockSurface;
const igExplore = ig.services.instagram.surfaces['explore-route'] as RouteBlockSurface;
const igIsolate = ig.services.instagram.surfaces['isolated-player'] as IsolateSurface;

describe('YouTube Shorts addresses go home', () => {
  it('is a route block to the home page', () => {
    expect(ytShorts.kind).toBe('route-block');
    expect(ytShorts.redirect).toBe('/');
  });

  it('blocks the Shorts tab address (no video id) and every Short', () => {
    const res = compile(ytShorts.patterns);
    for (const p of ['/shorts/', '/shorts', '/shorts?feature=tab', '/shorts/dQw4w9WgXcQ', '/shorts/a-b_c123XYZ?feature=share']) {
      expect(matchesAny(p, res), p).toBe(true);
    }
  });

  it('leaves every other route alone', () => {
    const res = compile(ytShorts.patterns);
    for (const p of ['/watch?v=abc', '/feed/subscriptions', '/', '/@channel', '/shortsfan', '/results?search_query=shorts']) {
      expect(matchesAny(p, res), p).toBe(false);
    }
  });
});

describe('rewrite()', () => {
  it('applies a pattern with a capture group', () => {
    expect(rewrite('/a/123', '^/a/(\\d+)$', '/b?id=$1')).toBe('/b?id=123');
  });

  it('returns null when nothing matches', () => {
    expect(rewrite('/c/1', '^/a/(\\d+)$', '/b?id=$1')).toBeNull();
  });
});

describe('Instagram route blocks', () => {
  it('blocks every reels route', () => {
    const res = compile(igReels.patterns);
    for (const p of ['/reels/', '/reels', '/reels/audio/123/', '/reels/video/456/']) {
      expect(matchesAny(p, res), p).toBe(true);
    }
  });

  it('blocks every explore route', () => {
    const res = compile(igExplore.patterns);
    for (const p of ['/explore/', '/explore/tags/cats/', '/explore/locations/1/']) {
      expect(matchesAny(p, res), p).toBe(true);
    }
  });

  it('does not block DMs, profiles, or permalinks', () => {
    const res = [...compile(igReels.patterns), ...compile(igExplore.patterns)];
    for (const p of ['/direct/inbox/', '/direct/t/123/', '/someuser/', '/p/Cabc/', '/']) {
      expect(matchesAny(p, res), p).toBe(false);
    }
  });

  it('never blocks an auth route', () => {
    const res = [...compile(igReels.patterns), ...compile(igExplore.patterns)];
    for (const p of ['/accounts/login/', '/challenge/', '/accounts/onetap/']) {
      expect(matchesAny(p, res), p).toBe(false);
    }
  });
});

describe('isolated player', () => {
  it('activates on single-item permalinks', () => {
    const res = compile(igIsolate.patterns);
    expect(matchesAny('/reel/Cabc123/', res)).toBe(true);
    expect(matchesAny('/p/Cxyz789/', res)).toBe(true);
  });

  it('does not activate on the feed or on reels routes (those are blocked outright)', () => {
    const res = compile(igIsolate.patterns);
    expect(matchesAny('/', res)).toBe(false);
    expect(matchesAny('/direct/inbox/', res)).toBe(false);
  });
});
