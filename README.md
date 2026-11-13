# Tattletale: pop-up prototype

A playable test of a new direction for Tattletale: flat paper characters in small low-poly sets. You walk a rapper from the street into a small recording studio (front room, control room, vocal booth) and can talk to the one other person there. It is a prototype: one building, two characters, one short conversation with placeholder lines.

![The street outside the studio](docs/street.jpg)

![Talking to Large Fry in the control room](docs/talk.jpg)

## How to play

You need **Godot 4.7 or newer**, the standard build (not .NET), from https://godotengine.org/download. Nothing else: there is no build step.

Get this folder (on GitHub: Code, then Download ZIP, and unzip it; or `git clone`), then either:

- **In Godot:** open Godot, choose **Import**, pick `project.godot` in this folder, wait for the art to finish importing (well under a minute), and press **F5**.
- **On Windows:** double-click **PLAY.cmd**. It finds Godot if `godot` is on the PATH, if you put the Godot .exe in this folder, or if you write its full path in a file named `godot_path.txt` in this folder. It brings in the art first, then opens the game.
- **From a terminal, any system:** in this folder run `godot --headless --path . --import`, then `godot --path .`.

The art must be imported once before the game can show it. Opening the project in the editor does that, and so do PLAY.cmd and the `--import` command.

## Keys

| Key | Does |
|---|---|
| WASD / arrows | Walk. He starts on the pavement outside the studio, walks round the furniture and the other character, and the camera follows him |
| E | Use whatever is nearest and in reach: talk to someone, open or close a door. Its name shows over it. A doorway can only be walked through while its door is open |
| 1 to 8 | Swap the lead between the character options (A to H). It starts on 5 (E), the only one with a walk cycle and loose face parts |
| Z / X | Previous / next expression (neutral, happy, grin, laugh, wink, calm, preachy, focused, angry, shout, sad, nervous, cringe, shocked, suspicious, side_eye, smug, bored) |
| Space (hold) | Move his mouth. If he has his back to you he turns round first |
| F | Close-up on / off (head to waist) |
| Tab | Next camera (follow, angle, angle_left, front, console, left, lounge, booth, top) |
| C | Control-room ceiling on / off |
| F8 | Save a screenshot to the Godot user folder |
| Esc | Quit |

In a conversation: the things he can say are listed; the one under the mouse turns yellow. Click it, or press its number. E, Space, Enter or a click (on the box, its text, or anywhere else) finishes a line that is still typing, then moves on.

## The place

Four spaces in a row, going away from the camera, with a door between each pair:

    street  |  front room  |  control room  |  vocal booth

- **Street:** a strip of pavement in front of the shopfront ("THE BACK ROOM"), between the wall and the kerb, with a laundry and a pawn shop either side. You cannot step into the road.
- **Front room:** counter, waiting chairs, soda machine, rate card. The padded red door leads on.
- **Control room:** the board, the couch, and Large Fry, who stays in this room.
- **Vocal booth:** through the door in the back wall, right of the glass. The mic and the lyric stand are at the window, so whoever is at the mic faces the control room.

The camera always looks from the street side. When he goes through a doorway the picture dips to black for a moment, everything between the camera and his room is taken away, and the camera takes up its place for that room. The wall he came through is left as a low strip on the floor and its door as a low slice, so the doorway can still be found and used from behind. The booth's window wall is the exception: from inside the booth it stays as a faint see-through wall with its window and door frames solid, so you look in at him through the glass.

Walking is relative to the screen. A character shows a different drawing for each way he walks: front when he comes towards you, back when he walks away, side when he walks across (mirrored to walk left). Changing drawing flips the card over like a sheet of paper. Expressions, blinking and talking work from the front and from the side; the back has no face.

The game view is `follow`: off to the right and turned about 30 degrees, a fixed step from him. In a conversation it eases in on the two of them. `angle` is the same side standing still, with the whole room in frame.

The names `TATTLETALE` and `LARGE FRY` are working names, and the lines in `assets/data/talk_fry.json` are placeholders.

## Files

- `scripts/main.gd` is the scene: the building, the two characters, the cameras, the fade between rooms, the E key and the name tag.
- `scripts/building.gd` puts the rooms in a row and knows the floor plan. `rooms` lists them front to back, each with its floor and its camera numbers (how close, how high, how far right). `walls` lists the wall and door between each pair. `show_from(n)` shows room n and what is behind it. `walk_areas()` is everywhere someone may stand: each room's floor, plus each doorway whose door is open. To add a room, build its set, add a row to `rooms` and a `_wall(...)` to `walls`. A wall can leave a see-through copy behind when it is cut away (`walls[i]["ghost"] = _ghost_of(wall)`): the set marks each part of that wall with `set_meta("ghost", "wall")` (turns faint, `GHOST_WALL`) or `"keep"` (frames and glass, left solid); unmarked parts are left out. The back wall in `studio_set.gd` is the example.
- `scripts/street_set.gd`, `scripts/front_set.gd` and `scripts/studio_set.gd` build the street, the front room, and the control room with its booth, from boxes and cylinders. Sizes and positions are metres; move a prop by changing its numbers. `AREA` is the floor, and `OBSTACLES` lists the floor space each prop takes up, for walking round: if you move a prop, move its entry.
- `scripts/kit.gd` holds the helpers it uses (`box`, `block`, `cyl`, `disc`, flat colours, tiling textures).
- `scripts/flicker_check.gd` finds surfaces that lie exactly on one another (they flicker as the camera moves). Run it after moving walls, frames or anything flush with them: `python tools/shot.py out.png --check-faces`. A door or window frame must stand a little into its opening, never flush with the cut end of the wall.
- `scripts/door.gd` is a door that swings open and shut, for any door: put the node at the hinge and call `build_leaf(width, height, colour)` (or build your own leaf under `leaf`). `open_angle`, `open_time` and `shut_time` set the swing; `passage` is the floor that opens up with it (`building.gd` sets it). The three doors in `street_set.gd`, `building.gd` and `studio_set.gd` are the examples.
- **Anything E can be used on** has four things: `use_name()` (shown over it), `use_spot()` and `use_reach` (where and how near), `label_spot()` (where the name goes), and `use(by)`. Doors and characters have them; add the node to `_usables` in `main.gd`.
- `scripts/paper_actor.gd` is the flat character card: which drawing to show, the walk cycle, and stopping at walls, props and other characters. Give it a `display_name` and it can be talked to.
- `scripts/wanderer.gd` walks a character about the floor on its own.
- `scripts/talk_box.gd` is the conversation box and runs a conversation from a table like `assets/data/talk_fry.json`: a node is either a list of things the player can say, or one line someone says. The format is at the top of the script. Text is in Bungee (`assets/fonts/`, with its licence, the SIL Open Font License; the font has capitals only).
- `shaders/paper_card.gdshader` moves the limbs inside a drawing without redrawing it: each leg is its own layer that can lift and swing, and each arm bends round its shoulder. The walk cycle in `paper_actor.gd` (`_pose`) only sets its numbers.
- `scripts/paper_face.gd` is the loose face: eyes, brows, mustache, goatee and mouth as small cards on the body card. It holds the expression table, blinks on its own, and flaps the mouth while `talking` is true. To add an expression, add a row to `EXPRESSIONS`: an eye drawing (or a different one per eye), a mouth, a brow, and where each brow sits. On the side profile it shows one eye, one brow and the profile version of the mouth (`parts/side_*.png`).
- `assets/characters/e/` is the lead and `assets/characters/fry/` the second character: a drawing per view, `limbs*.png` (which pixels are arm), `legs*.png` (which leg each pixel below the hip belongs to), `parts/*.png` and `rig.json` (where everything sits, in pixels of the body drawing). They are written by two scripts, `build_lead.py` and `build_fry.py`, from the original drawings. Those scripts and drawings are not in this repository (in the full Tattletale working folder they are in `../artifacts/flat-pivot-20261112/tools/`): change the numbers there and run them again (lead first), then `python tools/shot.py --import`. Fry wears shades and a cap, so the only loose face part he shows is the mouth. The side-view mouths (`parts/side_*.png`) are made by `lead_views.profile_mouths`: each is cut to the inside of the head outline, and one that would touch the drawn mustache or goatee is moved up or made smaller until it does not. To check them without the game, paste each on the side drawing where `rig.json` puts it.
- `assets/textures` are 256 px tiles and `assets/characters/option_*.png` are single cut-out drawings. Both were made outside this repository (in the full working folder: `../artifacts/flat-pivot-20261112/`, with the briefs in `briefs/`, the raw images, and `tools/process_art.py`, which keys out the green background and shrinks the textures).

## Screenshots from the command line

For working on the game, not needed to play it. Needs Python 3. Run from this folder; Godot is found the way PLAY.cmd finds it. The window opens on monitor 2 when there is one (`POPUP_MONITOR` picks another; 0 lets Godot choose). Inside the full Tattletale working folder it waits for that project's one-Godot-at-a-time lock, so close the Pen Lucy game first.

    python tools/shot.py --import
    python tools/shot.py out.png --cam=angle --char=e
    python tools/shot.py out.png --char=e --close --face=angry
    python tools/shot.py out.png --char=e --at=-1.5,1.6 --walk=1,0,0.8
    python tools/shot.py out.png --at=-0.3,0.9 --fry-at=-1.4,0.5 --do=use,wait:1,hover:1
    python tools/shot.py out.png --at=2.2,-1.9 --do=use,wait:1.2
    python tools/shot.py out.png --do=use,wait:1,go:1.97:5.26,go:0.78:3.24,use,wait:1,go:0.75:1.76

`--walk=x,y,seconds` walks him that way on screen (x right, y towards you) before the picture is taken. `--at=x,z` puts him anywhere on the floor plan (without it he starts on the pavement). `--do=` runs steps after that: `use` (press E), `wait:seconds`, `hover:n`, `pick:n`, `next`, `clickbox` (a mouse click on the talk box), `go:x:z` (walk straight to that spot; walls, props and shut doors stop him). The last line printed says which room he ended in. `--check-faces` lists flickering surfaces (see `flicker_check.gd`); `0 overlapping pairs` is clean.
