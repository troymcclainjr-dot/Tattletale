# Read-only audit: residents, combat, clock, day/night, wind and the Rust proposal

I didn't edit, build, run or launch anything.

- **Snapshot:** I read the working tree at 16:00–16:09. Several files changed while I was reading (`city_residents.gd`, `city_resident_actor.gd`, `city_day_night.gd`, `pen_lucy_level.gd`). Line numbers below were rechecked at 16:09 and may move.
- **Graphify:** the query `"city residents combat clock performance architecture"` returned only acceptance docs and yard tests. The graph doesn't index residents, combat, world time or day/night yet, so it needs rebuilding after integration.
- **No in-session evidence:** I didn't open the official Godot or godot-rust docs. Every timing number comes from the repo's existing `artifacts/vehicle-courts/*/metrics.json`. Anything marked *inference* is unmeasured.

## Findings, ranked by severity

### High

**H1. A pistol shot can hit someone standing behind the player.**
- Where: `city_combat.gd:248-262`.
- The aiming ray starts at the camera and excludes only the player. The camera's collision sweep (`city_player.gd:598`, mask 1|2|16) ignores people (layer 8), so a person can stand between the camera and the player, or overlap the camera.
- The ray is set to report hits from inside a shape (`hit_from_inside = true`, `:189`). So it can return that person, or the camera's own position. The muzzle-to-endpoint ray then fires backwards.
- **Fix:**
  - Start the aiming ray at the player's depth along it (`origin + dir * max(0, dot(chest - origin, dir))`), and drop `hit_from_inside` on that ray.
  - Reject any endpoint where `dot(endpoint - muzzle, dir) <= 0`.
- **Test:** put an NPC between the camera and the player, fire, and expect no hit.

**H2. Case dialogue ignores combat, so it can pause a fight and advance a case.**
- Where: `pen_lucy_level.gd:490-498`.
- `interact()` checks `missions.conversation_preview()` before the combat check in `nearby_talker()` (`:518`).
- `nearby_offer`, `_target_position` and `_can_interact` (`city_missions.gd:54-66, 349-367`) never check `combat_override`.
- Result: you can open a case conversation with a contact who is attacking you or knocked down. `open_conversation` pauses gameplay, and `commit_dialogue_action` can then advance the case stage.
- **Fix:** refuse case interaction while the target actor has `combat_override` set, or while combat has any aggressive actor.

**H3. Residents can deadlock permanently.**
- **Why they never recover:** `assign_route` sets `manual_target = true` (`city_resident_actor.gd:57`). The base actor only recovers from being blocked on non-manual patrols (`city_npc_actor.gd:142`).
- **Why they collide with things the route never checked:** routes are swept against layer 2 only (`city_residents.gd:204`), but movement collides with layers 4, 8 and 16.
- **Why they meet head-on:** every resident and every crowd walker walks the same line, `width/2 + 1.15` (`city_residents.gd:144`, `city_crowd.gd:336`).
- **Concrete case in the data:** `daily_nadine_brooks` and `daily_miriam_owens` are both on Old York Road, side 1, at fractions 0.42 and 0.48. Each one's home standing spot lies on the other's corridor.
- **Crowd walkers make it worse:** walkers stop for residents (their sweep includes layer 8, `city_crowd.gd:396`), and residents stop for walkers. Each waits for the other forever.
- **Fix:**
  - After being blocked for N seconds: wait, then try the lateral offsets the route builder already uses (±0.35 / ±0.6). Failing that, step back one corridor point or re-plan from the nearest point.
  - Add a deterministic yield rule (for example, the lower id yields).
  - Keep corridors from passing through other residents' home spots.

### Medium-high

**M1. A crowd proxy walking home has no timeout, which leaks a fight slot and blocks the player's health regeneration.**
- Where: `city_combat.gd:377-383`.
- The proxy is released only when it is within 0.22 m of home, or the player is more than 50 m away.
- `_move_actor` returns silently when the slope or step fails or the move is blocked (`:429-437`). For example, the player standing on the proxy's home spot blocks it.
- Health regeneration requires no active fighters (`_active.is_empty()`, `:182`), so one stuck proxy stops regeneration indefinitely.
- **Fix:** add a return timeout (about 6 s) with a no-progress check, then demote.

**M2. Releasing a resident or patrol NPC from combat restores a stale target.**
- Where: `city_combat.gd:490-495`.
- On release, the actor gets back the target it had before the fight. By then the chase may have moved it up to 18 m off its route, and it walks a straight line back. Residents can't recover from blocking (H3).
- Patrol NPCs keep stale `patrol_index`, `_wait` and `blocked_seconds`. They can bounce between endpoints that are unreachable in a straight line.
- If a mission retargeted the actor during the fight, release overwrites that new target.
- **Fix:**
  - Walk every actor back to its pre-fight spot (`state.home`), with a timeout.
  - Then for residents call `_update_schedule(actor, true)`, which re-plans from the nearest corridor point.
  - For patrols, call `set_patrol` starting at the nearest index.
  - Only restore the old target if nothing changed it during the fight (a revision counter).

**M3. Distant residents can get stuck invisible and frozen.**
- Where: `city_residents.gd:270-274`.
- When a resident's spot is occupied at activation time, `continue` also skips its distant (non-physical) movement, so it freezes.
- Distant movement ignores collision, and routes are validated against layer 2 only. A resident can therefore end up overlapping a layer-16 prop and never activate while the player is within 120 m.
- Two distant residents can overlap undetected, because hidden residents have collision layer 0. Both then activate overlapped, every `move_and_collide` reports contact, and both stay blocked.
- **Fix:**
  - Keep advancing the resident while activation fails.
  - Sweep routes against 2|16.
  - Check other residents' logical positions at activation.

### Medium

- **M4. Fully faded residents may still be rendered.**
  - The fade runs from 70 to 90 m (`city_resident_actor.gd:43`), but bodies stay enabled out to 120 m (`city_residents.gd:10`).
  - `transparency > 0` moves every puppet part into the transparent pipeline, so multi-part puppets may sort wrongly against themselves (behaviour I recall from Godot's documentation, not verified here).
  - *Inference:* at `fade == 1` the parts are probably still drawn.
  - **Fix:** set `visible = fade < 0.999`, or use the engine's own `visibility_range` fade.
- **M5. NPC timing spikes from batched crowd walkers.**
  - All walkers are processed every 0.05 s in one physics tick (`city_crowd.gd:312-313`).
  - Each walker allocates a new query object and runs `cast_motion` plus `intersect_shape` (`:392-407`).
  - The prior NPC timing (median 0.505 ms, p95 1.415 ms) fits a spike every third physics tick (*inference*).
  - **Fix:** split walkers into three groups processed on alternate ticks, and reuse one query object as `city_vehicle.gd:254` already does.
- **M6. 180 m ground ray for every moving actor, every tick.**
  - Where: `pen_lucy_level.gd:359-361`, used by `city_npc_actor.gd:120` and `city_combat.gd:429`.
  - **Fix:** use a short ±1.5 m probe for walking. The saving is *inference*; measure it.
- **M7. Route building causes a startup hitch and pollutes the timing numbers.**
  - One route builds per physics frame for 20 frames. Each build does up to 160 steps × 5 offsets × (ray + 2 shape queries + stair and trunk checks) (`city_residents.gd:253-254`).
  - `_max_tick_usec` is never reset, so it includes the builds.
  - **Fix:** limit build work per frame by a time budget or bake the corridors into data, and reset the counters before benchmarking.

### Low

- **L1. The smoke tests are weaker than they look** (`city_residents_smoke_runner.gd:69-94`):
  - The pause check waits 20 frames, which is less than the 0.5 s distant-update interval, so distant residents wouldn't have moved anyway.
  - It doesn't check that the clock or wind time stayed frozen.
  - "Toggle preserves positions" is true by construction.
  - "Progressed" needs only 1 of 20 residents to move.
  - Missing tests: combat-then-resume for a resident, two residents head-on, blocked activation, case dialogue during a fight, and a shot with an NPC behind the player.
- **L2.** `save_state` has no matching load, so the saved slot and route cursor are never restored (`city_residents.gd:336-351`).
- **L3. Day/night has two visible pops.**
  - Sun shadows switch off abruptly at energy 0.08. Whether it also causes a shader-variant hitch is *inference*.
  - The 8 pooled street lights jump between lamps with no crossfade.
  - The root has since added change detection on the lighting writes, which I checked.
- **L4. Combat line of sight is blocked by other people.** Layer 8 is in `WORLD_MASK`, so in crowded fights NPCs at the back lose sight of the player and give up after 5 s. Punch line of sight is tested at 1.0 m, so low hedges block punches.
- **L5. Per-tick allocations:** new query objects, `pose({...})` dictionaries and `_effects.duplicate()` every tick.
- **L6. File hygiene.** At 16:03 `pen_lucy_level.gd` briefly had a blank line after every line (1,804 lines); by 16:09 it was back to 908. Git also warns of LF→CRLF conversion on `city_residents.gd`. Check before committing.
- **L7. Wind is updated at 20 Hz.** About 1.6 mm per step, which isn't visible. No action needed.

## How to benchmark 20 residents with routines on vs off

1. **Don't trust the engine's CPU timing monitors.** By my reading of Godot's main loop, `TIME_PROCESS` and `TIME_PHYSICS_PROCESS` are roughly per-second maxima. The prior data supports this: `process_cpu_ms` median was 10.27 ms while the frame median was 3.95 ms, which can't be a per-frame cost. Use wall-clock frame distributions and the component timers.
2. **FPS can't detect this change.** Same-build runs ranged from 132 to 207 FPS. The cost of 20 residents is likely well under that noise (*inference*).
   - Alternate the two settings in A-B-B-A order, at least 5 pairs, a fresh process each run, and discard the first run.
   - Report the paired differences in the residents and NPC timers at p50, p95 and p99.
3. **"Routines off" isn't the same workload.** With routines off, residents are still posed and keep their bodies; only movement and scheduling stop.
   - Add a third run with residents absent, to capture the total cost including draw calls and physics bodies.
   - Log per sample: how many residents are moving, near, and physical, plus draw calls.
4. **The sample may catch mostly standing residents.** At 0.5 game-minutes per second, residents reach their destination within about 2 minutes and then stand. The benchmark starts at 09:00, inside the 08:00 slot.
   - Set the time just before a schedule boundary (for example 15:59) so everyone is walking during the sample.
5. **Exclude startup work.** Wait until `pending_routes == 0`, then reset `_max_tick_usec` and the update counters.
6. **The 199–207 FPS baseline predates day/night, wind and combat.** Re-baseline both settings with the same flags (`--freeze-world-time`, `--no-city-wind`). Day/night currently has no off switch, so it can't be excluded.
7. **Run longer than 7 s.** The residents' 0.5 s and 1 s batches give only 7–14 spike events in 7 s; use 15 s or more.
8. **Watch for path blocking.** Residents walk the same sidewalk line as the benchmark route, so they may stall the walking player in one setting only. Compare stall windows per setting.

## Should all logic be rewritten in Rust?

**What the repo shows:**
- Traffic costs 2.33 ms per physics tick (p95 3.29), NPCs 0.505 ms (p95 1.415), missions 0.003 ms.
- Frame median is 3.95 ms, p99 11.25 ms, at about 1,635 draw calls and 60 physics ticks per second.
- Most per-entity work is calls into Godot's own physics queries and node or MultiMesh transform updates. That work is native already and stays the same cost from Rust.

**Inference:**
- With physics at 60 Hz and rendering near 200 FPS, most frames contain no physics tick. Script time mostly shows up in the slow-frame tail, not the median.
- Even if all traffic and NPC script time vanished (it can't), the saving is about 2.8 ms per physics tick, roughly 0.85 ms per rendered frame on average.
- Nobody has measured how much of traffic's 2.3 ms is script versus physics queries.

**Costs of Rust:**
- A Rust toolchain for every contributor.
- Native builds for each platform, including macOS universal binaries and signing.
- Web export with native extensions is experimental.
- The binding must match the Godot 4.7 API. Verify that before committing; bindings can lag new minor releases.
- Heavier export and debugging, and it works against the project's portable source distribution.
- Calls between Rust and the engine are expensive if code passes Godot dictionaries and arrays back and forth.
- UI, dialogue, missions and combat would gain nothing: missions measure 0.003 ms and combat is negligible.

**Recommendation: don't rewrite everything.**
1. Fix the bugs above and do the GDScript performance work first:
   - Process walkers in groups across ticks, and reuse query objects.
   - Use short ground rays and typed arrays.
   - Replace per-entity dictionaries in the crowd and traffic code with packed arrays.
2. Instrument the traffic tick: how many queries it makes and how long they take, versus the script around them.
3. Only if traffic or crowd script time still exceeds about 1 ms per tick at the target density, prototype one native module: the traffic lane simulation.
   - It would keep its own spatial hash for car spacing and expose a batch `step(delta) -> PackedFloat32Array` call.
   - Keep a GDScript fallback behind the same API, which also allows determinism tests comparing the two.
   - Accept it only if paired A/B runs show traffic p50 and p99 dropping by at least 50% and frame p99 improving beyond the noise, with a clean-clone export smoke test passing.
   - C++ through godot-cpp is an equally valid way to build that one module.

Godot's CPU optimization guide and the godot-rust book both, as I recall them, favour measuring first and moving only proven hot spots to native code, mixed with GDScript. I didn't re-fetch either during this review.