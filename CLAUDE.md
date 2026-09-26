# Working in this repository

TileRate is Integrity Tile's installation estimator: an iPhone app the owner
uses on jobs to price tile work and produce a PDF estimate. It is a personal
build installed from Xcode, not an App Store app. GitHub:
`sjmilitello/tilerate`.

## Non-negotiables

**The bundle identifier is `app.estimateapp.estimator`, and it must stay that.**
The copy on the owner's iPhone carries it, and everything the app has saved
lives in that app's container: estimates in `Documents/SavedEstimates.json`,
rates, the current estimate and business details in `UserDefaults`, the admin
login in the Keychain. Building under any other identifier installs a second,
empty app beside the real one. The March 2026 rename set it to
`app.tilerate.estimator` and nobody noticed until the app had to be
reinstalled; it was put back on 2026-09-25.

**Never delete the app from the phone to fix an install.** Deleting it deletes
its data. Install over it.

**A new field on a saved type must not wipe what is saved.** `Store` falls
back to the defaults whenever a saved value will not decode, and the
synthesized `Codable` refuses a value with any key missing — which is every
saved copy, the moment a field is added. Worst of all is the saved estimates
list: it holds the same rooms and sections, so one new section field made
every saved estimate unreadable, the list came up empty, and the next save
wrote that over the file.

Since 2026-09-25 `Rates`, `EstimatorState`, `EstimateDocument` and everything
inside them — `EstimateRoom`, `EstimateSection`, `Measurements`, `Features`,
`AdditionItem` — read each field on its own through the `read`/`merge`
helpers at the bottom of `EstimatorModels.swift`. **A new stored property
needs a line in its type's `init(from:)` as well**, or it is never loaded.
`SavedEstimate` and `PartyInfo` still use the synthesized decoder, and a
field added to either would empty the saved estimates list. Give them the same
treatment first.

Test a change to saving against the phone's real data, not a made-up copy:
`xcrun devicectl device copy from --domain-type appDataContainer
--domain-identifier app.estimateapp.estimator --source Library/Preferences`
fetches it read-only. Compare decoded values, never the JSON text — a
dictionary keyed by an enum is written in no fixed order.

**The defaults in `Rates` are not the owner's prices.** The real ones are
entered in the Admin screen and saved on the phone. Never reason about what a
customer is charged from the numbers in the source.

## Signing, and why the app stops opening

A build installed from Xcode is signed for one year. When that runs out iOS
keeps the icon and says the app is "no longer available". The current install
runs until **2027-09-26**; before then, rebuild and install over it.

Signing is automatic, team `6U8639A3FK`. If a build fails with "No Accounts",
Xcode has been signed out of the Apple ID — the owner signs in under
Xcode → Settings → Accounts; that step is theirs, never ours. Use the release
Xcode (`/Applications/Xcode.app`), not the beta: the beta was installed in
September 2026 and is the likeliest reason the account was signed out.

Building and installing from the command line:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project "TileRate Installation Estimator.xcodeproj" -scheme "TileRate Installation Estimator" -configuration Release -destination "id=<iPhone UDID>" -allowProvisioningUpdates build
```

```bash
xcrun devicectl device install app --device <iPhone UDID> "<derived data>/Build/Products/Release-iphoneos/TileRate Installation Estimator.app"
```

`xcrun devicectl list devices` gives the UDID.

## Where things live

| Concern | Place |
|---|---|
| Pricing — every charge on an estimate | `Sources/Pricing/Pricing.swift` |
| Rates, measurements, estimate model | `Sources/Models/EstimatorModels.swift` |
| Saving and loading | `Sources/Persistence/Store.swift` |
| Admin screen (rates, minimums, escalator, business details) | `Sources/Admin/` |
| PDF estimate | `Sources/PDF/` |
| Everything else in the UI | `Sources/Views/ContentView.swift` |

The scheme is **TileRate Installation Estimator**. The second scheme,
`Integrity Tile Estimator`, and `Integrity Tile Estimator 2.xcodeproj` are the
app's earlier names. `Backups/` holds two February 2026 snapshots and is
git-ignored.

## The floor escalator

Owner's rule: a floor of 50 sq ft or less is the floor minimum ($1,500). From
51 to 99 sq ft it is the minimum plus the escalator rate ($14) for each foot
over 50. From 100 sq ft the floor rate takes over. Tile type, size and layout
adders go on top in every case.

In code: the greater of `base × sqft` and `minimum + escalator × (feet over the
lower threshold)`, the escalator counting only inside the window. The
thresholds, the rate and the minimum are all Admin settings.

The March 2026 restructure broke this by adding the escalator to *every*
square foot and starting it at exactly 50: a 60 sq ft floor came to $2,340
instead of $1,640, and 99 sq ft cost more than 100. It was restored on
2026-09-25 from the August 2025 version. When pricing changes, check a few
floor sizes either side of each threshold — the price should never fall as
the floor gets bigger.
