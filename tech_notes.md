# Technical Notes

How the app is built, how its data is stored, and the rules behind the main features. Update this file when you change any of them.

- [Stack and build settings](#stack-and-build-settings)
- [Project layout](#project-layout)
- [App lifecycle and state](#app-lifecycle-and-state)
- [Persistence](#persistence)
- [Domain models](#domain-models)
- [Entry requirement rules](#entry-requirement-rules)
- [Bundled data](#bundled-data)
- [Map rendering](#map-rendering)
- [UI structure](#ui-structure)
- [Random destination (dice)](#random-destination-dice)
- [Backup format and import](#backup-format-and-import)
- [Localization](#localization)
- [Friends](#friends)
- [iOS 16 support (planned)](#ios-16-support-planned)
- [Testing](#testing)
- [Conventions](#conventions)

## Stack and build settings

- SwiftUI app with MapKit (wrapped in `UIViewRepresentable`) for the main map. No third-party packages.
- Deployment target: iOS 26.2. Bundle ID `com.marcocheung.whereCanIGo`.
- Swift 5 language mode with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and approachable concurrency. Types are main-actor isolated by default. Code that must run in the background (backup decoding, DTOs, geometry preparation) is marked `nonisolated` explicitly.
- State uses `ObservableObject` / `@Published` / `@EnvironmentObject`. The project uses no `@Observable` and no SwiftData.
- Info.plist values are generated from build settings (`INFOPLIST_KEY_*`) and merged with `whereCanIGo-Info.plist`, which holds what build settings can't express: the travel card document type and exported UTType. The only privacy usage string is the camera description.
- CryptoKit is used for travel card signing. Files that read `.publicKey` or `.rawRepresentation` need their own `import CryptoKit`.
- `PrivacyInfo.xcprivacy` declares app-only UserDefaults access (`CA92.1`), no tracking and no developer-collected data. `ITSAppUsesNonExemptEncryption = NO` covers the current OS-provided cryptography.

## Project layout

```
where-can-i-go-ios/whereCanIGo/
├── whereCanIGoApp.swift      App entry; creates AppState, UserProfileStore and FriendStore,
│                             runs bootstrap() and passes opened files to FriendStore
├── RootView.swift            Loading → first-launch passport picker → ContentView
├── ContentView.swift         Map + bottom panel (system sheet or floating iPad panel)
├── Localization.swift        Localized names for countries and enums
├── Models/
│   ├── AppState.swift        Central store: data, selection, mutations, restore commit
│   ├── AppData.swift         Persisted user data (app_data.json)
│   ├── Country, DefaultVisaEntry, PersonalVisa, Visit, PlannedTrip, VisaCategory,
│   │   VisitPurpose, Continent, SearchEngine
│   ├── UserDataBackup.swift  Backup file format, validation, export, import planning
│   ├── UserDataRestore.swift Import mode, restore summary, restore errors
│   ├── TravelCard.swift      Travel card format, signing, verification, limits
│   └── UserDataPreview.swift Display-only mappings for the import preview
├── Services/
│   ├── DataStore.swift               Reads/writes app_data.json
│   ├── CountryRepository.swift       Loads countries.json and default_visas_<ISO3>.json
│   ├── AirlineRepository.swift       Loads and validates airline_destinations.json
│   ├── VisaEligibility.swift         Works out the entry requirement for one country
│   ├── UserProfileStore.swift        Name and avatar (user_profile.json)
│   ├── VisaAttachmentStore.swift     Attachment files and restore staging/rollback
│   ├── UserDataTransferService.swift Export and transactional import
│   ├── SharingIdentity.swift         Keychain signing key and card revision counter
│   ├── TravelCardBuilder.swift       SharingOptions, builds and signs a card file
│   ├── FriendStore.swift             friends.json, receipt rules, TravelCardReader
│   ├── UserDataBackupDocument.swift  FileDocument used by the exporter
│   └── AppInfo.swift                 Version, public links, feedback email and mailto builder
├── Views/
│   ├── CountryMapView.swift, CountryMapGeometry.swift, CountryMapHighlight.swift
│   ├── WorldMapView.swift    Flat map used for the shareable passport image
│   ├── CountryDetailCard.swift, CountryPickerSheet.swift, PassportPickerView.swift
│   ├── UserProfileView.swift (also contains SettingsView), ProfilePhotoEditorSheet.swift
│   ├── UserDataTransferView.swift  Export screen and import preview
│   ├── About/                About, Privacy Policy, FAQ, Send Feedback, Acknowledgements,
│   │                         and the hidden "open world" page (tap the Where I've Been
│   │                         card five times)
│   ├── Friends/              Friends segment, share and receive sheets, friend sheet,
│   │                         Sharing settings
│   └── Sheet/                Bottom panel: header, tabs and their sheets
└── Resources/                Bundled JSON, GeoJSON and data source notes
```

## App lifecycle and state

1. `whereCanIGoApp` creates one `AppState`, `UserProfileStore` and `FriendStore` and injects them with `.environmentObject`.
2. `AppState.bootstrap()` loads `countries.json`, then tries to load `app_data.json`.
   - Found: the saved data is used.
   - Missing or unreadable: HKG defaults are loaded so the map has colours, and `needsPassportSelection` shows the passport picker.
3. `RootView` shows a loading view, the first-launch passport picker, or `ContentView`.

`AppState` holds:

- `data: AppData`: everything the user owns except the profile and attachment files.
- `countries`: the sorted country list.
- Transient UI state: `selectedCountryCode`, `diceSpinTarget`, and the `pendingAdd…CountryCode` values. These let the country card ask a tab to open its add sheet. The tab handles the value in `onChange` / `onAppear` and sets it back to `nil`.
- `visaReferenceDate`: the date used to decide whether personal visas are valid. Call `refreshVisaValidity()` to move it to now.
- `dataRevision`: incremented whenever restored data is committed. Map caches include it in their signatures, so a restore always redraws the map.
- `isRestoring`: set during an import so the UI can disable editing.

## Persistence

All files live in the app's Documents directory.

| File / folder | Contents | Owner |
|---|---|---|
| `app_data.json` | `AppData`: passport, entry policies, personal visas, visits, planned trips | `DataStore` via `AppState` |
| `user_profile.json` | Name, cropped avatar, original photo and crop position | `UserProfileStore` |
| `visa_attachments/<visaID>/` | Attachment files; names are `<UUID>.<ext>` | `VisaAttachmentStore` |
| `visa_attachments/.restore-tmp/<UUID>/` | Staging and backup folders used during an import | `VisaAttachmentStore` |
| `friends.json` | Friends and their last received cards, photos inline | `FriendStore` |
| UserDefaults `sharing.defaults` | Default `SharingOptions` for the next card | `SharingOptions` |
| Keychain service `com.marcocheung.whereCanIGo.sharing` | Signing key and last card revision | `SharingIdentity` |

- `app_data.json` uses ISO 8601 dates, sorted keys, and atomic writes.
- Visa attachment writes and restore staging use `.completeFileProtection`; restore directories use `FileProtectionType.complete`. At launch, existing attachment and recovery files are upgraded in place. Failures are logged and surfaced with a retry action. OS file protection does not password-encrypt exported backup files or copies a user shares.
- `AppData` decodes `visits` and `plannedTrips` with `decodeIfPresent` so files from older versions still load. Follow the same pattern for any new field.
- `AppData.defaultVisas` holds the full list for the current passport (bundled entries plus user edits). Changing passport reloads the bundled list.
- Two save styles exist in `AppState`:
  - `save()` writes with `try?`. Visas, visits and entry policy edits use it, so a failed write is silent.
  - Planned-trip methods build an updated copy, save it with `try`, and only then publish it. Failures reach the caller.
  New code should follow the second style.

## Domain models

- **Country**: ISO3 `code` (the ID used everywhere), ISO2 `iso2`, English `name`, `flag` emoji. Display names come from `Locale`, see [Localization](#localization).
- **DefaultVisaEntry**: one entry policy for a country under the current passport: `category`, short `duration`, longer `remark`. Older data stored both in `duration`; the decoder splits it with `splitLegacyDuration`.
- **VisaCategory**: `visa_free`, `visa_on_arrival`, `eta`, `my_visa`, `visa_required`. Raw values are stored in JSON, so keep them stable. Colours are defined here.
- **PersonalVisa**: a visa the user holds. `coverage` is `issuing_country` or `schengen_area`; the initializer forces `issuing_country` for non-Schengen countries. `isValid(on:)` compares calendar days.
- **Visit**: one trip. Several visits can share a country. `dayCount` counts both end days.
- **PlannedTrip** (shown as Wishlist): a future trip. `durationMode` is `notSet`, `estimatedDays` or `dates`; the initializer clears fields that do not belong to the chosen mode.
- **Completing a planned trip**: `AppData.completePlannedTrip` creates a `Visit` with the same ID as the trip and removes the trip. The backup import relies on this: a wishlist ID that also exists as a visit counts as completed.

## Entry requirement rules

`VisaEligibility` decides the category for one country on one date:

1. If the bundled or edited entry policy is `visa_free`, the result is `visa_free`.
2. Otherwise, look for a personal visa that covers the country and is valid on the date. A visa for that exact country is preferred over a Schengen-area visa; then the later expiry date wins; ties are broken by ID.
3. If one is found, the result is `my_visa`. Otherwise it is the entry policy's category, or `visa_required` if the country has no entry.

`isAccessible` is true for `visa_free`, `visa_on_arrival` and `my_visa`. ETA counts as not accessible for the dice filter.

## Bundled data

All in `Resources/`:

- `countries.json`: `[{ code, iso2, name, flag }]`.
- `default_visas_<ISO3>.json`: `[{ countryCode, category, duration, remark }]` for one passport. A missing file gives an empty list.
- `airline_destinations.json`: `[{ id, name, destinationCountryCodes }]`. `AirlineRepository` rejects the whole file if IDs repeat, a field is empty, or a code is not three uppercase letters. Filters display text labels without airline logos.
- `world-countries.geojson`: Natural Earth public-domain 1:10m Admin-0 Countries, distributed through `datasets/geo-countries` (PDDL 1.0). The bundled file identifies `ne_10m_admin_0_countries`; the ISO3 code is read from the feature properties by `CountryMapView.Coordinator.extractISO3`. See `GEOJSON_INSTRUCTIONS.txt` and the in-app acknowledgements.
- `Source/*.sources.md`: where each passport's data came from.

Adding a passport needs the JSON file, the code in `PassportPickerView.supportedPassportCodes`, and a source entry in the README.

## Map rendering

`CountryMapView` is an `MKMapView` with a hybrid, realistic-elevation configuration, so zooming out shows a 3D globe. Each country is a polygon overlay filled with its category colour. Overlays are added at `.aboveRoads` so MapKit's place labels stay on top.

**Level of detail.** The raw GeoJSON has about 550k points, which is slow to draw zoomed out and makes borders look uneven. `CountryGeometry.prepare` builds five levels with Ramer–Douglas–Peucker simplification at tolerances of 0.2°, 0.06°, 0.02°, 0.006° and 0 (raw). Simplification runs in Mercator map points, so a tolerance means the same on-screen distance at every latitude. Very small rings are dropped at coarse levels, except where needed to keep micro-states visible.

When the camera changes, the coordinator picks the coarsest level whose error is under 0.5 screen points. It only switches back to a coarser level once the current one is finer than 0.18 points; this gap stops levels flickering near a threshold. On a switch, the new level is added first and the old one is removed 0.35 s later, so fills stay visible while MapKit prepares the new geometry.

**Recolouring.** `visaSignature` and `visitSignature` hash only the data that affects colours and visited markers. `updateUIView` compares them with the previous values and skips work when nothing changed.

**Selection.** The selected country gets two polyline overlays (`SelectionGlowOverlay`, `SelectionLineOverlay`) built from the current level's rings, drawn above all fills.

**Visited markers.** Countries with at least one visit get an amber check-mark annotation at a point inside their largest polygon (`CountryGeometry.visualCenter`).

**Dice spin.** Setting `appState.diceSpinTarget` starts a 2.5 s camera animation to the country. The final camera distance scales with the country's size, and the camera is shifted south so the country sits above the detail card.

**Tap hit-testing** checks the current level's renderer paths and picks the smallest matching bounding box, so enclaves win over the country around them.

`WorldMapView` is a separate flat map drawn with a SwiftUI `Canvas`. It is used for the shareable passport image, because `ImageRenderer` can't capture a live `MKMapView`.

## UI structure

- `ContentView` shows the map with a bottom panel.
  - Compact width (iPhone, narrow iPad window): a system `.sheet` with three detents: 290 pt, medium, large.
  - Regular width: a custom floating panel, 390 pt wide, with its own drag handle and the same three states (`PanelState`).
  - Both use the same `panelContent`: `SheetHeader` (passport, dice, profile) and a `TabView`.
- Tabs (`PanelTab`): Overview, My Visas, Travels. A Manage Data tab exists behind `showsManageDataTab` (currently `false`); its features are reached from the Overview tab.
- **Travels** (`MyTravelsTab`) has a segmented control for Been, Wishlist and Friends. Been uses `TravelSummaryCard`, `TravelCountryRow`, `CountryTripsSheet` and `TripEditorSheet`. Wishlist uses `WishlistSection`, `CountryPlansSheet` and `PlannedTripEditorSheet`. Friends uses `FriendsSection`, see [Friends](#friends).
- **Settings** (`SettingsView`, inside `UserProfileView.swift`) holds the search engine choice (`@AppStorage("searchEngine")`), Sharing settings for travel cards, and backup export/import.
- **Excel import** is not included in the release branch. The unfinished prototype and its feature-toggle strings are preserved on `feature/excel-import`.

## Random destination (dice)

`SheetHeader.randomSelectCountry()` picks at random from countries that meet all of these:

- It is not the passport country.
- Its continent is selected, or no continent is selected. HKG and MAC count as Asia.
- One of the selected airlines flies there, or no airline is selected.
- It is accessible, unless *Include All Entry Requirements* is on.

Continent and airline choices last for the current app session only.

## Backup format and import

The backup is one JSON file described by `UserDataBackup`. It has its own record types (`VisitRecord`, `WishlistRecord`, `PersonalVisaRecord`, `EntryPolicyRecord`) so `AppData` can change without breaking old files.

### File structure

```json
{
  "format": "wherecanigo.backup",
  "schemaVersion": 1,
  "kind": "fullBackup",
  "exportedAt": "2026-10-26T08:00:00.000Z",
  "app": { "version": "1.0", "build": "1", "platform": "iOS" },
  "profile": { "displayName": "Marco", "photo": { ...media } },
  "passport": { "code": "HKG" },
  "entryPolicies": { "overrides": [...], "removedCountryCodes": [...] },
  "personalVisas": [ { ..., "attachments": [ ...media ] } ],
  "visits": [...],
  "wishlist": [...],
  "sharingIdentity": { "privateKey": "<base64>", "lastRevision": 1767225600 },
  "friends": [ { "sharerID": ..., "publicKey": ..., "nickname": ..., "addedAt": ..., "lastReceivedAt": ..., "card": { ...payload } } ]
}
```

- **Entry policies** store only the user's edits compared with the bundled file for that passport: overrides plus removed codes. On import they are applied to the bundled list of the importing app.
- **Dates**: calendar days (`startDate`, `expiryDate`, …) are `yyyy-MM-dd` strings in the device's time zone (`BackupDay`), so a trip on 1 April stays on 1 April in another time zone. Instants (`exportedAt`, `createdAt`) are ISO 8601 UTC with milliseconds (`BackupTimestamp`).
- **Media** (`BackupMedia`): `fileName`, informational `mimeType`, `byteCount`, `sha256`, base64 `data`. The type comes from the file extension. Allowed types and size limits live in `BackupMediaPolicy`: attachments are images or PDF up to 20 MB, the profile photo is an image up to 10 MB. The whole file may be up to 100 MB.
- **Friends sections**: `sharingIdentity` and `friends` are optional and off by default on export. Older apps ignore them. See [Friends in backups](#friends-in-backups).
- **Optional sections**: a missing section means it was left out of the file. For example, `attachments: null` keeps the device's existing files for that visa, and `attachments: []` clears them.

### Compatibility rules

- Additive changes (new optional fields, new enum values) keep `schemaVersion`. Older apps ignore unknown keys. Unknown enum values fall back (`BackupValue.decode`), for example an unknown visit purpose becomes `other`.
- Breaking changes increase `schemaVersion`. Apps reject files with a newer version.
- `kind` is an open string type so unknown kinds still decode and can be rejected with a clear message. `visitShare` is reserved and unused; travel cards have their own format (`wherecanigo.travelcard`).

### Reading a file

1. `UserDataTransferService.readBackup` checks the file size, then reads and decodes in a detached task.
2. `decodeVerifyingMedia` reads only `format` and `schemaVersion` first, then the full document, then checks every SHA-256. This part leaves app models untouched.
3. Back on the main actor, `validate()` checks country codes, duplicate IDs, dates, and that each record converts to an app model.

### Import modes

`makeImportPlan` is pure: it returns the new `AppData`, the attachments to stage, the profile to apply, and a summary for the preview.

- **Replace**: the file wins. Passport, entry policies and all records come from the file. Visas without an attachments section keep this device's files.
- **Merge**: this device wins. Passport and entry policies stay. Only records with new IDs are added, so importing the same file twice adds nothing the second time. The profile name and photo are filled in only where the device has none.
- In both modes, a wishlist item whose ID exists as a visit is removed as completed.

### Applying an import

`UserDataTransferService.importBackup` runs as a transaction:

1. Mark `isRestoring`, snapshot current data and profile.
2. Create a workspace in `visa_attachments/.restore-tmp/<UUID>/` and write the old data and profile to its `backup/` folder.
3. Write new attachments into `staging/`.
4. `AppState.commitRestoredData` saves `app_data.json`, then publishes it and clears selection state.
5. Move staged attachment folders into place; existing folders move to `backup/` first.
6. Apply the profile, then restore friends (replace or merge in `FriendStore`).
7. Install the sharing identity last, since a Keychain write can't be rolled back.
8. Delete attachment folders of visas that no longer exist, delete the workspace, publish the summary and post `.userDataDidRestore`.

If a step fails, earlier steps are rolled back, including the previous friends list. If the rollback also fails, the workspace is kept and the error message shows its path so the files can be recovered by hand.

### Export

`UserDataBackup.make` builds the file from the current data. Files of unsupported type or size are left out and listed in `skippedFileNames`. The result is validated with the same rules as an import before it is offered for saving.

## Localization

- `Localizable.xcstrings` (source language English) with `zh-Hant` and `zh-Hans`. `whereCanIGo-InfoPlist.xcstrings` covers Info.plist strings.
- Most keys are the English text. Error messages and some import/export strings use identifier keys such as `backup.error.corrupted` or `import.reading`.
- Country names come from `Locale.localizedString(forRegionCode:)`. China has an override in `Localization.swift` so it shows 中國 / 中国 / China consistently.
- Enums have both `displayName` (English, older) and `localizedDisplayName`. Use `localizedDisplayName` in UI.

## Friends

Status: phase 1 implemented.

Under Travels, the **Friends** segment lets users exchange a "travel card" file through the share sheet (AirDrop, Messages, or any app). The receiver can view the sender's Been and Wishlist offline. There is no server.

### What this model means for users

- A friend's data is a snapshot from the last card received. New trips appear only after the friend shares again.
- Removing a friend deletes the data from this device only. The friend is not notified.
- Turning off sharing affects future cards only. Cards already sent stay with the people who received them.
- Adding is one-way: A can hold B's card while B has nothing from A. After adding or updating a friend, the app offers to share a card back.

UI wording follows this: "Share My Travel Card", "Add Friend", "Update Friend", "Last received …".

### Phases

| Phase | Scope |
|---|---|
| 1 (done) | Card format and file type, signing (TOFU), sharing identity, Sharing settings, share confirmation, Friends segment, read-only friend sheet, snapshot updates, "share back" prompt, friends and identity in backups |
| 2 | Nearby two-way exchange with the Network framework; compare view (countries in common, "they've been where I want to go") |
| 3 (optional) | Automatic updates through CloudKit sharing |

### Files

| File | Role |
|---|---|
| `Models/TravelCard.swift` | Envelope, payload types, `TravelCardCrypto` (sharer ID, safety code), signing, `decodeAndVerify`, `validateAndNormalize`, limits, errors |
| `Services/SharingIdentity.swift` | Signing key and revision counter in the Keychain |
| `Services/TravelCardBuilder.swift` | `SharingOptions` (defaults in UserDefaults), builds the payload from `AppData` and the profile, writes the signed file |
| `Services/FriendStore.swift` | `Friend`, `friends.json`, receipt rules, save/merge, `TravelCardReader` |
| `Views/Friends/FriendsSection.swift` | Friends segment: share and add buttons, friend list, opening files |
| `Views/Friends/ShareCardView.swift` | Share confirmation (`ShareCardView`, `ShareCardSheet`) and `SharingSettingsView` |
| `Views/Friends/ReceiveCardSheet.swift` | Shown after a card is opened: add, update, or explain why nothing changed |
| `Views/Friends/FriendDetailSheet.swift` | Read-only friend sheet with Been and Wishlist |
| `Views/Friends/TravelCardComponents.swift` | Shared pieces: option toggles, content rows, header, share sheet wrapper |

### Card file

- File extension `.wcigcard`, UTType `com.marcocheung.whereCanIGo.travelcard` conforming to `public.data` and `public.content`, declared with a document type (`LSHandlerRank` Owner) in `whereCanIGo-Info.plist`. The content is JSON, but the type does not conform to `public.json`: a text type makes Files show a text preview when the card is tapped.
- `LSSupportsOpeningDocumentsInPlace` is on, so tapping a card in Files opens the app with the original file. `TravelCardReader` reads it with `NSFileCoordinator`, which also downloads a card stored only in iCloud Drive.
- AirDrop: since iOS 17, files received by AirDrop for third-party apps are saved to Files › Downloads and the app is not opened (Apple DTS, developer forums thread 737971). Users open the card by tapping it in Downloads. Sending a custom-scheme URL with the card inside is a possible way to open the app directly; it is untested.
- Opening a card from another app: `onOpenURL` stores the URL in `FriendStore.incomingCardURL`. `ContentView` opens the panel on Travels, `MyTravelsTab` switches to Friends, and `FriendsSection` reads the file. Files iOS copied to `Documents/Inbox` are deleted after reading.
- "Add Friend" uses `fileImporter` with the card type and plain JSON, so cards saved under a `.json` name still import.
- The backup reader and the card reader check `format` first, so each rejects the other's files with a clear message.
- Envelope:

  ```json
  {
    "format": "wherecanigo.travelcard",
    "schemaVersion": 1,
    "publicKey": "<base64 P-256 raw public key>",
    "payload": "<base64 JSON bytes>",
    "signature": "<base64 raw r||s ECDSA signature of the payload bytes>"
  }
  ```

  The signature covers the exact payload bytes, so no canonical JSON form is needed.
- Payload: `sharerID`, `cardRevision`, `createdAt`, `displayName`, optional `photo`, optional `been`, optional `wishlist`, and `shared`, which lists the categories and fields the sender chose. Dates are `yyyy-MM-dd` (`BackupDay`); `purpose` is the `VisitPurpose` raw value.
- Same versioning rules as the backup format: additive changes keep `schemaVersion`, newer versions are rejected.

### Identity and signing

- The first share creates a P-256 key with CryptoKit. `SharingIdentity` stores it as a synchronizable Keychain item (`kSecAttrAccessibleAfterFirstUnlock`), so iCloud Keychain carries it to the user's other devices. If a synchronizable write fails, it falls back to a device-only item.
- `sharerID` is the hex SHA-256 of the raw public key. Holding the same private key is the only definition of "same person".
- Safety code: 12 digits from SHA-256 of `"wcig-safety"` plus the public key, shown in groups of four. It appears in Sharing settings, on the receive sheet, and in the friend menu.
- Reset: Sharing settings has "Reset Safety Code", which calls `SharingIdentity.reset()` to delete the key and revision items (synced copies included). The next share creates a new key, so recipients see a new `sharerID` and treat the user as a new person.
- Trust on first use: the first card from a `sharerID` stores its public key. Since the ID is the hash of the key, later cards with the same ID always carry the same key, and the signature must verify.
- `cardRevision` is `max(last + 1, current Unix seconds)`, stored in the Keychain next to the key. It keeps increasing across devices that share the key, and still increases when the clock is wrong.

### Receiving a card

`FriendStore.receipt(for:ownSharerID:)` decides what `ReceiveCardSheet` shows:

| Receipt | When | Sheet |
|---|---|---|
| `ownCard` | `sharerID` is the user's own | Message only |
| `older` | Known friend, lower revision | Message; card not saved |
| `unchanged` | Known friend, same revision | Message and "Share My Travel Card" |
| `update` | Known friend, higher revision | Old → new name, photo and counts; "Update Friend" |
| `new` | Unknown `sharerID` | Card contents; "Add Friend" |

For `new`, if a friend with the same display name exists, the sheet explains that this may be the same person on a new phone without a backup, or someone else. The user can add a new friend, or replace the existing one after comparing safety codes. Replacing moves the nickname and `addedAt` to the new identity.

After saving, the sheet asks "Share your travel card with <name>?" and opens the share confirmation.

### Snapshot rules

- A new card replaces the stored snapshot. Records the friend deleted disappear.
- A category missing from the new card is shown as "Not shared". The photo follows the same rule.
- "Not shared" and "Shared, no records" have separate messages in the friend sheet.
- The local nickname is kept when the friend's display name changes.
- `FriendStore.save` ignores a card whose revision is not higher than the stored one, so an older file can't overwrite a newer card.

### What can be shared

`SharingOptions` is stored in UserDefaults under `sharing.defaults`. Everything is off at first.

| Group | Options |
|---|---|
| Profile | Display name (falls back to the profile name), Profile photo |
| Been | On/off; Dates, Length of Stay, Location, Purpose |
| Wishlist | On/off; Planned Dates, Estimated Days, Location, Purpose |

With every field off, a category shares country codes only. Notes, passport, entry policies, My Visas and visa attachments stay on the device. `TravelCardBuilder` reads only the fields listed above, so a new field on `Visit` or `PlannedTrip` stays private until the builder is changed.

The share sheet (`ShareCardView`) shows what this card contains and lets the user change options for this card. "Remember as Default" saves them back to `sharing.defaults`.

### Validation of received cards

`decodeAndVerify` checks, in order: file size (4 MB), `format`, `schemaVersion`, signature, `sharerID` against the key, then `validateAndNormalize`:

- Display name 1–60 characters, locations up to 200, up to 5,000 Been and 2,000 Wishlist records, day counts up to 36,500.
- Country codes are three uppercase letters, dates parse, end dates are not before start dates.
- Categories the `shared` object marks as off are dropped. Unknown purposes display as Other.
- The photo (up to 1 MB) is re-encoded with `UserProfileStore.preparePhoto`, which also removes EXIF data such as GPS position. Cards restored from a backup skip the re-encode, because they were checked when first received.

### Storage

`friends.json` in Documents holds `schemaVersion` and a list of `Friend`: `sharerID`, `publicKey`, `nickname`, `addedAt`, `lastReceivedAt`, and the verified `card` payload with its photo inline. Dates are ISO 8601 with whole seconds; `save` truncates times so the copy in memory matches the file.

If `friends.json` fails to load, `FriendStore.loadError` is set, the Friends segment offers "Try Again", and backup export and import refuse to touch friends until it loads.

Any future "delete all data" action must clear `friends.json`, the Keychain items and `sharing.defaults`.

### Friends in backups

Export has two extra toggles, both off by default:

- **Friends**: writes `friends` with each friend's public key and payload, so later cards still verify after a restore. The footer reminds the user the file holds other people's records.
- **Sharing Identity**: writes the private key and last revision in plain text. The footer warns that anyone with the file can make cards friends accept as this user. Password protection can be added later.

On import, each friend is checked again (`FriendRecord.toModel`): the key parses, `sharerID` matches the key and the card, and the payload passes validation.

| Mode | Friends | Sharing identity |
|---|---|---|
| Replace | `FriendStore.replaceAll` | Installed from the file |
| Merge | `FriendStore.merge`: new friends are added, a newer card replaces an older one, local nicknames win | Installed only if this device has no key or the same key; otherwise this device's key is kept and the summary says so |

When installing, the revision counter becomes the higher of the file's and the device's value.

### Friend sheet

`FriendDetailSheet` uses medium and large detents. It reuses `TravelSummaryCard` (with `showsChevron: false`), `WishlistSummaryCard` and `TravelCountryRow`, fed by `TravelStats(records:countries:)` and `WishlistStats(trips:countries:)`. Payload records are turned into temporary `PlannedTrip` values for display only. The sheet is read-only. A friend's records live in `FriendStore` and stay separate from `AppState`, the map and visa state.

The menu has Set Nickname, Show Safety Code and Remove Friend.

### Phase 2 notes

Nearby exchange will use the Network framework: Bonjour discovery plus a TLS connection. Both people open an "Exchange nearby" screen, confirm a short code shown on both phones, then each sends its card. The iOS 26 Swift API (`NetworkListener`, `NetworkBrowser`, `NetworkConnection`) needs iOS 26; to support iOS 16, use `NWListener`, `NWBrowser` and `NWConnection` or wrap both behind one interface. This needs `NSLocalNetworkUsageDescription` and `NSBonjourServices` in Info.plist.

## iOS 16 support (planned)

Current findings:

- Three uses of `glassEffect` (iOS 26). Wrap them in `if #available(iOS 26, *)` with a material fallback.
- No `@Observable` or SwiftData, which are the hardest to back-port.
- The `Tab(...)` initializer in `ContentView` needs iOS 18; iOS 16 needs `.tabItem`.
- Check other APIs newer than iOS 16 when lowering the target, for example `onChange(of:)` with two parameters (iOS 17) and `URL.documentsDirectory` (iOS 16, fine).

For new code: keep using `ObservableObject`, prefer APIs available in iOS 16, and wrap newer visual effects in availability checks.

## Testing

The project has no test target yet. Good first candidates, since they are pure logic:

- `VisaEligibility`
- `DefaultVisaEntry` legacy duration splitting
- `UserDataBackup` decode, validate, `makeImportPlan` (replace and merge), `EntryPolicies.diff` / `applied`
- `AppData.completePlannedTrip`
- `AirlineRepository.decode`
- `CountryGeometry` simplification
- `TravelCardEnvelope` sign and verify (tampered payload, wrong key), `validateAndNormalize`, and `FriendStore` receipts, save and merge. `FriendStore(fileURL:)` takes a temporary file. Avoid `SharingIdentity` in tests, since it writes to the real Keychain.

`DataStore`, `UserProfileStore`, `FriendStore` and `AppState` accept custom file locations, so tests can use a temporary directory.

## Conventions

- Country codes are ISO 3166-1 alpha-3 everywhere except `Country.iso2`.
- Raw values written to disk (enums, keys) stay stable. Add a new case for a new meaning.
- New persisted fields decode with `decodeIfPresent` and a default.
- Save to disk first, then update published state.
- User-facing strings go through `String(localized:)` or SwiftUI `Text` so they appear in `Localizable.xcstrings`.
- Comments explain why something is done when it isn't obvious. Keep them short and factual.
