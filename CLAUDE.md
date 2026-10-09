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
within 1½″ to those lines and to other walls' ends, an end onto a wall it
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
near walls drop away whichever way it's turned. A partition (a scanned wall
with an end partway along another, `isPartition`) is drawn solid, both faces
showing; tile, niches and benches on a scanned wall go on the side toward
their area's floor (else the room's middle) — a shower behind a partition
had its tile on the room side (fixed 2026-10-08). Views: into this area
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
  "96" would collapse the room. The room stays joined: a wall sharing a corner stretches to
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

## Placing a shower, curbless showers and drains (owner's calls, 2026-10-08)

- **Put the shower here** (`AreaTakeoff.placeShower(near:in:curbWidthFt:)`):
  a tap inside a cove of three walls (`ScannedRoom.cove(around:)`: a back
  wall, a wall each side running out from it, 2–10′ each way along the
  room's square directions, the open side free of walls) fills the cove;
  the curb's outside face is flush with the cove's outside corners, so the
  floor stops at the curb's inside face (`coveDepthFt` keeps the cove's
  depth). A tub in the cove doesn't matter (a conversion). Anywhere else,
  48″ × 48″ in the nearest inside corner (no longer the last size, or 60″ × 36″).
- **The curb** is drawn (plan and 3-D) just outside the floor's open sides,
  always 4½″ wide (`StonePrices.curbWidthFt`; Admin's stone curb width is the
  stone on top, which overhangs the curb, so it isn't used for this;
  benches use it too).
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
