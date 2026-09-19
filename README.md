# The Weather App

A clean, ad-free native iOS weather app built with SwiftUI.

The product goal is intentionally simple:

> Open the app, understand the weather immediately, inspect anything interesting, and leave.

## Current status

The complete non-provider product shell is implemented on `feat/initial-weather-app`.

Implemented:

- Today dashboard with current conditions, provider freshness, feels-like, next-hour precipitation, hourly forecast, daily forecast, radar preview, and tappable metric details.
- Daily and hourly Forecast modes with charts, day details, and hour details.
- Native MapKit Radar surface with timeline/playback controls, product availability, and Reduce Motion behavior.
- Places with current-location refresh, city/ZIP search, saved-place persistence, rename, reorder, and removal.
- First-run location/search onboarding.
- Official weather alert list and detail surfaces.
- U.S./Metric display units with canonical internal units.
- Light, Dark, and System appearance.
- Product-level available / unsupported / unavailable states.
- Automatic stale-data refresh when the app returns to the foreground.
- Source/freshness diagnostics.
- Provider adapters and repository boundaries for NWS, NOAA radar, and WeatherKit.
- Unit and repository tests covering source policy, persistence, fallback behavior, request contracts, location races, and saved-place rules.
- CI that builds the app, runs tests on an iPhone Simulator, and captures visual smoke screenshots.

Live provider mapping remains intentionally disabled behind `PreviewWeatherRepository`.

## Weather source policy

| Product | Planned source |
| --- | --- |
| Current conditions | National Weather Service observation |
| Hourly forecast | National Weather Service forecast/grid |
| Daily forecast | National Weather Service forecast |
| Official alerts | National Weather Service |
| Radar | NOAA/NCEP |
| Next-hour precipitation | Apple WeatherKit |
| UV | Apple WeatherKit |
| Sunrise / sunset | Apple WeatherKit |

The app does **not** average forecasts or manufacture missing meteorological values.

Provider data is normalized into one internal unit basis. The U.S./Metric preference is a display conversion only.

## Development

The project is defined with XcodeGen:

```bash
brew install xcodegen
xcodegen generate
open WeatherApp.xcodeproj
```

The app currently targets iOS 17+.

See:

- [Architecture](docs/ARCHITECTURE.md)
- [Live data activation checklist](docs/LIVE_DATA_CHECKLIST.md)
