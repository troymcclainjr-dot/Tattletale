# Pen Lucy rendering and correctness audit (read-only)

This was a read-only review of about 15 minutes. I made no edits, ran no engine or Git commands, and saved no session. The plan file and ExitPlanMode tools weren't available to me, so this report is the only output. **Observed** means I saw it in source or in `metrics.json`. **Inferred** means I reasoned about engine behaviour without measuring it. I didn't fetch any Godot documentation, so engine-behaviour claims come from memory and are marked that way.

Graphify only returned acceptance documents and audio/Blender nodes. It doesn't index the rendering scripts yet.

## Most useful facts from the existing metrics

- **Streamed buildings didn't cause the 43–46 ms frames on this route.** Both `release-live` and `final-live-clock` show `streaming.background_loads = 0` (observed).
- **Vegetation is a large share of draw calls.** It uses **253 draw batches for 1,460 plants**, about 5.8 plants per batch. The crowd adds **191 batches**. Each opaque batch is drawn at least twice (depth prepass and colour), and near trees are drawn again for shadows (observed counts; the per-pass multiplier is inferred). Median draw calls are about 1,590.
- **About 40 vegetation rebuilds may have happened during play.** `cell_mesh_builds = 294` against 254 loaded cells, but the counter is never reset, so I can't tell how many fell inside the sample (inferred).
- **At 09:00 the only thing a live clock changes is the sun's angle.** In `sample()`, `day == 1` from 08:30 to 17:18, so ambient light, fog, sky colours and light energies are all constant. The sun rotates past the 0.2° threshold about every 1.5 s, and each step marks the sky radiance dirty.
  - The frozen-vs-live gap of 189.5 vs 180.4 FPS is **0.27 ms per frame**.
  - The two zero-wind repeats (179.84 vs 167.77) differ by 0.40 ms, so the gap is within noise. Treat it as unexplained, not as a known clock cost.

## Findings, ranked by severity

### High

**1. Quality presets don't apply shadow settings when the quality change happens at night.** (Observed bug; the cost impact is inferred.)
- `city_render_optimizer.gd:243-246` only updates lights where `node.shadow_enabled` is true. `city_day_night.gd:169-172` turns sun shadows off at night.
- So if `apply_settings` (`pen_lucy_level.gd:228`) runs at night, or the player changes quality at night, the sun keeps its constructor values (`pen_lucy_level.gd:315-316`): 120 m and 4 splits, which is High quality, on Balanced or Low.
- Once save/load restores night-time clocks, this will happen routinely.
- **Fix:** drop the `shadow_enabled` filter and set distance and mode on the sun explicitly. The fill light never casts shadows.
- **Test:** set the clock to 22:00, call `set_quality("low")`, advance to 09:00, then assert the sun has `directional_shadow_max_distance == 55` and 2-split mode.

**2. Two benchmark problems hide what causes the slow frames.** (Observed.)
- **(a) The start screenshot pollutes the process timings.**
  - `process_cpu_ms` shows max and p99 of **281.9 / 281.6 ms** in both runs, while the worst frame was only 43 ms.
  - Cause: `_save_image("walk_start.png")` (`city_life_benchmark_driver.gd:180`) does a GPU readback and a synchronous PNG encode right before `began`. The per-second process monitor then carries that 281 ms into the sample.
  - **Fix:** save the start image before the warmup, then wait at least 1.2 s before sampling. Stop reporting the `TIME_PROCESS`/`TIME_PHYSICS_PROCESS` monitors, or label them as per-second maxima.
- **(b) There's no record of what happened on each frame.**
  - **Fix:** before and after every sampled frame, snapshot these counters:
    - vegetation `_cell_mesh_builds`
    - streaming `_loads`
    - yard `async_loads`
    - crowd cell activations
    - day/night `_sky_updates`
    - the save count, once saving is wired in
  - Then write the 10 slowest frames with their counter changes, `viewport_gpu_ms` and `viewport_render_cpu_ms`.
  - This is how to find what causes the 40–46 ms frames. Add it alongside the nvidia-smi sampling Root is adding (graphics and memory clocks, utilization, power, throttle reasons, sampled every 250 ms in the background).
- **Test:** a run where `process_cpu_ms.max` is below 2× `frame_ms.max`, and every frame over 20 ms is either tagged with a counter change or listed as untagged.

### Medium-high

**3. Vegetation rebuilds run synchronously with no per-call limit, and a per-vertex GDScript loop dominates each rebuild.** (Code observed; hitch size inferred.)
- `set_presence` (`city_vegetation.gd:115-143`) rebuilds every cell that crosses a threshold (55 m, 90 m, 125 m or 400 m), all in the same call.
- For each plant, `_cell_mesh` (`:200-214`) does a Basis multiply, a normalize and 4 `append` calls per vertex. That's about 443k vertices cached across about 300 variants.
- This overlaps with the agent that owns the vegetation cache. Things to check when their file lands:
  - **At most one build (or about 2 ms) per refresh.** Keep the old node visible until its replacement is ready.
  - **Move the normal correction to the GPU.** Each plant's basis is `S·R_y` with `S = diag(r, h, r)`, and that S commutes with a Y rotation. So the correct normal is `normalize(n' * vec3(k, 1, k))`, where `n'` is what `append_from` already produces and `k = (h/r)²`.
    - Store `k` in the currently reserved `CUSTOM0.z` and apply it in `vertex()` of `city_vegetation_wind.gdshader`.
    - This removes the `corrected_normals` loop entirely.
  - **Precompute wind weights per template.** The weight depends only on the template's vertex y and the LOD, not on the plant.
  - **Fill packed arrays by index** (pre-sized with `resize`) instead of calling `append`.
- **Tests:**
  - A GDScript check that the shader's normal formula matches `inverse().transposed()` within 0.1° for random (r, h, yaw).
  - A pixel comparison of a fixed near-tree capture.
  - Benchmark frames tagged with vegetation builds staying under 8 ms.

**4. The sun moves in visible steps, and every step dirties the sky radiance.** (Code observed; the visual effect is calculated, not observed in captures.)
- The sun's rotation updates only on the 0.5 s sky cadence, and only once it has moved 0.2° (`city_day_night.gd:181-184`).
- At 17:30 the sun's elevation is about 7.9°. A 0.2° step moves the shadow tip of a 10 m building about 1.8 m, roughly every 1.5 s.
- **Fix:**
  - Set the sun to `sky_mode = SKY_MODE_LIGHT_ONLY` and update its rotation on the 50 ms `LIGHT_INTERVAL` with a threshold of 0.02° or less.
  - Add a shadowless `SkySun` directional light with `SKY_MODE_SKY_ONLY` that mirrors the sun's angle, colour and energy at the sky cadence. Only this light feeds the procedural sky and its radiance.
  - Set the fill light (`pen_lucy_level.gd:318-323`) to `LIGHT_ONLY`. From memory, `ProceduralSkyMaterial` draws a sun disk for up to four directional lights, so the fill probably adds a stray glow to the sky, and its writes dirty the radiance.
  - These enum names are from memory and should be checked against 4.7.2.
- **Tests:**
  - From 17:00 to 17:10, the sun's angle changes by at most 0.05° per update.
  - During 10 s of live play at 12:00, `_sky_updates` stays at or below 20.
  - A paired A/B run (live clock with the sky light separated, vs frozen) shows whether the 0.27 ms gap disappears.

**5. Changing any case reward or stage count silently destroys existing saves.** (Observed logic.)
- `city_world_save.gd:9-10` hard-codes `CASE_REWARDS` and `CASE_STAGES`. If either changes in the mission data, every existing save fails with "case reward mismatch", and the backup fails the same way.
- The next autosave then sees an invalid existing file, skips the backup copy (`:243`) and renames the new file over it.
- **Fix:**
  - Derive both tables from `city_missions.CASES` and the step data.
  - If the existing file is present but invalid (anything other than "no checkpoint"), move it to `.rejected-<unix>` before overwriting.
- **Test:** save, change a reward in the fixture, then load. The old file should be kept and nothing overwritten.

**6. Streamed-back building chunks get private copies of their materials.** (Observed; currently latent.)
- `city_weathering.gd:55` sets surface override materials on the `BuildingChunk_*` nodes. `city_streaming.gd:57-58` packs those nodes, materials included, into the cache.
- Reloads use `CACHE_MODE_IGNORE` (`:161`), so every reloaded chunk gets its own `ShaderMaterial` instances instead of the shared ones.
- Any future runtime material change (night window emission, wet roads, shader settings tied to quality) would skip reloaded chunks.
- **Fix:** in `_poll_load`, after `instantiate()`, swap each surface override for the shared material with the same `resource_name`. Expose the weathering shared-material map and the glass material for this.
- **Test:** unload and reload a cell, then assert the override material is the same instance as the shared one.

### Medium

**7. The save provider isn't wired in yet.** (Observed: nothing in `pen_lucy_level.gd` references it.)
- **Order:**
  - Load after the residents' route-build loop (`:196-198`). `restore_state` silently skips residents whose route doesn't exist yet.
  - Load before `day_night.setup` and `apply_settings`, so lighting and quality start at the restored time.
- **Save triggers:**
  - after `missions.changed` when a case completes (rewards still can't repeat, because `completed_ids` blocks it)
  - in `pause_exploring`
  - on `NOTIFICATION_WM_CLOSE_REQUEST`
- **Benchmarks:** graphical benchmark runs don't count as validation (`:22`), so they would write autosaves into `user://` and pay synchronous file IO during the sample. Add `--no-world-save` and pass it from the benchmark driver.
- **Partial load:** the comment at `:77` says everything is validated before anything changes. But if the mission restore fails, the clock, player and residents have already been changed. Either add a dry run of `start_case` first, or correct the comment.
- **Load collisions:** the player's safe-position check (`:81-86`) runs before residents are restored (`:96`). Check whether `_activation_clear` (mask 2|4|8|16) covers the player's collision layer; if not, a resident can be restored on top of the player.
- **Windows atomicity (inferred from memory of Godot's Windows rename, which deletes the target first):**
  - A crash in the middle of a save can leave only the `.bak` plus a validated `.tmp`. `read_snapshot` should accept a valid `.tmp` when the primary file is missing.
  - `flush()` isn't an fsync, so the "flushed" comment overstates power-loss durability.
- **Test:** quit with a just-completed case and reload. Then simulate a missing primary file with a valid `.tmp` and confirm it's recovered.

**8. Vegetation draw count: merge far cells.** (Counts observed; savings inferred.)
- Beyond 125 m, cells contain no bushes and no colliders, so the far ring can be built once as 3×3 super-cells (144 m). Keep 48 m cells for the near and bush ring.
- This should remove about 150–200 draws per frame.
- **Test:** compare median draw calls and `viewport_render_cpu_ms` in A/B runs.

**9. Building chunks are 150 m, which works against culling, LOD and shadows.** (Inferred.)
- The chunk the player is standing in probably renders at full LOD across its whole 150 m width. Its bounding box also enters both shadow splits.
- **Fix:** try `CHUNK_SIZE = 75` with `CACHE_VERSION` bumped. Keep it only if GPU time drops by more than the extra render-thread CPU.

**10. Soft-shadow filtering is fixed at quality 3 (Soft Medium) for every preset.** (`project.godot:106`; cost inferred.)
- **Fix:** in `set_quality`, call `RenderingServer.directional_soft_shadow_filter_set_quality` with 1, 2 or 3 for Low, Balanced and High. 2 is the engine default.
- **Check:** compare near-shadow softness at 09:00 and 17:30.

**11. The surface shader's hash breaks down far from the world origin.** (Inferred; not seen in captures.)
- `hash21` in `city_surface.gdshader:14-16` uses `sin` on very large inputs: brick-chip noise at `p*31` and brick IDs reach dot products of about 10⁶.
- At that size, 32-bit floats lose the precision this hash depends on. Distant blocks would show regular patterns, and results can differ between GPUs.
- **Fix:** use a hash without `sin`, such as `fract` of `p3*0.1031` with dot mixing. The cost is the same.
- **Test:** take matching captures near the origin and about 400 m away.

### Low

- **12.** `city_crowd.gd:522-524` rewrites `visibility_range_end` on every crowd node every 0.25 s, even when the radius hasn't changed. Only write when `_presence_radius` changes.
- **13. Two scripts own the same chunk settings.**
  - The optimizer sets Low quality's 520 m visibility range and 0.7 LOD bias on chunks (`city_render_optimizer.gd:234-236`).
  - Streaming immediately overwrites them with 0 and 0.65 (`city_streaming.gd:116-118`).
  - Pick one owner.
- **14. Other agents' work:**
  - The crowd walkers' staggered groups and the reused query object (`city_crowd.gd:318-321, 365-368`) are present and look correct. A long frame still runs all three groups in one tick, which is intended.
  - The bounded vegetation cache and pre-phase work weren't in the file yet when I read it, so I couldn't verify them.

## Measurement notes

- **FPS comparisons need paired, interleaved runs.** Report the paired differences in milliseconds per frame, not FPS. Log GPU clocks and throttle reasons for every run, or the 157 vs 180 FPS split between two identical live configurations can't be explained.
- **Treat `viewport_get_measured_render_time_gpu` with care.** From memory, it lags a few frames behind and covers only that viewport's GPU work, not presentation. Check it isn't zero and compare it with nvidia-smi utilization.
- **Test the 09:00 live-vs-frozen gap on its own.** Run with the sun's rotation pinned while the clock runs, or with the sky light separated (finding 4), before blaming the clock or sky.