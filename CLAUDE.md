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

Since 2026-10-05 `SavedEstimatesStore` (one shared instance, `.shared`, for
both designs) also survives a file it can't read. Estimates are decoded one
at a time, so a bad one doesn't lose the rest. If any of the file can't be
read, a copy of it as it was goes into `Documents/Data Backups`
("SavedEstimates unreadable <time>.json", never overwritten), the saved
estimates list shows a warning, and only then may a save write over it; if
the copy can't be made, nothing is saved. Before the first save of each day
the file is copied there too, and so are the rates (`DataBackups.daily`, the
newest 14 days kept). Rates, the current estimate and state that won't decode
are copied there before the defaults replace them. `SavedEstimatesSafetyTests`
covers this.

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

## Saved estimates open as they were sent

From 2026-10-05 (roadmap Phase 1) a saved estimate keeps the rates it was
priced with (`SavedEstimate.rates`) and its grand total (`total`, shown in the
saved lists). Opening one (`Store.open`) prices the estimate being worked on
with those rates (`Store.opened`, kept across launches) until "Convert to
current pricing" (`convertToCurrentPricing`), which first shows the saved and
the current total. Everything that prices the estimate uses
`store.pricingRates` — never `store.rates`, which is what Admin edits; the
price list menus still offer the current price list. `OpenedPricingBanner`
says which is in force, in both designs. Estimates saved before then have no
rates: they open at the current rates with a note, and saving one again keeps
today's rates with it. Starting a new estimate clears `opened`.
`QuoteHistoryTests` covers this. Still to come in Phase 1's spirit: wording
and PDF template choice saved with the estimate (Phases 3 and 4).

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

iOS keeps a picture of the launch screen and reuses it while the build
number (`CURRENT_PROJECT_VERSION`) stays the same. After changing the launch
screen or its logo (`TileRateLaunch.storyboard`, `LaunchLogo`), raise the
build number, or the phone keeps showing the old one (2026-10-17: it went
from 1 to 2 for the new icon).

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
| The pricing scheme engine (roadmap Phase 2) | `Sources/Pricing/PricingScheme.swift` |
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

## The pricing scheme engine (roadmap Phase 2)

From 2026-10-06 there are two ways to price an area's tile work.
`legacySummary` is the pricing written area by area in code. `schemeSummary`
prices from a `PricingScheme`: per area, its surfaces (label, which square
feet, which tile, and a rule — rate with minimum, or the escalator window),
whether features are charged, the ceiling, the tile adders, feature and
decorative prices. Today the scheme is built from the Admin rates
(`PricingScheme(rates:)`); Phase 5 will let users build their own. Radiant
heat and the price list are untouched.

`computeSummary` is what everything calls. With Admin → Pricing engine
switched off (the default) it returns `legacySummary`. Switched on, it prices
both ways and uses the scheme's result only when it matches line for line
(`PricingEngine.same`); otherwise it uses today's price and records the
difference, shown in Admin. The old path is retired only after the owner has
used the switch on real jobs with no differences.

`PricingGoldenTests` holds both engines to 1,380 areas recorded on 2026-10-06
(`PricingCases.swift`, `PricingGolden.swift`): every line, label and amount.
Never regenerate the recording to make a test pass — a difference is a
change in what customers pay. Add cases under new names instead. Both
engines also matched every area of the phone's saved estimates at the
owner's real rates. A change to pricing must be made in both engines while
both exist.

## Area pricing rules (roadmap Phase 5)

From 2026-10-07 Admin → Area pricing replaces the base rate, minimum and
escalator sections: each surface (floor, wall, tub surround, shower walls,
shower floor, backsplash, fireplace, ceiling) has a rule — rate with a
minimum, or a minimum with an escalator window — with example prices, a
warning when a bigger area would cost less (`firstPriceDrop`), and Suggest
an escalator (`suggestedEscalator`: (rate × first sq ft after the window −
minimum) ÷ window width, rounded down to the cent). Read rules with
`Rates.rule(for:)`, write with `setRule(_:for:)`: the usual kind of rule
(escalator for floors, rate for the rest) is stored in the old rate fields
exactly as before; only a different kind goes into `Rates.surfaceRules`. An
area with such a rule is priced by the scheme engine alone (`computeSummary`),
since today's code can't. Walls with their own tiles can take an escalator:
the rule on all the walls together, each wall's adders on top.
`SurfaceRuleTests` covers it, including the owner's floor ($22, $1,500,
$14 from 50 to 99: the suggestion gives exactly $14) and a ceiling with
$600 minimum and $25/sq ft from 31 (suggested $10.93).

## Room scanning with LiDAR

From 2026-10-07 (new design, Measure step) a room can be scanned with the
iPhone's LiDAR (Apple's RoomPlan; `RoomScanner.isAvailable`, the owner's
16 Pro Max has it). One scan belongs to the room (`EstimateRoom.scan`) and
every area in the room measures from it; "Scan just this area" keeps a scan
on the area instead (`EstimateSection.roomScan`, e.g. from inside a shower).
`ScannedRoom(captured:)` converts RoomPlan's result to feet: walls (pieces
the scanner split are merged back, `mergingStraightRuns`; each running with
the room on its right; lettered as below), doors, windows and
openings (wall, width, height, height off the floor, position along the
wall), the floor outline and area, and the bathtub's outline.

Each area keeps its own choices (`EstimateSection.scanTakeoff`,
`AreaTakeoff`): pieces of walls (a stretch along one wall, from/to in feet
from the wall's start, and a tile height in inches — so a shower wall that
continues into the room is two pieces, one per area), the openings ticked to
come off (owner's call: nothing comes off unless ticked; only the part of an
opening inside a piece), and the floor (scanned floor, see "A Floor area on a
scanned room" below, or width × depth for a shower floor) and ceiling.
A shower floor is drawn on the plan (`FloorSource.drawn`, `FloorRect`:
a corner, two side directions, width and depth), placed in the corner its
walls make (`suggestedFloorRect`) and dragged to size: green handles on the
plan for width, depth and moving, sides snapping to the sixteenth and to walls
(owner asked 2026-10-07: the whole room floor was being used). Other areas
see it faintly in orange. The floor has one move handle in its middle; tapping it lights the outline
and gives each edge a grip (the opposite edge stays put), with the size,
Reset and Done in a strip under the plan. The plan is turned on screen by
`ScannedRoom.squaringAngle` so walls run square to the screen — RoomPlan's
north is wherever the phone pointed when the scan began; only the drawing
turns, never the saved points. Scan controls sit at the top of the screen so
RoomPlan's 3D model at the bottom stays visible. While scanning, the screen stays awake at full
brightness. Zooming the camera out isn't possible: RoomPlan always shows the
1× camera and apps can't change it.
Walls that aren't built yet (knee walls, owner asked 2026-10-07) are drawn
on the plan from the editor's menu: drag from start to end; the start snaps
onto a wall, the line straightens to the room's square directions, its
length rounds to the sixteenth and stops on a wall within 1½″
(`snappedToWall`, `plannedEnd`). A planned wall (`Wall.planned`,
`thicknessIn`, starting from `Rates.kneeWallThicknessIn`, 4½″, Admin → Knee
walls) is dashed and as thick as it will be; it is saved with the scan, so
every area sees it. It has two faces (`Piece.face`, named by the wall each
looks toward). A planned wall as high as the ceiling is a full wall ("New
wall F", `isKneeWall` false), with no cap. A wall drawn in a shower along an open
side of its floor (roughly parallel, within 2′) snaps onto the curb line
(`snappedNewWall`, `newWallLines`; owner asked 2026-10-07). Tapping the curb
on the plan holds it (lit green, owner's call 2026-10-10): drag to move it
in or out — the floor's open edge follows (the curb's inside face is the
floor's edge), a framed bench out to the curb follows it
(`benchesFollowFloor`), and it catches with its outside face flush with a
side wall's end (`curbCatch`), with Catch off and nudge arrows as usual.
Add a Wall → Full Wall or Half Wall, then tap the curb: the wall goes on
the curb filling the opening — along the curb's middle, as thick as the
curb, and out to the curb's outside corner where another curb meets it
(`AreaTakeoff.wallOnCurb`, owner 2026-10-13; `WallOnCurbTests`) — with no door (`closeSide`; most showers have
no header — Add door is there for one); drag its end in and the curb fills
the gap with its jambs. Its first face looks into the shower and is
tiled. Adding a wall where a drawn-in one already lies
uses that one (`plannedWall(along:)`), so two never stack and hide each
other. ⋯ → "Delete a wall I added" lists them all; in a Floor area they
can be selected and deleted too. Deleting one re-measures the room's other
areas that tiled it. Cancel asks before discarding changes; "Use these
measurements" keeps them and fills in the area.

Walls are added from the editor's **Add a Wall** button (Full Wall, Half
Wall, Framed Bench): tap the curb to put it on the shower opening, or drag to
draw it. A full wall on the opening gets a door. "Knee wall" is called
**half wall** everywhere the owner sees it (code still says `kneeWall`). A
planned wall within 3″ of the ceiling is full (`isKneeWall`) — scans give
odd ceilings like 8′ 0.7″, and a ½″ allowance made new full walls half walls
with no door (fixed 2026-10-07).

Benches, niches, windows and corner pieces (owner's rules, 2026-10-07) are
`AreaTakeoff.items` (`Item`), placed from the buttons under a shower wall
(Add door / window / niche / corner shelf, seat or footrest / floating
bench) or Add a Wall → Framed Bench (then tap the wall it's against), and
dragged on the wall face-on. Starting sizes are Admin settings
(`Rates.scanDefaults`, `ScanItemDefaults`): benches 20″ high and 15″ deep;
niche 13″ × 24″, 48″ up; window 36″ × 24″, 48″ up; corner shelf 9″ at 48″
(another in the same corner 12″ higher; the Add corner menu has a section per corner, named by the wall meeting it), footrest 10″ at 18″, seat 18″ at
20″. A framed bench's footprint (length × depth, where it stands on the
drawn shower floor) comes off the shower floor's square feet, and so off
everything priced from them (owner, 2026-10-15; `floorSqft`); a floating
bench takes nothing off. A bench runs along the shower floor's side against its wall
(`benchSpan`): wall to wall, or a framed bench to flush with the outside of
the curb (the curb stone's width past the floor); a floating bench needs a
wall at each end and has no front. Tile benches add their top (and a framed
bench's front) to the walls' square feet; stone tops and fronts are
"Stone bench top/front" lines. A niche is tile, stone all around (top,
sides, base shelf, dividers) or stone shelves only (base shelf, dividers),
totalled as one; a window is tile or stone all around and never tiled
over. Corner shelves, seats and footrests are always stone, per unit.

"Use these measurements" with items placed (`itemsPlaced`) overrides the
area's counts (`placedFeatures`): niches, windows, shelves, footrests,
seats (`Features.seats`, `Rates.unitSeat`) and benches, and records each
bench, niche and window with its size (`Features.sized`). Both pricing
engines price features through one function, `featureLines`: each sized
item is the higher of its minimum (`unitBench`, `unitNiche`, `unitWindow`)
and its size — a bench's length × `benchPerLinFt`, a stone niche's or
window's stone at its stone rate (tile: the minimum); the rest of a count at
the per-unit price, exactly as before.

A niche in its own tile (`Item.tile`, owner's call 2026-10-08) adds that
tile's adders on the tile inside it — the back, and the sides, top and sill
that aren't stone, 3½″ deep (`AreaTakeoff.nicheTileSqft`, `nicheDepthIn`) —
at the area's wall rate, as its own line "Niche 13″ × 24″ tile adders @ …"
(`SizedFeature.tile`/`tileSqft`, priced in `featureLines` for both engines),
and the estimate names it: "Niche in 2×2 Glass Mosaic …" (other niches as
before). Its base price (the minimum, or its stone) is unchanged.

Every stone piece (`StoneItem`: curb, cap & header, jambs, bench top, bench
front, niche, window) has a `StoneRate` in Admin → Stone pieces
(`Rates.stoneRates`, `stoneRate(_:)`/`setStoneRate`; curb, cap and jamb fall
back to their old per-foot fields): per linear foot, a usual width, and —
once a width is set — per square foot instead (length × width). The floor's open sides
(`openSides`) are each edge less the stretches walls run along, so a knee
wall across part of the front leaves the rest as the entry, with its curb
and jambs. A selected planned wall has a move
handle in its middle (`movePlannedWall`): whole inches, its line snapping
within 1½″ to those lines and to other walls' ends, an end onto a wall it
nearly touches. Its ends drag on the plan; height, thickness and
length can be typed; it can be deleted. Its tile follows a dragged end
both ways, worked out from the wall as the drag began
(`Array<Piece>.followingEnd`; owner, 2026-10-14: tile was only ever
clipped, so a half wall shortened on the way kept a 6″ strip). Dragging a wall drawn in's tile back from one of its ends (on the
face-on view) and letting go moves that end of the wall in too, opening
it there — tile, built-ins and doors keep their places and the curb fills
the gap — unless that end is on a scanned wall (`shortenIfTileLeftAnEnd`,
`shortenPlanned`; owner, 2026-10-15: the half wall stayed full length,
part tile and part bare, in 3-D). In 3-D a wall drawn in's free ends are tiled in the tile of the
area that tiles it (owner, 2026-10-15: they showed bare grey); stone on an
end draws in front. A wall added
is tiled on its first side under Tile walls and Edit walls alike
(`tileNewWall`), and a wall chosen under Edit walls has **Tile this wall** /
**Change its tile**, which switches to Tile walls with it chosen (owner,
2026-10-14: a half wall added under Edit walls had no tile and no way to
add it there). A tap just beside a wall drawn in or a scanned divider — off its
drawn thickness — chooses that side and tiles it if it has no tile yet, on
the plan and in 3-D (`sideTapped`, `tapWall(_:side:)`; owner, 2026-10-14:
"I should be able to tile both sides by tapping"); a tap on the wall
itself chooses it as before, and the Side switch stays.

**Stone pieces by part (owner, 2026-10-13).** Admin → Stone pieces lists
groups — Curb (Top, Inside, Outside), Wall (Cap, Jambs), Door (Jambs,
Header), Window (Sill, Jambs, Header), Niche (Back, Base shelf, Jambs,
Header, Divider shelves — the back added 2026-10-13, a panel priced by
the niche's width × height when by the square foot, `isPanel`,
`TrimPiece.areaSqft`; tile until chosen), Ceiling (Header), Wall to wall floating bench (Top),
Framed bench (Top, Front, Sides) — bench parts are panels too (owner,
2026-10-14: a bench is dragged every way, so a usual width makes no sense):
by the square foot they're the bench as placed, top length × depth, front
length × height, outside end depth × height, with no width to set — each opening to its parts, each with its
own install price (`StonePart`, `StoneGroup`, `Rates.stoneRate(_: StonePart)`;
per linear foot, or per square foot once a width is set). A part with no
price of its own uses the one it was part of before (`StonePart.legacy`),
so prices carry over. Corner shelf, footrest and bench sit under Stone
pieces too, with their price each and size (the same `unitShelf` etc.).
The stone prices are to install it; **Stone material** (per sq ft of stone,
each piece's length × its width) is added into each line's price, or —
switched on — listed as one "Stone pieces" materials line
(`stoneMaterialPerSqft`, `stoneMaterialSeparate`). On the estimate: one line
per group ("Stone curb", "Stone wall trim", "Stone door trim", "Stone
window trim", "Stone niche", "Stone ceiling header", "Stone floating
bench", "Stone framed bench"; `stoneLineID(_:StoneGroup)`): by length at
the price when every piece in it has one price, else the total as one. A
niche or window is its minimum (Features) **plus** its stone parts on its
group's line (it used to be the higher of the two). On the model the
Extras panel lists the groups ("Tile", "All stone", "2 of 3 stone"), each
opening to its pieces; a niche's or window's panel has a Tile/Stone switch
per part (`partStone`/`setPartStone`, keys `niche:<id>:shelf` etc.; an
item saved before starts from its old choice). A niche always lists
Divider shelves; switching it to stone with none yet adds one, and the
Extras panel's Niche group has a divider shelves stepper per niche (owner,
2026-10-14). Each niche or window piece is named by what it is and its
own size — "Niche on wall F: jambs 2 × 24″", "…: divider shelves 3 × 13″"
— not the niche's size on every row. `StonePartPricingTests`. The room's own doors, windows and openings
(scanned, or added under Edit walls) in a wall an area tiles, where its tile
meets them, have stone parts too (owner, 2026-10-16; `stoneOpenings`): a
window's sill, jambs and header (keys `win:<id>:sill|jambs|header`, the
Window group), a door's or opening's left and right jamb and header
(`jamb:<id>:left|right`, `header:<id>`, the Door group; no header when it
reaches the ceiling). Any area, not only showers; drawn in 3-D as stone on
the opening's sides, underside and (a window's) sill. `RoomOpeningStoneTests`.

**None, outside the shower** (owner, 2026-10-17): a piece outside the
shower — the curb's outside face (and a shower door's), a wall's end that
faces out past the floor and curb (`endFacesOut`), e.g. a full wall drawn
in on a corner shower's curb ("Wall E end", `wallEnd:<id>:start|end`, priced
and lined as a wall jamb) or a half wall's end out there — can be **None**
(finished by someone else: painted drywall, glass) as well as Tile or Stone,
and starts as None. Pieces inside the shower stay Tile or Stone.
`TrimChoice.finish` (`TrimFinish`: tile, stone, none; nil = saved before, `stone`
says), `TrimPiece.finish`/`noneAllowed`. None adds nothing to the price or the
cutlist and draws as painted wall in 3-D (passed in the stone key set as
"none#<key>", `drawnFinishKeys`). `NoneOutsideTheShowerTests`.

**Stone cutlist** (owner, 2026-10-16; the format is `docs/stone-cutlist-format.md`,
a public contract FabSpecPro owns). Every stone choice is measured as the
pieces to order (`CutPiece`, `AreaTakeoff.cutPieces`, in
`RoomScan/StoneCutlist.swift`): ordered long and trimmed at fabrication —
corner curb tops on through the other curb to the far edge of its top,
outside faces past the other face's thickness, jambs full height, headers,
sills and niche shelves full width, a stone niche back's thickness off the
niche's other pieces, the half wall cap ¾″ past each free end, the framed
bench top the bench plus the front's (and end's) thickness (¾″ if tile) plus
the overhang (Admin → Stone pieces → Framed bench, `benchTopOverhangIn`).
Widths are Admin's (`StoneRate.widthIn`), else the model's; each part has a
thickness (`StoneRate.thickness`, 3 cm, a niche back 2 cm). `trimPieces`
measures from them (`TrimPiece.cuts`, `cutSqft`, pass `prices:`), so stone
prices follow the same sizes. `cutlist` names them: no sizes, letters by the
order added per area when there's more than one ("Niche A Jambs", "Curb B
Top"), a matching left and right as one row ("Entry Jambs", Qty 2).
An estimate has a permanent id (`EstimateDocument.id`; saved before: its
first room's, so it's the same on every read), sent as `estimate.id` so
FabSpecPro knows a cutlist sent again (owner, 2026-10-17 — the estimate
number changes as PDFs are made). Edges: the FabSpecPro file says "standard" —
every edge finished with the shop's standard edge, no profile; FabSpecPro
gives it the shop's Default edge finish (eased, pencil and polished mean the
same in shops; owner, 2026-10-17). The spreadsheet says "All Edges Finished". Area
prefixes use a plain hyphen. `EstimateIDTests`.
The review screen's **Stone cutlist** card (`StoneCutlistCard`,
`StoneCutlistExport`) has **Send to FabSpecPro** — opens
`fabspecpro://import?cutlist=<compact JSON, zlib, base64url>&z=1`; when nothing opens it, a
message offers the `.stonecutlist` file or the spreadsheet — and
**Spreadsheet** (CSV, free). No PDF: a drawing is FabSpecPro's. Nothing
ties the apps to one developer account (no App Group), so either can be sold.
`StoneCutlistTests`.

Shower entry trim (owner's rules, 2026-10-07): curbs, wall caps, jambs and
headers (`TrimPiece`, from `AreaTakeoff.trimPieces`) are tile by default —
part of the wall square feet, no adder — and each can be switched to stone
(`AreaTakeoff.trim`, `TrimChoice`, with a length typed over the measured
one). Stone goes on one estimate line per kind, per linear foot at Admin's
prices: "Stone curb" (`stoneCurbPerLinFt`), "Stone jambs" — every jamb on
one line (`stoneJambPerLinFt`) — and the wall cap line (`stoneCapPerLinFt`),
which also takes headers (owner's call) and is named "Stone wall cap",
"Stone header" or "Stone wall cap & header". The lines have fixed ids per
area and kind (`stoneLineID`), so measuring again keeps a price changed on
the estimate. For a shower with its floor drawn: the curb runs along the
floor's open sides (`openSides`); a jamb at each end of the entry runs from the curb to the
top of the tile against a full wall, or splits at a knee wall into a lower
(curb to cap) and an upper jamb (cap to the top of the tile); each knee wall
gets a cap. The top of the tile is the area's tallest piece on a scanned
wall, else the ceiling. Left and right are as you stand outside facing in.
Curb height: Admin (4″), per shower in the editor.
The curb stops at a framed bench (owner, 2026-10-09): it runs only where
no framed bench stands on the open side (`curbSides`, used for the curb's
length, the plan and 3-D), and such a bench gets an "outside end" stone
piece (`benchSide:<id>`, its depth long, priced and lined as the bench
front), and the jamb on its side splits at the bench top: a lower jamb
from the curb to the bench top and an upper from there to the top of the
tile. The curb's inside and outside faces below its top are stone
pieces too (`curb:inside`, `curb:outside`, and per door
`curb:<id>:inside/outside`), priced and lined as the curb. In 3-D each of
the curb's top and faces and the bench's top, front and end shows tile or
stone on its own. Stone entry jambs show in 3-D too (owner, 2026-10-13:
they didn't): the strip of wall face above each end of the curb, as wide
as the curb, on the face of the wall there (`AreaTakeoff.jambFaces`, keyed
as `trimPieces` keys them; also from the room's other areas; one-sided
like the walls). A shower door's jambs (the sides of the doorway, as deep
as the wall, curb to header) and its header (the underside of the top of
the doorway, facing down — like a curb top at the top) show too
(`doorAndHeaderFaces`, `HeaderStrip`).

**Ceiling headers** (owner, 2026-10-13: installed over the curb and/or wall
caps of open showers when the ceiling is tiled, to frame the ceiling tile,
so a glass panel can later sit between): every open shower offers
"Ceiling header (over the curb)" (`header:ceiling`, the curb's length) and
one over each half wall's cap (`header:ceiling:<id>`). Tile means none;
stone is priced and lined as a door header (the cap & header price, "Stone
header"/"Stone wall cap & header"). Drawn as a strip on the ceiling over
the curb's middle (or the half wall), 4½″ wide. **Dropped headers (soffits)** (owner's
answers, 2026-10-13): Add a Wall → Header (drop from ceiling) → over the
curb, a half wall or a doorway (`AreaTakeoff.soffits`, `Soffit`: `over` is
"curb", "cap:<wall id>" or "door:<opening id>", `dropIn`, 6″ to start).
Snapped over it: along the curb's middle — every curb run, so a corner
shower's is L-shaped — or the half wall or the doorway, 4½″ wide
(`soffitLines`). Its drop is set under Measure → Headers (chips or typed,
Set when done). Tiled like a curb on all three sides — both faces and the
underside add to the walls (`soffitTileSqft`); the underside can be stone
(`soffit:<id>`, the Ceiling → Header part), and replaces the flat ceiling
header over the same thing; the faces are tile (stone choices later, maybe).
Jambs below stop at its underside (`entryHeaderBottom`, and per door), so
glass can sit between it and the curb. Drawn in 3-D as a box down from the
ceiling (`soffitBoxes`). RoomPlan doesn't find soffits, so a scanned one
has to be added this way. `SoffitTests`.

A half wall at the entry (owner's rules, 2026-10-13), told apart by
whether it carries on past the entry's corner (`meetsFace`): a corner
shower with a half wall put on one curb (it runs the curb's width past the
corner) has the entry meet its **face** — the lower jamb is the strip of its
face above the curb's end, and its free end, flush with the curb's outside,
is a stone piece of its own, **Half wall X end** (`kneeEnd:<id>:start|end`),
floor to cap, priced and lined as a jamb. A half wall ending at the corner
(a three-wall shower with one partway along the curb) has the entry meet
its **end** — the lower jamb is its end face. Either way the upper jamb is
on the wall the half wall is attached to, above the cap, as wide as the
half wall. `HalfWallJambTests`. A knee wall outside a
shower: a cap and a jamb on each exposed end.

A shower door (`OpeningKind.showerDoor`, saved with the scan) goes in any
full wall a shower tiles — "Add a full wall with a shower door" draws a new
full-height wall with one in its middle, or Door on a wall's panel. It
starts at Admin's size (30″ × 80″, `showerDoorWidthIn`, `showerDoorHeightIn`)
and is dragged on the wall face-on (sides, top, or along) or typed. Its
distances are named by the wall each end meets ("To wall B"), never left
or right: the face-on drawing is from one side of the wall (it says which,
"Seen from inside the shower" / "the side facing wall C"), so left and right
swap for someone on the other side (owner placed a door 20″ "right" and got
the other end, 2026-10-07). A bench, seat or footrest reaching into the
doorway is flagged under the door (`doorClashes`). It is
never tiled — always taken off, no tick — and gives a curb across it, a left
and right jamb from the curb to the header (to the top of the tile with no
header), and a header as wide as the door. Dragged to the ceiling, it has no
header (`hasHeader`). Pricing is per linear foot only; wall thickness and
overhangs don't change it.
`AreaTakeoff.apply` fills in the area's measurements; a shower or tub with a
tile per wall gets a wall each named "Wall A"… keeping its tile.

A **2D / 3D** switch on the plan (owner asked 2026-10-07) shows the room in
3-D (`Room3DView.swift`, SceneKit), built from the scan and the areas'
choices — not Apple's own model, so walls drawn in, doors, items and tile
all show: walls with doors and windows cut out (`Room3DScene.cells`), each
area's tile with grout lines at its real size and layout (`TilePattern`:
stacked, running bond, diagonal, herringbone; long side across; sizes from
the tile, else usual for its shape), benches, niches, corner pieces, the
curb, stone in a stone colour — every area's, whichever area is open
(`OtherAreaPieces.takeoff`; owner, 2026-10-14: the Floor tab hid the
shower's bench, niches and drain; 2026-10-18: a half wall's stone cap too —
the cap reads every area's stone, else the tile of the area tiling the wall) — and the fixtures the scanner found
(`ScannedRoom.fixtures`, kept from 2026-10-07 scans on; switchable).
Tile has to read as tile at phone size (owner, 2026-10-09: a 24×48 wall
looked painted): `TilePattern` draws several tiles to the image (to about
8′ each way), each a slightly different shade (more for zellige and
terracotta), grout at least 2½ pixels wide in a colour that stands out
from the tile (light on darker tile), filtered anisotropically. Wall tile
is laid from the floor (`tileMaterial`: a plane's texture runs down from its
top, so its top edge sets the offset), so courses are at the same heights on
every wall — a half wall's grout lines meet the full walls' (owner,
2026-10-14; they were half a tile off). Each tile
is drawn in its real shape (owner: "the patterns should be accurate";
every pattern checked by the owner on a sheet, three rounds, 2026-10-09):
`TilePattern.shape`. Square and rectangle by layout — stacked, running
bond, 1/3 offset, herringbone (planks square to the wall), diagonal (the
tile itself at 45°), diagonal herringbone (planks at 45°), double
herringbone, chevron, basketweave, Versailles (the 12-piece set as sold —
8×8, 8×16, 16×16, 16×24 — repeating every 48″), hopscotch (checked against
a published drawing); hexagon, arabesque (lanterns traced from a photo:
each side an S-curve its neighbour shares, leaving the tip straight and
meeting the side upright), star and cross (stars from two squares touching
tip to tip, crosses a darker shade), diamond, triangle, fishscale,
picket and pill (capsule, rows offset half a pill) shapes (owner: kite and elongated hexagon are picket, scallop is
fishscale — one each); and every mosaic style (leaf and rhombus taken out), waterjet
as the owner's chosen floral design. Fishscale is laid round side up or,
turned over (`turnedOver`, `tileTurnedOver`; "Round side" on the Tile
step), round side down. A mosaic with no size uses its style's usual piece
size (`drawnSize`). Long side up (`TileChoice.vertical`,
`EstimateSection.tileVertical`; "Long side" on the Tile step) turns the
pattern and names it ("Vertical Running Bond"); price unchanged. A photo
of the real tile (`photoID`, `tilePhotoID`; Choose / Take photo on the
Tile step and the tile sheet) is kept in Documents/Tile Photos
(`TilePhotos`), only its id in the estimate, and is each tile's face in
3-D (each tile a different part of it); a missing photo draws as the
colour. The Tile step shows an "In 3-D" swatch at true scale. New layouts,
shapes and mosaic styles each have their own adder in Admin, starting at
$0. `PricingCases` keeps the enum values there were when it was recorded
(`recordedLayouts` etc.); later ones are tested in `NewTileChoicesTests`.
Added 2026-10-19, after comparing TileBar, Daltile and Tile Shop's
catalogues (owner's picks; no new materials): shapes **Octagon & Dot**
(the octagon with a small square dot at its corners) and **Trapezoid**
(60° sides, alternately up and down, rows half a tile over; long side up
allowed); layouts **Checkerboard** (stacked, every other tile in a second
colour) and **Random Offset** (planks staggered at random, no neighbouring
joints within a fifth of a plank, as wood-look floors are laid); mosaic
styles **Trapezoid**, **Fan** and **Lattice Weave**. Every mosaic style
was then checked against Daltile's product photos (owner, 2026-10-19:
"Daltile has a fan mosaic that doesn't look like the one here"), and
drawn to match: Fan is round-side-up scallops a little taller than wide,
pinched to a point, with a fine light rim inside the top (tone −1: part
of the tile before it); Lattice Weave is a basketweave of three 1×3
strips to a block; the Trapezoid mosaic is equilateral triangles each cut
into a small triangle and three trapezoids turning round it
(`trapezoidPinwheel`; the Trapezoid *shape* stays rows of trapezoids);
Diamond is tall harlequin diamonds (3″ × 2″); the Pinwheel (Daltile's
Windmill) dot is the second colour; the Basketweave mosaic is the one the
owner installs most (their photo, 2026-10-19): 1 × 2 strips woven over and
under with a square dot half a strip wide in each gap, in the second
colour (`basketweaveDot`; the Basketweave *layout* of full-size tile stays
plain pairs); picket and diamond mosaics can be
laid long side up. Left as they are, being other designs of the same
name: our fishscale is round (Daltile's is a tall 2×6 arch), our pebble
is river pebbles (Daltile's is flat broken stone), our waterjet is the
owner's floral. The checkerboard's other tiles, the dots of octagon & dot,
the pinwheel and the basketweave mosaic, and the trapezoid mosaic's
triangles take
`TileAppearance.secondColour` ("Tile 2" / "Dot" / "Triangles" in the tile
picker; nil: charcoal with light tile, white with dark), drawn as tone 4
in `TilePattern`. Each has its Admin adder, $0 to start; rates
saved before read them as $0.

Pictures for the PDF (owner's calls, 2026-10-07): the estimate keeps the
3-D views chosen for it (`EstimateDocument.pictures`, `EstimatePicture`:
the area, a name, the camera and whether it goes in — never an image; the
picture is drawn from the saved scan and choices when the PDF is made,
`Room3DScene.picture`, so a saved estimate draws the same pictures). The
preview's **3-D views** button lists each scanned area's standard views
("Shower"/the area, "Whole room") and any added from the 3-D view's
**Add to estimate**, ticked in or out (`NDPicturesSheet`). Layouts have
"3-D views of the job" (`EstimateTemplate.include3DViews`, off in every
starter) and pictures per page (1, 2 or 4; 2 to start): when on, pages headed
"Your project" follow the estimate (`EstimatePDF.picturePages`, appended
with PDFKit so the layouts themselves — Classic's pixel check — are
untouched). The layout preview doesn't show them. The two standard
views are framed afresh whenever drawn (`NDPicturesSheet.camera`), so they
follow the room; views added from the 3-D view keep their saved camera.
"Whole room" (`wholeRoomView`, owner 2026-10-15) is a doll's house: from
above the corner farthest from the area, square to the room's walls, 40°
down, back far enough for the room and its height to fit.

Dimensions (owner's call, 2026-10-07): the 2-D plan's ruler button shows
the room's perimeter — each scanned wall's length to the quarter inch
(`dimensionText`) as an architectural dimension line outside it
(`PlanCanvas.drawDimensions`). Walls drawn in, the 3-D view and the PDF
pictures have none (3-D labels were tried and taken out the same day).

A scan can be calibrated with a tape measure (owner asked 2026-10-07;
`CalibrateScanSheet`, Measure step → "Calibrate with a tape measure"): tape
any scanned walls (one, or better one each way) and optionally the ceiling.
`ScanCalibration.solve` scales the plan along the room's two square
directions (`squaringAngle`) — walls running each way set that way's scale,
one wall sets both — and heights by the ceiling. iPhone LiDAR apps quote
about 1–2% (an inch or two on a wall); most of that is overall scale, which
this removes. `ScannedRoom.calibrated` corrects walls, openings (a shower
door and walls drawn in keep their sizes), floor, tub and fixtures, and
records it (`calibrations`, last one undoable); `AreaTakeoff.calibrated`
moves each area with it — tile stretches along its walls, full-height tile
stays full, niches, windows, benches and corner pieces keep their sizes —
and every area measured from the scan is applied again. It shows how far
off the scan was and how close each taped wall comes out before applying. Opening it again shows
every wall taped before (`loadEarlierTape`), so calibrating again keeps
them: one wall alone rescales both ways, which used to undo the other
way's earlier correction (fixed 2026-10-08). Apply is off when nothing
would change.

The editor (`ScanEditor`): floor plan on top (`PlanCanvas`: tap a wall,
pinch to zoom round the fingers, drag to pan, double-tap or Fit to reset;
this area's tile blue, other areas' orange), the chosen wall face-on below
(`WallElevation`: drag a piece's sides and top; ends snap to the sixteenth and to
corners, openings, the tub and other areas' ends; tap a door or window to
take it off), height chips, From/To/Height typed in inches, Add tile,
Split, Remove tile. A new piece takes the wall's longest free stretch at a
starting height (backsplash 18″, tub 84″, else full height). The scanner
only runs on a real LiDAR iPhone; in DEBUG builds without LiDAR a "Use a
sample room" button loads `ScannedRoom.sample` to try the editor.
`RoomScanTests` covers the arithmetic.

## One screen per area (owner's direction, 2026-10-12)

A scanned area, once its kind is chosen, is one screen (`AreaFlowView`,
`useWorkspace`): the model (`ScanEditor`, embedded via
`ScanEditor.Embedding`, no NavigationStack of its own) docked on top, tabs
below — Tile (the Tile step page), Measure (the model's walls/floor panels,
then the Measure page's fields: separate wall tiles, shower floor tile,
radiant heat, ceiling), Extras (the model's built-ins and stone, then
bands, borders, inlays and other charges) and Price (the area's review).
Changes are kept as they're made (each settles 0.3 s, then `onUse`); no
"Use these measurements" or discard prompt. Undo/Redo stay; ⋯ has Revert
this area (back to how it opened), Change the kind of area, calibration,
scanning again and Enter by hand instead. The bottom bar shows the
measures, the live area price and Done. When the area's model choices
change outside the screen (calibrating, scanning again, the ceiling
switch, a different kind of area) `workspaceVersion` reopens it afresh.
Areas typed by hand still use the step pages (to come: a sketched model,
then the same screen). The classic design is untouched.

The screen is the room's (owner asked 2026-10-12: change the shower's wall
tile and the bathroom floor's tile without leaving the model). A row of
area chips with prices and **+ Add area** sits between the model and the
tabs (`ScanEditor.Embedding.areaBar`); tapping another area on the model
switches to it too (`onSwitchArea`): on the plan, well inside another
area's drawn floor (8 pt clear of its edges, so walls and the curb still
take their taps) or the room floor of a Floor area
(`PlanCanvas.onTapOtherArea`, `OtherAreaPieces.sectionID`); in 3-D, another
area's floor (nodes named "area|id", `Room3DHit.Target.area`). Switching
keeps the tab and 2-D/3-D (`Embedding.show3D`) and reopens the model on
the new area (`AreaFlowView.activeID`, `switchTo`). The model's edits are
kept on the area it opened on (`sectionBinding(areaID)` in `onUse`), and a
change still settling when the area switches is kept first (`onDisappear`).
⋯ → **Delete this area** asks, then removes it (and its 3-D pictures),
re-cuts the Floor area and moves to the room's next area, or leaves when
none is left.

**Tile on the model** (owner's pick A from mockups, 2026-10-12): on the Tile
tab a tap on the model chooses a surface's tile instead of holding
anything (`ScanEditor.pickingTile`, `PlanCanvas.onPickTile`,
`Embedding.onPickTile`; 3-D: walls, other areas' floors and this area's
own floor, named "floor|mine", `Room3DHit.Target.ownFloor`). On the plan,
well inside a floor (8 pt clear of its edges) is the floor, else a wall
there wins. A wall goes to the area that tiles it (this one first),
switching to it; a wall nobody tiles is chosen as before. What opens
(`AreaFlowView.openTile`): a shower's floor → its floor tile (nil while
the same as the main tile); a Floor area's floor or a backsplash etc. →
the main tile (`fullMainTile`/`setMainTile`, with orientation, photo and
side); a shower or tub wall with its own tile → that `TiledWall` (named
by the scan's letter); walls sharing a tile → "All walls", with **Give
Wall B its own tile** (`separateWallsOnModel`, then that wall's sheet).
Every tile sheet (`NDTileSheet`) starts with **Use a tile from this room**:
each tile already used in the room once (`roomTiles`: main, each wall,
shower floor, ceiling), with a true-scale swatch (`NDTileSwatch`), the one
in use ticked; one tap copies the whole tile. 3-D draws a wall with its own
tile in that tile (`Room3DContent.wallTiles`, `OtherAreaPieces.wallTiles`,
`EstimateSection.wallTiles(in:)`; the PDF pictures too) — before, every
wall showed the area's main tile. The 3-D view and camera are kept as
areas switch (`Room3DCameraMemory`, saved each frame by the scene view's
renderer delegate since the next area's view opens before the last closes).

## Adding a room: its areas first, then scan or sketch (owner, 2026-10-12)

**Add room** opens `NDNewRoomSheet`: the name, every kind of area ticked
with a count (two showers: "Shower", "Shower 2", numbered for display only,
`AreaFlowView.areaName`), then how to measure — **Scan the room**,
**Sketch it: type its sides**, or **Just type square feet** (the step pages,
as before; ⋯ → Enter by hand instead stays on every area). The areas are
made at once on the usual tile (`NewEstimateView.createRoom`). After a scan
(and Tape a wall?) or a sketch they're placed on the model where it
suggests (`EstimateRoom.placeAreas`, from `ScannedRoom.suggestions`: the
floor, a shower filling a cove, a tub surround round a found tub, a
backsplash behind a cabinet; each suggestion used once); anything that
can't be placed starts empty. The first area opens on its Measure tab, the
rest one chip away. Renaming a room is still the alert. Every other Add
area — "Add area to <room>" on the estimate and + Add area on the area
screen — opens the same sheet without name or measuring (`addingTo`) and
adds every ticked area at once (`EstimateRoom.addAreas`, placed on the model
when the room has one). A room with no model can get one from its menu:
**Sketch this room** (its areas with nothing typed yet are placed on it;
typed ones stay typed). An area in a room with no model (a sketch cancelled when the room was
added, say) shows **Sketch this room** / **Scan this room** at the top of
its Measure step (owner, 2026-10-15); sketching there places that area and
the room's other blank ones on the model and opens it.

**Guided through the areas** (owner, 2026-10-12): the areas just added
(a new room's, or several added at once) are walked one at a time —
showers first, then tub surrounds (their footprints come out of the floor;
`NewEstimateView.showersFirst`), then the rest as ticked.
`AreaFlowView.guide` holds them (`NewEstimateView.guides`, per room, kept
till the last is finished): the bottom button says "Next: Floor" (the next
area's name) instead of Done, on the model screen and on the last step
page alike (`finishOrNext`), opening the next on Measure (on a model) or
Tile (typed). After a scan or sketch, a guided shower not yet placed opens
waiting for a tap on where it goes (`Embedding.startPlacingShower`, the
same Choose Shower Area), once per guided shower (`showersPlaced`).

**Always forward** (owner, 2026-10-12: tapping back to Tile felt
backward): the area screen's tabs are in the order you go — Measure, Tile,
Extras, Price (`ScanEditor.Tab`, `next`) — and its bottom button steps
through them ("Next: Tile", "Next: Extras", "Next: Price"), then names the
next guided area or says Done (`goTab`).

**Options under the fingers** (owner, 2026-10-15, replacing the big green
banners and "Next: the walls" card of 2026-10-12/13: "nudge the user… put
the options the user needs under their fingers when they need it. there
should be no redundant buttons"): one row just under the drawing
(`ScanEditor.stageRow`) on the Measure tab. A shower not placed yet shows
only **Choose Shower Area**; once placed, **Add/Edit Walls** leads (solid
blue, with Tile beside it) until the walls step is done — Done in the walls
mode, or on to the tile (`wallsDone`; placing or moving the shower starts
it again) — then **Add/Edit Tile** leads, with Walls beside it (owner,
2026-10-15/16: walls first, then tile). Add/Edit Tile opens the Tile tab,
where a tap on a wall or floor adds or changes its tile. A small Move and
Remove sit at the end; the floor panel no longer repeats them. The bottom
button follows the same order: "Next: Walls" (opens the walls mode) until
the walls are done, then "Next: Tile". Add/Edit Walls opens the **walls mode** (owner,
2026-10-15: adding and editing walls felt awkward; `openWallsMode`,
`wallsModeRow`): chips **Half · Full · Bench** and **Done**, with a blue
line saying what to tap. A picked chip stays picked (solid blue) — each tap
on a curb adds that wall (or drag to draw one), so a corner shower's two
half walls are two taps — and a tap on a wall or its end ring holds it to
drag, so the entry can be opened at the curb end or the wall end. New
walls get tile on their shower side as they're added (the area's tile).
Done leaves the mode and lets go of anything held; tapping a wall then
tiles it. Header (drop from ceiling) is in the ⋯ beside the line. While
the plan waits for a tap outside the walls mode (placing the shower) the
row becomes one blue line with Cancel (`waitingFor`). Nothing covers the
plan, and the tab below no longer repeats these (no Move/Remove buttons,
Tile walls | Edit walls switch or Add a Wall menu there). **Undo**
also steps back out of a step with nothing changed yet (adding a wall or
bench, placing: `guideStepToUndo`), and undoing the shower's placement
asks where it goes again. **Remove** takes off the shower's floor, curb,
drain, tiled walls, built-ins and stone choices; walls drawn in stay
(they're the room's); Undo puts it back.

Wall tile runs on past the shower floor to the curb's **outside edge**
where the floor's edge at that corner is open (owner, 2026-10-13: "wall tile
typically extends to the outside edge of the curb"; 4½″, none when
curbless; `tileWallsAroundFloor`). Showers placed before are brought up
to date when the shower is opened (`extendTileToCurb`: a piece ending at
the floor's corner where the entry is runs on by the curb's width; one
already past it is left alone). Where a half wall stands across that corner (on the curb), the
tile runs to the half wall's **outside face** instead (owner, 2026-10-16:
it stopped at its inside; `kneeWallReach`, in `tileWallsAroundFloor` and
`extendTileToCurb`, which the editor runs on every room change), and the
strip behind the half wall's end, up to its height, isn't counted
(`sqft(of:)`). `TileToHalfWallOutsideTests`.

**Sketch** (`RoomSketch`, `NDSketchRoomSheet`; owner's pick: shape, then
typed sides): Rectangle (width A/C, depth B/D) or L-shape (overall width
and depth, and the corner cut out at the bottom right: its width and
depth), and the ceiling, typed as a tape is read, drawn to scale as typed.
It makes a `ScannedRoom` with `sketched = true` (walls at the ceiling with
the room on their right, lettered by `reletter`, floor outline and area), so
every model tool works on it. A sketched room has no calibration, says
"Room floor" not "Scanned floor", shows a pencil-and-ruler icon on the
overview, and offers "Scan the room"/"Scan this room" to replace it.
`RoomSketchTests`.

## Two ways to measure a room (owner's design, 2026-10-08)

Adding a room asks **Scan the room** or **Enter measurements by hand**
(`NewEstimateView`). Both paths ask the same questions in the same steps —
Area, Tile, Measure, Extras, Review — and arrive at the same estimate; a
scanned room answers the physical ones on its model instead of in fields.

- **Scan**: the scanner opens, then "Tape a wall?" (`CalibrateScanSheet`,
  `afterScan`, skippable), then the room's first area opens on the Area step.
- **Area**: the same screen, with the scan's suggestions highlighted on the
  room's plan and marked "In the scan" (`ScannedRoom.suggestions`: the floor,
  a tub surround round a found tub, a backsplash behind a cabinet or sink,
  and "Possible shower" for an alcove of three walls — Apple's scanner finds
  tubs and cabinets but no shower). Choosing a suggested area starts it with
  what the scan found. You always choose; nothing is added by itself.
- **Tile**: the same screen either way.
- A wrong shower guess is fixed with **Put the shower here** (tap the
  corner it goes in: `AreaTakeoff.placeShower`, the floor at its size with
  its long side along the longer wall, walls round it tiled) and **Rotate**
  (`FloorRect.turned`: width and depth swap, staying in its corner). Moving,
  resizing or turning the floor makes its scanned walls follow
  (`tileWallsAroundFloor`, keeping each wall's tile height); the curb is
  always on the floor's open sides.
- **Measure**: a scanned area opens its model straight away the first time
  (`ScanEditor`, mode `.measure`: walls and tile heights, shower floor and
  curb, ceiling, walls drawn in, doors). Afterwards the step shows what came
  from the model, read-only ("from the model"), with Edit on the model;
  "Enter by hand instead" (`EstimateSection.measuredByHand`) gives the usual
  fields. An area typed before its room had a scan stays typed until moved
  to the model.
- **Extras**: built-ins are "Add on the model" (mode `.extras`: niches,
  windows, benches, corner pieces, stone for every piece); bands, borders,
  inlays and other charges are the same as by hand. Using the model sets the
  area's counts (`itemsPlaced`).
- **Edit walls** (Measure, any area; owner asked 2026-10-08): every wall,
  scanned or drawn in, can be changed after scanning and calibrating. Tap it
  on the plan or in 3-D; drag its middle to slide it (`moveWall`, square to
  itself, to the sixteenth) or an end to lengthen it (`moveWallEnd`); type length
  and height; split it in two (`splitWall`, `Wall.splitFrom`/`splitAtFt`);
  delete it. The chosen wall shows face-on with its doors, windows and
  openings (`WallElevation.editOpenings`): tap one to choose it, drag it
  along (and a window up and down), drag its sides, top or bottom; type
  kind, width, height, off the floor and the distance to each end ("To wall
  B"); delete it; Add door / window / opening (`openingEditor`). Its
  distance to the nearest wall running the same way on each side ("To wall
  D", `parallelNeighbors`) can be typed; the wall slides there
  (`setDistance`, via `moveWall`, so the room follows). Fields that move
  walls (distance, length, height) apply only when typing ends — a Set
  button by the field (`InchField.applyWhenDone`) — since "9" on the way to
  "96" would collapse the room. Under a wall's height, **Make every wall
  99 1/2″ high** (shown when any wall to the ceiling differs;
  `ScannedRoom.setEveryWallHeight`, `wallsDiffer`; owner asked 2026-10-12
  after a scan gave one wall 99 1/2″ and the rest 86 13/16″) sets every
  scanned wall and full wall drawn in to that height; half walls keep
  theirs, openings stay inside their walls, and full-height tile follows.
  `WallHeightTests`. The room stays joined: a wall sharing a corner stretches to
  follow (dragging a shower/closet divider stretches the closet's door wall),
  an end meeting the middle of another wall slides along it (the back wall
  keeps its length), a wall running into the moved one follows; doors and
  windows keep their places, floor-outline corners move with wall ends.
  Every area measured on the model follows (`AreaTakeoff.following`: split
  walls take their part of the tile, pieces and items keep their places,
  full-height tile stays full height) and is measured again. Drags work from
  the room as the drag began (`dragBase`). Leaving the model with changes
  asks Apply changes / Discard changes / Keep editing; 2-D and 3-D are the
  same model, so switching between them needs no prompt.
- **One rule for everything dragged** (owner, 2026-10-08: "everything
  should move in 1/16" increments the same way"): it moves to the
  sixteenth (`Steering.stepFt`) and catches on a wall, corner, edge, end or
  middle within a reach set on the glass (`Steering.catchFt(steered:ptPerFt:)`):
  4 pt when steered, 20 pt for a direct touch (where a new wall starts and
  its end as it's drawn), turned into feet at the zoom in use — from the
  owner's catch test (19 in 20 steered within 3 pt, taps within 18 pt, the
  same at either zoom). Fitted (≈30 pt/ft) that's 1.6″ and 8″; zoomed ×3,
  a third. To hold something nearer a wall than that, zoom in — walls slid, ends dragged,
  walls drawn in (drawing and moving), the shower floor and its edges,
  drains, tile pieces, doors, windows, niches and benches (`snapped`,
  `plannedEnd`, `movePlannedWall`, `snapLength`, `snappedDrain`; 1½″ where no
  zoom is known). Dragging a wall's end (`lengthenedEnd`) keeps the wall's own
  line (never squared up) and never catches on the walls attached at that
  end or in line with them — they move with it, and catching on them made
  the end stick and jump (fixed 2026-10-08). Lengthening or
  shortening a wall slides the wall square across its end whole, so the
  room stays square. A wall the scanner gave in pieces either side of a
  doorway — in line, up to 5′ end to end (`inLine(with:)`) — moves as one
  (owner: "a doorway doesn't create two walls"); the pieces keep their own
  letters.
- **While something is held** (owner's calls, 2026-10-08, after looking at
  how CAD and design apps do it): catching is felt and seen — a light tick
  and a green flash (a ring on the plan, a dashed line on the wall view)
  as it catches (`cue`, comparing with where it would be without
  catching); a **Catch on / Catch off** button turns catching off for that
  thing till it's let go (`catchOff`); and nudge arrows move it 1/16″ a
  tap, catching nothing (`nudge`) — the arrows point the way it moves on
  screen (◀ ▶ or ▲ ▼ per direction it can move). In the strip at the top
  of the plan and in place of the hint on the wall view.
- **Admin → Catch test** (`CatchTest.swift`, owner asked 2026-10-08): three
  drills — tap on a wall's line (where a new wall starts), steer a held
  wall end to touch a wall, steer a tile edge to a window's side — at the
  fitted plan's scale (30 pt/ft; wall view 24) and zoomed ×3, nothing
  catching, 15 tries each. Misses are kept in points and inches
  (UserDefaults "catchTest.v1"; Copy results) and summed up as the miss 19
  tries in 20 stay within. Meant to set the catch in screen points from
  the owner's real aim, converted at the current zoom (done 2026-10-08:
  4 pt steered, 20 pt touch).
- The model opens in the mode of the step it came from, and a **Measure |
  Extras** switch at its top changes mode without leaving it (owner asked
  2026-10-08).
- Wall tile starts at the top of the wall everywhere except backsplashes
  (owner's rule, 2026-10-08; tub surrounds were 84″).
- Calibrating or deleting a wall re-measures only areas measured on the
  model; typed numbers are never overwritten.

## A Floor area on a scanned room (owner's calls, 2026-10-12)

A Floor area on the scanned floor tiles the floor's outline (the scan's,
or its own once its edges are dragged: Edit floor outline, `floorOutline`,
catching on walls alongside) less, each only where it's on the floor
(`FloorGeometry.clip`/`area`): every other area's drawn shower floor and its
curb's 4½″ strip (`floorFootprints`; kept in `AreaTakeoff.cutouts`,
refreshed by `EstimateRoom.refreshFloorCutouts` whenever an area is saved
from the model or the scan is calibrated, and set fresh when the editor
opens), "no tile" boxes (`skipBoxes`: Leave out an area, or the cabinets the
scanner found, once, `addScannedSkips`; chosen with a tap, moved and resized
like the shower floor), the tub when left out, and "Also leave out" square
feet. The plan fills it in blue with those as holes; 3-D tiles it the same
way (`Room3DContent.floorShape`: the tile over the whole outline, each
hole laid on top as bare floor — holes cut into one `SCNShape` dropped
whole triangles of tile when they touched each other or the walls, as a
corner shower's floor and curb strips do; owner, 2026-10-13), square to the
room's walls: the shape is built turned by `squaringAngle` and its node
turned back, since a shape's tile follows its own axes (owner,
2026-10-12: the floor tile wasn't square to the room). A curbless shower
whose floor tile is the floor's tile has no hole: the floor's tile runs on
into it in 2-D and 3-D (its own floor isn't drawn over it), but it's still
priced apart — drawing only. Before this the floor was the whole scanned
floor less only the tub. `RoomFloorTests`.

## Wall letters and sections (owner's calls, 2026-10-09)

**Sections.** A wall a divider meets partway is cut into sections, each a
wall of its own with its own letter and its own face-on view ("each wall
section should have its own letter and be its own view when tapped on"):
`ScannedRoom.sectionAtDividers`. A divider is any full-height wall, scanned
or drawn in, with an end on a scanned wall at least 6″ from its ends; half
walls don't divide (the wall carries on above them) and walls drawn in are
never divided. The section after a divider has `Wall.startsAtDivider`;
when no divider meets its joint any more (deleted, moved off) it joins the
wall before it again — a wall split by hand never does. Section ids come
from the wall and the divider (`sectionID`), so a drag that divides a wall
at every step keeps them. It runs on every change in the editor
(`onChange(of: room)`), on a new scan, and once on scans saved before.
Areas follow (`AreaTakeoff.following`: tile across a joint is cut in two,
joined again when the sections join; items and corner pieces go with their
section; several splits at once are taken in order). Sections are in line
and joined, so they slide as one wall (`inLine`) and a divider moved drags
their joint along. The plan dimensions a wall in sections as one —
overall, and the stretches between dividers (`joiningSections`, used by
`PlanDimensions.build`) — and a divider is still a partition (drawn solid
in 3-D). A face-on view's end at a divider is named for the divider, not
the next section. Cove filling and tiling round a shower floor reach across
sections (`sections(of:)`).

**Both sides of a divider.** A scanned divider (`ScannedRoom.isDivider`)
has the Side switch walls drawn in have, so one area can tile either side
or both ("Shower side" / "Side facing wall N"; each side's square feet
count). For a scanned wall `Piece.face`/`Item.face` 0 is the area's own
side — toward its drawn floor, else the room's middle, as always — and 1
the far side (`sideNormal(of:face:toward:)`; a wall drawn in keeps face 0
on its left), so nothing saved before moves. Other areas' tile on a
divider is turned into this area's sides for the face-on view and the plan
(`othersHere`); the plan draws a divider's tile just off the side it's on;
a tap in 3-D picks the side tapped.

**Letters** go in the order you'd meet the walls going clockwise round the
plan as it shows on screen (turned square, `squaringAngle`): A is the top
wall, then along each outside wall, and straight after a wall the walls
that run into it, in order along it, each followed by any running on from
it (a closet's walls follow the wall they stand on); walls standing on
their own go last (`ScannedRoom.reletter`, `wallsInMeetingOrder`). It
replaced lettering by angle round the room's middle, which mixed closet
walls in with the outside ones. Only letters change, never a wall's
direction. Scans saved before (`ScannedRoom.lettering` < 2) are cut into
sections and lettered again when read (`EstimateRoom.reletterOldScans`,
`upgradeLettering`): areas follow, and walls named by the old letters
("Wall C" with its own tile) are renamed to match — a wall now in sections
gives its tile to each section, the first keeping the square feet (the
rest 0) until the area is measured again, so prices don't move. Walls
added, split or divided later take the next free letter; nothing is
re-lettered while editing. On the plan the letter is a badge centred on its
wall, over the dimension lines, slid along the wall only where it would
sit on another wall's letter. `WallLetteringTests`.

## Tubs (owner's calls, 2026-10-19)

A tub surround's tub is its own, on the model (`AreaTakeoff.tubRect`,
`tubKind`, `tubRimIn`, `tubLipIn`; Sources/Views/RoomScan/Tub.swift) —
kept apart from `floorRect`, which is a shower's floor everywhere. Before,
a tub was only the scanner's grey box; a sketched room or a missed tub had
none. **Choose Tub Area** (Measure tab, like Choose Shower Area) and a tap
(`placeTub`): in a space of three walls the tub fills it, wall to wall (30″
deep, or the space's depth under 3½′); else 60″ × 30″ from the nearest
inside corner, long side against the wall nearer the tap. **An alcove tub
has three full walls** (owner): placed in a corner, a full wall is drawn in
at its open end, its face flush with the tub, tiled on the tub's side
(`closeTubEnds`) — an ordinary wall drawn in, edited or deleted like any
other. A drop-in in a corner starts open; **Full wall at the open end** (Tub
panel) closes it in, for either kind. The tub is held, dragged and resized
on the plan like the shower floor (the plan's floor binding is the tub for a
tub surround), turned with Rotate, typed in the Tub panel; Move / Remove sit
under the drawing. A scanned tub becomes the tub surround's own
(`adoptScannedTub`). The room's `tubOutline` follows it, with `tubPlaced`
set, so the floor, the other areas and 3-D see it.

Kinds: **Alcove** (rim 15″) and **Drop-in** (a deck 20″ high, the tub
`tubLipIn` 3″ inside it on each open side, `tubInDeck`; switching grows or
shrinks the deck). The walls the tub is against are tiled along it
(`tubChanged`: pieces that ran along it follow, keeping their height), and
the wall **below the rim** (or the deck's top) isn't counted
(`tubBelowRimSqft`, in `apply`). A drop-in's deck **top** (the deck less the
tub's opening) and **front** (each open side × the deck height) are tile or
stone (`tubDeck:top`, `tubDeck:front`, Extras → Drop-in tub deck): tile on
its own line, "Tub deck tile", per sq ft at Admin → Stone pieces → Drop-in
tub deck (`Rates.tubDeckTilePerSqft`, $0); stone in its group
(`StoneGroup.tubDeck`, Top and Front, panels by the square foot as placed, $0
until set) on a "Stone tub deck" line, and in the cutlist (the top one slab
over the whole deck, a front piece per open side). The floor leaves the tub
out (`floorFootprints`) and never cuts the scanned tub twice.

**A deck beside a shower ties to it** (owner): a shower tapped beside a
placed tub takes the part of the space on the tap's side, ending at the
tub (`placeShower` → `FloorRect.clipped`, either way across), and a tub
tapped beside a shower likewise (`placeTub(avoid:)`); the shower has **no
curb and no jamb along the tub** (`openSides`, the tub's edges standing in
for a wall, `tubDeckWallID`) — only a tub a tub surround placed
(`ScannedRoom.tubPlaced`); a scanned tub in a shower's cove is still a
conversion. Where a drop-in's deck meets the shower, the Tub panel chooses:
**Deck stops at the shower** — the deck's end, inside the shower, is part
of its front — or **Runs in as a bench** — the shower gets a framed bench
(`Item.fromTubDeck`) along their back wall from the deck, the deck's depth
and height, 15″ into the shower, priced as the shower's bench, and the
deck's end is no longer front. The room keeps them tied whenever an area
is saved (`EstimateRoom.tieTubsAndShowers`, run by `refreshFloorCutouts`;
`AreaTakeoff.tubNeighbors`). Dragged, they catch on each other as on
a wall (`FloorRect.caught(on:reach:)`, the plan's `catchOutlines`: a shower
on the placed tub, a tub on the room's showers; a moved floor catches on
walls too), and the bench shows on the tub's model as soon as it settles.

**Freestanding tubs** are the room's, decoration only — nothing about the
tile changes (owner): ⋯ → Add a freestanding tub in any area's model, a tap
where it goes, 66″ × 32″ square to the room (`ScannedRoom.freestandingTubs`,
`addFreestandingTub`); ⋯ → Freestanding tub → Move (a tap), Turn, Remove.
Drawn as an oval on the plan and a 22″ oval tub in 3-D; the floor's tile
runs under it, and tile on the wall behind it is whatever area tiles it.

**Vanities and toilets** (owner, 2026-10-19), from the same ⋯ in any
area's model: **Add a vanity** / **Add a toilet**, then a tap by the wall
it goes against (set against the wall's face, half its drawn thickness off
the line). A toilet (20″ × 28″) is decoration: ⋯ → Toilet → Move, Turn,
Remove. A vanity (`ScannedRoom.vanities`, `Vanity`; Sources/Views/RoomScan/
Vanity.swift, `VanitySheet`) starts 36″ × 21″, 34½″ high, opening its sheet:
width, depth and height; sinks (1, or 2 from 60″ wide unless typed,
`fitSinks`); the stone top 1″ past the cabinet on its open sides
(`vanityTop`) and its stone (`top`, the stone picker); the backsplash —
**Stone** (4″ to start), **Tile** or **None** — its height, and which of the
walls it touches get it (`splashWalls`, `wallsTouching`, `vanitySplash`);
Move, Turn, Remove. Each vanity has its **own area**: a Backsplash area
called **Vanity Backsplash** on the chips, the estimate and its screens
(`AreaTakeoff.vanityID`, `EstimateSection.areaTitle`, `areaName`), made and
removed with it and measured again whenever the room is saved
(`EstimateRoom.syncVanities`, run by `refreshFloorCutouts`). There a tile
backsplash is square feet at the backsplash price, in that area's tile (kept
on the vanity, `splashTile`, for drawing); a stone backsplash is
`StonePart.vanitySplash` on a "Stone vanity backsplash" line (Admin →
Stone pieces → Vanity, $0 until set) and in the cutlist; the top is always
in the cutlist (one slab, the cabinet plus overhang, `vanityCutPieces`) and
is charged as **materials** — "Vanity top" (sq ft × `Rates.vanityTopPerSqft`)
and "Sink cut-outs" (each × `sinkCutoutEach`) — only when stone material is
its own line (`stoneMaterialSeparate`; owner's call). Drawn on the plan
(cabinet, top, backsplash lines; toilet) and in 3-D (`vanityNode`: cabinet
over a toe kick with door seams, stone top with oval sinks, backsplash on
the wall's face; `toiletNode`). `VanityTests`.

3-D draws each (`Room3DScene.tubNode`, `freeTubNode`): a white alcove tub
with its apron, rim, basin and drain; a deck in tile or stone with the tub's
rim set in it. `TubTests`.

## Placing a shower, curbless showers and drains (owner's calls, 2026-10-08)

- **Put the shower here** (`AreaTakeoff.placeShower(near:in:curbWidthFt:)`):
  a tap inside a cove of three walls (`ScannedRoom.cove(around:)`: a back
  wall, a wall each side running out from it, 2–10′ each way along the
  room's square directions, the open side free of walls) fills the cove;
  the curb's outside face is flush with the cove's outside corners, so the
  floor stops at the curb's inside face (`coveDepthFt` keeps the cove's
  depth). A side wall that ends at a wall running across it reaches that
  wall's far face — half its drawn thickness past the line (scanned walls
  are drawn 4½″, a drywalled 2×4 wall, `scannedWallThicknessFt`; owner:
  3½″ framed, 4½″ with drywall, the curb flush to the drywalled corner)
  (`ScannedRoom.endJoinFt`; owner, 2026-10-13: "the curb should go to the
  corner"); 3-D draws scanned walls out to there too, and wall tile may run
  that far past a wall's line. Showers filled into a cove before are
  deepened to match when opened (`fitCove`). A tub in the cove doesn't matter (a conversion). Anywhere else,
  48″ × 48″ in the nearest inside corner (no longer the last size, or 60″ × 36″).
  The end of a narrow room or a long alcove (a back wall with a side wall
  square to it at each end, 2½–6′ apart, `ScannedRoom.roomEnd`; owner,
  2026-10-14) gets a shower wall to wall across it, 48″ deep. A dragged
  shower floor stays inside the room's floor (`ScanEditor.fitsRoom`: a
  move tries each way alone, an edge stops at the wall); one already past
  the walls moves freely. An edge let go within 0.4′ (≈4¾″) of one of the room's walls — the
  reach that counts as against it — snaps the rest of the way
  (`snapFloorToWalls`, in `tileWallsAroundFloor`), so a corner shower whose
  curb is dragged to the far wall becomes a three-wall shower tight to all
  three; walls drawn in (e.g. on the curb) aren't snapped to.
- **The curb** is drawn (plan and 3-D) just outside the floor's open sides,
  always 4½″ wide (`StonePrices.curbWidthFt`; Admin's stone curb width is the
  stone on top, which overhangs the curb, so it isn't used for this;
  benches use it too).
- **Drawn from every area, corners overlapped** (owner, 2026-10-12): a
  shower's curb shows on the plan (lighter) and in 3-D from the room's
  other areas too (`OtherAreaPieces.curbs`, with its height and stone
  parts). A corner shower's two curb runs overlap at the outside corner —
  one runs on past it by the curb's width — instead of meeting at the
  inside corner (`AreaTakeoff.curbRuns`, used for drawing only; the curb's
  linear feet and dimensions are unchanged). `CurbCornerTests`.
- **Remove the curb (curbless)** (`AreaTakeoff.curbless`, `setCurbless`): no
  curb pieces or curb line, jambs from the floor, and a cove-filled floor
  runs to the outside corners (put back: it stops at the curb again). A
  corner shower keeps its size. "Curbless Shower" goes on the estimate per
  sq ft of shower floor, with its minimum.
- **Drain** (`AreaTakeoff.drain`, `Drain`; nil = a 4″ square drain in the
  middle of the floor): kept in the floor's own terms (along its width and
  depth), so it moves with the floor. Tap it on the plan, then drag
  anywhere. **Linear** starts against the floor's longest wall side, wall to
  wall (`startingLinearDrain`); it snaps flush to each side of the floor —
  walls, and the open side, which is the outside corners when curbless —
  and to the middle, within 1½″ (`snappedDrain`); held, its ends drag (snap
  to the sides), Turn turns it a quarter turn (`turnedDrain`); length typed
  in the panel. "Linear Drain" goes on the estimate per linear foot of
  drain, with its minimum (materials, taxable; switchable in Admin).
- Both items are on the price list (`PriceListItem.curblessShower`,
  `.linearDrain`, fixed ids, $0 until set); rates saved before get them
  once (`Rates.showerDrainItemsAdded`), so deleting one in Admin sticks,
  and a deleted one is simply not added. Their lines have fixed ids per
  area (`extraLineID`), like the stone lines, so a price changed on the
  estimate stays when measuring again. `ShowerCoveAndDrainTests`.

## Holding, steering, lengths and undo on the model (2026-10-08)

Borrowed from the owner's other app, FabSpecPro. This replaces the drag
handles described above wherever they differ.

- **Tap to hold, then drag anywhere** (owner: a thumb on top of a wall hides
  where it's going). On the plan (`PlanCanvas.Hold`) tap a wall, a wall's end
  ring, the shower floor or, with the floor held, one of its edges; on the
  wall face-on (`WallElevation.Hold`) tap a piece's side or top grip, or tap
  a niche, window, door or opening a second time to hold all of it. Then a
  drag anywhere on that drawing moves what is held; a strip at the top gives
  its live measurements. Tapping empty space lets go. With nothing held a
  drag pans.
- **Speed-based steering** (`Steering.gain`): a slow finger moves things at
  0.3 of its travel, a fast one 1:1 (2 to 16 pt per event), so fine
  adjustments are easy. Steered lengths snap to the sixteenth.
- **Zoom** (`PlanViewport`): pinch about the fingers, pan clamped to half a
  screen past the plan, Fit resets; the held thing is kept on screen.
- **Lengths** (`Lengths`, `inchText`): every length shown — plan, wall,
  fields, calibration, labels — is in inches to 1/16″ (106 1/2″, 13 1/8″);
  owner's call, 2026-10-08, after a day of feet and inches crowded the
  plan. Typed either way, as a tape is read (106 1/2, 106.5, 3/4,
  8' 10 1/2", 8'10-1/2). Don't bring feet back for one place: one rule everywhere.
- **Undo and redo** (icons at the top of the model; `EditHistory`, up to 100
  steps): the room and the area's takeoff together, one step per change once
  it has been still for 0.6 s. Selections that no longer exist are cleared.
- **Dimensions**: see "Plan dimensions" below — the plan (the ruler button) and the wall face-on.

## Plan dimensions (2026-10-08, adapted from FabSpecPro)

Owner asked for FabSpecPro's dimensioning, with FabSpecPro left untouched:
TileRate has its **own copies**, never shared — `PlanDimensions.swift` (the
model and builder, after FabSpecPro's GeoDimension: one list of dimensions
the drawing only renders) and `PlanDimensionPlacer.swift` (after its
SheetPlacer and SheetLayout rules). Never edit FabSpecPro to change these.

What the plan shows: each scanned wall's overall length outside the room;
where another wall runs into a wall partway, its stretches (corner to
partition, partition to corner) on one row just inside the overall —
FabSpecPro's seam chain, so two stretches never cross in an inside corner;
a partition's own length on whichever side is clear (`isPartition`,
`eitherSide`); walls drawn in beside themselves; the shower floor's width
and depth inside it, except a side that is all curb, which the curb's own
number gives (two numbers on sides that meet would cross in their corner);
the curb outside the floor ("Curb 49 1/2″", or the number alone when the
words don't fit, `shortText`); framed benches' length and depth.

How it's placed: walls, floor, curb and tub claim their lines and the wall
letters their boxes first; every extension line's lane is reserved; then
nearest first, each tries rungs 13 pt apart and spots along them (beside a
short line, or past an end without running through a wall). Rules: numbers
don't overlap anything, dimension lines don't cross (D1, D2), a number is
nearest its own edge (D3), parallel numbers stagger, an overall is beyond
its wall's stretches, a number for something on screen stays on screen
and out of the strip with the hint and the 2D/3D switch. Nothing clean: the
least crowded spot — never left out. The plan is 340 pt tall with
dimensions on (250 off). Numbers are 9.5 pt on the plan and the wall alike
(`DimensionDrawing.font`). `PlanDimensionTests` holds the rules.

The wall face-on (`WallElevation`) uses the same placer and drawing
(`WallDimensions.swift`, `DimensionDrawing.swift`; the view 330 pt tall): along the bottom, every door, window, opening, niche, bench
and corner piece's sides on one row, the wall's length beyond it; up the
right-hand end, every bottom and top of those and this area's tile top on
one column, the wall's height beyond it; the chosen niche, window, bench or
opening (Edit walls) has its own width over it and height beside it, in
cyan. Sizes and "up" heights are no longer written inside the shapes.
Grips, labels, the end names and the hint are claimed so numbers keep off them.

## Estimate wording templates (roadmap Phase 3)

From 2026-10-06 each area's sentence on the estimate is built from templates
the owner edits in Admin → Estimate wording (`WordingTemplates`, kept in
`Rates.wording`, so a saved estimate keeps the wording it was saved with and
"Convert to current pricing" also brings in the current wording). Two kinds:
`tile` describes one tile ("12×24 Porcelain Tile in Running Bond pattern"),
used for the area's tile and each wall, floor or ceiling with its own tile;
`areas` holds the sentence for each kind of area, where {tiles} is every
tile with the surfaces it goes on. `fillTemplate` fills {brace words}; a part
in [square brackets] is dropped when every brace word in it is empty; an
unknown brace word is printed as typed. Fixed for now: the " on " and "; "
joining tiles to surfaces, the feature and band/border/inlay phrases, and the
"Room - Area" prefix.

Every caller passes the templates (`describeSection(_:wording:)`,
`estimateSentence(room:section:wording:)`, `SectionPrice.sentence`), taken
from `store.pricingRates`. `WordingGoldenTests` holds the standard templates
to the wording of 1,403 areas recorded before templates
(`WordingCases.swift`, `WordingGolden.swift`) — never regenerate it to pass.

An area's sentence can also be typed over on one estimate (new design: the
review screen's Edit wording, `NDWordingSheet`). It is saved on the section
(`EstimateSection.customWording`) with the generated sentence it replaced;
when the area later generates something different, the review screen flags
it (`AreaWording.isOutOfDate`) with Keep my wording / Use the new wording.
`areaWording` is what every screen and the PDF show. Using wording for
future estimates" is decided in Admin, not on the estimate (owner's
call, 2026-10-06). The edit sheet shows what the edit would be as that
area's template (`templateFromEdit`: the app's own {tiles}, {features} and
{sqft} text goes back to brace words, their joining words into brackets),
explains each part, and can leave it as a suggestion (`WordingSuggestions`,
in UserDefaults). Admin → Estimate wording shows a waiting suggestion under
its area with Use this suggestion / Dismiss. Every area sentence and the tile
description has its own Reset to standard, besides "Back to the standard
wording" for all of it. An edit inside the tile description can't become a
sentence template; that is changed under Each tile.

## Estimate layouts (roadmap Phase 4)

From 2026-10-07 the PDF is drawn in a layout (`EstimateTemplate`, kept in
`Rates.estimateTemplates` with `defaultTemplateID`, so a saved estimate keeps
its layouts; `SavedEstimate.templateID` and `EstimateTemplate.chosenID`
(UserDefaults "export.templateID") record which one an estimate uses). A
layout sets the title, the detail (every line / labor and materials per area
/ one price per area), the QTY and RATE columns, grouping of price list items
named "Group: name" into one line per group (taxable and untaxed never share
a line; a group of one stays as the item), the accent colour, a "valid until"
date, text sections after the totals, and the signature lines. Starters:
Classic (the old PDF, unchanged and not grouped), Summary, Labor & Materials,
Proposal (its scope/not included/payment wording is placeholder for the owner
to edit). Admin → Estimate layouts edits them, with a preview; the new
design's review screen picks one per estimate; the classic design uses the
chosen or default layout.

In the new design, Create PDF opens `NDEstimatePreview`: the estimate drawn
live in each layout, swiped through left and right, starting on the one
chosen for the estimate. Tapping an area's description (`EstimateRow.sectionID`,
`TemplatePDFView.onEditWording`, nil when drawing the PDF) opens the Edit
wording sheet; per-estimate wording is edited there, not on the review
screen. "Use this layout" chooses it for this estimate; "Make default" sets
`Rates.defaultTemplateID` (★); Share makes the PDF in the layout on screen.

`estimateRows` (EstimateLayout.swift) builds the rows from `EstimateTotals`;
every layout's rows add up to the same subtotal (a test checks).
`TemplatePDFView` draws them. `ExportedFormPDFView` is the PDF as drawn
before layouts, kept only so `EstimateLayoutTests` can check page by page that
Classic is pixel-identical to it.

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

## Price list for extras

From 2026-10-04 Admin has a price list (`PriceListItem`, `Rates.priceList`):
each item has a name, a unit (per sq ft, per linear ft, each, flat per job), a
price, and whether it is labor or materials (taxable or not). Picking one for
an area adds an ordinary labor or materials line (`EstimateSection.add`), so
its price can still be changed on that estimate and it appears everywhere
lines do. A per-sq-ft item starts at the area's square feet (`areaSqft`: a
shower's walls + floor + ceiling, a tub's walls + ceiling, otherwise the
area's figure) and follows it (`followsAreaSqft`, kept up to date by
`syncAreaQuantities` whenever a section is saved) until a quantity is typed.
Each item has a minimum charge (0 = none) that the line keeps
(`AdditionItem.minimum`; amount = max(qty × price, minimum)). Typed custom
lines are still available.

A per-sq-ft item also has a measure (`EstimateSection.sqft(_:)`): whole area,
walls only, walls and ceiling, Floor areas only, shower floor only, or ceiling
only. Owner's rule: a shower floor is not a floor — it includes the mud bed
and shower pan and is an item to itself.

Demolition is one item per thing torn out (`PriceListItem.ownersDemolition`,
named "Demo: …" and grouped under a Demolition submenu): fixtures priced each
— one-piece tub/shower unit, tub only, acrylic shower base — and surfaces per
sq ft — tile shower base (shower floor), tile walls (walls), tile floors
(Floor areas), tile ceiling (ceiling), vinyl, laminate and hardwood floors,
carpeting and plywood (Floor areas). Any item named "Group: name" is grouped
the same way in the menu. The rest of the starting list: Floor leveling
(Floor areas only) and Epoxy grout upgrade (whole area). All labor, $0 until
set. The very first list (2026-10-04) had one "Demolition" item; reading
saved rates replaces it with the demolition items — per-sq-ft ones keep its
price and minimum — and makes floor leveling Floor areas only.

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

## Materials, shapes and wording (owner's calls, 2026-10-09)

Limestone and travertine are separate materials (`TileType.limestone` is
now "Limestone"; a saved "Limestone/Travertine" reads as Limestone, and
rates saved before give Travertine limestone's adder once,
`Rates.travertineSplit`). Terrazzo, Quarry and Pearl were added (adders
start at $0). Square is not a separate shape: the shapes offered are
`TileSize.choices`, and a saved square reads as a rectangle (they always
priced the same — the doubling adder). Multi-Tile is no longer offered
(`Layout.choices`); the case stays so estimates saved with it read and
price as before. The estimate names a tile's shape after its size unless
it's a square or rectangle ("6×6 Ceramic Hexagon Tile", `tileWord`).
Porcelain, Rectangle and Running Bond come first in their lists
(`TileType.choices`, `TileSize.choices`, `Layout.choices`), and an area
with no tile yet opens on them at 12″ × 24″ (`startWithUsualTile`, both
designs); a separate tile with nothing to copy starts on
`TileChoice.usual`. `TileChoice()` itself still defaults to ceramic —
recorded cases rely on it.
`WordingGoldenTests.withOwnersChanges` applies exactly these two wording
changes to the recording (never re-recorded); `PricingCases` keeps the
materials by the names they were recorded with (`recordedMaterials`).

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


**How stone looks** (owner's design, 2026-10-17; drawing only, never the
price). Each area has a stone (`AreaTakeoff.stoneLook`, nil = the standard
white marble) and any piece can have its own (`stoneLooks`, by its
`TrimPiece.key`; corner shelves, seats and footrests by `cornerKey`,
"corner:<id>", following the area's until given their own). A
`StoneAppearance` is a pattern and colours — base, markings (veins, flecks,
bands, chips or shading, by pattern) and a second marking colour — polished
or honed, or a photo of the slab (`photoID`, in `TilePhotos`), and a name
when it has one. Patterns are grouped by look (owner, 2026-10-18, after
Cambria's 159 quartz designs — Vein 51, Waterstone 48, Wave 34, Solid 16,
Granular 10 — and the common US granites and marbles; a marble-look quartz
is "veined", not "marble"): Veined (soft veins, thin veins, bold veins,
web, breccia), Moving (sweeping, linear, cloudy), Speckled (speckled,
coarse), Plain (solid, concrete), Natural stone (soapstone, travertine,
onyx, terrazzo). The three veined marbles must look plainly different
on a tile (owner, 2026-10-18: "very little difference"): soft veins is
hazy, pale drifts (Carrara), thin veins long fine veins on a clean white
field (Calacatta), bold veins wide, dark diagonal veins. No CC0 photo had
a Calacatta's long veins, so the owner chose Pexels photos (free under
the Pexels licence, not CC0): thin is Pexels 3847500, soft the same
photo's other end softened, bold Pexels 2341290 — each with its lighting
flattened and edges cross-faded so it tiles. Travertine is Travertine009
(even cream bands, vein-cut; it was Travertine004, which read as onyx).
Sweeping is Onyx001, broad bands
(Brittanicca, Taj Mahal), with Onyx004's surface. Limestone and Flowing
were taken out; saved ones read as Solid and Sweeping (`Pattern.reading`).
**Naming** (owner, 2026-10-18): the picker's name field, under the
preview, is optional — named ("Taj Duna Quartz", "Absolute Black
Granite"), the stone is kept in My Stones on Done with its pattern,
colours, finish and direction (a named slab photo too, badged "Photo");
blank, it's that piece's alone. A name already in My Stones offers "Use
the saved one", else Done updates it. Each pattern is a photo of
real stone (owner, 2026-10-18: patterns drawn from noise weren't
realistic), recoloured by `StonePatterns` (Sources/Views/Stone): a grayscale
map per pattern (`StoneMap-<pattern>` in the asset catalogue's StoneMaps
folder, 1024 px, tiling; made from ambientCG textures, CC0 public domain —
which one each is, `StoneMaps.source`) holds how far each point is from the
stone's middle tone, 128 the middle; the base colour goes at the middle,
the markings colour where its veins, flecks or bands are, the second
colour at their soft edges, and the other side lightens (or darkens) the
base a little (`StoneMaps.darkMarkings`). Each map keeps its photo's own
contrast (solid, concrete and limestone softened), so quiet stone stays
quiet. To change a pattern's photo, remake its map the same way (median
and 1st/99th percentile of the luminance) rather than editing the image.
Drawn images are cached. Coarse granite is Granite007A (2026-10-18,
replacing a weaker pick). Each pattern is drawn at
its real size (`StoneMaps.spanFt`: sweeping 7′ a repeat, bold marble and
onyx 6′, speckled granite 1½′; owner chose no size control) with the photo's surface
(`StoneNormal-<pattern>`, a normal map, stronger when honed); patterns that
run one way (`hasDirection`) can run along the piece or across it
(`StoneAppearance.across`, "Veins run" in the picker; the image is turned,
not redrawn). Direction is for the 3-D model and pictures only — not sent
in the cutlist (owner, 2026-10-18; FabSpecPro's slab layout has a rotation
lock and reads a slab's vein direction, so a per-piece `veins` field could
feed it later). Stone pieces → "Use this stone for every piece" (in a piece's
picker: the area's stone, own stones cleared) and "Put … back on the area's"
(owner, 2026-10-18). Stone lines on the estimate keep their plain wording
("Stone curb") — the stone's name and finish stay off the description
(owner, 2026-10-18; maybe listed under materials later), and a line given
a name for a day is put back unless typed over. The cutlist carries
`material` (the name, absent when unnamed) and `finish` once a stone is
chosen (`chosenStone(for:)`, `StoneAppearance.label`; JSON fields,
spreadsheet columns), and pieces in different stones aren't merged. The picker (`StonePickerSheet`): a big preview in the chosen
colours, the name, Polished/Honed, My Stones and Recently used
(`StoneLibrary`, UserDefaults, an unreadable list kept aside as
".unreadable"), the pattern swatches each in its own usual colours
(owner's call, so every pattern is recognisable; picking one keeps the
chosen colours), the colours (`StonePatterns.families`, 57: Whites 5 by
undertone, Cool gray 10 to true black, Warm gray 9, Beige 8, Gold 6, Red 6,
Blue 6, Green 7 with a soapstone green-gray — even OKLCH steps, fitted so
every colour measured from the Cambria designs and the common stones has a
close match; greige was dropped, owner 2026-10-18): wells choosing what
it colours, all eight families as buttons (each a light-to-dark bar of its
colours, "Cool"/"Warm" for the grays) and the chosen family's colours in
one row, no scrolling, with Any colour at its end (owner, 2026-10-18: a
scrolling strip with labels above wasn't obvious); it opens on the family
of the colour in use, and switching Base/Veins switches to that colour's
family — pinned under the preview, so the stone stays in view while
colours are chosen (owner, 2026-10-17) — and the slab photo. It opens from Stone pieces → This area's stone and from
the swatch on each stone piece's row (owner, 2026-10-17), where "Same as the
area's stone" is offered. In 3-D (`Room3DScene.stoneMaterial`) each piece is
drawn in its look (`StoneKeys`: the stone keys with their looks, passed where
a `Set<String>` used to be), about 3′ of pattern repeated (a slab photo
mirrored instead, since it doesn't tile), polished ones shiny. The plan and lists still use `StoneLook.color` (#E9E6E0).
`StoneLookTests`.

**How tile looks** (owner's design, 2026-10-18; drawing and wording only,
never the price). A tile's `TileAppearance` (`TileChoice.appearance`; the
area's main tile keeps it in `EstimateSection.tileAppearance`, carried by
`mainTile`/`fullMainTile`/`setMainTile`; nil anywhere = drawn as before):
its colour, look (solid, handmade — a mottled glaze, from the concrete
map, with a thin soft band at each edge — marble, stone, wood, concrete,
terrazzo), a marble, stone or wood look's pattern (marble: soft, thin, bold
veins, web; stone: slate, quartzite, travertine — the stone picker's
real-stone maps; wood: straight grain and rustic, ambientCG Wood049 and
Wood096, owner, 2026-10-18: the drawn grain wasn't realistic; slate is
ambientCG Rock020; all CC0, patterns the stone picker doesn't list) and
veins colour, its grout (Laticrete
PermaColor's 40 colours by name and Laticrete's on-screen values,
`TilePalette.grouts`, owner's grout; or any colour), variation (V1–V4, the
rating on the box: how much tile to tile differs), finish (matte or gloss,
gloss shining in 3-D; owner, 2026-10-18 — a satin saved for a day reads as
matte) and its name in My Tiles (`TileLibrary`, like My
Stones, keeping the whole tile — material, size and layout too). Drawn in
`TilePattern.make`: each tile its own patch of the look's texture at the
stone's real size (wood: 4′ of board), never the same veins tile after
tile, and turned with the tile when its long side is up, so grain runs
along the plank. Tile, stone and
grout names are kept but not put in the estimate's description (owner,
2026-10-18: maybe listed under materials later). The picker
(`TilePickerSheet`, Sources/Views/Tile) opens from **Colour, look & grout**
(`TileLookRow`) under the tile choices on the Tile step and in every tile
sheet: what prices it on top with Change › back to those choices, a preview,
the name, wells (Tile, Veins for marble/stone, Grout) and family buttons
with one row of colours — tile: `TilePalette.families`, 53 colours in nine
families measured from 1,045 TileBar tiles (real tile is muted; purple left
out); grout: PermaColor's six families with names under each — pinned; then
look, pattern, variation, finish, My Tiles, Recently used and a photo of
the tile. Naming the grout's maker is a factual description (owner chose
names, 2026-10-18); its swatch values are facts; Laticrete's own images
aren't used. `TileLookTests`.

In 3-D a niche's stone parts are ¾″ slabs — back, jambs and header lining
the opening, the sill lipping ½″ past the face, divider shelves ¾″ — so
straight on their edges show as a frame (owner, 2026-10-14). A wall drawn
as its face alone (the room's outside walls) has a grey footprint at the
floor, so when it drops away the floor under its thickness doesn't show
(it showed as a strip of floor tile behind a bench).
A bench's back (against its wall) is never tiled in 3-D, and wall tile
running into an inside corner stops at the other wall's face, not its line
(`insideCornerInset`), so a dropped-away wall leaves no strip of tile.
Drawing only: square feet still run to the lines.
