# Startup performance results

Companion to [`FRESH_STARTUP_PERFORMANCE_PLAN.md`](FRESH_STARTUP_PERFORMANCE_PLAN.md). This file records what was implemented, what was verified and how, and what is still unverified.

**Branch:** `codex/fresh-startup-performance`, based on `dafea22`.
**Environment:** Xcode 27.0 (27A266a), iOS 27.0 Simulator, iPhone 18 Pro, Debug build, Wi-Fi. Unsigned, so WeatherKit is unavailable in every run below.
**Date:** September 24, 2026.

## Summary

- Weather is fresh-only. Cold launch shows the selected place with every section loading; no weather restored from disk is ever rendered.
- Each product publishes independently as soon as it is validated. Against live NWS for Indianapolis, the whole NWS refresh (route, alerts, daily, hourly, grid enrichment, current) completed in **about 0.3 s** in the simulator.
- The largest single cost found was not in the plan. Hourly grid enrichment took **19.5 s** in the Debug simulator build. That code is unchanged from `main`, where hourly and the rest of the bundle waited on it. It now takes **about 0.09 s** (details below). This is the most likely explanation for much of the reported 5–10 s wait. The device-side contribution has not been measured.
- Physical-device latency percentiles and the plan's UI/accessibility checks have **not** been run. Nothing here is a device benchmark.

## Grid enrichment parsing (new finding)

`NWSParsing.date` created two `ISO8601DateFormatter` instances per call, and `NWSParsing.duration` compiled an `NSRegularExpression` per call. `NWSGridValueSeries.value(at:)` re-parsed every interval of a series for each lookup. Enrichment looks up five series for each of about 156 hourly periods, which comes to tens of thousands of formatter and regex constructions per refresh.

On `main`, `NWSWeatherProvider.weather(for:)` mapped hourly with the grid inside the all-products barrier, so every section waited on this work.

Fix: the formatters and the regex are built once and shared, and each series is parsed once per mapping (`NWSParsedGridSeries`).

| Measurement (live NWS, Indianapolis, Debug simulator) | Before | After |
| --- | --- | --- |
| Enriched hourly published | 19.5 s | 0.29 s |
| NWS provider finished all work | 19.5 s | 0.30 s |
| Base hourly published | 0.44 s | 0.21 s |
| Current conditions published | 0.23 s | 0.29 s |

These are single samples from a temporary live-network probe test (since removed), not percentiles. Release builds optimize this code, so the device-side cost on `main` was lower than 19.5 s but still likely significant. Measure it before quoting a device number.

## Issues found in the handed-off work and fixed

| Issue | Consequence | Fix |
| --- | --- | --- |
| After a stale-route 404 re-resolved `/points`, forecasts already produced on the old route were never refetched. The store also reset current conditions on a route change, but current could not be republished. | A 404 on just one endpoint (e.g. hourly) could leave daily showing "did not return a usable result" and wipe a valid current observation. | Superseded-route results are discarded and refetched once on the new route. A route change resets only hourly/daily. Current (station-keyed) is not route-gated. Grid enrichment applies only to hourly from the same route. |
| The four-second NWS current deadline permanently resolved current conditions. | A WeatherKit fallback arriving at, say, 5 s was dropped, so the fresh-current success rate was lower than on `main`. | At the deadline, current shows unavailable, but a later fallback still replaces it. A late NWS observation is still ignored. |
| Reuse caps (alerts 60 s, current 5 min, …) were applied as display lifetimes on a 15 s foreground timer, with no refresh. | Alerts turned into "no longer fresh" one minute after loading while the app stayed open, and nothing rechecked them. | Two freshness scopes. The foreground timer uses source validity only, and a refresh starts when a shown value actually ages out. Individually expired alerts are removed. |
| Every refresh, including pull-to-refresh and a 61-second app switch, reset all sections to loading. | The whole screen blanked on routine refreshes. | Same-place refreshes and brief resumes keep products that are still inside their reuse caps. The rest show loading until replaced. Long resume and place changes still clear everything. |
| `timeoutInterval` was used as the request deadline. | It bounds idle time only, so a slow transfer could exceed its product budget. | Each request races its deadline, which cancels the URLSession task. |
| `Dictionary(uniqueKeysWithValues:)` in hourly identity preservation. | The app would crash if NWS returned two periods with the same start time. | Duplicate keys keep the first entry. |
| Metadata cache expiry boundary was inconsistent (`<=` TTL, `>` HTTP expiry), and two tests contradicted each other. | One test always failed. | HTTP semantics throughout: fresh strictly before expiry. |

## Verification

Command (from the plan, run locally):

```bash
xcodebuild -project PlainSky.xcodeproj -scheme PlainSky -configuration Debug \
  -destination "platform=iOS Simulator,id=<UDID>" \
  -derivedDataPath DerivedData/StartupPerformance CODE_SIGNING_ALLOWED=NO build test
```

- **Unit tests:** 106/106 pass on two consecutive runs. New regression tests:
  - `NWSWeatherProviderTests.testForecastsDeliveredOnSupersededRouteAreRefetchedOnNewRoute`
  - `WeatherRepositoryTests.testFallbackArrivingAfterCurrentDeadlineStillReplacesUnavailable`
  - `WeatherRepositoryTests.testUpdatesPrimaryCurrentWinsAsWholeGroup`
  - `WeatherRepositoryTests.testUpdatesMissingCurrentFromBothProvidersKeepsForecasts`
  - `WeatherStoreTests.testForegroundExpiryUsesSourceValidityNotReuseCaps`
  - `WeatherStoreTests.testForegroundExpiryRemovesIndividuallyExpiredAlerts`
  - `WeatherStoreTests.testBriefResumeKeepsOnlyProductsInsideReuseCaps`
  - `WeatherStoreTests.testSameLocationRefreshKeepsFreshProductsUntilReplaced`
- **Manual simulator run (live data):** Onboarding worked, then adding Indianapolis, a cold relaunch, and switching to Pensacola. On relaunch and on the place switch, current, hourly, and daily populated within a few seconds with no old or mock values shown. The WeatherKit-only card showed its unavailable state, as expected unsigned.
- **Observed once, not reproduced:** on the simulator's first network use in this session, the first refresh showed "Current conditions unavailable" while forecasts loaded. The system log showed connection failures to `api.weather.gov` at that moment. Two later refreshes and the provider probe returned current in under 0.3 s. The likely cause is a cold connection exceeding the four-second current budget or failing outright; transport errors (as opposed to HTTP statuses) are not retried. Watch for this on device.

## Remaining limitations

- **No physical-device measurements.** Wi-Fi/cellular percentiles, cold versus warm metadata, long resume, and rate-limit cases from Slice 7 are not measured. Signed WeatherKit behavior, including the fallback timing, is unverified on device.
- **No UI test target.** The first-frame, VoiceOver, placeholder-layout, and light/dark/accessibility-size checks in Slice 6 are not automated or manually completed. The inactive-screen mask and first active frame need to be checked on device.
- **No Instruments trace.** Signposts (`com.columbuslabs.plainsky`, categories `weather.startup` and `weather.network`) are in place for one.
- **Budgets are uncalibrated.** They are the plan's starting defaults. If device traces show the 4 s current budget losing observations on normal networks, raise it from evidence.
- **Legacy snapshot keys** (`weather.cachedSnapshot`, `weather.cachedSnapshotsByLocation`) are ignored but not deleted from existing installs.
- **Most legacy repository tests** still exercise `LiveWeatherRepository.load(location:onPrimary:)`, which the app no longer calls. The live `updates` path now has its own tests. Retiring `load` and `PrimaryWeatherProviding.weather(for:)` is a follow-up cleanup.
- **Transport errors** (connection lost, DNS) are not retried; only HTTP statuses are. That matches `main`.
