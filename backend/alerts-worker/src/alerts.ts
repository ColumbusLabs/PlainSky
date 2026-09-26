// Pure alert logic: categorizing NWS events, matching alerts to devices, and
// building notifications. No I/O so it can be unit tested with `node --test`.

export type Category = "warning" | "watch" | "advisory" | "statement";

export interface Preferences {
  warnings: boolean;
  watches: boolean;
  advisories: boolean;
  statements: boolean;
}

export interface Device {
  token: string;
  environment: "sandbox" | "production";
  latitude: number;
  longitude: number;
  zones: string[];
  preferences: Preferences;
  placeName: string;
}

type Ring = [number, number][];
type Geometry =
  | { type: "Polygon"; coordinates: Ring[] }
  | { type: "MultiPolygon"; coordinates: Ring[][] }
  | null;

export interface NWSAlert {
  id: string;
  geometry: Geometry;
  properties: {
    event: string;
    headline?: string | null;
    description?: string | null;
    severity?: string | null;
    messageType?: string | null;
    status?: string | null;
    expires?: string | null;
    ends?: string | null;
    references?: { "@id": string }[] | null;
    geocode?: { UGC?: string[] | null } | null;
  };
}

export interface Notification {
  alertId: string;
  title: string;
  subtitle: string;
  body: string;
  timeSensitive: boolean;
  expiresAt: number;
}

/** Mirrors WeatherAlertCategory in the iOS app. */
export function categorize(event: string): Category {
  const lowered = event.toLowerCase();
  if (lowered.endsWith("warning") || lowered.includes("emergency") || lowered.startsWith("evacuation")) {
    return "warning";
  }
  if (lowered.endsWith("watch")) return "watch";
  if (lowered.endsWith("advisory")) return "advisory";
  return "statement";
}

export function allows(preferences: Preferences, category: Category): boolean {
  switch (category) {
    case "warning": return preferences.warnings;
    case "watch": return preferences.watches;
    case "advisory": return preferences.advisories;
    case "statement": return preferences.statements;
  }
}

/** Ray casting on GeoJSON [lon, lat] rings. Holes are ignored; NWS polygons don't use them. */
function inRing(lon: number, lat: number, ring: Ring): boolean {
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [xi, yi] = ring[i];
    const [xj, yj] = ring[j];
    if ((yi > lat) !== (yj > lat) && lon < ((xj - xi) * (lat - yi)) / (yj - yi) + xi) {
      inside = !inside;
    }
  }
  return inside;
}

export function containsPoint(geometry: Geometry, latitude: number, longitude: number): boolean {
  if (!geometry) return false;
  const polygons = geometry.type === "Polygon" ? [geometry.coordinates] : geometry.coordinates;
  return polygons.some((rings) => rings.length > 0 && inRing(longitude, latitude, rings[0]));
}

/**
 * Storm-based alerts (tornado, severe thunderstorm, flash flood warnings) carry
 * a polygon and only that area is affected. Zone- and county-based alerts have
 * no geometry and are matched by UGC code.
 */
export function affects(alert: NWSAlert, device: Device): boolean {
  if (alert.geometry) {
    return containsPoint(alert.geometry, device.latitude, device.longitude);
  }
  const codes = alert.properties.geocode?.UGC ?? [];
  return codes.some((code) => device.zones.includes(code));
}

export function expiresAt(alert: NWSAlert, now: number): number {
  const raw = alert.properties.expires ?? alert.properties.ends;
  const parsed = raw ? Date.parse(raw) : NaN;
  return Number.isFinite(parsed) ? Math.floor(parsed / 1000) : now + 6 * 3600;
}

export type Decision = "notify" | "silent" | "skip";

/**
 * - skip: not for this device (area, preference, cancellation, expired)
 * - silent: an update to something this device was already told about
 * - notify: send a push
 */
export function decide(
  alert: NWSAlert,
  device: Device,
  deliveredIds: Set<string>,
  now: number
): Decision {
  const props = alert.properties;
  if ((props.status ?? "Actual") !== "Actual") return "skip";
  if ((props.messageType ?? "").toLowerCase() === "cancel") return "skip";
  if (expiresAt(alert, now) <= now) return "skip";
  if (deliveredIds.has(alert.id)) return "skip";
  if (!affects(alert, device)) return "skip";
  if (!allows(device.preferences, categorize(props.event))) return "skip";

  const references = props.references ?? [];
  if ((props.messageType ?? "").toLowerCase() === "update" &&
      references.some((ref) => deliveredIds.has(ref["@id"]))) {
    return "silent";
  }
  return "notify";
}

export function buildNotification(alert: NWSAlert, device: Device, now: number): Notification {
  const props = alert.properties;
  const severity = (props.severity ?? "").toLowerCase();
  const body = props.headline?.trim() || (props.description ?? "").trim().slice(0, 240) || props.event;
  return {
    alertId: alert.id,
    title: props.event,
    subtitle: device.placeName,
    body,
    timeSensitive: categorize(props.event) === "warning" || severity === "severe" || severity === "extreme",
    expiresAt: expiresAt(alert, now),
  };
}

/** Rounds to two decimals (~1 km) before anything is stored. */
export function coarse(value: number): number {
  return Math.round(value * 100) / 100;
}
