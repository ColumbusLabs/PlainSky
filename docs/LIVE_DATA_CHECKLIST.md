# Live data activation checklist

The product UI intentionally stays on `PreviewWeatherRepository` until each provider is verified independently.

## NWS — first activation target

No API key is required.

Already implemented:

- shared HTTP client
- required identifying User-Agent
- `/points/{lat},{lon}`
- forecast URL fetch using canonical U.S. units
- hourly forecast URL fetch using canonical U.S. units
- observation station collection
- latest-station observation route
- active-alert route
- source/freshness metadata model
- product availability model
- stale-location response protection
- source-policy and request-contract tests

Before activation:

1. Capture real NWS responses from several U.S. locations and weather regimes.
2. Save sanitized fixtures for tests.
3. Implement point/forecast/hourly/observation/alert mapping.
4. Verify station selection against stale, distant, and partially missing station observations.
5. Normalize NWS observation unit codes into the canonical internal unit basis.
6. Preserve observation, issue, valid, fetch, and expiration timestamps distinctly.
7. Verify Today/Tonight period pairing and the case where today's daytime period has already ended.
8. Ensure missing values remain missing rather than becoming zero.
9. Run the full simulator/unit/visual-smoke CI.
10. Switch the primary provider from preview to NWS only after the fixtures pass.

## Apple WeatherKit — supplemental only

Before activation:

1. Enable WeatherKit for the Apple Developer App ID and Xcode target.
2. Implement the native WeatherKit adapter.
3. Map only the approved supplemental products:
   - next-hour precipitation
   - UV
   - solar events
   - complete current-condition fallback when required
4. Mark minute precipitation as unsupported when WeatherKit does not offer it at the selected location.
5. Preserve Apple source/validity metadata.
6. Add Apple's required attribution wherever Apple Weather data is displayed.
7. Keep WeatherKit caching temporary and within Apple's terms.
8. Verify an Apple failure leaves the NWS forecast usable.

## NOAA/NCEP radar

Before activation:

1. Select and document the exact NOAA/NCEP imagery service.
2. Verify its capabilities document, layer identifiers, coordinate system, and advertised timestamps.
3. Implement frame discovery from provider-advertised times.
4. Feed timestamped frames into the existing `RadarPlaybackState`.
5. Implement map tile overlay loading, cancellation, and a bounded cache.
6. Keep the previous complete frame visible while a replacement frame loads.
7. Distinguish a valid transparent/no-echo frame from a failed request.
8. Never synthesize missing frames or future radar.
9. Verify map/radar performance on a physical iPhone.

## Final live cutover

After all three providers are verified:

1. Wire the live repository in `AppEnvironment`.
2. Replace the Settings/Diagnostics "Preview" mode label with live mode.
3. Verify all source labels and attribution on-device.
4. Test:
   - offline launch
   - NWS outage
   - WeatherKit outage
   - radar outage
   - approximate location
   - denied location permission
   - location switch during an in-flight request
   - no active alerts
   - active severe alerts
   - minute precipitation unsupported
   - Today after the daytime NWS period has ended
   - U.S. and Metric display units
   - Light/Dark/System
   - accessibility Dynamic Type
   - Reduce Motion
5. Keep the PR draft until live-provider CI and on-device smoke testing are green.
