# Tattletale independent audit (read-only), 2026-10-30

I didn't edit, run or launch anything, and I didn't run any tests. Graphify only covers the Python, JS and Markdown parts of the project, so after one orientation query I read the GDScript directly. Every line number below is what I saw in the current worktree. Files that other agents are changing right now (vehicle collision, courts, jump) are reported as "observed now, recheck".

---

## 1. The four current requests (kept separate from the main audit)

### 1a. Tighter vehicle collisions (other agents are on this)
The physical collision shells are already close to the models: about 4.5 cm extra on each side and 3 cm at each end (`city_car_collision.gd:19-23`). The visible looseness comes from the driving logic:

- **Stop distance before obstacles:** cars stop 1.5 m short of anything their lookahead finds, plus a 0.06 m stop threshold (`city_vehicle.gd:371-376, 382`). Cautious drivers and police include the player in that lookahead (`:374-375`).
- **Following gap:** the gap to the car ahead is `along - BODY_SIZE.z - 1.8` (`city_traffic.gd:216`). It uses one fleet size (4.70 m long, 2.12 m wide, `city_vehicle.gd:8`) for every model, so compacts (4.38 m) leave about 2.1 m.
- **Road check:** the on-road corner test also uses the 2.12 × 4.70 fleet size for every model (`city_vehicle.gd:209-212`).
- **Player-contact test reports contact early near corners.** `_player_contact_fraction` (`city_vehicle.gd:91-129`) checks the capsule against each flat face of the car's shell, pushed out by the capsule's radius. Near edges and corners that shape is bigger than the true rounded one. With r = 0.30 m, contact can be reported up to about 0.12 m early at edges and 0.22 m at corners. A player grazing a bumper corner or hood edge can stop a car, or trigger the stumble, without touching it.
  - **Fix:** use the face test only as a quick first check, then confirm with a real capsule sweep against the car's parts.
  - **Validation:** place the capsule diagonally off a bumper corner with a 0.05–0.20 m gap; expect no contact.
- **Likely (needs a runtime check):** cars move by setting `global_transform` directly (`city_vehicle.gd:439`). As I understand Godot's physics servers, a moved kinematic body's new position only takes effect at the next physics step. So other cars and the player may see a car one tick (~0.15 m at 9 m/s) behind where it is. Converging bodies could then overlap slightly. Check it with an overlap counter that includes crossing and opposite directions.

### 1b. Higher car-roof jump (parent owns this)
- **Current height:** `JUMP_SPEED 10.4` with `GRAVITY 22` gives about 2.37 m at 60 Hz (`city_player.gd:41-43`).
- **Roof heights:** compact 1.39, sedan 1.48, minivan 1.72, police light bar top 2.06 (`city_car_models.gd:17-21`, `city_car_collision.gd:44-47`).
- **Two tests hard-code the apex at 2.25–2.50 m** and must be retuned with the change: `city_jump_smoke_runner.gd:73` and `city_vehicle_jump_smoke_runner.gd:85`.
- **Confirmed: jumping off a moving car loses its speed.** The script resets horizontal velocity every frame (`city_player.gd:288-289, 317-318`). Whatever push the engine gives when leaving a moving surface is gone one frame later, so the player drops behind the car.
- **Not tested:** landing on a car that is already moving. The test boards a stopped car (`city_vehicle_jump_smoke_runner.gd:142-155`).
- **Likely edge case:** cars update before the player (`pen_lucy_level.gd:742-750`), and "is the player riding" uses last frame's contacts (`city_player.gd:226-233`). If the capsule is within the 1 cm query margin on the landing tick, the car may register a hit and stop with "Player impact".
- **Things a higher jump opens up:**
  - Porch and low roofs become reachable.
  - Hoop backboards can be jumped through (see 1d).
  - `_safe_position` accepts any floor (`pen_lucy_level.gd:732-733`).
  - The interaction height tolerance is 1.5 m (`city_missions.gd:358`).

### 1c. Smoother traffic turns
- **Turn shape:** the car's centre follows the path and its heading is set to each step's direction (`city_vehicle.gd:388-398`). So the car pivots about its middle and the rear swings outward. There's no sideways sliding (the precision test checks this), but it doesn't look like a car turning.
  - **Fix:** steer from the rear axle toward a point ahead (bicycle model), keeping the existing sweep checks.
- **Junction speed:** every reserved junction crossing is capped at 4.2 m/s (`city_vehicle.gd:360-361`), whether it's a straight-through on green or a tight U-turn.
  - **Fix:** precompute each connector's tightest curve and cap speed from that.
- **Speed changes:** acceleration 2.4 and braking 4.0 m/s² are applied as hard steps with no smoothing (`city_vehicle.gd:387`).
- **Confirmed by arithmetic: aggressive cars snap-stop at stop lines.**
  - Junction control only starts within 22 m (`city_traffic.gd:254-255`).
  - Aggressive cruise speed is 12–15 m/s (`city_vehicle.gd:63-65`).
  - Stopping from 15 m/s at 4 m/s² takes about 28 m.
  - The step is then clamped to the remaining distance (`city_vehicle.gd:388`), so the car reaches the line at about 7 m/s and stops instantly.
  - Yellow means stop at any distance (`city_traffic.gd:259-261`; signal timing at `city_street_signals.gd:69-73`).
  - **Fix:** look ahead at least the braking distance (v²/2a) plus a margin, and let cars that can't stop comfortably go through on yellow.
- **Likely queue wobble:** the gap to the car ahead is recomputed every 0.1 s (`city_traffic.gd:350-352`). Between updates it only shrinks by the follower's own travel (`city_vehicle.gd:445`), never credited for the leader moving. Followers keep slightly underestimating the gap, so they surge and brake at about 10 Hz.
- **Intentional but limiting:** one car at a time per junction zone, even on green or for opposing straights (`city_traffic.gd:274-276, 292`). This causes stop-go queues.
- **Minor:** rounded lane corners (`city_traffic_network.gd:161-184`) join the junction curves (`:212-236`) without a sudden change of direction, but the turn tightness still jumps, so turning speed changes abruptly at each join.

### 1d. Courts in all large greens (other agents on this; the generator is mid-change)
- **Generator, as of now:** greens of 250 m² or more, one court per green, raised slabs up to 0.80 m with solid side walls (`park_courts.py:14, 124-178, 212-262`). The game already supports any number of courts and the new side walls (`city_park_courts.gd:57-69`).
- **Confirmed: backboard, arm and rim have no collision.**
  - Only a 3.75 m pole cylinder exists (`city_park_courts.gd:76-88`).
  - The data puts the rim about 2.3 m out from the pole and about 3.05 m above its base.
  - The player's head reaches about 4.1 m at the current jump, so they can pass through the backboard. That breaks the house rule on solid props, and gets worse with a higher jump.
  - **Fix:** add a box collider on layer 2 for the backboard and arm.
- **Brittle test:** `city_courts_smoke_runner.gd:65` hard-codes 160 park residents. More courts will reserve more park space and break it.
- **Scaling:**
  - `is_clear` and `is_court` scan every court for every population candidate (`city_park_courts.gd:113-131`).
  - Street placement checks only the hoops, not the court surface (`city_npcs.gd:169`). Add `is_court` there if courts reach the sidewalk band.

---

## 2. Main audit findings

### Confirmed code defects
1. **Walkers move backwards at their turnaround (house rule #1).**
   - **Evidence:** `city_crowd.gd:362-365` reverses direction and moves at once, while the facing only eases round (`:391-392`). For about 0.1–0.2 s the walker moves opposite to the way it faces.
   - **Fix:** turn in place first, as `city_npc_actor.gd:113-117` already does.
   - **Validation:** for every walker update, motion must point the way the walker faces (dot product above 0.99).
2. **Vegetation detail switches cause stutters.**
   - **Evidence:** when a 48 m cell switches near/far detail, its mesh is rebuilt on the main thread. The normals are fixed one vertex at a time in GDScript (`city_vegetation.gd:121-160`). Only one detail level is cached per cell (`:155-158`), so walking back and forth rebuilds it every time. Turning tree collision on or off rebuilds the whole cell (`:99-101`).
   - **Fix:** keep both detail meshes, use the yard-style disk cache with background loading, or switch to per-template MultiMesh.
3. **Disk caches grow and can go stale.**
   - **Growth:** stream and yard cache folders are named by a signature and never cleaned up (`city_streaming.gd:42`, `city_yard_details.gd:130-131`). Every change leaves another full copy under user://.
   - **Stale risk:** the render and stream cache signatures use the source GLB's size and modified time, plus script and shader modified times (`city_render_optimizer.gd:110-115`, `city_streaming.gd:40-41`). An exported build won't contain the source .glb, so the signature falls back to triangle counts. That would serve stale geometry after an update that keeps the same counts.
   - There's no `export_presets.cfg` yet, so this is a packaging risk, not a current bug.
   - **Fix:** hash the data the way the yard cache already does, and delete old sibling folders.
4. **Low graphics quality loses its building draw-distance limit.** The renderer sets 520 m for Low (`city_render_optimizer.gd:236`), then hands quality to streaming (`:252-253`), which resets it to unlimited (`city_streaming.gd:116-118`). Streaming's own unload distance mostly hides this. Pick one owner.
5. **Crowd draw distance never updates.** It's set once when created (`city_crowd.gd:291, 515`), but later changes from the quality setting don't reach existing crowd meshes (`:482`).
6. **City settings leak into the original game.** Frame cap, render scale, vsync and audio levels (`city_settings.gd:82-95`) aren't restored when leaving the city (`pen_lucy_level.gd:224-228`). The settings file is also rewritten on every slider tick (`city_settings.gd:109-116, 197-199`).

### Likely issues (need a runtime repro)
1. **Cars can stall forever.**
   - **Evidence:** these all stop with no timeout: "Waiting for nearby clearance" (`city_vehicle.gd:285-287, 332-334`), "Occupied vehicle clearance" (`:367-369`), "Obstacle ahead" (`:426-428`), "Turning clearance occupied" (`:433-437`). The recycle path only applies to parked cars (`:477`).
   - **Why it matters:** a stopped car that holds a junction reservation (`city_traffic.gd:248-252`) blocks the whole junction.
   - **Triggers:**
     - The player standing in a turn path.
     - Two distant cars overlapping. Distant cars have no physics, and the car-ahead search is only 1.85 m wide, so it can miss on curves (`city_traffic.gd:214`). When those cars come into range, both stay blocked.
   - **Fix:** a stuck timer. Recycle the car out of view using the existing `try_recycle` checks, and release the reservation if the car hasn't yet entered the junction.
2. **Building chunks may hitch on arrival.** They load in the background, but are created and uploaded on the main thread (`city_streaming.gd:176-184`). On first run every chunk is also saved to disk during setup (`:56-60`). The 57 m benchmark walk never crosses the 240 m load radius.
3. **Camera pumping near traffic.** The camera's collision check includes moving cars (`city_player.gd:584`). It pulls in instantly and eases back out (`:592-595`), and can hide the character (`:599`).
4. **Launcher.** `Play Pen Lucy.cmd:5-7` prefers any Godot on PATH over the known 4.7.2 install, with no version check. It runs a headless editor import on every launch (`:17`) without the shared lock that `godot_run.py:27` uses, so it can collide with agent imports.
5. **Loading.** The whole GLB loads synchronously (`pen_lucy_level.gd:96`), and collision is built for every mesh (`:293-308`). The loading screen freezes; slow disks could show "Not responding".

### Intentional tradeoffs (don't "fix" by accident)
- Aggressive drivers ignore the player when looking ahead (`city_vehicle.gd:83-89`), so they hit and stumble the player.
- Distant cars run without physics.
- Terrain and building collision always stay loaded.
- Mission route lines follow road centrelines (`city_mission_navigation.gd:62-68`), which leads players along traffic lanes; offset them to sidewalks later.
- Cases aren't saved between visits.
- Courts are scenery only.
- Space is mapped to the original game's binoculars in `project.godot:77-81`, but the city ignores that action.

### Missing future content
- Pedestrians crossing streets and signals for them (walkers stay on 6 m sidewalk strips, `city_crowd.gd:330-352`).
- Unique residents, as documented.
- Save/load.
- A smarter junction reservation scheme that lets non-conflicting movements share a junction.

### Low priority
- Full map redraws at 30 Hz or more even when idle (`city_minimap.gd:53-58`).
- `get_status()` builds the case offers twice per call, and the UI calls it every 0.1 s (`city_missions.gd:206-221`, `pen_lucy_level.gd:752-788`).
- A failed dialogue choice silently does nothing (`city_dialogue_state.gd:69-77`).
- Falling (not jumping) keeps going behind menus (`city_player.gd:248-254`).

---

## 3. Good safeguards to keep
- **Player movement:** full-capsule step sweeps, a check that the raised position is empty, and a verified curb top (`city_player.gd:416-551`). Zero wall-slide dead zone (`:131-133`).
- **Car movement:** moves are committed only after every check passes. Turns are checked at sampled angles. The player is only treated as hit if they're reached before any other solid (`city_vehicle.gd:399-437`). A car isn't switched to physics while it overlaps something (`:278-291`).
- **Traffic:**
  - A follower can't reserve a junction from behind a waiting leader (`city_traffic.gd:267-273`).
  - Cars wait until the outgoing lane is clear (`:286-288`).
  - Old route points are trimmed (`:224-228`).
  - Cars are placed before joining the scene, so none appear briefly at the origin (`:152-155`).
- **Teardown:** collision is turned off before objects are freed (`city_crowd.gd:489`, `city_missions.gd:186-189`, `city_yard_details.gd:238-240`). Pending background loads are finished on exit.
- **Dialogue:** choice actions are re-checked before they count, and the world pauses during dialogue (`city_missions.gd:237-247`, `pen_lucy_level.gd:509-511`).
- **Navigation:** never draws a guessed line through buildings.
- **Caches and rendering:** the yard cache is keyed by a hash of its data and script (`city_yard_details.gd:130`). Building batching checks triangle counts and falls back if they differ (`city_render_optimizer.gd:57-67`).
- **Scene changes:** the original game's state is cleared on every transition (`g.gd:232-294`).

---

## 4. How well the tests cover this
- **Strong:** the player's step/curb/jump fixtures, vehicle impact and recovery, junction-curve kinematics on a synthetic road, dialogue state, navigation, and yard/court grounding.
- **Blind spots:**
  - Overlap checks only cover cars facing the same way (`city_traffic_network_smoke_runner.gd:112, 268`). Crossing and turning conflicts aren't checked.
  - Nothing asserts that cars obey red lights, stop signs, or how they behave on yellow.
  - Long-run gridlock: runs are only 45 s near and 60 s distant, with loose thresholds (3 nearby cars, 75% distant).
  - Junctions with physics at scale: the accelerated run deliberately turns physics off (`:77-78`).
  - Stuck-car recovery isn't tested.
  - Smooth braking: the precision test fixes speed at 4.2 and disables junction control (`city_vehicle_precision_smoke_runner.gd:17-18, 112`).
  - Near-corner contact gaps, landing on moving cars, momentum on jump-off, walker facing, and backboard collision have no tests.
  - Streaming and vegetation stutter over a long route: the only benchmark is a 57 m background walk.
  - Export/packaging has no tests.
- **Hard-coded values that will clash with the current work:**
  - Jump apex 2.25–2.50 m (two tests).
  - Exactly 160 park residents.
  - Exactly 90 cars.
  - 12–18 aggressive drivers.
- **Side effect:** the traffic tests write report files into `artifacts/pen-lucy-dense/traffic` (`:138-142, 288-292`).

---

## 5. Ranked next priorities
1. Stuck-car timer and reservation release (§2 likely #1).
2. Stop-line and yellow braking, curve-based junction speeds, rear-axle steering (§1c).
3. Exact capsule confirmation after the face test, per-model gaps, smaller stop distance (§1a).
4. Backboard and arm collider before the jump is raised; retune both jump tests together; keep platform speed on jump-off (§1b, §1d).
5. Walkers turn in place before reversing (§2 confirmed #1).
6. Long-route benchmark tracking worst and 99th-percentile frames per streaming or detail switch; fix vegetation rebuilds (§2 confirmed #2, likely #2).
7. Add tests: crossing-direction overlaps, signal compliance, long-run gridlock, landing on a moving car, near-corner gaps.
8. Before packaging: export-safe cache signatures and cleanup; launcher version check and lock (§2 confirmed #3, likely #4).
9. Remaining low items: quality/settings inconsistencies, camera pumping, map redraw.

---

## 6. Scope and limitations
- **Read in full:**
  - Player: `city_player.gd`.
  - Vehicles and traffic: `city_vehicle.gd`, `city_car_collision.gd`, `city_traffic.gd`, `city_traffic_network.gd`, `city_street_signals.gd`, `city_parked_cars.gd`.
  - Level, cases and dialogue: `pen_lucy_level.gd`, `city_missions.gd`, `city_mission_navigation.gd`, `city_dialogue.gd`, `city_dialogue_state.gd`.
  - People: `city_npcs.gd`, `city_npc_actor.gd`, `city_crowd.gd`.
  - World detail, streaming and UI: `city_park_courts.gd`, `city_streaming.gd`, `city_render_optimizer.gd`, `city_vegetation.gd`, `city_yard_details.gd`, `city_settings.gd`, `city_minimap.gd`.
  - Config, launch and generator: `project.godot`, `godot_run.py`, `Play Pen Lucy.cmd`, `park_courts.py` (lines 1–262).
- **Partially read:**
  - `g.gd` (scene changes), `city_car_models.gd` (sizes).
  - The courts and level JSON, via targeted searches.
- **Tests:** read the vehicle precision, vehicle jump and traffic network runners in full. Only scanned the checks in the jump, impact and courts runners.
- **Docs:** read the streets, content and Rose Hill acceptance notes.
- **Lightly checked:** in the original Godot game, only the crime tables and scene-change reset. In the web prototype, only script load order and that the crime tables match.
- **Not examined:** `city_dressing`, `city_neighborhood_details`, `city_weathering`/`city_windows`, `city_street_surfaces`, `city_map_overlay`/`city_radar`, `city_theme`, most original Godot gameplay scripts, the Blender `process.py`/`runtime.py`/`kits.py`/`yards.py`, the shaders, and most other test runners.
- **Not run:** no tests, benchmarks or game launches. The kinematic-body timing point (§1a) rests on my understanding of the engine and needs a runtime check.

I couldn't save this as a plan file: no write or plan-exit tool was available in this session, so the full report is in this message.