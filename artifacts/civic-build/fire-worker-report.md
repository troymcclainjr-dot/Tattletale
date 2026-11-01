# Fire station report: `godot/scripts/city/city_civic_fire.gd`

I haven't run it in the engine. I didn't launch Godot, parse the script, render it or run the tests. The checks I did:
I read the code by hand, checked every helper/kit call's argument count and the indentation with Grep, and worked out
the budgets and bounds by hand. The root still needs to parse it, render it and run `tests/city_civic_models.gd`.

## API and contract
- `static func build() -> Node3D`, `static func footprint() -> Vector2` returns `Vector2(18, 17)`. No `class_name`.
- Local origin is the footprint center at finished floor Y=0. FRONT faces +Z. All visual geometry stays within
  X [-9, 9] and Z [-8.5, 8.5], including the stairs/ramp, cornices, eaves and hoods (the test allows 0.1 m extra).
- Uses only the existing kit methods: `material`, `box`, `cylinder`, `triangle`, `solid_box`, `solid_convex`, `label`, `finish`.
  `Kit` is typed through `const Kit = preload(...)`, as `city_civic_hospital.gd` does.
- Metadata on the root, in the same form as the hospital: `civic_type="fire"`, `footprint_m`, `front_local=(0,0,1)`,
  `ground_y=0`, `storeys=2`, `apron_local_xz=Rect2(-4.8, 3.6, 13.8, 4.9)` (x, z, width, depth).
- `Marker3D` anchors (meta `use`, `clear_width_m`, `clear_height_m`, `approach_local=(0,0,1)`), there for future trucks:
  `ApparatusBay1` (-1.3, 0, 3.65) and `ApparatusBay2` (4.3, 0, 3.65), both `fire_apparatus`, 4.2 m wide x 4.2 m clear;
  `PersonnelEntrance` (-6.75, 0.14, 4.2), `pedestrian`.

## Design
A compact two-bay Baltimore engine house. The hose tower and a two-storey office wing hold the corner on local -X.
Under the root's current plan (yaw = pi) that is world east, where the demolished corner row Row_328 stood. The
preserved neighbor Row_327 is on local +X.
- **Apparatus block** (two storeys): two red six-section overhead doors set 0.35 m behind brick piers. Each door has
  raised panels, dark seams, a row of four small dark lights in the upper section, steel jambs and header, and an
  exposed steel lintel. The piers have stone imposts and a gray base. A continuous stone belt runs over both bays as
  the lintel, with a keystone over each bay. Above it, in the frieze, is a framed cream stone panel reading
  **ENGINE HOUSE** in dark letters. Above that: the sill course, five double-hung quarters windows (stone lintels and
  keystones), a dark-brick band and a three-step corbelled cornice. On top are a coped parapet and a stepped center
  parapet with a **PEN LUCY** panel. A narrow watch window with a transom sits in the wide right pier.
- **Hose tower** (front-left, 0.2 m proud of the front and the side):
  - **Base:** the personnel entrance.
  - **Middle:** windows aligned with the apparatus courses.
  - **Recessed upper panels:** a stone roundel with a red Maltese cross faces the street; a stair slit window faces the side street.
  - **Drying loft:** louvered openings on all four faces.
  - **Top:** stone bands, a corbelled cornice, an eave board, a hipped cap, and a finial with a lightning rod.
- **Personnel entrance:** red door with a vision light, a transom, a stone threshold, stone pilasters and an
  entablature reading **FIRE DEPT**, a metal canopy on tie rods, and two wall lanterns (geometry only, no lights).
  It has an accessible landing 0.14 m up with a 1:12.5 ramp to the walk. The rise is under 150 mm, so no handrails.
- **Office wing** (two storeys, behind the tower along the corner side): three bays facing the side street and one at
  the rear. Tall ground-floor windows with transoms, quarters windows above, the same courses, and a parapet 0.6 m
  lower than the main block.
- **Rear annex** (one storey): high windows, two steel service doors with stone lintels, drip hoods and lamps,
  downspouts with leader heads, and a corbelled parapet.
- **Roof equipment you can see from the street and side:**
  - **Main roof:** a red siren with two horns on a 3 m mast (top about 12.3 m), a radio mast (top about 13.4 m), a
    packaged HVAC unit on a curb with fans and a grille, two mushroom exhaust fans, and a roof hatch.
  - **Annex roof:** a condensing unit and two apparatus exhaust stacks with rain caps.
  - **Office roof:** a skylight and a vent.
- **Forecourt:** a flush concrete apparatus apron (X -4.8..9.0, Z 3.6..8.5, top Y 0.012) with a trench drain, an
  entry walk, and narrow side and rear walks. All visual only, with no collision. The root foundation (top -0.015)
  is the walkable floor.

How it's built: every volume is a brick core behind facade skins. `_fill()` builds each skin around its openings
from merged rectangular runs, so windows and doors sit in real reveals: 0.18-0.4 m deep, with dark frames, sashes,
meeting rails, sills, lintels and keystones. They aren't decals. Where faces met, they were offset so no two
different finishes share a plane: window sills stand 1 cm proud of the sill course; the steel lintel covers the
recess soffit over each bay; the loft skins stop at the stone impost; the door has a threshold block.

## Dimensions (local metres)
| Volume | X | Z | Height |
|---|---|---|---|
| Apparatus block | -4.8..8.7 | -4.4..4.0 (front plane; doors at 3.65) | roof 8.91, parapet 9.42, stepped crown 10.22 |
| Hose tower | -8.7..-4.8 | 0.3..4.2 | cornice 14.36, eaves 14.44, apex 16.25, rod 17.46 |
| Office wing | -8.5..-4.8 | -8.2..0.3 | roof 8.36, parapet 8.82 |
| Rear annex | -4.8..8.5 | -8.2..-4.4 | roof 5.21, parapet 5.67 |
| Apron (visual) | -4.8..9.0 | 3.6..8.5 | top 0.012 |
| Landing + ramp | -8.35..-5.15 | 4.2..7.2 | landing 0.14, toe 0.012 |

- **Bays:** each door is 4.2 m wide x 4.3 m high (4.2 m clear under the header). Piers are 1.4 / 1.4 / 2.3 m, and the
  bays are centered on X -1.3 and 4.3.
- **Shared datums:** base course to 0.55, belt 4.3-4.75, sign frieze 4.75-5.75, sill course 5.75-5.9, upper windows
  5.9-7.6, cornice 7.95-8.6.

## Budgets (estimated from the code; please confirm in the engine)
- **Triangles:** about 8.3k. Apparatus about 2.2k, doors about 1.0k, tower about 1.8k, entry about 0.35k, office
  about 1.1k, annex about 0.65k, roof plant and downspouts about 1.2k. All boxes are 12 tris; cylinders are 6 x sides (rings=1).
- **Draw surfaces:** 9 batched finishes, plus 3 Label3D (ENGINE HOUSE, PEN LUCY, FIRE DEPT), all on the +Z front,
  dark INK `2b201b` so they don't glow at night.
- **Materials** (all `city_surface`):

  | Finish | Kind | Color | Used for |
  |---|---|---|---|
  | `brick` | 1 | `8a4a3a` | walls |
  | `brick_dark` | 1 | `6e3a30` | corbels, band, tower panels |
  | `stone` | 2 | `dbcfb2` | cream lintels, sills, belts, coping, sign panels, surround, roundel |
  | `concrete` | 2 | `9a968c` | base course, apron, walks, landing, curbs |
  | `roof` | 0 | `3e3e44` | membranes, tower cap |
  | `red` | 6 | `b02a22` | bay doors, personnel door, siren, cross |
  | `frame` | 6 | `2c332f` | frames, jambs, louver backs, canopy, lanterns |
  | `glass` | 0 | `1c2328` | dark matte glass, roughness 0.5 |
  | `metal` | 6 | `8b9093` | louvers, roof plant, masts, downspouts |

- **Collision:** 9 shapes, the main masses plus the accessible entrance only:
  - apparatus mass to the door plane
  - three bay piers
  - the wall over the doors
  - tower
  - office wing
  - rear annex
  - one convex landing+ramp
  - The bay recesses can be walked into up to the doors. There's no collision on the apron, trim or roof plant.
    The landing is 0.14 m, under the player's STEP_HEIGHT of 0.28.
- No per-frame processing, scripts on nodes, or dynamic lights.

## For root
- **Apron gap:** `pen_lucy_civic_build.json` puts the fire site center at z=137 with yaw pi. Its apron runs to world
  z=125, and its contract assumed a 24 m deep envelope with the front at local z=12. With 18 x 17 m, my footprint's
  front edge lands at world z=128.5, leaving a 3.5 m gap to the root apron. To close it, either move the center to
  z=133.5 or extend the root paving to z=128.5. The 24/18 and 24/17 scale clamp stays at 1.0.
- **Foundation:** your `_foundation()` covers the whole footprint (top -0.015). The skins and base courses start at
  -0.05, so there's no visible seam on graded ground.

## Suggested kit changes (not made; I used the existing methods)
1. A full `rotation: Vector3` on `box()` like `cylinder()`, for pitched louver blades, sloped rails and arch voussoirs.
   The ramp and the tower cap are hand-wound triangles for now.
2. A `quad(a, b, c, d, finish)` helper with the same winding fix as the district's `_ground_triangle`.
3. `label()` options for `shaded` and `alpha_cut`. Unshaded cream labels stay at full brightness at night.
4. A small `stats()` (triangles, shapes per surface) so the civic tests can report budgets without walking the arrays.
