# Rendering audit and shader implementation — 2026-10-30

The main measured costs were CPU-side rendering submission and vegetation mesh construction, rather than GPU saturation. The implemented pass retains the neighborhood population and full-detail building geometry. [Shader research](../living-world/shader-research.md) and the [implementation matrix](shader-implementation.md) are linked separately so the proposed work and shipped work are distinguishable.

## Implemented

- **Building materials:** compatible finishes now use full-float vertex color/roughness palettes. Building surfaces fell from **677 to 317** across the same 21 chunks and **1,160,637 full-detail triangles**. Glass, multipass materials, authored custom data, collision and shadow surface mappings are preserved. Native LOD generation protects finish seams.
- **Streaming/cache:** reloaded materials reconnect to canonical shared resources. One owner controls chunk LOD. Palette meshes persist locally. Effective shader defaults are normalized in cache keys: Godot filling unset defaults during serialization can no longer invalidate an otherwise identical cache.
- **Vegetation:** at most one uncached cell mesh is built per presence refresh, nearest first. Old visuals remain until replacements are ready, and trunk collision updates immediately. Initial coverage prepares behind the loading screen. A bounded 32 MiB historical-variant cache avoids repeated threshold rebuilds; precomputed sway weights and GPU normal correction remove repeated scripted construction work.
- **Simulation:** primitive walkers use three staggered 20 Hz groups and a reused query; unchanged visibility distances no longer trigger redundant writes. Full actors use short reusable walking-ground probes instead of allocating a long placement ray each step.
- **Lighting:** daytime quality settings now remain correct when selected at night. A physical sun updates smoothly while a separate shadowless sky-only sun controls the slower sky/radiance updates. The eight-light streetlamp budget remains.
- **Materials:** existing brick, paint, concrete, grass, asphalt, glass and road-marking shaders now use material-specific roughness/specular response and spatial filtering of fine distant wear. No full-screen grain, clay treatment, extra textures, transparency or expensive GI effect was added.
- **Next-priority persistence:** stable world checkpoints now load automatically and save every 30 seconds on safe ground, on normal window close, and through **Esc → Save progress**. Clock, resident routes, case progress/rewards, position and stable equipment persist. Active combat/airborne states wait; old, malformed and future-version files are preserved rather than silently overwritten. This is one chapter slot, not an interiors or full life-simulation save system.

## Matched rendering measurements

RTX 3070 Ti, Godot 4.7.2 Vulkan/Forward+, **1920×1080**, Balanced, 100% render scale, project **4× MSAA**, uncapped/VSync off. Each row is a fresh process with a 20-second actual-input walk, collision, live clock, NPCs, traffic, HUD and an accepted mission route. No population reduction. The eight runs below used matching source hashes and explicit treatment flags. Screenshots and an additional 1.3-second cooldown precede sampling; GPU and render-CPU timers are measured directly.

| Run | Delivered FPS | Frame median / p95, ms | GPU median, ms | Render CPU median, ms | Draw calls, median |
| --- | ---: | ---: | ---: | ---: | ---: |
| Legacy finishes, no palette A | 182.7 | 4.585 / 9.361 | 2.051 | 2.209 | 1,583 |
| New finishes, no palette A | 183.2 | 4.536 / 9.310 | 2.098 | 2.192 | 1,582 |
| New finishes + palette A | 172.5 | 5.009 / 10.088 | 2.145 | 2.147 | 1,342 |
| Legacy finishes, no palette B | 178.7 | 4.541 / 9.893 | 2.057 | 2.178 | 1,581 |
| New finishes, no palette B | 184.4 | 4.492 / 9.217 | 2.119 | 2.189 | 1,584 |
| New finishes + palette B | 200.5 | 4.078 / 9.011 | 2.159 | 1.944 | 1,341 |
| New finishes + palette C | 211.8 | 3.887 / 8.567 | 2.154 | 1.878 | 1,340 |
| New finishes, no palette C | 184.1 | 4.512 / 9.272 | 2.110 | 2.187 | 1,585 |

The shader-only change added approximately **0.05–0.06 ms median GPU time**, with essentially unchanged delivered FPS. Palette batching removed about **15% of total draw calls**; later B/C repeats used about **13% less render-CPU time** than the shader-only repeats. They delivered 200–212 FPS versus approximately 184 FPS, but **the first palette run was slower** and is deliberately retained above. Do not describe every launch as 200+ FPS. GPU clocks also varied during the first palette and legacy-B runs; the evidence does not isolate one cause for their slower frame delivery.

Palette A built all 21 meshes; B hit three and rebuilt 18 because of the subsequently fixed shader-default fingerprint defect; C hit all 21. First generation took approximately 3.9 seconds behind loading, versus about 0.3 seconds for a fully cached load. Estimated reported video memory rose from approximately 486 to 494 MiB. These are engine-reported resource figures, not a full system memory inventory. The fingerprint fix changes cache setup behavior, not geometry or the timed simulation.

Earlier diagnostic source states (`baseline-live` and `current-no-palette`) are retained but are not the controlled shader/batching comparison. The initial diagnostic showed GPU median 2.084 ms versus render CPU 2.767 ms and approximately 1,586 draws. Per-frame event tracing then found the ten largest tagged frames correlated with vegetation construction. Median frames tagged with a tree build declined from 13.56 ms before the construction-loop optimization to 11.88 ms in legacy-A and 11.24 ms in final-C. They can still reach approximately 20 ms; this pass does **not** claim all traversal hitches are gone.

See [machine-readable metrics](performance-summary.json), individual `metrics.json` files and [validation](validation.json). GPU timings exclude presentation and can lag; render-CPU time excludes game simulation. Do not add unrelated medians together or treat a 20-second route as a whole-map performance guarantee.

## Final cache-fix validation

Three further 20-second runs use a private render target with the playable window's **1920×1080 / 4× MSAA** settings copied explicitly. This is a separate comparison cohort, not pooled with the window-based FPS above. Sources match within this cohort. Both palette runs reuse all 21 meshes without regeneration, confirming the shader-default cache-key fix.

| Treatment | Delivered FPS | Frame p95, ms | Render CPU median, ms | GPU median, ms | Draws |
| --- | ---: | ---: | ---: | ---: | ---: |
| Final A | 217.5 | 8.433 | 1.830 | 2.111 | 1,340 |
| Same shaders, palette disabled | 192.3 | 9.114 | 2.088 | 2.046 | 1,584 |
| Final B | 216.0 | 8.688 | 1.803 | 2.090 | 1,340 |

All three passed active-play validation. The approximately 15% draw reduction and 12–14% render-CPU reduction repeat with the latest source. No claim is made that private-target FPS equals visible-window FPS. [Final source hashes](final-source-provenance.json).

## Validation and visual evidence

**966 passing checks** across the recorded suites (duplicate comparison profiles excluded). Focused suites cover palette geometry/material identity, vegetation normals/caching, crowd cadence and real GPU feet placement, day/night transitions, save corruption/recovery, all 20 resident schedules, combat, movement, jumps, traffic impacts, mission routing, UI, and original-block progression. The original smoke fixture now drains its audio streams before shutdown instead of reporting spurious WAV resource leaks.

Real Vulkan captures pass for day, dusk, night, pistol aiming, a daily resident, close Rose Hill finishes and the settings/save UI. Matching palette-on/off Rose Hill images have a mean absolute channel difference of **0.00020 on an 8-bit scale**; only one pixel differs by more than two levels. This verifies close-facade appearance preservation, not all distant LOD silhouettes. The legacy/new-finish comparison visibly changes glass and surface response while retaining authored color and shape.

Local captures: `visual-final/01-day-0900.png`, `02-dusk-1845.png`, `03-night-2200.png`, `06-rose-hill-finishes.png`, `07-save-settings.png`. Image binaries and logs stay out of Git; small reports/metrics are retained.

Two intermediate **hidden-window** benchmark startups failed with Vulkan device loss and corresponding Windows `nvlddmkm` event 153 records (17:17 and 17:38). Both failed runs are excluded; their logs are retained. Private-viewport visual captures succeeded. A private-viewport benchmark path was added to avoid relying on hidden-window presentation and explicitly copies the playable window's antialiasing settings. This is a validation-harness workaround; the underlying NVIDIA/Vulkan cause has not been proven, and no driver or operating-system settings were changed. Initial private-target diagnostic runs without copied MSAA are excluded from playable performance claims.

## Remaining priorities

1. **Smooth the remaining tree-build frames further:** consider prebuilt resources or incremental construction after measuring native commit versus array preparation. Reducing population does not address this measured source.
2. **Traffic CPU:** the 90-car simulation costs about 2.3–2.5 ms per physics tick on this route, versus roughly 0.2–0.25 ms for the 20 daily residents. Instrument ground/support, compound-clearance and junction-control portions before changing safety behavior. A wholesale Rust rewrite does not remove draw submission or physics-query costs; see the [Rust assessment](../living-world/rust-assessment.md).
3. **Longer mixed-route and dusk traversal coverage:** the current measurements do not fully characterize distant chunk reloads, all parks or dense intersections. Keep the recorded GPU startup fault visible until its cause is isolated.
4. **Content:** broaden authored routines and dialogue after these budgets are stable. The current 20 residents remain a bounded authored pilot.

The independent [Opus high audit](opus-audit.md) is a mid-change read-only snapshot. Its missing-integration findings were completed later; its proposed far-tree supercells, smaller building chunks, lower global shadow filtering, and replacement noise hash were not blindly enabled. They remain experiments that need measured benefit and visual parity. [Shader implementation decisions](shader-implementation.md) cover every research recommendation.

## Team and provenance

Root integrated, profiled and accepted the work (root model/effort not exposed). Native workers: Astra high for rendering/cache and persistence, Sol high for crowd/lighting and fixture cleanup. Claude CLI Opus 5.5 high completed the independent audit; Opus 5.5 max wrote the shader implementation/tests, then reached its time limit before a final report. Root finished corrections and validation. Every Claude call disabled session persistence. [Receipts](review-provenance.json). No desktop control, Git commit or push occurred in this pass.
