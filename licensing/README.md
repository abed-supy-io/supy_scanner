# supy-licensing-backend

Billing + **offline-license issuance** backend for the paid `supy_scanner`
library. Stripe handles the money; this service turns a paid checkout into an
Ed25519-signed license token that the Flutter library verifies **100%
on-device** (no network in the scan path).

```
buyer → Stripe Checkout → webhook → issue signed token → store
device → /activate (claims a seat) → receives token → SupyScanner.activate(token)
```

## Why offline tokens

The library's non-negotiable constraint is *no network call in the scanning
path*. So the license is a self-contained signed token: the backend holds the
**private** Ed25519 key and signs; the library ships only the **public** key and
verifies locally. The device only talks to this backend once, out-of-band, at
activation time.

Token format (must stay byte-compatible with
`lib/src/licensing/supy_license_verifier.dart`):

```
supy-lic.v1.<base64url(payloadJson)>.<base64url(ed25519Signature)>
```

The signature covers the ASCII bytes of `supy-lic.v1.<payloadB64>`.

## Setup

```bash
npm install
cp .env.example .env
npm run keygen          # prints the PUBLIC key + writes the private key to .env
```

Paste the printed public key into the Flutter library's
`kSupyLicensePublicKeyBase64` (replacing the all-zero placeholder). Until you do,
the on-device gate stays closed and rejects every token.

```bash
npm test                # round-trip sign/verify + tamper/expiry checks
npm run dev             # start on :8080
```

## Endpoints

| Method | Path        | Body                          | Purpose |
|--------|-------------|-------------------------------|---------|
| GET    | `/health`   | —                             | liveness + whether Stripe/signing are configured |
| POST   | `/checkout` | `{ tier, email }`             | create a Stripe Checkout Session → `{ url }` (501 if Stripe unset) |
| POST   | `/webhook`  | Stripe event (raw)            | on `checkout.session.completed`, mint + store a license |
| POST   | `/activate` | `{ licenseId, deviceId }`     | claim a seat, return the signed `token` |
| POST   | `/validate` | `{ token }`                   | support tooling: mirror the on-device verify |

## Secrets

- `SUPY_LICENSE_PRIVATE_KEY_B64` is the only key that can mint valid licenses —
  keep it in secrets management, never commit it. `.env` and `*.pem` are
  gitignored.
- Never paste a real key into a chat/PR. If one leaks, rotate: run `keygen`,
  redeploy, ship a library update with the new public key.

## Scope

This is a **scaffold**: the store is a JSON file (`data/licenses.json`). Swap it
for a real database and add auth on `/activate` / `/validate` before production.
Logged decision: `../TODO.md` → Decisions log → *STRATEGIC REVERSAL (Phase PAID)*.
