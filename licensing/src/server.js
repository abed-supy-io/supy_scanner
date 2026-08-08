import express from 'express';

import { assertSigningConfigured, config } from './config.js';
import { issueLicense, verifyToken } from './license.js';
import { loadPrivateKey, publicFromPrivate } from './keys.js';
import { activateDevice, getLicense, saveLicense } from './store.js';
import {
  constructWebhookEvent,
  createCheckoutSession,
  isStripeConfigured,
  tierForSession,
} from './stripe.js';

const app = express();

app.get('/health', (_req, res) => {
  res.json({
    ok: true,
    product: config.product,
    stripe: isStripeConfigured(),
    signingConfigured: Boolean(config.licensePrivateKeyB64),
  });
});

// --- Checkout -------------------------------------------------------------
// POST /checkout { tier, email } -> { url }
app.post('/checkout', express.json(), async (req, res) => {
  const { tier, email } = req.body ?? {};
  const priceId = Object.entries(config.priceToTier).find(
    ([, t]) => t === tier,
  )?.[0];
  if (!tier || !priceId) {
    return res.status(400).json({ error: 'unknown_or_unconfigured_tier' });
  }
  if (!isStripeConfigured()) {
    return res.status(501).json({ error: 'stripe_not_configured' });
  }
  try {
    const session = await createCheckoutSession({ tier, priceId, email });
    res.json({ url: session.url });
  } catch (err) {
    res.status(502).json({ error: 'stripe_error', message: err.message });
  }
});

// --- Stripe webhook -------------------------------------------------------
// Raw body is required for signature verification, so this route uses
// express.raw rather than the JSON parser.
app.post(
  '/webhook',
  express.raw({ type: 'application/json' }),
  (req, res) => {
    let event;
    try {
      event = constructWebhookEvent(req.body, req.headers['stripe-signature']);
    } catch (err) {
      return res.status(400).json({ error: 'invalid_signature', message: err.message });
    }

    if (event.type === 'checkout.session.completed') {
      const session = event.data.object;
      const tier = tierForSession(session);
      if (!tier) {
        return res.status(422).json({ error: 'could_not_resolve_tier' });
      }
      try {
        assertSigningConfigured();
        const { record } = issueLicense({
          tier,
          seats: config.seatsByTier[tier],
          holder: session.customer_details?.email ?? session.customer_email,
        });
        saveLicense(record);
        // Production: email `record.id` (activation id) to the buyer here.
        console.log(`[license] issued ${record.id} tier=${tier}`);
      } catch (err) {
        return res.status(500).json({ error: 'issue_failed', message: err.message });
      }
    }
    res.json({ received: true });
  },
);

// --- Activation (device claims a seat, receives its token) ----------------
// POST /activate { licenseId, deviceId } -> { token }
app.post('/activate', express.json(), (req, res) => {
  const { licenseId, deviceId } = req.body ?? {};
  if (!licenseId || !deviceId) {
    return res.status(400).json({ error: 'licenseId_and_deviceId_required' });
  }
  const result = activateDevice(licenseId, deviceId);
  if (!result.ok) {
    return res.status(result.reason === 'unknown_license' ? 404 : 409).json(result);
  }
  const record = getLicense(licenseId);
  res.json({ token: record.token, seats: result.seats, used: result.used });
});

// --- Validation (support tooling; mirrors the on-device check) ------------
// POST /validate { token } -> { valid, reason?, expired?, tier? }
app.post('/validate', express.json(), (req, res) => {
  const publicKey = publicFromPrivate(
    loadPrivateKey(config.licensePrivateKeyB64),
  );
  const result = verifyToken(req.body?.token, publicKey);
  res.json({
    valid: result.valid,
    reason: result.reason,
    expired: result.expired,
    tier: result.payload?.tier,
    id: result.payload?.id,
  });
});

// Only listen when run directly (not when imported by tests).
if (process.argv[1] && process.argv[1].endsWith('server.js')) {
  app.listen(config.port, () => {
    console.log(`supy-licensing-backend listening on :${config.port}`);
  });
}

export { app };
