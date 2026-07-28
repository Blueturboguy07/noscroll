#!/usr/bin/env node
/**
 * Sign rule bundles with ed25519.
 *
 * Why signing matters here: rule bundles are fetched at runtime and decide what
 * gets blocked. An attacker who can MITM the CDN and swap a bundle could switch
 * blocking off entirely — silently, with no app update and no user-visible sign.
 * Verification happens NATIVELY, before the bundle ever reaches the WebView.
 *
 * CANONICALISATION — must match RuleStore.canonicalize in
 * ios/NoScroll/Core/RuleBundle.swift byte for byte:
 *
 *   1. remove the `signature` key
 *   2. serialise with keys sorted lexicographically at every level
 *   3. compact separators, no whitespace
 *
 * `tools/verify-canonical.swift` asserts the two implementations agree; run it
 * (or `pnpm run verify:signing`) after touching either side.
 *
 * Usage:
 *   node tools/sign-bundle.mjs keygen                 -> writes keys/
 *   node tools/sign-bundle.mjs sign rules/*.json      -> signs in place
 *   node tools/sign-bundle.mjs verify rules/*.json
 */

import { createPrivateKey, createPublicKey, generateKeyPairSync, sign, verify } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const KEY_DIR = join(ROOT, 'keys');
const PRIV = join(KEY_DIR, 'rules-signing.pem');
const PUB = join(KEY_DIR, 'rules-signing.pub.pem');
const PUB_RAW = join(KEY_DIR, 'rules-signing.pub.raw');

/** Sort object keys recursively. Arrays keep their order — order is meaningful. */
function sortKeys(value) {
  if (Array.isArray(value)) return value.map(sortKeys);
  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.keys(value)
        .sort()
        .map((k) => [k, sortKeys(value[k])]),
    );
  }
  return value;
}

export function canonicalize(raw) {
  const obj = JSON.parse(raw);
  delete obj.signature;
  return Buffer.from(JSON.stringify(sortKeys(obj)), 'utf8');
}

function keygen() {
  if (existsSync(PRIV)) {
    console.error(`refusing to overwrite ${PRIV} — delete it explicitly if you mean to rotate`);
    process.exit(1);
  }
  mkdirSync(KEY_DIR, { recursive: true });
  const { privateKey, publicKey } = generateKeyPairSync('ed25519');
  writeFileSync(PRIV, privateKey.export({ type: 'pkcs8', format: 'pem' }), { mode: 0o600 });
  writeFileSync(PUB, publicKey.export({ type: 'spki', format: 'pem' }));

  // Raw 32-byte key: what Curve25519.Signing.PublicKey(rawRepresentation:) wants.
  const spki = publicKey.export({ type: 'spki', format: 'der' });
  writeFileSync(PUB_RAW, spki.subarray(spki.length - 32));

  console.log(`wrote ${PRIV}\nwrote ${PUB}\nwrote ${PUB_RAW} (32-byte raw, for the Swift/Kotlin shells)`);
  console.log('\nNEVER commit keys/rules-signing.pem. It is in .gitignore.');
}

function signFile(path) {
  const key = createPrivateKey(readFileSync(PRIV));
  const raw = readFileSync(path, 'utf8');
  const signature = sign(null, canonicalize(raw), key).toString('base64');

  const obj = JSON.parse(raw);
  obj.signature = signature;
  // Keep the on-disk file human-diffable; only the canonical form is signed.
  writeFileSync(path, JSON.stringify(obj, null, 2) + '\n');
  console.log(`signed ${path} (v${obj.version})`);
}

function verifyFile(path) {
  const key = createPublicKey(readFileSync(PUB));
  const raw = readFileSync(path, 'utf8');
  const obj = JSON.parse(raw);
  if (!obj.signature) {
    console.error(`FAIL ${path}: no signature`);
    return false;
  }
  const ok = verify(null, canonicalize(raw), key, Buffer.from(obj.signature, 'base64'));
  console.log(`${ok ? 'OK  ' : 'FAIL'} ${path}`);
  return ok;
}

const [cmd, ...files] = process.argv.slice(2);
switch (cmd) {
  case 'keygen':
    keygen();
    break;
  case 'sign':
    files.forEach(signFile);
    break;
  case 'verify': {
    const all = files.map(verifyFile);
    process.exit(all.every(Boolean) ? 0 : 1);
    break;
  }
  case 'canonical':
    process.stdout.write(canonicalize(readFileSync(files[0], 'utf8')));
    break;
  default:
    console.error('usage: sign-bundle.mjs <keygen|sign|verify|canonical> [files...]');
    process.exit(1);
}
