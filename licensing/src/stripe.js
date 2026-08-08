import Stripe from 'stripe';

import { config } from './config.js';

// Lazily construct the Stripe client so the service still boots (for /activate,
// /validate, keygen, and tests) when Stripe isn't configured in dev.
let client = null;
export function stripe() {
  if (!config.stripeSecretKey) return null;
  client ??= new Stripe(config.stripeSecretKey);
  return client;
}

export function isStripeConfigured() {
  return Boolean(config.stripeSecretKey);
}

/** Create a Checkout Session for a tier's configured price. */
export async function createCheckoutSession({ tier, priceId, email }) {
  const s = stripe();
  if (!s) throw new Error('stripe_not_configured');
  return s.checkout.sessions.create({
    mode: 'subscription',
    line_items: [{ price: priceId, quantity: 1 }],
    customer_email: email,
    // The tier travels in metadata so the webhook can mint the right license
    // without a second Price lookup.
    metadata: { tier, product: config.product },
    success_url: `${config.publicUrl}/checkout/success?session_id={CHECKOUT_SESSION_ID}`,
    cancel_url: `${config.publicUrl}/checkout/cancel`,
  });
}

/**
 * Verify + parse a Stripe webhook. Returns the typed event. Throws if the
 * signature doesn't verify (never trust an unverified webhook body).
 */
export function constructWebhookEvent(rawBody, signature) {
  const s = stripe();
  if (!s) throw new Error('stripe_not_configured');
  return s.webhooks.constructEvent(
    rawBody,
    signature,
    config.stripeWebhookSecret,
  );
}

/** Resolve the tier for a completed checkout session (metadata first, then price map). */
export function tierForSession(session) {
  if (session?.metadata?.tier) return session.metadata.tier;
  const priceId = session?.line_items?.data?.[0]?.price?.id;
  return priceId ? config.priceToTier[priceId] : undefined;
}
