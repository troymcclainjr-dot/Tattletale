# City build: Pen Lucy, Baltimore

A real piece of Baltimore, built from open data: Greenmount Ave (west) to Argonne Dr (east), E 41st St
(north) to E 38th St (south), plus both sides of those boundary streets and a ring of plain gray
context massing. Buildings follow mapped footprints and surveyed heights on graded terrain, with
road-conflicting footprints repaired during processing. The
967 site buildings wear **archetype kits**: porch-front rowhouses, marble-stoop rows, Greenmount
storefronts, detached houses, and window grids on the big buildings. Eighteen commercial
buildings are generated in the source geometry. Runtime additions include
neighbors across the mapped blocks, postal fixtures, parked cars, street
markings and varied vegetation. These are interpretive additions, not a photographic survey.

## Run it

```bash
python blender/city/fetch.py
.work/city/venv/Scripts/python.exe blender/city/process.py
"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b --factory-startup --python blender/assets/pen_lucy.py
python blender/city/godot_shot.py
```

`godot_shot.py` renders the GLB inside the Godot port (the game's shared surface shader and lighting) by
loading it at runtime (`city_shot.gd`), so nothing is imported into the Godot project. It takes the
port's shared Godot lock. The Blender build needs `blender/claykit.py` from the Godot port.

rockyweb (the USGS server) gives about 125 KB/s per connection and answers 429 when pushed, so the
first `fetch.py` run takes 10–20 minutes.

`process.py` needs `numpy scipy shapely pyproj laspy[lazrs]`. The venv lives in `.work/city/venv`:
`uv venv --python 3.14 .work/city/venv` then `uv pip install --python .work/city/venv/Scripts/python.exe -r blender/city/requirements.txt`.
The pinned requirements reproduce the tested processor environment. If the default uv cache is
unwritable, set `UV_CACHE_DIR` to `.work/city/uv-cache` before these commands.

| Step | Writes |
|---|---|
| `fetch.py` | `.work/city/raw/osm.json`, the LiDAR `.laz` tiles (about 130 MB) |
| `process.py` | `.work/city/build/pen_lucy_geom.json` (meshes), `pen_lucy_report.json`, and the committed `data/pen_lucy_buildings.geojson` and `data/pen_lucy_area.geojson` |
| `runtime.py` (called by `process.py`) | `godot/assets/data/pen_lucy_level.json`: terrain-following spawn, street landmarks, roads, boundaries, walking route, businesses, parks, rear doors, porch stairs, construction audits and decorative fixture anchors |
| `vegetation.py` (called by `process.py`) | `godot/assets/data/pen_lucy_vegetation.json`: shared near/far tree and shrub meshes plus grounded, deterministic placements |
| `blender/assets/pen_lucy.py` | `godot/assets/models/city/pen_lucy.glb`, `.work/city/build/pen_lucy.blend` (not in git: about 25 MB and rebuilt every run), `.work/previews/pen_lucy.png` |
| `godot_shot.py` | `.work/previews/pen_lucy_godot.png` (overview, top-down, Greenmount at street level, Old York Rd); with `--closeups`, `pen_lucy_godot_closeups.png` (one typical house of each main archetype, from across the street) |

## Archetypes and kits

`process.py` sorts the site buildings, then `kits.py` dresses each one. Counts from the current build:

| Archetype | How it's picked | Kit | Count |
|---|---|---|---|
| `row_porch` | Attached, LiDAR found a lower front porch | Open porch across the front (deck, posts, railing with a gap at the steps, roof slab, fascia, steps), door with transom, double-hung windows, bracketed cornice | 599 |
| `row` | Attached, no porch | Same front with a marble stoop instead of a porch | 131 |
| `storefront` | Selected commercial frontages | Knee wall, display glass with mullions, sign band, sometimes an awning, then windows above | 18 |
| `detached_porch` / `detached` | Touches nothing | Front like a row (with or without porch), windows on every exposed wall, siding colors | 79 / 59 |
| `civic` | Church, school and similar tags, or over 700 m² | Window grid on every exposed wall | 5 |
| `garage` | Under 45 m² and under 4.6 m tall | Plain mass | 76 |

The look of each house is seeded by its OSM id: rows share a brick and roof color, and some houses
have formstone or painted fronts. Trim, door and awning colors vary. Doors alternate along a row,
so neighbors mirror each other. End units and rear walls get windows wherever no other building
touches the wall.

Kit parts are boxes with 45° edge cuts (28 triangles, 12 for a plain box), smooth shaded so they
have clean beveled edges under the shared surface shader. They're generated in numpy inside `process.py`
rather than with claykit primitives, because about 40,000 parts would take Blender far too long one
object at a time. They still use claykit's material naming, so Godot's material import hook applies.
Godot imports LODs, and the runtime building optimizer generates native LODs again for its
combined render chunks. Final GLB size and triangle totals are reported by each export.
All 659 generated open porches now have supported stair-side railing ends: 659 terminal
posts were added outside the clear stair openings. Side rails meet the house wall instead
of stopping short. This shared kit correction applies across the map.

## Where the numbers come from

| What | Source | Notes |
|---|---|---|
| Footprints, addresses, streets, alleys, paths, parking | OpenStreetMap (Overpass) | Every rowhouse is its own footprint. Heights are almost never tagged |
| Building heights, roofs, porches, rear additions | USGS 3DEP LiDAR `MD_4County_D24`, flown Dec 17–30 2024, about 15 points/m² | Last-return points inside each footprint. Houses are profiled front to back: main roof (a plane or a gable, whichever fits more points), lower front porch, lower rear addition |
| Terrain | Same LiDAR, ground-classified points, 1 m grid | Holes filled from nearest ground; a continuous grading field controls paved slopes across the playable site and connected context corridors |
| Trees | Same LiDAR, canopy peaks of multi-return pulses | Trunk centers, height and crown spread guide varied shared tree meshes; bare winter branches return a pulse several times, roofs once |
| Shrubs | Seeded fictional garden dressing | Restricted to mapped grass, inset from pavement and building footprints |
| Street widths | Defaults per street type in `process.py` (`ROAD_W`, `SIDEWALK_W`, `SERVICE_W`) | Not measured. `width=*` tags win when present |

OSM and LiDAR can disagree by a meter or two. `process.py` searches for the shift that best overlaps
the footprints with the LiDAR roofs and moves the LiDAR onto OSM, and the report prints the shift.
Here it came out at 0 m: Baltimore's OSM footprints already line up.

The terrain refinement uses a continuous 1 m grading field across the playable site and
connected context road/pedestrian corridors, with a smooth outer transition. Roads, sidewalks,
alleys, paved lots and building footings share the field, avoiding steep paved banks between
separately graded strips. Small residual imperfections remain. The final source audit finds
zero paved area above 4° slope. Maximum slopes on substantial faces are 3.349° for roads,
3.078° for sidewalks, 3.612° for alleys and 2.889° for paved lots.

The sidewalk top-surface audit covers 99,684 triangles, with a 2.719° 95th-percentile slope
and zero area above 5% crossfall. Surveyed roof returns move by the same datum shift as each
building's footing before profiling: all 967 buildings retain their relative main-roof
heights with zero measured error. Twelve footprint repairs eliminate all building-road
intrusions found by the source audit. These are generated playability grades, not a claim
that every paved elevation matches the unmodified survey.

The service yards use 91,002.54 m² of hardscape. Seven mapped parks and greens retain
6,584.02 m² of grass, including polygon holes where appropriate. Commercial fronts belong to
18 generated building kits rather than runtime storefront overlays. These ground and
building treatments are interpretations of the mapped neighborhood, not surveyed materials.

## Coordinates and objects

1 unit = 1 m. Origin = the Old York Rd / Wyanoke Ave intersection at ground level. x east, y up,
z south (north is -z). This is its own world, separate from the original block's coordinates.

The runtime JSON uses `[x, y, z]` arrays throughout. `spawn.yaw` follows the game's convention:
zero faces south (+Z), PI faces north (-Z). `landmarks` have `id`, `label`, `position`, `description`, and real
intersection `streets`; `roads` have `name`, sampled `points`, `width`, and `sidewalk_width`.
`route.landmark_ids` defines the four-stop Old York walk, and `route.points` prefers its west
sidewalk, crossing streets and using the road edge where projecting steps leave too little
clearance. Routing combines OSM footprints with the actual generated facade/kit triangles
clipped to -0.5–2 m above local terrain, then keeps 0.5 m clearance from those obstacles.
Every connecting segment is checked; high roofs and cornices are excluded from this walk-level
projection. `site_boundary` includes the 45 m site buffer;
`area_boundary` is the original street-bounded area. `terrain_extent` is a bounding box of the
context terrain, with approximate sampled ground-height limits, not a playable rectangle.

`porch_stairs` records each building/source mesh, the ground approach, raised landing, outward
normal, riser height, tread depth and stair width. The movement integration test uses those
points against the actual imported triangles. Individual risers stay within the player's
28 cm step limit, with full capsule and head-clearance checks. Crowd placement reserves the
approach-to-landing corridor. `rear_doors` records entrances on exposed rear walls;
`construction_audit` reports rear-door coverage, porch-stair omissions and rejected kit sections.
`businesses` describes the generated commercial fronts, and `parks` retains polygon holes.

The final source audit records 889 rear entries, covering all addressed homes and 866 of
868 footprints in the broader residential classification. Both exceptions are unaddressed:
`w336339670` is a single-story alley block whose rear and side walls are all shared, and
`w336348734` has only 2 m of wall height and insufficient rear-door headroom. The kit leaves
shared walls and undersized structures intact instead of forcing unusable doors. Neither
exception is a verified addressed home; the broad residential label comes from kit heuristics.

Spawn and landmarks are derived from the generated sidewalks with facade clearance, not placed
on building roofs or guessed flat ground. `dressing` entries have `kind`, `position`, and `yaw`,
plus `street_names` for signs. Their small bases sit 0.5–0.7 m from the road edge, at least 1.25 m
from building footprints and nearby lower kit geometry, and 0.9 m from the route. Lamps face the road. These fixtures are
interpretive scenery rather than a survey of real fixture locations. Collision uses the city
meshes, preserving open porches and the sloping terrain. Regenerating metadata does not rebuild
or replace the GLB; the separate Blender command does that.

| Object | What |
|---|---|
| `Row_###` | One row of attached houses (touching footprints) with their kit parts. Custom props `osm_ids` and `addresses` |
| `Bldg_###` | A building that touches nothing, with its kit parts |
| `Context_Buildings` | Everything in the outer ring, plain gray, one mesh |
| `Ground` | Road, sidewalk, alley, parking and grass surfaces draped on the terrain |
| `Curbs` | The vertical edges where surfaces change height (curbs, grass edges) |
| `Ground_Context` | Coarse terrain under the outer ring |
| `Trees` | Varied trunk/cluster geometry for standalone previews; the playable level replaces this mesh with spatial near/far batches and nearby cylinder collision |

`data/pen_lucy_buildings.geojson` has one record per site building: address, row, archetype, door
side, front direction, height and eave, roof kind and pitch, porch and rear-addition depth and
height, and flags. The detail passes start from it. Flags: `no_lidar` (height guessed),
`complex_roof` (gables, towers: flat roof used), `height_clamped`.

The kits are generic Baltimore types, not checked against photos of these exact houses. The next
pass should check them against street photos (Mapillary covers most streets, but its API needs a
token) or the owners' own photos.

The playable build filters inferred tree trunk centers that fall inside mapped road pavement.
Canopy peaks can overhang a street even when the real trunk is elsewhere. The current pass
rejects 66 roadway peaks and retains 1,812 trees. Four tree variants use branching, irregular
clustered crowns; three shrub variants add 440 untended bushes on mapped grass. Each variant
has near/far meshes: 14 shared meshes total. Tree meshes use 372 triangles nearby and 92 far
away; shrub meshes use 136 and 80. Placement records support trunk clearance checks even
when a distant cell's physics is unloaded. Road and route clearance are audited during generation.

## Runtime population and streaming

The playable neighborhood distributes porch residents, seated neighbors, conversation circles,
sidewalk walkers and park visitors across the map. Runtime checks confirm 1,200 ambient
residents: 840 street residents, 200 porch residents and 160 park visitors; 128 of the street
residents use batched walking. Individual case actors and six validated foot patrols are additional. Connected
traffic has 72 moving cars across 16 streets, including four police cars, and 96 parked cars
share three vehicle prototypes. These population checks make no performance claim.
Postal drops, mailboxes, crossings, worn road dots and occasional potholes occupy geographic
detail cells. Traffic uses directed lanes, signal/stop-line handling and exclusive junction
reservations; nearby vehicles retain physical collision checks.

`city_render_optimizer.gd` batches building surfaces and generates native mesh/shadow LODs.
`city_streaming.gd` saves and asynchronously restores detailed chunk scenes, frees distant
render nodes and retains simple building silhouettes. Load/unload margins prevent cell-edge
thrashing. Imported terrain/building collision shapes remain resident. Vegetation,
crowd, parked-car and street-detail providers separately release and rebuild nearby cells;
tree trunk collision is loaded before the player reaches the trees.

Startup still reads the complete imported GLB to build collision and measure placements.
Only after those steps are hidden source meshes released and detailed render chunks streamed.
The initial model import/setup is therefore not fully streamed. Cached render resources
speed unchanged visits. Case progress lasts for the current visit; display, audio and
control settings persist. The controls are unchanged: WASD/Shift move, right mouse holds
camera orbit, V changes view, E interacts, M opens the map and Esc opens Settings. Porch
stairs use verified structural treads, wall contact preserves tangential movement, and the
chase camera gently follows sustained travel after a look grace period while leaving idle
and held-orbit views alone. See `../../godot/README.md` for full controls and runtime tests.

## Licenses

- OpenStreetMap data © OpenStreetMap contributors, ODbL. A game that shows the map needs the credit
  "© OpenStreetMap contributors". `pen_lucy_buildings.geojson` is a derived database: share it only
  under ODbL.
- USGS 3DEP LiDAR is public domain.
- Google Maps / Street View / 3D Tiles are not used (their terms don't allow it).
