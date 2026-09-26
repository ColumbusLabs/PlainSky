import {
  buildNotification,
  coarse,
  decide,
  expiresAt,
  type Device,
  type NWSAlert,
  type Preferences,
} from "./alerts.ts";
import { send, type APNsConfig } from "./apns.ts";

interface Env {
  DB: D1Database;
  APNS_TEAM_ID: string;
  APNS_BUNDLE_ID: string;
  APNS_SANDBOX_KEY_ID?: string;
  APNS_SANDBOX_PRIVATE_KEY?: string;
  APNS_PRODUCTION_KEY_ID?: string;
  APNS_PRODUCTION_PRIVATE_KEY?: string;
}

const NWS_HEADERS = {
  "user-agent": "PlainSky alerts (github.com/ColumbusLabs/PlainSky)",
  accept: "application/geo+json",
};

interface DeviceRow {
  token: string;
  environment: "sandbox" | "production";
  latitude: number;
  longitude: number;
  zones: string;
  preferences: string;
  place_name: string;
}

function toDevice(row: DeviceRow): Device {
  return {
    token: row.token,
    environment: row.environment,
    latitude: row.latitude,
    longitude: row.longitude,
    zones: JSON.parse(row.zones),
    preferences: JSON.parse(row.preferences),
    placeName: row.place_name,
  };
}

function apnsConfig(env: Env, environment: "sandbox" | "production"): APNsConfig | null {
  const keyId = environment === "sandbox" ? env.APNS_SANDBOX_KEY_ID : env.APNS_PRODUCTION_KEY_ID;
  const privateKey = environment === "sandbox" ? env.APNS_SANDBOX_PRIVATE_KEY : env.APNS_PRODUCTION_PRIVATE_KEY;
  if (!keyId || !privateKey) return null;
  return {
    teamId: env.APNS_TEAM_ID,
    keyId,
    privateKey,
    bundleId: env.APNS_BUNDLE_ID,
  };
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

async function fetchAlerts(query: string): Promise<NWSAlert[]> {
  const response = await fetch(`https://api.weather.gov/alerts/active?${query}`, { headers: NWS_HEADERS });
  if (!response.ok) throw new Error(`NWS alerts ${response.status}`);
  const body = await response.json<{ features: NWSAlert[] }>();
  return body.features ?? [];
}

/** UGC codes for the point: forecast zone, county, and fire weather zone. */
async function zonesFor(latitude: number, longitude: number): Promise<string[]> {
  const response = await fetch(`https://api.weather.gov/points/${latitude},${longitude}`, { headers: NWS_HEADERS });
  if (response.status === 404) return []; // Outside NWS coverage.
  if (!response.ok) throw new Error(`NWS points ${response.status}`);
  const body = await response.json<{ properties: Record<string, unknown> }>();
  return ["forecastZone", "county", "fireWeatherZone"]
    .map((key) => body.properties[key])
    .filter((url): url is string => typeof url === "string")
    .map((url) => url.split("/").pop()!)
    .filter(Boolean);
}

/**
 * Sends every alert that should reach these devices and records the outcome.
 * Returns how many pushes went out.
 */
async function deliver(env: Env, alerts: NWSAlert[], devices: Device[], now: number): Promise<number> {
  if (alerts.length === 0 || devices.length === 0) return 0;

  const tokens = devices.map((d) => d.token);
  const deliveredRows: { alert_id: string; token: string }[] = [];
  // D1 caps bound parameters per statement, so look tokens up in chunks.
  for (let i = 0; i < tokens.length; i += 90) {
    const chunk = tokens.slice(i, i + 90);
    const result = await env.DB
      .prepare(`SELECT alert_id, token FROM deliveries WHERE token IN (${chunk.map(() => "?").join(",")})`)
      .bind(...chunk)
      .all<{ alert_id: string; token: string }>();
    deliveredRows.push(...result.results);
  }

  const deliveredByToken = new Map<string, Set<string>>();
  for (const row of deliveredRows) {
    if (!deliveredByToken.has(row.token)) deliveredByToken.set(row.token, new Set());
    deliveredByToken.get(row.token)!.add(row.alert_id);
  }

  const writes: D1PreparedStatement[] = [];
  const invalidTokens = new Set<string>();
  let sent = 0;

  const record = env.DB.prepare(
    "INSERT OR IGNORE INTO deliveries (alert_id, token, sent_at) VALUES (?, ?, ?)"
  );

  const jobs: Promise<void>[] = [];
  for (const device of devices) {
    const config = apnsConfig(env, device.environment);
    const deliveredIds = deliveredByToken.get(device.token) ?? new Set<string>();
    for (const alert of alerts) {
      const decision = decide(alert, device, deliveredIds, now);
      if (decision === "skip") continue;
      if (decision === "silent") {
        writes.push(record.bind(alert.id, device.token, now));
        continue;
      }
      if (!config) {
        console.warn("APNs key not configured; skipping push for", alert.id);
        continue;
      }
      const notification = buildNotification(alert, device, now);
      jobs.push(
        send(config, device.environment, device.token, notification, now).then((result) => {
          if (result === "sent") {
            sent += 1;
            writes.push(record.bind(alert.id, device.token, now));
          } else if (result === "invalid-token") {
            invalidTokens.add(device.token);
          }
        })
      );
    }
  }

  await Promise.all(jobs);

  for (const token of invalidTokens) {
    writes.push(env.DB.prepare("DELETE FROM devices WHERE token = ?").bind(token));
    writes.push(env.DB.prepare("DELETE FROM deliveries WHERE token = ?").bind(token));
  }
  if (writes.length > 0) await env.DB.batch(writes);
  return sent;
}

/** Every minute: find alerts not seen before and push them to affected devices. */
async function checkAlerts(env: Env): Promise<void> {
  const now = Math.floor(Date.now() / 1000);
  const alerts = await fetchAlerts("status=actual");

  const seen = await env.DB.prepare("SELECT alert_id FROM seen_alerts").all<{ alert_id: string }>();
  const seenIds = new Set(seen.results.map((row) => row.alert_id));
  const fresh = alerts.filter((alert) => !seenIds.has(alert.id));

  if (fresh.length > 0) {
    const devices = await env.DB.prepare("SELECT * FROM devices").all<DeviceRow>();
    const sent = await deliver(env, fresh, devices.results.map(toDevice), now);
    console.log(`alerts: ${alerts.length} active, ${fresh.length} new, ${sent} pushes`);

    const mark = env.DB.prepare("INSERT OR IGNORE INTO seen_alerts (alert_id, forget_at) VALUES (?, ?)");
    const marks = fresh.map((alert) => mark.bind(alert.id, expiresAt(alert, now) + 24 * 3600));
    for (let i = 0; i < marks.length; i += 100) {
      await env.DB.batch(marks.slice(i, i + 100));
    }
  }

  await env.DB.batch([
    env.DB.prepare("DELETE FROM seen_alerts WHERE forget_at < ?").bind(now),
    env.DB.prepare("DELETE FROM deliveries WHERE sent_at < ?").bind(now - 7 * 24 * 3600),
  ]);
}

function parsePreferences(value: unknown): Preferences | null {
  if (!value || typeof value !== "object") return null;
  const v = value as Record<string, unknown>;
  const keys = ["warnings", "watches", "advisories", "statements"] as const;
  if (!keys.every((key) => typeof v[key] === "boolean")) return null;
  return { warnings: v.warnings as boolean, watches: v.watches as boolean, advisories: v.advisories as boolean, statements: v.statements as boolean };
}

async function register(request: Request, env: Env): Promise<Response> {
  const body = await request.json<Record<string, unknown>>().catch(() => null);
  if (!body) return json({ error: "invalid JSON" }, 400);

  const token = typeof body.token === "string" ? body.token.toLowerCase() : "";
  const environment = body.environment;
  const latitude = Number(body.latitude);
  const longitude = Number(body.longitude);
  const placeName = typeof body.placeName === "string" ? body.placeName.slice(0, 80) : "";
  const preferences = parsePreferences(body.preferences);

  if (!/^[0-9a-f]{64,200}$/.test(token)) return json({ error: "invalid token" }, 400);
  if (environment !== "sandbox" && environment !== "production") return json({ error: "invalid environment" }, 400);
  if (!(Math.abs(latitude) <= 90 && Math.abs(longitude) <= 180)) return json({ error: "invalid coordinates" }, 400);
  if (!preferences) return json({ error: "invalid preferences" }, 400);
  if (!apnsConfig(env, environment)) return json({ error: "push service unavailable" }, 503);

  const lat = coarse(latitude);
  const lon = coarse(longitude);
  let zones: string[];
  try {
    zones = await zonesFor(lat, lon);
  } catch {
    return json({ error: "zone lookup failed" }, 502);
  }

  const now = Math.floor(Date.now() / 1000);
  await env.DB.prepare(
    `INSERT INTO devices (token, environment, latitude, longitude, zones, preferences, place_name, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT (token) DO UPDATE SET
       environment = excluded.environment, latitude = excluded.latitude, longitude = excluded.longitude,
       zones = excluded.zones, preferences = excluded.preferences, place_name = excluded.place_name,
       updated_at = excluded.updated_at`
  ).bind(token, environment, lat, lon, JSON.stringify(zones), JSON.stringify(preferences), placeName, now).run();

  // Catch up on alerts that were already active before this phone registered
  // or moved its alert place. Deliveries keep this from repeating.
  const device: Device = { token, environment, latitude: lat, longitude: lon, zones, preferences, placeName };
  let caughtUp = 0;
  try {
    caughtUp = await deliver(env, await fetchAlerts(`point=${lat},${lon}`), [device], now);
  } catch (error) {
    console.warn("catch-up failed", String(error));
  }

  return json({ ok: true, zones, caughtUp });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "GET" && url.pathname === "/health") {
      const devices = await env.DB.prepare("SELECT COUNT(*) AS count FROM devices").first<{ count: number }>();
      return json({
        ok: true,
        devices: devices?.count ?? 0,
        apnsConfigured: apnsConfig(env, "sandbox") !== null && apnsConfig(env, "production") !== null,
        apnsSandboxConfigured: apnsConfig(env, "sandbox") !== null,
        apnsProductionConfigured: apnsConfig(env, "production") !== null,
      });
    }

    if (request.method === "POST" && url.pathname === "/v1/devices") {
      return register(request, env);
    }

    const match = url.pathname.match(/^\/v1\/devices\/([0-9a-fA-F]{64,200})$/);
    if (request.method === "DELETE" && match) {
      const token = match[1].toLowerCase();
      await env.DB.batch([
        env.DB.prepare("DELETE FROM devices WHERE token = ?").bind(token),
        env.DB.prepare("DELETE FROM deliveries WHERE token = ?").bind(token),
      ]);
      return json({ ok: true });
    }

    return json({ error: "not found" }, 404);
  },

  // Awaited (not waitUntil) so a failed check marks the cron run as failed.
  async scheduled(_controller: ScheduledController, env: Env): Promise<void> {
    await checkAlerts(env);
  },
} satisfies ExportedHandler<Env>;
