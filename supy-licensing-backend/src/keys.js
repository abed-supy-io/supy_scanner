import crypto from 'node:crypto';

// Ed25519 key helpers shared by the signer and the keygen script.

/** Load the private signing key from a base64-encoded PKCS8 PEM string. */
export function loadPrivateKey(b64Pem) {
  const pem = Buffer.from(b64Pem, 'base64').toString('utf8');
  return crypto.createPrivateKey({ key: pem, format: 'pem', type: 'pkcs8' });
}

/**
 * Raw 32-byte Ed25519 public key as base64url — this is exactly the value the
 * Flutter library embeds in `kSupyLicensePublicKeyBase64`.
 */
export function publicKeyToBase64Url(publicKey) {
  const jwk = publicKey.export({ format: 'jwk' });
  // JWK `x` is already the base64url of the raw 32-byte public key.
  return jwk.x;
}

/** Derive the public key that matches a given private key. */
export function publicFromPrivate(privateKey) {
  return crypto.createPublicKey(privateKey);
}
