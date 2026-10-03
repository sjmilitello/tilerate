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
| Radiant heat systems, and their Admin editor | `Sources/Models/HeatingSystems.swift`, `Sources/Views/HeatingSystemEditor.swift` |
| Rates, measurements, estimate model | `Sources/Models/EstimatorModels.swift` |
| Saving and loading | `Sources/Persistence/Store.swift` |
| Admin screen (rates, minimums, escalator, business details) and its Face ID unlock | `Sources/Admin/` |
| PDF estimate | `Sources/PDF/` |
| Everything else in the UI | `Sources/Views/ContentView.swift` |

`Sources/Views` is a synchronized folder in the Xcode project: a new file
there is picked up by itself. `Sources/Models`, `Pricing`, `Persistence`,
`Admin` and `PDF` are not — a new file in one of them must also be added to
`project.pbxproj` (file reference, group, and the target's Sources phase), or
the build won't see it.

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

## Tile size adder (square and rectangle)

Owner's rule, from 2026-09-27: the price per square foot is based on the
standard 12×24 tile (288 sq in), which pays no size adder. The further a
tile's size is from it, in either direction, the more it adds: **$2.50 per sq
ft for every doubling or halving of the tile's area**, part doublings in
proportion. So 24×48 (4× the area, 2 doublings) adds $5.00, 24×24 adds $2.50,
48×48 adds $7.50, 12×12 adds $2.50 and 3×12 (1/8 the area, 3 halvings) adds
$7.50. In code: `|log2(area / standard area)| × adder per doubling`
(`sizeDoublings` in `Pricing.swift`).

Why doublings rather than square inches: tile sizes grow by multiplying
(6×6, 12×12, 24×24, 48×48), and each jump makes the job about as much harder
as the last. Counting square inches made large slabs cost far too much and
tiny tiles too little. The owner's usual figures were $5 for both 24×48 and
3×12, which no single linear rule can give; they chose one constant of $2.50.

The standard tile size and the adder are Admin settings; the adder takes the
same $/sqft or % unit as the other size adders. From 2026-09-29 bigger and
smaller tiles have separate adders: `sizeAdderPerDoubling` for tiles bigger
than the standard, `sizeAdderPerHalving` for smaller ones (`sizeAdderAmount`).
Rates saved before then have no halving adder; it is read as the saved
doubling adder, so prices don't move until the owner sets it.
Hexagon, arabesque, star/cross and mosaic keep their own flat adders. A
square or rectangle with no width or length gets no size adder, and both
designs warn about it.

History: Over/Under length × width escalators until 2026-09-26, then whole
54 sq in steps from 288 for a day, then doublings.

## Materials and mosaic styles

Materials added 2026-09-27: Granite, Quartzite, Cement, Terracotta, Zellige,
each with its own adder (starting at $0). When the shape is Mosaic, a mosaic
style can be chosen (17 styles, `MosaicStyle`); its adder in Admin goes on top
of the Mosaic adder, and the estimate names it ("Porcelain Penny Round Mosaic
in …"). For Square and Rectangular mosaics the width and length entered are
the piece size and show on the estimate; the doubling size adder does not
apply to mosaics. New enum cases are safe for saved data: rates tables merge,
so a new case starts at its default.

## Electric radiant heat

From 2026-10-03 a Floor area or a shower floor can have electric radiant heat.
It is priced from a **heating system** the owner sets up in Admin
(`HeatingSystem` in `Sources/Models/HeatingSystems.swift`), not built in, so
another brand can be priced the same way. A system has parts, each with a
quantity rule: covers the floor (floor sq ft ÷ coverage, rounded up), sized to
the heated area (heated sq ft × amount per sq ft, rounded up to the next
stocked size from a price table; size lists can be limited by heated area,
e.g. 120V up to 100 sq ft, and long runs split evenly across the fewest
pieces), one per sized item (a thermostat per wire) or fixed per job.

Materials = parts at cost × (1 + markup %). Owner's rule: markup 60% on cost
(cost × 1.6), entered as a percentage with the matching margin shown.
Installation = floor sq ft × $8, minimum $500 — the minimum applies to labor
only. Each system can instead charge installation on the heated area only
(`laborOnHeatedAreaOnly`); the owner charges the whole floor. Mats are based
on the whole floor too, wire on the heated area.

On the estimate the kit is one taxable material line named after the
system ("Strata Heat Electric Radiant Heat Kit W/ LCD Smart WiFi Thermostat")
and installation a separate labor line; both names are editable. They are
added to the area's lines in `sectionPrice`, so the Summary, the Review screen
and the PDF all include them, and the kit counts toward tax and shipping.

Why a price table and not a formula: the owner wants 1.6 as the *minimum*
markup on every item. Formulas fitted to the wire prices (best fit, base +
rate, or a minimum + rate) all either undercharged some sizes or padded them
by $13–$170 on average; the stocked-size table prices each wire at its real
cost. Expected quirk, accepted by the owner: at the 120V/240V switch the
price falls — 100 sq ft heated needs the 398 LF 120V wire ($527.33 cost),
101 sq ft the 415 LF 240V wire ($458.42).

The owner's Strata Heat system (their wire price list, October 2026) is
`HeatingSystem.ownersStrataHeat`, the default for rates saved before this.
Before an App Store release the default should become an empty list, so other
users enter their own brand and prices.

The Admin editor is `Sources/Views/HeatingSystemEditor.swift`: systems,
their parts and each sized part's price lists, with "Delete this system".
The part and size-list screens were not exercised on the simulator (scrolling
inside the Admin sheet is unreliable there); check them on the phone after
changing them. `RadiantHeatTests` covers the pricing, including the owner's
example (60 sq ft floor, 50 heated: $1,043.82 kit, $500 installation).

## Multi-tile layouts

From 2026-09-28 a Multi-Tile layout lists its tiles, each with its own shape
and size (`TilePiece`: `multiTilePieces` on a section, `pieces` on a
`TileChoice`). Owner's rule: a multi-tile layout pays **no size adder**, only
the Multi-Tile layout adder (plus the material adder), and missing sizes raise
no warning. The estimate lists the pieces: "Porcelain Tile in Multi-Tile
pattern (12×24, 24×24, 6×6 Hexagon)". In the new design the Tile step goes
Material, Layout (with Mosaic as a layout choice, which leads to mosaic style
and size), then shape and size; the classic design keeps its order.

## Bands, borders and inlays

From 2026-09-28 an area can have any number of bands, borders and inlays
(`DecorativeItem`), each with an optional name, its own tile and its own rate
in Admin: bands and borders per linear foot (`bandRatePerLinFt`,
`borderRatePerLinFt`), inlays per square foot (`mosaicInlayRate`, the old
mosaic inlay rate kept under its name so the saved price carries over). The
tile describes the item on the estimate; it doesn't change its price. A new
item in a shower starts with the shower floor's tile when that is a mosaic,
otherwise with the area's main tile.

In a shower or tub surround each item can also have locations
(`decorativeLocationOptions`): the walls (Back, Left and Right when all walls
are the same, otherwise each wall, stored by id so renaming keeps the link),
the ceiling when tiled and a shower's floor when measured. Bands and borders
take several, an inlay one. Locations appear in the estimate wording
("… on Back Wall & Left Wall"), never in the price. The estimate wording
leaves out linear and square feet.

They replaced one "mosaic band, border or inlay" switch with a square-foot
figure. An estimate saved with that switch on converts, when read, into one
inlay of the same square feet, so its price is unchanged.

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

## Features on floors

Owner's rule, from 2026-09-26: shelves, niches, footrests and benches don't go
on a floor. On a Floor section the Features step greys them out, the price
never charges them — even if a number was left in one — and the estimate
description leaves them out. The decorative mosaic band stays available on
floors. `floorsNeverChargeShelvesNichesFootrestsOrBenches` checks the price.

## Tests

`TileRate Installation EstimatorTests` (Swift Testing) covers the escalator,
minimums, adders, the size adder, separate tiles and walls, the estimate totals,
and loading data saved by earlier versions. Every test sets its own rates.
The Summary screen and the PDF both take their numbers from `computeTotals`,
so the totals tests cover both.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project "TileRate Installation Estimator.xcodeproj" -scheme "TileRate Installation Estimator" -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5" -only-testing:"TileRate Installation EstimatorTests"
```

The test target could not run from the March rename until 2026-09-26: its
`TEST_HOST` still named `Integrity Tile Estimator.app`.
