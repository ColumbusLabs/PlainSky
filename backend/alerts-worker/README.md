# PlainSky alerts worker

Cloudflare Worker that pushes official NWS alerts to PlainSky users within about a minute.

- **Every minute** (cron): fetch `api.weather.gov/alerts/active`, take alerts not seen before, match them to registered phones, and send through APNs.
  - Storm-based alerts with a polygon (tornado, severe thunderstorm, flash flood warnings) match only phones inside the polygon.
  - Zone/county alerts match on the phone's NWS forecast zone, county, and fire weather zone (UGC codes).
  - Updates to an alert a phone already received and cancellations are silent.
- **`POST /v1/devices`**: the app registers `{token, environment, latitude, longitude, placeName, preferences}`. Coordinates are rounded to 2 decimals (~1 km) before storage, and alerts already active for that place are sent right away.
- **`DELETE /v1/devices/:token`**: the app removes itself when notifications are turned off.
- **`GET /health`**: device count and whether APNs is configured.

Rain notices stay on the phone (Apple next-hour precipitation); they are not sent by this worker.

## Setup

```bash
npm install
npm run migrate          # apply D1 migrations
npx wrangler secret put APNS_KEY_ID
npx wrangler secret put APNS_PRIVATE_KEY < AuthKey_XXXXXXXXXX.p8
npm run deploy
npm test
```

Secrets are never committed; this repository is public.
