import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { test } from 'node:test';

// Generate a throwaway signing key and inject it BEFORE importing modules that
// read config at load time.
const { privateKey } = crypto.generateKeyPairSync('ed25519');
process.env.SUPY_LICENSE_PRIVATE_KEY_B64 = Buffer.from(
  privateKey.export({ format: 'pem', type: 'pkcs8' }),
).toString('base64');

const { issueLicense, verifyToken } = await import('../src/license.js');
const { loadPrivateKey, publicFromPrivate } = await import('../src/keys.js');

const publicKey = publicFromPrivate(
  loadPrivateKey(process.env.SUPY_LICENSE_PRIVATE_KEY_B64),
);

test('issued token has the supy-lic.v1 shape', () => {
  const { token } = issueLicense({ tier: 'growth', seats: 5 });
  const parts = token.split('.');
  assert.equal(parts.length, 4);
  assert.equal(`${parts[0]}.${parts[1]}`, 'supy-lic.v1');
});

test('round-trips: a freshly issued token verifies', () => {
  const { token, record } = issueLicense({
    tier: 'enterprise',
    seats: 0,
    holder: 'acme@example.com',
  });
  const result = verifyToken(token, publicKey);
  assert.equal(result.valid, true);
  assert.equal(result.payload.tier, 'enterprise');
  assert.equal(result.payload.product, 'supy_scanner');
  assert.equal(result.payload.id, record.id);
});

test('a tampered payload fails signature verification', () => {
  const { token } = issueLicense({ tier: 'starter', seats: 1 });
  const parts = token.split('.');
  const forged = JSON.parse(
    Buffer.from(parts[2], 'base64url').toString('utf8'),
  );
  forged.tier = 'enterprise';
  parts[2] = Buffer.from(JSON.stringify(forged)).toString('base64url');
  const result = verifyToken(parts.join('.'), publicKey);
  assert.equal(result.valid, false);
  assert.equal(result.reason, 'bad_signature');
});

test('an already-expired token reports expired', () => {
  const past = new Date(Date.now() - 1000);
  const { token } = issueLicense({
    tier: 'starter',
    seats: 1,
    issuedAt: new Date(Date.now() - 2000),
    expiresAt: past,
  });
  const result = verifyToken(token, publicKey);
  assert.equal(result.valid, false);
  assert.equal(result.reason, 'expired');
});
