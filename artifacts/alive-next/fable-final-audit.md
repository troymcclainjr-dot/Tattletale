# Pen Lucy final independent audit (Fable 5.1, high effort)

**Date:** 2026-10-31, snapshot taken between 06:30 and 06:37 local (the tree was being edited by the root during the audit; see §1.3).
**Mode:** read-only. No engine, Blender or GUI was launched by this audit. The only files written are this report and `.work/alive-next/fable-findings.json`.
**Method:** `graphify query` first (graph still indexes only JS/Python/Markdown; zero GDScript nodes, so every runtime claim below comes from direct reads), then every city runtime module, the shaders, the fixtures that back the claims, the recorded logs, and the rendered captures. Each finding says whether it rests on **static review** (code read) or **executed evidence** (a recorded engine run, hash-matched to the file I read).

Companion JSON (same IDs, for root disposition): `.work/alive-next/fable-findings.json`.

---

## 0. Verdict in one paragraph

The engineering base is sound and most of this pass's requirements are implemented and backed by fixtures that passed on the current source hashes: phone photography with correct input ownership, tire damage that changes yaw, lateral motion and braking distance, six new vehicle kinds in traffic and parking, twenty modular looks carried through crowd, daily residents and combat promotion, melee witnesses, a bounded spatial audio pool, the world repairs (Row050 shrubs, Frisby fence, Row170 fronts, firehouse lawns, two conifer silhouettes), save recovery UX, OSM attribution on the full map, credits, the case ledger, and the all-complete objective. **It is not yet a certifiable M0 exit.** Three things block that: (1) the evidence set is not frozen, with several production files and fixtures edited after their last green run and two `summary.json` indexes that still list superseded failures while omitting later passes; (2) the only normal-input end-to-end session fixture is red on its mouse-click save step (a fixture coordinate bug by all evidence, now patched but not rerun); (3) no performance measurement exists for the integrated tree, and the standalone export has not booted (both release attempts failed on sandbox environment errors, and the rc2 PCK may carry an empty `project.binary`). One real player-facing defect was found statically and confirmed in a capture: the minimap OpenStreetMap credit was clipped and invisible in play; the root moved it during the audit, and that fix is unverified by a run.

---

## 1. What evidence actually exists

### 1.1 Recorded engine runs (executed evidence)

| Run set (time) | Case | Result on log | Hash-matched to current source? | Status |
|---|---|---|---|---|
| final-validation2 (06:24–06:26) | cars | 35 passed, 0 failed | cars runner yes; `city_parked_cars.gd` and `city_car_catalog.gd` were **modified after** this run (mtime > 06:26:49) | needs rerun |
| final-validation2 | recovery | 11 passed, 0 failed | yes (`city_resident_actor.gd` f70b595a, `city_population_appearance.gd` 55634a8d) | green |
| final-validation2 | case-ledger | 10 PASS incl. Settings modal | yes | green |
| final-validation2 | legacy-people | 9 PASS | yes | green |
| final-validation2 | ui-render | 6 captures, failures 0 | **runner later edited** to add `RadarAttribution`/`MapAttribution` assertions; those did not run | needs rerun |
| final-validation2 | car-showroom | 21 captures, failures 0 | yes | green |
| final-validation2 | input-case (AF-25) | **30 passed, 1 FAIL** "mouse input activates exactly one checkpoint write" | runner **edited after** the run (click now uses canvas transform + `viewport.push_input`) | red, patched, not rerun |
| final-validation (06:17–06:23) | car-catalog | 284 passed, 0 failed | yes (`city_car_catalog.gd` 222aa7ec at that time) | superseded by later catalog edit |
| final-validation | catalog-integration | failures 0 | yes | green |
| final-validation | melee-audio | 21 passed, 0 failed | yes (`city_combat.gd` cc8ecc06, `city_world_audio.gd` 67fd26d0) | green |
| final-validation | save (06:23:56) | **77 passed, 0 failed** | yes (`city_world_save.gd` f8d9425e) | green, **absent from summary.json** |
| final-validation | cars / case-ledger | FAIL | stale fixtures | superseded (see above) |
| regression (06:10–06:24) | traffic 29/0, movement 114/0, expansion 59/0, residents 201/0, day-night 19/0, parks, backlots | pass | yes | green |
| regression | damage failures=0, inspector pass, phone failures=0, tires pass (06:23–06:24) | pass | yes | green, **absent from summary.json** |
| regression | save, recovery, case-ledger | FAIL | superseded by the later passes above | historical |
| phone-final (05:56) | phone headless + `--phone-render` | pass | `city_player_phone.gd` 8ab0af52 yes; level hash older | green (phone module unchanged since) |
| integration3/4, validation, validation2 | various | mixed | older hashes | historical only |
| `.work/alive-next/settings-layout-run.log` | Settings action row fits viewport at 1280×720 and 1600×900, all three tabs | PASS | yes | green |
| `.work/alive-next/npc-modular-test.json` | people fixture, failures 0, 3192/592 and 3264/640 triangles, 18 batches before and after | pass | people modules unchanged | green |

Summary indexes: `final-validation/summary.json` lists five cases and omits the 06:23 save pass that sits beside it; `regression/summary.json` lists ten cases and omits damage, inspector, phone and tires runs that sit beside it. Neither index can be handed to a reader as "the result".

### 1.2 Non-engine evidence

- Visual captures (06:06, private viewport, FOV 68): `ss1-east41st-lawns`, `ss2-frisby-side-fence`, `ss3-dumbarton-fronts`, `ss4-firehouse-side-lawns`, `row170-rear-doors-dumpsters`, `conifer-tree4`, `conifer-tree5`, plus `integration-report.json` (failures 0). I viewed six of them (§7).
- UI captures (06:26): gameplay-minimap, full-map, settings-video, settings-controls, cases, credits. Viewed four.
- Vehicle showroom: 21 PNGs and `showroom-report.json` (coverage gate 8–20 % met on every shot). Viewed the pickup.
- `vehicle-models-measured.json` (06:17): `fails: 0`, `passes: 284`. The IMPLEMENTATION report's "thirteen failures" row is superseded.
- NPC rosters: `npc-roster.png`, `npc-daily-roster.png`, `npc-seated-roster.png`. Viewed two.
- World authoring: `world-author-audit.json`, `final-cleanup-check.json` (sections unchanged by the final cleanup; three shrubs with 0 m² paving overlap).
- Performance: only `artifacts/civic-build/alive-next-before/metrics.json` (05:31). Its provenance hashes are **older** than the current combat, crowd, player, settings, traffic, vehicle, world-save, level, npcs, parked-cars, car-models, population-appearance, missions, map and resident-actor files. The 184.88 FPS / 1,495 median draw calls figure is therefore a *pre-integration* number. `.work/alive-next/car-performance-assessment.md` refers to "the measured regression" but I found no post-integration metrics artifact.
- Release: `artifacts/releases/packaging-preflight-20261031` (docs and notices only), `pen-lucy-rc1` (docs only; import failed), `pen-lucy-rc2` (exe + pck present, **no** `release-manifest.json`, `SHA256SUMS.txt`, zip or `standalone-boot.json`). `godot/export_templates/` is empty; the AppData template directory is outside my allowed paths.

### 1.3 Files that changed during or after the latest green runs

Modified after `final-validation2/summary.json` (06:26:49): `pen_lucy_level.gd` (now a9361344; radar credit moved into the HUD root), `city_minimap.gd` (95cf5d67; label removed), `city_car_catalog.gd`, `city_parked_cars.gd` (legacy-catalog flag), `city_current_ui_render_runner.gd`, `city_input_case_smoke_runner.gd`, new `city_settings_layout_runner.gd`, `export_city_release.py`, `test_export_city_release.py`. Everything in §2 is written against the hashes I read; the root must freeze the tree and rerun before any row above is called certified.

---

## 2. Findings (prioritized)

Severity: **P1** blocks the M0 exit or shipping; **P2** should be closed in M1; **P3** hygiene or low-risk improvement. Class: **AUTO** concrete defect or test/harness fix the root can apply; **FOLLOWUP** needs engine time or hardware; **CREATIVE** product decision.

### FA-01 · P1 · AUTO · Minimap OpenStreetMap credit was invisible in play (fixed during audit, unverified)

- **Where:** `godot/scripts/city/city_minimap.gd:66-76` (as of hash e86e1f9e) placed the label at `Vector2(4, 208)` inside a 208 px map canvas that fills the radar; `city_radar.gd:11` sets `clip_children = CLIP_CHILDREN_AND_DRAW` on the circular radar. A child at y = 208 lies outside both the control rect and the drawn circle, so it was clipped.
- **Evidence:** static review plus `artifacts/alive-next/ui/gameplay-minimap.png` (06:26), which shows the radar with no credit text anywhere on the HUD. The full map credit (`city_map_overlay.gd:50-54`) is visible in `full-map.png`.
- **Current state:** `pen_lucy_level.gd:722-736` (hash a9361344) now creates `RadarAttribution` on the HUD root, anchored bottom-left under the radar, visibility tied to the radar. `city_current_ui_render_runner.gd:25-50` asserts the label is enclosed by the viewport, is not a radar descendant, and changes rendered pixels. **That runner version has not been executed.**
- **Fix/validation:** rerun `city_current_ui_render` with `--offscreen-validation`; keep the pixel-diff assertion. Also check the 1280×720 layout since the label uses fixed offsets.

### FA-02 · P1 · AUTO · The only normal-input session fixture is red on the Save click

- **Where:** `godot/tests/city_input_case_smoke_runner.gd` (`save_with_ui`), result in `artifacts/alive-next/input-case-report.json` and `final-validation2/input-case-run.log`: 30 PASS, then `FAIL mouse input activates exactly one checkpoint write`.
- **Cause by evidence:** the recorded click position was `[417.5, 1519.0]` in a 1600×900 viewport. The Settings action row really sits at y ≈ 797 (settings-layout log, both resolutions, all tabs; `settings-video.png` confirms). The old `click()` used `get_global_rect()` and `Input.parse_input_event`, which disagree with canvas coordinates under headless stretch. The click never reached the button, so this is a fixture defect, not a save or UI defect. The production path (`city_settings.gd:63` → `pen_lucy_level.save_progress`) is exercised green elsewhere (`city_release_reliability`, save fixture 77/0).
- **Current state:** the runner now computes the point with `get_global_transform_with_canvas()` and injects through `viewport.push_input` (lines 45-63). Not rerun.
- **Fix/validation:** rerun headless and `--offscreen-validation`. If still red, print `level.world_save.last_result` and the button's canvas rect in the failing check before changing production code. This fixture is the M1 acceptance for AF-25; it must be green on the frozen tree.

### FA-03 · P1 · AUTO · Evidence is not frozen or indexed; M0 exit criterion 1 is unmet

- **Where:** `artifacts/alive-next/final-validation/summary.json` and `regression/summary.json` (stale rows, missing later runs, §1.1); files edited after their green runs (§1.3).
- **Expected:** one serialized run of every touched suite on a frozen tree, one summary that lists every case with `source_sha256`, zero engine errors.
- **Fix:** freeze, then rerun at minimum: cars, car-catalog, catalog-integration, vehicle precision/jump/street smokes (catalog kinds changed the parked batches), ui, ui-render, input-case, life, save, reliability, melee-audio, phone (both modes), alive-world, people, legacy-people. Write a single summary and delete or mark the superseded ones. Update `IMPLEMENTATION_AND_REVIEW.md` rows that still say "case ledger awaiting execution" and "vehicle artifact has thirteen failures" (both superseded) and the roadmap §1.2 table (export preset, melee witness, spatial audio, notice queue, attribution, Start-fresh equivalent are now present).

### FA-04 · P1 · FOLLOWUP · No performance measurement of the integrated tree

- **Where:** `artifacts/civic-build/alive-next-before/metrics.json` is the only benchmark and predates the people, vehicle, tire, audio and world changes (provenance hash list differs for 17 city scripts). Crowd pose meshes grew from 108 to 3,192 triangles (far LOD 592) and parked batches from 7 to 19 (`city_parked_cars.gd:198-234`).
- **Expected:** a matched-route run (same config as the 05:31 baseline: 1920×1080, Balanced, 4× MSAA, private viewport, 75.5 m Old York route) on the frozen tree, reporting p50/p95/p99 frame time, draw calls, GPU and render-CPU medians, physics component medians, and the catalog A/B via `--legacy-vehicle-catalog` that the car-performance assessment proposes.
- **Note:** do not interpret any delta as an optimization or regression without the variance study (AF-22). Two cheap, behavior-preserving micro-fixes from the assessment are safe AUTO items and are listed as FA-10.

### FA-05 · P1 · FOLLOWUP/AUTO · Standalone export has not booted; rc2 payload is suspect

- **Where:** `.work/alive-next/release-build.log` (rc1: editor could not create `AppData/Roaming/Godot`, `user://` unavailable → import aborted), `release-build2.log` and `.work/release-stage/pen-lucy-rc2/export.log` (export reached `[ DONE ] savepack`, but Godot logged `Safe save failed` and `Can't open file ... sandbox.{...}/AC/Temp/tmpproject.binary` while storing `res://project.binary`; `run_checked` in `export_city_release.py:193-204` correctly refused to continue). No `standalone-boot.json`, `release-manifest.json`, `SHA256SUMS.txt` or zip exists.
- **Impact:** the exe and pck in `artifacts/releases/pen-lucy-rc2` must not be distributed or treated as a candidate; the packed `project.binary` may be empty because the temp file could not be read back.
- **Fix:** run the editor subprocesses with `TEMP`/`TMP` (and `APPDATA`/`LOCALAPPDATA`, which rc2 already redirects into `editor-profile`) pointed at a writable stage-local directory, or run the build outside the sandboxed shell. Then let the pipeline's own boot probe (`BOOT_PROBE`, 1,200 crowd / 20 daily / 15 named / no placeholders / inspector present) decide. The design of the pipeline itself is good: it never mutates the source `project.godot`, stages a copy, verifies hashes, and refuses to package an unvalidated runtime.

### FA-06 · P2 · AUTO · Row170 rear dumpsters have no usable visual acceptance

- **Where:** `artifacts/alive-next/visual/row170-rear-doors-dumpsters.png` (camera eye (370, 1, −148), heading 180, pitch −17) shows a rooftop, chimneys and barred windows; no rear door or bin is in frame. The world report explicitly says the third bin on the opposite-facing end unit "needs visual judgment".
- **Evidence that the geometry exists:** `city_alive_world.gd:99-137` accepted 3 bins (`dumpster_rejected: []`, integration-report) and `city_alive_world_smoke` passed at integration3 on the current `city_alive_world.gd` hash.
- **Fix:** re-capture from lane level inside the rear lane (eye height 1.7 m, two headings, one per lane side) via the existing `city_alive_next_render` views list, or inspect with F6 and save F8 captures. Confirm the end-unit bin does not block its rear door corridor.

### FA-07 · P2 · AUTO · Tire-shot acceptance margin for catalog kinds is on a floating-point boundary

- **Where:** `city_car_catalog.gd:323-325` sets the lower hull `wheel_band` exactly 1 mm inside the tire face. `city_combat.gd:392-397` (`_trace_bullet`) only accepts the analytic tire when its distance is `< from.distance_to(endpoint) - 0.001`, where the endpoint comes from the physics ray against the convex hull. A perpendicular side-on shot therefore produces `d − 0.001 < d − 0.001`, which is equality, so the result depends on rounding. Legacy kinds have a 5 mm margin (`city_car_collision.gd:24` half + 0.045 vs analytic tire face half + 0.050 from `city_vehicle.gd:113`), so they are safe.
- **Evidence:** static review. The catalog-integration fixture shoots perpendicular rays but through `car.raycast_tires` directly (`city_car_catalog_integration_smoke_runner.gd:43-49`), which compares strictly without the 1 mm margin, so it cannot detect this. Oblique shots, and shots at the exposed lower tread below y = 0.08, are unaffected.
- **Fix:** either set the catalog inset to 5 mm (`- 0.005`) to match legacy, or change the `_trace_bullet` comparison to `<= ... - 0.0005`. Add one production `_fire` test on a catalog kind at 90° (place the player at wheel height, muzzle aligned) asserting `last_shot.tire == true`.

### FA-08 · P2 · AUTO · Recycled damaged cars keep their flats and permanent physics forever

- **Where:** `city_vehicle.gd:740-778` (`try_recycle`) resets route, tire-handling motion and timers but never clears `flat_tires` or calls `_update_wheels()`; `set_presence` (`:484-497`) keeps `near_physics` and `collision_layer = 16` for any car with flats at any distance. The far-damage scheduler bounds tick cost (`city_traffic.gd:412-438`, max 8 coarse updates per frame, verified by the traffic-budget fixture), so this is not unbounded work, but it is a session-long accumulation of physics-active bodies and a recycled car visibly respawns damaged.
- **Fix:** on a successful recycle, clear `flat_tires`, call `tire_handling.reset_motion()` (already done) and `_update_wheels()`, then `set_presence(player)` so the layer follows distance again. Extend `city_traffic_damage_budget_smoke_runner.gd` jam case: puncture before recycle, assert `flat_tires.is_empty()` and `collision_layer == 0` beyond 65 m afterwards. This is AF-12's second half.

### FA-09 · P2 · AUTO · Documentation and help text still contradict shipped behavior

- `godot/README.md:98` and `:148-150` say mission progress and points last only for the current visit; `:276` describes the persistent versioned checkpoint. AF-18 remains open.
- `godot/release/PLAYING.txt:31` "every30seconds" (missing spaces) ships in the package.
- `city_settings.gd:57` Controls text omits `O` (photo folder) and `F5` (save while the phone is open) which PLAYING.txt documents.
- Roadmap §1.2/§11 and IMPLEMENTATION status rows are stale (see FA-03).

### FA-10 · P3 · AUTO · Two allocation-per-frame hot spots (from the car assessment; verified in source)

- `city_vehicle.gd:86-87` `effective_braking()` builds a profile dictionary and two arrays even with zero flats, and `_tick_motion` calls it for every near car every tick (`:599`), plus `control_distance` (`city_traffic.gd:302`). Return `BRAKING` when `flat_tires.is_empty()`.
- `city_world_audio.gd:45-54` writes `stream_paused` on all 12 voices every process frame. Only reapply while paused or when the flag changes. Keep the "just-scheduled voice" guarantee by reapplying on the frame the pause begins.
- Validation: traffic-budget, tire, melee-audio fixtures unchanged; measure in FA-04.

### FA-11 · P3 · AUTO · Traffic bootstrap still fails silently without "Old York Road"

- `city_traffic.gd:82-107` returns with no error if the named road is absent or shorter than 120 m, leaving zero cars. AF-11. Add `push_error` and a fixture assertion `traffic.vehicles.size() >= 80` (the longest-road substitution should wait for network validation, as the follow-up note says).

### FA-12 · P3 · AUTO · Reliability fixture leaves recovery copies in `.work`

- `city_release_reliability_runner.gd:63-69` calls `recover_saving()` on `.work/alive-next/exit-fixture.json`; four `exit-fixture.json.recovery-*` files have accumulated. Clean the fixture basename and its suffixed files at start and end, as `city_world_save_smoke_runner.gd:277-281` does.

### FA-13 · P3 · AUTO · graphify still has no GDScript nodes

- `graphify-out/manifest.json` contains no `.gd` entries; my query returned payphone.py and README nodes for a combat question. AF-19.

### FA-14 · P3 · AUTO · Promoted crowd actor collision height does not follow the roster height

- `city_combat.gd:927-941` builds the actor from a cast proxy (capsule height from that cast's `H`, `city_npc_actor.gd:53-60`), then swaps the visual rig to `look.height`. The capsule can differ from the visible body by roughly ±0.1 m. Harmless for play; set `actor.capsule.shape.height = max(0.8, look.height - 0.10)` and the capsule position as `city_resident_actor.gd:39-40` does, then verify the demotion path (`city_crowd.end_combat`, which copies the proxy shape) still passes the people fixture.

### FA-15 · CREATIVE · Decisions D1–D9 are unchanged and correctly held out of AUTO work

Driving, crime/heat policy, defeat stakes, economy/ammo, destinations, platform/min-spec, audio direction, entry flow (the staged release boots the city directly; `project.godot` keeps `scenes/main.tscn`), and save model. Nothing in this audit changes their framing. Two observations for those decisions: (a) seven mortal contacts still gate six cases and `on_actor_died` (`city_missions.gd:67-74`) closes the active case; the ledger now explains it (`:262-298`), which is the right AUTO scope; (b) the pistol's `reserve` cap of 72 is hard-coded in both `city_combat.gd:52` and the save validator `city_world_save.gd:188`, so any D4 ammo source must change both.

---

## 3. Requirement-by-requirement status (this pass)

| Requirement | Implemented where | Evidence | Status |
|---|---|---|---|
| Row050 lawns/bushes | `blender/city/alive_world.py` → `pen_lucy_alive_world.json`; `city_vegetation.gd:67-70` appends plants; 537 normalized beds, 3 shrubs | alive-world smoke (integration3), `final-cleanup-check.json`, `ss1` capture viewed | shipped; final human eye still recommended for residual apron grass on East 41st |
| Frisby side fence, other yards | `city_alive_world.gd:23-55`, 15 fences, solid boxes | alive-world smoke; `ss2` viewed (fence present, posts grounded) | shipped |
| Pine variety | `city_vegetation.gd:100-104` splits tree4/tree5 by high hash bits; 11 conifers | integration-report `conifers: 11`; `conifer-tree4` viewed | shipped |
| Row170 fronts | source frontage rule, 27 narrow fronts repaired; 8 rear doors preserved | alive-world smoke `rear_count == 8`; `ss3` viewed (doors/windows present) | shipped |
| Row170 rear dumpsters | `city_alive_world.gd:99-137`, 3 accepted | smoke passes; capture inconclusive (FA-06) | implemented, visual acceptance open |
| Firehouse grass | `city_alive_world.gd:56-69`, 30.6 m² each side | `ss4` viewed (strips visible) | shipped |
| Phone photo framework | `city_player_phone.gd` (one-frame SubViewport, viewmodel layer excluded, atomic PNG+JSON, no save overwrite, input ownership before combat) | phone-final + regression phone pass; render check verifies HUD/phone exclusion by pixel | shipped; see §4 for the ownership trace |
| Tire damage alters steering/braking | `city_tire_handling.gd`, `city_vehicle.gd:86-90, 587-660` | tire fixture pass (06:23): 0.61 m departures, yaw 0.089 rad, stop 7.93 m vs 11.04 m | shipped |
| Six vehicle silhouettes | `city_car_catalog.gd`, `city_car_mesh_kit.gd`, rotations `:17-20` | catalog 284/0, measured JSON fails 0, showroom 21/0, cars 35/0 (pre-edit) | shipped; rerun after the 06:28 catalog/parked edit |
| 20 modular looks, 16/2/2, 1,200 identities and 20 routines preserved | `city_modular_people.gd`, `city_population_appearance.gd:13-27` (permutation over birth ordinals), `city_crowd.gd:347-355`, `city_resident_actor.gd:27-42`, `city_combat.gd:927-943` | people fixture 0 failures, legacy-people pass, rosters viewed; crowd identity/recipe code unchanged | shipped |
| Melee witness | `city_combat.gd:474-558` (24 checks, 48 rays, no heat) | melee-audio 21/0 | shipped |
| Spatial audio | `city_world_audio.gd` (12 voices, inverse-square, pause sync) | melee-audio | shipped |
| Save recovery UX, blocked-save truth, checkpoint age | `city_world_save.gd:357-391`, `city_settings.gd:76-129`, `pen_lucy_level.gd:1054-1097` | reliability pass (integration4), save 77/0 | shipped |
| OSM attribution | full map `city_map_overlay.gd:50-54`; HUD credit `pen_lucy_level.gd:722-736` | full-map capture; HUD fix unverified (FA-01) | partially verified |
| Credits/notices | `city_settings.gd:107-116`, `assets/data/release_notices.txt`, package notices | credits capture | shipped |
| Case ledger, all-complete objective | `city_missions.gd:262-317` | case-ledger 10/10, reliability | shipped |
| Rules text (knockdown, ammo, deaths) | `city_settings.gd:57` | settings-controls capture | shipped |
| Native + Opus gap reports, Opus roadmap | present | read | see §6 |
| Standalone delivery | `export_city_release.py`, preset | not booted (FA-05) | not shipped |

---

## 4. Runtime logic review notes (static, by area)

**Input ownership.** `pen_lucy_level._input` (`:799-851`) orders dialogue → F6 → inspector → phone → Esc/M → pause gate → mouse capture → combat → orbit, and `_unhandled_input` (`:853-862`) handles E/V/look. The phone consumes every key and mouse button while active (`city_player_phone.gd:83-128`), returns M and F6 to the level after suspending itself, and the player gates movement, turning and jump on `phone.active` (`city_player.gd:225, 311`) because held `Input` state cannot be suppressed by marking events handled. Combat refuses direct attacks while the phone is active but keeps ticking NPCs and damage (`city_combat.gd:123-128`); `can_open()` refuses during knockdown, reload, combo, impact recovery, inspector, pause and tree pause, and `_process` suspends the phone when any of those begin. Pause, map, dialogue and focus loss all call `_suspend_phone()`. No defect found. One note: while paused, pressing P is swallowed by `phone.handle_input` before the Esc/M handling; harmless.

**Camera/movement.** Unchanged from the reviewed foundations (swept boom, curb solver, impact stumble). The photo camera reuses the first-person anchor with a wider pitch range and restores pitch on suspend (`city_player.gd:166, 613-618`; `city_player_phone.gd:80`). Movement fixture 114/0 on current hash.

**Missions/dialogue.** Preview never mutates (`city_missions.gd:321-331`), commits recheck range and revision (`:334-343`), restore never replays rewards (`:372-392`). Normal-input fixture covers offer, cancel, accept, three stages, completion, reload (30 green checks) up to the click (FA-02).

**Persistence.** Validator, atomic write, rejected-bytes preservation, future-version refusal and explicit recovery verified by the 77/0 save run and reliability run. Boot shows the blocked notice (`pen_lucy_level.gd:307-308`) and a persistent HUD badge (`:710-713, 979-980`). Known content coupling remains: 20-resident equality (`city_world_save.gd:199`) and index-keyed crowd deaths (`:256-258`) are the AF-16 migration items, not defects.

**Traffic/tires.** Logical route position decoupled from physical offset; damaged pose sweeps are exact nearby and rotation-expanded offscreen; leader corridor widened for damaged cars; braking planner uses reduced adhesion; stop lines and reservations stay authoritative. Traffic-budget fixture verifies the 8-per-frame coarse cap, fairness, offscreen-only recycling and reservation protection. FA-07/FA-08 above.

**Combat/crowd reactions.** Budgets (8 fighters, 16 panic, 24 corpses, 160 crowd panic) unchanged. Melee witnesses use facing and two sight rays per candidate, crowd witnesses panic through the existing cheap path. Corpse identity and permanent death registry unchanged. Promotion keeps the roster look; demotion restores the GPU slot and proxy capsule.

**World dressing/streaming/rendering.** World repairs are static batched kits in 48 m cells with distance culling and no per-frame work (`city_alive_world.gd:153-156`); lawn overlays add no collision; fences keep solid boxes. Vegetation keeps one mesh build per refresh and a 32 MB mesh history. Shaders: `city_surface.gdshader` and `city_vegetation_wind.gdshader` keep all variation in world space with no screen-space grain or post blur; `city_modular_people.gdshader` selects palettes and components per instance with no per-frame CPU appearance work. Environment uses SSAO and filmic tonemapping only (`pen_lucy_level.gd:361-399`). Draw calls: unmeasured on this tree (FA-04).

---

## 5. Design boundaries check

- No driving or heat system was introduced. `is_police` still only changes model, wheel radius and driver profile.
- NPC deaths remain permanent; player knockdown 3.5 s with full recovery (`city_combat.gd:234-240, 1313-1332`); finite ammo stated in Controls.
- Twenty reusable appearances, 1,200 identities and 20 daily IDs intact; appearance derives only from birth ID.
- No desktop takeover: the only OS interaction is `OS.shell_open` of the photo folder on an explicit `O` press (`city_player_phone.gd:109-111`); offscreen validation hides and unfocuses its window.
- Phone does not grant invulnerability (fixture asserts `_hurt_player` succeeds while composing).
- Photos are clean (no HUD, no viewmodel) and never touch the checkpoint files.
- Graphics stay clean; no grain, clay or blur passes were added.
- No language rewrite proposed; the two perf items (FA-10) are allocation removals.

---

## 6. Are the prior reports and the roadmap trustworthy?

- **Native and Opus audits:** their file-level claims matched what I read, with two corrections already superseded by the pass: the promotion appearance swap (F-19) is fixed, and the OSM credit (F-05) exists on the full map and, after the 06:28 edit, on the HUD. The Opus suggestion to drop physics retention for distant damaged cars was correctly rejected; the implemented coarse scheduler is the better answer.
- **Roadmap:** the structure is actionable: milestones have entry/exit conditions, decisions are isolated, no durations are invented, and the status vocabulary (verified/recorded/underway/not finished) is correct. Its §1.2 and §11 tables are stale relative to the tree (export preset, melee witness, spatial audio, notice queue, attribution, recovery UX, rules text and case-ledger fixture now exist). Its M0 exit list is right, and by that list M0 is **not** exited: criterion 1 (fresh hash-tied summary, zero errors) fails on FA-02/FA-03; criterion 2 (normal-camera review of the user spots) is met for four spots and open for the rear bins (FA-06); criterion 3 is this audit.
- **IMPLEMENTATION_AND_REVIEW.md:** accurate in scope and boundaries; two status rows are stale (case ledger, vehicle failures) and the "Root acceptance addendum" is still reserved, which is honest.
- **auto-fixes.json:** still a planning snapshot. Items now done in source: AF-01/02/03/15 (recovery flow), AF-04 (pending FA-01 rerun), AF-05, AF-06, AF-07, AF-08, AF-09 (bounded FIFO, no priorities), AF-10, AF-14 (derived, not persisted history), AF-20 (preset; build not certified), AF-25 (fixture written, red), AF-26 (phone reruns green), AF-27 (people fixture), AF-29. Open: AF-11, AF-12 (second half), AF-13 (done for jams via `abandoned_jam`), AF-16, AF-17, AF-18, AF-19, AF-21, AF-22, AF-23, AF-24, AF-28, AF-30, AF-31, AF-32.

---

## 7. What I looked at with my own eyes

- `ss1-east41st-lawns.png`: continuous front lawns with three rounded shrubs; one small green patch remains on the paved strip right of center that may be residual ground grass; cannot tell from one angle.
- `ss2-frisby-side-fence.png`: short wooden side fence along the exposed end wall, posts grounded, approaches open.
- `ss3-dumbarton-fronts.png`: Row170 fronts now have doors, windows, porches and lawns.
- `ss4-firehouse-side-lawns.png`: two narrow grass strips beside the engine house over the paved apron.
- `row170-rear-doors-dumpsters.png`: rooftop and chimneys only; inconclusive (FA-06).
- `conifer-tree4.png`: tiered pine beside a porch with a seated and a standing modular resident.
- `npc-roster.png`, `npc-daily-roster.png`: twenty distinct looks, hair and garment variety readable.
- `04-pickup-front-three-quarter.png`: readable pickup silhouette with bed and two-tone body.
- `gameplay-minimap.png`: HUD at 1600×900, no minimap credit visible (FA-01 confirmation).
- `settings-video.png`, `settings-controls.png`: action row and rules text visible at 1600×900.
- `full-map.png`: credit line present at the bottom.

---

## 8. Limits of this audit

- Static review cannot certify runtime feel, hitching, audio balance or the 1,200-person density on screen; only the matched-route run and a human session can.
- I did not run Godot, so FA-01, FA-02, cars/catalog after the 06:28 edits, and the rc2 export remain unverified.
- The AppData export-template directory was outside my permitted paths; I cannot say whether 4.7.2 templates are installed, only that rc2 produced an exe and pck.
- The tree changed during the audit; §1.3 lists what moved. Treat the hashes in §1.1 as the audit snapshot, not as a certification of the final tree.
