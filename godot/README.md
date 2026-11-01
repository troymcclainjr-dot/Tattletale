# Tattletale 2-Pack: Godot port

A Godot 4.7 port of the web prototype in the repo root. The web version stays playable and
available. Open this folder (`godot/`) in Godot 4.7.2 and press F5.

## Pen Lucy neighborhood

Double-click **Play Pen Lucy** in the repository root on the configured Windows machine to
enter the Baltimore neighborhood with 2-Pack directly, in a maximized window. The launcher
uses its own profile under `.work/play-profile`. In the editor, run
`scenes/city/pen_lucy.tscn` directly, or choose **Explore Pen Lucy** from the F5 title screen.
Choose **Start snitchin'** there for the original two-stage game.

Current Pen Lucy centers on helping neighbors, recording evidence and truthful reports.
Player attacks, car driving and alignment scoring are disabled. The original two-stage game
and web prototype retain their own historical controls. Current evidence and release gates:
[pacifist acceptance](../artifacts/pacifist-foundation/ACCEPTANCE.md).

- **WASD** walks; **Shift** runs. Steering turns the body and travel together without
  stopping at ordinary corners; tight reversals slow into a forward turn.
  Walk onto porch stairs naturally. Oblique wall contact preserves movement along the wall,
  while head-on walls, posts, low ceilings, people and vehicles remain solid.
- **Mouse** looks around; **left/right arrows** turn the camera. Play captures the cursor
  automatically. Click in active play to capture it again if it has been released.
- Hold **right mouse** to orbit the camera while preserving your movement direction.
  Releasing it keeps the current movement bearing until you start a fresh movement gesture.
  After a short manual-look grace period, sustained movement gently brings the chase view
  behind the character without redirecting held movement. Idle views and held orbit never
  recenter. The camera sweeps a small volume around obstacles and eases back out afterward.
- **V** switches between first-person and third-person views.
- **Space** jumps during exploration. Running retains forward momentum, ceilings remain
  solid, and a short input buffer/coyote window makes takeoff and landing forgiving.
  The roughly 2.37 m jump clears vehicle roofs; model-specific body and cabin collision
  lets you land on the visible surface. Moving roofs carry a standing passenger in an idle pose.
  There is no double jump. Menus freeze a jump; dialogue keeps Space as Confirm.
- **E** talks to a case contact, examines evidence or checks in at a gold walk marker.
  Conversations show speaker text and replies. **E / Enter / Space** continues, **↑ / ↓**
  selects a reply, mouse clicks choose, and **Esc** leaves. Opening or closing text does not
  advance a case; an explicit reply confirms the action.
- **M** opens or closes the map. Use the mouse wheel or **+ / −** to zoom and drag to pan.
  **Whole neighborhood** fits the map; **Find me** centers your position.
  Civic buildings and local businesses use place symbols and a legend; hover or select a
  symbol to see its name, rather than keeping every building name over the map.
  The precinct, firehouse, courthouse and hospital are built exterior architecture.
  Accepted cases show a yellow destination ring and street route on both maps.
  Guidance updates for the current case step and clears when it ends or is cancelled.
- **P** opens the phone: Contacts, Camera, Photos, Cases and Police. **1–5** selects
  those apps; **LMB / Enter** takes a photo in Camera and the wheel zooms. Photos
  stay in the game's gallery (48-photo capacity), with viewing and deletion in Photos.
  In **Police**, **Enter** reports a witnessed incident or asks officers to check the area.
  Unknown or unwitnessed incidents are refused; a report is not proof of an offender's guilt.
  Real patrols or cruisers investigate; infractions can receive a warning, while theft or
  violence can lead to custody. An actively
  threatening armed suspect can be shot. Officers check their firing line for
  bystanders and stop firing when the threat ends. This never awards a player kill.
  **F5** saves progress while the phone is open. **P** puts it away;
  **Esc / Backspace** backs out one page. The phone leaves the world running.
- **F** mounts the bicycle parked beside you, or dismounts after braking.
  **W** pedals, **S** brakes then reverses, **A/D** steers independently of the camera.
  **Space** hops; **Shift** pedals harder. Parked bicycles appear on the map.
  Glancing impacts can slide or recoil; hard impacts can eject the rider into a bounded
  collision-tested tumble and recovery. Wait to stand safely before riding or saving again.
  Pedestrian contacts can cause nonlethal stumbles or knockdowns, followed by fists-only
  retaliation or flight. These contacts do not award player offense, money or alignment.
  Put the phone away before mounting; riding and crash recovery block phone use.
- Every basketball court has a ball: **E** picks up/drops it, **hold/release LMB**
  charges/throws a shot, and **R** returns a held ball. Made baskets are counted.
  This is a shooting foundation, not a complete basketball match.

Player attacks, weapon selection, ammunition sales and car boarding are disabled
by `city_play_mode.gd`; their backend code and compatible saved inventory remain.
Snitch/Gangsta values are preserved but frozen, hidden and removed from access and
price gates. Currency, relationships, errands and nonviolent story choices remain.
Completed police custody is included in checkpoints; unsafe active confrontations, riding
and crash recovery defer saving. Settings explains any checkpoint blocker. Cases cannot
converse with detained contacts. Camera photos are
stored separately inside the game's phone gallery, not exported to a screenshot folder.
- **Esc** opens Settings or resumes play. Settings also offers **Save progress**, **Cases**,
  **Credits**, **Return to starting corner**
  and **Main menu**, which returns to the original game's title screen.

The map and Settings pause play and release the cursor. Switching to another application
also pauses; returning to the game waits for an explicit **Resume** or **Esc**. Resuming
captures the cursor again. These controls apply to Pen Lucy; the web and original-block
controls are unchanged.

Settings has three tabs, with changes applied immediately and saved in the current user's
`user://pen_lucy_settings.cfg`:

- **Video:** Windowed, Maximized or Fullscreen; Low, Balanced or High quality; vertical sync,
  frame limit, render scale, camera field of view, and Off/Simple/Volumetric clouds.
- **Audio:** master, music and sound-effect volume.
- **Controls:** mouse sensitivity, inverted vertical look and the keyboard reference.

The default is a maximized window. The top left shows FPS; the right-hand ledger shows the street
name, current objective and nearby interaction prompt. A small circular radar rotates with
the camera; the full **M** map remains north-up and supports zooming and panning.
Loading welcomes you to Baltimore. Settings use a black background with light text and
shorter half-width sliders on every tab.

The introductory route follows Old York Road from Wyanoke Avenue north through Dumbarton,
Rose Hill Terrace, and Cator Avenue. The north-up map uses the same street coordinates as the
model, showing street names, walk stops, case contacts, the current target and your heading.
Terrain, curbs, buildings, trees, and substantial street furniture have physical collision.
Small decorative trash does not block movement. Street signs use real street names; the
added porch lights, street lamps, traffic signals, hydrants and bins are interpretive
set dressing rather than a photographic survey of individual fixtures. Signals at
Old York and Wyanoke cycle through their phases, and traffic respects the stop lines.

Residents occupy raised porches, sit in chairs, gather in conversation circles, walk along
sidewalks and use parks throughout the mapped neighborhood. Their feet are checked against
actual deck or terrain collision, with walking-route and porch-stair corridors reserved.
No NPC has a persistent name above their head; contacts still speak during interactions.
Foot patrols join the walkers. Runtime checks confirm 1,200 ambient residents: 840 along
streets, 200 on porches and 160 in parks. The street population includes 128 batched walkers;
individual case actors and six validated foot-patrol officers are additional.

Traffic follows connected directed lanes across streets, yielding through reserved junctions,
obeying signals and stop signs, and braking for nearby obstacles. Runtime checks confirm
90 moving cars across 16 streets, including four police vehicles, alongside 216 street-parked cars.
Seventeen drivers are aggressive and travel at 12–15 m/s; cautious drivers and police retain
8–10.5 m/s cruising speeds. Aggressive drivers may hit an explorer who enters their lane.
Swept collision stops the car at contact and applies a short collision-safe player stumble;
walls, other vehicles and people remain solid. Menus pause these effects.
Parked and moving cars use shared legacy sedan/compact/minivan prototypes plus six catalog silhouettes: hatchback, midsize sedan, long sedan, pickup, cargo van and compact SUV.
Parked and moving cars share fitted lower-body and tapered-cabin collision shapes.
Traffic consumes its full travel distance through rounded lane and junction samples,
and keeps intersections reserved until the rear bumper clears the exit.
Settings and the map pause neighbors, traffic and case interactions.

The original game's Bungee headings, Barlow Condensed body text, Courier Prime metadata,
paper panels and red case-file accents are shared by city UI. Licensed fonts are bundled
under `assets/fonts/`, with OFL notices and source hashes. Six ambient conversation graphs
live in `assets/data/pen_lucy_dialogue.json`. `level.register_conversation(actor_id, graph)`
binds authored text to an existing actor; graphs support multiple lines, choices, conditions,
branches and validated case hooks. Mission progress persists in the local chapter checkpoint.

Small lawns and shrubs replace front concrete at 654 homes, preserving paved porch access.
Rose Hill Terrace's 24 upper bay windows use three projecting designs with angled side
panes, varied painted cladding and wrapping cornices, integrated into building LOD batches.
The source-generated yard provider adds 275 continuous hedge rows along 271 porch fronts,
469 reused cans, 51 dumpsters and 4,619 loose litter pieces. Nearby 48 m cells combine into one surface
each; distant cells unload. Only substantial bins have collision, never loose litter.
Twenty basketball courts (seventeen full courts, three half courts, 37 solid hoop poles) occupy
the approved usable greens across the level, preserving the requested Argonne court removal.
Each raised playing slab has solid retaining sides and two 3 m wide access ramps. The playing
grade stays at or below 1.5%, access ramps stay below 4°, and the deepest fill is 0.681 m.
Paint, slab, retaining sides and hoops share one draw surface per court; floor and side collision
remain active when distant visuals cull. Court reservations remove 29 overlapping trees and
62 shrubs, retaining 1,780 trees and 324 shrubs; all existing yard fixtures remain clear.

`pen_lucy_courts.json` includes an explicit inventory of all 48 grass components at least 250 m²
and every named park: 22 covered, 24 too narrow for a supported half court and two approaches,
and two constrained terrain remnants excluded (1,353.29 m² at x 396–522/z −314–−271 and
386.72 m² at x 239–262/z 57–95). Another 1,250 tiny lawn fragments are below the area threshold.
The source pipeline discovers courts from all grass rather than limiting them to the three
largest community greens. For an overlay-only rebuild against the unchanged exported ground,
run `.work/city/venv/Scripts/python.exe blender/city/update_courts.py --publish` from the repository
root; without `--publish`, it writes reviewable metadata under `.work/vehicle-courts/generated/`.
Street fixtures are checked against complete sidewalk footprints, including crossing roads.
Unsignalized junctions have 87 signs tied to traffic stop controls; crossings join clear sidewalks.

Eighteen fictional local businesses are actual generated commercial buildings with readable
facade signs, display windows and awnings. Postal drop boxes and house mailboxes are
distributed across blocks. Hardscaped service yards cover 91,002.54 m², while seven mapped
parks and greens retain 6,584.02 m² of grass. Worn yellow road dots, occasional potholes and marked
crossings add street detail beyond the introductory Old York walk.

Discover optional cases by approaching people who need a hand. Press **E** at the nearby
prompt to preview a conversation; an explicit reply accepts the case. The resident offers the satchel case first,
then the opened parcel after its completion; the witness near Dumbarton offers cleanup.
Farther along Old York, the gardener, block organizer and porch caretaker offer separate
cases involving missing tools, a torn watch notice and a damaged lantern.
Yellow route lines and destination rings on both maps lead to the current objective. **E** works only nearby with a clear
view of the target. Cases are accepted from contacts in the neighborhood. Settings → Cases is a read-only ledger of completion, current progress, prerequisites and unavailable contacts; it does not accept missions or invent cancelled-attempt history.

| Case | Playable sequence | Points |
|---|---|---|
| Lost satchel | Ask the resident, find the blue satchel, carry it back | 100 |
| The opened parcel | Ask the resident, inspect or photograph packing evidence, speak to a witness, file a report | 150 |
| Keep the sidewalk clear | Ask the witness, record dumped waste, request cleanup, verify the cleared site | 175 |
| The missing garden tools | Ask the gardener and mail carrier, recover the green caddy, return the tools | 125 |
| The torn watch notice | Inspect the torn notice, check the witness account, resolve the cause with the organizer | 140 |
| A light out on the block | Inspect the disconnected lantern, report damage without accusing a suspect, confirm repair arrangements | 160 |

Cases and characters are fictional. Each case rewards points once per saved chapter. Case progress,
points and walk check-ins persist in the chapter checkpoint; display, audio and control settings
persist separately. The original block, its two-stage missions and saved stage progress
remain available through **Settings → Main menu**. Baltimore uses its own local cases and actors.

The opened-parcel case is migrated to the validated data-driven case engine. Templates
support dialogue, evidence, photos, interviews, reports, visit/follow/flee objectives and
incident outcomes, with saved progress and once-only rewards. Templates and the unindexed
authoring example are scaffolds, not newly shipped story cases. See
[CASE_AUTHORING.md](../artifacts/pacifist-foundation/CASE_AUTHORING.md) for the schema and
workflow, and [ACCEPTANCE.md](../artifacts/pacifist-foundation/ACCEPTANCE.md) for tested scope.

Bounded ambient incidents use real neighbors for jaywalking, mail tampering, dumping, theft
and fights. Sight or verified evidence establishes report context; gallery metadata cannot
fabricate a new witnessed act. Police handle the reported situation, and repeat reports do
not create duplicate dispatches. Case and incident records are included in checkpoints.

The city renderer groups building surfaces into cached geographic chunks with native mesh
LODs and matching shadow meshes. Distant detailed chunks are actually freed, leaving simple
building silhouettes; approaching chunks load asynchronously. Different load and unload
distances prevent repeated rebuilding at a boundary. Imported terrain/building
collision shapes remain resident, so graphics streaming does not open holes in the world.
Vegetation, ambient crowds, parked cars and street details also create and release nearby
cell nodes while retaining their placement records. Nearby idle crowd poses update four times
per second; batched walkers update at 20 Hz. Three cached pose meshes share one modular material and twenty reusable appearances. The 1,200 ambient identities reuse these looks; the twenty daily residents each have a different roster appearance.

The first phase of each visit still loads the full imported GLB to establish authoritative
collision and measure placements. Streaming reduces detailed render resources after this
setup; it is not a fully streamed startup. Cached building meshes avoid rebuilding batches
on unchanged runs, and loading progress is shown while setup completes.

Across the 659 generated porches, 659 stair-end posts support previously open railing ends.
The source includes 889 rear entries and covers every addressed home. Of 868 footprints in
the broader residential classification, 866 have rear entries; two unaddressed structures
lack either an exposed rear wall or sufficient door headroom.
A continuous grading field covers roads, sidewalks, alleys and paved lots. The source audit
finds no paved area above 4° slope. The sidewalk check covers 99,684 top triangles: substantial
faces reach 3.078° maximum slope, with a 2.719° 95th percentile and no area above 5% crossfall.
Main roof heights relative to building footing are preserved across all 967 buildings, with
zero datum-relative error in the source audit. Twelve repaired building footprints leave
zero building-road intrusions. The vegetation library
places 1,812 trees and 440 shrubs using seven shared variants with 14 near/far meshes. Tree crowns have irregular clusters and
branches; nearby trunks use cylinder collision, and distant trees retain cheap silhouettes.
Shrubs are decorative and do not obstruct walking. City-specific materials weather brick,
trim and glass; roughly 80% of eligible first-floor windows have inexpensive grille quads.
Small pieces of non-blocking litter add detail beside the walking route. The original block
keeps its existing materials.

The city model lives at `assets/models/city/pen_lucy.glb`; compact runtime route and map data
is `assets/data/pen_lucy_level.json`, generated by `blender/city/process.py`. Shared vegetation
meshes and placements are in `assets/data/pen_lucy_vegetation.json`. The source workflow
and geographic-data attribution are documented in `../blender/city/README.md`.

The house rules in the root `CLAUDE.md` apply here too: substantial objects remain solid,
the owners' lines are word for word, and the camera doesn't
cut between back-to-back lines by the same speaker. Decorative sidewalk litter is explicitly
non-blocking. Pen Lucy's requested movement behavior uses continuous forward steering and
physical wall gliding, with the visible body turning toward its actual travel.

## How it is put together

| Path | What |
|---|---|
| `scripts/core/g.gd` | Autoload `G`: game state (`S`, `P`, `C`, `W`, `W_`, `car`, clock, `later()`), the main loop, the shared helpers. JS globals keep their names (`S.score` is `G.S.score`; functions are snake_case: `startCrime` is `G.start_crime`) |
| `scripts/core/u.gd` | `U.rand`, `U.ang_diff`, `U.turn_toward`, `U.fmt` (engine.js helpers) |
| `scripts/core/clay_lib.gd` | Builds every material from its Blender name (see `blender/README.md`) |
| `scripts/world/` | The block: placing the models, `ground_y`, colliders (`SOLIDS`), occluders, Stage 2 props |
| `scripts/actors/` | Puppets (`pose()`), walkers and collision bodies, the player, camera, binoculars, cop car, `animate_all` |
| `scripts/crimes/` | `Crime` base class, crime spawning/timers, every crime, the minigames, the E key |
| `scripts/ui/hud.gd` | Autoload `Hud`: subtitles, toasts, markers, case file, mini-map, puzzles, screens, music video |
| `scripts/audio/audio.gd` | Autoload `Audio`: the beat and the sound effects |
| `scripts/city/` | Pen Lucy movement and physics, neighbors, vehicles, local cases, map, settings, weathering, native LOD batches and cell streaming |
| `assets/models/` | GLBs built by `blender/assets/*.py`. Don't edit them in Godot; change the script and rebuild |
| `assets/materials/clay.gdshader` | Clean color/roughness shading shared by both levels (legacy filename) |
| `assets/audio/`, `assets/video/` | The beat and sound effects rendered from `js/audio.js` (`python tools/audio/render_audio.py`), and the music video as Ogg Theora (`python tools/audio/convert_video.py`). Keep the `.wav.import` files: they force uncompressed PCM |
| `tools/` | Import hook, preview renderer (`godot_preview.py`), locked runner (`godot_run.py`), texture generator, input setup |

The original block's coordinates are the same as the JS: x east along the street, y up, houses at negative z
(front walls at z = -7), the street at z 0..14, yaw 0 facing +z with forward `(sin(yaw), cos(yaw))`.
Collision works like the JS (2D circles and boxes in x/z, not the physics engine), so the
"nobody walks through anybody" rules behave exactly the same. Pen Lucy instead uses Godot
physics bodies on surveyed terrain, with x east, y up and z south; yaw 0 still faces +z.

## The contract between parts

Gameplay talks to the HUD only through the functions in `scripts/ui/hud.gd`, and to sound only
through `scripts/audio/audio.gd`. The HUD reads only the state marked `[HUD]` in `g.gd` and
`crime.gd`. Keep those names stable and the parts can change independently.

## Testing

- `python tools/godot_preview.py res://assets/models/<id>.glb out.png` renders a model with the game's lighting.
- The debug hooks in `G` (like the JS `window.__tt`) can start any crime directly.
- `python tools/godot_run.py -- --headless --script res://tests/city_smoke.gd` checks neighborhood
  entry/return, terrain footing, building collision, and walking. Run from the `godot/` folder.
- `python tools/godot_run.py -- --headless --script res://tests/city_life_smoke.gd` checks local
  actors, traffic movement, pause, ordered case interactions, rewards and scene cleanup.
- `python tools/godot_run.py -- --headless --script res://tests/city_expansion_smoke.gd` checks
  porch support, crowd density and batching, route clearance, pause and distance updates,
  absent name labels, nearby discovery, and the three new cases' one-time rewards.
- `python tools/godot_run.py -- --headless --fixed-fps 60 --max-fps 0 --script res://tests/city_movement_smoke.gd`
  checks all eight input directions, every ordered direction transition while walking and
  running, orbit/release and delayed camera follow, diagonal/uphill curbs, structural porch
  stairs, head clearance, wall gliding and solid corners. The current fixture suite passes 114 checks.
- `python tools/godot_run.py -- --headless --fixed-fps 60 --max-fps 0 --script res://tests/city_jump_smoke.gd`
  checks grounded jump, momentum, ceiling collision, coyote time, input buffering and pause.
- `city_mission_navigation_smoke.gd` checks shared route caching and safe endpoint links;
  the UI and six-case life suites check actual case destinations and route lifecycle.
- `city_courts_smoke.gd` checks the complete green coverage audit, court grounding, pole and
  retaining-side collision, all 160 park residents staying clear, actual player traversal of
  both access ramps, jumping and distance culling. Counts come from the exported coverage audit.
- `python tools/godot_run.py -- --headless --fixed-fps 60 --max-fps 0 --script res://tests/city_porch_movement_smoke.gd`
  exercises actual imported porch staircases across the map, walking and running up and down
  with full collision and the original 28 cm step limit. Eight sampled porches pass all 50
  checks. It requires the regenerated porch metadata.
- `python tools/godot_run.py -- --headless --fixed-fps 60 --max-fps 0 --script res://tests/city_traffic_network_smoke.gd`
  checks geographic traffic coverage, sustained movement, lane separation and junction handoff.
- `python tools/godot_run.py -- --headless --script res://tests/city_streaming_smoke.gd` checks
  actual detailed-chunk unload/reload, material and geometry preservation, collision continuity,
  distance margins and detail-provider operation when building streaming is unavailable.
  `--fixed-fps 60 --max-fps 0` can accelerate deterministic smoke runs; use normal wall-clock
  timing for performance measurements.
- `python tools/godot_run.py -- --resolution 1280x720 --script res://tools/city_life_benchmark.gd -- --outdir res://../artifacts/city-life-benchmark`
  measures seven seconds of actual route walking after 120 warmup frames, with the normal
  chase camera, HUD, people and traffic active. It writes `metrics.json` and start/end PNGs.
  Keep its window focused: any pause makes the result invalid. Rendering is uncapped with
  VSync off; the report includes delivered and physics FPS, median/p95/worst frame time,
  draw calls, CPU timing samples, actual walking distance and active actor counts.
  This complements `tools/city_render_benchmark.gd`, whose fixed views isolate rendering cost.
- `python tools/godot_run.py -- --headless --script res://tests/smoke.gd` checks the original
  game's crime progression and finale.


## Daily residents, clock and combat

The Pen Lucy level now owns `world_time`, `day_night`, `residents` and `combat` providers.
The twenty authored adults live in `assets/data/pen_lucy_residents.json`: stable IDs,
appearance, dialogue and six schedule slots. Nearby actors use grounded collision-tested
walks; distant actors advance logical routes at 2 Hz. Activation has hysteresis and a fade,
with deterministic yielding and a validated route rejoin after combat. Sleep currently
means resting at an outdoor home frontage. A versioned local checkpoint restores clock, resident schedules, case progress, player position and equipment. Progress autosaves every 30 seconds on safe ground, on normal window close, and through Esc → Save progress. Combat and airborne states wait for a stable checkpoint. Malformed/future-version saves are preserved.

The clock starts at 09:00 and runs one game day per 48 real minutes. Menus and dialogue
freeze it and the shared wind clock. Daylight/sky update at bounded rates; eight nearby
shadowless street lights illuminate existing lamp heads after dusk.

Player attacks and weapons are disabled by `city_play_mode.gd`; RMB still orbits.
The old punch/weapon implementation and inventory data are retained as backend scaffolding.
NPC fights cap at eight full reactive actors,
including temporary promotions from the modular crowd that retain the same appearance. Bullets check chest/barrel/target
cover and never aim backward through the player. NPC deaths persist in the world slot. A case closes without a reward if a required remaining contact dies; survivors can resume their routines. Nearby gunfire triggers bounded flee/cower behavior, and deterministically armed civilians return fire only when directly threatened. Vehicle tires can be punctured; threatened drivers accelerate to escape while respecting physical clearance and junction rules.

Validation fixtures: `city_residents_smoke`, `city_resident_recovery_smoke`,
`city_world_time_smoke`, `city_day_night_smoke`, `city_combat_smoke`,
`city_vegetation_batch_smoke`, and the graphical `city_living_world_render`.
Use the existing serialized `tools/godot_run.py` wrapper. The graphical fixture requires
`--offscreen-validation`; it captures a private SubViewport, never the desktop.

Benchmark flags on `tools/city_life_benchmark.gd`: `--profile-city`,
`--freeze-world-time`, `--no-resident-routines` (same 20 people),
`--no-daily-residents` (population baseline), `--no-city-wind` (same shader, no sway),
and `--no-city-wind-shader` (prior StandardMaterial appearance, same mesh layout).
Use repeated fresh processes, fixed render size/quality and identical walk route.
Wait for resident path preparation before collecting component timings. Reports live in
`../artifacts/living-world`; no Rust migration was performed.


## Rendering audit and material finishes

Compatible building finishes share full-float vertex palettes after weathering; glass and
unrelated materials keep their own surfaces. Geometry, native LODs and collision remain.
Consolidated meshes are cached under `user://city_palette_cache`; shader changes invalidate
that cache. Vegetation retains a bounded history of LOD meshes, constructs at most one new
mesh per presence refresh, and prepares the initial horizon behind the loading screen.

The calibrated brick, trim, pavement, road paint and glass shaders reuse existing wear
masks and fade fine detail with distance. `--legacy-city-finishes` and
`--no-city-material-palette` isolate their costs for comparisons. See
[the implementation matrix](../artifacts/render-audit/shader-implementation.md) and
[measurements and validation](../artifacts/render-audit/acceptance.md).

### Civic district and detailed map

M opens the full neighborhood with cached building footprints, street names, parks and ochre basketball courts. Civic buildings and businesses use symbols with a legend and names on hover/selection; the circular minimap and yellow mission route remain available during play.

The selected redevelopment is authored in `godot/assets/data/pen_lucy_civic_build.json`: P2 police precinct and its south parking lot, East 39th/Old York firehouse, Argonne courthouse, and Cator/Elkader hospital. The hospital retains all 22 Argonne homes in Row_143, Row_173 and Row_186. `pen_lucy_new_businesses.json` adds one recording studio, three liquor stores and four corner stores. Civic buildings remain exterior architecture; police cruiser response is implemented below. Hospital/fire dispatch remains future work.

Civic source removals run before collision, rendering caches and population setup. Terrain repairs fill holes under demolished buildings. Detailed placement/preservation evidence lives in `artifacts/civic-build/`; generated screenshots stay local. Existing map-edge collision remains a fallback; a natural-looking boundary pass is still a design proposal.

Ambient crowd identities are fixed by `assets/data/pen_lucy_crowd_recipe.json`, captured from the pre-redevelopment city. Keep every existing ordinal and birth anchor: append future residents instead of regenerating/reordering the recipe. Civic construction relocates affected slots while preserving saved `crowd_<index>` deaths. `--export-crowd-recipe` is an authoring-only baseline operation and must be paired with `--no-civic-district`; normal play never rewrites this compatibility asset.

### Screenshot inspection mode

During play, F6 toggles a detached, collision-free camera. The world and clock freeze; F6 returns to 2-Pack's original position and camera mode. WASD flies relative to the view, E or Space rises, Q descends, Shift boosts speed fourfold, Ctrl gives precision speed, and the wheel adjusts base speed from 5 to 200 m/s (default 35). Mouse sensitivity/invert settings apply. Esc releases the cursor; click to resume flying. Losing window focus releases control too.

The overlay shows camera XYZ, compass bearing, pitch, forward vector, FOV, nearest street, crosshair hit position/object, FPS and streamed detail. Coordinates are Godot metres: X east, Y up, Z south; compass zero is north and positive pitch looks up. Building detail, props and the existing night-light pool follow the inspection camera while the physical player stays put. M opens the neighborhood map during flight: the white arrow marks the camera and its bearing, while a small muted dot marks 2-Pack. Find me centers the camera. M, Esc or Close map returns to flight with the simulation still paused.

F7 copies a JSON location report. F8 saves the current viewport, including the overlay, as a PNG plus a matching JSON sidecar under `user://inspection_shots`. On a default Windows install this is `%APPDATA%/Godot/app_userdata/Tattletale 2-Pack/inspection_shots`; the copied report includes the exact directory and last screenshot path. Share the image and JSON together for precise change requests. No save-slot positions are changed by flying.

Validation: `tests/city_inspector_smoke.gd` runs headless for controls/state or with `--offscreen-validation` for private-viewport PNG/JSON verification. All normal engine runs still use `tools/godot_run.py`.


### Standalone candidate and acceptance status

Current nonviolent foundation, standalone candidate and audit status are tracked in
[the pacifist acceptance report](../artifacts/pacifist-foundation/ACCEPTANCE.md).
The older release and test results below remain historical; they do not certify later changes.

The Windows x86-64 `pen-lucy-rc3` package was exported, booted from its executable/PCK, and checksum-verified by the release pipeline. It starts Pen Lucy without a Godot editor or source checkout. The original source-project F5 entry remains the original title screen; F6 inspection remains available in both. See [release build instructions](release/README.md). The launcher profile under `.work/play-profile` and a normal standalone `%APPDATA%` profile are separate; the exporter does not automatically migrate a launcher's saved game.

The latest normal-input case session passed 44 checks, including actual dialogue choices, a mouse click on Save progress, a fresh scene, and checkpoint reload. Private UI captures passed the radar/full-map attribution pixel checks. These results do not certify every later source change. The final frozen suite, matched performance acceptance, and closure of the final independent audit are tracked in [the implementation review](../artifacts/alive-next/IMPLEMENTATION_AND_REVIEW.md).

### Retained systems and the nonviolent playable direction

Player car driving is disabled. Its backend promotion preserves visual identity and damage, while a bounded
eight-car remembered fleet keeps save and physics costs predictable. Cars have body
damage, disabled engines, punctured tires, a seated player, spatial engine/skid/horn
audio, and occupant bullet tests against solid bodywork and world cover.

Witnessed/reported offenses can dispatch up to two real traffic cruisers with dedicated
officers. Their response uses reports and sightings, then last-known-position search,
dismount and ordinary foot law behavior. The previous player-pursuit/surrender path is retained. Crews, authority,
road clearance and safe queue recovery are bounded; dead officers do not return.

Talk to Ines Morales on Dumbarton Avenue with E to begin Petal Pushers. Nonviolent
approaches lead into later branches, with persistent relationships and lawful delivery/watch
income. Intimidation is withheld; old intimidation saves can make amends. Snitch/Gangsta
alignment is frozen and hidden, with its stored values and implementation retained.
All four gun shops remain modeled but physically shuttered and unable to sell weapons/ammo.
Money and the existing goods shop remain available. Jobs share a cooldown. The
Cases ledger records progress, and dead contacts are handled without impossible jobs.

Schema-4 checkpoints persist story and remembered cars, migrate old versions and
validate complete restores before applying them. Occupied cars and active confrontations
defer checkpoints. The launcher and standalone profiles remain separate.

Detailed map building/court geometry now uses retained mesh/line batches, preserving
vector zoom/pan. A private GPU probe measured 3,928 to 28 canvas draw calls for its
civic geometry; this is a map-specific improvement, not an overall FPS claim.

The previous combat/driving acceptance suite (`tools/validate_priorities_session.py`) is
retained as backend history, not the playable nonviolent acceptance gate. Current integrated
phone/map/bicycle/case/report/save checks use `tests/city_foundation_acceptance.gd` with
`--offscreen-validation` and a private profile. See the current
[acceptance ledger](../artifacts/pacifist-foundation/ACCEPTANCE.md) for its guarded render
launcher, exact receipts, and separate natural-incident/curb/recovery coverage.
The previous `tools/validate_priorities_session.py --mode soak --seconds 900 --render` provides the
isolated, off-desktop combined run, and `tools/validate_priorities_release.py --build
--build-id <unique-id>` for the source-free Windows package and save/startup checks.
Both route engine work through the shared serialized Godot runner. Test windows must
remain unfocusable with the desktop cursor uncaptured. See the acceptance report for
the explicit validation-only input gates and staged release pointer guard.
