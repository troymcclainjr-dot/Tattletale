# Final independent audit — Tattletale pacifist foundation (Pen Lucy)

Date: 2026-11-01. Auditor: independent read-only review requested in `.work/pacifist-foundation/final-audit-brief.txt`.

Model identity: the runtime environment declares this session as Fable 5.1 (model id `claude-fable-5-1`).
`claude --version` could not be executed (the permission tooling rejected the command twice), so no
CLI-reported identity is available and none is invented.

Mode: read-only. No production file was edited, no engine, build or export was run, no settings changed, no
git state touched. The only files written are this report and `final-audit-findings.json`. Every pass/fail
number quoted below is read from the root's receipts in `.work/pacifist-foundation/` and
`artifacts/pacifist-foundation/`; I did not run any test.

## Verdict

- P0 / P1 (must-fix before release): **none found**.
- P2 (real bugs or clear low-risk improvements): **2** (F-01 phone listing occlusion mask, F-02 checkpoint write re-parses).
- P3 (latent bugs, consistency, maintenance hazards): **5** (F-03 .. F-07).
- Optional design/perf notes: **5** (D-01 .. D-05), not bugs, no action required.

Nothing found re-enables violence, pays twice, fabricates evidence or reports, breaks save idempotence or
future-version refusal, or lets a bicycle contact earn a police reward. The shipped case content
(`parcel_report` only) is unaffected by F-03/F-04, which concern templates no shipped case uses yet.

Source state audited: the uncommitted working tree on top of `c14e66f` (the graphify graph was built from
`c14e66fb` and contains none of the new GDScript modules; grep of `graphify-out/graph.json` for the new module
names returned 0 hits, so scoped reads were used as the brief anticipated). `README.md` changed on disk
during the audit (04:59); the final text at lines 24–43 is current and consistent with the pacifist controls.

## Findings — P2

### F-01  Phone subject listing occludes through people and cars, contradicting the evidence policy
- File: `godot/scripts/city/city_photo_context.gd:141-144` (`visible_subjects`), with `:169-175` (`_hit_is_subject`).
- Policy it contradicts: `godot/scripts/city/city_case_evidence.gd:18-20` (`STATIC_MASK := 1 | 2`, "People and moving cars do not hide a subject") and `:129-134`.
- Trigger: `PhysicsRayQueryParameters3D.create(eye, entry.position)` is built without a mask, so the single ray to the subject's chest point uses every layer. Any neighbor body (layer 8) or car (layer 16) crossing that ray at capture time is the first hit; it is neither the subject's collider nor within `SURFACE_EPSILON` (0.15 m) of the point, so the subject is dropped from the listing.
- Impact: a correctly framed photo of the offender/prop is rejected by the case engine as `not_in_photo` (`city_case_engine.gd` photo evaluation only sees listed subjects via `Evidence.listed_subject`), and the photo id is already in `seen_photos`, so that capture can never count. On sidewalks with the 1,200-strong crowd this is a plausible false rejection; the player must retake. No exploit, no reward effect. Also inconsistent with the incident service's own re-check, which uses `SIGHT_MASK 1|2|16` (`city_incidents.gd:58`), so people never hide there either.
- Minimal fix: set `query.collision_mask = 1 | 2` (static world; or `1 | 2 | 16` if cars should hide, then update the `city_case_evidence.gd` comment) before `intersect_ray`. Keep `exclude` and the own-collider acceptance so layer-2 props with their own collider still pass.
- Regression evidence: add to the phone/photo smoke a layer-8 capsule between camera and a listed subject and assert the subject is listed with `line_of_sight` true; keep the existing wall case asserting omission. Re-run `city_case_engine_smoke_runner` (170 checks) and the foundation acceptance (80) unchanged.

### F-02  Every checkpoint write parses and validates the slot files up to ten times
- File: `godot/scripts/city/city_world_save.gd:825-869` (`write_snapshot`), `:785-806` (`read_snapshot`), `:808-823` (`_read`).
- Trigger: `write_snapshot` calls `validate_snapshot(state)`, then `read_snapshot()` (three `_read`s), then `_read(path)`, `_read(path + ".bak")`, `_read(temporary)`, then the preservation loop re-reads the same three sources, then `_read(temporary)` after writing. Each `_read` parses up to 256 KB of JSON and runs the full `validate_snapshot`, which fans out into progression, incidents, police custody, case engine and residents validators. This happens on the main thread every 30 s autosave (`AUTOSAVE_SECONDS`) and on manual saves.
- Impact: a periodic main-thread hitch proportional to save size. Unmeasured by me (I ran nothing; the 10 s live sample need not contain an autosave). This is a clear low-risk cost reduction, not a correctness bug; behaviour is otherwise correct and the rollback protection is sound.
- Minimal fix: factor `read_snapshot`'s `sources` map into `_read_sources()` and reuse those three results in `write_snapshot` for `existing`, `existing_backup`, `existing_temporary` and the preservation loop (keep the `_write_blocked` logic). That removes six of the ten passes with no behavioural change. The post-write `_read(temporary)` can stay.
- Regression evidence: re-run the world-save regression suite (`world-save-regression-3.log`, 82 checks) and the rollback/preservation fixtures unchanged; optionally time `write_snapshot` before/after in the live-world benchmark driver.

## Findings — P3

### F-03  Case roles filled by crowd stand-ins are permanently "absent"
- File: `godot/scripts/city/city_case_engine.gd:256` (`role_state`), `:190-195` (`is_present`), `:198-211` (`_candidates`).
- Trigger: `_candidates` resolves `incident:witness` to `summary.witnesses` and `incident:<role>` to participant ids, which for natural incidents are mostly `crowd_N` stand-ins (and sometimes `player`). Neither id is in `npcs.actors`, so `is_present` returns false and `role_state` hits `if _actor(actor_id) == null: continue`, leaving `living = false`, `confirmed = false`, state `absent`.
- Impact: an `interview`/`talk`/`report` objective targeting an incident role held by a crowd member can never become `ok`; `blocker()` reports absent forever and the case neither progresses nor cancels. Latent: only the draft template `templates/incident_report.json` uses incident roles; the shipped `parcel_report` uses named actors. It does block the incident-triggered authoring path described in `artifacts/pacifist-foundation/CASE_AUTHORING.md` for the common case.
- Minimal fix: in `is_present` and `role_state`, when `_actor(id) == null`, fall back to the incident service: present if `incidents._person_position(id)` is finite (exposed as a small `person_present(id)` that also checks crowd death and `combat_override`), and drop `player` from `_candidates`. Keep daily-resident handling unchanged.
- Regression evidence: extend `city_case_engine_smoke_runner` with a fixture incident whose witness is `crowd_12`; assert `role_state` is `ok` with that actor and the interview commit succeeds, and that a dead crowd witness yields `dead`.

### F-04  After a mid-response reload, a case-bound incident is reopened but nothing re-files it
- File: `godot/scripts/city/city_incidents.gd:1113-1121` (`_settle`), with `city_case_engine.gd:1139-1156` (`tick`, `await_incident`) and `:963-983` (`_commit_report`).
- Trigger: a case files through the `case` channel (not a phone call), so neither `police_assistance.blocks_checkpoint` (`city_police_assistance.gd:280-287`, phone calls/custody only) nor `incidents.blocks_checkpoint` (`:440-441`, always false) blocks saving while officers respond. On reload police `restore_state` drops ambient responses, `has_open_ref` is false, and `_settle` sets the record to `ended` with `rec.report = {}` "so the case can file it again". The engine's `report` objective is already `done` and `tick` skips done objectives; only `await_incident` consumes the record, waiting for `states` (draft: `resolved`).
- Impact: the case waits. The player can recover by re-reporting through the phone Police app within `REPORT_WINDOW_MINUTES` (120), but no objective text says so; after the window the record expires to state `expired` (`:1053`), which never satisfies `resolved`, so the case is stuck without being cancelled. Latent: the only template with `await_incident` is the draft `incident_report.json`; `report_with_witness` (shipped `parcel_report`) ends on the report itself and is unaffected.
- Minimal fix: in `on_incident_event`, when the active case's bound incident arrives as `ended` with an empty `report` while a `report` objective is `done`, erase that objective from `active.done` (and from `evidence`-independent state) so the player is asked to report again; or have `_settle` leave case-sourced records in `reported` and let the engine re-file via the `report` hook. Either keeps the proportional-police and once-only reward invariants (reward happens only at `finish`).
- Regression evidence: new case-engine smoke: start an incident-triggered case, commit the report, snapshot incidents + case engine, restore both, assert the report objective is open again and completes on the next `case_report` commit; assert no second `reward_case`.

### F-05  Incident victims with a physics body are never listed by the phone
- File: `godot/scripts/city/city_incidents.gd:413-417` (`_photo_subjects`), with `city_photo_context.gd:169-175`.
- Trigger: the victim entry carries `position` only (no `collider`/`node`), unlike the offender entry (`:408-412`). Performers (`performer_actor`, `:578-579`) and daily residents have capsules; the listing ray hits the victim's own capsule ~0.3 m from the chest point, beyond `SURFACE_EPSILON` 0.15, so the victim is dropped. Crowd victims without bodies are listed because the ray reaches the point.
- Impact: gallery metadata and any future "photograph the victim" objective cannot see bodied victims. No shipped objective targets a victim; incident `evaluate_photo` only scores the offender. P3 consistency.
- Minimal fix: when `performer_actor(victim)` or the named actor is a `CollisionObject3D`, add `"collider": body` to the victim entry.
- Regression evidence: phone photo smoke framing a `bag_snatch` victim performer; assert a subject tagged `incident_role:victim` is listed.

### F-06  Nested section versions are hard-coded in the future-version guard
- File: `godot/scripts/city/city_world_save.gd:668` (`case_engine` → `1`), `:670` (`police_assistance` → `1`), `:678` (`deaths` → `1`). Compare `:672` and `:674`, which read `_declared(..., "VERSION")`/`"STATE_VERSION"` from the owning service.
- Trigger: bumping `CaseEngine.VERSION` (`city_case_engine.gd:16`) or the police/deaths versions without editing this file.
- Impact: the build would classify its own freshly written sections as "newer than this build", so `read_snapshot` sets `_write_blocked` and refuses every save and load until the user deletes the slot. Currently consistent (all are 1), so this is a maintenance hazard, not a live bug; the existing future-version tests pass because they bump the file's constant, not the service's.
- Minimal fix: `_newer(missions.get("case_engine"), _declared(level.missions.cases, "VERSION"))` and equivalents for police custody and the death registry (expose a `STATE_VERSION` on `city_police_custody.gd`/the death registry if absent).
- Regression evidence: a unit check that each nested version compared in `_future_section` equals the owning service's declared constant.

### F-07  Two writers for the phone's police status line
- File: `godot/scripts/city/city_police_assistance.gd:783-787` (`_tell` writes `phone.set_report_status` directly for phone incidents) and `godot/scripts/city/city_incidents.gd:533-547` (`on_police_progress` → `_emit_status`) → `pen_lucy_level.gd:1379-1383` (`_on_incident_report_status` → `phone.set_report_status`).
- Trigger: every police progress step on a phone-originated incident.
- Impact: `set_report_status` (`city_player_phone.gd:230-234`) also raises `_notice`, so the player can receive two notices per step, the second (incident-service wording) overriding the first. Bounded and harmless; no state divergence because the incident service owns the record.
- Minimal fix: in `_tell`, skip the direct phone write when `incident.ref` is non-empty (the incident service will relay it), or make `set_report_status` ignore an identical consecutive message.
- Regression evidence: foundation acceptance phone phase asserting one notice per status step.

## Optional — design and performance notes (not bugs)

- D-01 `city_world_save.gd:64-65`: being seated on the bicycle blocks autosave for the whole ride; long rides can go several minutes without a checkpoint. Intentional per README ("Get off the bicycle ... before saving"); consider allowing a checkpoint while seated and stationary on stable ground if the root wants shorter loss windows.
- D-02 `city_police_assistance.gd:280-283`: a phone-fallback area check blocks checkpoints until the incident is `closing`, which can be up to the full response (worst case a few game minutes). Documented behaviour; note only.
- D-03 `city_combat.gd:902-906` (`_sight`): the ray must end on `target_body`; while the player is mounted, the bicycle hull/rider sphere are separate bodies, so a bike-grudge NPC very likely cannot land retaliation until the player dismounts. Consistent with "fists-only retaliation, not exploitable for police rewards" (provoked fighters are skipped by `_discover`, `city_police_assistance.gd:490`), so this is a feel note. Not verified at runtime.
- D-04 Small allocations in hot paths, negligible at current rates: `city_bicycle_reactions.gd:65-69` (new shape + query per 0.2 s scan), `city_player.gd:676` and `:818` (camera sweep query per frame), `city_day_night.gd:312-334` (full lamp re-sort every 0.25 s). Pool the query objects if a profiler ever shows them.
- D-05 Photo evidence is attached twice per capture (case `_add_evidence` and incidents `evaluate_photo` both record a photo entry on the incident record). Bounded by the record's evidence cap; harmless duplication.

## Verified sound (no finding)

- Rewards: `progression.reward_case` is idempotent via `rewarded_cases` (`city_progression.gd:591-615`); the data-driven `finish` and legacy `_complete` both route through it; `case_money` with `money_per_point 1.0`, no overrides (`pen_lucy_progression.json:91-94`) pays the migrated `parcel_report` the same 150 as the legacy path. Incidents and police never call progression.
- Report gates: `report_incident` refuses unknown/closed/expired/offender/unwitnessed/no-dispatch and returns `duplicate` without a second dispatch (`city_incidents.gd:197-238`); `_phone_followups` is present.
- Protected caller / no friendly fire: `_protected_points` (player, officers, NPC reporter) and `fire_clearance`; `_discover` skips provoked fighters and the reporter.
- Incident → custody ownership: `_comply` → `release_for_custody` handoff; custody builds a fresh stand-in; `_settle` handles records without live parts.
- Save: v4 preflight/rollback, `_future_section` refusal before fallback, canonical case snapshot/validate/restore, `seen_photos` persisted; no gallery re-submit path exists, so remembering a photo before the stage check is harmless.
- Bicycle: raised hull from 0.31 m, 11 support rays, STEP_HEIGHT 0.30, crash thresholds, swept-sphere recovery with `center = _body.global_position`, `blocks_checkpoint` while crashed; reactions connect before the level bridge and release on `combat_controlled`; cars sweep layers 1|2|4|8|16 and look ahead for layer 4 (`city_vehicle.gd:328-335, 385`).
- Camera/photo: `camera_yaw` forward convention matches `_player_facing`; `commit_photo` emits `photo_captured` once; gallery writes atomically with LIMIT 48; `can_open` blocks while riding/seated/inspector.
- Rendering: streaming refresh deduplicated (`city_streaming.gd:223`), vegetation `MAX_NEW_MESHES_PER_REFRESH 1`, sky shader has no `TIME` and quarter-res 8-sample volume, lamp pool of 8 lights, minimap single triangle batch, retained map meshes.
- Release: export include filter packages case JSON and notices; `PLAYING.txt`, `godot/README.md` and top-level `README.md` describe the pacifist controls; standalone r1 verified (zip sha256 `3cb8027f…ac60a`).

## Evidence assessment — fixture versus gameplay, timing versus causality

| Receipt | What it proves | Limit |
|---|---|---|
| Curb matrix r4: 2616 checks, 0 failures, 277 crossings | Solver behaviour on authored synthetic curbs, post-escape clear | Synthetic geometry, not the city mesh |
| `bike-city-final.log`: 186/0, 28 real-curb crossings, real parked-car crash, rider_overlaps 0 | Real-city curb and crash handling with production save objects | Scripted inputs |
| Crash suite r3: 88/0 | Eject/slide/getup/recovery with real player and save | Scripted impacts |
| Natural incidents r2: 36/0 | Production `_try_spawn` planner at 3 sites | Player placed by fixture |
| Foundation acceptance r3: 80/0 | Real key events through the input map to gameplay, checkpoint restore | Arranged placement, incident spawned by API (`spawn_template_now`) |
| Case engine smoke: 170/0 | Engine logic incl. replay/custody/dead/follow/visit/flee | Fake world; unit-level, not gameplay proof |
| Saves 82/0 | Production write/rollback/preservation | — |
| Sky 63/0, gallery r3 69/0 | Off-screen rendered windows, residency, collision preserved, PNGs written | No automated visual-quality judgement; images are for human review |
| Live 1080p metrics | `valid_active_play` true, mean 6.49 ms, p95 11.32, p99 15.49, draw calls p95 1347, 90 cars | 10 s sample; the "traffic" bucket spans traffic, bicycle, reactions, basketball, police, incidents, driving and presentation (`pen_lucy_level.gd:1144-1165`), so 3.387 ms/tick is not attributable to traffic alone; background contention unknown |
| Standalone r1 | Packaged build boots, input moves player, save, foundation checks, `gameplay_passed` | `display_server: headless`; rendering fidelity of the standalone is not shown by this receipt |

No receipt supports a causal "X made it faster" claim; comparisons across runs were made on a shared machine without controlled contention. Treat performance numbers as a non-regression sample.

## Limits of this audit

- No engine, test, build or export was executed by me; all counts are the root's receipts.
- The code graph predates the new modules; coverage relied on scoped reads of the modules listed in the brief plus their interfaces (traffic, player, input, basketball, persistence, release validation). Runtime-only behaviours (D-03, F-02 cost) are reasoned from source, not measured.
- `claude --version` and a few compound shell commands were rejected by the permission tooling; none affected findings except the identity statement above.
- Working tree was moving during the audit (README updated at 04:59); line numbers were re-verified immediately before writing this report.

## Recommended order of application

1. F-01 (one-line mask) and F-05 (one dictionary key), retest photo smokes and acceptance.
2. F-02 (reuse read results), rerun save regression.
3. F-03/F-04 together before any incident-triggered case ships; F-06 at the next version bump; F-07 when convenient.

Nothing here should be called release-ready until the root applies and retests; this audit did not run tests.
