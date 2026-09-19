# Live data activation checklist

The product UI intentionally runs in preview mode until each provider is verified independently.

## NWS

No API key is required.

Already implemented:
- Shared HTTP client
- Required identifying User-Agent
- `/points/{lat},{lon}`
- Forecast URL fetch with U.S. units
- Hourly forecast URL fetch with U.S. units
- Observation station collection
- Latest station observation route
- Active alert route

Before activation:
1. Capture real responses from several U.S. locations.
2. Save sanitized fixtures for tests.
3. Verify station-selection policy against stale/missing observations.
4. Map provider quantities without manufacturing missing values.
5. Preserve observation, issue, valid, fetch, and expiration timestamps distinctly.
6. Verify today/tonight period handling.

## Apple WeatherKit

Before activation:
1. Add WeatherKit capability to the Apple Developer App ID.
2. Add the capability/entitlement to the Xcode target.
3. Implement the native WeatherKit adapter for minute precipitation, UV, and solar events.
4. Add required Apple Weather attribution in every surface using Apple data.
5. Keep WeatherKit caching temporary and within Apple's terms.

## NOAA radar

Before activation:
1. Select and document the exact NOAA/NCEP imagery service.
2. Verify its capabilities document and advertised timestamps.
3. Implement frame discovery from provider-advertised times.
4. Build tile overlay loading/cancellation/cache behavior.
5. Never synthesize or interpolate future radar.
6. Distinguish an empty/transparent valid frame from a failed frame request.

## Activation rule

Switch `AppEnvironment.makeWeatherStore()` from `PreviewWeatherRepository` to the live repository only after provider fixtures and mapping tests pass.
