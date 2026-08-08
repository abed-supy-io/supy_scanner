import crypto from 'node:crypto';

import { config } from './config.js';
import { loadPrivateKey } from './keys.js';

// Detached-JWS-style license token. MUST stay byte-compatible with the Flutter
// verifier in lib/src/licensing/supy_license_verifier.dart:
//   token = "supy-lic.v1." + b64url(payloadJson) + "." + b64url(ed25519Sig)
//   signature covers the ASCII bytes of ("supy-lic.v1." + b64url(payloadJson))
const PREFIX = 'supy-lic.v1.';

function b64url(buf) {
  return Buffer.from(buf).toString('base64url');
}

/**
 * Mint a signed license token.
 *
 * @param {object} opts
 * @param {string} opts.tier      'starter' | 'growth' | 'enterprise'
 * @param {number} opts.seats     device activations allowed (0 = unmetered)
 * @param {string} [opts.holder]  org / email embedded for support
 * @param {Date}   [opts.issuedAt]
 * @param {Date}   [opts.expiresAt]
 * @param {string} [opts.id]      license id (generated if omitted)
 * @returns {{ token: string, record: object }}
 */
export function issueLicense(opts) {
  const privateKey = loadPrivateKey(config.licensePrivateKeyB64);

  const issuedAt = opts.issuedAt ?? new Date();
  const expiresAt =
    opts.expiresAt ??
    new Date(issuedAt.getTime() + config.licenseTermDays * 86_400_000);
  const id = opts.id ?? `${config.licenseIdPrefix}_${crypto.randomUUID()}`;

  const payload = {
    id,
    product: config.product,
    tier: opts.tier,
    seats: opts.seats ?? config.seatsByTier[opts.tier] ?? 0,
    iat: Math.floor(issuedAt.getTime() / 1000),
    exp: Math.floor(expiresAt.getTime() / 1000),
  };
  if (opts.holder) payload.holder = opts.holder;

  const payloadB64 = b64url(Buffer.from(JSON.stringify(payload), 'utf8'));
  const signingInput = Buffer.from(PREFIX + payloadB64, 'ascii');
  const signature = crypto.sign(null, signingInput, privateKey);

  const token = `${PREFIX}${payloadB64}.${b64url(signature)}`;
  return { token, record: { ...payload, token } };
}

/**
 * Verify a token the same way the Flutter library does — used by /validate and
 * the round-trip self-test. Signature check is offline; expiry is reported
 * separately so callers can tell "expired" from "invalid".
 *
 * @returns {{ valid: boolean, reason?: string, payload?: object, expired?: boolean }}
 */
export function verifyToken(token, publicKey) {
  const trimmed = String(token ?? '').trim();
  if (!trimmed.startsWith(PREFIX)) return { valid: false, reason: 'malformed' };

  const parts = trimmed.split('.');
  if (parts.length !== 4 || !parts[2] || !parts[3]) {
    return { valid: false, reason: 'malformed' };
  }

  const payloadB64 = parts[2];
  const signingInput = Buffer.from(PREFIX + payloadB64, 'ascii');

  let signature;
  let payload;
  try {
    signature = Buffer.from(parts[3], 'base64url');
    payload = JSON.parse(Buffer.from(payloadB64, 'base64url').toString('utf8'));
  } catch {
    return { valid: false, reason: 'malformed' };
  }

  if (!crypto.verify(null, signingInput, publicKey, signature)) {
    return { valid: false, reason: 'bad_signature' };
  }
  if (payload.product !== config.product) {
    return { valid: false, reason: 'wrong_product', payload };
  }

  const expired = payload.exp * 1000 <= Date.now();
  return { valid: !expired, reason: expired ? 'expired' : undefined, payload, expired };
}
