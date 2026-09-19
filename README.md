# The Weather App

A clean, ad-free iOS weather app built with SwiftUI.

## Product direction

The app is intentionally simple: open it, understand the weather immediately, inspect anything interesting, and leave.

The source policy is explicit:

- **National Weather Service (NWS)** — primary U.S. forecasts, official alerts, and nearby station observations.
- **NOAA/NCEP** — radar imagery and precipitation visualization.
- **Apple WeatherKit** — narrowly scoped supplemental products such as next-hour precipitation, UV, and solar data.
- **No homemade meteorology** — provider-supplied values are displayed with source and freshness metadata.

Live providers are deliberately kept behind adapters so the complete product can be built and reviewed with deterministic mock data before provider entitlements are enabled.

## Development

The project definition is kept in `project.yml` using XcodeGen.

```bash
brew install xcodegen
xcodegen generate
open WeatherApp.xcodeproj
```

The app currently targets iOS 17+.

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

Development is being implemented in small, reviewable commits on `feat/initial-weather-app`.
