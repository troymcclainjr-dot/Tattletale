# Firehouse grounds fix

Added `godot/scripts/city/city_civic_fire_grounds.gd`, `godot/assets/data/pen_lucy_fire_grounds.json`, and reproducible generator `.work/civic-build/generate_fire_grounds.py`. No edits to the Opus model, district integration or shared plan.

API: `static build(site: Dictionary) -> Node3D`; keep returned node at world origin. It checks the source site position/yaw before construction. Root should skip the former fire terrain patches, simple center approach and flat apron when adding this replacement.

The apron spans X[-36,-12] and reaches the actual model forecourt at Z=128.5, Y=-2.5. Its street edge follows the existing sidewalk exactly, from Z=112.8516 on the west to Z=120.3288 on the east. The exported `clearance_polygon_xz` field is the precise polygon to add to district clearance; this extends the old Z=114 clearance slightly north on the west side. Paving and collision do not intrude into roads or sidewalks.

Ground uses clipped exported terrain triangles, fills demolition holes by interpolating their existing rim heights, and blends to the finished floor. Source terrain remains beneath the mesh, so the blend is clamped above its source plane plus 0.025 m. This removes both the old 3.5 m gap in front of the smaller firehouse and the buried fixed-height street edge. All remaining demolished-ground holes outside the model footprint are repaired by the same component.

Measured geometry: 1,135 apron triangles plus 72 repair triangles; two surfaces, one layer-1 concave collider. Apron area 295.7108 m², repair area 5.4709 m². Road/sidewalk overlap and retained-building footprint overlap are both zero. Maximum tested interpolation residual is 0.0077 m. Forecourt edge samples equal Y=-2.5. At X=-17.25 and X=-28.3, sampled half-meter access-route height changes are at most 0.03539 m and 0.04486 m respectively. Python assertions enforce <=0.16 m and exact entrance-edge height.

Root owns Godot parsing, physics-ray checks and final integrated render. No engine or desktop used by this worker. Model route: native Astra high worker; no further delegation.
