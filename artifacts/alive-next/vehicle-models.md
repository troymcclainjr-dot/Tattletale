# Six new neighborhood vehicle models — implementation report

Worker: Opus 5.5 (vehicle models). Date: 2026-10-31.
**Status:** the code is written and statically reviewed. **I have not run it.** Godot and Blender were not launched, nothing was rendered, and nothing was committed. The root agent runs every test listed under *Validation*.

## What was added

Six prototypes in the existing `CityCarModels.prototype()` / `make()` API, alongside the existing `box_sedan`, `compact` and `minivan`:

| kind | label | silhouette features (actual geometry) |
|---|---|---|
| `hatchback` | Compact five-door hatchback (2000s) | Short 4.06 m body. Wedge beltline, raked hatch backlight with a roof spoiler, short overhangs, body-colour bumpers with a lower intake. |
| `midsize_sedan` | Midsize four-door sedan (2000s) | Rounded nose, fast windscreen, arched roof over three roof stations, short decklid. Blackout pillars give a flush-glass look. Body-colour bumpers. Small quarter glass. |
| `long_sedan` | Older full-size long sedan (early 1990s) | Wide (1.94 m) and low (1.42 m). Long hood and strongly rounded "whale" ends. **Skirted rear wheels.** Chrome bumpers, chrome side strip and a slatted chrome grille. Darker landau-style roof shade, small opera windows, 8-slot chrome wheel covers. |
| `pickup` | Compact regular-cab pickup (1990s) | Regular cab with a vertical back window. **Open long bed** with side walls, floor, wheel tubs, tailgate and a chassis rail visible under the bed. Tall vertical tail lamps on the bed walls. Chrome grille surround, step bumper, two-tone lower body, tall mirrors. |
| `cargo_van` | Panel cargo van | Tallest model at 1.98 m. Short sloped hood, side glass only in the cab doors, blank cargo sides. **Kerb-side (-X) sliding-door shut lines.** Two rear doors with split rear glass and a centre seam. Black bumpers, steel wheels with lug detail. |
| `compact_suv` | Compact SUV with tailgate spare (2000s) | High ground clearance. **Black lower and wheel-arch cladding** comes from vertex shades. Near-vertical tailgate with a **mounted spare tyre**, low roof rails, blackout pillars, three side windows. |

None of these is a palette swap. Each has its own lofted lower body, greenhouse stations, deck profile, wheel arches, glass, fascia and extras. `tests/city_car_catalog_smoke_runner.gd` (`_check_silhouettes`) checks that every new kind differs from every other kind, new or legacy, by at least 6 cm in one or more major proportions: length, height, rear greenhouse base, rear roof station, front greenhouse base or belt height.

## Files (owned and new only)

- `godot/scripts/city/city_car_catalog.gd` (new): the single data source. It holds per-kind configuration, dimensions, wheel poses, the profile evaluators (deck, ends, arches, greenhouse), traffic and parked rotations, and collision hulls that match the legacy `parts()` schema.
- `godot/scripts/city/city_car_mesh_kit.gd` (new): procedural low-poly builders. These are the lofted lower body, greenhouse, clipped side glass, windscreen and backlight, fascia, side details, pickup bed, van rear doors, SUV rails and spare, and round tyres. It returns SurfaceTool groups without materials.
- `godot/scripts/city/city_car_models.gd` (edited; it was clean in git before this work):
  - added `Catalog`/`Kit` preloads, `CATALOG_KINDS`, `ALL_KINDS`, `has_kind()` and `_materialize()`
  - `dimensions()` and `wheel_radius()` now dispatch to the catalog
  - `prototype()` builds catalog kinds and accepts `ALL_KINDS`
  - the prototype dictionary gained the extra keys `label`, `catalog` and `surfaces`
  - `_paint()` now leaves vertex colour enabled (see Compatibility)
- `godot/tests/city_car_catalog_smoke.gd` and `godot/tests/city_car_catalog_smoke_runner.gd` (new): headless smoke test.
- `godot/tests/city_car_showroom.gd` and `godot/tests/city_car_showroom_runner.gd` (new): private-SubViewport visual showroom.
- No `.uid` files were created. Godot generates them on its next import or scan.

During the session `city_car_catalog.gd` was edited outside this worker. `reference()` was renamed to `reference_description()`, which is correct because the old name shadowed `RefCounted.reference()`. The caller in `city_car_models.gd` was already updated. I kept both changes.

## Catalog: declared bounds and exact wheel centres

All six use the vehicle origin: ground plane, centre of overall length and width, +Z forward, +Y up. Wheel poses are identity-basis transforms in the legacy order and names: `[WheelFL, WheelRL, WheelFR, WheelRR] = [(-X, front), (-X, rear), (+X, front), (+X, rear)]`. Wheel centre: x = ±(width/2 − wheel_inset), y = radius.

| kind | L × W × H (m) | front / rear axle z | wheelbase | wheel radius | wheel centre ±x | tyre width | body ends z (lofted) |
|---|---|---|---|---|---|---|---|
| hatchback | 4.06 × 1.74 × 1.48 | +1.230 / −1.320 | 2.55 | 0.300 | 0.795 | 0.200 | ±2.018 |
| midsize_sedan | 4.62 × 1.80 × 1.44 | +1.360 / −1.360 | 2.72 | 0.320 | 0.825 | 0.210 | ±2.298 |
| long_sedan | 4.64 × 1.94 × 1.42 | +1.460 / −1.440 | 2.90 | 0.330 | 0.890 | 0.210 | ±2.308 |
| pickup | 4.64 × 1.80 × 1.68 | +1.540 / −1.300 | 2.84 | 0.355 | 0.820 | 0.220 | ±2.308 |
| cargo_van | 4.62 × 1.96 × 1.98 | +1.420 / −1.380 | 2.80 | 0.350 | 0.900 | 0.220 | ±2.298 |
| compact_suv | 4.58 × 1.80 × 1.70 | +1.430 / −1.190 | 2.62 | 0.345 | 0.820 | 0.220 | +2.278 / −2.058 (spare to −2.273) |

The values below are derived from the code. They are **not measured**; the smoke test writes the measured values.

- **Mesh AABB width:** declared width + 0.07 (mirror heads at ±(W/2 + 0.035)). This gives hatchback 1.81, midsize 1.87, long 2.01, pickup 1.87, van 2.03 and SUV 1.87. All are ≤ 2.12, the fleet `BODY_SIZE.x`. Tyre sidewalls stop at W/2 + 0.025–0.030.
- **Mesh AABB height:** equals the declared H. The SUV roof rails reach 1.70; its painted roof is 1.685.
- **Mesh AABB length:** equals the declared L. Bumper and plate faces are exactly at ±L/2. The SUV's rear extent is the spare face at −2.273, 1.7 cm inside −L/2.
- **Ground contact:** the AABB starts at y = 0 because the 12-segment tyre has a vertex directly under the hub.

Every model fits the existing envelopes without changes: `city_vehicle.gd` `BODY_SIZE` (2.12 × 2.30 × 4.70) and `ROAD_CORNERS` (±1.06, ±2.35), and `city_parked_cars.gd` `PARKING_SIZE` (2.12 × 2.05 × 4.70). Because the length cap is 4.70 m, the long sedan, pickup and van are compressed versions of their real classes.

- **Collision hulls** (`Catalog.collision_parts(kind)`). Each kind has two convex parts, `[LowerBody, Cabin]`, with the same `{name, shape, planes, radius}` schema and the same plane-generation method as `city_car_collision.gd`.
  - LowerBody spans x ±(W/2 + 0.045) below the sill band and z ±(L/2 + 0.03). Its top follows the visible hood/deck profile, including the end roll-off, so there is no full-height box over the hood.
  - Cabin uses exactly the greenhouse station points.
  - The **pickup bed is solid to rail height (1.08 m)**. This is a documented simplification.
  - The **SUV roof collider is 1.685 m**, because the rails do not collide.
- **Triangles** (my estimate; the measured counts go to JSON): near-parked meshes are about 2,100–2,700 (body about 1,050–1,650 plus wheels about 1,060). Far meshes swap in 7-segment wheels for about 750 fewer triangles. The smoke test enforces < 3,500.

## Rendering and style

- **Surfaces:** at most six per kind (paint, trim, glass, metal, headlamp, tail). They use the **existing shared `city_vehicle_*` materials** from `_material()`. There are no textures and no new shaders. Tyres use the `trim` material, so in the parked mesh they merge into the trim surface. The legacy kinds use nine surfaces.
- **Vertex colours:** every vertex has a colour. On the paint surface the colour is a linear multiplier on the paint material or MultiMesh instance colour:
  - road-dust rocker band (0.68–0.72)
  - darker underside (0.17)
  - two-tone pickup lower body (0.36)
  - black SUV cladding and blackout pillars (0.05)
  - landau roof on the long sedan (0.45)
  - body-colour bumper tone (0.93)
  Non-paint materials ignore vertex colour.
- **Normals and winding:** body panels are flat shaded, matching the legacy look. Tyres use smooth normals around the circumference, so 12 segments read as round. Every triangle is emitted clockwise from outside (Godot's front face, the same convention as `city_pointed_shrubs_smoke.gd`) with outward normals. The smoke test checks this for every triangle of the body, wheel and parked meshes.
- **LOD:** the same `_finish()` LOD generation as the legacy prototypes. `far_parked` uses lower-detail wheels.
- **Spinner:** catalog kinds have no `Spinner_*` nodes and `spinner == null`. The `box_sedan` spinner, its stationary parked hubs and `animate_spinners()` are unchanged.

## Compatibility

- `CityCarModels.KINDS` is unchanged (`["box_sedan", "compact", "minivan"]`), so current traffic, parked and fleet selection is identical until the root opts in.
  - `PALETTE`, `REFERENCES`, `paint_color()`, `make()` node names, `animate_spinners()` and legacy meshes are unchanged.
  - Legacy wheel poses are unchanged. They are now computed in the `else` branch of `prototype()`.
- `_paint(index)` **no longer turns `vertex_color_use_as_albedo` off**. This keeps one shared paint material per colour across all kinds, which `city_street_smoke_runner.gd` checks with "traffic paint palette reuses shared materials". It also lets traffic cars show the catalog shades.
  - Legacy bodies have no colour array. The renderer supplies white for a missing colour attribute, so their appearance should not change. The parked MultiMesh path already relies on this behaviour.
  - This is the one behaviour edit that touches legacy kinds. If a capture shows any legacy paint change, revert just that line; the catalog cars will then lose their shades only in traffic, not in the parked batches.
- `prototype()` with an unknown kind still falls back to `compact`.

## Integration instructions (for the root; these files were not edited by me)

1. **Collision (required before any new kind enters traffic or parking).** In `godot/scripts/city/city_car_collision.gd`:
   ```gdscript
   const Catalog := preload("res://scripts/city/city_car_catalog.gd")
   static func parts(kind: String) -> Array[Dictionary]:
   	if _cache.has(kind):
   		return _cache[kind]
   	if Catalog.has_kind(kind):
   		_cache[kind] = Catalog.collision_parts(kind)
   		return _cache[kind]
   	# ... existing legacy/police code unchanged ...
   ```
   `envelope()` and `attach()` work unchanged.
2. **Traffic distribution.** In `city_vehicle.gd:279` (`setup`):
   ```gdscript
   prototype_kind = "police" if police else Models.Catalog.traffic_kind(paint_index)
   ```
   - `TRAFFIC_ROTATION` has 13 slots: box_sedan 1, compact 2, minivan 1, hatchback 2, midsize 2, long 1, pickup 1, van 1, SUV 2. Index 0–2 keep the legacy order.
   - 13 is coprime with the six-colour palette, so every kind gets every colour.
   - The first spawned car (number 0) is still a `box_sedan`, which keeps the spinner coverage in `city_cars_smoke_runner.gd`. The police numbers 5, 24, 43 and 62 do not land on box_sedan slots.
3. **Parked distribution.** In `city_parked_cars.gd`:
   - line 90: `var kind := Models.Catalog.parked_kind(index)`
   - line 198: `for kind in Models.Catalog.rotation_kinds(Models.Catalog.PARKED_ROTATION):`

   `PARKED_ROTATION` is box_sedan 2, compact 2, minivan 1, midsize 2, hatchback 2, long 1, SUV 1, pickup 1, van 1. The spinner and hub code stays `box_sedan`-only and stationary.

   **Batch count rises from 7 to 19** (9 kinds × near/far + hubs). Update `tests/city_cars_smoke_runner.gd:75` from `<= 7` to `<= 19`. New kinds draw six surfaces per batch against nine for legacy kinds, so the worst-case parked draw submissions are about 63 near plus 63 far, up from 54. If that is too much, drop kinds from `PARKED_ROTATION` (keeping 13 slots) and the batch count follows.
4. **Civic parking fleet (optional).** In `city_civic_parking_fleet.gd`:
   - line 18: `Models.Catalog.parked_kind(index)`
   - line 43: `Models.has_kind(hull_kind)` instead of `Models.KINDS.has(hull_kind)`

   `_rectangle()` already uses `Models.dimensions()`.
5. **Existing tests to widen (optional).** `city_cars_smoke_runner.gd:23`: iterating `Models.ALL_KINDS` instead of `Models.KINDS` should pass as is (budgets < 4,500, paint index count ≥ 250, paint roof ≥ dims.y − 0.02).
   - `city_vehicle_precision_smoke_runner.gd` hard-codes legacy belts, so leave it on legacy kinds. The catalog smoke test runs the same roof, hood, shoulder and tyre ray checks for the new kinds.
   - `city_vehicle_jump_smoke_runner.gd` uses `Models.dimensions(kind).y` as the roof height. For `compact_suv` the collidable roof is 1.685 against a declared 1.70.

## Validation (for the root to run; not run by me)

- Headless smoke (more than 150 checks):
  ```
  python godot/tools/godot_run.py --timeout 180 -- --headless --script res://tests/city_car_catalog_smoke.gd
  ```
  It covers:
  - API and legacy invariants
  - bounds against declared values and the fleet/parking envelopes
  - < 3,500 triangles and far mesh < near mesh
  - ≤ 6 surfaces using only shared materials
  - paint at surface 0 with ≥ 3 vertex shades, including 1.0
  - complete paint roof
  - clockwise winding for every triangle
  - tyre radius and width
  - the wheel-pose contract and the `make()` node contract
  - shared paint material between new and legacy cars
  - arch clearance and overhangs
  - distinct silhouettes
  - collision schema, planes and envelope
  - real physics rays for roof, hood, shoulder, tyre enclosure and pickup bed height
  - rotation coverage and palette spread

  It writes measured bounds, wheel centres, triangle counts, paint shades and collision AABBs to `artifacts/alive-next/vehicle-models-measured.json`; change the path with `-- --report-out <path>`.
- Private-viewport showroom:
  ```
  python godot/tools/godot_run.py --timeout 300 -- --script res://tests/city_car_showroom.gd -- --offscreen-validation
  ```
  It refuses to run headless or without `--offscreen-validation`, and renders into a 1600×900 SubViewport. It writes PNGs and `showroom-report.json` to `artifacts/alive-next/vehicle-showroom/`; change the path with `--capture-outdir`. The captures are:
  - front and rear three-quarter views of each new kind
  - six feature close-ups (pickup bed, SUV spare and cladding, long-sedan skirt and chrome, van sliding door, round tyre, hatch)
  - an orthographic side-profile sheet comparing new and legacy kinds
  - a lineup of all nine
  - the real parked path: MultiMesh near and far batches with per-instance palette colours over the vertex shades

  Each shot fails unless at least 8–20% of sampled pixels differ from the same camera with its subject hidden.
- Also rerun after integration: `city_cars_smoke`, `city_street_smoke`, `city_vehicle_precision_smoke`, `city_vehicle_damage_smoke`, `city_vehicle_jump_smoke`, and `validate_city.py --only traffic damage`.

## Known risks and limits (unverified until run)

- No engine parse or run has happened. GDScript typing was checked by hand. Variant-to-typed assignments and untyped array literals passed to typed parameters were avoided deliberately.
- Visual quality is unproven. Fascia, lamp and window numbers were derived analytically. Review the showroom PNGs before accepting the look. The catalog numbers are plain data and can be tuned without touching the kit.
- There are no amber front markers on the new kinds. This avoids a seventh surface.
- The pickup bed is collision-solid to the rail. The SUV rails do not collide.
- The pickup's visible bed is 0.32 m deep: floor at 0.76 m, rail at 1.08 m. That is shallower than a real compact pickup (about 0.42 m), because the floor slab has to clear the 0.71 m rear tyre tops inside the 4.70 m envelope.
- The vertex-colour-on paint change for legacy cars depends on the renderer treating a missing colour attribute as white. The parked MultiMesh path already depends on this, but no render of it was taken in this session.
