# Grounded world repairs

The source facade repair restores entrances and windows on narrow residential fronts that were silently skipped below 3 m. The new build reports 27 repaired narrow fronts, including all seven affected Row170 fronts; minimum porch ceiling remains 2.4 m. Existing rear entries are produced before front details and remain intact. The eighth Row170 end unit retains its existing opposite-facing entrance.

Two evergreen mesh templates add broad pine and narrower conifer silhouettes inside existing tree height/radius envelopes. The rebuilt source selects 11 existing surveyed trees; runtime uses high hash bits to split the two silhouettes because the survey grid otherwise collapses parity. No tree position, radius, growth index or trunk collision is added or enlarged.

## Published post-build repair manifest

`blender/city/alive_world.py` reads the final exported Ground triangles and current homes, exact street polygons, door metadata, yards, vegetation/growth, courts, backlots and redevelopment polygons. Its output is consumed by `city_alive_world.gd`, with small shrubs appended through the existing vegetation batching. Run the author only after those inputs have finished rebuilding.

- 537 existing grassy residential front beds normalized into continuous lawns. Intentional all-paved yards stay paved. Exact public sidewalks and full-width door paths remain outside the lawns; explicit cleanup masks cover stray original grass outside the intended beds, including detached frontage fragments that do not intersect the exact sidewalk polygons. Both measured overlaps are0mÂ².
- 3 added Row050 shrubs use the three existing rounded shrub styles; full crowns stay within supported lawn and clear paths/props. Their authored radius is 0.65 m and heights 1.25â€“1.45m.
- 15 short private side fences, including the requested paved Frisby corner side yard. The requested fence has 10 terrain-supported posts, extending the side run toward the porch and returning to the end wall, height 1.1 m, and leaves both end approaches open. These paved-side fences stay near exposed end walls beside the exact public sidewalk; back service alleys and interior row gaps are excluded.
- 3 authored Row170 rear dumpsters clear all preserved door corridors. Two are on the north rear lane. The opposite-facing end unit has its rear on the south side, so its third dumpster needs visual judgment before final acceptance.
- Firehouse side grass covers30.598mÂ² west and30.600mÂ² east outside the 18 m model. Only existing supported Ground triangles are painted; no new unsupported surface bridges a terrain hole or apparatus apron. A further 3,583 paving triangles cover the old diagonal grass wedge and detached islands outside those intended side strips, including a 12 cm adjacent-material buffer over their thin borders.

## Integration and cost

Initialize `CityAliveWorld.setup(level)` after yard templates, backlots and permanent terrain/building collision, before population placement. Register `set_presence(focus, near_radius, far_radius)` with the existing streamer. No frame processing. Fence and ground geometry use 48 m cells, shared finish surfaces, shadow casting off and distance culling. Fence collision stays present when visuals cull. Dumpsters reuse the established backlot ground-normal and body-overlap validation.

The published manifest has 90,656 lawn triangles,30,851 paving repair triangles and304 fire-side grass triangles. These overlay triangles sit 2.5â€“3cm above their sampled supporting terrain and do not add collision. Runtime performance and visual acceptance remain the parent integration pass responsibility; no performance improvement is claimed.

## Checks

- `test_alive_world.py`: 2 source-geometry tests pass (narrow front/rear entries, porch headroom, bounded conifer mesh/LOD and variation).
- `test_alive_details.py`: 2 geometry tests pass (sloped triangle interpolation, clipped holes, unsupported-point rejection and rotated dumpster footprint dimensions).
- Python author assertions pass for requested Frisby fence, Row050 planting, rear service bins and both fire lawns.
- `city_alive_world_smoke.gd` is the pending full-level fixture: validates final terrain under every fence post and added shrub, accepted bins, conifers, both side lawns and all 8 preserved Row170 rear doors. Parent owns serialized engine execution and final screenshots.

No crowd identity or save recipe was modified. Approved court 13 layout and removed court 17 remain locked through the full process rebuild; the locked publication passed 123,298 source-height support samples.

Post-publication geometry check: each of the three added shrub crowns has 0 m² intersection with the expanded paving cleanup. Final recapture remains required; the earlier capture exposed residual original grass and is not final acceptance.

Final narrow cleanup extends the East 41st frontage apron across the wider inter-house gaps. SHA checks confirm plants, fences, dumpsters, all normalized lawn triangles and both firehouse lawn strips are unchanged by that final cleanup. Projected remaining green-spur samples are covered; one non-covered probe was already source alley paving. Evidence: `.work/alive-next/final-cleanup-check.json`.

## Original terrain correction

The original grass boundaries generate vertical dirt/brick skirts in the separate `Curbs` mesh. Top-surface overlays cannot change those borders. The final local source repair partitions original Ground faces inside the two reviewed cleanup masks and assigns paving outside retained lawn polygons. It also assigns paving to the mask-interior portions of the original vertical skirts. All vertical geometry remains closed; no skirt faces are discarded. Public street-curb, asphalt and alley skirt faces and all original grades are preserved.

`blender/city/surface_repairs.py` and the reviewed `pen_lucy_surface_repairs.json` specification run from `process.py` before every geometry publication. The standalone helper can stage the same repair for a Blender-only re-export. The specification retains 85.86285 m² of East41st lawns and 61.19825 m² of fire side lawns, with zero road overlap. The final `preserve-skirts-v2` result partitions/recolors 756 private skirt source triangles, producing 155,712 closed Curbs triangles overall with zero faces removed. See `.work/alive-next/source-surface-repair.json`.

Four source-repair unit tests pass, including exact grade/winding preservation, protected street curbs, and full vertical surface area across material boundaries. The actual staged mesh also passed an independent area check: original skirts 16,288.413643781889 m²; final 16,288.413643782395 m² (difference 5.06e-10 m²). All protected street-curb/asphalt/alley face indices are exactly unchanged. Evidence: `.work/alive-next/closed-skirt-verification.json`.

The parent owns the final Blender export, import and visual acceptance. No engine or Blender process was launched by this worker. The visible right-front firehouse patch projects to the intentional west lawn strip at approximately (-35.2,132); it is preserved as requested grass beside the station.

Rear review cameras sit in the actual north service lane at terrain height plus 1.65 m, looking from both ends. A third view shows the opposite-facing end unit's south rear door/bin; that rear cannot be seen through the houses from the north lane.
