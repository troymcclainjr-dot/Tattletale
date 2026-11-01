# Hospital architecture handoff

Implemented `godot/scripts/city/city_civic_hospital.gd` with the shared civic mesh kit. No other implementation files modified.

- API: `static func build() -> Node3D`; `static func footprint() -> Vector2` returns `(55, 38)` metres.
- Ground datum is local Y=0, centered site envelope X±27.5 / Z±19, frontage +Z. Public and emergency pavement upper faces sit exactly at Y=0.
- Main block: four stories, brick, 32×24 m, X[-25,7], Z[-17,7], main roof at Y=16.05. Upper cornice/parapet, a tall hospital identity panel, framed recessed glazing, piers and floor bands create relief.
- Low pale emergency wing: two stories, 18×20 m, X[8,26], Z[-17,3], with masonry connector and projecting brick stair enclosure.
- Glass public vestibule and broad canopy centered X=-9; separate ambulance canopy centered X=17, Z=9.5, front fascia at Z=16.06. Canopy clearance is 4.13 m at its front fascia and 4.44 m under its main slab. No central drive-lane columns.
- Public entry signs: H, PEN LUCY HOSPITAL, MAIN ENTRANCE. Emergency signs face the front and east approach; the front fascia reads AMBULANCE.
- Grouped rooftop equipment, fan caps, louvers, plant screen and stair/service housings; maximum modeled roof height approximately 18.78 m.
- Sidewalks are flat, entrances require no stairs, and exterior shells are intentionally closed (no interiors).

## Integration markers

Child Marker3D nodes carry `use`, `clear_width_m`, and `approach_local=(0,0,1)` metadata:

| Marker | Local position | Use | Width |
|---|---|---|---|
| PublicEntrance | (-9,0,13.15) | pedestrian | 5 m |
| EmergencyEntrance | (17,0,3.25) | pedestrian | 4 m |
| AmbulanceBay | (17,0,10) | ambulance | 12 m |

Building root carries `civic_type=hospital`, `footprint_m`, `front_local`, `ground_y` and `storeys` metadata. Campus paving beyond these entrance pads, ambulance routes and all site/world placement belong to root/site planner.

## Budget and validation

Ten shared weathered shader finishes, one batched architecture mesh, one static collision body with 24 box shapes, six static Label3D signs, and three markers. Expected geometry approximately 8,000 triangles; exact mesh count is pending root's Godot build. No frame processing, dynamic lights, interiors, or ambulance vehicle.

Read Astra workflow and graphify skills; ran `graphify query "city procedural building architecture materials windows Baltimore" --budget 1600` before broad navigation. Used existing `city_surface.gdshader` through the shared kit for brick/concrete/paint/trim weathering. All kit calls checked against the supplied API. `gdtoolkit`/`gdlint` are unavailable in this environment. Per assignment, this worker did not launch Godot, use the desktop, touch git, or update shared graph files. Root must run Godot parse/build, mesh/material/collision/bounds inspection, integrated visual acceptance, and central `graphify update .`.

Model route: native Astra high hospital worker, requested by Astra root; no external model calls or further delegation.

## Hospital campus follow-up

Added `city_civic_hospital_grounds.gd`, `pen_lucy_hospital_grounds.json`, and the reproducible generator `.work/civic-build/generate_hospital_grounds.py`. API is `static build(site: Dictionary) -> Node3D`; returned node stays at world origin because vertices use world coordinates. Position/yaw guards reject stale site placement. Root should add this node and skip both existing hospital terrain-patch emission and the simple hospital entry approach.

The campus follows clipped exported Ground triangles at +0.025 m, fills demolition holes from their existing terrain edges, and grades a 12 m collar up to the hospital's floor at the actual 55×38 m model envelope. This joins the public entrance and ambulance canopy pavement without a floating constant-height lot. Materials are asphalt, pale concrete walkway, restrained green landscape and parking paint. There are ten complete 2.7×5 m stalls with a 6 m aisle; a generator assertion checks every stall lies wholly inside asphalt. Ambulance approach guides remain separate from parking. No furniture, traffic, vehicle or dynamic lights added.

Final measured budget: 11,780 triangles total (6,030 asphalt, 326 walk, 4,975 landscape, 442 paint, 7 repair); four surfaces and one layer-1 concave collision shape. Geometry coverage is 2,808.641 m². Campus-only overlap with roads, sidewalks and retained homes' 5 m buffers is zero. Round-off coverage gaps sum to less than 0.001 m². Terrain grading interpolation residual at tested edge midpoints is at most 0.04 m; exact exported terrain edges are retained outside grading, and all ten stalls fit.

The seven grass-only demolition-hole repair triangles outside the campus cover 3.925 m² in the preserved 5 m buffer. They restore a previously demolished building hole (0.675 m² of the actual old footprint lies beyond the campus boundary) and its original seam margin; no retained building footprint is affected. This is necessary ground restoration, not expanded paving or vegetation clearing. Root was informed explicitly. Those patches replace the earlier root-generated hospital hole repairs.

Root still owns Godot parse/build, integrated render/ground traversal acceptance, and central graphify update. This worker performed source/API checks, geometry coverage/exclusion audits and a top-down campus-plan preview; it did not launch an engine or desktop session.
