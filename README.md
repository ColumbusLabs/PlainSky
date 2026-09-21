# PlainSky

A clean, ad-free native iOS weather app built with SwiftUI.

## Current state

The app now has a real no-key weather stack:

- **National Weather Service** for current observations, hourly/daily forecasts, and official alerts.
- **NOAA/NCEP** for live radar frames rendered over a native MapKit map.
- **Apple WeatherKit** supplements NWS with next-hour precipitation, UV, solar events, and a whole-group current-condition fallback. The adapter is implemented, but remains opt-in pending Apple-side capability setup and physical-device validation.

Normal launches use live NWS + NOAA. Deterministic UI testing uses `--preview-data`; launch with `--live-weatherkit` to opt into WeatherKit supplements after Apple-side activation.

Live launches restore a matching cached snapshot immediately when it is no more than six hours old, then refresh primary NWS data and, when enabled, supplemental products in stages. Expired snapshots are ignored.

The app does not average providers or invent meteorology.

## Features

- Today dashboard with source/freshness metadata
- provider-supplied feels-like
- hourly and daily forecasts
- official alerts
- live animated NOAA radar
- saved places and current-location refresh
- U.S./Metric units
- Light/Dark/System appearance
- accessibility / Dynamic Type / Reduce Motion support
- diagnostics and per-product availability
- no ads, accounts, or third-party analytics

## Development

```bash
brew install xcodegen
xcodegen generate
open PlainSky.xcodeproj
```

iOS 17+.

See:

- [Architecture](docs/ARCHITECTURE.md)
- [Live data checklist](docs/LIVE_DATA_CHECKLIST.md)
- [WeatherKit activation](docs/WEATHERKIT_SETUP.md)
