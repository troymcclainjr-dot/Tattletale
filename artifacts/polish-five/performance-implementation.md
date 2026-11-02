# Streaming polish: traversal hitch implementation

Files changed: `godot/scripts/city/city_vegetation.gd` and `godot/scripts/city/city_streaming.gd`. New fixtures: `godot/tests/city_streaming_polish_vegetation.gd` and `godot/tests/city_streaming_polish_schedule.gd`. Hooks and semantics are in `.work/polish-five/performance-contract.md`. Population (1200/40/90), quality presets, radii, LOD thresholds, collision shapes/layers and trunk-collider timing are unchanged. No threads were added. This worker launched no engine.

## Measured causes (root's `polish-five-baseline`, 180 s traversal)

- `refresh_with_details` max 21.507 ms (712 calls, avg 6.04 ms). All 11 detail providers ran in one frame every 0.25 s.
- `detail:CityVegetation` max 14.024 ms, avg 2.51 ms. It was the largest share of each refresh. The earlier next-five run measured 18.961 ms / 16.964 ms.
- Frame metrics for that run: max 43.29 ms, p99 17.25 ms, median 2.85 ms.

## Changes

**Vegetation cell merge.** Each plant used to call `SurfaceTool.append_from()`. That fetches the template's arrays back from the RenderingServer for every plant (on Forward+ this is a GPU buffer readback) and copies every vertex through SurfaceTool's large per-vertex struct. CUSTOM0 then took four GDScript writes per merged vertex. Now:
- Setup keeps each template's CPU arrays.
- Merging appends `Transform3D * PackedVector3Array` results.
- The wind lanes come from a 4-wide `FORMAT_RF` image (native `fill_rect`/`blit_rect`), whose bytes are exactly the CUSTOM0 RGBA-float layout.

Output is meant to be bit-identical for positions, CUSTOM0, format and bounds, with normals within encoding precision. The setup's 40 template readbacks are gone too. Fixtures that inject only meshes read each template back once.

**Vegetation scan.** No `{}` allocation, signature formatting or history probes per unchanged cell, and the lambda sort is gone. Ready variants are applied first, then the nearest uncached cell gets the one-build budget. The fixture checks these decisions against the verbatim old scan.

**Detail scheduling.** Ordinary periodic passes are spread across frames:
- The budget is a soft 2.5 ms, checked *between* provider calls, using each provider's last cost.
- An indivisible call can exceed it, and overruns are counted. At least one provider runs per frame, so a pass takes at most 11 frames.
- `refresh_now()`, setup and captures stay fully synchronous.
- A physics-focus jump of more than 16 m starts building scheduling and a pass at once, instead of waiting up to 250 ms. A running pass is never restarted.

**Bounded teardown.**
- Periodic building refreshes retire one out-of-range cell per call, farthest first.
- Ordinary vegetation passes use `set_paced_presence`, which retires at most 16 horizon cells per call. In-range decisions are identical.
- Explicit refreshes still retire everything.
- `_exit_tree` consumes any outstanding threaded load and clears the pass.

**Loading.** `prepare_presence` runs several one-build passes per frame, up to 12 ms. It still finishes completely before returning.

## Root's integrated measurement (unmatched)

Root ran `polish-five-measured` (snapshot 22:46; 180 s, `--profile-transitions`, 1280x720). It passed **37/37 checks** with no errors, full 1200/40/90 population and 0 streaming failures. The results are in `.work/priorities-five/session-validation/sustained-polish-five-measured-191912600000/`, and the baseline is `sustained-polish-five-baseline-351835653100`.

This is **not a matched A/B**. The candidate snapshot also contains other workers' changes to residents (3 files), basketball, bicycle, emergency response, police cruisers and both audio scripts. Host contention was not controlled.

| Measure | Baseline | Candidate |
| --- | ---: | ---: |
| Per-frame detail peak (`refresh_with_details` → `detail_frame_slice`) | 21.507 ms | **10.932 ms** |
| Total detail CPU over the run | 4.298 s | **3.430 s** |
| `detail:CityVegetation` max / total | 14.024 ms / 1.787 s | **10.854 ms / 0.685 s** |
| Streaming stages ≥ 20 ms | 1 | **0** |
| Frames > 33 ms / > 40 ms | 24 / 4 | **8 / 0** |
| Frame max / p99 | 43.29 / 17.25 ms | **38.66 / 16.30 ms** |
| Frame p95 / median / mean | 10.06 / 2.85 / 4.30 ms | 12.69 / 4.30 / 5.68 ms (worse) |

- **Early burst removed.** The baseline's Wyanoke-day burst (20 frames of 33–43 ms at the 0.25 s refresh cadence while the horizon filled) is gone. Wyanoke-day p99 fell from 32.6 to 19.4 ms.
- **Median/mean regression not attributed to streaming.** The worse median and mean appear in every other phase, about 0.5–2 ms per frame. Streaming adds only microseconds per frame outside detail passes, and those passes total 3.4 s over the whole run. In the walking phases, sampled draw calls match the baseline. Greenmount's camera sweep advances per frame, so its views aren't comparable between runs at different frame rates.
- **Remaining frames over 33 ms:**
  - Five fall at a 30 s cadence (55, 85, 115, 145, 175 s), matching the session's ~30 s `checkpoint.json` rewrites (an inference from timing; no streaming stage there).
  - Two belong to the Greenmount-night relocation (frame 27226). There the vegetation call took 10.85 ms, of which 5.55 ms was synchronous trunk-collider creation, and the timeline cycle shows 17.98 ms of physics scripts over 3 catch-up ticks.
  - One is the Wyanoke-night relocation.
- **To isolate this work,** root should run the same snapshot with only these two files reverted to `98e4d48`.

## Instrumentation (opt-in `profile_streaming`)

- `refresh_with_details` now means synchronous refreshes only.
- Per-frame detail cost is `detail_frame_slice`. Total pass CPU is `detail_pass_cpu`, a multi-frame sum that is never logged as a frame event.
- Vegetation phases are nested under `detail:CityVegetation/{scan,unload,mesh_arrays,mesh_upload,physics}`. `unload` excludes deferred frame-end destruction.
- Always-on status counters: `detail_passes`, `detail_slices`, `detail_budget_overruns`, `relocation_refreshes`, `unloads_deferred`.

## Limits

- Not engine-verified by this worker. Root must run every command below.
- Root's `polish-five-measured` snapshot (22:46) matches both production files except for one null-player guard added afterwards in `city_streaming.gd`: `_process` now returns when `level.player` is null. Previously a queued pass would have dereferenced a missing player. The shipped level always creates the player before streaming, so the guard is unreachable there and does not affect any measured path.
- Spreading the pass lowers only the per-frame peak; the measured 20% drop in total detail CPU comes from the vegetation work. The peak now becomes the largest single provider call: crowd 2.75 ms, neighborhood details 2.95 ms, yard 4.09 ms in the candidate run. Those files are owned elsewhere and were not changed.
- Dense near-cell builds still pay `ArrayMesh` creation and upload in proportion to their vertex count. Trunk bodies are still created synchronously, by design.
- Fixture timing lines are informational only. Headless uses the dummy renderer, so it cannot show the GPU readback cost that was removed.

## Test commands (repo root; root serializes)

```
python godot/tools/godot_run.py -- --headless --script res://tests/city_streaming_polish_vegetation.gd
python godot/tools/godot_run.py -- --headless --script res://tests/city_streaming_polish_schedule.gd
python godot/tools/godot_run.py -- --headless --script res://tests/city_vegetation_batch_smoke.gd
python godot/tools/godot_run.py -- --headless --script res://tests/city_streaming_cadence_smoke.gd
python godot/tools/godot_run.py -- --headless --script res://tests/city_capture_residency_smoke.gd
python godot/tools/godot_run.py -- --headless --script res://tests/city_pointed_shrubs_smoke.gd
python godot/tools/godot_run.py -- --headless --script res://tests/neighborhood_utilities_runner.gd
python godot/tools/godot_run.py -- --headless --script res://tests/city_streaming_smoke.gd
python godot/tools/godot_run.py -- --headless --script res://tests/city_park_neighborhood_smoke.gd
```

Rendered/capture regressions, with root's usual flags: `city_vegetation_quality_render.gd`, `city_foundation_world_gallery.gd`, `city_foundation_sky_perf.gd`.

Traversal: `city_sustained_performance.py snapshot --name <n>`, then `run --name <n> --seconds 180 --profile-transitions`, then `analyze_city_transitions.py <result.json>`. Compare against `sustained-polish-five-baseline-351835653100`. The comparison is only matched if the snapshots differ just in the two files above.
