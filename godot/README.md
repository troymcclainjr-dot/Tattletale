# Tattletale 2-Pack: Godot port

A Godot 4.7 port of the web prototype in the repo root. The web version stays playable and
available. Open this folder (`godot/`) in Godot 4.7.2 and press F5.

## Pen Lucy neighborhood

Double-click **Play Pen Lucy** in the repository root on the configured Windows machine to
enter the Baltimore neighborhood with 2-Pack directly, in a maximized window. The launcher
uses its own profile under `.work/play-profile`. In the editor, run
`scenes/city/pen_lucy.tscn` directly, or choose **Explore Pen Lucy** from the F5 title screen.
Choose **Start snitchin'** there for the original two-stage game.

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
- **E** talks to a case contact, examines evidence or checks in at a gold walk marker.
- **M** opens or closes the map. Use the mouse wheel or **+ / −** to zoom and drag to pan.
  **Whole neighborhood** fits the map; **Find me** centers your position.
- **Esc** opens Settings or resumes play. Settings also offers **Return to starting corner**
  and **Main menu**, which returns to the original game's title screen.

The map and Settings pause play and release the cursor. Switching to another application
also pauses; returning to the game waits for an explicit **Resume** or **Esc**. Resuming
captures the cursor again. These controls apply to Pen Lucy; the web and original-block
controls are unchanged.

Settings has three tabs, with changes applied immediately and saved in the current user's
`user://pen_lucy_settings.cfg`:

- **Video:** Windowed, Maximized or Fullscreen; Low, Balanced or High quality; vertical sync,
  frame limit and render scale.
- **Audio:** master, music and sound-effect volume.
- **Controls:** mouse sensitivity, inverted vertical look and the keyboard reference.

The default is a maximized window. The top left shows FPS; the right-hand ledger shows the street
name, current objective and nearby interaction prompt. A small circular radar rotates with
the camera; the full **M** map remains north-up and supports zooming and panning.

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
72 moving cars across 16 streets, including four police vehicles, alongside 96 parked cars.
Parked cars use shared older-sedan, compact and minivan prototypes.
Settings and the map pause neighbors, traffic and case interactions.

Eighteen fictional local businesses are actual generated commercial buildings with readable
facade signs, display windows and awnings. Postal drop boxes and house mailboxes are
distributed across blocks. Hardscaped service yards cover 91,002.54 m², while seven mapped
parks and greens retain 6,584.02 m² of grass. Worn yellow road dots, occasional potholes and marked
crossings add street detail beyond the introductory Old York walk.

Discover optional cases by approaching people who need a hand. Press **E** at the nearby
prompt to accept and begin the conversation. The resident offers the satchel case first,
then the opened parcel after its completion; the witness near Dumbarton offers cleanup.
Farther along Old York, the gardener, block organizer and porch caretaker offer separate
cases involving missing tools, a torn watch notice and a damaged lantern.
Teal markers and the map lead to the current objective. **E** works only nearby with a clear
view of the target. Cases are discovered in the neighborhood, with no case board in Settings.

| Case | Playable sequence | Points |
|---|---|---|
| Lost satchel | Ask the resident, find the blue satchel, carry it back | 100 |
| The opened parcel | Ask the resident, examine packing evidence, speak to a witness, file a report | 150 |
| Keep the sidewalk clear | Ask the witness, record dumped waste, request cleanup, verify the cleared site | 175 |
| The missing garden tools | Ask the gardener and mail carrier, recover the green caddy, return the tools | 125 |
| The torn watch notice | Inspect the torn notice, check the witness account, resolve the cause with the organizer | 140 |
| A light out on the block | Inspect the disconnected lantern, report damage without accusing a suspect, confirm repair arrangements | 160 |

Cases and characters are fictional. Each case rewards points once per visit. Case progress,
points and walk check-ins last for the current visit; display, audio and control settings
persist between visits. The original block, its two-stage missions and saved stage progress
remain available through **Settings → Main menu**. Baltimore uses its own local cases and actors.

The city renderer groups building surfaces into cached geographic chunks with native mesh
LODs and matching shadow meshes. Distant detailed chunks are actually freed, leaving simple
building silhouettes; approaching chunks load asynchronously. Different load and unload
distances prevent repeated rebuilding at a boundary. Imported terrain/building
collision shapes remain resident, so graphics streaming does not open holes in the world.
Vegetation, ambient crowds, parked cars and street details also create and release nearby
cell nodes while retaining their placement records. Nearby idle crowd poses update four times
per second; batched walkers update at 20 Hz and residents share two colored meshes.

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
  stairs, head clearance, wall gliding and solid corners. The current fixture suite passes 88 checks.
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
