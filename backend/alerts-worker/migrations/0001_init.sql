-- Phones that want alerts. Coordinates are rounded to ~1 km before storage.
CREATE TABLE devices (
  token TEXT PRIMARY KEY,
  environment TEXT NOT NULL CHECK (environment IN ('sandbox', 'production')),
  latitude REAL NOT NULL,
  longitude REAL NOT NULL,
  zones TEXT NOT NULL,        -- JSON array of NWS UGC codes, e.g. ["TNZ027","TNC187"]
  preferences TEXT NOT NULL,  -- JSON {warnings, watches, advisories, statements}
  place_name TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);

-- NWS alert IDs already processed, kept until shortly after they expire.
CREATE TABLE seen_alerts (
  alert_id TEXT PRIMARY KEY,
  forget_at INTEGER NOT NULL
);

-- Which device was told about which alert, so updates stay silent.
CREATE TABLE deliveries (
  alert_id TEXT NOT NULL,
  token TEXT NOT NULL,
  sent_at INTEGER NOT NULL,
  PRIMARY KEY (alert_id, token)
);
CREATE INDEX deliveries_token ON deliveries (token);
