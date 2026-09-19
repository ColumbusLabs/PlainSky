# Architecture

## Product rule

The app does not invent weather. Provider values are preserved with their source, observation/issue time, validity interval, and fetch time. The UI may format units and dates, but it does not average forecasts or manufacture missing meteorological values.

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

Fallback behavior will be explicit. In particular, a modeled Apple current-conditions fallback must not be silently mixed field-by-field with a nearby NWS station observation.

## Layers

1. **Provider adapters** translate external provider payloads into typed records.
2. **Repository / refresh coordinator** owns fetching, caching, cancellation, and deduplication.
3. **Source policy** chooses the approved provider for each product.
4. **WeatherStore** exposes presentation-ready state to the SwiftUI feature views.
5. **Feature views** render values and their freshness without initiating independent duplicate requests.

## Initial feature areas

- Today
- Forecast
- Radar
- Places and Settings
- Shared source/freshness and alert detail surfaces

## Networking principles

- NWS requests identify the application with an appropriate User-Agent.
- Cache headers and provider validity windows are honored.
- A recent download time is never substituted for an older observation time.
- A request failure is different from a valid empty response.
- Location changes cancel or supersede older in-flight responses.
- Radar, WeatherKit, and NWS failures are isolated so one provider cannot blank the whole app.

## Live-provider rollout

The first UI slices run against deterministic mock data. Live provider adapters are added only after the presentation model is stable, keeping provider credentials/entitlements out of feature views.
