# Working in this repository

TileRate is Integrity Tile's installation estimator: an iPhone app the owner
uses on jobs to price tile work and produce a PDF estimate. It is a personal
build installed from Xcode, not an App Store app. GitHub:
`sjmilitello/tilerate`.

## Non-negotiables

**The bundle identifier is `app.estimateapp.estimator`, and it must stay that.**
The copy on the owner's iPhone carries it, and everything the app has saved
lives in that app's container: estimates in `Documents/SavedEstimates.json`,
rates, the current estimate and business details in `UserDefaults`. Building
under any other identifier installs a second, empty app beside the real one. The March 2026 rename set it to
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

Since 2026-09-25 every saved type reads each field on its own through the
`read`/`merge` helpers at the bottom of `EstimatorModels.swift`: `Rates`,
`EstimatorState`, `EstimateDocument`, `EstimateRoom`, `EstimateSection`,
`Measurements`, `Features`, `AdditionItem`, `TileChoice`, `TiledWall`,
`SavedEstimate` and `PartyInfo`.
**A new stored property needs a line in its type's `init(from:)` as well**, or
it is never loaded. A new saved *type* needs its own `init(from:)` before it
is saved anywhere.

`SavedEstimate` and `PartyInfo` keep fields with no default on purpose —
nothing should create an estimate without a title — so their fallbacks live in
`init(from:)` only. Do not add defaults to the properties to make decoding
easier.

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

## The Admin unlock

Admin opens with the phone's own Face ID, falling back to the phone passcode
(`LAContext` with `.deviceOwnerAuthentication`, in
`Sources/Admin/AdminAuthManager.swift`). There is no admin username or
password, so there is nothing to forget and nothing to recover. Do not bring
one back.

Until 2026-09-25 Admin had its own username and password, kept only in the
Keychain. A forgotten password locked the owner out of their own rates: the
"Forgot my password" email from `tilerate.com` could not change a password
that existed only on the phone, and the reset screen a `tilerate.com` link
opened accepted any code without checking it. All of that is gone —
`APIClient`, `AppState`, the reset screen, the recovery email and the
`tilerate.com` link registration. The app no longer talks to any server. The
old username and password are still in the phone's Keychain, unread.

A phone with no passcode set is let straight in, since there is nothing to
check against and refusing would lock the owner out. Cancelling the prompt
leaves Admin locked with an Unlock button.

On the simulator, enrol Face ID and answer the prompt with `xcrun simctl
spawn <sim UDID> notifyutil` — `-s com.apple.BiometricKit.enrollmentChanged 1`
then `-p com.apple.BiometricKit.enrollmentChanged` to enrol, and
`-p com.apple.BiometricKit_Sim.pearl.match` (or `.nomatch`) at the prompt.

## Where things live

| Concern | Place |
|---|---|
| Pricing — every charge on an estimate | `Sources/Pricing/Pricing.swift` |
| Rates, measurements, estimate model | `Sources/Models/EstimatorModels.swift` |
| Saving and loading | `Sources/Persistence/Store.swift` |
| Admin screen (rates, minimums, escalator, business details) and its Face ID unlock | `Sources/Admin/` |
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
the floor gets bigger. `FloorEscalatorTests` does this.

## Tile size steps (square and rectangle)

Owner's rule, from 2026-09-26: a tile of 288 sq in (12×24) pays no size
adder. Every whole 54 sq in its area is above *or* below 288 adds the size
adder once, per square foot installed. Part steps do not count (12×12 = 144 sq
in is 2.67 steps → 2; 24×48 = 1,152 is 16). Base size, step size and the adder
per step are Admin settings; the adder takes the same $/sqft or % unit as the
other size adders. Hexagon, arabesque, star/cross and mosaic keep their own
flat adders.

It replaced the Over/Under length × width escalators. A square or rectangle
with no width or length gets no size adder, and the app warns on the Size step
and the Summary. Code: `sizeSteps` in `Pricing.swift`.

## Separate tiles within one section

- **Shower floor and ceiling** (and a tub-surround ceiling) can each have their
  own tile (`showerFloorTile`, `ceilingTile`); nil means the main tile.
- **Shower and tub-surround walls**: "All walls the same tile" (the default,
  `walls` empty) prices one area in the main tile. Switched off, every wall is
  a `TiledWall` with a name, square feet and its own tile. The base rate and
  the area's minimum apply to all the walls together — splitting walls never
  adds minimums — and each wall adds its own adders. Walls with identical
  tiles must cost exactly what "all the same" costs; a test checks it.

A section still needs its main tile type, size and layout before it is priced.

## Tests

`TileRate Installation EstimatorTests` (Swift Testing) covers the escalator,
minimums, adders, size steps, separate tiles and walls, the estimate totals,
and loading data saved by earlier versions. Every test sets its own rates.
The Summary screen and the PDF both take their numbers from `computeTotals`,
so the totals tests cover both.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project "TileRate Installation Estimator.xcodeproj" -scheme "TileRate Installation Estimator" -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5" -only-testing:"TileRate Installation EstimatorTests"
```

The test target could not run from the March rename until 2026-09-26: its
`TEST_HOST` still named `Integrity Tile Estimator.app`.
