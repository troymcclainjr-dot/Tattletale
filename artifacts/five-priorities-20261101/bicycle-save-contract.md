# bicycle-save-contract.md — bike-side predicates and persistence hooks for the save worker

Owner: bicycle worker (owns `city_bicycle.gd`, `city_bicycle_crash.gd`, `city_player.gd`).
Consumer: save worker (owns `city_world_save.gd` + the new bicycle persistence helper).

**Status: v1 LANDED in source (not engine-run by me; root runs the engine).** Root asked us to
converge now, so the section 3 hooks are in `godot/scripts/city/city_bicycle.gd` exactly as written
below. They are additive: nothing in section 1 was renamed or removed. Bike-side fixture:
`godot/tests/city_bicycle_save_hooks.gd` (+ `_runner.gd`). Amendments go in `coordination.md`.

---------------------------------------------------------------------------------------------
## 1. Pre-existing state at c77e972 (unchanged; file `godot/scripts/city/city_bicycle.gd`)

Access the bike through `level.bicycle` (CharacterBody3D, collision layer 16). At c77e972 the root
creates it in `pen_lucy_level._ready` **after** `world_save.load_state()`. See 4.1.

| Concept | Where it lives | Meaning |
|---|---|---|
| Mounted | `bicycle.active` (public var) | Rider is on the bike. Also true for the whole crash |
| Seated explorer | `player.is_seated()`; `player.seated_vehicle` | `== bicycle` while riding; `== bicycle._crash` (crash rig) while a crash plays out |
| Crash in progress | `bicycle.is_crashed()` == `bicycle.blocks_checkpoint()` | Ejection/tumble/lying/get-up. World save already refuses save+load on it. **Stays crash-only** |
| Pedal speed | `bicycle.speed` (signed m/s along the frame) | `get_status().speed` (0 while crashed), `speed_kmh` |
| Residual slide | `_slip` (private Vector3) | Recoil/sideways slide after a knock, decays at 6.5 m/s² |
| Measured motion | `bicycle.velocity` | x/z = last tick's displacement / delta; y = hop/fall velocity |
| Grounded / hop | `_grounded`, `_hop_active` (private) → `get_status().grounded / airborne` | |
| Collision response pending | `_wobble` > 0, `_yaw_deflect` ≠ 0 (private) | Post-bump wobble (≤ 0.55 s); a glance still swinging the frame |
| Last impact | `bicycle.last_impact` (`time` in bike clock), `impacts`, `crashes` | scrape < 1.8 ≤ bump < 6.0 ≤ crash (closing m/s) |
| Riderless bike still moving | `_settling` (private) | After an ejection: recoiling/sliding/falling over |
| Bike lying on its side | `_fallen` → `get_status().fallen` | "F · Pick up bicycle" |

Two behaviours any mounted restore must respect (they are why the hooks exist):
* While seated, `player.global_position == bicycle.global_position` and the explorer has collision
  layer/mask 0. A standing-capsule test there (`safe_player_position`) **overlaps the bike hull
  (layer 16)**. Never use it for a mounted pose. `pose_blocker` is authoritative.
* `bicycle.tick()` treats a jump of the seated explorer > 0.75 m from the last seat as an external
  relocation and dismounts there. Moving a mounted explorer with `_put_player` silently dismounts
  them. Mounted restores must go through `restore_pose`, which re-anchors the seat.

## 2. Safety predicate: `save_blocker()` (checked in this order, first failure wins)

Mounted (`active`):
1. crashed → `"recovering from a bicycle crash"` (same text world save already uses)
2. hopping, not grounded, or vertical velocity → `"land the bicycle before saving"`
3. `|speed|`, `|slip|` or planar `|velocity|` > `SAVE_STILL_SPEED` (0.05 m/s) → `"stop the bicycle before saving"`
4. wobble, a pending glance swing, or an impact within the last 0.5 s → `"steady the bicycle before saving"`
5. `pose_blocker(current pose)`: `"no stable ground under the bicycle"` / `"something is pressing against the bicycle"`
6. explorer not seated on this bike → `"bicycle seat state is changing"`

Not mounted: `"your bicycle is still settling"` while a crash slide plays out, else `""`. A fallen bike
at rest is fine; save its `fallen` flag. Not spawned (no parking was found at setup): `""`.
Pause does not block, since state is frozen.

## 3. Hooks (landed, `city_bicycle.gd`)

```gdscript
const SAVE_VERSION := 1
const SAVE_STILL_SPEED := 0.05      # m/s
const SAVE_SUPPORT_REACH := 0.35    # m: saved height vs. sampled wheel support

func save_blocker() -> String                         # section 2
func persistence_state() -> Dictionary
## {"version", "spawned", "mounted", "crashed", "settling", "fallen", "grounded", "airborne",
##  "steady", "speed", "planar_speed", "slip", "position": Vector3, "yaw": float,
##  "parked_position": Vector3, "blocker": String (== save_blocker())}

func pose_blocker(at: Vector3, heading: float, explorer := false) -> String
## "" or a reason. No mutation. Wheel support (11 rays, vehicles/people never support) within
## 0.35 m of at.y, no riser > 0.30 m / steep face under a wheel, and the upright hull clear of
## world/people/cars at the supported height (same 1.5 cm contact allowance riding has). With
## explorer=true a STANDING explorer is also an obstacle (analytic capsule test).
## Reasons: "bicycle unavailable", "invalid bicycle pose", "no stable ground under the bicycle",
##          "something is pressing against the bicycle".

func restore_pose(at: Vector3, heading: float, mounted: bool, fallen := false) -> Dictionary
## -> {"ok": bool, "reason": String, "mounted": bool, "position": Vector3, "yaw": float, "fallen": bool}
## On ok == false NOTHING was changed. Refusals: crash in progress ("recovering from a bicycle
## crash"), any pose_blocker reason (explorer counted when mounted == false), mounted while the
## explorer sits in another vehicle ("leave the vehicle first"), mounted with the phone up
## ("put away the phone before riding"; the phone is never closed for you), not mounted while
## currently ridden with no verified step-off spot ("no clear spot to step off the bicycle").
## Effects: the bike sits at the SUPPORTED height (not the raw saved y). Speed, slip, hop,
## wobble, deflect, settling, spin and trail are cleared.
##  mounted: seats the explorer like enter_bicycle() (combat actions cancelled, mounted signal,
##           chase distance 4.8) but without the walk-up distance or line-of-sight gate. If they
##           are already riding, it moves bike + explorer together. Either way the seat is
##           re-anchored, so tick() does not dismount, and player.reset_vehicle_view(heading)
##           starts the chase view behind the bike (no swing from the pre-load view).
##  not mounted: if ridden, the explorer first steps off to a verified spot beside the CURRENT
##           pose that also stays clear of the NEW pose (dismounted signal). Then the bike moves.
##           fallen=true lays it on its side ("F · Pick up bicycle").

func park_beside_explorer() -> Dictionary
## -> {"ok", "reason", "position", "yaw"}. Same bounded search setup() uses (2.1–5 m, ground,
## clear hull) around where the explorer stands now. Refuses while ridden/crashed or when nothing
## nearby is clear; then nothing changes. Use it for checkpoints without a usable bike section,
## or when the saved parked pose fails pose_blocker.
```
`city_player.gd` also gained `reset_vehicle_view(heading)` (no-op unless seated). restore_pose
calls it. The helper does not need to.

Suggested section (the helper owns it): `{"version": 1, "mounted": bool, "position": [x, y, z],
"yaw": float, "fallen": bool}` from `persistence_state()` when `save_blocker() == ""`.
Restore: `validate` (schema) → `pose_blocker(at, yaw, not mounted)` in preflight → `restore_pose`
→ on a later provider failure, roll back with `restore_pose(pre.position, pre.yaw, pre.mounted,
pre.fallen)` using the `persistence_state()` captured before the load (refuse loads while
`save_blocker() != ""`, so that pre-load state is always restorable).

## 4. Integration notes for save worker / root

1. **Startup ordering (root):** root said it will create the bike before `load_state()` and stop
   setup from overriding a restored pose. Then (a) bike section present → `restore_pose`; (b) absent
   (legacy v1–v4), or its pose fails → `park_beside_explorer()` after the explorer is placed. Setup's
   own parking was beside the *pre-load* spawn, so the bike would otherwise be left there.
   (c) mounted section → do NOT `_place_player` the explorer to the seat with the standing test; call
   `restore_pose(..., true)` (it puts the explorer on the bike). If it refuses, place the explorer
   with your normal standing rules and `park_beside_explorer()`. Never leave them inside the bike.
2. Order inside a load: vehicles are restored before the explorer today. A restored parked car can
   occupy a saved bike pose, so re-check with `pose_blocker` after vehicles are applied (restore_pose
   does this itself and refuses cleanly).
3. Keep refusing save/load during `is_crashed()`. If loads stay refused while seated, the pre-load bike
   state is always "parked". If you allow loads over a stationary rider, restore_pose handles moving a
   mounted bike, and stepping a rider off for a parked section.
4. Never call `player.leave_vehicle` / `_put_player` on a seated explorer. Use `restore_pose(..., false)`
   or the existing `bicycle.recovery_exit_at(at, heading)`.
5. **Existing test to update when mounted saves ship:** `godot/tests/city_nonviolent_session_runner.gd:131`
   asserts `not provider.can_checkpoint()` and that the blocker contains "bicycle" right after an ordinary
   F mount, while the bike is still stationary. Under the new rules a stationary mounted bike IS saveable,
   so that assertion should move to while the bike is moving (the reason then is "stop the bicycle before
   saving", which still contains "bicycle"). It is shared/root-owned; I did not edit it.
