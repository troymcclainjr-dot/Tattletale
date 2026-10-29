# Tattletale 2-Pack: Godot port

A Godot 4.7 port of the web prototype in the repo root. The web version stays playable and
untouched. Open this folder (`godot/`) in Godot 4.7.2 and press F5.

The house rules in the root `CLAUDE.md` apply here too: nobody moves sideways or backwards,
nothing passes through anything, the owners' lines are word for word, and the camera doesn't
cut between back-to-back lines by the same speaker.

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
| `assets/models/` | GLBs built by `blender/assets/*.py`. Don't edit them in Godot; change the script and rebuild |
| `assets/materials/clay.gdshader` | The clay look for the whole game, one shader |
| `assets/audio/`, `assets/video/` | The beat and sound effects rendered from `js/audio.js` (`python tools/audio/render_audio.py`), and the music video as Ogg Theora (`python tools/audio/convert_video.py`). Keep the `.wav.import` files: they force uncompressed PCM |
| `tools/` | Import hook, preview renderer (`godot_preview.py`), locked runner (`godot_run.py`), texture generator, input setup |

Coordinates are the same as the JS: x east along the street, y up, houses at negative z
(front walls at z = -7), the street at z 0..14, yaw 0 facing +z with forward `(sin(yaw), cos(yaw))`.
Collision works like the JS (2D circles and boxes in x/z, not the physics engine), so the
"nobody walks through anybody" rules behave exactly the same.

## The contract between parts

Gameplay talks to the HUD only through the functions in `scripts/ui/hud.gd`, and to sound only
through `scripts/audio/audio.gd`. The HUD reads only the state marked `[HUD]` in `g.gd` and
`crime.gd`. Keep those names stable and the parts can change independently.

## Testing

- `python tools/godot_preview.py res://assets/models/<id>.glb out.png` renders a model with the game's lighting.
- The debug hooks in `G` (like the JS `window.__tt`) can start any crime directly.
