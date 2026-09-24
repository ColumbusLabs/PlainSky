# PlainSky

A clean, ad-free native iOS weather app built with SwiftUI.

## Current state

The app now has a real no-key weather stack:

- **National Weather Service** for current observations, hourly/daily forecasts, and official alerts.
- **NOAA/NCEP** for live radar frames rendered over a native MapKit map.
- **Apple WeatherKit** supplements NWS with next-hour precipitation, UV, solar events, and a whole-group current-condition fallback. It never replaces NWS forecasts or alerts, or NOAA radar.

Normal launches use each provider only for those assigned products: NWS for primary weather, NOAA/NCEP for radar, and WeatherKit for supplements. Deterministic UI testing uses `--preview-data`; `--live-nws` disables WeatherKit for diagnostics.

Live launches never show cached weather. The selected place appears immediately and each section fills in as soon as its own fresh NWS or WeatherKit result is validated.

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
