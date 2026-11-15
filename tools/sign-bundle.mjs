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
 * KEYS:
 *   - keys/rules-signing.pub.pem and keys/rules-signing.pub.raw are the PUBLIC
 *     key. They are committed. ios/NoScroll/Resources/rules-signing.pub.raw is
 *     the same 32 bytes, bundled into the app.
 *   - The PRIVATE key is never in the repo. CI holds it in the secret
 *     RULES_SIGNING_KEY (pkcs8 PEM), and `sign` reads it from that environment
 *     variable. Without the variable, `sign` falls back to keys/rules-signing.pem
 *     (gitignored) for local work.
 *   - `sign` refuses a private key that does not match the committed public key.
 *   - .github/workflows/sign-rules.yml signs every bundle with the secret and
 *     commits the result. ed25519 signatures are deterministic, so a re-run on
 *     unchanged bundles changes nothing.
 *
 * Usage:
 *   node tools/sign-bundle.mjs keygen                 -> writes keys/
 *   RULES_SIGNING_KEY=... node tools/sign-bundle.mjs sign rules/*.json  -> signs in place
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
  console.log('To rotate the CI key: store the new private key in the repo secret');
  console.log('RULES_SIGNING_KEY, commit the two public files and copy the .raw file to');
  console.log('ios/NoScroll/Resources/rules-signing.pub.raw.');
}

/**
 * The private key: the RULES_SIGNING_KEY environment variable (CI), else the
 * gitignored keys/rules-signing.pem. It must match the committed public key, so
 * a wrong key fails here and not on a user's phone. The key is never printed.
 */
function loadSigningKey() {
  const fromEnv = (process.env.RULES_SIGNING_KEY || '').trim();
  if (!fromEnv && !existsSync(PRIV)) {
    console.error('no signing key: set RULES_SIGNING_KEY or create keys/rules-signing.pem');
    process.exit(1);
  }
  const key = createPrivateKey(fromEnv ? fromEnv + '\n' : readFileSync(PRIV));
  const derived = createPublicKey(key).export({ type: 'spki', format: 'der' });
  const committed = createPublicKey(readFileSync(PUB)).export({ type: 'spki', format: 'der' });
  if (!derived.equals(committed)) {
    console.error(`the signing key does not match ${PUB} — refusing to sign`);
    process.exit(1);
  }
  return key;
}

let signingKey;
function signFile(path) {
  const key = (signingKey ??= loadSigningKey());
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
