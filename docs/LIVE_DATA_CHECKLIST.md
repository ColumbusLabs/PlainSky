# Live data activation checklist

## NWS / NOAA — implemented

No API key is required.

Implemented and tested:

- NWS `/points/{lat},{lon}` discovery
- identifying User-Agent
- daily and hourly forecasts
- raw grid-data enrichment
- ordered nearby observation-station fallback
- stale-observation rejection
- current temperature / feels-like / humidity / dew point / wind / visibility / pressure
- official NWS alerts with failure distinct from an all-clear
- Tonight-only handling without inventing a daytime high
- day/night condition separation
- canonical unit normalization
- live NWS simulator smoke testing
- NOAA/NCEP WMS capabilities discovery
- provider-advertised radar frame timestamps
- CONUS / Alaska / Hawaii / Caribbean / Guam radar configuration
- exact WMS TIME frame requests
- native MapKit radar overlay and playback
- real NOAA radar simulator visual verification

Normal launches use live NWS + NOAA plus WeatherKit for its assigned supplemental products. `--preview-data` is reserved for deterministic UI validation, and `--live-nws` disables WeatherKit for diagnostics.

## WeatherKit — implemented, physical validation pending

Implemented in the repo:

- native WeatherKit adapter
- current-condition fallback mapping
- minute precipitation mapping
- UV
- sunrise/sunset
- Apple Weather source metadata
- required Apple Weather attribution UI
- WeatherKit entitlement file and XcodeGen wiring
- condition-mapping tests

Apple Developer setup and physical-device validation:

1. Enable WeatherKit on the Apple Developer App ID `com.columbuslabs.weatherapp`.
2. Refresh provisioning / confirm the capability in Xcode.
3. Launch normally with WeatherKit enabled; use `--live-nws` only to compare the NWS/NOAA-only diagnostic mode.
4. Verify minute precipitation, UV, solar events, attribution, and current-condition fallback on a physical device.

Do not treat adapter or simulator tests as physical-device validation.

Live launches may restore a matching cached snapshot for up to six hours while a fresh load runs. Primary NWS data can render before the optional WeatherKit supplement finishes; time-sensitive products are re-verified live.

See `docs/WEATHERKIT_SETUP.md`.

## Final physical-device checks

After Apple-side WeatherKit activation:

- denied and approximate location
- offline launch / provider outage behavior
- active and empty NWS alert responses
- stale or incomplete nearest observation station
- rapid saved-location switching during requests
- WeatherKit unavailable location
- U.S. and Metric display units
- Light / Dark / System
- Dynamic Type
- Reduce Motion radar behavior
- actual iPhone radar pan/zoom/playback performance
