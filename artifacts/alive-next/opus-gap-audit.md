# Pen Lucy GTA-gap audit (independent, read-only)

**Reviewer:** Claude Opus 5.5, high effort. **Date:** 2026-10-31. **Mode:** read-only source/artifact review. I made no source edits, ran no engine or shell tests, made no commits, and did not open other current reviewers' reports (`artifacts/alive-next/native-gap-audit.md` was deliberately left unread).

**Target:** a small, indie-scope, GTA-like Baltimore sandbox. I measured against what a player expects from "small GTA": walk, drive, fight and shoot; the world reacts and remembers; missions give a reason to move; the game ships and runs. I did not measure against AAA feature count.

**Method.** I ran `graphify query` first. The graph (`graphify-out/graph.json`, 1,783 nodes) indexes only the web prototype JS, the Blender Python and the markdown. **It has no GDScript nodes**, so every Godot finding below comes from direct reads of `godot/scripts/city/*.gd`, `godot/project.godot`, the launcher, the tests and the artifacts. Re-indexing GDScript would make future graph-first audits useful (see A-14).

**Snapshot caveat.** The tree was being edited during this audit. For example, `pen_lucy_level.gd` grew between two of my reads, so line numbers may drift by a few lines. World, phone, tire, NPC and six-new-vehicle work is in progress. I do **not** treat missing parts of those features as regressions. I assess only the systemic foundations they will sit on.

**Evidence labels**
- **V (verified):** read directly in code or config at the cited location.
- **H (hypothesis):** inferred from code. Player-visible frequency or magnitude is unmeasured, and an acceptance condition is suggested to confirm or refute it.
- **R (roadmap):** already listed as unfinished in a prior acceptance report. Cited so it isn't rediscovered as new.

**Fix classes**
- **AUTO:** low or moderate risk. A coordinator can implement and test it without creative input.
- **PRODUCT:** needs a creative, design or business decision first.
- **UNDERWAY:** overlaps current work. I name the underlying gap only.

---

## 1. Executive summary

The project's simulation foundations are unusually careful for indie scope. Swept collision for every actor, deterministic combat, a bounded fight/panic/corpse budget, atomic saves with backups, and roughly 900+ headless checks. What it lacks is not engineering rigor. It lacks the **core GTA loop and the shipping envelope**:

1. **The player cannot drive** (V). No enter, exit or drive code exists anywhere. Traffic cars are forward-only route followers (`city_vehicle.gd:2`). This is the largest single gap to "GTA-like", and it is a product decision with a large implementation cost.
2. **Crime has no consequence** (V). There is no wanted or heat state. Police respond only if an individual officer personally sees a gunshot (`city_combat.gd:449-458`). The four patrol cars are cosmetic. Melee assaults and murders are invisible to bystanders and police (`_punch_hit` never emits a witness event). Player "death" is a 3.5-second knockdown with a full heal, and every attacker retreats (`city_combat.gd:1207-1215`).
3. **Persistence can silently lock a save forever** (V). Any validation mismatch sets `_write_blocked` for the whole session. A changed resident count is one trigger (the count is hard-coded to 20 at `city_world_save.gd:195`, while NPC roster work is underway). Boot never shows the failure. Settings has no "start fresh" option. Every content update risks turning existing players' saves read-only with no explanation.
4. **There is no standalone build** (V). There is no `godot/export_presets.cfg`. Players must install the Godot 4.7 editor, and the launcher runs an editor-mode headless import on every launch (`Play Pen Lucy.cmd:17`). This is already on the roadmap (R).
5. **Mission content can be permanently destroyed** (V for the logic, H for frequency). All six cases depend on seven mortal NPCs. Officer Dan appears in three cases and Malik in three. NPC stray fire can kill them without the player intending it (`city_combat.gd:965`). Deaths are permanent and saved.
6. **Ammo is a one-time resource** (V). The pistol has 12 + 72 rounds per save, with no pickup, purchase or refill anywhere. Once spent, the pistol is useless for that save forever.
7. **Map data attribution is missing in-game** (V for the scripts). The city README requires "© OpenStreetMap contributors" when the map is shown (`blender/city/README.md:236-238`), but no city script renders it. This is a legal/shipping blocker with a trivial fix.
8. **Audio is thin and flat** (V). All combat and traffic sounds are non-positional 2D players. When launched via the `.cmd`, music only starts if the user touches the music slider (`city_settings.gd:102-105`). There is no ambience, footsteps or engines.

The best return for autonomous work: **save recovery UX + schema tolerance (A-1/A-2), OSM attribution (A-3), a melee witness event (A-4), tire-damage cost bounding (A-6), stuck-car recycling (A-7), positional audio (A-8), an InputMap migration (A-9), and a notice queue (A-10)**. Driving, heat/police response, death/respawn, the economy, ammo sources and mission depth are **product decisions** to make before building.

---

## 2. Prioritized findings table

Severity: **S1** blocks shipping or the core "GTA-like" promise. **S2** is a major player-facing gap. **S3** is noticeable or limits scale. **S4** is polish or hygiene.

| ID | Sev | Area | Finding | Evidence | Label | Player impact | Class |
|---|---|---|---|---|---|---|---|
| F-01 | S1 | Traffic / core loop | Player cannot enter or drive any vehicle; traffic cars are scripted route followers with no drivable model | no enter/exit/drive symbols in `godot/scripts`; `city_vehicle.gd:1-2` "Forward-only sedan" | V | The defining GTA verb is absent; the city is walk-only | PRODUCT (large) |
| F-02 | S1 | Persistence | Any save validation failure permanently blocks saving for the session; boot ignores the failed result; no reset path | `city_world_save.gd:83-86,114-117,263-280`; `pen_lucy_level.gd:271-278`; `city_settings.gd:55-58` | V | Progress after a content update silently stops saving; "Could not save" with no remedy | AUTO (A-1) |
| F-03 | S1 | Persistence | Resident roster hard-coded to exactly 20; crowd deaths keyed by index (`crowd_N`) | `city_world_save.gd:195,252-254` | V | Changing the resident roster (underway) or crowd generation invalidates every existing save, which feeds F-02 | AUTO (A-2) |
| F-04 | S1 | Shipping | No export preset; launcher needs an installed editor and runs editor-mode import every launch | no `godot/export_presets.cfg`; `Play Pen Lucy.cmd:3-23` | V, R | Players must install Godot; slow first launch; README says "double-click" | AUTO (preset) + PRODUCT (store/signing) |
| F-05 | S1 | Legal | No in-game "© OpenStreetMap contributors" credit although the map is shown | `blender/city/README.md:236-238`; 0 matches for OSM/© in `godot/scripts/city` | V (scripts), H (no other asset renders it) | ODbL non-compliance on release | AUTO (A-3) |
| F-06 | S2 | Combat / police | No wanted or heat state; police engage only on personal sight of a gunshot; police cars are cosmetic | `city_combat.gd:449-458,483-499`; `city_traffic.gd:194`; `city_vehicle.gd:41,296-299` | V | Shooting and killing carry no systemic risk; no chases | PRODUCT (design), then AUTO build |
| F-07 | S2 | Combat / civilians | Melee assaults and kills emit no witness event; only gunshots alert bystanders and police | `city_combat.gd:283-306` (no `_gunshot_event`/witness call); `_gunshot_event` called only at `:335,364,967` | V | Beating someone to death beside Officer Dan draws no reaction | AUTO (A-4) |
| F-08 | S2 | Combat | Player "death" is a 3.5 s knockdown, full heal and 3 s invulnerability, and all attackers retreat | `city_combat.gd:1207-1215,220-226` | V, R (deliberate "recoverable knockdown") | Losing a fight ends it in the player's favor; no stakes | PRODUCT |
| F-09 | S2 | Combat / economy | Ammo never replenishes (12 + 72 per save); persisted "without refill" | `city_combat.gd:46-47,155-161`; only assignments at `city_world_save.gd:92-93`; test `city_world_save_smoke_runner.gd:196` | V | Pistol permanently dead after 84 shots for that save | PRODUCT (source), AUTO stopgap |
| F-10 | S2 | Missions / NPCs | All 6 cases depend on 7 mortal contacts; deaths are permanent, saved, and cancel or lock cases; NPC stray fire can kill contacts | `city_missions.gd:41-73,187-229`; `city_combat.gd:965`; test asserts lockout at `city_world_save_smoke_runner.gd:238` | V logic, H frequency | One firefight near Wyanoke can delete 5 of 6 cases forever | PRODUCT (choose policy), AUTO after |
| F-11 | S2 | Missions | 6 short E-press fetch/report cases, hard-coded in GDScript; no fail states, timers, chases, combat or driving objectives; points have no sink | `city_missions.gd:8-15,187-229`; points only displayed (`pen_lucy_level.gd` ~`:986`) | V | Little reason to traverse the city or use combat | PRODUCT (content), AUTO (data-driven loader) |
| F-12 | S2 | Traffic / perf | A car with any flat tire stays physics-active forever regardless of distance, and its damaged pose is swept at 0.02 m granularity; network cars never recycle, so damage accumulates over a session | `city_vehicle.gd:461,410-420,642-656`; recycle only when `state=="parked"` at `city_traffic.gd:410-411`, `city_vehicle.gd:702` | V code, H cost | After shooting many tires, physics cost can climb with no bound (no soak exists) | AUTO (A-6) / UNDERWAY tire work |
| F-13 | S2 | Traffic | Blocked cars never recover (only end-of-route "parked" cars recycle) | `city_traffic.gd:410-411`; `city_vehicle.gd:397-408,700-733` | V, R (vehicle-courts #2) | Permanent honking jams behind obstacles or crippled cars | AUTO (A-7) |
| F-14 | S2 | Perf / shipping | Performance measured only on an RTX 3070 Ti at Balanced; ~1,360 median and ~1,775 p99 draw calls; no min-spec, Low preset or 720p cohort | `artifacts/life-reactions/performance-summary.json`; `living-world/acceptance.md:18` | V | Unknown experience on integrated GPUs or Steam Deck | AUTO (benchmark task) |
| F-15 | S3 | Audio | All SFX are non-positional; NPC gunfire 25 m away is as loud as your own; honks are omni within 55 m | `city_combat.gd:1353-1366`; `city_vehicle.gd:403-408`; `audio.gd:68-73` | V | No directional threat cue; flat soundscape | AUTO (A-8) |
| F-16 | S3 | Audio | City launch via `.cmd` never starts music unless the music slider changes; no ambience, footsteps or engines; audio not paused with the menu | `city_settings.gd:96-105`; `Audio.start` only at `crimes/game.gd:97,256`; no `Audio.set_paused` in city | V | Silent city on direct launch | AUTO (start/pause), PRODUCT (music choice) |
| F-17 | S3 | Controls | Combat, interact, map, view, menu and jump use raw keycodes, bypassing InputMap | `pen_lucy_level.gd:783-822`; `city_combat.gd:119-139`; `city_player.gd:257`; only move/run use actions (`city_player.gd:312,328`) | V | No rebinding, no gamepad, no Steam Deck | AUTO (A-9) |
| F-18 | S3 | UI | One notice slot: case, check-in and save messages overwrite each other | `pen_lucy_level.gd:530-532,851-855,881` | V | Messages lost; the phone will need a queue | AUTO (A-10) |
| F-19 | S3 | Combat visuals | A crowd member promoted into a fighter becomes one of 4 cast characters (index%4), not its own appearance | `city_combat.gd:818-831`; `city_crowd.gd:633-646` returns position/yaw only | V code, H visible pop | Punched stranger visibly "turns into" Ricky/Granny | AUTO (investigate then carry appearance) |
| F-20 | S3 | NPCs / missions | Mission-contact placement failure is only a warning; the case silently disappears | `city_npcs.gd:135-138`; `city_missions.gd:47` | V code, H occurrence | Civic/world edits can delete cases with no signal | AUTO (A-11) |
| F-21 | S3 | Traffic | Traffic aborts entirely if no "Old York Road" ≥ 120 m exists | `city_traffic.gd:78-102` | V | A data rename removes all 90 cars | AUTO (A-12) |
| F-22 | S3 | Persistence | Launcher redirects `APPDATA` into the git-ignored `.work/play-profile`; editor F5 uses real AppData, so there are two diverging slots | `Play Pen Lucy.cmd:14`; `.gitignore:8` | V | Re-download or cleanup loses saves; confusing dual progress | PRODUCT (resolved by an exported build) |
| F-23 | S3 | Perf | ~12.9 s warm startup; trimesh collision for every city mesh; 40–46 ms worst frames | `artifacts/pen-lucy-dense/acceptance.md:52`; `pen_lucy_level.gd:384-399`; `living-world/acceptance.md:31` | V, R | Long load; occasional hitch | R (existing) |
| F-24 | S3 | Stability | Vulkan device loss in hidden-window benchmark startups, cause unproven | `artifacts/render-audit/acceptance.md:58` | V, R | Possible startup crash class on some drivers | R (watch) |
| F-25 | S3 | World | No interiors; routines use outdoor frontages | `README.md:27`; `living-world/acceptance.md:57` | V, R | Shops, homes and the precinct are facades | PRODUCT |
| F-26 | S4 | Docs | README contradicts itself on persistence (`:27-28` vs `:57-58`); living-world acceptance still says "no autoload, no permanent deaths" | `README.md:27-28,57-58`; `living-world/acceptance.md:57` | V | Testers and users misinformed | AUTO (A-13) |
| F-27 | S4 | Release hygiene | F6 free-fly inspector is listed in the player Controls tab | `city_settings.gd:51`; `pen_lucy_level.gd:770-776` | V | Debug tool exposed (pauses the game, so low abuse risk) | AUTO (gate behind flag) |
| F-28 | S4 | Tooling | graphify graph excludes GDScript | `graphify query` output: only JS/PY/MD nodes | V | Graph-first audits blind to game code | AUTO (A-14) |

---

## 3. Area-by-area detail

### 3.1 Player, camera and controls: good foundation, input plumbing is the gap
- **Verified strengths.** Camera-relative steering with free-look offset handling, a swept camera boom with immediate contraction, a capsule-swept curb/step solver with multiple fallbacks, coyote time, jump buffering and a vehicle-impact stumble (`city_player.gd:157-415,494-584`). This is solid third-person feel work. Don't churn it.
- **F-17.** Only `move_*`, `turn_*` and `run` go through InputMap. Everything else is a raw keycode: 1, 2, R, LMB, RMB (combat); E, V, M, Esc, F6 (level); Space (jump in `city_player.gd:257`). Rebinding and gamepad are therefore structurally impossible.
- **Existing roadmap (R).** Jump-off platform momentum is overwritten (`vehicle-courts/acceptance.md:37`). The passive-fall-behind-menus issue from the same list now appears fixed (`city_player.gd:274-279`).
- **H.** First-person view combined with pistol aim uses the same `aim_direction` math but no shoulder offset. Probably fine, but it is untested in captures.

### 3.2 Combat: gunfire, aggro and death
- **Verified strengths.** One shared bullet trace for player and NPC (body-to-barrel guard, then world ray, then analytic tires), backward-endpoint rejection, telegraphed NPC fire with deterministic accuracy, and bounded budgets (8 fighters, 16 panic, 24 corpses) where an over-budget hit still applies its damage (`city_combat.gd:308-447,585-655`).
- **F-07 (V).** `_punch_hit` → `_damage_target` → `_kill` never notifies bystanders or police. Only `_fire` and `_npc_fire` call `_gunshot_event`. Bystanders keep walking and Officer Dan watches.
- **F-08 (V).** At zero health: `downed = 3.5`, then all fighters `_start_return`, then health resets to 100 with 3 s invulnerability. There is no positional, economic or progression consequence. The living-world pass documented this as a deliberate choice ("recoverable knockdowns").
- **F-09 (V).** `reserve` starts at 72 and only decreases. The save validator caps reserve at 72 (`city_world_save.gd:184`), which means any future pickup that exceeds 72 also needs a validator change. Tie them together (A-5).
- **F-19 (V code / H visual).** `_promote_crowd` builds `Actor` with `["liner_2","ricky","mailman","granny"][index % 4]` and label "Neighbor". The crowd batch instance is scaled to zero. No appearance is transferred.
- **Missing for "small GTA" (PRODUCT, not defects).** A second weapon class, weapon pickups or dropped guns, hit-direction indicator, lock-on or soft-aim, and cover. Indie scope can skip most of these. Ammo sources and death stakes are the two that matter.

### 3.3 Civilians, routines and police response
- **Verified strengths.** 20 authored residents with schedules and post-combat reconnection, a 1,200-member multimesh crowd with spatial threat scans, and panic/cower/return states with bounded trails (`city_residents.gd`; `city_crowd.gd:766+`; `city_combat.gd:1063-1148`).
- **F-06 (V).** `_react` has police engage only with `direct` or `_sight`. There is no shared alert, radio, dispatch, heat accumulation or decay. `is_police` on vehicles changes only the model, wheel radius and the cautious driver profile.
- **F-10 (V/H).** Contacts are ordinary `Actor`s in `npcs.actors`, killable by player hits and by NPC stray rounds (`_damage_target(..., "stray", muzzle, false)`). `on_actor_died` cancels the active case, and `_available_offers` skips dead contacts permanently. The test suite asserts the lockout is intended (`city_world_save_smoke_runner.gd:238`). Content-loss map: killing `officer` removes parcel_report, dumping and porch_light. Killing `lookout` removes parcel_report, dumping and torn_notice. Together they remove 5 of 6 cases.
- **F-20 (V).** `_spawn` only warns on placement failure. Case offers silently omit missing contacts.
- **R / PRODUCT.** Interiors (F-25).

### 3.4 Missions, dialogue and progression
- **Verified strengths.** Restore without replaying rewards, stale-callback refusal, preflight before mutation, and a dialogue preview that never mutates (`city_missions.gd:141-184,279-351`).
- **F-11 (V).** Six cases of 3–4 "walk there, press E" steps. Step text, placement distances and clue meshes are all in code. "Community points" are displayed but nothing consumes them. There is no city ending, credits or completion screen beyond a notice (`pen_lucy_level.gd:853-856`).
- **Creative tension (PRODUCT).** The game premise is a snitch ("telling on everybody", `README.md:5`). The city cases are prosocial civic reporting. A GTA-like sandbox implies the player can also commit crimes. Whether the city's loop is *reporting* crime (heat on others), *committing* it (heat on the player), or both is the central creative decision. It determines what F-06 should look like.

### 3.5 Traffic, navigation and tire damage
- **Verified strengths.** Lane network with junction reservations, signals and stop signs; leader search via spatial cells; compound-hull swept motion; player-contact fraction math; deterministic flat-tire handling (`city_traffic.gd`; `city_vehicle.gd`; `city_tire_handling.gd`).
- **F-12 (V/H).** `set_presence` keeps `near_physics` true while `flat_tires` is non-empty at any distance (`:461`). `_damage_path_clear` samples `ceili(travel / 0.02)` poses, each with 4 `on_road` checks plus a shape query. Network cars never become `parked`, so they never `try_recycle` and their tires are never restored. Under the tire work underway, this is the underlying systemic risk. The life-reactions summary itself says "No sustained gunfight FPS measurement" (`performance-summary.json`, limits).
- **F-13 (V, R).** `_stop` only accumulates `stopped_time` and honks. Nothing recovers a car blocked longer than N seconds. The roadmap entry rightly forbids teleporting *visible* cars; off-screen recycling with the existing `_outside_view` guards is compatible with that rule.
- **F-21 (V).** Traffic bootstraps on the longest "Old York Road" polyline and returns early if it is missing or < 120 m, silently disabling the whole fleet.
- **F-01 (V).** Player driving would need a new controller, because the existing vehicle has no physical dynamics to hand over. It also needs a camera mode, enter/exit flow, pedestrian collision response, a save field, and traffic awareness of a non-route vehicle. A practical indie path: an arcade kinematic controller reusing `Collision.parts` and `_cast_fraction` sweeps, not `VehicleBody3D`.

### 3.6 Content variety
- **V.** 20 authored residents, 1,200 crowd instances, 7 mission contacts plus 6 patrol officers, 90 traffic cars (4 police), 144–216 parked cars, 6 cases, 1 weapon. New vehicle models are underway; I did not assess their count as final.
- **H.** The crowd-to-fighter identity swap (F-19) and the 4-character proxy pool will be the most visible variety seams in combat.

### 3.7 Persistence, load and recovery
- **Verified strengths.** Temp-file write, validate, then rename; `.bak` retention; preserving rejected bytes; future-version refusal; nothing applied before preflight (`city_world_save.gd:260-351`). This is better than most indie saves.
- **F-02 (V).** The protective stance has no user-facing exit:
  - `load_state` returns `{ok:false}` and sets `_write_blocked`. `pen_lucy_level._ready` only branches on `ok == true` and shows nothing otherwise.
  - Later saves return `ERR_UNAVAILABLE`, which the menu reports as "Could not save. Your previous checkpoint is retained." That is misleading when the "checkpoint" is from an older content version that can never load.
  - No "Start fresh / archive old save" control exists.
- **F-03 (V).** `known.size() != 20` and exact per-ID equality turn any roster edit into a hard refusal. Crowd deaths keyed `crowd_<index>` are validated against the current crowd size. Reordering the crowd silently re-targets deaths onto different people.
- **F-22 (V).** Two save locations, depending on how the game is launched.
- **Not saved (acceptable for indie, noted):** traffic and parked-car damage, crowd positions, time-of-day lights (derived).

### 3.8 UI, audio and phone
- **V.** Right-hand ledger, radar, full map, settings with immediate apply, dialogue with explicit hooks. Fonts and styling are coherent.
- **F-18 (V).** `show_notice` overwrites the text. The phone (underway) will need a message queue or history. Build it once, generically.
- **F-15 / F-16 (V).** 2D-only players; music start tied to slider change; no `Audio.set_paused` call on the city's Esc pause.
- **Phone:** underway. The only systemic recommendation is F-18.

### 3.9 Performance, LOD and draw calls
- **V.** Strong measured cohort on a high-end GPU: ~190–200 FPS delivered, ~2 ms viewport GPU, p99 frame ~12 ms. Traffic is ~2.3–2.5 ms per physics tick (R). Streaming, palette consolidation and vegetation presence exist.
- **Gaps:** F-14 (no low-end, Low-preset or 720p data), F-12 (unbounded damaged-car cost), F-23 (startup and worst frames), F-24 (device loss). No combat-heavy or long-session soak (life-reactions limits; living-world limits).

### 3.10 Shipping and release completeness
- **F-04 (V, R).** No export, no clean-clone or exported smoke test (already listed in `vehicle-courts/acceptance.md:38`).
- **F-05 (V).** ODbL attribution missing from the UI.
- **F-27 (V).** Debug inspector exposed.
- **F-26 (V).** Docs drift.
- **H.** No crash log surfacing beyond Godot's `--log-file` in `.work/`. That is acceptable for a first release once exported logs go to `user://logs`.

---

## 4. Actionable low-risk fixes a coordinator can implement autonomously

Each item lists its scope, why the risk is low, and an acceptance condition.

| # | Fix | Scope | Acceptance condition |
|---|---|---|---|
| A-1 | **Save recovery UX.** On boot, if `load_state()` is not ok and a file exists, show a persistent notice with the reason. Add a Settings button "Start fresh (keep old save)" that renames slot, `.bak` and `.tmp` to `*.archived-<ts>`, clears `_write_blocked` and saves a fresh checkpoint. Make `save_progress()` say "Saving is paused: your save is from an incompatible version. Use Start fresh to continue." when `_write_blocked`. | `pen_lucy_level.gd` (`_ready`, `save_progress`), `city_settings.gd`, `city_world_save.gd` (new `archive_and_reset()`) | Headless: write an incompatible fixture, boot, and assert a notice is visible containing the reason; press reset and assert the original bytes exist under `*.archived-*`, `write_blocked == false`, `save_state() == OK`. No path deletes bytes. |
| A-2 | **Roster-tolerant resident schema.** Replace `known.size() != 20` / exact-match with: unknown saved IDs ignored (logged), missing current IDs take their schedule default. Bump to v3 with a stable `crowd_seed`/`crowd_count` fingerprint; if it differs, drop crowd deaths only (not the whole save) and record that in `last_result`. | `city_world_save.gd:192-204,240-258`; `city_residents.gd:restore_state` | Fixtures: a 19- and a 21-resident roster both load `ok`; a crowd fingerprint change loads `ok` with crowd deaths cleared and named deaths retained; existing v2 tests still pass. |
| A-3 | **OSM attribution.** Add "© OpenStreetMap contributors" to the map overlay corner, the radar footer or settings, and a Credits section listing data and fonts. | `city_map_overlay.gd`, `city_settings.gd` | UI smoke asserts the label exists and is visible whenever the map overlay is visible. |
| A-4 | **Melee witness event.** In `_damage_target` (by_player, source `punch`) and `_kill`, call a `_witness_event(at, 12.0)` that reuses `_react` (police on sight engage `aggro`/`gun`; others flee) and `crowd.react_to_threat(at, 12.0, at, at)`. | `city_combat.gd` | Fixture: a police actor at 8 m with line of sight engages after a player punch kill; a civilian at 8 m panics; actors behind a wall at 8 m do not. Fight/panic budgets unchanged. |
| A-5 | **Ammo stopgap (if product approves).** Refill reserve to 72 at day rollover or at a precinct/locker interaction; keep the validator bound in a shared const. | `city_combat.gd`, `city_world_save.gd:184` | Fixture: reserve 0, advance to next day, reserve 72; save validates. |
| A-6 | **Bound damaged-car cost.** Drop the `or not flat_tires.is_empty()` presence override beyond e.g. 120 m (car stops logically, collider off). Allow damaged off-screen cars > 80 m to recycle via the existing guards and clear `flat_tires` on recycle. Optionally cap `_damage_path_clear` samples (for example ≤ 8 per tick). | `city_vehicle.gd:458-471,410-420,700-733`; `city_traffic.gd:410-411` | Soak: puncture all 90 cars, walk 300 m away for 120 s, and assert `physics_cars` returns to baseline ±5 and the traffic tick p95 stays within baseline +0.5 ms. Recycled cars have `flat_tires == []`. Never recycle while in view. |
| A-7 | **Stuck-car recovery.** If `state == "blocked"` and `stopped_time > 20 s`, the car is > 80 m away and off-screen at both its pose and its spawn → release its reservation and recycle onto a free spawn-pool lane. | `city_traffic.gd`, `city_vehicle.gd` | Fixture: block a lane with a static box; within 30 s of the player leaving view, the car recycles; the reservation map has no orphan entries; no visible teleport (assert `_outside_view`). |
| A-8 | **Positional audio.** Pool of ~8 `AudioStreamPlayer3D` on the SFX bus for NPC shots, hits and honks, with `unit_size` and `max_distance` tuned; keep the player's own shot 2D. | `city_combat.gd:1325-1366`, `city_vehicle.gd:403-408` | Headless: assert NPC shots use a 3D player positioned at the muzzle; the SFX slider still mutes them. |
| A-9 | **InputMap migration.** Add `attack`, `aim`, `weapon_1`, `weapon_2`, `reload`, `interact` (exists), `jump`, `map`, `toggle_view`, `menu` actions; replace keycode checks with `event.is_action_pressed`. Joypad bindings can follow. | `project.godot`, `pen_lucy_level.gd`, `city_combat.gd`, `city_player.gd` | All existing UI, movement and combat smoke suites pass unchanged; a new test injects `InputEventAction` for each action. |
| A-10 | **Notice queue.** A FIFO with priority (combat < case < save/system) and minimum display time; expose `push_notice(text, priority, seconds)`. The phone can subscribe later. | `pen_lucy_level.gd` | Fixture: three notices in one frame are all displayed in order; none is lost. |
| A-11 | **Mission contact placement is a hard check.** Fail `city_life_smoke` if any of the 7 contacts or a patrol is in `placement_failures`; on spawn failure, log at error level. | `city_npcs.gd:135-138`; tests | Test suite red if a civic or world edit removes a contact's spawn. |
| A-12 | **Traffic bootstrap fallback.** If "Old York Road" is missing, use the longest road and `push_error`; add a test asserting `traffic.vehicles.size() >= 80`. | `city_traffic.gd:78-102` | Renamed-road fixture still spawns cars. |
| A-13 | **Docs truth pass.** Fix `README.md:57-58`; annotate `living-world/acceptance.md:57` as superseded. | docs | Reviewer spot-check. |
| A-14 | **graphify GDScript coverage.** Re-index with `.gd` included (or add a GDScript extractor), so future audits can query the game code. | tooling | `graphify query "city_combat _kill"` returns GDScript nodes. |
| A-15 | **Audio start/pause.** Call `Audio.start()` at city ready when music > 0; call `Audio.set_paused` from `pause_exploring`/`resume_exploring`. | `pen_lucy_level.gd`, `city_settings.gd` | Fixture asserts `Audio._started` after ready with music > 0 and `stream_paused` while the menu is open. |
| A-16 | **Gate the inspector.** Enable F6 only with `--inspector` or `OS.is_debug_build()`; remove it from the player Controls text otherwise. | `pen_lucy_level.gd:770-776`, `city_settings.gd:51` | Release-mode test: F6 does nothing; Controls text has no F6 line. |
| A-17 | **Export preset draft.** Add a Windows Desktop preset with `user://` defaults, include `assets/data/*.json`, and add an "export then run headless smoke" script. | `godot/export_presets.cfg`, tools | Needs export templates installed. Acceptance: exported exe boots to `level_ready == true` headless and passes `city_smoke` in the exported context. |

---

## 5. Product and creative decisions (do not implement without the user)

1. **Driving (F-01).** Is a drivable car in scope for v1? If yes: arcade kinematic controller vs physics body; carjacking vs only "your" car; pedestrian hits (non-gory stumble already exists for the player). This is the largest scope item, and it shapes missions, police and the map.
2. **The loop's moral axis (F-06, F-11, §3.4).** Snitch (report other people's crimes, heat on suspects) vs GTA (commit crimes, heat on the player) vs both. This decides whether a wanted system exists and who it targets.
3. **Failure and death (F-08).** Keep the knockdown, or respawn at the precinct/hospital with a cost (points, ammo, time skip)?
4. **Economy and ammo (F-09, F-11).** What do community points buy? Where does ammo come from (store, locker, pickups, daily refill)?
5. **Contact mortality (F-10).** Pick one: (a) contacts are non-lethal (knocked down like the player); (b) roles are fungible ("officer" step → any living police actor; dead resident → next of kin); (c) keep permanent lockout but surface it on the map with "case lost" ledger entries. I recommend (a) for named contacts plus (b) for police. It keeps the "deaths matter" promise for strangers without bricking content.
6. **Interiors (F-25).** Which three or four interiors, if any? The precinct, a corner store and one home cover most mission needs.
7. **Distribution (F-04, F-22).** itch.io/Steam/zip, code signing, minimum spec target (F-14), Steam Deck support (pairs with A-9).
8. **Music and soundscape (F-16).** Reuse "Still There" for the city or commission/produce a separate ambient bed.

---

## 6. Test gaps

Existing suites are broad (covering save corruption, combat budgets, traffic reservations, tire handling, movement and UI). The gaps are mostly **long-horizon, cross-system and player-facing-recovery** behaviors:

| Gap | Why it matters | Suggested test |
|---|---|---|
| Blocked-save UX | F-02: the protection is tested; the user experience is not | Incompatible fixture → visible boot notice → reset path (A-1) |
| Roster and crowd evolution | F-03: content updates are certain | 19/21-resident and crowd-fingerprint fixtures (A-2) |
| Sustained gunfight soak | Life-reactions limits: "No sustained gunfight FPS measurement" | 5-minute scripted firefight with 8 fighters + 16 panic, FPS p95/p99 and physics tick budget |
| Fleet-wide tire damage soak | F-12 | Puncture all, walk away, assert `physics_cars` recovers (A-6) |
| Traffic stuck/gridlock soak | F-13, R | 30-minute headless traffic run; assert no car `blocked` > 60 s while off-screen; reservations never orphaned |
| Melee witness | F-07 | A-4 fixture |
| NPC crossfire kills contacts | F-10: frequency unknown | Seeded scenario: player fires near Wyanoke with armed civilians; record contact death rate over N seeds |
| Contact placement integrity | F-20 | A-11 |
| Exported build smoke | F-04, R | A-17 |
| Low-end/Low-preset perf | F-14 | Low preset at 1280×720 on integrated GPU or a capped-clock profile; record draw calls and frame p95 |
| Input via actions | F-17 | A-9 |
| Audio routing | F-15/F-16 | 3D placement and pause assertions (A-8, A-15) |
| Visual combat identity | F-19 | Offscreen capture before and after promoting a crowd member; image diff of silhouette and colors |
| Long-session memory | No hours-long soak exists (living-world limits) | 60-minute mixed walk/combat/traffic; Godot object and resource counts must plateau |

---

## 7. Suggested acceptance conditions for the next milestone ("small GTA, shippable")

1. **Ship envelope.** An exported Windows build launches without an installed editor, reaches `level_ready` in ≤ 15 s warm on the reference machine, and shows OSM attribution on the map.
2. **Save safety.** No content change can leave a player in a state where saving silently fails. Every failed load is shown to the player with a one-click non-destructive reset. A roster change of ±1 resident loads existing saves.
3. **Consequence loop (once designed).** A witnessed crime (gunshot *or* melee) produces a visible response within 10 s within 30 m of any police actor. The response decays when the player breaks line of sight for ≥ 30 s. Police vehicles participate if the design includes them.
4. **Content resilience.** No single NPC death removes more than one case permanently (or the chosen policy from §5.5 is implemented and visible).
5. **Sustained performance.** A 5-minute firefight and a fleet-wide tire-damage scenario each keep physics tick p95 ≤ baseline + 1.0 ms and delivered FPS p95 ≥ 60 on the agreed minimum-spec profile.
6. **Traffic health.** In a 30-minute headless soak, no car remains blocked for more than 60 s while off-screen, and no visible teleport occurs.
7. **Input.** Every gameplay verb is an InputMap action. Rebinding through the project InputMap needs no code change.
8. **Audio.** NPC gunfire is directional and attenuates. Music or ambience plays on direct launch when its volume is above 0.

---

## 8. What not to change

- The collision-swept actor and vehicle motion and the deterministic combat budgets. They are the reason the world is stable. New features (driving, heat) should reuse `_cast_fraction`, `_trace_bullet` and the fight-budget pattern rather than bypass them.
- The atomic save write path and rejected-bytes preservation. Fix the *user experience around it* (A-1/A-2), not the protection.
- The prior guidance against a wholesale Rust rewrite (`living-world/acceptance.md:66`). Nothing in this audit points to language-level CPU limits. The perf risks are unbounded *work counts* (F-12) and draw calls (F-14).
