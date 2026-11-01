# Vehicles, courts and project audit — 2026-10-30

## Delivered

- Parked and moving vehicles share model-specific lower-body and tapered-cabin convex hulls. Police add a fitted lightbar shape. Hoods and shoulder space are no longer blocked by the old 2.35 m tall box. Exact capsule confirmation rejects false bumper-corner hits, including tested 5/10/20 cm near misses.
- Jump launch speed 10.4 m/s with gravity 22 gives approximately 2.37 m feet elevation at 60 Hz. Physical lateral jumps land on all four model roofs. A moving sedan carried an idle passenger 6.79 m over 6.86 m of vehicle travel with 0.07 m relative drift, 150/150 upward floor contacts, and no false impact.
- Traffic consumes full movement distance across fine curve samples, rounds lane vertices and faces its actual motion. Intersection reservation release uses rear-bumper clearance independent of sample density. High-speed approaches now consider braking distance and a discrete stopping ceiling: maximum speed drops 0.066518 m/s at 60 Hz and 0.39465 m/s at dt=0.1, within the 4 m/s² braking bound.
- Cached rider/exclusion checks and an enclosing-box empty-space rejection reduce repeated convex queries. All actual collision shapes, endpoint checks and conservative rotational-sweep coverage remain.
- 22 basketball courts: 6 full and 16 half, 28 hoops. Covers all seven mapped park regions and other usable greens. The audit inventories 48 grass components>=250 m²; 24 narrow strips and 2 constrained terrain remnants are explicitly excluded. Courts are scenery, not a basketball minigame.
- Removed 29 trees and 62 shrubs where needed; 1,780 trees and 324 shrubs remain. Raised courts have solid retaining edges and two access ramps; maximum fill 0.681 m, court grade<=1.5%, access slopes<4°. Backboards and support arms now have 56 accurately fitted static boxes. Ground, ramps, poles, overhead jump contact and all 160 park residents are physically checked.
- Ambient walkers turn in place before reversing, retain obstacle/player yielding, and follow graphics-quality visibility changes without rebuilding their allocation.

No desktop control was used. Tests ran headless or in hidden offscreen windows using the isolated project test profile. The player's running game was not stopped.

## Performance

15-second 1920×1080 Balanced offscreen walks with normal input, collision, HUD, active mission guidance, 1,215 NPCs, 90 moving cars and 144 parked cars. Each completed about 57 m without a stalled movement window. Final data: [first final run](performance-final/metrics.json), [repeat](performance-repeat/metrics.json), [profile before hot-path changes](performance-profile-before/metrics.json).

| Run | Delivered FPS | p95 frame ms | p99 frame ms | Worst frame ms | Median draws |
|---|---:|---:|---:|---:|---:|
| Historical streets pass | 178.87 | 8.975 | 11.290 | 29.076 | 1636 |
| performance-profile-before | 137.14 | 11.360 | 22.400 | 43.181 | 1642 |
| performance-final | 207.40 | 8.976 | 11.248 | 40.485 | 1635 |
| performance-repeat | 198.86 | 9.399 | 11.843 | 40.990 | 1636 |

An earlier unprofiled run in this session delivered 132.38 FPS, p95 11.958 ms, worst 50.452 ms. The spread is material: these are short offscreen samples on the user's active machine, not a controlled foreground A/B. Do not attribute the entire FPS change to the patch. Directly timed traffic tick median changed from 2.423 ms to 2.331 ms (3.8% lower in the first final run); NPC median remained about 0.5 ms. The final sample retained all population/traffic targets. No broad density reduction was applied.

The benchmark now optionally records fresh per-component physics samples with `--profile-city`, reset after warmup; normal play does not record them. The engine's separate CPU monitor values can lag and include older peaks, so they are not a trustworthy attribution of an individual measured frame. Wall-clock frame distributions and the new component timers are the useful evidence.

## Two independent audits and next priorities

[Root audit](root-audit.md) was written before reading [Opus 5.5 high's read-only audit](opus-audit.md). The raw Opus report describes a mid-change snapshot, not final acceptance. Actual model metadata is recorded in [review provenance](review-provenance.json). Both audits have explicit coverage limits; original Godot gameplay was regression-tested, while the web prototype received syntax checks rather than a browser playthrough.

1. **Long-route streaming performance.** Bake vegetation near/far cells ahead of play and avoid synchronous mesh/normal rebuilding on LOD transitions (`city_vegetation.gd:75,121`). Prebuild building/collision/placement products rather than importing the entire city and constructing collision at startup (`pen_lucy_level.gd:96,113,293`). The starting view still holds 17 of 21 building-detail cells with a 240 m load radius; introduce a useful middle-detail facade representation before reducing that radius aggressively. A 57 m walk cannot certify all cell-boundary hitches; measure p99/worst frames across the neighborhood.
2. **Traffic reliability and behavior.** Add long-running near-physics junction stress tests, crossing/opposing overlap checks and safe stuck-car recovery. Yellow-light stopping policy, the blanket 4.2 m/s junction cap and single-car reservations remain simplistic. Static audit suggests possible gridlock, but the present tests do not prove a permanent deadlock. Never release an occupied junction or teleport a visible car merely because a timer expires.
3. **Resident identity, routines and saved progress.** The 1,200 ambient residents include 128 short-corridor walkers; most do not have individual routines/dialogue. Six playable cases and authored contacts work, but city progress is intentionally current-visit only. Add stable resident/case IDs, versioned saves and data-driven schedules/dialogue, with cheap distant scheduling and nearby full actors, before scaling authored content toward 75% unique residents.
4. **Remaining movement/pause edges.** Standing on moving roofs is verified; landing on an already moving car needs a dedicated regression. Jump-off horizontal platform momentum is overwritten by the current controller, and a passive fall can continue while controls are disabled even though active jumps freeze. Those are distinct remaining controller limitations. Camera compression around passing vehicles deserves a bounded foreground feel check only if the user reports it.
5. **Release hardening.** Add exported-build/clean-clone smoke coverage, content-hashed export-safe building caches, cache generation cleanup and version-checked/locked imports. The original game still emits its pre-existing 20 ObjectDB/8 resource shutdown-retention warning despite 197 passing checks; investigate repeated transitions before labeling it a growing gameplay leak.

### Review dispositions

Fixed and tested after Opus: early corner contact, fast approach snap stops, missing overhead hoop collision, backward walker turn motion and stale existing crowd draw ranges. Jump-height and 160park population assertions remain intentional acceptance targets and pass; they were not weakened. Geometry-cache rebuild cost is confirmed in code, but attribution of a particular stutter remains unproven. Possible transform synchronization delay, permanent traffic deadlock and camera pumping remain hypotheses. Global video/audio settings carrying into the original game may be intended; they should not be blindly restored without deciding the product behavior. The renderer/streamer draw-range ownership is an architectural cleanup, not demonstrated missing-building behavior.

## Validation

| Suite | PASS | FAIL |
|---|---:|---:|
| city_vehicle_precision_smoke | 46 | 0 |
| city_vehicle_impact_smoke | 35 | 0 |
| city_traffic_optimization_smoke | 12 | 0 |
| city_vehicle_jump_smoke | 32 | 0 |
| city_jump_smoke | 15 | 0 |
| city_traffic_network_smoke | 29 | 0 |
| city_courts_smoke | 188 | 0 |
| city_crowd_motion_smoke | 10 | 0 |
| city_yard_smoke | 19 | 0 |
| city_cars_smoke | 34 | 0 |
| city_life_smoke | 325 | 0 |
| city_ui_smoke | 84 | 0 |
| city_mission_navigation_smoke | 9 | 0 |
| city_movement_smoke | 114 | 0 |
| city_streaming_smoke | 19 | 0 |
| smoke | 197 | 0 |

Also: 10 Python source geometry tests; 17 web JavaScript syntax checks; strict offscreen GPU walker test 10 PASS (72 stationary turn samples, zero physical/rendered foot drift); offscreen court render/physics 163 PASS before the later invisible overhead collider addition. Headless UI skips one graphics-only assertion, parked-car checks skip GPU spinner readback, and headless crowd skips only dummy-renderer MultiMesh readback; its physical checks remain strict and GPU readback passes. Final court 188 PASS includes the added backboard jump and all 22 actual ramp traversals. Original shutdown warnings are documented above rather than counted as clean teardown.

Court/source evidence: [coverage audit](coverage-audit.json), local screenshot `courts/park_court_0.png`. Source support probe checked 99,400 points; incremental publication preserved the city GLB and Rose Hill's 24 bay windows. Required game data is included; screenshots, caches and large logs remain Git-ignored. No commit/push was requested in this turn.

Team: native GPT-6 Astra high agents owned vehicles/traffic and courts/crowd; Claude CLI `claude-opus-5-5 --effort high --no-session-persistence` completed the independent audit after an initial network-retry attempt. Root integrated, audited, rendered and tested; root model/effort metadata is not exposed.
