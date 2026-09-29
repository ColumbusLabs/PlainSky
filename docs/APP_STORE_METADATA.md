# PlainSky App Store listing

Prepared September 29, 2026 for the English (U.S.) listing.

## App information

- Name: PlainSky
- Subtitle: Weather, radar & alerts. Free.
- Primary category: Weather
- Price: Free in every configured storefront. No in-app purchases, subscriptions, ads, or paid feature tiers.
- Age rating: Apple calculated 4+ from the completed content questionnaire. This is a general-audience weather app, not a Kids category app.
- Distribution: All 175 current App Store territories; new territories enabled. Weather coverage is described separately below.
- Release: Manual release after approval.
- Source: https://github.com/ColumbusLabs/PlainSky
- Support: https://github.com/ColumbusLabs/PlainSky/blob/main/docs/SUPPORT.md
- Privacy policy: https://github.com/ColumbusLabs/PlainSky/blob/main/docs/PRIVACY.md

## Promotional text

Completely free weather. No ads, subscriptions, or paid upgrades. Get NWS forecasts and alerts, NOAA radar, and supplemental Apple Weather data in one clean app.

## Description

PlainSky is a completely free weather app. Every feature is free, with no ads, no subscriptions, no in-app purchases, and no account required.

Get a clear view of the weather with real data from the National Weather Service, NOAA, and Apple Weather. PlainSky is built for weather in the United States and supported U.S. territories; available products vary by location.

EVERYTHING IS FREE
Check current conditions, browse hourly and daily forecasts, follow radar, save places, use the home screen widget, and choose the notifications you want. There are no premium tiers or locked features.

REAL WEATHER SOURCES
The National Weather Service supplies forecasts, observations, and official alerts. NOAA supplies radar, with NOAA HRRR forecast radar provided through the Iowa Environmental Mesonet. Apple Weather adds next-hour precipitation, UV, sunrise and sunset information, and current conditions when needed. Supplemental products and forecast radar are available where supported.

WEATHER AT A GLANCE
See temperature, feels-like, precipitation chances, wind, humidity, and more. Switch between U.S. and metric units, check saved places, and keep current conditions close with a home screen widget.

OPTIONAL NOTIFICATIONS
Choose NWS warnings, watches, advisories, and statements for your alert place. Enable precipitation-start notices where Apple next-hour data is available. Notification delivery depends on network and iOS background availability. Always follow official guidance from local authorities.

OPEN SOURCE ON GITHUB
PlainSky is open source under the MIT License. Explore the code, report issues, and contribute at https://github.com/ColumbusLabs/PlainSky.

PlainSky requires iOS 17 or later and an internet connection for fresh weather data.

## Keywords

forecast,radar,NOAA,NWS,rain,temperature,storm,alerts,widget,precipitation,free,ad-free

## License

PlainSky's source code is available under the [MIT License](../LICENSE). The license does not replace the separate terms applicable to weather data, Apple services, or other third-party products.

## App Review notes

PlainSky is a free native iPhone weather app. No login, account, subscription, or purchase is required. All features are available without payment.

For a full weather demonstration, use a U.S. city such as Indianapolis, Indiana. Location permission is optional: reviewers can search for and save a place in Settings. Notification permission is optional and is needed only for notifications. Internet access is required for fresh weather and maps.

The National Weather Service supplies U.S. forecasts, observations, and official alerts. NOAA supplies radar. Apple WeatherKit provides next-hour precipitation, UV, sunrise/sunset, and current-condition fallback where available. Apple Weather attribution and its legal link appear in Today, Settings, metric details, and the Forecast header when it uses Apple current conditions. The home screen widget uses the NWS pipeline. NOAA HRRR forecast radar is provided by the Iowa Environmental Mesonet and is limited to the contiguous U.S. Provider availability varies by location; unavailable data is identified in the app.

Optional NWS push notifications register an APNs token, approximate alert-place coordinates, a place label, and alert-category preferences with PlainSky's alert service. This data is used for app functionality, never advertising or tracking. Turning off all NWS alert categories requests deletion when the device can reach the service. Precipitation-start notifications are generated on the device during background refresh.

The app uses standard operating-system HTTPS/TLS and does not implement proprietary or non-exempt encryption.

## Verified preparation

- Free pricing is configured across all 175 current storefronts, with new territories enabled.
- The English listing, Weather category, 4+ content questionnaire, and manual release setting are saved in App Store Connect.
- Today, Forecast, and Radar screenshots at 1320 × 2868 are uploaded and have `COMPLETE` processing status.
- All 122 unit tests pass. The 1.0.0 (3) archive includes the revised app/widget privacy manifests, client-side alert-coordinate rounding, alert-registration removal, and Apple Weather attribution.
- Apple processed 1.0.0 (3) as `VALID` and `APP_STORE_ELIGIBLE`; build 3 is selected for this App Store version. The version remains `PREPARE_FOR_SUBMISSION` with manual release enabled.
- Public privacy and support documents are published in this repository; both URLs are saved and verified in App Store Connect.
- The App Review contact details and final review notes are saved and verified in App Store Connect. Private contact details are not included in this repository.
- The App Privacy questionnaire is fully entered and saved: Coarse Location, Device ID, and Other Data Types; App Functionality only; linked to the device; no tracking. Apple's final Publish attestation is pending owner approval.
- Browser verification confirmed the Free Apps Agreement and Digital Services Act compliance are Active, and the app is identified as a trader. The version's Save button is disabled because the listing has no unsaved changes.

## Remaining submission gates

- Apply the saved App Privacy responses after owner approval of Apple's final accuracy, compliance, and ongoing-update attestation.
- Validate the final signed build's WeatherKit products and attribution on a physical iPhone. The connected iPhone still had 1.0.0 (2) when checked on September 29, 2026.
- Run Apple's final Add for Review validation only when the owner authorizes that step. It has deliberately not been run, and the version remains Prepare for Submission.
