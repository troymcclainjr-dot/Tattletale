# Courthouse report — `godot/scripts/city/city_civic_courthouse.gd`

Status: implementation complete. **Not engine-validated** — no Godot launch, import or test was run
(per brief). Static checks only (listed at the end). Root owns parse/render verification, integration,
site clearing and map registration.

## API
- `static func build() -> Node3D` — returns the kit root `PenLucyCourthouse` containing
  `SolidArchitecture` (StaticBody3D, layer 2, mask 0, 17 shapes), `BatchedArchitecture`
  (one MeshInstance3D, 9 surfaces) and one Label3D `CourthouseInscription`.
- `static func footprint() -> Vector2` — `Vector2(32, 26)` (X frontage by Z depth).
- Local frame: origin = footprint centre at grade (y 0); FRONT faces +Z. Everything (stairs, ramp,
  landing, rear stoop, cornice overhangs) lies within x ±16, z ±13.
- Optional metadata on the root (harmless if unused): `footprint`, `entrance` (0, 0, 10.6) foot of the
  main stairs, `door` (0, 0.6, 4.4) on the portico in front of the doors, `ramp_foot` (15.3, 0, 7.8)
  on the ramp's grade landing.
- Uses only existing kit methods: `material`, `box`, `cylinder`, `triangle`, `solid_box`,
  `solid_convex`, `label`, `finish`. No `class_name`. Shared kit untouched.

## Design
Neighbourhood district courthouse in the Baltimore Georgian/neoclassical revival manner, scaled to the
rowhouse street (wing parapets 9.2 m vs ~9-10 m rowhouses) rather than a palace:
- **Massing / setbacks.** Two two-storey red-brick wings (x 6.4..15.2 each side, z -8.6..2.4) flank a
  taller central block (|x| < 6.4, z -11..4) that projects 1.6 m forward of the wings and 2.4 m behind
  them. Central block cornice 9.85 m under a 17-degree slate gable (ridge ~11.97 m); wings have a
  stone cornice, brick parapet and stone coping (9.2 m) over a flat roof.
- **Portico.** Tetrastyle (four columns, x -6/-2/2/6, z 7) giant order, 0.84 m diameter, 7.6 m
  tall on square plinths: torus base, tapered shaft, echinus, abacus. Stone antae wrap the central
  block's front corners. Architrave + frieze + three-part cornice run continuously round the central
  block and over the portico (its soffit is the portico ceiling). Pediment: tympanum recessed 0.55 m
  behind raking cornices that stand proud of the slate, with a glazed stone roundel. Rear gable has a
  brick tympanum, matching rakes and a louvred vent roundel.
- **Sign.** One Label3D, `COURTHOUSE`, centred on the portico frieze (y 9.03, z 7.47, facing +Z),
  font 46 at 0.0105 m/px (~0.36 m caps, ~3.3 m long on a 12.9 m frieze), dark bronze `3b3226`,
  `shaded = true` so it does not glow at night.
- **Facades.** Every window is a real opening: masonry skin boxes around the holes (0.22 m reveal)
  in front of an interior mass, painted sash frame, recessed glass, meeting rail and centre bar,
  stone sill carried into the reveal. Brick walls get flat-arch stone lintels with keystones; the
  stone portico face gets full architrave surrounds, and the centre upper window a cornice hood.
  Ground windows 1.25 x 2.5 m (sill 1.5), upper 1.25 x 2.2 m (sill 5.2): 3 bays per wing front/rear,
  4 per wing side, 2+3 on the portico face, 2+3 on the rear around a service door, one narrow bay on
  each flank of the rear projection. Granite water table (to 1.25) with stone cap (1.4), stone string
  course (4.45-4.75), wing frieze band (7.85-8.2), stone quoin strips on outer corners.
- **Entrance.** Bronze double doors (raised panels), stone transom bar, glazed transom with muntins,
  stone architrave and cornice hood. Terrace/portico floor at 0.6 m in stone paving with a nosing.
- **Stairs.** Four 0.15 m risers, three 0.45 m marble treads, 11.6 m wide (x ±5.8, z 8.8..10.15),
  flanked by granite pedestals with stone caps and iron lanterns (no lights).
- **Accessible ramp.** East (+x) of the terrace: 0.6 m over 7.2 m = **1:12**, 1.5 m clear
  (z 7.05..8.55), granite guard walls with stone coping and a rail at 0.95 m on four posts each side,
  level 1.4 m grade landing (x 14.6..16) open to the forecourt. A granite raised planter with stone
  coping and clipped hedge mirrors it on the west.
- **Rear.** Service door on the rear projection with a three-tread marble stoop and iron rails.
- **Roof readability.** Slate gable with stone rakes; cupola on the ridge at z -1.5 (painted base,
  louvred belfry with corner posts, entablature, octagonal copper dome, finial; top ~17.7 m), placed
  so the dome clears the pediment from ~25 m out on the street axis; brick chimneys with stone caps
  and pots on each wing (top ~11.75 m, ~0.7-1 m visible over the parapet from 25 m); rooftop
  condenser on the east wing (seen from side/rear streets).
- **Grounds.** Granite-paved forecourt to the front boundary (top y 0.03), lawn panels (y 0.04) and
  box hedges along the wing bases. Plantings are decorative/non-blocking, matching yard hedges.

## Dimensions (local metres)
| Element | Extent |
|---|---|
| Wings (each) | x 6.4..15.2, z -8.6..2.4; cornice 8.6, parapet coping 9.2 |
| Central block | x -6.4..6.4, z -11..4; cornice top 9.85, ridge 11.97 |
| Portico | columns z 7 (x ±2, ±6), entablature front z 7.5, pediment rake front z 7.95 |
| Terrace | x ±7.4, z 2.4..8.8, top 0.6 |
| Stairs | x ±5.8, z 8.8..10.15 |
| Ramp / landing | x 7.4..14.6 (1:12) / x 14.6..16, z 6.8..8.8 |
| Planter | x -14.6..-7.4, z 6.8..8.8, coping 1.13, hedge to 1.7 |
| Rear stoop | x ±1.5, z -12.8..-11 |
| Cupola | 2.7 m square base at z -1.5, dome 2.2 m, finial top 17.7 |
| Overall | 32 x 26 footprint fully used for forecourt; building 30.4 m wide x 18.5 m deep incl. portico |

## Budget
- **Triangles: ~9,450** (hand tally; kit box = 12, cylinder = 6 x sides): masses/bands 360, wall
  skins 1,344, windows 4,056, quoins/antae/hood 156, portico (columns 1,056, pediment, roundel) 1,280,
  roofs/chimneys/condenser 508, cupola 472, approach (terrace, stairs, pedestals, lanterns, ramp,
  planter, main doors) 926, rear entry 230, grounds 120. Under the 12k target.
- **Draw surfaces: 9** (one per finish; all nine are used, so no empty surface is committed).
- **Collision shapes: 17** in the kit's single StaticBody3D (layer 2):
  wings box, central block box, terrace box (to z 8.575), stair slope (convex; plane through the
  tread midpoints, 18.4 deg, within 7.5 cm of every tread, meets the terrace top without a lip),
  2 stair pedestals, 2 terrace parapets, 4 columns (0.96 m boxes), ramp slope (convex, 4.8 deg),
  2 ramp guards (convex, wall + rail height 0.95 m), planter box, rear stoop (one convex: landing +
  26.6 deg slope). All slopes are below the player's 48 deg floor limit; no per-step colliders, no trim.
- **Labels: 1.** No dynamic lights, no per-frame processing, no class_name.

## Finishes (city_surface shader, world-space weathering)
| id | kind | colour | roughness | use |
|---|---|---|---|---|
| brick | 1 brick | 8c4a3a | 0.90 | wall skins, parapets, chimneys, rear tympanum, interior masses |
| stone | 2 concrete | d4ccbb | 0.86 | portico, columns, entablature, cornices, dressings, stairs, paving |
| granite | 2 concrete | 8f8b83 | 0.90 | water table, terrace/ramp/planter walls, pedestals, forecourt |
| trim | 6 trim | eeeadf | 0.82 | sash frames, rails, bars, cupola woodwork |
| glass | 0 plain | 1c232c | 0.60 | dark matte glass, roundel, lanterns |
| slate | 0 plain | 4a4e55 | 0.80 | gable and flat roofs (like the city's untouched roof finishes) |
| copper | 4 paint | 6d9283 | 0.70 | cupola dome/finial (streaks + exposed patches read as patina) |
| metal | 0 plain | 2c2a27 | 0.55 | bronze doors, rails, posts, belfry louvres, pots, condenser |
| planting | 5 earth | 4f6b36 | 0.95 | lawns, hedges |

## Notes for root / suggested kit changes (not made)
1. `label()` could take a `shaded` flag; I set `shaded = true` on the returned Label3D.
2. `finish()` could skip committing empty SurfaceTools (not an issue here: all materials used).
3. A shared `quad()` / convex `prism()` helper (I wrote local `_facing`, `_hexa`, `_beam`, `_gable`,
   `_slab_z` on top of `triangle()`, auto-oriented per triangle so winding cannot be wrong) and a full
   rotation on `box()` would help the other civic buildings with sloped members.
4. `triangle()` normalises a zero vector for degenerate input; my helpers never pass degenerates.
5. Ground pieces (forecourt y 0.03, lawns y 0.04, all extending to y -0.3) assume root grades the pad
   to y 0. If root lays its own plaza/sidewalk over the footprint, drop or lower `_grounds()` to avoid
   coplanar fighting. Foundations extend to y -0.6 to hide small grade differences.
6. If NPC navigation needs it, root's clearance polygon should cover the whole 32 x 26 footprint
   (the forecourt is walkable; the building, terrace edges, ramp guards and planter are solid).

## Static self-checks done (no engine)
- Tabs-only indentation; every `:=` infers from a typed expression; Variant loop values are assigned
  to explicitly typed locals; typed arrays are always declared before being passed.
- Every kit call matches the kit's signatures; all nine materials declared before use and all used.
- Footprint bounds checked for every element; columns, rakes and the cupola checked for clearances.
- Coplanar overlaps only occur between same-material faces (identical world-space shading) or are
  hidden inside masses; glass sits 1.5 cm proud of the sash frame, dressings 4-13 cm proud of walls.
