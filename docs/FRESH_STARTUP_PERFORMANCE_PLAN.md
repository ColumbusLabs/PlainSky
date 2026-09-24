# Faster fresh weather on startup and resume

**Status:** Implementation plan only; no runtime optimization is implemented by this document.

**Requested outcome:** Reduce the reported 5–10 second wait after the app has not been opened for a while, without displaying stale weather to disguise the delay.

**Repository:** `ColumbusLabs/PlainSky` (the weather app referred to as Clean Sky in the request).

**Audit date:** September 24, 2026.

**Inspected baseline:** `43a329cbc3d19ffe01011f8a302ae79da7e2f197` on `main`.

## 1. Decision and scope

There are concrete opportunities to reduce both time to the first useful fresh weather and time to fresh current conditions. The largest is removing the all-products completion barrier inside the NWS provider. Reusing location-routing metadata, fixing station-selection waits, and separating refresh ownership from the visible spinner provide additional opportunities.

Implement and validate this work in a native Mac/Xcode environment. The inspecting chat environment has Linux Swift but no Xcode/iOS Simulator, and could not reproduce the device's network timing. The GitHub connector was used to inspect the actual source and publish this plan. An unvalidated change to SwiftUI state, WeatherKit coordination, and asynchronous cancellation should not be pushed to production merely because the files can be edited here.

The reported 5–10 seconds is the user's observation, not an instrumented benchmark. The code findings below are verified; their individual contribution on the user's device is not yet measured. Performance numbers in this plan are acceptance targets or configurable starting policies, not promises about NWS response time.

Keep the existing product ownership: NWS observations and forecasts, NWS official alerts, NOAA radar, and WeatherKit supplements plus the approved whole-group current fallback. Do not introduce a paid provider, backend, polling service, analytics SDK, or mandatory background refresh.

## 2. What the current code actually does

Paths and symbols below refer to the inspected commit, not an assumed architecture.

| Finding | Source | Consequence |
| --- | --- | --- |
| Startup and foreground activation call `refreshIfNeeded()`. | `PlainSky/RootTabView.swift` | Both paths need testing; a warm process resume is different from a cold launch. |
| `refreshIfNeeded(maxAge:)` uses a ten-minute aggregate snapshot age or pending products. | `PlainSky/Core/State/WeatherStore.swift` | One recently merged product can make unrelated old products appear recently refreshed. |
| All NWS work first waits for `/points`. | `PlainSky/Core/Providers/NWS/NWSWeatherProvider.swift`, `weather(for:)` | Alerts unnecessarily wait for routing even though their request already uses coordinates. |
| Daily, hourly, raw grid, alerts, and the observation pipeline then run concurrently, but the provider returns only after all have finished. | Same provider | Existing concurrency does not provide incremental publication. One slow endpoint delays every fresh result. |
| Hourly mapping receives the raw grid result, even though the mapper accepts a missing grid. | `NWSWeatherProvider.swift`; `NWSMapper.hourlyForecast` | Optional enrichment is on the first-display path. Basic hourly weather can be mapped before enrichment. |
| Current weather requires a station-directory lookup. The nearest two observation requests run concurrently, but the code collects both before selecting a winner. Up to three additional stations are tried sequentially. | `NWSWeatherProvider.currentConditions` | A good nearest observation still waits for the second station. Failures can create a long tail. |
| Each NWS request has a 20-second timeout setting. The HTTP client retries certain status codes once after a fixed five-second sleep. | `NWSAPIClient.makeRequest`; `URLSessionHTTPClient.data` | A failed endpoint can add exactly five seconds before retrying. This is a possible contributor, not proof that a retry happened on the user's device. |
| WeatherKit already starts concurrently with the primary provider, and `onPrimary` publishes before supplements finish when current conditions exist. | `PlainSky/Core/Repository/WeatherRepository.swift` | Do not propose merely parallelizing WeatherKit as if this optimization were missing. |
| `onPrimary` still receives the complete NWS bundle. No usable NWS current group means no primary snapshot callback. A thrown primary error cancels WeatherKit. | Same repository | Ready forecasts/alerts cannot independently unlock the dashboard; some primary failures also prevent a usable fallback. |
| The supplemental timeout is installed when `value(of:)` is called, after the primary await, not when the supplemental task starts. | Same repository | A ten-second supplemental timeout can effectively be additional time after primary work. Preserve its existing uncooperative-provider protections when fixing the deadline. |
| `WeatherSnapshot.current` is nonoptional. Live launch begins with a mock snapshot when no cache is restored. Today draws the content and covers it with `LiveWeatherLoadingView`. | `WeatherModels.swift`; `AppEnvironment.swift`; `Features/Today/TodayView.swift` | Progressive forecasts without current conditions require real partial state, not simply removing the loading overlay. |
| A matching snapshot is restorable for up to six hours based on aggregate `fetchedAt`. Restoration strips alerts, minute precipitation, and solar but keeps current/hourly/daily values. | `AppEnvironment.isRestorable`; `WeatherSnapshot.restoringFromCache` | The existing startup strategy does not satisfy a strict fresh-only relaunch requirement. Never extend this window to make startup look faster. |
| Same-location in-memory weather remains present during refresh and after errors. | `WeatherStore.performRefresh` | Fixing disk restoration alone would leave the stale foreground-resume path intact. |
| The primary callback sets `isRefreshing = false` while the repository may still be loading supplements. | `WeatherStore.performRefresh` | A subsequent automatic trigger can see pending products and start a replacement load. Spinner state is not a reliable in-flight guard. |
| The HTTP session already has a 16 MiB memory / 64 MiB disk cache with `.useProtocolCachePolicy`. | `PlainSky/Core/Networking/HTTPClient.swift` | HTTP caching already exists. Measure cache hits before claiming every point/station lookup goes over the network. |
| Snapshot persistence encodes the last snapshot and a dictionary of up to five locations on the main actor. | `PlainSky/Core/Persistence/WeatherPreferences.swift` | Do not multiply this cost by persisting every incremental event. Measure before attributing significant delay to it. |

The successful primary path approximately has this dependency shape:

```text
refresh
  +-- WeatherKit current/minute/daily + attribution ------------------+
  |
  +-- NWS point lookup                                                |
        +-- daily forecast ------------------+                       |
        +-- hourly forecast -----------------+                       |
        +-- raw grid enrichment -------------+-- complete NWS bundle  |
        +-- alerts --------------------------+           |           |
        +-- station directory                |           |           |
              +-- observation 0 --+          |           |           |
              +-- observation 1 --+-- both --+           |           |
              +-- sequential fallbacks if needed -------+           |
                                                          |           |
                                      publish primary if current      |
                                                          +-- merge --+
```

The code waits for the slowest branch; it does not sum every forecast request. Station discovery and fallback requests add dependencies within their branch. If NWS current is absent, even publication of the primary bundle is deferred to fallback handling.

`docs/ARCHITECTURE.md` currently describes primary products as committed “as soon as they arrive.” At this baseline, that means the primary bundle relative to WeatherKit, not each independent NWS product. Correct this wording when the implementation actually changes.

## 3. Define “fresh” before changing the loader

### Required display behavior

1. **Cold launch:** restore the selected place, preferences, and lookup metadata immediately. Do not render persisted meteorological values before the new refresh validates them.
2. **Return after a long absence:** use five minutes as the initial configurable long-resume threshold. Before active content is exposed, mask/clear old weather and start a new refresh generation. Do not rely solely on an asynchronous `.onChange` callback that can allow an old frame to appear first.
3. **Brief interruption:** still-valid in-memory products may remain visible only while each passes its own freshness policy. An expired product becomes a placeholder even if another product is fresh.
4. **Location change or explicit refresh:** start a fresh validation generation. Never briefly show old-place temperatures under the new place name.
5. **No connection / provider outage:** show missing or unavailable sections and a retry action. Do not substitute yesterday's weather, retain expired current values, or turn failed alerts into an all-clear.

Five minutes is a proposed UI lifecycle threshold, not a statement about the frequency with which NWS generates observations. Put it in one injectable policy and test its boundary.

### Preserve the difference between source time and retrieval time

“Freshly fetched” does not mean “observed this second.” NWS documents observation delays of up to approximately twenty minutes from upstream quality-control processing. A new HTTP response can also contain old or expired provider data. Source time and validity must be checked after retrieval and again at publication. See external references [E1]–[E3].

Create `WeatherFreshnessPolicy` with an injected wall clock and use a monotonic clock for elapsed-time deadlines. It must evaluate product/location identity, source timestamps, source expiration, forecast validity, and the last actual validation of that product.

Starting policy for implementation:

| Product | Source-level rule | Brief-resume reuse cap |
| --- | --- | --- |
| NWS current | Preserve the existing 90-minute observation-age ceiling and ten-minute future-clock-skew bound from `NWSMapper`; never widen them for performance. Recheck at publication. | Five minutes since actual validation, also bounded by source expiry. |
| WeatherKit current | Require usable current date and unexpired provider metadata; initial current-date ceiling fifteen minutes, with the same explicit future-skew policy. | Five minutes, never beyond provider expiry. |
| NWS hourly/daily | Require usable issue metadata, relevant unexpired intervals, and filter completed periods. Initial issue-age safety ceiling twelve hours, documented as an app policy rather than an NWS guarantee. | Fifteen minutes, but a long resume still forces validation. |
| Alerts | Only a successfully validated response may establish the current alert set, including an empty set. Filter expired alerts. | At most sixty seconds on a brief interruption; do not restore from disk. |
| Minute precipitation | Require unexpired WeatherKit metadata and a forecast window covering the current minute; remove elapsed samples. | Two minutes, with no disk restore. |
| UV / solar | Check the appropriate source metadata separately; solar must belong to the selected location's current local date. | UV five minutes; solar only within its provider expiry and local-date boundary. No cold disk restore. |

These reuse caps are upper bounds, not guaranteed lifetimes. The stricter source expiration/validity always wins. A ninety-minute NWS ceiling is already in the code; it is not permission to present a cached observation without revalidation or to call it newly observed. A stricter meteorological observation policy would be a separate accuracy/availability decision, not a hidden performance change.

The twelve-hour forecast and fifteen-minute WeatherKit source-age defaults are proposed conservative application policies. Validate them against real supported-location responses before release; record adjustments and their rationale in the results report rather than silently broadening them.

For cold/long-resume refreshes, require response validation even if an old HTTP representation remains in `URLCache`. Use an explicitly tested URLSession revalidation policy; a legitimate `304 Not Modified` may reuse its exact matching response body without pretending its observation/issue time changed. Without a valid matching cached body or usable validators, obtain the full response. Preserve normal protocol caching for stable metadata. Never use random query-string cache busting or stale-cache-only policies.

Track `lastValidatedAt` independently from the source's `observedAt`, `issuedAt`, and original receipt time. A local cache read or a later supplemental merge must not advance another product's validation timestamp. Respect HTTP `Date`/`Age` when deciding whether a response really satisfies the requested freshness; receiving cached bytes now is not proof of an origin validation now.

Legacy `weather.cachedSnapshot` and `weather.cachedSnapshotsByLocation` data must not become a live-display fallback. Ignore or migrate only those weather-cache keys; preserve saved places, the last selected place, units, and other preferences.

## 4. Intended architecture

### Partial screen state, not a fabricated complete snapshot

Introduce `WeatherScreenState` and a typed `WeatherProductState<Value>` in `Core/Models`. Each product must distinguish `loading`, `available(value, validationMetadata)`, `unsupported`, and `unavailable`. An available empty alerts array has a different meaning from an unavailable or pending alert result.

Use this state as the live UI's source of truth. Do not make the design depend on a nonoptional `WeatherSnapshot.current`, an arbitrary temperature, or `MockWeather` hidden behind an overlay. Keep the old snapshot format only for preview/compatibility needs while migrating; it must not continue supplying live values through an overlooked view.

All live consumers must be migrated: Today, forecast screens, places summaries, current/metric/detail views, source metadata, daylight/background selection, and alert UI. Use compiler errors and a repository-wide search for `snapshot.current`, `isShowingPlaceholderData`, `restoringFromCache`, and `availability(for:)` to find every consumer. Unknown availability must not default to `.available` in the new screen state.

### Typed incremental delivery

Replace the single `onPrimary` boundary with typed `WeatherProductUpdate` events. Prefer a callback delivered to a main-actor reducer, with a repository operation that stays owned until its work finishes or is cancelled. Events should include:

- Refresh generation and the full request location key, including coordinates, not UUID alone.
- Product-specific ready/unavailable/unsupported results.
- Source identity and validation timestamps.
- An explicit terminal event for the refresh's owned work.

Examples are current conditions, base hourly forecast, hourly enrichment, daily forecast, alerts, minute forecast, and solar/UV. Product errors become events rather than throwing away already-ready sibling products. Cancellation remains distinct from a provider failure.

The store commits an event immediately if its generation, coordinates, source revision, and freshness are valid. Completion of the whole operation is not a prerequisite for rendering. Do not buffer everything and send it only at the end.

### Independent request graph

```text
refresh generation
  +-- fresh alerts by coordinate ---------------------------------- publish alerts
  +-- WeatherKit work ---------------------------------------------- publish allowed supplements
  +-- usable point/station metadata or metadata resolution
        +-- daily forecast ----------------------------------------- publish daily
        +-- hourly forecast ---------------------------------------- publish base hourly
        +-- bounded observation selection -------------------------- publish current / resolve fallback
        +-- raw grid enrichment ------------------------------------ enrich matching hourly records
```

An alert must not wait for a failed point lookup. Forecasts must remain usable when current conditions are unavailable. A grid enrichment failure must not erase base hourly weather.

The existing NWS mapper already accepts `grid: nil`. Publish that base forecast, then enrich only matching location/grid/issue/valid-time records. Preserve item identity across enrichment: existing hourly items generate UUIDs when constructed, so blindly remapping the whole array would cause identity churn. Update existing rows or introduce stable semantic IDs. Never apply an old grid result to a newer hourly forecast.

## 5. Implementation slices

Implement in the following order on a working branch in the native environment. Keep each slice compiling and update this checklist with evidence as work lands. The plan itself is on `main`; implementation is still pending.

### Slice 1 — Baseline instrumentation and deterministic network gates

**Files:** `Core/Networking/HTTPClient.swift`, `Core/Repository/WeatherRepository.swift`, `Core/State/WeatherStore.swift`, `RootTabView.swift`; new test helpers under `PlainSkyTests`.

Add local-only signposts and `URLSessionTaskMetrics` collection. Record endpoint family, start/end, attempt count, response status, network versus local-cache fetch, DNS/connect/TLS/response timing when available, and mapping/publication duration. Record cold launch versus resume, metadata cache hit/miss, first usable fresh section, first fresh current conditions, full core completion, and all-work completion separately.

Use static endpoint labels or redacted identifiers. Do not log precise coordinates, raw point URLs, weather payloads, WeatherKit credentials, or user place names into shared telemetry. No third-party analytics.

Build a gate-controlled fake HTTP client with per-route responses, request counters, a controllable clock, and explicit completion gates. It must be possible to hold grid or one station indefinitely while allowing another endpoint to return. Do not base correctness tests on repeated arbitrary sleeps.

**Gate:** Capture a native baseline trace and add a characterization test demonstrating the existing all-products publication barrier. Distinguish code behavior from live provider delay. Do not block the entire project on a large benchmarking effort before beginning the fix.

### Slice 2 — Partial state and fresh-only lifecycle rendering

**Files:** `Core/Models/WeatherModels.swift`, `Core/Models/WeatherAvailability.swift`, `Core/AppEnvironment.swift`, `Core/State/WeatherStore.swift`, `Core/Persistence/WeatherPreferences.swift`, `RootTabView.swift`, `Features/Today/TodayView.swift`, and all live snapshot consumers. Add `WeatherScreenState.swift` and `WeatherFreshnessPolicy.swift`.

Introduce the partial state and central freshness policy described above. Start live mode with actual loading states rather than mock weather. Restore only non-weather preferences and routing metadata on cold launch. Separate compatibility decoding of old snapshots from permission to display them.

Replace the blocking Today overlay with section-level placeholders using the existing visual design. The place name, navigation, and neutral background appear immediately; weather numbers appear only when validated. Current, daily high/low, hourly rows, metrics, and alert status can populate independently. Missing current data must not hide forecasts.

Do not show unavailable/error wording for a section that is still loading. Alert loading must say it is being checked, not suggest there are no alerts. Make placeholder/error text accessible and ensure VoiceOver cannot discover underlying mock or expired values. Avoid changing the app's broader visual language.

Handle app inactivity explicitly. Cover weather while inactive as needed, then synchronously evaluate whether a brief resume can restore valid in-memory products or whether a long resume must remain masked. Check the first active frame and app-switcher transition on device; a later async state reset alone is insufficient evidence.

Add clock-driven expiration while the app remains foregrounded so a once-fresh value does not remain visible indefinitely without any scene change. Cancellation/backgrounding must not leak a repeating timer or refresh loop.

**Gate:** Seed a six-hour-old snapshot, an expired observation with a recent aggregate `fetchedAt`, and an expired in-memory value. None may appear in a live cold/long-resume frame or accessibility tree. Existing preview mode remains deterministic. Update the old six-hour restore tests deliberately instead of weakening or deleting freshness coverage.

### Slice 3 — Publish primary products independently

**Files:** `Core/Providers/WeatherProviderProtocols.swift`, `Core/Providers/NWS/NWSWeatherProvider.swift`, `Core/Providers/NWS/NWSMapper.swift`, `Core/Repository/WeatherRepository.swift`, `Core/State/WeatherStore.swift`; provider/repository test fakes.

Introduce the event contract and reducer. Start alerts immediately from coordinates. Resolve routing for the forecast/observation branch, then run independent product work. Publish daily, base hourly, alerts, and selected current results independently. Treat raw grid data as optional later enrichment.

A failed point lookup resolves the dependent NWS products but does not cancel coordinate-based alerts or the approved WeatherKit fallback path. Missing current from both providers leaves that product unavailable rather than failing the whole dashboard.

Preserve provider-supplied values, day/night periods, units, quality-control requests, and source metadata. Record receipt/validation at the correct endpoint completion time, not only once at the beginning of the NWS bundle. Re-evaluate observation age using the actual publication clock rather than the current frozen `fetchedAt` passed as `now`.

Keep expensive decoding/mapping away from the main actor. Audit concurrency isolation instead of adding broad `@unchecked Sendable` annotations. The `NWSAPIClient` currently holds a decoder; concurrent access must be deliberately isolated or replaced with per-decode instances compatible with the project's Swift mode.

**Gate:** With grid held for ten seconds, fresh current and base forecasts appear before its gate opens. With current held, forecasts and successful alerts appear. With alerts held, the hero/forecasts appear but alerts remain explicitly unverified. With `/points` failing, independent alerts still complete.

### Slice 4 — Reuse routing metadata and bound observation selection

**Files:** `Core/Providers/NWS/NWSAPIClient.swift`, `Core/Providers/NWS/NWSWeatherProvider.swift`, `Core/AppEnvironment.swift`; new `Core/Providers/NWS/NWSLocationMetadataCache.swift`; associated tests.

Create an actor-owned, disk-backed, versioned cache for point routing and station-directory metadata only. Store the exact lookup coordinates, grid office/X/Y, forecast/hourly/grid/station URLs, time zone, station directory/order, and validation time. Do not store temperatures or forecast bodies in this cache.

Initial metadata TTL: twenty-four hours, configurable in tests. Expired metadata must be revalidated before it shortcuts routing. Respect shorter explicit provider cache restrictions. Limit the cache to a small bounded LRU, initially twenty locations. Corrupt/unknown versions become cache misses rather than launch failures.

Use a canonical exact-coordinate request key plus provider/schema version. A UUID is insufficient when a location changes coordinates; broad coordinate rounding can cross a forecast-grid boundary. Preserve endpoint representation/header distinctions where applicable. Coalesce concurrent metadata resolution for the same key.

Invalidate affected routing and resolve `/points` once when a grid/station route is invalid, including a 404/410. Do not retry an obsolete route repeatedly. On a changed grid, reject old in-flight dependent results and refetch affected products. NWS explicitly permits cached grid mappings but requires periodic checks [E1]. Existing URLCache may already satisfy some lookups; measure the actual additional gain.

Replace the current “collect both nearest responses before deciding” selection. Preserve NWS station ordering and whole-group selection: if station zero returns a valid observation, publish it without waiting for station one. If a nearer candidate is still pending, a farther result waits only until the nearer request fails or reaches its bounded candidate deadline.

Use at most two observation requests concurrently and at most five candidates, matching today's fan-out/candidate limits. Start the next candidate when a slot frees after failure. Initial overall NWS-current budget: four seconds from refresh start, including routing and station discovery. Initial per-candidate budget: two seconds, clipped to the remaining overall budget. Make these configurable and calibrate using Slice 1 traces.

At a deadline, terminate that attempt, classify the result as unavailable for this generation, and allow the already-running approved current fallback if fresh. Never choose an observation outside the freshness policy to meet a stopwatch target. Do not treat the fastest arbitrary station as automatically the most appropriate station.

**Gate:** A valid nearest response publishes before a blocked second station. A faster farther station cannot displace a valid nearer one that resolves within its budget. A timed-out nearer station cannot block all other useful weather. Warm metadata avoids point/directory requests before observation fetching; expired metadata revalidates; changed coordinates never reuse the old routing key.

### Slice 5 — Request deadlines, retries, fallback, and task ownership

**Files:** `Core/Networking/HTTPClient.swift`, `Core/Providers/NWS/NWSAPIClient.swift`, `Core/Repository/WeatherRepository.swift`, `Core/Providers/WeatherKit/WeatherKitSupplementalProvider.swift`, `Core/State/WeatherStore.swift`.

Introduce request context with product, refresh generation, a monotonic deadline, and retry policy. A request's timeout setting is not a whole-refresh wall-clock deadline. Clip individual work and retry waits to the remaining budget and propagate cancellation to the underlying URLSession task.

Starting overall product budgets: NWS current four seconds, alerts six seconds, daily/hourly eight seconds, grid and WeatherKit ten seconds, all measured from generation start. These are terminal-state budgets, not a global spinner duration. Fresh siblings publish before them. They are tunable engineering defaults, not new provider SLAs.

Replace the blanket five-second retry behavior with deadline-aware retry handling. Respect `Retry-After` when present, retain a conservative rate-limit backoff, and do not use rapid parallel retries to evade NWS limits. A 403 is not universally proof of rate limiting; retain sanitized diagnostics for classification. If a permitted retry cannot fit inside the product budget, show that product's unavailable state and retry on the next appropriate refresh rather than delaying every section. Keep retries bounded to one unless evidence justifies a separate change.

Do not weaken HTTP freshness to gain speed. Add native URLSession tests for successful revalidation, cached-body matching on 304, missing validators/body, and expiration. Observe the documented NWS alert polling guidance; lifecycle deduplication must prevent bursts, and repeated automatic checks must not become sub-thirty-second polling [E2].

WeatherKit already runs in parallel. Keep that, but attach its deadline and parent cancellation from task creation, not after NWS completes. Preserve the existing protection against a provider that ignores cancellation. A fresh WeatherKit current group becomes eligible only after the NWS current attempt has failed, exhausted usable candidates, or reached its deadline. Never mix individual Apple fields into NWS current data. Once a current provider is selected for a generation, ignore late timed-out candidates to avoid flicker; a subsequent refresh can prefer NWS again.

If instrumentation demonstrates that WeatherKit's combined current/minute/daily/attribution request is itself the next bottleneck, split its adapter into typed product delivery in this slice. Preserve required attribution and valid source metadata; do not drop attribution to accelerate rendering. Do not add duplicate WeatherKit current requests merely to race the same service. If it is not a demonstrated blocker, retain the bundled request and document that evidence.

Separate `isRefreshInFlight` / owned load identity from header-spinner visibility and initial-content readiness. Automatic same-location triggers join or skip the owned load until all its work is terminal. Explicit refresh replaces it once. Location changes cancel all old children and reject every stale-generation event, including metadata revalidation and enrichment.

Retain explicit task handles and release them at termination. Swift task groups wait for all children when leaving scope; calling `cancelAll()` does not force an uncooperative task to return [E5]. Do not replace the existing resolver with a naive task-group “race” that reintroduces the timeout bug. Publication must happen before joining slow siblings. Any necessary unstructured tasks require cancellation handlers, one-shot continuation resolution, late-result rejection, and tests for cleanup; no orphaned task per refresh.

**Gate:** Rapid startup/active triggers create one generation. The visible spinner can stop without permitting duplicate requests. Switching location during the primary or supplemental phase cannot apply old results. Cancelling during NWS also cancels the supplemental task. A slow primary cannot extend WeatherKit's absolute deadline by another ten seconds. Rate limits do not induce a retry storm.

### Slice 6 — Persistence, UI integration, and targeted regression coverage

**Files:** Live screen consumers, `Core/Persistence/WeatherPreferences.swift`, `PlainSkyTests/*`, `project.yml`, and a new `PlainSkyUITests` target if needed for automated first-frame checks.

Do not persist every product event by encoding the complete five-location snapshot dictionary on the main actor. Since cold launch no longer displays legacy weather snapshots, remove unnecessary live snapshot writes or retain only a separately justified, coalesced compatibility write. Keep required preferences and metadata durable. Metadata persistence must not delay initial rendering and must be atomically replaced.

Preserve the existing source-policy, unit-conversion, stale-observation, day/night, saved-place, and cancellation coverage. Some existing tests intentionally assert the old behavior and must be replaced with stronger new-contract tests:

- `AppEnvironmentTests.testRestorableSnapshotAcceptsRecentCache` currently uses nearly the entire six-hour restore window. Replace live weather restore expectations with preference/metadata restoration plus masked weather.
- `WeatherRepositoryTests.testMissingCurrentFromBothProvidersFails` must become a partial-success test: current unavailable, independent successful forecasts/alerts retained.
- `testPrimarySnapshotIsDeliveredBeforeSupplementalFinishes` must expand to individual NWS products, not just the primary bundle.
- Preserve and extend `testSupplementalTimeoutDoesNotWaitForUncooperativeProvider` and `testCancellationWhileWaitingForSupplementalReturnsPromptly`.
- Extend `WeatherStoreConcurrencyTests.testOlderLocationResponseCannotOverwriteNewerSelection` to multiple product events and same-UUID/changed-coordinate selections.
- Preserve `NWSWeatherProviderTests` coverage for stale nearest observations and alert failures without forecast loss.

Add dedicated metadata cache, freshness, network policy, and incremental publication suites. Test expiry boundaries exactly, clocks jumping forward/backward, missing/future timestamps, a source expiring while its request is in flight, HTTP errors, malformed payloads, empty successful alerts, offline first launch, and WeatherKit disabled mode.

UI checks must cover Today and Forecast when current is missing, high/low placeholders, metric placeholders, alert-loading text, no expired value in VoiceOver, stable layout during enrichment, current-location changes, and light/dark/accessibility sizes. New UI tests must use a deterministic gated-data launch mode separate from production and from the existing static preview mode.

**Gate:** Full unit suite and focused UI tests pass on native iOS Simulator. No product semantics or preview behavior regress. No stale fallback exists behind a secondary tab, detail screen, background style, or cached place summary.

### Slice 7 — Device verification, results, and landing

**Files:** new `docs/STARTUP_PERFORMANCE_RESULTS.md`, this plan, `docs/ARCHITECTURE.md`, `docs/LIVE_DATA_CHECKLIST.md`, and `README.md` only after runtime behavior is implemented.

Generate and build the native project with its existing XcodeGen configuration. The inspected project is iOS 17+ with Swift language version 5.10 and scheme `PlainSky`; validate new APIs against that deployment target rather than silently raising it.

Typical commands on the implementing Mac:

```bash
xcodegen generate
xcodebuild -project PlainSky.xcodeproj -scheme PlainSky -showdestinations
# Select an available iPhone Simulator UDID from the output above.
# Set SIMULATOR_UDID to that actual UDID before running the next command.
: "${SIMULATOR_UDID:?Set SIMULATOR_UDID to an available iPhone Simulator}"
xcodebuild \
  -project PlainSky.xcodeproj \
  -scheme PlainSky \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=${SIMULATOR_UDID}" \
  -derivedDataPath DerivedData/StartupPerformance \
  -resultBundlePath "StartupPerformance-$(date +%Y%m%d-%H%M%S).xcresult" \
  CODE_SIGNING_ALLOWED=NO \
  build test
```

The simulator covers correctness and ordering; it does not prove signed physical-device WeatherKit behavior. Run a signed build on a real supported iPhone with WeatherKit enabled, including the user's iPhone class when available. No entitlement or signing changes are authorized merely to make tests pass. Clearly mark unavailable device evidence rather than calling simulator results a device benchmark.

Measure separately on Wi-Fi and cellular: cold process with valid metadata, cold process without metadata, long background resume, recent warm resume, saved-place switch, and manual refresh. Include an offline run and controlled slow-grid, slow-station, and rate-limit cases. Use a clock-controlled test mode to reproduce old data without waiting hours, plus actual device background/foreground transitions to check rendering behavior.

For meaningful measured percentiles, collect at least twenty samples per principal healthy-network scenario and report sample counts, device/OS/build, cache state, endpoint timings, source-data ages, failures, and distribution. Do not report the time to a skeleton or an error as time to fresh current conditions.

Keep `.github/workflows/ios.yml` manual-only (`workflow_dispatch`). Do not re-enable push/PR workflows or dispatch paid CI as part of this documentation task. Use local native checks for implementation; any later workflow use must respect the user's CI preference.

**Landing gate:** All deterministic correctness gates pass; native build and regression results are recorded; real-device results or their explicit limitation are documented; the measured first-fresh path improves without losing fresh-current success rate. Review the diff for unrelated changes, then land the validated implementation on `main` without a force-push. Do not claim the improvement is released in an installed app merely because source is committed.

## 6. Performance and correctness acceptance matrix

| Scenario | Required behavior |
| --- | --- |
| First shell render | Selected place and interactive navigation appear without awaiting a network response. Initial target: within 300 ms on the reference device. No old/mock weather is visible. |
| Healthy network with usable metadata | Target median first fresh weather section within two seconds; target median fresh current within three seconds. Record actual p95 and availability. These are goals contingent on provider/network response, not guaranteed bounds. |
| Product response received | Validated data should reach its section promptly; initial target under 100 ms from completed parsing to UI commit on the reference device. Measure rendering separately. |
| Current ready; grid blocked ten seconds | Current publishes before grid completes. No full-page blocking overlay. |
| Base hourly ready; grid blocked | Base hourly is visible; absent enrichment remains absent until valid enrichment arrives. |
| Nearest observation ready; second station blocked | Current publishes without joining the blocked second response. |
| Current missing or slow | Daily/hourly/alerts can be useful independently; current transitions to fresh approved fallback or unavailable within its budget. |
| Alerts failed or pending | No all-clear state, stale warning, or zero-alert inference is fabricated. Other weather remains usable. |
| Six-hour disk snapshot; no network | No weather values are restored. Show unavailable/retry state instead. |
| Long resume with old in-memory data | No old weather flash before refresh, including accessibility and secondary screens. |
| Old observation in a new response | Source-age policy rejects it. A new receipt/merge timestamp cannot make it fresh. |
| Duplicate lifecycle triggers | One owned generation for the same request key, including while supplements remain pending. |
| Late old-location or timed-out result | Ignored; cannot update UI, freshness timestamps, or the new location's metadata. |
| HTTP failure/retry | Respect backoff and product deadline; no whole-page dependency and no increased request storm. |
| Entire app stays foregrounded | Values age out according to policy rather than remaining indefinitely because scene phase did not change. |

Do not improve latency by making successful data disappear more frequently under ordinary network conditions. Compare fresh-current success rate and failure causes alongside latency. If the four-second current budget is too aggressive on supported networks, adjust it from evidence while retaining independent section publication and strict freshness.

## 7. Work explicitly excluded

- Extending the six-hour weather-cache window or relabeling cached values as updated now.
- Displaying placeholders containing fake meteorological values.
- Simply cutting every timeout to one second and declaring startup faster because it errors sooner.
- Removing grid enrichment, alerts, or current observations permanently to win a benchmark.
- Replacing NWS forecast/alerts with Apple data, field-level provider mixing, or synthesized feels-like values.
- Adding background location permission, mandatory GPS acquisition, or a new geocoding dependency on startup. The inspected root refresh uses the selected saved coordinates; profile location separately when the user explicitly requests it.
- A broad radar rendering redesign. Keep radar loading out of the core weather publication dependency and profile resource contention separately if traces demonstrate it.
- Assuming a larger URLCache alone fixes this: the app already configures one.
- Re-enabling automated CI, deploying an app, or changing signing as part of publishing this plan.

## 8. Progress and evidence ledger

| Item | Status at publication |
| --- | --- |
| Inspect current main and relevant source/test contracts | Complete at baseline `43a329c` |
| Verify external NWS caching and Swift concurrency guidance | Complete; references below |
| Identify code-level bottlenecks | Complete; not yet device-timed |
| Implement runtime changes | Not started |
| Native baseline trace | Not run in this environment |
| Native build / unit / UI checks | Not run in this environment |
| Signed-device performance comparison | Not run in this environment |
| Publish this implementation plan to main | This documentation change |

The implementing agent should append the commit, commands, test results, measurements, and remaining limitations after each slice. Do not turn planned gates into checked items without evidence.

## 9. Primary references

### Repository evidence

All inspected source paths in Sections 2 and 5 were read from commit `43a329cbc3d19ffe01011f8a302ae79da7e2f197`. Important entrypoints:

- [NWS provider at audit baseline](https://github.com/ColumbusLabs/PlainSky/blob/43a329cbc3d19ffe01011f8a302ae79da7e2f197/PlainSky/Core/Providers/NWS/NWSWeatherProvider.swift)
- [Repository coordination at audit baseline](https://github.com/ColumbusLabs/PlainSky/blob/43a329cbc3d19ffe01011f8a302ae79da7e2f197/PlainSky/Core/Repository/WeatherRepository.swift)
- [Weather store at audit baseline](https://github.com/ColumbusLabs/PlainSky/blob/43a329cbc3d19ffe01011f8a302ae79da7e2f197/PlainSky/Core/State/WeatherStore.swift)
- [Startup/cache policy at audit baseline](https://github.com/ColumbusLabs/PlainSky/blob/43a329cbc3d19ffe01011f8a302ae79da7e2f197/PlainSky/Core/AppEnvironment.swift)
- [HTTP client/cache/retries at audit baseline](https://github.com/ColumbusLabs/PlainSky/blob/43a329cbc3d19ffe01011f8a302ae79da7e2f197/PlainSky/Core/Networking/HTTPClient.swift)
- [Today rendering at audit baseline](https://github.com/ColumbusLabs/PlainSky/blob/43a329cbc3d19ffe01011f8a302ae79da7e2f197/PlainSky/Features/Today/TodayView.swift)
- [Existing repository regression tests](https://github.com/ColumbusLabs/PlainSky/blob/43a329cbc3d19ffe01011f8a302ae79da7e2f197/PlainSkyTests/WeatherRepositoryTests.swift)

### External documentation checked September 24, 2026

- **[E1]** [NWS API documentation](https://www.weather.gov/documentation/services-web-api): location/grid lookup caching, periodic remapping checks, cache-friendly responses, and upstream observation delays.
- **[E2]** [NWS alerts service](https://www.weather.gov/documentation/services-web-alerts): alert request frequency guidance and rate limiting.
- **[E3]** [Apple: Accessing cached data](https://developer.apple.com/documentation/foundation/accessing-cached-data): URLCache and the difference between protocol caching and unconditional cache reuse.
- **[E4]** [Apple: URLSessionTaskMetrics](https://developer.apple.com/documentation/foundation/urlsessiontaskmetrics) and [transaction metrics](https://developer.apple.com/documentation/foundation/urlsessiontasktransactionmetrics): collect actual request/cache/timing evidence rather than guessing from a spinner.
- **[E5]** [Swift: TaskGroup](https://docs.swift.org/latest/documentation/swift/taskgroup/): structured scopes await all children; cancellation is cooperative.
