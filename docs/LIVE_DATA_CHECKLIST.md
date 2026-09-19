# Live data activation checklist

The normal product launch intentionally stays on `PreviewWeatherRepository` until the remaining supplemental providers are verified. The NWS primary provider can already be exercised with `--live-nws`.

## NWS — implemented and fixture-tested

No API key is required.

Implemented:

- identifying User-Agent
- `/points/{lat},{lon}` discovery
- structured temperature and wind forecast feature flags
- daily forecast endpoint
- hourly forecast endpoint
- raw grid-data endpoint
- observation station collection
- latest QC station observation
- active-alert endpoint
- canonical unit normalization
- ISO valid-time interval parsing
- apparent temperature / dew point / humidity / gust grid enrichment
- stale-observation rejection
- ordered nearby-station fallback
- day/night period pairing
- Tonight-only handling without inventing a high
- official alert wording and timestamps
- partial-product failure states
- request/mapper/provider fixture tests
- opt-in `--live-nws` application mode

Remaining NWS validation before making it the default primary launch mode:

1. Exercise `--live-nws` against real locations and inspect source/freshness diagnostics.
2. Test a location with a stale or incomplete nearest station.
3. Test active and empty alert responses against the live service.
4. Verify offline/cached behavior when NWS cannot be reached.
5. Run the full on-device smoke pass.

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

After WeatherKit and radar are verified:

1. Make NWS + approved supplements the normal `AppEnvironment` repository.
2. Verify all source labels and required attribution on-device.
3. Test:
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
4. Keep the PR draft until live-provider and on-device smoke testing are green.
