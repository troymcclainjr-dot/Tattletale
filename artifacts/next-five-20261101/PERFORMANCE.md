# Performance evidence - next five priorities

The player relocation fix reduces the measured collision stall without changing geometry, masks, population, or rendering quality. **The final integrated 600-second stationary endurance and 180-second traversal passed all 19 and 37 checks respectively.** Machine-readable evidence is in [compactmetrics.json](compactmetrics.json).

## Matched relocation comparison

Both frozen runs used the same 32-second, eight-phase rendered diagnostic at 1280x720, balanced quality, scale 1, FOV 68, and uncapped frames. Both passed with 1200 ambient residents, 40 daily residents, and 90 traffic vehicles. The 1,826-file snapshots share commit `b8e04bc19d1b602973b651a9d39c0bf02f3b6025` plus identical traffic/streaming instrumentation and harness; only the 22-line player bounds fix differs. This short diagnostic is not the final 180-second traversal acceptance.

| Measurement | Baseline | Candidate |
| --- | ---: | ---: |
| Worst player collision call | 213.816 ms | 3.316 ms |
| Matched Wyanoke collision call | 96.797 ms | 3.316 ms |
| Greenmount day worst frame | 224.587 ms | 45.191 ms |
| Greenmount night worst frame | 255.861 ms | 40.427 ms |
| Overall worst frame | 255.861 ms | 56.406 ms |
| Median frame | 4.046 ms | 4.611 ms |
| p95 frame | 12.872 ms | 13.492 ms |

The peak collision cost fell 98.45%. The matched Wyanoke event has identical final position, contact normals, depths, and points. All eight spawn capsule overlap lists are empty in both runs; contacts are ordinary terrain contacts of roughly 0.9 mm depth. Both source receipts are unchanged and exit cleanly.

During the matched diagnostic runs, user videos and a separate playable game remained active. **Candidate median/p95 are worse, so no overall FPS improvement is claimed.** The demonstrated result is the removal of the repeatable large relocation collision stall. Remaining 40-56 ms transition frames include detail-provider refresh work around 22 ms plus normal physics/rendering; all stutter has not been eliminated.

## Why the fix is narrow

The investigation separated streaming activation, pipeline compilation, render intervals, native physics, player callbacks, and individual player stages. `move_and_slide` accounted for the 200 ms stalls; camera, pose, and input stages stayed below 1 ms. A separate distant, non-mutating collision query showed deferred global shape flushing cost at most 0.021 ms. Clear spawn probes ruled out placement inside buildings, vehicles, or props.

Godot Physics stores kinematic sweep bounds through the following tick. After a large placement, the next query can use bounds spanning the old and new locations. `city_player.gd` now re-submits the unchanged capsule owner transform for two physics ticks after a discontinuity above the existing 3 m camera-cut threshold. It still runs every original collision test. Geometry, enabled state, layers, masks, platform handling, movement, and camera behavior remain intact. The helper catches existing placement entry points without changing their APIs.

The relevant native implementation is [kinematic integration](https://raw.githubusercontent.com/godotengine/godot/4.7/modules/godot_physics_3d/godot_body_3d.cpp), [cached collision bounds](https://raw.githubusercontent.com/godotengine/godot/4.7/modules/godot_physics_3d/godot_collision_object_3d.cpp), and [motion-query candidate culling](https://raw.githubusercontent.com/godotengine/godot/4.7/modules/godot_physics_3d/godot_space_3d.cpp). All seven movement/collision regressions completed with clean exit 0 and zero failures: movement 114 checks, jumping 15, vehicle jumping/moving support, vehicle impact, bicycle feel 52, bicycle curb matrix 2,616 checks across 277 crossings, and bicycle contact integration. These cover actual movement, platform, impact, mounting/recovery camera, and curb behavior after the bounds fix. `compactmetrics.json` records individual log paths and SHA-256 hashes.

## Traffic and emergency integration

Concrete vehicle access and a per-vehicle damage flag snapshot remove repeated dynamic property lookups in traffic control/leader loops. The differential fixture passes 12,000 control/state comparisons and 7,200 leader comparisons. Six alternating AB/BA timing pairs of 20,000 calls each show median paired changes: far approach -3.69%, leader wait -4.27%, foreign reservation -1.06%, blocked outgoing -3.08%, unavailable continuation -1.12%, held reservation -1.83%. Red light is +0.92%, an inconclusive result. These are small per-gate CPU observations, not an FPS claim. An old stop-dwell timing branch advanced during warmup; it is excluded from stop-sign performance claims and the fixture has been corrected.

The initial external emergency-body registry validation passed 22 headless checks; subsequent functional integration counts are recorded in [ACCEPTANCE.md](ACCEPTANCE.md). It admits up to 4 real bodies, derives conservative hull extents, includes them in presence/leader/outgoing-lane safety, and never adds them to the 90-car population. This is EMS safety integration, not a performance improvement.

## Final integrated stationary endurance

The frozen 1,944-file `next-five-integrated-final` snapshot completed **600.006 measured seconds** after 30 seconds of warmup at 1280x720, balanced quality, scale 1, FOV 68 and uncapped frames. All 19 checks passed with clean exit 0, no timeout, no engine errors or warnings, and no telemetry errors. At completion of performance validation, both the frozen snapshot and current source matched the recorded manifest. The renderer recorded 130,445 frame intervals; all 121 periodic samples retained 1200 ambient residents, 40 daily residents and 90 traffic vehicles. The world clock and traffic remained live, with no streaming failures or orphan nodes.

| Frame measurement | Result |
| --- | ---: |
| Mean | 4.600 ms |
| Median, histogram upper bound | 3.4 ms |
| p95, histogram upper bound | 9.7 ms |
| p99, histogram upper bound | 12.4 ms |
| Exact maximum | 41.718 ms |

The fixture retained zero per-frame/physics timing arrays, 640,032 bytes of fixed histograms and 121 five-second metric samples. Time percentiles are 0.1 ms upper-bin bounds; means and extrema are exact.

| Memory over measured interval | First | Last | Change | OLS trend |
| --- | ---: | ---: | ---: | ---: |
| Engine static | 863.144 MiB | 864.921 MiB | +1.777 MiB | +0.158 MiB/min |
| Native process private | 2978.867 MiB | 2976.641 MiB | -2.227 MiB | -0.089 MiB/min |
| Native working set | 2056.238 MiB | 2053.387 MiB | -2.852 MiB | -0.161 MiB/min |

Nodes returned from 11,146 to 11,146, with a peak of 11,169; objects increased by 24 and orphan nodes stayed at zero. Native process telemetry contains 2,311 samples within the measured interval. This run shows no native process-memory escalation over ten minutes. The small positive engine-static trend is reported rather than treated as proof of indefinite leak freedom; fixture success does not itself enforce a memory-growth threshold.

Background videos remained allowed and no personal applications were stopped. Specific active applications were not inventoried; telemetry observed an average of 1.764 logical cores used outside the engine. The earlier separate-game observation is not asserted for this final run. These are contended measurements of the integrated build, not a matched FPS comparison.

The earlier 60-second smoke remains in `compactmetrics.json` as harness validation.

## Final integrated traversal

The same unchanged 1,944-file snapshot completed **180.016 measured seconds**, passing all 37 checks with clean exit 0, no timeout, no engine errors or warnings, and no telemetry errors. All eight district/day-night phases completed with full 1200/40/90 population and no streaming failures. The player walked 277.474 m through normal collision-aware input; Greenmount phases used stationary intersection camera sweeps. Real P/2 phone-camera input opened and closed without pausing. All eight relocation capsule probes were clear, and the world released before shutdown.

| Frame measurement | Result |
| --- | ---: |
| Recorded frame intervals | 38,985 |
| Mean | 4.617 ms |
| Median | 3.234 ms |
| p95 | 11.225 ms |
| p99 | 15.357 ms |
| Maximum | 49.959 ms |

Transition profiling is included in these timings. The largest player collision call was **3.351 ms** over 10,801 calls. Remaining slow frames are visible: 13 exceeded 33.333 ms, none exceeded 50 ms. The worst frame occurred after the Greenmount night relocation and contained 25.103 ms of process-script time plus physics and rendering work. Across the run, detail refresh reached 26.881 ms; its individual vegetation provider reached 16.964 ms. These observations do not support an all-stutter-eliminated claim.

The traversal retained frame/physics/transition profiling arrays while changing streamed views. Its engine-static memory increased by 54.236 MiB; that measurement is not a leak test and is kept separate from the bounded stationary endurance above. Orphan nodes remained zero across all 44 periodic samples. Background application contention remained uncontrolled, averaging 2.915 logical cores outside the engine; specific active applications were not inventoried. These final timings are current-build acceptance evidence, not a matched before/after FPS comparison.

## Provenance

`compactmetrics.json` retains result paths, SHA-256 hashes, clean-run receipts, distributions, and summarized microbenchmarks. After performance measurement, only `godot/tools/export_city_release.py` and `godot/tools/priorities_release_probe.gd` changed to correct the standalone acceptance fixture from 17 named actors to 19 (15 base, 2 police, 2 EMS). Gameplay scripts and assets still match the measured snapshot; these later validation-only changes do not alter the recorded performance evidence. Raw logs, frame arrays, and large frozen snapshots remain under `.work/`; they are not copied into this artifact. All engines were launched serially by root, and this worker did not control the desktop or stop the user's videos/game.
