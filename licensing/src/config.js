// Central config, read once from the environment. No secrets are hardcoded —
// everything sensitive comes from process.env (see .env.example).

function num(value, fallback) {
  const n = Number.parseInt(value ?? '', 10);
  return Number.isFinite(n) ? n : fallback;
}

export const config = {
  port: num(process.env.PORT, 8080),
  publicUrl: process.env.PUBLIC_URL ?? 'http://localhost:8080',

  // The Ed25519 private signing key (base64 PKCS8 PEM). Required to mint tokens.
  licensePrivateKeyB64: process.env.SUPY_LICENSE_PRIVATE_KEY_B64 ?? '',
  licenseIdPrefix: process.env.LICENSE_ID_PREFIX ?? 'lic',
  licenseTermDays: num(process.env.LICENSE_TERM_DAYS, 365),

  stripeSecretKey: process.env.STRIPE_SECRET_KEY ?? '',
  stripeWebhookSecret: process.env.STRIPE_WEBHOOK_SECRET ?? '',

  // Stripe Price id -> tier. Only non-empty entries are used.
  priceToTier: Object.fromEntries(
    [
      [process.env.STRIPE_PRICE_STARTER, 'starter'],
      [process.env.STRIPE_PRICE_GROWTH, 'growth'],
      [process.env.STRIPE_PRICE_ENTERPRISE, 'enterprise'],
    ].filter(([price]) => Boolean(price)),
  ),

  seatsByTier: {
    starter: num(process.env.SEATS_STARTER, 1),
    growth: num(process.env.SEATS_GROWTH, 5),
    enterprise: num(process.env.SEATS_ENTERPRISE, 0),
  },

  product: 'supy_scanner',
};

export function assertSigningConfigured() {
  if (!config.licensePrivateKeyB64) {
    throw new Error(
      'SUPY_LICENSE_PRIVATE_KEY_B64 is not set. Run `npm run keygen` first.',
    );
  }
}
