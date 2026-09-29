# App Store Connect privacy answers

Prepared for PlainSky's 1.0.0 release candidate on September 29, 2026. These are the answers to enter in App Store Connect; the privacy manifest alone does not publish the App Store privacy label.

All answers below were entered and saved in the signed-in App Store Connect browser on September 29, 2026. The completed product-page preview shows all three data types linked to the device for App Functionality, with no tracking. Apple's final Publish confirmation remains pending owner approval of its accuracy, compliance, and ongoing-update attestation. Publishing the privacy responses is separate from adding the app for review.

## Data collection

Choose **Yes, we collect data from this app**. The optional alert service retains a registration after the request completes. Do not select "Data Not Collected."

| Data type | Purpose | Linked to user/device | Tracking |
| --- | --- | --- | --- |
| Coarse Location | App Functionality | Yes | No |
| Device ID | App Functionality | Yes | No |
| Other Data Types | App Functionality | Yes | No |

Coarse Location covers the rounded alert-place coordinates, place label, and relevant NWS alert zones. Device ID covers the APNs push token. Other Data Types covers the saved NWS alert-category preferences and notification environment. These are kept in one registration, so they are linked through the device token even though the app has no account system.

The data is not used for advertising, marketing, cross-app tracking, analytics, or data-broker sharing. No tracking permission prompt is needed for this functionality.

The current release candidate rounds alert-service coordinates on the device before transmission. Weather and map requests still use the selected place's coordinates or map area to serve those requests. Selected/saved places, shared widget settings, and on-device diagnostic state are stored locally; local storage by itself is not collection for Apple's privacy label.

## URLs

- Privacy policy: https://github.com/ColumbusLabs/PlainSky/blob/main/docs/PRIVACY.md
- Support: https://github.com/ColumbusLabs/PlainSky/blob/main/docs/SUPPORT.md

## Evidence and Apple definitions

The app registration flow is in `PlainSky/Features/Notifications/AlertPushRegistration.swift`. The retained registration and removal behavior are in `backend/alerts-worker/src/index.ts` and its D1 migration. The app and widget include `PlainSky/Resources/PrivacyInfo.xcprivacy`.

Apple defines collection in terms of off-device data retained beyond the real-time request and requires functionality-only collection to be disclosed: [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/). See also [adding collection details to a privacy manifest](https://developer.apple.com/documentation/technotes/tn3184-adding-data-collection-details-to-your-privacy-manifest) and [required reason APIs](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).

Reassess these answers if the alert service, analytics, logging, or providers change. The questionnaire is saved; applying the privacy label requires completing Apple's final Publish confirmation in App Store Connect.
