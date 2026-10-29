# City build: Pen Lucy, Baltimore

A real piece of Baltimore, built from open data: Greenmount Ave (west) to Argonne Dr (east), E 41st St
(north) to E 38th St (south), plus both sides of those boundary streets and a ring of plain gray
context massing. This is the **massing pass**: every building at its real footprint and height,
the real terrain, and the street layout. Facades, porches as real porches, and props come later.

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
| `blender/assets/pen_lucy.py` | `godot/assets/models/city/pen_lucy.glb`, `blender/blend/pen_lucy.blend`, `.work/previews/pen_lucy.png` |
| `godot_shot.py` | `.work/previews/pen_lucy_godot.png` (overview, top-down, Greenmount at street level, Old York Rd) |

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
| `Row_###` | One row of attached houses (touching footprints). Custom props `osm_ids` and `addresses` |
| `Bldg_###` | A building that touches nothing |
| `Context_Buildings` | Everything in the outer ring, plain gray, one mesh |
| `Ground` | Road, sidewalk, alley, parking and grass surfaces draped on the terrain |
| `Curbs` | The vertical edges where surfaces change height (curbs, grass edges) |
| `Ground_Context` | Coarse terrain under the outer ring |
| `Trees` | LiDAR trees as trunk + crown |

`data/pen_lucy_buildings.geojson` has one record per site building (address, row, front direction,
height, roof slope, porch and rear-addition depth and height, flags). The detail passes start from it.
Flags: `no_lidar` (height guessed), `complex_roof` (gables, towers: flat roof used), `height_clamped`.

## Licenses

- OpenStreetMap data © OpenStreetMap contributors, ODbL. A game that shows the map needs the credit
  "© OpenStreetMap contributors". `pen_lucy_buildings.geojson` is a derived database: share it only
  under ODbL.
- USGS 3DEP LiDAR is public domain.
- Google Maps / Street View / 3D Tiles are not used (their terms don't allow it).
