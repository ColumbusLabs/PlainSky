# The Weather App

A clean, ad-free native iOS weather app built with SwiftUI.

The product goal is intentionally simple:

> Open the app, understand the weather immediately, inspect anything interesting, and leave.

## Current status

The product shell and the keyless National Weather Service primary provider are implemented on `feat/initial-weather-app`.

Implemented:

- Today dashboard with current conditions, provider freshness, feels-like, next-hour precipitation, hourly forecast, daily forecast, radar preview, and tappable metric details.
- Daily and hourly Forecast modes with charts, day details, and hour details.
- Native MapKit Radar surface with timeline/playback controls, product availability, and Reduce Motion behavior.
- Places with current-location refresh, city/ZIP search, saved-place persistence, rename, reorder, and removal.
- First-run location/search onboarding.
- Official weather alert list and detail surfaces.
- U.S./Metric display units with one canonical internal unit basis.
- Light, Dark, and System appearance.
- Product-level available / unsupported / unavailable states.
- Automatic stale-data refresh when the app returns to the foreground.
- Source/freshness diagnostics.
- Keyless NWS point discovery, current station observations, hourly forecast, daily day/night forecast, raw grid enrichment, and official alerts.
- Stale-station rejection and fallback through nearby NWS stations.
- Honest NWS Tonight handling after the daytime period ends.
- Provider adapters and repository boundaries for NOAA radar and WeatherKit.
- Unit and repository tests covering source policy, NWS parsing/mapping, provider orchestration, persistence, fallback behavior, request contracts, location races, and saved-place rules.
- CI that builds the app, runs tests on an iPhone Simulator, and captures visual smoke screenshots.

Normal launches still use `PreviewWeatherRepository` so CI and visual review remain deterministic. Launch with `--live-nws` to exercise the real NWS primary provider.

## Weather source policy

| Product | Source |
| --- | --- |
| Current conditions | National Weather Service observation |
| Hourly forecast | National Weather Service forecast + grid fields |
| Daily forecast | National Weather Service forecast |
| Official alerts | National Weather Service |
| Radar | NOAA/NCEP — pending activation |
| Next-hour precipitation | Apple WeatherKit — pending activation |
| UV | Apple WeatherKit — pending activation |
| Sunrise / sunset | Apple WeatherKit — pending activation |

The app does **not** average forecasts or manufacture missing meteorological values.

Provider data is normalized into one internal unit basis. The U.S./Metric preference is a display conversion only.

## Development

The project is defined with XcodeGen:

```bash
brew install xcodegen
xcodegen generate
open WeatherApp.xcodeproj
```

To exercise real NWS data, add this launch argument in the Xcode scheme:

```
--live-nws
```

No NWS API key is required.

The app currently targets iOS 17+.

See:

- [Architecture](docs/ARCHITECTURE.md)
- [Live data activation checklist](docs/LIVE_DATA_CHECKLIST.md)
