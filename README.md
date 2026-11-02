# Tattletale 2-Pack

Current Pen Lucy work: [non-quest systems and acceptance](artifacts/next-five-20261101/ACCEPTANCE.md), [pacifist foundation](artifacts/pacifist-foundation/ACCEPTANCE.md), [case authoring](artifacts/pacifist-foundation/CASE_AUTHORING.md), and [world quality inventory](artifacts/pacifist-foundation/WORLD_QUALITY.md). Earlier [neighborhood implementation](artifacts/alive-next/IMPLEMENTATION_AND_REVIEW.md), [shipping roadmap](artifacts/alive-next/SHIPPING_ROADMAP.md), [shader implementation](artifacts/render-audit/shader-implementation.md), and [shader research](artifacts/living-world/shader-research.md) preserve previous work; their older combat/driving priorities are historical.

A stylized 3D snitch game. Tattletale 2-Pack lives on a block where nothing ever changes, and he's telling on **everybody**. Every crime gets reported its own way: follow a trail of cash, tail the mailman, blow your whistle on the beat, tell Timmy's mama, dial in Mama's license plate from memory... and the timer never stops.

Based on the claymation music video **"Still There"** (it plays between Stage 1 and Stage 2).

## Current Godot neighborhood: Pen Lucy

The **Godot version** includes a walkable Pen Lucy, Baltimore neighborhood built from real
map and terrain data, with 1,200 ambient neighbors, connected street traffic and six local cases.
On Windows, install Godot 4.7+ and put `godot.exe` on PATH (or set `GODOT_EXE` to its full
path), then double-click **Play Pen Lucy.cmd** to enter the neighborhood in a maximized
window. The first launch imports the included assets; Blender and source-data downloads
are not needed to play. From the Godot editor, open `godot/project.godot`, press F5, and choose
**Explore Pen Lucy**. Walk up to a neighbor and press **E** when offered help: the resident
has a lost satchel and then an opened parcel; other neighbors need help with dumped waste,
missing garden tools, a torn watch notice and a damaged porch light. Residents sit on porches,
gather along sidewalks and walk the block without persistent names above their heads.
**WASD** steers continuously; **Space** jumps; hold **right mouse** to orbit the camera while moving.
Forty authored adult residents now have distinct appearances and daily home/work/leisure routines.
A shared 48-minute day moves the visible sun, changes the sky and lights street lamps at dusk.
Pen Lucy focuses on helping neighbors, documenting evidence and reporting what you witnessed.
Player attacks, weapon selection, car driving and alignment scoring are disabled; currency,
relationships and nonviolent errands remain. NPC incidents and police responses still operate,
and persistent NPC state is retained. Six additional vehicle silhouettes join the original three.
Forty modular appearances replace the ambient blockouts while preserving all 1,200 crowd identities.
**P** opens or closes the phone. **1–5** selects Contacts, Camera, Photos, Cases or Police.
In Camera, **left mouse / Enter** takes a clean photo and the wheel zooms. View or delete
photos inside the phone's gallery; there is no photo-folder shortcut. **Esc / Backspace** goes
back, **F5** saves while the phone is open, and **M** opens the map. The world keeps moving
while you use the phone. In Police, **Enter** reports a witnessed incident or requests an area
check; an unknown or unwitnessed incident cannot become a report just by selecting it.
Reported injuries can dispatch a hospital ambulance and two paramedics. The phone follows actual
arrival, treatment or inability to reach the patient; loading interrupts a live response honestly.
**F** mounts the nearby bicycle or dismounts after braking. **W/S** pedals or brakes/reverses,
**A/D** steers independently of the camera, **Space** hops and **Shift** pedals harder.
Hard impacts can eject the rider; wait for recovery before riding or saving again. Pedestrian
contacts can cause nonlethal stumbles or knockdowns and fists-only retaliation. Put the phone
away before riding. At a court, **E** picks up/drops a ball; hold/release **left mouse** to shoot,
**R** returns it and **T** starts a first-to-11 pickup game. Press **T** twice to quit;
press it at the result to rematch. Defensive rebounds must be cleared beyond the arc.
Pickup games are local activities and are not saved with checkpoints.
Routines currently use outdoor frontages; interiors are not implemented. Stable ground progress
saves automatically and through **Esc → Save progress**; supported older saves migrate through
the compatibility path. Mounted bicycle checkpoints are supported while safely stopped;
finish crash recovery or active confrontations before saving or loading.
Settings includes checkpoint loading and a confirmed Start Fresh action that archives existing saves.
Controls can be rebound, and text can be enlarged to 110% or 125%.
At the Old York Pantry service window near East 41st, buy food/drink to recover lost health,
bicycle colors or bandana colors. Owned colors can be equipped again without paying twice.
See [current validation and profiling](artifacts/next-five-20261101/ACCEPTANCE.md).
Walk onto porch stairs and glide along walls with full collision. After manual look, the
camera gently follows sustained travel; it preserves your view while idle or holding orbit.
A circular radar follows your view; **M** opens the full neighborhood map and **Esc** opens
Video, Audio and Controls settings.
The map uses place symbols and a legend; hover or select a symbol to see its name.
Accepted cases show a yellow destination and route on both maps. Loading welcomes you to
Baltimore; Settings use a black background with light text and half-width sliders.
The neighborhood has solid buildings and street fixtures, traffic signals, porch and street
lights, weathered glass and brick, and decorative litter
that does not block walking. Across the neighborhood, people sit on porches and gather in
circles; generated commercial buildings, postal boxes, 216 street-parked cars, varied trees and
shabby shrubs fill out the surrounding blocks. Small front gardens now serve 654 homes,
with clear paved porch approaches and 275 continuous porch-front hedges. Twenty basketball
courts (seventeen full courts and three half courts) occupy approved usable greens.
Raised slabs have solid retaining sides and two gentle access ramps;
the placement audit records narrow or steep parcels that cannot fit safely. Service yards and alleys contain 469 cans, 51 dumpsters and
non-blocking loose litter. Hardscaped service yards separate the homes,
and seven mapped parks and greens retain grass. Porch rail ends have supports; sidewalks
follow street grades with mild imperfections and controlled crossfall. Its street name and current objective share the right-hand ledger;
FPS sits at the top left. The original crime missions remain on the original block.
The moving fleet has 90 cars across 16 streets, including four police cars. Cautious drivers
brake for the player; a minority of faster aggressive drivers can cause a short physical stumble.
The original Bungee, Barlow Condensed and Courier Prime fonts and case-file styling now carry
through the city HUD, settings and text conversations. Nearby **E** opens a conversation;
reply choices explicitly accept or progress a case, and **Esc** leaves without advancing it.
All 659 generated porches have supported stair-side rail ends, and every addressed home
has a generated rear entry on an exposed wall.
The original opened-parcel case now uses a validated data-driven case engine. Reusable
templates support evidence, interviews, photographs, reports and saved outcomes; they do not
add new story cases by themselves. See [CASE_AUTHORING.md](artifacts/pacifist-foundation/CASE_AUTHORING.md)
for the schema and authoring workflow, and [ACCEPTANCE.md](artifacts/pacifist-foundation/ACCEPTANCE.md)
for the current candidate's tests and remaining audit work.
Nearby building details load and unload as you explore, while distant silhouettes remain.
Startup still reads the full city model to establish collision and placements. Case progress,
world time, resident state, equipment and NPC deaths persist in the chapter checkpoint;
settings persist separately. Settings explains blocked saves and can preserve an incompatible
checkpoint before establishing a new one. **Esc → Cases** shows current case availability.
See [the Godot guide](godot/README.md) for neighborhood controls and saved settings.
The [vehicle, courts and independent audit report](artifacts/vehicle-courts/acceptance.md)
records fitted car collisions, roof jumps, smooth traffic, expanded courts and next priorities.
The [current streets and navigation report](artifacts/pen-lucy-streets/acceptance.md) records
mission routes, jumping, settings, courts, hedges and fixture validation. The earlier
[content report](artifacts/pen-lucy-content/acceptance.md) covers dialogue and vehicle additions; the
[dense-world report](artifacts/pen-lucy-dense/acceptance.md) preserves the original baseline.
Large local captures,
downloaded LiDAR, build outputs, Godot caches and generated knowledge graphs are excluded
from Git; all required game assets and small runtime data files are included.

## Original two-stage web version — historical controls

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
