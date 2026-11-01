# save-contract.md — mounted-bicycle checkpoints and the queued save request

Owner: save worker (priority 5). Status: **r2 — converged** with `bicycle-save-contract.md` v1 and
the "Root integration decision" in `coordination.md`. Implementation is in source (section 0).
Nothing here has been engine-run by me; root runs every test.

## 0. Files (save worker edits only these)

- `godot/scripts/city/city_world_save.gd` (existing owner file)
- NEW `godot/scripts/city/city_bicycle_checkpoint.gd` — save-side helper: section schema, standing
  spot, resident reservation, restore preflight/verification/standing fallback, walking re-park.
- NEW tests `godot/tests/city_mounted_save_smoke.gd` + `_runner.gd` (provider-contract doubles, no
  city) and `godot/tests/city_mounted_save_city.gd` + `_runner.gd` (actual city + actual bicycle).

Not edited: `city_bicycle.gd`, `city_bicycle_crash.gd`, `city_player.gd`, `pen_lucy_level.gd`,
police/incidents/phone, settings.

## 1. Schema: no container bump, one optional nested section

Container `version` stays **4** (3 without the driving API). Walking checkpoints are byte-for-byte
the existing layout. A safe rider adds:

```
"bicycle": {"version": 1, "mounted": true, "position": [x, y, z], "yaw": float}
```

- `position`/`yaw`: the bicycle origin (foot height) and heading at the save.
- `player.position` is the **verified standing spot beside the bicycle**, never the seat: the
  provider's own `safe_player_position` (ground, capsule vs layers 2|8|16 — the frame itself is
  layer 16 — residents, bounds, closed shops), >= 0.30 m outside the 0.70 x 2.10 m frame footprint,
  on the bicycle's side of walls (ray 1|2). Candidates: 1.0/1.4 m either side (the bicycle's own
  unforced dismount offsets), then 1.6 m behind/ahead. None => blocked "no room to step off the
  bicycle here".
- Validation (pure): section version integer 1, `mounted == true`, finite yaw, in-bounds position,
  container version >= 3; standing spot must not overlap the footprint ("saved explorer overlaps the
  bicycle") and must be within 2.6 m planar / 0.65 m vertical ("saved explorer is not beside the
  bicycle"). Any failure is corruption (`.bak` recovers). An integer section version > 1 is
  `unsupported version` (slot protected, no fallback, no writes) — same rule as every nested section.
- Why no bump (precedent: `incidents`, `police_assistance`): existing assertions require walking
  snapshots to equal `VERSION` and `VERSION + 1` to be a protected container; an older build reading
  a mounted file ignores the section and stands the explorer at the checked spot, losing only the
  seat (no durable data). The parked bicycle pose is deliberately not persisted.

## 2. Bicycle hooks consumed (bicycle worker, bicycle-save-contract.md section 3)

`save_blocker()`, `persistence_state()`, `pose_blocker(position, heading)`,
`restore_pose(position, heading, mounted, fallen := false)`; optional `park_beside_explorer()`;
constant `SAVE_STILL_SPEED`. Present together => mounted checkpoints enabled
(`get_status().mounted_checkpoints`). Absent => today's behaviour: "step off your bicycle before
saving"; a mounted file restores standing with an explicit note.

`persistence_state()` keys read: `blocker` (used as the verdict, so one pose check per evaluation;
`save_blocker()` is called only if it is absent), `mounted, crashed, grounded, airborne, speed,
planar_speed, position (Vector3), yaw`, optional `slip, steady`. The save re-checks them after the
verdict is "" (defence in depth: a moving/sliding/unsteady/airborne/crashed frame is never written
even if a verdict regresses) and after restore.

Requests to the bicycle worker (please confirm in coordination.md):
1. `restore_pose(..., true)` re-anchors the seat so `tick()` does not treat the restore as an external
   relocation, and leaves `persistence_state()` reporting mounted/grounded/still at the pose.
2. `park_beside_explorer()` returns `bool` or `{ok}` (void also accepted) and, when no spot is found,
   leaves a visible bicycle where it is rather than hiding it.
3. Parked `save_blocker()` is "" unless the riderless bicycle is still settling (the save refuses a
   load only then: "wait for your bicycle to come to rest before loading a checkpoint").

## 3. Save rules

`checkpoint_blocker()` order: world ready, routes, impact recovery, crash (`blocks_checkpoint`),
**seat** (driving active => "leave the vehicle first"; no hooks => legacy text; seat not this bicycle
=> "bicycle seat state is changing"; else the bicycle's `save_blocker()` reason, then the facts
re-check: "recovering from a bicycle crash" / "land the bicycle before saving" / "stop the bicycle
before saving"), police, incident, law, fight (unchanged), then for a rider: residents within the
footprint ("something is pressing against the bicycle") and the standing spot; for a walker
"no stable ground". The player is never dismounted to make a save.

## 4. Load order (all-or-nothing preserved)

Refusals before anything changes: police response, impact/crash recovery, seated, driving,
**riderless bicycle still settling**. Then unchanged read/validate/preflight/apply ... incidents ->
walk -> **bicycle (last)**. Being last, no provider can refuse after a remount, so it never needs to be
unwound and it sees restored residents, cars and incidents.

- Mounted section: save-side preflight (bounds, closed shop, resident reservation) + `pose_blocker`
  -> `restore_pose(pos, yaw, true)` -> verification from `persistence_state()` and the explorer
  (seated on this bicycle, still/grounded, planar <= 0.02 m, rise <= 0.06 m, yaw <= 0.01 rad).
  Refused => explorer stays at the checked standing spot, bicycle re-parked beside, note, and
  `player_fallback = true` (root's existing startup notice shows it). Unverified => undone through
  `recovery_exit_at(standing spot)` (never by moving a seated explorer) then the same fallback.
- No section (walking, v1-v4 legacy, 20-resident legacy): `park_beside_explorer()`.
- `load_state()` result / `last_load` add `bicycle: {state, reason[, parked]}` with state
  `mounted | standing | parked | not parked | unchanged | unverified`.

## 5. Queued request (in memory only)

```gdscript
signal pending_save_resolved(result: Dictionary)   # {source, state, message, error, retrying}
func request_save(source := "manual") -> Dictionary # {state: saved|queued|failed|unavailable, reason, message, error, source}
func cancel_pending_save(reason := "cancelled") -> bool
## get_status().pending: {active, source, waiting_for, attempts, retry_in, message}
```

- Safe now => written now. Else ONE request waits; repeats coalesce (manual upgrades autosave) and
  never add writes or disk reads. Autosave (30 s) uses the same queue, so a blocked autosave completes
  at the next safe moment.
- Polls at most every 0.25 s of unpaused play; a blocked poll is `checkpoint_blocker()` only (no file
  access). Write failure keeps the request and retries after 5 s, 10 s, 20 s, then every 30 s.
  Write-blocked/disabled drops it with the reason. Any successful write (manual, autosave, exit,
  recovery) satisfies it and restarts the autosave interval.
- Discarded by `setup()`, a successful `load_state()`, leaving the tree; never written to disk or
  settings, so a restart never replays it. Signal fires only for requests that actually waited
  (`saved`, `cancelled`, `unavailable`, `discarded`, first polled `failed`).
- `save_state()` stays the immediate, non-queuing attempt (exit path, recovery, fixtures).

## 6. Root hooks

1. Startup (decided): `bicycle.setup(self)` before `world_save.load_state()`; do not re-place it after.
2. `save_progress()`: `return str(world_save.request_save("manual").message)` (keep the
   unavailable-session early return).
3. `world_save.pending_save_resolved.connect(func(r): if r.source == "manual": show_notice(r.message))`.
4. `_request_exit` unchanged (direct `save_state()`, prompt on failure). Optional: mention
   `get_status().pending.message` in the dialog; call `cancel_pending_save("leaving")` before
   `_finish_exit` when leaving without saving.
5. Optional: settings `refresh_checkpoint_status()` can show `get_status().pending.message`.
