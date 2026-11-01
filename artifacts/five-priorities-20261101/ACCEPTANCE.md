# Five non-mission priorities — November 1, 2026

All five priorities are implemented and integrated. The updated source launcher and verified standalone build are ready.

Scope: performance/stability, bicycle and walking feel, police-response clarity/reliability, neighborhood activity/audio, and safe checkpoint persistence. No new cases, population cuts, model changes, or return to player combat/drivable cars/alignment.

## Changes

1. **Performance and stability.** Fixed an NPC LOD render-layer transition that left stale light/geometry pairings in Godot Forward+ and produced renderer errors when leaving the city. Hide geometry before changing its render mask, then restore its prior visibility. LOD distances, appearance, population and simulation rates are unchanged. Removed a temporary joined vehicle-fleet array from intersection clearance checks. Added opt-in detailed physics timing and an immutable-source, offscreen sustained benchmark.
2. **Bike and walking feel.** Corrected repeated pedal-speed loss after recoil, incorrect steering deflection when brushed by a faster car, and ejection directed into an oncoming car. Smoothed the camera subject/boom across mounting, dismounting and crash recovery; the explorer's own coarse bicycle hull no longer obstructs their camera. Real walls and other cars still obstruct it. Recovery keeps the explorer grounded and avoids a distant get-up teleport. WASD steering remains independent of camera direction; Space hops, Shift pedals hard. Existing walking turn rules and player size are preserved.
3. **Police response.** The phone displays actual dispatch stages, bounded history and a useful next action. No invented ETA or progress percentage. Report buttons describe what they will do, repeated notifications coalesce, and notices reach the HUD when the phone is put away. Blocked routes exclude failed officers from the call; lost officers release their patrol hold; failures have bounded retries and truthful messages. Arrival is required before scene handling. Reloaded unfinished reports say their outcome is unknown rather than claiming officers are still approaching.
4. **Neighborhood activity.** Nearby groups periodically shift attention toward conversation partners or visible court activity. Daily residents can take short walks on existing route edges, pause, then retrace their path and resume their schedule. These behaviors yield to fights, custody, death and bicycle reactions. The same 1,200 ambient people, 40 daily residents and 90 traffic vehicles remain. Three shared positional audio voices provide restrained air, bird and actual basketball-impact sounds; four original generated clips total about 526 KB. Pause, focus and audio settings are respected.
5. **Checkpoints.** A stopped, grounded, steady bicycle with a clear frame and safe standing fallback can be saved without dismounting. Loading restores the bicycle pose, rider and chase view; a blocked pose gives an explained standing fallback. Unsafe manual/autosaves coalesce into one request and complete at the next safe opportunity, with bounded write retries. Existing police, incident, crash and fight barriers remain. The save container stays version 4 with an optional bicycle section; older readers see a safe standing position.

## Performance evidence and limits

Profiling attributed 96% of the previous aggregate traffic CPU time to actual vehicle updates, not bicycle, police, incidents or basketball. Most vehicle CPU work is per-car script bookkeeping; the ground-probe call count was much smaller than total vehicle ticks. Largest recorded frame stalls occurred at forced cross-district benchmark teleports, so those measurements must not be represented as ordinary walking FPS.

An attempted reusable route-result dictionary increased measured time per call by about 7%; it was reverted. The retained intersection allocation cleanup has a structural benefit, but its standalone FPS benefit is not established. Background videos remained running as requested. Do not treat differences between individual timing runs as a causal speedup.

The LOD/light fix has stronger evidence: isolated light teardown and actual city-to-main-menu transition both pass without the previously reproduced renderer errors. The menu test also verifies music remains playing across the transition. Test shutdown waits briefly for asynchronous audio cleanup outside the measurement window; no production music fix is claimed.

### Final frozen before/after pair

Two 180-second samples, 1280×720 Balanced, scale 1, uncapped, identical harness and eight district/day-night phases. Implementation workers were finished; the user's background workload remained. These are observational timings, not a proof of causal FPS improvement.

| Metric | Original `c77e972` | Updated |
|---|---:|---:|
| Frame median | 3.633 ms | 3.643 ms |
| Frame mean | 4.883 ms | 4.933 ms |
| Frame p95 | 10.156 ms | 10.234 ms |
| Frame p99 | 12.994 ms | 12.983 ms |
| Maximum frame, including deliberate relocations | 264.489 ms | 272.996 ms |
| GPU p95 | 3.721 ms | 3.751 ms |
| Draw calls p95 | 1,134 | 1,134 |
| Renderer errors on city teardown | 6 | **0** |

Overall timing is essentially flat with the added activity and new systems; the clear result is the renderer stability fix. Source snapshots, complete traces, native memory telemetry and per-phase results remain in `.work/five-priorities-20261101/performance/baseline-v3/` and `candidate-v3/`. This short comparison is not a long-session memory-leak proof or a benchmark at the user's native display resolution.

Both runs passed 37/37 active-world checks and retained full population with zero unexplained orphan nodes. Native engine exits were both 0; the old build's validation wrapper correctly failed because of the six renderer errors. The candidate wrapper and engine both exited 0. NPC plus daily-resident mean CPU time rose by about 0.104 ms per physics tick in the pair; this is the observed cost alongside the new activity, not an isolated causal measurement. Candidate static/private memory growth was approximately 31.77/29.52 MB versus baseline 25.00/19.87 MB; the fixture retains samples, and candidate ending private memory was lower. A longer controlled soak is needed before drawing leak conclusions.

## Validation

- Bicycle feel: 52 passed; crash camera maximum movement 0.12 m/frame, previously 4.72 m/frame in the same scenario; threshold was not relaxed.
- Bicycle persistence hooks: 58 passed. Curb matrix: 2,616 passed across 277 crossings. Crash suite: 88 passed.
- Real-city bicycle session: 181 passed, zero failed; crossings occupied by live traffic were skipped and recorded.
- New mounted provider/schema/queue fixture: 113 passed. Final actual-city mounted save: 31 passed; existing world-save: 86 passed; incident-save: 75 passed. Walking/camera regression: 114 passed.
- Neighborhood activity: 16 passed; resident recovery: 11 passed; existing crowd-idle behavior and new audio runtime tests passed. Offline audio generation: 3 passed; phone source contracts: 12 passed.
- Independent native review found and re-reviewed fixes for lost officer coverage during scene clearance and active reports hidden by newer records. Final police status run: 94 passed, zero failed, with two real replacement assignments. The subsequent one-string queued-label correction (“Waiting for a response”) was covered by the final rendered phone check and visual review.
- Existing police assistance: 36 passed; lifecycle: 41 passed; police audit: 12 passed; incidents: 72 passed; phone follow-up: 18 passed; case/incident audit: 50 passed; phone storage/context/input: 124 passed. Intersection clearance: 358 differential comparisons, zero failures.
- Rendered police page: 51 passed across five states at both 1280×720 and 1600×900. Root visually reviewed all five states at 720p plus the queued page at 900p; handset controls and text remain on screen, with scrolling for long history.
- Full rendered foundation acceptance: 80 passed, zero failed, including actual input, private checkpoint reload and truthful duplicate-report handling.
- Final paired sustained benchmark: complete; updated build exits cleanly.
- Standalone `five-priorities-20261101-r1`: export, boot, fresh gameplay, API save/reload, and ordinary graphical startup automatic restore all pass. The build's source/import-cache directory was made unavailable before runtime tests, and the private installed copy was checked for unwanted writes. Source runtime fingerprints remain unchanged. ZIP integrity verified; SHA256 `b6d97706418c8a892e53d49654f969d49ebc3c8c0425f69f22a74bad45d47ff6`.
- `graphify update .` completed; whitespace checks pass. All test engines exited; no desktop control was used.

### Legacy test limitations

Two older suites still assume enabled player car-driving and armed loadout restoration: `city_driving_smoke` fails at boarding before aborting, and `city_world_persistence_smoke` has 132 passes and six failures on retired driving/equipped-weapon assumptions. These are not counted as passing current-policy acceptance; production combat/driving remains disabled. The old `city_save_story_context_audit` direct entry also fails to bootstrap the `G` autoload before statically loading the puppet. Current mounted/world/incident save tests and rendered foundation acceptance use the correct autoload-aware runners and pass. The phone source test was updated from its stale 20-person expectation to the already-shipped 40-person roster.

## Boundaries

Only stationary riding is persisted; momentum and arbitrary parked-bike locations are not. Live police simulations remain unsafe to save; durable incident records survive. Nearby activity is bounded, not a new citywide planner. Audio has automated runtime/asset checks but has not received a subjective listening review during this pass. No desktop control or personal save profile was used.

## Work allocation and reproducibility

Bicycle, persistence and police implementation used verified `claude-opus-5-5` workers at MAX effort, with session persistence disabled. Native `gpt-6-astra` HIGH workers handled performance investigation, activity, audio and independent reviews. Root integrated changes and exclusively serialized engine runs. Scratch logs, immutable source snapshots and worker receipts are under `.work/five-priorities-20261101/`; large captures/builds remain local. Durable integration contracts accompany this report.

The normal `Play Pen Lucy.lnk` launcher runs the updated source project. Generated builds, caches, captures and personal saves are excluded from Git; source, required audio assets, tests and these small reports are included.

Detailed timing/phase/memory analysis: [PERFORMANCE.md](PERFORMANCE.md). Compact machine-readable results: [metrics.json](metrics.json). Standalone files: `artifacts/priorities-five/release/five-priorities-20261101-r1/`; verified ZIP beside that directory. Remaining performance priorities are bulk traffic bookkeeping and cell activation during long-distance relocations, followed by a longer controlled memory soak.
