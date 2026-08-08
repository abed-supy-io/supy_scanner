#!/usr/bin/env node
// Generate an Ed25519 keypair for license signing.
//
//   npm run keygen
//
// Prints the PUBLIC key (base64url of the raw 32 bytes) to paste into the
// Flutter library's `kSupyLicensePublicKeyBase64`, and the PRIVATE key as
// base64 PKCS8 PEM for SUPY_LICENSE_PRIVATE_KEY_B64. If a local .env exists and
// its private-key line is empty, the private key is written there for you.
//
// The private key is a SECRET. It is never printed to logs in production and
// never committed (.env is gitignored, *.pem is gitignored).

import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { publicKeyToBase64Url } from '../src/keys.js';

const { publicKey, privateKey } = crypto.generateKeyPairSync('ed25519');

const publicB64Url = publicKeyToBase64Url(publicKey);
const privatePem = privateKey.export({ format: 'pem', type: 'pkcs8' });
const privateB64 = Buffer.from(privatePem).toString('base64');

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const envPath = path.join(root, '.env');

let wroteEnv = false;
if (fs.existsSync(envPath)) {
  const env = fs.readFileSync(envPath, 'utf8');
  if (/^SUPY_LICENSE_PRIVATE_KEY_B64=\s*$/m.test(env)) {
    fs.writeFileSync(
      envPath,
      env.replace(
        /^SUPY_LICENSE_PRIVATE_KEY_B64=.*$/m,
        `SUPY_LICENSE_PRIVATE_KEY_B64=${privateB64}`,
      ),
    );
    wroteEnv = true;
  }
}

console.log('\n=== Ed25519 license keypair ===\n');
console.log('PUBLIC KEY — paste into lib/src/licensing/supy_license_verifier.dart');
console.log('  kSupyLicensePublicKeyBase64:');
console.log(`\n  ${publicB64Url}\n`);

if (wroteEnv) {
  console.log('PRIVATE KEY — written to .env (SUPY_LICENSE_PRIVATE_KEY_B64). Keep it secret.\n');
} else {
  console.log('PRIVATE KEY — set SUPY_LICENSE_PRIVATE_KEY_B64 to this (keep it secret):');
  console.log(`\n  ${privateB64}\n`);
  if (fs.existsSync(envPath)) {
    console.log('(.env already has a value; not overwriting.)\n');
  }
}
