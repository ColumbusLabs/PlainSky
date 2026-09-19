# Architecture

## Core product rule

The app does not invent weather.

Provider values preserve:

- provider and product
- observation / issue time
- validity interval
- fetch time
- expiration / freshness
- product availability

The UI may format dates and perform ordinary unit conversion. It does not average forecasts, calculate feels-like values, synthesize precipitation timing, or fill missing meteorological data with made-up values.

## Canonical units

Provider adapters normalize values into the app's canonical internal units.

The U.S./Metric setting is presentation-only. It is intentionally separate from forecast generation so a provider request cannot cause double-conversion or change the forecast itself.

## Provider responsibilities

| Product | Primary provider |
| --- | --- |
| Current station conditions | National Weather Service observation |
| Hourly forecast | National Weather Service forecast/grid |
| Daily day/night forecast | National Weather Service forecast |
| Official alerts | National Weather Service |
| Radar | NOAA/NCEP |
| Next-hour precipitation | Apple WeatherKit |
| UV | Apple WeatherKit |
| Sunrise/sunset | Apple WeatherKit |

Current-condition fallback is whole-group only: if a usable NWS observation group is unavailable, WeatherKit may provide a complete modeled current-condition fallback. Individual Apple fields are not silently mixed into an NWS station observation.

## Layers

1. **Provider adapters** translate external payloads into typed records.
2. **WeatherRepository** coordinates primary and supplemental providers.
3. **Source policy** owns the approved provider for each weather product.
4. **WeatherStore** owns refresh, stale-request protection, persistence, display preferences, and selected location.
5. **AppRouter** owns cross-tab product navigation.
6. **Feature views** render state; they do not independently fetch weather.

## Product availability

Every provider product can be:

- `available`
- `unsupported(message)`
- `unavailable(message)`

This prevents important semantic mistakes such as:

- a failed minute forecast appearing to mean "no rain"
- an empty forecast appearing to mean zero values
- a radar request failure appearing to mean a clear radar image

Alerts are treated separately: a successful empty NWS alert result means no active alerts; a failed refresh is surfaced as a failure and never as an all-clear.

## Refresh behavior

- Cached/in-memory content stays visible while refreshing.
- Pull-to-refresh always requests fresh data.
- Returning to the foreground refreshes only when the snapshot is stale.
- Selecting or updating a location triggers a refresh.
- Request generations prevent a late response for an old location from overwriting a newer selection.

## Location behavior

- Current Location is pinned at the top of saved places.
- Saved places can be renamed, reordered, and removed locally.
- Current Location can be refreshed from Core Location.
- Removing the currently viewed saved place falls back safely to another location.
- Location permission is requested only in response to a user action.

## Radar

MapKit is only the basemap and interaction layer.

Actual radar imagery will come from NOAA/NCEP. The radar UI never fabricates echoes, frame timestamps, or future radar. If Reduce Motion is enabled, animation remains paused and manual timeline scrubbing remains available.

## Accessibility and appearance

- System, Light, and Dark appearance are supported.
- Weather backdrops and text adapt to color scheme.
- Metric cards collapse to one column at accessibility Dynamic Type sizes.
- Large temperature typography uses scaled metrics.
- Radar respects Reduce Motion.
- Color is not the only signal for provider/error state.

## Validation

CI:

1. generates the Xcode project,
2. builds the simulator app,
3. boots an available iPhone Simulator,
4. runs the unit tests,
5. installs and launches the app,
6. captures visual-smoke screenshots for the four tabs plus light mode.
