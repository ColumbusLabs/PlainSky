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

The repo already contains `WeatherApp/WeatherApp.entitlements` with:

```xml
<key>com.apple.developer.weatherkit</key>
<true/>
```

and XcodeGen already points the target at that entitlement file.

## Testing after Apple-side activation

Generate/open the project, then launch with:

```
--live-weatherkit
```

That mode keeps NWS as the primary U.S. forecast/current source and enables WeatherKit only for:

- next-hour precipitation
- UV
- sunrise/sunset
- whole-group current-condition fallback when a usable NWS observation is unavailable

Apple Weather attribution is already rendered wherever WeatherKit data is displayed.

Once that device test passes, the only remaining activation change is to make the WeatherKit-enabled mode the normal default instead of requiring the launch argument.
