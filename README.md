# PlainSky

<img src="PlainSky/Resources/Assets.xcassets/AppIcon.appiconset/PlainSky-1024.png" alt="PlainSky app icon" width="96">

Free, ad-free weather for iPhone, built with SwiftUI by Columbus Labs. Check current conditions, forecasts, radar, and official alerts without an account, subscription, in-app purchase, or paid feature tier.

Primary forecasts and alerts cover the United States and supported U.S. territories. Apple Weather supplements and NOAA radar products vary by location. Requires iOS 17 or later and an internet connection for fresh weather data.

## Features

- Current conditions with source and freshness details, including provider-supplied feels-like temperature.
- Hourly and daily forecasts, live animated NOAA radar, and official NWS alerts.
- Optional notifications for NWS warnings, watches, advisories, and statements, plus precipitation-start notices where Apple next-hour data is available.
- A small Home Screen widget with current temperature, today's high/low, and the next three hours.
- Saved places, optional current-location refresh, U.S./metric units, and light/dark/system appearance.
- Dynamic Type, Reduce Motion, diagnostics, and per-product availability details.
- No ads, accounts, or third-party analytics.

## Weather sources

PlainSky uses each weather source for the products it supplies:

- **National Weather Service** for current observations, hourly/daily forecasts, and official alerts.
- **NOAA/NCEP** for live radar frames rendered over a native MapKit map.
- **Apple WeatherKit** supplements NWS with next-hour precipitation, UV, solar events, and a whole-group current-condition fallback. It never replaces NWS forecasts or alerts, or NOAA radar.

Normal launches use each provider only for those assigned products: NWS for primary weather, NOAA/NCEP for radar, and WeatherKit for supplements. `--live-nws` disables WeatherKit for diagnostics.

Live launches never show cached weather. On a cold launch, or a resume without usable current conditions, a loading screen matching the launch screen holds for up to 1.5 seconds while current conditions, hourly and daily forecasts, and sunrise/sunset resolve, so the app opens on a background that matches the weather. Anything slower fills in on screen as soon as its own fresh NWS or WeatherKit result is validated.

The app does not average providers or invent meteorology.

## Build from source

Install Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen), then generate the project:

```bash
brew install xcodegen
xcodegen generate
open PlainSky.xcodeproj
```

Configure signing for your own development team. See [WeatherKit activation](docs/WEATHERKIT_SETUP.md) for Apple's capability setup and NWS-only diagnostic mode. Deterministic UI testing uses `--preview-data`.

## Documentation and support

- [Architecture](docs/ARCHITECTURE.md)
- [Live data checklist](docs/LIVE_DATA_CHECKLIST.md)
- [WeatherKit activation](docs/WEATHERKIT_SETUP.md)
- [Privacy policy](docs/PRIVACY.md)
- [Support](docs/SUPPORT.md)
- [App Store metadata preparation](docs/APP_STORE_METADATA.md)
- [Report an issue](https://github.com/ColumbusLabs/PlainSky/issues/new)

Selected-place coordinates are sent to weather providers to request data. Optional NWS push alerts register an APNs token, approximate alert-place coordinates, and preferences with PlainSky's alert service. See the privacy policy for retention and removal details.

## License

PlainSky is open source under the [MIT License](LICENSE). Weather data and Apple services remain subject to their providers' terms. Explore the code, report issues, and contribute through this repository.
