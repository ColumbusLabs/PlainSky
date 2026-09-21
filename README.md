# PlainSky

A clean, ad-free native iOS weather app built with SwiftUI.

## Current state

The app now has a real no-key weather stack:

- **National Weather Service** for current observations, hourly/daily forecasts, and official alerts.
- **NOAA/NCEP** for live radar frames rendered over a native MapKit map.
- **Apple WeatherKit** is fully implemented as a supplemental adapter but remains runtime opt-in until the Apple Developer WeatherKit capability is enabled.

Normal launches use live NWS + NOAA. Deterministic UI testing uses `--preview-data`. After Apple-side WeatherKit activation, use `--live-weatherkit` to test Apple supplements.

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
