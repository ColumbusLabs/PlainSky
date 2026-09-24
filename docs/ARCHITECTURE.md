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

Current-condition fallback is whole-group only: if a usable NWS observation group is unavailable, WeatherKit may eventually provide a complete modeled current-condition fallback. Individual Apple fields are never silently mixed into an NWS station observation.

The NWS primary adapter is implemented. It discovers the forecast grid from the selected point, preserves day/night forecast periods, enriches hourly records only with provider-supplied grid values valid for that hour, rejects stale observations, and walks the NWS-provided nearby station list in order until it finds a fresh usable observation (at most two observation requests in flight, at most five candidates, and a valid nearer station always wins over a faster farther one).

Point routing and station-directory metadata (never weather values) are cached on disk by exact coordinates in `NWSLocationMetadataCache`: 24-hour TTL, shortened by the response's `Cache-Control`/`Age`, twenty-entry LRU, concurrent lookups coalesced. A 404/410 from a grid or station route invalidates that entry and re-resolves `/points` once per refresh; forecast products produced on the superseded route are discarded and fetched again on the new one.

## Layers

1. **Provider adapters** translate external payloads into typed records.
2. **WeatherRepository** coordinates primary and supplemental providers.
3. **Source policy** owns the approved provider for each weather product.
4. **WeatherStore** owns refresh, stale-request protection, product freshness, persistence of preferences, and selected location. Its live source of truth is `WeatherScreenState`, which holds a separate `WeatherProductState` (`loading` / `available(value, validation)` / `unsupported` / `unavailable`) per product. `WeatherSnapshot` remains only for preview data and legacy compatibility.
5. **AppRouter** owns cross-tab product navigation.
6. **Feature views** render state; they do not independently fetch weather.

## Product availability

Every provider product can be:

- `loading`
- `available`
- `unsupported(message)`
- `unavailable(message)`

This prevents important semantic mistakes such as:

- a failed minute forecast appearing to mean "no rain"
- an empty forecast appearing to mean zero values
- a radar request failure appearing to mean a clear radar image
- a pending supplemental request appearing as an error or an all-clear

Alerts are treated separately: a successful empty NWS alert result means no active alerts; a failed refresh is surfaced as a failure and never as an all-clear.

## Refresh behavior

Weather is shown only after it has been fetched and validated in the current process. The app never renders weather restored from disk.

- **Incremental delivery.** Providers emit typed `WeatherProductUpdate` events (current, hourly, hourly enrichment, daily, alerts, minute precipitation, UV, solar, radar, terminal). Each section renders as soon as its own event passes validation; nothing waits for the whole bundle. Alerts are requested by coordinate and do not wait for `/points`. Hourly renders from the base forecast and is enriched with grid values when they arrive, keeping row identity.
- **Budgets.** Every request carries a monotonic deadline measured from the start of the refresh: current 4 s (candidate 2 s), alerts 6 s, hourly/daily 8 s, grid and WeatherKit 10 s (`WeatherRequestBudgets`). Deadlines are enforced on the whole transfer, not only idle time. One retry is allowed for retryable statuses, honoring `Retry-After`, only when it fits inside the remaining budget.
- **Current-condition selection.** NWS wins if it produces a usable observation before its deadline. At the deadline the section shows unavailable, but an approved WeatherKit whole-group fallback that lands later still replaces that state. A late NWS observation after the deadline is ignored so the provider cannot flicker within one refresh.
- **Cold launch** restores saved places, the selected place, units, and routing metadata only. Every weather section starts as loading. Legacy `weather.cachedSnapshot*` keys are neither read for display nor written.
- **Freshness** (`WeatherFreshnessPolicy`) has two scopes. *Display* scope applies source validity (NWS observation ≤ 90 min, WeatherKit current ≤ 15 min, forecast issue ≤ 12 h, provider expiry, solar local date) and runs every 15 s while the app is foregrounded; if a shown value ages out, a refresh starts. *Reuse* scope adds per-product caps on time since validation (current/UV/solar 5 min, hourly/daily 15 min, minute precipitation 2 min, alerts 60 s) and decides whether a refresh is needed and what may stay visible after a brief interruption.
- **Lifecycle.** The screen is covered while the app is inactive. Returning after five minutes or more cancels any in-flight load and clears all weather before the first active frame. A shorter interruption keeps only products still inside their reuse caps; the rest show loading while the activation refresh rechecks them. A same-place refresh (pull-to-refresh or activation) keeps still-reusable products visible until replacements arrive.
- **Ownership.** One refresh is in flight at a time (`isRefreshInFlight`), separate from the header spinner. Automatic triggers skip while a load is in flight; pull-to-refresh or a location change replaces it. Request generations plus full coordinate keys prevent a late response for an old place, including one with the same ID but moved coordinates, from overwriting a newer selection.

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

## Runtime modes

- Default launch: live NWS forecasts and alerts, live NOAA/NCEP radar, and Apple WeatherKit for its assigned supplemental products and whole-group current-condition fallback.
- `--live-nws`: run live NWS and NOAA/NCEP with WeatherKit disabled for diagnostics.
- `--preview-data`: deterministic preview repository for UI validation.

Provider ownership does not change by mode: WeatherKit never replaces NWS forecasts or alerts, and NOAA/NCEP remains the radar source.

## Validation

CI:

1. generates the Xcode project,
2. builds the simulator app,
3. boots an available iPhone Simulator,
4. runs the unit tests,
5. installs and launches the app,
6. captures visual-smoke screenshots for the four tabs plus light mode.
