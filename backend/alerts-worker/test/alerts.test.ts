import assert from "node:assert/strict";
import { test } from "node:test";
import { buildNotification, categorize, coarse, decide, type Device, type NWSAlert } from "../src/alerts.ts";

const now = 1_800_000_000;
const inAnHour = new Date((now + 3600) * 1000).toISOString();

const device: Device = {
  token: "a".repeat(64),
  environment: "sandbox",
  latitude: 35.92,
  longitude: -86.87,
  zones: ["TNZ027", "TNC187"],
  preferences: { warnings: true, watches: true, advisories: true, statements: false },
  placeName: "Franklin",
};

function alert(overrides: Partial<NWSAlert["properties"]> & { id?: string; geometry?: NWSAlert["geometry"] }): NWSAlert {
  const { id, geometry, ...properties } = overrides;
  return {
    id: id ?? "https://api.weather.gov/alerts/urn:1",
    geometry: geometry ?? null,
    properties: {
      event: "Flood Watch",
      headline: "Flood Watch until tomorrow",
      severity: "Moderate",
      messageType: "Alert",
      status: "Actual",
      expires: inAnHour,
      geocode: { UGC: ["TNZ027"] },
      ...properties,
    },
  };
}

// Square around Franklin, TN in GeoJSON [lon, lat] order.
const franklinBox: NWSAlert["geometry"] = {
  type: "Polygon",
  coordinates: [[[-87.0, 35.8], [-86.7, 35.8], [-86.7, 36.0], [-87.0, 36.0], [-87.0, 35.8]]],
};
const faraway: NWSAlert["geometry"] = {
  type: "Polygon",
  coordinates: [[[-90.0, 30.0], [-89.9, 30.0], [-89.9, 30.1], [-90.0, 30.1], [-90.0, 30.0]]],
};

test("categorizes NWS events like the app", () => {
  assert.equal(categorize("Tornado Warning"), "warning");
  assert.equal(categorize("Civil Emergency Message"), "warning");
  assert.equal(categorize("Evacuation Immediate"), "warning");
  assert.equal(categorize("Winter Storm Watch"), "watch");
  assert.equal(categorize("Wind Advisory"), "advisory");
  assert.equal(categorize("Special Weather Statement"), "statement");
});

test("zone-based alerts match by UGC code", () => {
  assert.equal(decide(alert({}), device, new Set(), now), "notify");
  assert.equal(decide(alert({ geocode: { UGC: ["KYZ001"] } }), device, new Set(), now), "skip");
});

test("polygon alerts match only inside the polygon, even when the county matches", () => {
  const inside = alert({ event: "Tornado Warning", geometry: franklinBox, geocode: { UGC: ["TNC187"] } });
  const outside = alert({ event: "Tornado Warning", geometry: faraway, geocode: { UGC: ["TNC187"] } });
  assert.equal(decide(inside, device, new Set(), now), "notify");
  assert.equal(decide(outside, device, new Set(), now), "skip");
});

test("respects preferences, cancellations, expiry, and prior deliveries", () => {
  assert.equal(decide(alert({ event: "Special Weather Statement" }), device, new Set(), now), "skip");
  assert.equal(decide(alert({ messageType: "Cancel" }), device, new Set(), now), "skip");
  assert.equal(decide(alert({ expires: new Date((now - 60) * 1000).toISOString() }), device, new Set(), now), "skip");
  assert.equal(decide(alert({ status: "Test" }), device, new Set(), now), "skip");
  const a = alert({});
  assert.equal(decide(a, device, new Set([a.id]), now), "skip");
});

test("updates to an alert the device already got stay silent; new areas still notify", () => {
  const update = alert({
    id: "https://api.weather.gov/alerts/urn:2",
    messageType: "Update",
    references: [{ "@id": "https://api.weather.gov/alerts/urn:1" }],
  });
  assert.equal(decide(update, device, new Set(["https://api.weather.gov/alerts/urn:1"]), now), "silent");
  assert.equal(decide(update, device, new Set(), now), "notify");
});

test("warnings are time-sensitive and carry the place name", () => {
  const n = buildNotification(alert({ event: "Tornado Warning", severity: "Extreme" }), device, now);
  assert.equal(n.title, "Tornado Warning");
  assert.equal(n.subtitle, "Franklin");
  assert.equal(n.timeSensitive, true);
  assert.equal(n.expiresAt, now + 3600);
  assert.equal(buildNotification(alert({}), device, now).timeSensitive, false);
});

test("coordinates are coarsened to about 1 km", () => {
  assert.equal(coarse(35.924871), 35.92);
  assert.equal(coarse(-86.868812), -86.87);
});
