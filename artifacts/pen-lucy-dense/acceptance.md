# Dense Pen Lucy pass — October 29, 2026

## Neighborhood and geometry

- 1,215 people: 1,200 shared-mesh ambient residents plus 15 character actors, including six functioning foot patrols. Ambient placement comprises 840 street residents, 200 porch residents and 160 park/green residents. The street population is 5.25 times the previous 160. There are 128 nearby-updated walking residents, 203 social circles and 154 seated porch/park poses. Existing case actors remain; final placement reports no actor failures.
- 72 moving vehicles distributed over 16 streets, including four police cruisers; 96 parked cars remain. Cruise targets are 8–10.5 m/s, with slower turns, signal stops, following distance, outgoing-lane checks and junction reservations. Cars follow connected routes rather than parking at route endpoints.
- Eighteen commercial ground floors are built into the source buildings, with actual doors, display windows and fascia. Runtime additions are text on those fascia boards, not duplicate storefront overlays. Businesses include liquor, grocery, barber, laundry and takeout shops; these remain exterior buildings, without shop interiors.
- 659 generated porches and terminal railing posts. Stairs have risers no higher than 18 cm and treads at least 28 cm. The character retains its 28 cm maximum step limit.
- 889 rear entries; all addressed homes are covered. Of 868 broadly classified residential footprints, 866 have a rear entry. Two unaddressed, service-like structures have physical exceptions: `w336339670` has neighboring buildings against its rear and both sides, while `w336348734` has a wall only 2 m high. Their actual use is unspecified in OSM. No door was fabricated into a party wall or an impossibly low roof. Shallow rear additions are raised modestly below their main eaves when necessary for rear-door headroom.
- Twelve road-overlapping footprints repaired. Independent inspection of the final generated building triangles finds no carriageway intrusion.
- Independent audit of 99,684 actual sidewalk top faces: zero area above 15 degrees, zero area above 5% crossfall, 2.719-degree 95th-percentile slope and 3.078-degree maximum for faces larger than 0.2 m². The expanded audit covers **all** paved surfaces, including the service-yard and parking banks missed by the first sidewalk-only audit: road maximum 3.349 degrees, sidewalk 3.078, alley/yard 3.612 and lot 2.889. No paved area exceeds 4 degrees. Curb skirts are excluded.
- Regrading shifts each building's roof returns by the same amount as its foundation before fitting its architecture. The measured roof-to-ground height error is zero over all 967 modeled site buildings, preserving the surveyed house and porch profiles. Exact planar ground cells merge back into larger triangles; changing grades use the matching 1 m terrain facets.
- 91,002.54 m² of additional service yards/gaps paved, while seven mapped or generic community greens preserve 6,584.02 m². Small terrain/sidewalk imperfections remain. Vegetation now comprises 1,812 trees and 440 shrubs, using seven shared variants.

## Controls and map

- Wall contacts preserve tangential movement; head-on walls and corners remain solid. Porch stairs use full capsule clearance against the actual building collision geometry.
- Right mouse continues to orbit. After 0.85 seconds without manual camera input, movement gradually brings the camera behind the character; idle play leaves it alone. Automatic camera motion does not change the direction of held movement keys. The camera boom contracts around obstacles and restores smoothly.
- The radar redraws on every camera/player change, rather than waiting for an 80 ms timer. Road geometry is cached. `M` opens the full map, with street names positioned and oriented along streets and separate captions reserved for points of interest.
- Natural case discovery, the settings menu, mouse capture, maximized-windowed launch, FPS counter, non-blocking small trash and existing cases remain.

Camera decisions follow the obstruction and follow/orbit separation described by [Godot's spring-arm documentation](https://docs.godotengine.org/en/stable/tutorials/3d/spring_arm.html), [Cinemachine Orbital Follow](https://docs.unity3d.com/Packages/com.unity.cinemachine@3.1/manual/CinemachineOrbitalFollow.html), and [Third Person Follow](https://docs.unity3d.com/Packages/com.unity.cinemachine@3.1/manual/CinemachineThirdPersonFollow.html). The timing and speed are project-specific tuning, not a claim to reproduce GTA's internal camera code.

## Rendering and loading

Distance-based loading/freeing of detailed building chunks, retained distant silhouettes, native mesh LOD, shared crowd/detail meshes and nearby-only active collision bodies continue to operate. Different load/unload thresholds prevent churn when turning. Normal frustum culling handles view visibility. The 387 authoritative world collision meshes remain resident; initial GLB setup is still not fully streamed. Vegetation and detail cells unload independently.

## Acceptance evidence

**805 checks passed, zero failed.** Traffic network 26, street behavior 90, neighborhood expansion 56, imported porch movement 50, route/transitions 34, cases/living neighborhood 157, streaming 19, graphical cars 34, graphical UI 54 (zero backend skips), movement/camera fixtures 88, and original game 197. The full 131-point walking route and all six cases pass. Logs are under `.work/logs/dense-final-*`; movement fixtures are in `.work/logs/dense-movement.log`.

The near-traffic test runs the complete scene for 45 simulated seconds with pedestrians, parked cars and nearby vehicle collision active: 11 cars observed nearby, 10 traveled over 8 m while physically active, six still progressed in the final 15 seconds, and no same-direction physical overlaps were detected. Another 60 seconds exercises distant simulation, followed by reservation handoff and queue-order regressions. Cars can still wait through congestion; the two longest waits in the final snapshot had moving reservation owners, not stuck owners or red-light reservations. The network is a lightweight driving simulation, not a full GTA traffic implementation.

Rendered review covers the 18 storefronts, porch railings/stairs, rear entries, parks, police patrols, repaired Dumbarton corner, formerly steep path and map. The final captures show the paved bank removed and the barber entrance clear. Large PNG captures and local logs are deliberately excluded from Git; the capture scripts under `godot/tools/` can regenerate them. Small evidence files remain included: [runtime counts](world-report.json) and [the independent mesh audit](geometry-audit.json).

The original-block smoke test also prints a nine-resource shutdown diagnostic after its passing assertions. Final city suites have no parse/script errors. Export/import encountered non-blocking editor thumbnail/settings-save warnings; the imported geometry, collisions, renders and runtime suites were verified successfully.

## Active-play performance

Measured on NVIDIA GeForce RTX 3070 Ti, Godot 4.7.2 Forward+/Vulkan. Both samples render actual 1920 × 1080 at 100% scale, Balanced quality, VSync off and uncapped frame rate. Normal movement input, chase camera, HUD, collisions, all population systems and 72 moving cars remain active. Builds, graph indexing and other engine runs finished first. Timing uses wall-clock frames, with startup and screenshot writes outside the sample.

| Metric | Starting route | Northern route, point 80 |
|---|---:|---:|
| Sample | 15.001 s | 15.008 s |
| Delivered average FPS | 149.26 | 182.70 |
| Median frame time | 6.585 ms | 4.971 ms |
| 95th-percentile frame time | 10.320 ms | 9.838 ms |
| Worst frame | 29.309 ms | 30.567 ms |
| Median draw calls | 1,787 | 1,223 |
| Player distance | 57.02 m | 57.11 m |
| Stalled movement time | 0 s | 0 s |
| Warm-cache startup | 12.857 s | 12.744 s |

Both samples satisfy the active-play validity checks. Included raw evidence: [start metrics](performance/start/metrics.json) and [north metrics](performance/north/metrics.json). The corresponding PNGs stay in the local artifacts directory. These short local samples do not guarantee performance on every view or hardware configuration. They are slower than the previous 249-person/eight-car build's 201/310 FPS samples; the population, traffic and terrain workload increased substantially, so no speedup is claimed. Separate streaming tests verify real unload/reload and preserved collision; these short walks are not a cold-streaming stress test. Engine CPU-monitor maxima can retain startup observations, so measured wall-clock frame times are the acceptance figures.

Three native GPT-6 Astra/high agents handled geometry, movement/camera and traffic. The lead integrated crowd/map/business data, serialized engine validation and reviewed rendered output. No Claude or Cursor calls were used.

## Publication check

The publication set contains 1,021 files, approximately 122 MiB before Git compression/history.
It includes both playable versions, their model/video/material assets, runtime metadata,
generators and tests. Local build/source-download caches, imported Godot caches, PNG captures,
generated knowledge graphs and the machine-specific shortcut remain excluded. Seven small
acceptance/metrics files are retained. A fresh copy containing only the publication files
imported successfully, then passed 157 neighborhood checks and 197 original-game checks.
The Windows launcher discovers Godot through `GODOT_EXE` or PATH and imports changed assets
before launching; Godot itself is installed separately.
