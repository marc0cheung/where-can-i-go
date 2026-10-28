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
- [Friends (planned)](#friends-planned)
- [iOS 16 support (planned)](#ios-16-support-planned)
- [Testing](#testing)
- [Conventions](#conventions)

## Stack and build settings

- SwiftUI app with MapKit (wrapped in `UIViewRepresentable`) for the main map. No third-party packages.
- Deployment target: iOS 26.2. Bundle ID `com.marcocheung.whereCanIGo`.
- Swift 5 language mode with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and approachable concurrency. Types are main-actor isolated by default. Code that must run in the background (backup decoding, DTOs, geometry preparation) is marked `nonisolated` explicitly.
- State uses `ObservableObject` / `@Published` / `@EnvironmentObject`. The project uses no `@Observable` and no SwiftData.
- Info.plist values are generated from build settings (`INFOPLIST_KEY_*`). The only privacy usage string is the camera description.

## Project layout

```
where-can-i-go-ios/whereCanIGo/
├── whereCanIGoApp.swift      App entry; creates AppState and runs bootstrap()
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
│   └── UserDataPreview.swift Display-only mappings for the import preview
├── Services/
│   ├── DataStore.swift               Reads/writes app_data.json
│   ├── CountryRepository.swift       Loads countries.json and default_visas_<ISO3>.json
│   ├── AirlineRepository.swift       Loads and validates airline_destinations.json
│   ├── VisaEligibility.swift         Works out the entry requirement for one country
│   ├── UserProfileStore.swift        Name and avatar (user_profile.json)
│   ├── VisaAttachmentStore.swift     Attachment files and restore staging/rollback
│   ├── UserDataTransferService.swift Export and transactional import
│   └── UserDataBackupDocument.swift  FileDocument used by the exporter
├── Views/
│   ├── CountryMapView.swift, CountryMapGeometry.swift, CountryMapHighlight.swift
│   ├── WorldMapView.swift    Flat map used for the shareable passport image
│   ├── CountryDetailCard.swift, CountryPickerSheet.swift, PassportPickerView.swift
│   ├── UserProfileView.swift (also contains SettingsView), ProfilePhotoEditorSheet.swift
│   ├── UserDataTransferView.swift  Export screen and import preview
│   └── Sheet/                Bottom panel: header, tabs and their sheets
└── Resources/                Bundled JSON, GeoJSON and data source notes
```

## App lifecycle and state

1. `whereCanIGoApp` creates one `AppState` and injects it with `.environmentObject`.
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

- `app_data.json` uses ISO 8601 dates, sorted keys, and atomic writes.
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
- `airline_destinations.json`: `[{ id, name, logoAssetName, destinationCountryCodes }]`. `AirlineRepository` rejects the whole file if IDs repeat, a field is empty, or a code is not three uppercase letters.
- `world-countries.geojson`: country outlines. The ISO3 code is read from the feature properties by `CountryMapView.Coordinator.extractISO3`.
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
- **Travels** (`MyTravelsTab`) has a segmented control for Been and Wishlist. Been uses `TravelSummaryCard`, `TravelCountryRow`, `CountryTripsSheet` and `TripEditorSheet`. Wishlist uses `WishlistSection`, `CountryPlansSheet` and `PlannedTripEditorSheet`.
- **Settings** (`SettingsView`, inside `UserProfileView.swift`) holds the search engine choice (`@AppStorage("searchEngine")`) and backup export/import.
- **Excel import** in My Visas is hidden. It is shown only when the localized string `MyVisas.ShowExcelImport` is `"true"`, and the button does nothing yet.

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
  "wishlist": [...]
}
```

- **Entry policies** store only the user's edits compared with the bundled file for that passport: overrides plus removed codes. On import they are applied to the bundled list of the importing app.
- **Dates**: calendar days (`startDate`, `expiryDate`, …) are `yyyy-MM-dd` strings in the device's time zone (`BackupDay`), so a trip on 1 April stays on 1 April in another time zone. Instants (`exportedAt`, `createdAt`) are ISO 8601 UTC with milliseconds (`BackupTimestamp`).
- **Media** (`BackupMedia`): `fileName`, informational `mimeType`, `byteCount`, `sha256`, base64 `data`. The type comes from the file extension. Allowed types and size limits live in `BackupMediaPolicy`: attachments are images or PDF up to 20 MB, the profile photo is an image up to 10 MB. The whole file may be up to 100 MB.
- **Optional sections**: a missing section means it was left out of the file. For example, `attachments: null` keeps the device's existing files for that visa, and `attachments: []` clears them.

### Compatibility rules

- Additive changes (new optional fields, new enum values) keep `schemaVersion`. Older apps ignore unknown keys. Unknown enum values fall back (`BackupValue.decode`), for example an unknown visit purpose becomes `other`.
- Breaking changes increase `schemaVersion`. Apps reject files with a newer version.
- `kind` is an open string type so unknown kinds still decode and can be rejected with a clear message. `visitShare` is reserved for the Friends feature.

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
6. Apply the profile.
7. Delete attachment folders of visas that no longer exist, delete the workspace, publish the summary and post `.userDataDidRestore`.

If a step fails, earlier steps are rolled back. If the rollback also fails, the workspace is kept and the error message shows its path so the files can be recovered by hand.

### Export

`UserDataBackup.make` builds the file from the current data. Files of unsupported type or size are left out and listed in `skippedFileNames`. The result is validated with the same rules as an import before it is offered for saving.

## Localization

- `Localizable.xcstrings` (source language English) with `zh-Hant` and `zh-Hans`. `whereCanIGo-InfoPlist.xcstrings` covers Info.plist strings.
- Most keys are the English text. Error messages and some import/export strings use identifier keys such as `backup.error.corrupted` or `import.reading`.
- Country names come from `Locale.localizedString(forRegionCode:)`. China has an override in `Localization.swift` so it shows 中國 / 中国 / China consistently.
- Enums have both `displayName` (English, older) and `localizedDisplayName`. Use `localizedDisplayName` in UI.

## Friends (planned)

Status: agreed design, implementation not started.

### Goal

Under Travels, add a third segment: **Been | Wishlist | Friends**. Users exchange a "travel card" file through the share sheet (AirDrop, Messages, or any app). The receiver can view the sender's Been and Wishlist offline. The app keeps running without a server.

### What this model means for users

- A friend's data is a snapshot from the last card received. New trips appear only after the friend shares again.
- Removing a friend deletes the data from this device only. The friend is not notified.
- Turning off sharing affects future cards only. Cards already sent stay with the people who received them.
- Adding is one-way: A can hold B's card while B has nothing from A.

UI wording should match this: "Share My Travel Card", "Add Friend", "Update Friend", "Last received …".

### Phases

| Phase | Scope |
|---|---|
| 1 | Card format and file type, signing (TOFU), sharing identity, Sharing Settings, share confirmation, Friends tab, read-only friend sheet, snapshot updates, "share back" prompt, friends in backup (optional) |
| 2 | Nearby two-way exchange with the Network framework; compare view (countries in common, "they've been where I want to go") |
| 3 (optional) | Automatic updates through CloudKit sharing |

### Card file

- File extension `.wcigcard`, declared as an exported UTType conforming to `public.json`, plus a document type so iOS offers to open it in the app. The app receives it through `onOpenURL`, copies it into its own storage, and removes the incoming copy.
- The backup importer and the card importer each reject the other's files.
- Envelope:

  ```json
  {
    "format": "wherecanigo.travelcard",
    "schemaVersion": 1,
    "publicKey": "<base64 P-256 public key>",
    "payload": "<base64 JSON bytes>",
    "signature": "<base64 ECDSA signature of the payload bytes>"
  }
  ```

  Signing the exact payload bytes avoids having to define a canonical JSON form.
- Payload: `sharerID`, `cardRevision`, `createdAt`, `displayName`, optional `photo`, optional `been`, optional `wishlist`, and a `shared` object listing which categories and fields were included.
- `cardRevision` is a counter that increases with every card the user creates. It decides which card is newer, since device clocks can be wrong.
- Same envelope versioning rules as the backup format.

### Identity and signing

- On first share, the app creates a P-256 signing key with CryptoKit and stores it in the Keychain with `kSecAttrSynchronizable`, so iCloud Keychain carries it to the user's other devices and through reinstalls.
- `sharerID` is the SHA-256 of the public key. There is one definition of "same person": holding the same private key.
- Trust on first use: the first card from a `sharerID` stores its public key. Later cards for that friend must verify against the stored key.
- Each friend shows a short safety code derived from the public key, so two people can compare codes in person.
- The full backup gets an option "Include my sharing identity" (off by default). When on, the private key is written in plain text, with a clear warning that anyone holding the file can send cards as this user. Password encryption can be added later.

### Receiving a card

1. Verify the envelope, the signature, and that `sharerID` matches the public key.
2. If `sharerID` is the user's own: show "This is your own card" and stop.
3. If `sharerID` is known:
   - Lower `cardRevision` than stored: reject as older.
   - Same revision: no change.
   - Higher: show what will change (name, counts added/removed), then replace the snapshot.
4. If `sharerID` is new but the display name matches an existing friend: explain that this may be the same person with a new identity (for example a new phone without a backup). Choices:
   - Add as a new friend (default).
   - Replace the existing friend and trust the new key. The user should compare safety codes first. The local nickname is kept.
   - Cancel.
5. Otherwise add a new friend.
6. After a successful add or update, offer "Share your card with <name>?" which opens the share confirmation.

### Snapshot rules

- A new card replaces the stored snapshot. Records the friend deleted disappear.
- A category marked as not shared in the new card clears the stored data for it and the UI shows "Not shared". The profile photo follows the same rule.
- "Not shared" and "Shared, no records" are separate states with separate messages.
- The local nickname set by the receiver is kept when the friend's display name changes.

### What can be shared

Sharing Settings (in Settings) store the defaults for the next card. They are all off at first.

| Group | Options |
|---|---|
| Profile | Display name (required, any nickname), Profile photo |
| Been | On/off; then Dates, Length of stay, Location, Purpose |
| Wishlist | On/off; then Planned dates, Estimated days, Location, Purpose |

With every field option off, a category shares country codes only. Notes, passport, entry policies, My Visas and visa attachments stay on the device; the settings page states this.

Before each share a confirmation sheet lists what this card contains, for example "Display name, photo, Been: 12 trips (countries and dates)". The user can change options for this card and choose "Remember as default".

### Validation of received cards

- Limits on file size, record counts and string lengths.
- Country codes must be three uppercase letters; dates must parse.
- The photo is re-encoded with `UserProfileStore.preparePhoto` (512 px JPEG). This also removes EXIF data such as GPS position. The same step runs when creating a card.

### Storage

- `friends.json` (separate from `app_data.json`) holds each friend: `sharerID`, public key, local nickname, last received time, last `cardRevision`, and the snapshot. Photos are stored next to it.
- Full backup gets an option "Include friends" (off by default). When on, friends are exported with their public keys so later cards still verify after a restore.
- Any future "delete all data" action must clear friends too.

### UI

- Friends segment: "Share My Travel Card", "Import Card", and a list of friend cards (avatar or default avatar, name, "Last received …"). Empty state: "Exchange travel cards with friends to see where they've been and want to go, offline. Cards don't update automatically."
- Tapping a friend opens a sheet (medium and large detents) with avatar, name, last received time, and a Been | Wishlist control showing a summary and the country list.
- Everything in the friend sheet is read-only. A friend's data stays separate from the user's own records, map colours, visa state and filters.
- Friend menu: set nickname, show safety code, remove friend.

### Code changes this needs

- `TravelStats(appState:)` and `WishlistStats` read from `AppState`. Add initializers that take an array of visits or trips plus the country list, and build read-only list views on top, so the friend sheet can reuse them.
- A new `FriendStore` (like `UserProfileStore`) for `friends.json`, and a `SharingIdentity` service for the Keychain key.
- The backup format gains optional `sharingIdentity` and `friends` sections. These are additive, so `schemaVersion` stays at 1.

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

`DataStore`, `UserProfileStore` and `AppState` accept custom file locations, so tests can use a temporary directory.

## Conventions

- Country codes are ISO 3166-1 alpha-3 everywhere except `Country.iso2`.
- Raw values written to disk (enums, keys) stay stable. Add a new case for a new meaning.
- New persisted fields decode with `decodeIfPresent` and a default.
- Save to disk first, then update published state.
- User-facing strings go through `String(localized:)` or SwiftUI `Text` so they appear in `Localizable.xcstrings`.
- Comments explain why something is done when it isn't obvious. Keep them short and factual.
