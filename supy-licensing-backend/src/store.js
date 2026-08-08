import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// Minimal file-backed license store. This is a SCAFFOLD — swap for Postgres/
// Dynamo/etc. in production. It records issued licenses and their per-device
// activations so /activate can enforce the seat count.

const dataDir = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  '..',
  'data',
);
const dbFile = path.join(dataDir, 'licenses.json');

function load() {
  try {
    return JSON.parse(fs.readFileSync(dbFile, 'utf8'));
  } catch {
    return { byId: {}, activations: {} };
  }
}

function persist(db) {
  fs.mkdirSync(dataDir, { recursive: true });
  fs.writeFileSync(dbFile, JSON.stringify(db, null, 2));
}

let db = load();

export function saveLicense(record) {
  db.byId[record.id] = record;
  db.activations[record.id] ??= [];
  persist(db);
}

export function getLicense(id) {
  return db.byId[id] ?? null;
}

/**
 * Register a device against a license, enforcing the seat count.
 * @returns {{ ok: boolean, reason?: string, seats?: number, used?: number }}
 */
export function activateDevice(id, deviceId) {
  const record = db.byId[id];
  if (!record) return { ok: false, reason: 'unknown_license' };

  const devices = (db.activations[id] ??= []);
  if (devices.includes(deviceId)) {
    return { ok: true, seats: record.seats, used: devices.length };
  }
  // seats === 0 means unmetered.
  if (record.seats !== 0 && devices.length >= record.seats) {
    return {
      ok: false,
      reason: 'seat_limit_reached',
      seats: record.seats,
      used: devices.length,
    };
  }
  devices.push(deviceId);
  persist(db);
  return { ok: true, seats: record.seats, used: devices.length };
}

// Test seam — reset the in-memory + on-disk store.
export function _resetForTests() {
  db = { byId: {}, activations: {} };
  try {
    fs.rmSync(dbFile);
  } catch {
    /* ignore */
  }
}
