# police-contract.md — police response clarity and reliability (priority 3)

Owner: police worker (claude-opus-5-5). Status: **r2 — implemented** (r1 listed these files before any
source edit). Nothing here was engine-run by me; root runs every test serially.

## 0. Files

Edited (owned):
- `godot/scripts/city/city_police_assistance.gd` — dispatch-stage model, single-owner transitions,
  truthfulness/reliability fixes, additive read-only APIs, `cancel_ref`.
- `godot/scripts/city/city_incidents.gd` — **narrow status bridge only**: relays stage/handling, stands police
  down when a linked record is closed by someone else, ignores late steps for closed records, read-only phone
  helpers, `revision`, honest post-reload text. Record schema, `STATE_VERSION` (1) and OUTCOMES unchanged.
- `godot/scripts/city/city_player_phone.gd` — **Police page / police notices only**.

New:
- `godot/scripts/city/city_police_status.gd` — pure static vocabulary + bounded card merge.
- `godot/tests/city_police_status_smoke.gd` + `_runner.gd` — headless logic arena (real police, real incident
  service, real actors/physics; combat fixture).
- `godot/tests/city_police_phone_view.gd` + `_runner.gd` — graphical offscreen review captures of the page.

Not edited: `city_phone_ui.gd` (not needed), `city_police_driver.gd`, `city_police_lanes.gd`,
`city_police_cruisers.gd` (assist contract reviewed; no defect found), `pen_lucy_level.gd`, `city_world_save.gd`,
bicycle/player, crowd/residents, audio, cases/missions content, models/world data.

## 1. Dispatch state vs incident state

- **Dispatch state** (police-owned, per call), `stage`:
  `received` → `queued` | `dispatched` → `en_route` → `on_scene` → `handling` → `resolved` | `failed` | `cancelled`.
  `handling` ∈ `contact | warning | commands | detaining | arrest | force`. Intake refusals are not calls: bounded
  `refusals` (≤ 3, phone callers only) with stage `unavailable`.
- `en_route` is evidence-based: only after an assigned officer or car physically moved ≥ 2 m from where it was
  dispatched. No ETA, percentage or predicted arrival exists anywhere. The only distance shown is the existing
  straight-line "about N m away" at dispatch time.
- **Incident state** (durable record): unchanged (`active | ended | reported | responding | resolved | expired |
  cancelled`). The phone card shows both: dispatch label + responders, and an "Incident:" line (who reported,
  whether the player confirmed, what officers actually know about the person).
- Coarse `status` (existing consumers) keeps its meaning: `received/queued → report_received`,
  `dispatched/en_route → responding`, `on_scene/handling → on_scene`, terminal → `resolved`
  (outcome `unavailable` → `unavailable`).

## 2. Single-owner updates

- Police is the only writer of dispatch transitions; `_transition()` emits one structured
  `report_status_changed` per real change (dedupe key: coarse status + stage + handling + outcome) and appends
  to a bounded timeline (≤ 8, first step kept).
- Linked incidents: transitions reach the phone only through the incident relay (F-07 rule kept). Unlinked phone
  calls: police writes the phone directly. Intake text is owned by the caller's reply (no extra notice).
- `en_route` is card-only. Notices: received/queued, dispatched (incl. replacements), on_scene, each handling
  step, terminal, and same-stage "notes" (one of several units lost, a reinforcement).
- Phone: an identical message still on the banner is not announced again (kills the same-frame triple from
  relay + relay + reply); while put away, a changed police notice goes to `level.show_notice("Police: …")`
  once per 5 s per text.

## 3. Additive APIs (no existing signature changed)

`city_police_assistance.gd`
```gdscript
var revision: int      # bumps on every dispatch-visible change (phone refresh key)
var generation: int    # bumps when restore_state() accepts a checkpoint (session timeline replaced)
func dispatch_view() -> Dictionary
#   {generation, revision, available, reason, minutes, live: [summary], history: [summary], refusals: [refusal]}
func call_status(id_or_ref: String) -> Dictionary   # live, else newest archived summary; {} when unknown
func cancel_ref(ref: String, text := "") -> bool    # linked incident closed elsewhere: stand down cleanly
```
Summary gains: `stage, handling, kind, street, phone, closing, threat, responders {foot, cars},
opened_minutes, updated_minutes, timeline [{stage, handling, outcome, text, minutes}]`.
`report_status_changed` payload gains `stage, handling, street, minutes, responders`.
`get_status()` gains `refusals, revision, generation`; counters gain `transitions, replacements, cancelled_refs`.

`city_incidents.gd`
```gdscript
var revision: int
func reports_for(person_id := "player", limit := 4) -> Array
#   reported or corroborated by person only: reports police still answer first, however old
#   (<= city_police_status MAX_LIVE_CALLS = 3), then the `limit` newest others (r3, final review)
func phone_report_preview(at: Vector3) -> Dictionary
#   exactly what report_from_phone(at) would do now (same selection code):
#   {kind: "incident"|"area_check", incident_id, title, street, state, already_reported, yours}
```
`report_status_changed` payload gains `stage, handling, street`.

`city_police_status.gd` (static): `coarse_status, terminal_stage, record_stage, is_live, label, next_action,
accent, clock_text, responders_text, subject_text, report_action(preview) -> {button, hint},
cards(view, records, limit := 4) -> Array`; constants `MAX_CARDS` (4), `MAX_LIVE_CALLS` (3, r3).

`city_player_phone.gd`: `get_status()` gains `police_cards`, `notices`; `DEFAULT_REPORT_STATUS` const;
`set_report_status(message)` signature unchanged.

## 4. Save / reload semantics (save worker: nothing to change)

- `snapshot_state()` (custody v1), `validate_state()`, `blocks_checkpoint()` unchanged; incidents section stays v1.
- A successful police `restore_state()` additionally clears this session's closed-call history and refusals and
  bumps `generation`, so the phone never shows calls from an abandoned timeline. (World-save rollback also calls
  `restore_state`; it clears the same session-only history — documented limit.)
- After a load the phone rebuilds report cards from the durable incident records; a record restored mid-response
  shows "Response interrupted / result unknown", never "on the way".

## 5. Root integration

None required. `_request_police_help` and `_on_incident_report_status` keep working as they are.
