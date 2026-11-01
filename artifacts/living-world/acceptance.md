# Living-world pass — 2026-10-30

Implemented in the playable source project. Restart through `Play Pen Lucy.lnk` / `Play Pen Lucy.cmd` to load it. No desktop control was used: engine checks were serialized headless or in hidden offscreen render targets with an isolated test profile. No commit or push was performed.

## Delivered

- Twenty authored adults with stable IDs, unique names/appearances/dialogue, distinct six-slot daily schedules and home/work/leisure destinations across sixteen preferred streets. The existing 1,200 ambient people and fifteen mission/patrol actors remain. These are authored data, not runtime LLM calls.
- Collision-tested nearby walking; 2 Hz distant logical movement; fade and 100/120m activation hysteresis. Deterministic yielding, swept bypass/backstep recovery, logical space reservations, parked-car clearance and post-combat reconnection handle the reviewed blocking cases. Route preparation now finishes under the loading screen, one corridor per rendered loading frame.
- Shared 48-real-minute day, starting at 09:00, with a clock on the right ledger. Menus/dialogue freeze schedule time and wind time. Day/dusk/night palettes, directional sunlight, shared lamp lenses and a capped pool of eight nearby shadowless lights. Actual heads of 21 existing authored/network fixtures are used; no extra poles or road obstructions.
- Three-click punch combination; pistol with 12-round magazine, reserve ammo, reload, hit feedback and camera/barrel cover checks. Provoked NPCs turn, pursue, telegraph and throw combinations. Recoverable knockdowns preserve mission contacts. At most eight reactive fighters, including temporary promotions from the primitive crowd. Returning actors release their slot within a bounded interval and preserve mission retargets.
- Pistol aim uses a swept over-shoulder camera; unarmed right-mouse orbit remains. The player no longer falls behind menus. First click recaptures the mouse without firing.
- Shared vertex tree wind with fixed roots, bounded sway and expanded mesh bounds; no per-tree CPU animation or added draw calls. [Shader research](shader-research.md) ranks additional material/fog/AO/decal options and distinguishes estimates from measured evidence.

Controls: **1 fists, 2 pistol, LMB attack, RMB pistol aim, R reload**. Click successive punches to chain a combo. WASD/Shift/Space/E/V/M/Esc retain their existing roles. Walk away to disengage.

## Performance evidence

Godot 4.7.2 Forward+, RTX 3070 Ti, verified 1920×1080 target, Balanced quality, uncapped, 20-second active walking samples, live traffic/NPCs/HUD and a case route. Every run covered about 76m with zero stalled windows. Fresh processes and warmup were used; path building is excluded from direct steady-state component samples. Fifteen graphical runs are summarized in [performance-summary.json](performance-summary.json).

The final same-population comparison at fixed 09:00 isolates routine logic:

| Workload | Delivered FPS | Resident tick median | Resident tick p95 |
|---|---:|---:|---:|
| Same 20 people, routines off | 189.51 | 0.119ms | 0.147ms |
| Routines on, A | 189.67 | 0.227ms | 0.331ms |
| Routines on, B | 188.74 | 0.225ms | 0.342ms |
| No daily residents, two population baselines | 184.37 / 188.52 | 0.004ms | 0.005ms |

Routine movement/scheduling therefore adds about **0.107ms per 60Hz physics tick** over the same idle people. The whole provider costs about **0.226ms/tick**, about 1.36% of a 16.67ms physics budget. The route finishes with **3 physical / 17 distant** residents. This is not a benchmark of twenty simultaneously nearby full actors, and it must not be linearly extrapolated to 900 residents. The memory snapshots rose roughly 5MB with the twenty residents, but these are whole-engine snapshots with slightly different streamed residency.

Live-clock runs (normal play) delivered **180.40 FPS** and **157.04 FPS**; the latter is the final release check after moving route preparation under loading. Their p95 frames were 9.483/10.803ms, p99 12.315/14.470ms, worst 43.539/46.194ms. Both were valid, uninterrupted 20s walks. The lower repeat prevents claiming a precise overall FPS cost or unchanged total performance. Direct resident timing remains near 0.23ms; clock/light controller CPU was around 0.006ms median, up to about 0.075ms p99 in the first live run. GPU/radiance work is not included in that controller CPU timer.

The prior StandardMaterial vegetation baseline produced 190.43/186.77 FPS, overlapping the final wind-shader 189.67/188.74 samples; no repeatable FPS penalty can be established here. Same-shader zero-wind runs were 179.84/167.77, further demonstrating run variance. Keep the baseline switches for future controlled GPU investigation. This is not a claim that shaders are free. Streetlight/night rendering was visually checked but not given a separate nighttime FPS guarantee.

Traffic remains the largest directly measured gameplay component at roughly 2.35ms/tick. Existing crowd p95 is around 1.5ms versus a 0.43ms median. Native engine queries are included in these timings. Do not add physics-tick medians to rendered-frame medians or interpret engine sampled CPU monitors as identical per-frame costs.

## Independent audit and fixes

A read-only **Claude Opus 5.5, high effort** review completed successfully through the authenticated CLI, with `--no-session-persistence`. [Provenance](review-provenance.json) records the returned model. The [raw audit](opus-audit.md) describes a moving mid-implementation snapshot; the disposition below supersedes resolved observations.

- H1 backward camera-origin shots: fixed by clipping the aim ray to player depth, rejecting backward endpoints and treating chest/barrel obstruction as nondamaging. Regression passes.
- H2 case conversations during fights: root interaction now refuses while downed or any aggressor remains; normal six-case/dialogue regressions pass afterward.
- H3 permanent resident deadlocks: deterministic yielding, validated passing/backstep and retries; two head-on residents and a stationary crowd obstruction pass physical tests.
- M1 return-slot/health stall: bounded return and demotion at the current physical location, with regeneration based on absence of aggressors. Regression passes.
- M2 stale targets after combat: swept chase breadcrumbs, mission target revisions, nearest patrol point and validated resident reconnection. Regression passes.
- M3 invisible activation stalls/overlap: continued far progress, logical reservations and parked-car route clearance. Regression passes.
- M4 invisible meshes still rendering: fully faded meshes explicitly hide, including exact endpoint handling. Regression passes.
- M7 startup/timing pollution: corridor construction moved behind loading; benchmark waits for completion and resets steady-state counters.
- Root visual review additionally caught a pending night-sky update being skipped after a clock jump, a floating-point cadence boundary, and the aiming reticle obscured by the player's head. These were corrected and recaptured.

## Validation and limits

**892 headless checks across twelve suites passed**, with no script/shader errors in the final logs. Five private offscreen images and full-level integration assertions passed. Headless UI skips its pixel draw comparison; the graphical fixture provides actual rendered evidence. All six cases, movement/wall glide, jump/roof support, vehicle impact recovery, full-day resident transitions, collision/yielding, clock rollover, lamp budget and combat were exercised. The fast combat fixture now allows the audio thread to consume shutdown commands, eliminating its exit-only playback retention warnings. [Validation inventory](validation.json).

Images remain local to keep repository size low: `visual/01-day-0900.png`, `02-dusk-1845.png`, `03-night-2200.png`, `04-third-person-pistol-aim.png`, `05-daily-resident-hotspot.png`. They were inspected without taking control of the desktop.

This is a first content slice. Residents use outdoor frontage destinations; sleeping is a resting pose rather than a simulated interior. Snapshot/save APIs exist but automatic load/resume is not implemented. Combat is recoverable, with no wanted system or permanent deaths. Pursuit uses collision-safe local movement and bounded escape, not full navigation around arbitrary buildings. The profile is a short street walk, not a full-night or hours-long soak.

## Next priorities and Rust

1. Add versioned automatic save/load for cases, clock and resident state; author real destinations/activity animations for these twenty before scaling the roster.
2. Spatially index resident reservations/avoidance before hundreds of schedules (the twenty-person checks are currently linear scans), bake reusable corridors, stagger the existing crowd walker updates and reuse physics queries.
3. Reduce remaining streamed mesh construction hitches and measure traffic decision math separately from native collision queries. The 40–46ms worst frames are still worth addressing.
4. Add traffic night cues, more lamp coverage where warranted, combat animation/audio polish and longer mixed combat/schedule traffic soak tests.

**Do not rewrite all logic in Rust.** Keep dialogue, missions, UI and content in GDScript. Godot rendering/physics is already native; changing the caller language does not remove its work. If measurements isolate a costly numeric traffic/spatial kernel, prototype one batched GDExtension behind the existing API and require matched release-build/clean-export evidence. No Rust speedup was measured or claimed. [Project-specific Rust assessment and checked primary sources](rust-assessment.md).
