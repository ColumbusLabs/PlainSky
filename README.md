# PlainSky

A completely free, ad-free native iOS weather app built with SwiftUI. No subscriptions, in-app purchases, or paid feature tiers.

## Current state

The app now has a real no-key weather stack:

- **National Weather Service** for current observations, hourly/daily forecasts, and official alerts.
- **NOAA/NCEP** for live radar frames rendered over a native MapKit map.
- **Apple WeatherKit** supplements NWS with next-hour precipitation, UV, solar events, and a whole-group current-condition fallback. It never replaces NWS forecasts or alerts, or NOAA radar.

Normal launches use each provider only for those assigned products: NWS for primary weather, NOAA/NCEP for radar, and WeatherKit for supplements. Deterministic UI testing uses `--preview-data`; `--live-nws` disables WeatherKit for diagnostics.

Live launches never show cached weather. On a cold launch, or a resume without usable current conditions, a loading screen matching the launch screen holds for up to 1.5 seconds while current conditions, hourly and daily forecasts, and sunrise/sunset resolve, so the app opens on a background that matches the weather. Anything slower fills in on screen as soon as its own fresh NWS or WeatherKit result is validated.

The app does not average providers or invent meteorology.

## Features

- Today dashboard with source/freshness metadata
- provider-supplied feels-like
- hourly and daily forecasts
- official alerts, with notifications for NWS warnings, watches, advisories, and statements (toggle each in Settings)
- "Rain begins around 1:25 PM" notifications from Apple next-hour precipitation
- small home screen widget: current temperature, today's high/low, the next three hours
- live animated NOAA radar
- saved places and current-location refresh (Settings tab)
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

Primary forecasts and alerts cover the United States and supported U.S. territories. Apple Weather supplements and NOAA radar products vary by location.

PlainSky is open source under the [MIT License](LICENSE). Explore the code, report issues, and contribute through this repository.

See:

- [Architecture](docs/ARCHITECTURE.md)
- [Live data checklist](docs/LIVE_DATA_CHECKLIST.md)
- [WeatherKit activation](docs/WEATHERKIT_SETUP.md)
- [Privacy policy](docs/PRIVACY.md)
- [Support](docs/SUPPORT.md)
- [App Store listing](docs/APP_STORE_METADATA.md)
