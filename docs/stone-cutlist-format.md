# Stone cutlist format (version 1)

The file TileRate sends to FabSpecPro: an estimate's stone pieces, sized to
order. It is a public contract between the two apps. FabSpecPro owns it
(it accepts the files); TileRate writes it. Either app may change owner, so
nothing here depends on a developer account, App Group or shared container.

Agreed with the owner on 2026-10-16.

## How it travels

1. **Link** (one tap, FabSpecPro installed): TileRate opens
   `fabspecpro://import?cutlist=<compact JSON, zlib-compressed (raw DEFLATE), as base64url without padding>&z=1`.
   (Without `z=1` the data is plain JSON; FabSpecPro reads both.)
   If nothing opens it, TileRate says FabSpecPro isn't installed and offers
   the file or a spreadsheet instead (the App Store page once FabSpecPro has
   an App Store ID).
2. **File** (share sheet, AirDrop, Files): the same JSON in a file named
   `<customer> stone cutlist.stonecutlist`. FabSpecPro registers the type.

The scheme (`fabspecpro`) and extension (`stonecutlist`) are chosen to
outlast the bundle IDs, which change when the apps move to the LLC's
developer account. Only the file type's identifier will carry the LLC's
domain.

## The JSON

```json
{
  "format": "stone-cutlist",
  "formatVersion": 1,
  "source": { "app": "TileRate", "appVersion": "1.0" },
  "exportID": "UUID, new for every export",
  "exportedAt": "2026-10-16T21:30:00Z",
  "units": "inches",
  "estimate": { "id": "UUID, the same for every export of this estimate", "number": 1443, "title": "Carlton", "date": "2026-10-15T13:23:00Z" },
  "customer": { "name": "Carlton", "address": "", "address2": "", "cityStateZip": "" },
  "pieces": [
    {
      "id": "curb#0#Top#",
      "name": "Curb A Top",
      "group": "Curb",
      "type": "curbTop",
      "shape": "rectangle",
      "lengthIn": 53.75,
      "widthIn": 7,
      "thickness": { "value": 3, "unit": "cm" },
      "edges": "Polished",
      "quantity": 1,
      "notes": []
    }
  ]
}
```

- **estimate.id**: never changes for an estimate (added 2026-10-17), so a
  cutlist sent again updates the same project. Match on it first; the
  estimate number can change between sends and repeat across devices.
- **customer**: name and address only (no phone or email; FabSpecPro has no
  place for them).
- **id**: unique within the export and the same across exports of the same
  estimate, so a later import can update a project.
- **name**: never contains a size. When more than one area of the estimate
  has stone, it starts with the area ("Shower 2 - Niche Jambs", a plain hyphen).
- **group**: Curb, Wall, Door, Window, Niche, Ceiling, Floating bench,
  Framed bench, Corner pieces.
- **type**: TileRate's part (`curbTop`, `curbOutside`, `wallCap`,
  `nicheJamb`, `framedBenchTop`, `cornerShelf`…); informational.
- **shape**: `rectangle`, or `rightTriangle` (corner shelves, seats and
  footrests), whose `lengthIn` and `widthIn` are the two legs.
- **lengthIn / widthIn**: decimal inches, to the sixteenth, sized to order.
- **thickness**: value and unit (`cm` or `in`). 3 cm unless set in TileRate's
  Admin; a niche back 2 cm.
- **edges**: the edge finish to put on every edge, by the name FabSpecPro's
  Edges library uses: "Polished" for now (the spreadsheet says "All Edges
  Polished"). When TileRate has edge profiles, the profile's own name.
- **material**: absent until TileRate has material choices; then a string.
- **quantity**: identical pieces of one thing are one row.

### Reading rules (for FabSpecPro)

Read leniently: a missing or unknown field never fails an import; unknown
fields are ignored. Refuse, with a clear message, a `formatVersion` newer than
supported, and keep reading older versions. Imports only add.

## Names

Letters go by the order things were added, per area, only when there's more
than one: "Niche Jambs", or "Niche A Jambs" and "Niche B Jambs"; "Curb A
Top" and "Curb B Top" on a corner shower. The room's own doors and windows,
which the scanner found, are lettered by wall letter, then along the wall.
A matching left and right is one row ("Entry Jambs", Qty 2); otherwise each
its own ("Entry Left Jamb"). Identical corner pieces are one row ("Corner
Shelves", Qty 2).

## Sizes (ordered long, trimmed at fabrication)

| Piece | Length | Width |
|---|---|---|
| Curb top | From the wall's face along the curb; at a corner of two curbs, on through the other curb (4½″) and past its overhang to the far edge of the other top | Admin (else 4½″) |
| Curb outside face | The curb's length; at a corner, also past the other outside face's thickness | Admin (else the curb's height) |
| Curb inside face | The curb's length | Admin (else the curb's height) |
| Jambs: entry, door, window, niche | Full height (curb, floor or sill to header or ceiling) | Admin (else the wall's thickness; a niche's 3½″ depth) |
| Headers, sills, niche base shelf and dividers | Full width of the opening | Admin (else as jambs) |
| Niche back | Niche width × height | 2 cm thick; the niche's other pieces lose its thickness from their width |
| Half wall cap | The half wall's length + ¾″ past each free end | Admin (else the wall's thickness) |
| Half wall end | Floor to cap | Admin (else the wall's thickness) |
| Framed bench front | Bench length × height | |
| Framed bench end | Bench depth × height | |
| Framed bench top | Bench length + the end's thickness (¾″ if tile) + overhang, where it meets the entry | Bench depth + the front's thickness (¾″ if tile) + overhang (Admin, ¾″) |
| Floating bench top | Wall to wall | Bench depth |
| Ceiling header, dropped header underside | Wall to wall (over a corner curb, to the far edge of the other) | Admin (else 4½″) |
| Corner shelf, seat, footrest | Right triangle, legs its size | |

TileRate prices stone from these same sizes, so the estimate and the cutlist
agree.

## The spreadsheet (CSV)

Free in TileRate, for anyone: one row per piece, decimal inches.

`Piece,Group,Type,Shape,Length (in),Width (in),Thickness,Edges,Qty,Notes`

A Material column will be added when TileRate has material choices. There is
no PDF: a drawing of each piece is FabSpecPro's.
