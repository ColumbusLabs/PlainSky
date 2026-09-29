# Privacy policy

Effective September 29, 2026

PlainSky is a free weather app with no ads, subscriptions, accounts, or third-party analytics. This policy describes the information the app uses to provide weather, maps, the home screen widget, and optional notifications.

## Location and weather requests

PlainSky stores your selected and saved places on your device so it can show weather for them. If you allow location access, the app can use your current location as a place. The home screen widget and background refresh use the place selected for notifications.

When PlainSky requests weather, it sends the selected place's coordinates to the National Weather Service (NWS) for observations, forecasts, and alerts. When Apple WeatherKit features are requested, the coordinates are sent to Apple. The radar map requests NOAA/NCEP radar imagery and Apple MapKit basemap tiles for the visible map area. The optional HRRR forecast radar uses map tiles from Iowa Environmental Mesonet at Iowa State University, which also receives requests for the visible map area. These requests happen as weather products or map areas are loaded. Those providers handle requests under their own terms and privacy practices.

## Optional NWS push alerts

If notifications are allowed and at least one NWS alert category is enabled, PlainSky sends the APNs device token, notification environment, alert category choices, place name, and alert coordinates rounded to two decimal places (about 1 km) to PlainSky's Cloudflare alert service. The service rounds the coordinates again before storing them. It uses the location to find relevant NWS alerts and the token to deliver those alerts through Apple Push Notification service (APNs). Cloudflare D1 stores the registration, including the rounded coordinates, NWS alert zones, place name, preferences, and token.

Precipitation start notices use Apple WeatherKit data and are scheduled as local notifications on the device. They do not use the NWS push registration service.

### Retention and removal

The alert service keeps a device registration until PlainSky successfully sends an unregister request after all NWS alert categories are turned off or notification permission is revoked, or APNs reports that the token is invalid. The service has no automatic expiry for device registrations. Turning off all NWS alert categories sends the removal request when the device can reach the service; if it fails, a later app sync can retry it. Uninstalling PlainSky does not proactively send a removal request, so a registration can remain until APNs reports the token as invalid.

The app also stores its alert choices, selected alert place, and APNs token locally in the shared app-group settings used by PlainSky and its widget.

## Tracking and advertising

PlainSky does not use location, device identifiers, or alert preferences to track you across other companies' apps or websites. It does not include ads or third-party analytics.

## Contact and support

For support, use [PlainSky's public GitHub Issues page](https://github.com/ColumbusLabs/PlainSky/issues/new). Issues are public. Do not post your precise location, APNs token, or other private information.
