# Pen Lucy Precinct: worker report

Deliverable: `godot/scripts/city/city_civic_police.gd` (no other project files touched).
API: `static func build() -> Node3D` and `static func footprint() -> Vector2` (returns `Vector2(24, 20)`).
Built entirely with the root-owned `city_civic_mesh_kit.gd` (`material`, `box`, `cylinder`, `triangle`,
`solid_box`, `solid_convex`, `label`, `finish`). There are no per-frame callbacks, lights, emission or
`class_name`.

**Not engine-validated.** Per the brief I did not launch Godot, so nothing has been parsed, run or
rendered. Everything below comes from reading the code and counting by hand. The root's parse and render
checks are still needed.

## Frame and placement
- Local origin is the footprint centre at ground level, y = 0. FRONT (the street) faces +Z.
- Footprint is x -12..12, z -10..10. The geometry reaches x ±11.96 (the cornice cap) and z -9.99..+9.98.
  Every step, landing, bollard and the flagpole is inside the footprint.
- The plinth, wall skins and walk slabs run down to y -0.6 and -0.3, so a slightly sloped surveyed site
  shows no gap under the building. The walk meets grade with a 3 cm lip at its street edge (z 9.98).
- Metadata on the returned root (local coordinates):
  - `entrance`: (0, 0.12, 7.0), the vestibule floor in front of the doors
  - `approach`: (0, 0.03, 9.58), the street end of the walk
  - `front_normal`: (0, 0, 1)
  - `footprint`: (24, 20)
- Both side elevations are fully dressed, so the separate parking lot can be on either side. The rear has
  the sally-port door.

## Dimensions
| Part | Plan (m) | Heights (m) |
|---|---|---|
| Office block (two storeys) | 23.2 x 10.4 (x ±11.6, z -3.4..7.0) | ground-floor windows 1.30-3.40 / belt course 4.78-4.95 / upper windows 4.95-6.75 / frieze 7.35-7.70 / cornice 7.70-8.00 / roof deck 8.30 / parapet coping 8.90 |
| Entrance pavilion | 7.8 wide, projects 0.9 (to z 7.9) | quoins; attic to 9.90 + coping 10.02; crest with datestone to 10.42 |
| Raised hall behind the attic | 7.8 x 6.3 (z 1.6..7.9) | deck 9.55, coping 10.02 |
| Recessed vestibule | 3.2 wide x 1.7 deep | floor 0.12 (flush with the walk), clear height 3.38; two 0.97 m door leaves (2.42 high), sidelights, transom |
| Entry walk | full building width, z 7.0/7.9..9.98 | 0.12 at the vestibule down to 0.03 at the street edge: about 1:23 (4.3 %), no steps, no rails needed |
| Service wing (one storey, sally port) | 22.5 x 6.3 (x ±11.25, z -9.7..-3.4), inset 0.35 m each side | roof 4.55, coping 5.17; overhead door 3.6 x 3.3; staff door 1.1 x 2.23 on a flat landing at 0.12 |
| Stair bulkhead | 3.2 x 3.2 (x -7.6..-4.4, z -3.0..0.2) | 10.97; radio mast and whips to about 17.9 |
| Rooftop units | 2.4 x 1.8 and 2.8 x 1.8 on 0.25 m curbs | tops about 9.8 / 9.7, fan shrouds about 9.9 |
| Flagpole | stone base 0.9 x 0.9 on the west middle bay axis | about 9.6 |

## Design
This is a Baltimore station house in the 1920s-30s Colonial Revival civic manner: robust red-brown brick,
pale limestone trim and a symmetrical street front. It also echoes the original game's Precinct 9 (navy
POLICE panel, blue globe lamps, quoins, keystones, a raised parapet, roof AC units and an antenna).
- **Volumes and setbacks**:
  - the office block
  - the 0.9 m entrance pavilion
  - the raised hall and attic, with a stepped crest
  - a lower service wing, inset on both sides
  - the rooftop bulkhead
  The roof line steps 5.2 → 8.9 → 10.0/10.4 → 11.0 m, with the mast above.
- **Organized fascia**: continuous stone courses run around the whole block and pavilion:
  - plinth (pale stone, 0.95 m above grade)
  - water table
  - belt course (the sill line of the upper windows)
  - frieze
  - cornice on modillions, and its cap
  - brick parapet with stone coping
- **Window bays** (consistent sills, lintels and frames, with variation between types):
  - Front wings: three bays each, between brick piers, with corner piers wrapping onto the sides.
    - Ground floor: tall windows with a stone sill, stone lintel and keystone, a bronze mullion and
      transom, and a 4-bar grille set in the reveal.
    - Between floors: a recessed dark-brick spandrel panel.
    - Upper floor: windows standing on the belt course, with flat lintels.
  - Pavilion upper floor: a triple window in a stone architrave, with a keystone block running up into
    the frieze, flanked by two narrow lights.
  - Side elevations: the same bay rhythm, but with high ground-floor windows (sill at 2 m).
  - Back wall: four upper windows.
  - Service wing: a ribbon of three-light clerestories on three sides.
  - All glass sits 17 cm back in real reveals (holes cut in 25 cm wall skins), not painted onto the walls.
- **Entry**:
  - The vestibule is lined in stone, with a soffit downlight (geometry only, no light), an intercom plate
    and a recessed mat.
  - Bronze storefront double doors with sidelights and transom.
  - Outside: stone pilasters with bases and capitals, an entablature lettered PEN LUCY PRECINCT, and a
    blue police globe on a bracket each side (painted, unlit).
- **Signage** (2 labels, both facing +Z, kit font, `shaded = true` so they darken at night):
  - **POLICE**: cream capitals, about 0.78 m tall, on a blue attic panel (5.1 x 1.32 m) in a stone frame.
  - **PEN LUCY PRECINCT**: dark bronze capitals, about 0.31 m tall, on the stone entablature.
  - Each label's pixel size is fitted once at build time with `Font.get_string_size`, capped at 4.5 m
    and 4.3 m wide inside panels 5.1 m and 4.8 m wide. It is lifted using the font's ascent and descent so
    the capitals centre on their panel. The Barlow capital height is assumed to be 0.70 em.
- **Blue accent (subtle)**: the POLICE panel, the two globes and reflector bands on the four front
  bollards. Nothing glows or flashes.
- **Roof** (readable over the parapets from the street, and in detail from above):
  - bulkhead with a steel door and canopy, a louvre facing the street, and coping
  - radio mast with a crossarm, three whips and a dish
  - two rooftop units with louvre banks, condenser fan shrouds and a flue hood
  - mushroom exhaust fans, vents, a roof hatch and a conduit run
  - access ladder from the service wing roof over the coping
  - service wing roof: a condenser with its line set, a skylight and splash blocks under the leaders
- **Site** (no parking lot; that stays with the root): the graded walk with a stone street edge, four
  bollards across the entry, the flagpole, two corner security cameras, and two guard bollards at the
  overhead door.

## Budgets (static tally, not engine-measured)
- **Finishes and draw surfaces: 7**, one surface each in kit insertion order. Adding the 2 labels gives 9 draws.

  | Finish | Color | Kind | Roughness |
  |---|---|---|---|
  | brick | `8a4a3a` | 1 | 0.90 |
  | brick_dark | `6e3a30` | 1 | 0.90 |
  | stone | `d2cbb8` | 2 | 0.86 |
  | paving | `9c998f` | 2 | 0.92 |
  | bronze | `3b352f` | 6 | 0.85 |
  | glass | `1b222b` | 0 | 0.50 |
  | blue | `27427a` | 6 | 0.80 |

  The colors follow the neighborhood palette (brick_2 / brick_dark, curb stone, sidewalk, glass
  `1a2230`); weathering comes only from the shared shader.
- **Triangles: about 11.8k.** Kit boxes are 12 triangles, cylinders are 6 x sides (rings = 1), and the
  faceted spheres and walk slabs are built from kit triangles.

  | Section | Triangles |
  |---|---|
  | Front | 3070 |
  | Sides | 1750 |
  | Roofs | 2040 |
  | Service wing | 1310 |
  | Fascia | 1010 |
  | Entry | 930 |
  | Back | 880 |
  | Site | 710 |
  | Signs | 60 |
- **Collision shapes: 24**, all on the kit's single StaticBody3D (layer 2).
  - Office block (6 boxes): the volume up to the coping, carved around the open vestibule — the core
    behind the door line, two front strips, two pavilion piers and the head over the vestibule.
  - Vestibule floor (top at 0.12).
  - Raised hall.
  - Service wing.
  - Bulkhead.
  - Two rooftop units.
  - Rear staff-door landing.
  - Graded walk (3 convex wedges, so the walk is walkable with no step).
  - Bollards (6).
  - Flagpole (base and pole).

  Trim (cornices, sills, quoins, lamps, ladder, downspouts) has no colliders.
- **Labels: 2.**

## Suggested kit changes (not made; root-owned)
1. `label()` could take `shaded` (and maybe `alpha_cut = ALPHA_CUT_OPAQUE_PREPASS` to avoid sorting
   against glass and foliage). This worker sets `shaded = true` on the returned node.
2. A `glass` variant of `material()` using `city_glass.gdshader` (`Windows.glass_material()`), so civic
   windows match the neighborhood's glass response.
3. Optional cap flags on `cylinder()`, to skip hidden caps (bollard bottoms, mast and vent bases) and save
   triangles.
4. Small conveniences: `box_between(min, max, finish)` and a clockwise `quad()`.

## For the root to check
- The script parses (typed throughout; Variant values cast explicitly). The `Kit` type comes from a
  preloaded const.
- Label fit and the cap-height lift are correct in a render.
- Facing and placement are right after rotation. The labels are single-sided, +Z.
- Vestibule lining and soffit joints: coplanar faces were offset or hidden by design.
- The real triangle count from the mesh arrays.
- Site grading meets the exposed walk ends at x ±11.6 (0.03 to 0.16 m high) and the rear landing.
