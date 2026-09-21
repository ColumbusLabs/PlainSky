# WeatherKit activation

The native WeatherKit adapter is already implemented. It does **not** use a WeatherKit REST API key.

## External Apple Developer step

For the App ID used by this project (`com.columbuslabs.weatherapp`):

1. Sign in to Apple Developer.
2. Open **Certificates, Identifiers & Profiles**.
3. Open **Identifiers** and select the App ID for `com.columbuslabs.weatherapp`.
4. Enable the **WeatherKit** capability/app service and save.
5. Allow Apple/Xcode a few minutes to refresh provisioning if needed.
6. In Xcode, select the app target and confirm the WeatherKit capability is present under **Signing & Capabilities**.

The repo already contains `PlainSky/PlainSky.entitlements` with:

```xml
<key>com.apple.developer.weatherkit</key>
<true/>
```

and XcodeGen already points the target at that entitlement file.

## Testing after Apple-side activation

WeatherKit supplements are enabled for normal launches. To run with only NWS and NOAA/NCEP for diagnostics, launch with:

```
--live-nws
```

Normal mode keeps NWS as the primary U.S. forecast/current source and uses WeatherKit only for:

- next-hour precipitation
- UV
- sunrise/sunset
- whole-group current-condition fallback when a usable NWS observation is unavailable

Apple Weather attribution is already rendered wherever WeatherKit data is displayed.

Use `--preview-data` for deterministic UI validation without live provider requests.

Live launches can restore a matching cache for up to six hours, then render primary NWS data while the WeatherKit supplemental request is still loading. NOAA/NCEP remains the radar source in both live modes.
