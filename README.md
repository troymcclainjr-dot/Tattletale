# Tattletale 2-Pack

A stylized 3D snitch game. Tattletale 2-Pack lives on a block where nothing ever changes, and he's telling on **everybody**. Every crime gets reported its own way: follow a trail of cash, tail the mailman, blow your whistle on the beat, tell Timmy's mama, dial in Mama's license plate from memory... and the timer never stops.

Based on the claymation music video **"Still There"** (it plays between Stage 1 and Stage 2).

The **Godot version** also includes a walkable Pen Lucy, Baltimore neighborhood built from real
map and terrain data, with 1,200 ambient neighbors, connected street traffic and six local cases.
On Windows, install Godot 4.7+ and put `godot.exe` on PATH (or set `GODOT_EXE` to its full
path), then double-click **Play Pen Lucy.cmd** to enter the neighborhood in a maximized
window. The first launch imports the included assets; Blender and source-data downloads
are not needed to play. From the Godot editor, open `godot/project.godot`, press F5, and choose
**Explore Pen Lucy**. Walk up to a neighbor and press **E** when offered help: the resident
has a lost satchel and then an opened parcel; other neighbors need help with dumped waste,
missing garden tools, a torn watch notice and a damaged porch light. Residents sit on porches,
gather along sidewalks and walk the block without persistent names above their heads.
**WASD** steers continuously; hold **right mouse** to orbit the camera while moving.
Walk onto porch stairs and glide along walls with full collision. After manual look, the
camera gently follows sustained travel; it preserves your view while idle or holding orbit.
A circular radar follows your view; **M** opens the full neighborhood map and **Esc** opens
Video, Audio and Controls settings. The neighborhood has solid buildings and street fixtures,
traffic signals, porch and street lights, weathered glass and brick, and decorative litter
that does not block walking. Across the neighborhood, people sit on porches and gather in
circles; 18 generated commercial buildings, postal boxes, 96 parked cars, varied trees and
shabby shrubs fill out the surrounding blocks. Hardscaped service yards separate the homes,
and seven mapped parks and greens retain grass. Porch rail ends have supports; sidewalks
follow street grades with mild imperfections and controlled crossfall. Its street name and current objective share the right-hand ledger;
FPS sits at the top left. The original crime missions remain on the original block.
The moving fleet has 72 cars across 16 streets, including four police cars.
All 659 generated porches have supported stair-side rail ends, and every addressed home
has a generated rear entry on an exposed wall.
Nearby building details load and unload as you explore, while distant silhouettes remain.
Startup still reads the full city model to establish collision and placements; case progress
lasts for the current visit, and settings persist between visits.
See [the Godot guide](godot/README.md) for neighborhood controls and saved settings.
The [latest neighborhood acceptance report](artifacts/pen-lucy-dense/acceptance.md) includes
805 passing checks and measured 1080p active-play performance. Large local captures,
downloaded LiDAR, build outputs, Godot caches and generated knowledge graphs are excluded
from Git; all required game assets and small runtime data files are included.

## Play it

- **On your computer:** download the project (GitHub Desktop, or the green **Code → Download ZIP** button) and double-click `index.html`.
- **Online:** once GitHub Pages is turned on (see below), it's at **https://troymcclainjr-dot.github.io/Tattletale/**

Controls: **WASD** walk · **Shift** run · drag the mouse or **← →** to look · hold **right mouse** or **Space** for binoculars · **E** to do things · **M** music · **P** pause. Keyboard and mouse only for now.

## What's in here

| File | What it does |
|---|---|
| `index.html` | The page: screens, panels, and the list of scripts (they load in order) |
| `css/style.css` | How the menus and on-screen panels look |
| `js/engine.js` | Helpers, the renderer, lights, surface materials, text signs |
| `js/world.js` | The block: houses, shops, Precinct 9, payphones, Gary's spot, and the Stage 2 props |
| `js/characters.js` | The clay people and the cop car |
| `js/movement.js` | Collisions and NPC walking |
| `js/state.js` | Game state, the player, `build()` |
| `js/crimes-core.js` | How a crime works: steps, timers, spawning, stages |
| `js/crimes-stage1.js` | Stage 1: Gary, Ricky, Grandma, Timmy, the lawn, the mailman |
| `js/crimes-stage2.js` | Stage 2: Mama, Daddy, the squirrel, the baby, the cops |
| `js/minigames.js` | Whistle, ruler, snore recording, the 911 call |
| `js/copcar.js` | The cop car driving to busts and back |
| `js/player.js` | 2-Pack's controls, binoculars, camera |
| `js/animate.js` | Animating everybody every frame |
| `js/interact.js` | What the **E** key does where you're standing |
| `js/puzzles.js` | The broken payphone puzzles |
| `js/hud.js` | Subtitles, case file, markers, mini-map |
| `js/audio.js` | The beat and sound effects |
| `js/game.js` | Stages, the music video, the finale, input, the main loop |
| `media/still_there.mp4` | The music video |

## Working together (the routine)

You'll each have a copy of this folder on your own computer. GitHub keeps them in sync.

**First time only**
1. Install **GitHub Desktop** and sign in.
2. **File → Clone repository** → pick `Tattletale` → choose where to put it.

**Every time you work on it**
1. **Pull** first (the "Fetch origin" / "Pull origin" button). This grabs your partner's latest changes.
2. Make your changes. Open `index.html` in your browser to test (refresh after each change).
3. In GitHub Desktop, write a short summary of what you did (like "Added graffiti tagger crime") and click **Commit to main**.
4. Click **Push origin** to send it.

**Rules that keep it easy**
- **Pull before you start, push when you stop.** Small, frequent pushes beat one giant one.
- **Split up the files.** If one of you is working on `crimes-stage2.js`, the other works somewhere else (like `world.js`). Say who's taking what before you start.
- **If GitHub Desktop says there's a conflict,** you both changed the same lines. It will show both versions; keep the right one (or call your partner), then commit.
- **Use Issues as a to-do list.** The **Issues** tab on GitHub is a to-do list. One issue per idea; assign it to whoever's doing it.

## Turn on the online version (GitHub Pages)

Repo **Settings → Pages →** under "Build and deployment" pick **Deploy from a branch**, branch **main**, folder **/ (root)** → **Save**. After a minute or two the link above works, and it updates every time someone pushes.

## Ideas list

- Hiding spots for tailing (behind trash cans and hedges)
- Suspects who run when they spot you
- New crimes: a graffiti tagger painting "2-PACK IS A SNITCH" live; the judge; the jury
- Stage 3
- Controller support, and phone/touch controls
- Moving to a real game engine (Godot) for Steam

## Credits

- 3D: [three.js](https://threejs.org) r128 (MIT license), loaded from cdnjs
- Fonts: Bungee, Courier Prime, Barlow Condensed (Google Fonts)
- Everything else (the block, the clay people, the beat, the sound effects) is made in code in this repo.
