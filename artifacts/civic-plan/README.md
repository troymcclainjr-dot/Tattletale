# Civic plan and power grid

These are game-world proposals, not real-world land-use claims. No civic buildings, homes, courts, missions, or destinations were changed.

## Review

Open `index.html` for the standalone actual-city map with Police / Fire / Hospital filters. Each service also has an inspected PNG preview and SVG. Preferred compatible set: P1 central Dumbarton police station, F1 Old York / Dumbarton response house, H1 Wyanoke neighborhood hospital.

P2 conflicts with F1; F2/H2 and F3/H3 share alternative lots. These are alternatives, not nine proposed simultaneous builds. Police envelopes are 20 × 24 m, fire envelopes 20 × 28 m (compact single-bay), and hospital envelopes 24 × 28 m (compact 4–6 storey neighborhood hospital; no campus/helipad). Envelopes are concept lots: building layout, ambulance/fire turning paths, parking, curb cuts, grading, and landscaping require a subsequent design pass.

All nine selected envelopes and 6 m direct road access corridors were checked against projected triangles of the currently exported Row_/Bldg_ architecture, surveyed footprint buffers, mapped parks, current courts and road polygons. They intersect no exported architecture. Existing vegetation/yard dressing is not a claim of an empty cadastral parcel and needs landscape review before a later build. Corner ground variation is recorded in `proposal-audit.json`. Preferred sites do not overlap each other.

## Power

`pen_lucy_power.json`: 178 poles, 110 three-conductor spans, all 17 named streets. Placement uses exact exported sidewalk polygons and Ground triangle heights, excluding entrances, projected architecture, courts, vegetation and yard props. Minimum sampled span-ground clearance: 8.182 m. One side per span; breaks at blocked candidates/corners.

`city_power_grid.gd`: 64 cells at 72 m, MultiMesh poles and one wire mesh per cell, at most two draw batches per cell. Cells cull beyond detail radius plus half-cell/span padding. Zero collision bodies, zero shadow casters, zero per-frame processes. Root ran the standalone `city_power_smoke.gd` fixture successfully: 23 ms setup and 63,360 wire vertices on this machine. No additional player snag collision is introduced.

## Reproduce from current source export

Run `build_plan.py`, `generate_civic.py` with `.work/city/venv/Scripts/python.exe`; `validate_sites.py`, `publish_plan.py`, `render_plan.py` with Python including numpy/shapely/matplotlib. Source inputs: current level/streets/courts/yards/vegetation metadata, `blender/city/data/pen_lucy_buildings.geojson`, the source LiDAR CRS, and `.work/city/build/pen_lucy_geom.json`. Scripts preserve the existing city data and only write the new power/proposal metadata and this review folder.

`find_hospitals.py`, survey output, candidates and map-source JSON are intermediate planning scratch, not final deliverables. The root agent owns integration tests, UI capture, and the single final graphify update.
