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
the scanner split are merged back, `mergingStraightRuns`; lettered A, B…
round the room, each running with the room on its right), doors, windows and
openings (wall, width, height, height off the floor, position along the
wall), the floor outline and area, and the bathtub's outline.

Each area keeps its own choices (`EstimateSection.scanTakeoff`,
`AreaTakeoff`): pieces of walls (a stretch along one wall, from/to in feet
from the wall's start, and a tile height in inches — so a shower wall that
continues into the room is two pieces, one per area), the openings ticked to
come off (owner's call: nothing comes off unless ticked; only the part of an
opening inside a piece), and the floor (scanned floor less the tub and other
areas' floors, or width × depth for a shower floor) and ceiling.
A shower floor is drawn on the plan (`FloorSource.drawn`, `FloorRect`:
a corner, two side directions, width and depth), placed in the corner its
walls make (`suggestedFloorRect`) and dragged to size: green handles on the
plan for width, depth and moving, sides snapping to the inch and to walls
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
length rounds to the inch and stops on a wall it nearly reaches
(`snappedToWall`, `plannedEnd`). A planned wall (`Wall.planned`,
`thicknessIn`, starting from `Rates.kneeWallThicknessIn`, 4½″, Admin → Knee
walls) is dashed and as thick as it will be; it is saved with the scan, so
every area sees it. It has two faces (`Piece.face`, named by the wall each
looks toward). A planned wall as high as the ceiling is a full wall ("New
wall F", `isKneeWall` false), with no cap. A wall drawn in a shower along an open
side of its floor (roughly parallel, within 2′) snaps onto the curb line
(`snappedNewWall`, `newWallLines`; owner asked 2026-10-07). Tapping the curb
on the plan, or "Add a wall on the curb" under Shower entry, adds one with no
drawing (`closeSide`): a full wall with a door in its middle, or a knee wall
from the side's end against a wall, leaving a door's width open. Its first
face looks into the shower and is tiled. Adding a wall where a drawn-in one already lies
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
20″. A bench runs along the shower floor's side against its wall
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

Every stone piece (`StoneItem`: curb, cap & header, jambs, bench top, bench
front, niche, window) has a `StoneRate` in Admin → Stone pieces
(`Rates.stoneRates`, `stoneRate(_:)`/`setStoneRate`; curb, cap and jamb fall
back to their old per-foot fields): per linear foot, a usual width, and —
once a width is set — per square foot instead (length × width). The floor's open sides
(`openSides`) are each edge less the stretches walls run along, so a knee
wall across part of the front leaves the rest as the entry, with its curb
and jambs. A selected planned wall has a move
handle in its middle (`movePlannedWall`): whole inches, its line snapping
within 3″ to those lines and to other walls' ends, an end onto a wall it
nearly touches. Its ends drag on the plan; height, thickness and
length can be typed; it can be deleted.

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
Curb height: Admin (4″), per shower in the editor. A knee wall outside a
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
curb, stone in a stone colour, and the fixtures the scanner found
(`ScannedRoom.fixtures`, kept from 2026-10-07 scans on; switchable). The
room's own walls are drawn from inside only, like a doll's house, so the
near walls drop away whichever way it's turned. Views: into this area
(from its open side) and the whole room; turn and pinch by hand. In 3-D, **Place** (shower) picks a door, window,
niche, corner piece or bench, then a tap on a wall puts it there (`tap3D`,
`Room3DHit`: scene nodes are named "wall|id" and "item|id"): a niche or
window centred on the tap, a corner piece in the nearer corner at the tapped
height, a bench along that wall, a door at that spot (moving the wall's door
if it has one). Without Place, tapping a wall or item chooses it, and the
face-on drawing below fine-tunes it; the chosen item is lit up.

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
untouched). The layout preview doesn't show them.

The editor (`ScanEditor`): floor plan on top (`PlanCanvas`: tap a wall,
pinch to zoom round the fingers, drag to pan, double-tap or Fit to reset;
this area's tile blue, other areas' orange), the chosen wall face-on below
(`WallElevation`: drag a piece's sides and top; ends snap to the inch and to
corners, openings, the tub and other areas' ends; tap a door or window to
take it off), height chips, From/To/Height typed in inches, Add tile,
Split, Remove tile. A new piece takes the wall's longest free stretch at a
starting height (backsplash 18″, tub 84″, else full height). The scanner
only runs on a real LiDAR iPhone; in DEBUG builds without LiDAR a "Use a
sample room" button loads `ScannedRoom.sample` to try the editor.
`RoomScanTests` covers the arithmetic.

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
