# aftermath-contract.md — incident aftermath and ambulance response (priority 2)

Owner: aftermath worker (claude-opus-5-5, MAX). Status: **r2 — final, shipped signatures.** Supersedes r1.
Final report: `aftermath-report.md` beside this file. The aftermath worker ran **no engine**; root runs every fixture.

Concurrency note: while this worker was still implementing, root's fix pass (acting on `ems-review.md`,
`ems-routing-review.md`, `ems-service-review.md`) edited the owned files in place: `_treatment_contact`/`TREAT_HEIGHT`,
the scene deadline first in `_tick_scene`, multi-incident `refs`/`MAX_CALL_REFS`/`_call_refs`, per-actor visibility
in `_recover_home`, the driver's junction yield (yield while the conflict lasts) and query counter, and explicit
types where `:=` inferred from a Variant. All kept as the current state; this worker completed the matching
service side (a junction that stays busy is a bounded `VEHICLE_WAIT` then replan/closure, `_wait_limit`).

## 0. Files

Edited (owned):
- `godot/scripts/city/city_incidents.gd` — creates/ticks/resets the EMS child; watches the harm a fight does;
  optional durable `medical` summary; `note_injury`, `medical_for`, `on_medical_progress`; requests an ambulance
  for reported/found injuries; validates/settles/relays medical state.
- `godot/scripts/city/city_police_status.gd` — cards add one medical line, merged police+medical timeline,
  `card.medical`; a live ambulance keeps the card live. Records without `medical` produce unchanged cards.
- `godot/scripts/city/city_combat.gd` — narrow: see §8.
- `godot/scripts/city/city_police_assistance.gd` — **unchanged** (EMS reads `call_status()` only).

New:
- `godot/scripts/city/city_emergency_response.gd` — EMS service (Node3D `EmergencyResponse`, child of `NeighborhoodIncidents`).
- `godot/scripts/city/city_emergency_status.gd` — pure static medical vocabulary.
- `godot/scripts/city/city_ambulance_driver.gd` — kinematic, ground-snapped, hull-swept path follower.
- `godot/scripts/city/city_emergency_people.gd` — patient holds (crowd stand-in, ≤ 2).
- `godot/tests/city_emergency_response_smoke.gd` + `_runner.gd` — headless arena regression fixture.
- `godot/tests/city_emergency_city_session.gd` + `_runner.gd` — actual-city session fixture.

## 1. Lifecycle (as shipped)

1. People react (existing combat/crowd panic, witnesses, victim statement).
2. Injury is combat's fact: while an incident fight lasts `_watch_injury` reads `combat.npc_fight_status(victim)`
   (knocked → `knocked_down`; health ≤ `INJURY_HEALTH` 60 → `hurt`; bicycle knockdowns never count). At fight end
   (or if the record closes mid-fight) the record gets `medical.stage = "injured"`. External systems may call
   `note_injury()` for a person the record names. Never the player, never someone who died.
3. A call is required: the ambulance is asked when a report is accepted, when an injury follows a report, when
   police report `on_scene`, or on a repeat report after a failed/interrupted response. Requests are queued and made
   on the next unpaused incidents tick (never inside the report call).
4. Police handle the incident unchanged; medical care is independent of the police outcome.
5. The injured person waits: a free crowd neighbor is held by one stand-in (begin/end_combat); named/daily people
   are tracked only. Combat, custody or death takes precedence at any time (hold forgotten, never overridden).
6. The ambulance (minivan hull, the civic fleet's ambulance livery, beacons) starts in a validated canopy bay or
   at a validated curbside standby; dispatch follows the bay approach (≤ 3 m/s) or curb pull-out, then police-lane
   routes over traffic lanes/connectors, pulling over at a validated curb spot when one fits.
7. Arrival before treatment: `en_route` only after ≥ 2 m of real driving; `on_scene` only when the leg is finished
   and stopped (or a bounded foot-arrival ≤ 45 m from the end on the carriageway after being held up);
   `treating` only with a paramedic in physical contact (`_treatment_contact`: reach, height, clear ray); the
   9 s treatment timer runs only during contact with a calm (`ok`) patient.
8. Outcome: `treated` (person released to ordinary life) or an honest terminal outcome (§3). A dead patient is
   forgotten, never released/revived/treated.
9. Crew walk back and board; the ambulance leaves when the crew are aboard (or after `CREW_RETURN_LIMIT`);
   clearance becomes `cleared` after it has driven ≥ 25 m away; it returns to the standby (or backs into the bay).

## 2. Bounds and cost

1 ambulance, 2 paramedics, ≤ `MAX_CALLS` 3 live calls (1 served, FIFO queue), ≤ 2 holds, ≤ 6 closed calls,
≤ 8 incident refs per call, ≤ 6 timeline steps per call/record. Think 4 Hz; driver sensing 10 Hz (traffic arrays by
position, one box cast + one rest-info); per moving physics step ≤ 4 hull queries + 5 ground rays; crew walking uses
the police walker (1 ray + move_and_collide); contact checks ≤ 2 short rays per crew per tick. No world scans.
Idle: ~nothing (4 Hz bookkeeping on ≤ 3 calls and 2 crew). Exit/standby validation once at setup
(≤ `MAX_EXIT_CHECKS` 24 physics-checked candidates; bounded retries `CONFIGURE_TRIES` 3 × 2 s).

## 3. Status vocabulary (`city_emergency_status.gd`)

Stages: `injured` (record only) → `requested` → `queued` | `dispatched` → `en_route` → `staging` (optional) →
`on_scene` → `treating` → `resolved` | `failed` | `cancelled`. Timeline-only step `cleared`.
Outcomes: `treated` (resolved); `unreachable`, `blocked`, `no_access`, `unavailable`, `unsafe`, `timeout` (failed);
`patient_left`, `patient_died`, `in_custody`, `cancelled`, `interrupted` (cancelled). Clearance: `""`, `at_scene`,
`cleared`. No ETA/countdown/percentage. Static API: `is_live`, `terminal_stage`, `label`, `clearance_text`,
`summary(medical, live := true)`, `next_action`, `injury_text`.

## 4. APIs (shipped)

`city_incidents.gd` (additive):
```gdscript
var emergency: Node3D                                  # child "EmergencyResponse"; null only on instances never set up
const INJURY_HEALTH := 60.0
func note_injury(incident_id: String, person_id: String, injury := "hurt") -> bool   # "hurt" | "knocked_down"
func medical_for(id: String) -> Dictionary             # deep copy; {} when nobody was hurt
func on_medical_progress(ref: String, data: Dictionary) -> void   # EMS relay; single writer of rec.medical
```
`report_status_changed` also emits `status: "medical"` payloads:
`{incident_id, police_incident_id, status: "medical", outcome, text, by, phone, minutes, title, stage: "", handling: "",
street, medical_stage, medical_outcome, clearance}`. Root's existing `_on_incident_report_status` forwards `text`
when `phone` (report.phone or a live phone follow-up).
`reports_for()` copies of records with `medical` carry transient `medical_live: bool` (never saved).
`get_status()` adds `medical_due` and `medical` (EMS `get_status()`); counters add `injuries`, `medical_requests`,
`medical_refused`.

`city_emergency_response.gd`:
```gdscript
var available: bool; var reason: String; var revision: int
var calls: Array[Dictionary]; var history: Array[Dictionary]; var base: Dictionary; var base_report: Array[String]
func setup(owner_level: Node, owner_incidents: Node) -> void
func configure_base(spec: Dictionary) -> bool     # {bays: [Transform3D] | bay: Transform3D, name}; fixtures and retries
func request(event: Dictionary) -> Dictionary     # {ref, patient, injury, at, by, street, phone}
                                                  # -> {ok, call_id, duplicate, stage, outcome, message, reason}
                                                  # refusals: invalid, identity, capacity, deceased, custody, absent, unavailable
func has_live(ref: String) -> bool
func call_for(key: String) -> Dictionary          # by incident ref or call id: live first, then newest closed
func view() -> Dictionary                         # {available, reason, revision, live, history, minutes}
func blocks_checkpoint() -> bool                  # always false
func tick(delta: float) -> void                   # only from incidents.tick(); paused/inspector/tree-paused: no-op
func reset_state(why := "reset", relay := true) -> void
func get_status() -> Dictionary                   # incl. base {name, home, curb, report}, unit, driver, crew, people, counters
```

## 5. Save / durable state (root and save worker: nothing to change)

- `incidents` section stays version 1. Records gain an **optional** `medical`:
  `{patient, injury, stage, outcome, text, minutes, opened_minutes, clearance, timeline: [≤6 {stage, outcome, text, minutes}]}`,
  validated when present (`_validate_medical`); older records without it remain valid.
- Live EMS state is never saved and never blocks a checkpoint. `incidents.restore_state()` first calls
  `emergency.reset_state("checkpoint", false)` (no relay; restore stays faithful for the rollback equality check);
  a restored live medical stage settles on the next upkeep to `cancelled/interrupted` ("result unknown").
- Paramedic identities `ems_paramedic_1/2` are registered in `level.npcs.actors` during `incidents.setup()`
  (before any checkpoint load) with meta `ems_crew`; a dead paramedic is never re-seated; no living crew → unavailable.

## 6. Root integration

None required. Optional, root's choice: expose `level.emergency_response = incidents.emergency` for diagnostics/map;
consider a neutral HUD prefix for medical notices (the phone currently prefixes every relayed notice "Police: ";
medical texts are worded to read acceptably after it).

## 7. Traffic integration (traffic owner's shipped registry)

`traffic.register_emergency_vehicle(ambulance)` whenever a leg starts (respond/return/back-in);
`unregister_emergency_vehicle()` when parked at home (bay, or the standby that leaves the travel lane free), on
`_place_home` (reset/load/recovery) and on teardown. On scene and when stranded it stays registered (a real obstacle).

## 8. Combat edits (narrow)

- `npc_fight_status(id)`: also reports a fleeing (panic) person's health/body (`mode: "panic:<mode>"`).
- `_fightable`: refuses actors with `ems_responder` or `ems_patient`.
- `_bike_exempt`: `ems_responder` → `on_duty`; `ems_patient` → `injured` (a bump only stumbles; no knockdown/grudge).
- `_react`: skips `ems_responder` (no gunfire-hearing panic; direct hits still land). Scene safety is the EMS's
  (`_scene_unsafe`: an armed fighter within 28 m or a live armed police call → staging/recall).

## 9. Fixtures (root runs)

- Headless arena: `res://tests/city_emergency_response_smoke.gd` (treated lifecycle with truthful stages, duplicates,
  care independent of police, pause/inspector, unreachable, death without revival, patient left, custody refusal,
  checkpoint interruption + validation + retry + reset, bounded calls/holds, armed staging, teardown, combat edits).
- Actual city: `res://tests/city_emergency_city_session.gd` with user args `--session-run-id=<id>` (rendered runs
  also `--offscreen-validation`); writes `.work/next-five-20261101/aftermath-city-<id>/result.json`.
