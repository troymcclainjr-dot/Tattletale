# City build: Pen Lucy, Baltimore

A real piece of Baltimore, built from open data: Greenmount Ave (west) to Argonne Dr (east), E 41st St
(north) to E 38th St (south), plus both sides of those boundary streets and a ring of plain gray
context massing. Every building sits at its real footprint and height on the real terrain, and the
967 site buildings wear **archetype kits**: porch-front rowhouses, marble-stoop rows, Greenmount
storefronts, detached houses, and window grids on the big buildings. Street props, signs and
per-house details from photos come later.

## Run it

```bash
python blender/city/fetch.py
.work/city/venv/Scripts/python.exe blender/city/process.py
"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b --factory-startup --python blender/assets/pen_lucy.py
python blender/city/godot_shot.py
```

`godot_shot.py` renders the GLB inside the Godot port (the game's clay shader and lighting) by
loading it at runtime (`city_shot.gd`), so nothing is imported into the Godot project. It takes the
port's shared Godot lock. The Blender build needs `blender/claykit.py` from the Godot port.

rockyweb (the USGS server) gives about 125 KB/s per connection and answers 429 when pushed, so the
first `fetch.py` run takes 10–20 minutes.

`process.py` needs `numpy scipy shapely pyproj laspy[lazrs]`. The venv lives in `.work/city/venv`:
`uv venv --python 3.14 .work/city/venv` then `uv pip install --python .work/city/venv/Scripts/python.exe numpy scipy shapely pyproj "laspy[lazrs]"`.

| Step | Writes |
|---|---|
| `fetch.py` | `.work/city/raw/osm.json`, the LiDAR `.laz` tiles (about 130 MB) |
| `process.py` | `.work/city/build/pen_lucy_geom.json` (meshes), `pen_lucy_report.json`, and the committed `data/pen_lucy_buildings.geojson` and `data/pen_lucy_area.geojson` |
| `blender/assets/pen_lucy.py` | `godot/assets/models/city/pen_lucy.glb`, `.work/city/build/pen_lucy.blend` (not in git: about 25 MB and rebuilt every run), `.work/previews/pen_lucy.png` |
| `godot_shot.py` | `.work/previews/pen_lucy_godot.png` (overview, top-down, Greenmount at street level, Old York Rd); with `--closeups`, `pen_lucy_godot_closeups.png` (one typical house of each main archetype, from across the street) |

## Archetypes and kits

`process.py` sorts the site buildings, then `kits.py` dresses each one. Counts from the current build:

| Archetype | How it's picked | Kit | Count |
|---|---|---|---|
| `row_porch` | Attached, LiDAR found a lower front porch | Open porch across the front (deck, posts, railing with a gap at the steps, roof slab, fascia, steps), door with transom, double-hung windows, bracketed cornice | 600 |
| `row` | Attached, no porch | Same front with a marble stoop instead of a porch | 132 |
| `storefront` | Attached, no porch, on Greenmount Ave | Knee wall, display glass with mullions, sign band, sometimes an awning, then windows above | 12 |
| `detached_porch` / `detached` | Touches nothing | Front like a row (with or without porch), windows on every exposed wall, siding colors | 79 / 63 |
| `civic` | Church, school and similar tags, or over 700 m² | Window grid on every exposed wall | 5 |
| `garage` | Under 45 m² and under 4.6 m tall | Plain mass | 76 |

The look of each house is seeded by its OSM id: rows share a brick and roof color, and some houses
have formstone or painted fronts. Trim, door and awning colors vary. Doors alternate along a row,
so neighbors mirror each other. End units and rear walls get windows wherever no other building
touches the wall.

Kit parts are boxes with 45° edge cuts (28 triangles, 12 for a plain box), smooth shaded so they
read as soft clay under the Godot clay shader. They're generated in numpy inside `process.py`
rather than with claykit primitives, because about 40,000 parts would take Blender far too long one
object at a time. They still use claykit's material naming, so Godot's clay import hook applies.
The build is about 1.24M triangles and a 31 MB GLB; Godot's import generates LODs.

## Where the numbers come from

| What | Source | Notes |
|---|---|---|
| Footprints, addresses, streets, alleys, paths, parking | OpenStreetMap (Overpass) | Every rowhouse is its own footprint. Heights are almost never tagged |
| Building heights, roofs, porches, rear additions | USGS 3DEP LiDAR `MD_4County_D24`, flown Dec 17–30 2024, about 15 points/m² | Last-return points inside each footprint. Houses are profiled front to back: main roof (a plane or a gable, whichever fits more points), lower front porch, lower rear addition |
| Terrain | Same LiDAR, ground-classified points, 1 m grid | Holes under buildings filled from the nearest ground |
| Trees | Same LiDAR, canopy peaks of multi-return pulses | The survey only classifies ground and noise; bare winter branches return a pulse several times, roofs once. Crown size comes from the canopy spread |
| Street widths | Defaults per street type in `process.py` (`ROAD_W`, `SIDEWALK_W`, `SERVICE_W`) | Not measured. `width=*` tags win when present |

OSM and LiDAR can disagree by a meter or two. `process.py` searches for the shift that best overlaps
the footprints with the LiDAR roofs and moves the LiDAR onto OSM, and the report prints the shift.
Here it came out at 0 m: Baltimore's OSM footprints already line up.

## Coordinates and objects

1 unit = 1 m. Origin = the Old York Rd / Wyanoke Ave intersection at ground level. x east, y up,
z south (north is -z). This is its own world, separate from the original block's coordinates.

| Object | What |
|---|---|
| `Row_###` | One row of attached houses (touching footprints) with their kit parts. Custom props `osm_ids` and `addresses` |
| `Bldg_###` | A building that touches nothing, with its kit parts |
| `Context_Buildings` | Everything in the outer ring, plain gray, one mesh |
| `Ground` | Road, sidewalk, alley, parking and grass surfaces draped on the terrain |
| `Curbs` | The vertical edges where surfaces change height (curbs, grass edges) |
| `Ground_Context` | Coarse terrain under the outer ring |
| `Trees` | LiDAR trees as trunk + crown |

`data/pen_lucy_buildings.geojson` has one record per site building: address, row, archetype, door
side, front direction, height and eave, roof kind and pitch, porch and rear-addition depth and
height, and flags. The detail passes start from it. Flags: `no_lidar` (height guessed),
`complex_roof` (gables, towers: flat roof used), `height_clamped`.

The kits are generic Baltimore types, not checked against photos of these exact houses. The next
pass should check them against street photos (Mapillary covers most streets, but its API needs a
token) or the owners' own photos.

## Licenses

- OpenStreetMap data © OpenStreetMap contributors, ODbL. A game that shows the map needs the credit
  "© OpenStreetMap contributors". `pen_lucy_buildings.geojson` is a derived database: share it only
  under ODbL.
- USGS 3DEP LiDAR is public domain.
- Google Maps / Street View / 3D Tiles are not used (their terms don't allow it).
