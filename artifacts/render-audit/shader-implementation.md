# Shader research implementation — 2026-10-30

Companion to [the original research](../living-world/shader-research.md). This is the implementation record, authored by root after integration. Opus 5.5 with requested **max** effort wrote the surface, glass, road-wear, weathering, and material-test changes. Its 30-minute CLI limit expired after those writes, before a final report. Root reviewed the code, fixed runtime profile reporting and the Compatibility color-space guard, and ran the engine validation. See [provenance](review-provenance.json) and [acceptance/performance](acceptance.md).

## What is now implemented

| Research recommendation | Implementation / decision | Incremental rendering work |
| --- | --- | --- |
| Gentle tree wind | Already implemented; now optimized. Cached height weights and pre-sized arrays replace repeated construction work. Existing CUSTOM0.z carries the scale ratio so vertex normals are corrected on the GPU. The StandardMaterial comparison path retains correct CPU normals. Trunks remain fixed; wind follows the pausable world clock. | Same mesh layout, draw count and shared shader. One vertex normal correction; removes per-vertex scripted transforms/normalization at mesh-build time. |
| Time-dependent lighting and fog | Implemented. Physical sun updates at 20 Hz; a separate, shadowless sky-only sun updates on the existing 2 Hz sky cadence. Fill contributes to scene lighting only. Eight nearby streetlamp lights remain the maximum. | No additional scene-lighting pass from the sky-only sun. Sky radiance updates remain bounded, not eliminated. |
| Material-specific roughness | Implemented in the existing surface shader. Brick faces differ from mortar; worn horizontal concrete differs from dirty joints; asphalt patches differ from cracks; exposed paint/wood stays matte; turf loses its vinyl-like grazing sheen. Existing wear masks are reused. Authored base colors and imported materials remain intact. | Scalar arithmetic using existing masks; no texture, geometry, decal or screen pass added. |
| Dusty glass response | Implemented. Opaque windows retain dark interiors and dust, with a more glass-like grazing response. Horizon-facing sky reflections are restrained to reduce the false bright sheen from missing street-canyon reflections. Fine streaks fade to their average at distance. | Existing shader/material and draw layout; reflected-direction arithmetic and distance-dependent skipping of fine noise. No transparency, refraction, SSR or reflection-probe update. |
| Stable distant detail | Implemented. Derivatives are taken before material branches. Brick antialiasing no longer includes the discontinuous half-brick bond offset. Paint flecks, glass streaks and road-wear detail fade toward average coverage as they become subpixel. Broad scuffs, potholes and flaking remain. | Existing shader paths; some fine noise lookups are skipped at distance. This is spatial filtering, not temporal antialiasing. |
| Road paint and pothole finish | Implemented. Dry markings receive a restrained sheen, worn tire paths are rougher, and pothole depressions remain matte and dark. | No extra road instances or surfaces. |
| Shadow distance and LOD | Existing native mesh LOD and preset distances retained. Fixed night-to-day quality handling, shared ownership of chunk settings, material reuse after streaming, and bounded vegetation construction. Compatible building finishes now share surfaces through a full-float vertex palette. | Reduces material surfaces/draw submission; preserves full-detail geometry and collision. |
| SSAO adjustment | Existing Low-off / Balanced-and-High-on policy retained. No extra ambient-occlusion or indirect-lighting effect added. | No new cost. Current measurement identifies CPU submission/construction work rather than GPU saturation; blanket SSAO changes would alter the established look without fixing that cause. |
| Selective story decals | Deferred until actual case-specific marks are authored. Existing mesh road markings and wear already cover generic dirt and damage. | Avoids extra projected decals and material/cluster work without a content purpose. |
| Wetness | Deferred until there is a weather/rain state. A permanent wet layer would conflict with the requested dry, worn neighborhood. | No wetness/SSR cost. |
| Authored detail normals/AO | Deferred pending a close-up asset that demonstrably needs them. No blanket procedural bump, grain, clay treatment or texture stack. | No added texture bandwidth/tangent data. |

SDFGI, SSIL, volumetric fog, full-screen grain, broad SSR and alpha-blended foliage remain excluded from this low-cost pass. The research ranked these as poor current tradeoffs; “apply what is worth doing” does not mean enable every available effect.

## Comparison and validation

`--legacy-city-finishes` selects the previous material math through shader preprocessor defines in memory. `--no-city-material-palette` disables consolidation independently. The on-disk source is unchanged by these switches, and streaming/cache identities distinguish the treatments. The renderer-dependent palette conversion follows Godot's output color space. Shader-source changes invalidate the consolidated-mesh cache; subsequent launches reuse it.

`city_material_fidelity_smoke` verifies classification, roughness bounds, shared finish reuse, imported-resource isolation, all 314 imported glass panes, and legacy-profile idempotence: **20 checks passed**. `city_material_palette_smoke`: **20 passed on Vulkan**; headless passed 19 with one unsupported shader-default-query skip. Headless checks verify resource/geometry contracts, not rendered appearance. Root separately inspected real Vulkan/Forward+ captures of day, dusk, night, a resident, player aiming and the Rose Hill facade. GPU timings and remaining limits are recorded in the acceptance report.

The spatial noise hash was intentionally retained in this pass: replacing it would relocate every existing weathering mark. The audit's possible far-coordinate precision issue remains a targeted follow-up, not a confirmed measured defect or a claimed fix.

## Primary technical references

- [Godot spatial shader built-ins and material outputs](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html)
- [DirectionalLight3D sky-only and light-only modes](https://docs.godotengine.org/en/stable/classes/class_directionallight3d.html)
- [StandardMaterial3D and PBR material properties](https://docs.godotengine.org/en/stable/tutorials/3d/standard_material_3d.html)
- [Native mesh LOD](https://docs.godotengine.org/en/stable/tutorials/3d/mesh_lod.html)
- [GPU optimization and transparency/shadow costs](https://docs.godotengine.org/en/stable/tutorials/performance/gpu_optimization.html)
- [RenderingServer timing APIs and their scope](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html)
