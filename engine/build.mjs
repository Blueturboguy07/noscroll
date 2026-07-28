// Bundles the engine to a single IIFE for injection into WKWebView / Android WebView.
import { build } from 'esbuild';
import { mkdirSync, writeFileSync, readFileSync } from 'node:fs';

mkdirSync('dist', { recursive: true });

const result = await build({
  entryPoints: ['src/index.ts'],
  bundle: true,
  format: 'iife',
  target: ['safari17', 'chrome110'],
  minify: true,
  legalComments: 'none',
  outfile: 'dist/noscroll.js',
  banner: {
    js: '/* NoScroll engine — AGPL-3.0-or-later — https://github.com/Blueturboguy07/noscroll */',
  },
});

const size = readFileSync('dist/noscroll.js').byteLength;
// The shells embed this as a string resource, so keep an eye on it.
writeFileSync('dist/SIZE', String(size));
console.log(`engine bundle: ${(size / 1024).toFixed(1)} KB`);
if (result.errors.length) process.exit(1);
