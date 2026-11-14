# Tattletale: pop-up prototype

A playable test of a new direction for Tattletale: flat paper characters in small low-poly sets. You walk a rapper round thirteen places in his neighbourhood: a small recording studio, the police station, the courthouse, his own house, a corner store, a liquor store, a friend's apartment, a hospital emergency department, a park with a full basketball court, a second park, a street of rowhouses, an old neighbour's house and a clothing store. He can run, change his clothes, and carry a pistol, an Uzi or an AK and point it. It is a prototype. Large Fry is at the studio and at home and has a short conversation in each, with placeholder lines. A clerk stands behind each shop's counter, police officers stand about the station and the court's security lobby, nurses work the hospital, three young men hang about the court in the park and three rappers are out shopping; they blink and watch you but have nothing to say yet.

![The street outside the studio](docs/street.jpg)

![Talking to Large Fry in the control room](docs/talk.jpg)

## How to play

You need **Godot 4.7 or newer**, the standard build (not .NET), from https://godotengine.org/download. Nothing else: there is no build step.

Get this folder (on GitHub: Code, then Download ZIP, and unzip it; or `git clone`), then either:

- **In Godot:** open Godot, choose **Import**, pick `project.godot` in this folder, wait for the art to finish importing (well under a minute), and press **F5**.
- **On Windows:** double-click **PLAY.cmd**. It finds Godot if `godot` is on the PATH, if you put the Godot .exe in this folder, or if you write its full path in a file named `godot_path.txt` in this folder. It brings in the art first, then opens the game. The game opens maximized.
- **From a terminal, any system:** in this folder run `godot --headless --path . --import`, then `godot --path .`.

The art must be imported once before the game can show it. Opening the project in the editor does that, and so do PLAY.cmd and the `--import` command.

## Starting

The game opens on a title screen: **NEW GAME**, **CONTINUE** and **SETTINGS**. Pick with the mouse, or Up / Down and Enter.

- **New game** goes to a black screen with the lead in the middle, a little angel at one shoulder and a little devil at the other. While you have picked neither, his eyes go from one to the other, the camera drifts a little, and START is greyed out. Click one (or press Left / Right): its outline glows, gold and white for the angel, red for the devil, his eyes stay on it, and START can be pressed. Click it again to let go; Esc goes back to the title. START puts him on the street outside the studio. So far the choice is only remembered (it shows in the corner text); nothing in the places depends on it yet.
- The angel and the devil are never still, picked or not. Both blink, move their brows and stretch and squash a little. The angel hovers, beats his wings and raises and lowers his praying hands; the devil flicks his tail, lifts his pitchfork and sets it down, and bounces on his heels. The devil wears no whistle: it is the lead's badge of telling tales. Each is one drawing cut into a body and its moving parts by `build_choice.py` (in the art folder): `assets/ui/<name>.png` is the body, `<name>_layer.png` the parts in colour, `<name>_parts.png` which part each pixel belongs to, `<name>.json` the pivots. `shaders/paper_glow.gdshader` moves each part as a stiff piece of card, behind the body or in front of it, so a wing or the pitchfork moving beside a face leaves the face alone. The choice is to become a crime-fighting playthrough (angel) or a criminal one (devil); nothing uses it yet.
- **Continue** is greyed out until there is a game to go back to. It returns him to the street outside the place he was last at. The game is kept in `save.json` in the Godot user folder, written when a new game starts and each time he travels.
- **Settings** has one switch so far: fullscreen on or off (kept in `settings.json`).

## Keys

| Key | Does |
|---|---|
| WASD / arrows | Walk. He starts on the pavement outside the studio, walks round the furniture and the other character, and the camera follows him |
| Shift (hold) | Run: nearly twice as fast, with quicker and longer steps, a lean, and arms that pump |
| Q | What he holds: nothing, a pistol, an Uzi, an AK, and round again |
| Right mouse button, or Ctrl (hold) | Point it. He turns side-on, towards the side of the screen the mouse is on (with Ctrl, the way he is already facing). Walking towards the camera or away from it he lowers it again |
| E | Use whatever is nearest and in reach: talk to someone, open or close a door, go up or down stairs, step up to the microphone in the studio's booth, try clothes at a rack in the clothing store, sleep in his bed. Its name shows over it. A doorway can only be walked through while its door is open |
| 1 to 8 | Swap the lead between the character options (A to H). It starts on 5 (E), the only one with a walk cycle and loose face parts |
| Z / X | Previous / next expression (neutral, happy, grin, laugh, wink, calm, preachy, focused, angry, shout, sad, nervous, cringe, shocked, suspicious, side_eye, smug, bored, scared, crying, hurt, disgusted, confused, embarrassed, guilty, pleading, dizzy, love, furious, innocent, sleepy, sly) |
| Space (hold) | Move his mouth. If he has his back to you he turns round first |
| F | Close-up on / off (head to waist) |
| Tab | Next camera (follow, angle, angle_left, front, console, left, lounge, booth, top). In the studio only |
| C | Control-room ceiling on / off. In the studio only |
| M | The travel list: the places he can go. Click one or press its key (1 to 9, then 0, A, B, C) and he arrives on the street outside it. M or Esc closes the list. There are thirteen |
| F8 | Save a screenshot to the Godot user folder |
| Esc | Ends a conversation, steps away from the microphone, or backs out of a menu. Otherwise quits |

At the microphone (E beside it, in the booth): black bars slide in top and bottom, the camera watches him through the control-room window and drifts slowly from side to side, and he performs: his mouth goes, his knees dip on the beat, he rocks from foot to foot and his arms work. There is no sound yet. Esc steps away.

In a conversation: the box opens out from a thin line, then the things he can say are listed; the one under the mouse turns yellow. Click it, or press its number. E, Space, Enter or a click (on the box, its text, or anywhere else) finishes a line that is still typing, then moves on.

## Running, weapons, clothes and days

- **Running** (Shift) is the walk cycle driven harder, not a second set of drawings: the steps come 1.4 times as fast and reach further than he was drawn, he leans into it, and his arms bend at the elbow and pump (`paper_actor.gd`: `RUN`, `RUN_STEPS`, `_pose`).
- **Weapons** (Q, and the right mouse button to point). A pistol and an Uzi are held in one hand, an AK in two. His arms are rubber hoses cut out of his drawing: each can turn at the shoulder, bow, and stretch along its length, and the game works out the turn and stretch that put his hand exactly on the grip. The hand itself is cut off at the wrist and a fist drawn with the weapon takes its place, tinted to his skin; the AK has a second fist under its handguard, which the other arm reaches. Side-on, where only one arm is drawn, the second arm comes out from behind his chest. Carrying, the weapon points at the ground ahead of him (a rifle across his chest from the front); pointing it, he turns side-on. Anyone whose drawing has cut-out arms can hold one: the lead, Large Fry and the six street characters. Nothing fires yet.
- **Clothes.** Each drawing comes with a picture that says which pixels are hat, jacket, shirt, trousers and shoes, and the card repaints a piece in another colour, keeping the ink lines. In the **clothing store** each rack gives the next colour of one piece (E), a jacket can come with long sleeves, and the tall mirror by the fitting rooms puts him back in his own clothes. What he has on is kept in the save.
- **Days.** E at the bed in his room at the crib ends the day. Every day after the first, the people whose clothes can change (the six street characters) take two or three pieces off the same racks, so nobody wears the same thing every day they are seen. Uniforms stay uniforms.

## The places

Press M to travel. He arrives on the pavement outside.

- **The Back Room**, the recording studio: described below.
- **Police station** (Pen Lucy Precinct): a worn old station house, 16 x 22 m. Lobby and the desk sergeant's office behind glass; the squad room and the captain's office; interview room, booking and the evidence cage; three cells, the drunk tank and the sally port at the back.
- **Courthouse** (district court): 18 x 22.5 m. Security lobby and the clerk's windows; a public hall and a lawyer room; one courtroom with the lockup and holding cell on one side and the jury room on the other; the judge's chambers and a records room behind.
- **Tattletale's crib**: a Baltimore rowhouse, 5 m wide. Living room, dining room, kitchen, back yard; press E at the foot of the stairs for his room, the bathroom and the back bedroom upstairs.
- **Corner store** (Miss Bea's Corner Grocery): the ground floor of the last house in a row, where two streets meet, 9 x 11 m. The shop, with the clerk behind plexiglass down the left side (the way in behind the counter is round its far end), coolers along the back wall and two runs of shelves; a back office and a stock room.
- **Liquor store** (Parkway Spirits): 10 x 12 m. The sales floor has the beer coolers, the wine and a stack of cases; the spirits are on a wall behind a sheet of plexiglass the width of the shop, reached by the steel door beside it; an office and a stock room behind.
- **Large Fry's place**: the ground-floor flat of an apartment block, 11 x 9.6 m, all on one floor and nothing like the crib. The block's entry hall (the lift is out of order) leads to his door; living room, kitchen, bathroom, bedroom. He is at home, wandering the living room, and will talk (he is also still at the studio).
- **Hospital** (the emergency department of Cator-Elkader Hospital): 18 x 18 m. Waiting room, triage and registration; a treatment room with three curtained bays and the nurses' station; a trauma room; the ambulance bay, a staff room and a supply room at the back.
- **Pen Lucy Park**: all out of doors, at night. A full 28 x 15 m basketball court, broadside to the camera, with every line and two hoops, under floodlights; bleachers, team benches, a scoreboard, a drinking fountain, bins; chain link round three sides and a low railing with a gate on the street. Behind it, across an alley, the backs of 27 rowhouses: back doors and steps, lit windows, yard fences, washing lines, aerials, garbage cans. Tre, Big Dee and Chuy are on the court.
- **Linden Square**: the second park, an old green square, 32 x 22 m, nothing like the first: iron railings and brick gate piers, flagstone paths meeting at a white bandstand, globe lamps, a lily pond with a fountain, picnic tables, stone chess tables, flower beds, and a playground in the back corner (swings, a slide, a roundabout, a climbing frame). Behind it the fronts of grand rowhouses, a stone church, a painted mural and a water tower.
- **Rose Hill Terrace**: a street to walk down, 57 m of it: a shorter copy of the Rose Hill Terrace block of the old Pen Lucy game. Porch-front rowhouses 516 to 532 in the old game's own colours, each with its three-sided upper bay; a paved strip, the pavement and the road, with parked cars to walk between; utility poles and wires; Old York Road crossing at one end. The houses have no insides.
- **Miss Bea's house**: an old neighbour's free-standing clapboard house, 9 x 11 m on two floors, lived in for forty years and unlike the crib and unlike Large Fry's flat: the front door opens at the foot of the stairs with the parlour through an arch beside it. A picket-fenced front yard and a full-width porch (a glider, rockers, hanging ferns); the parlour (a plastic-covered sofa, an upright piano with the family photographs, a console television) and the front hall; the dining room and the kitchen; a sun room and a pantry; upstairs (E at the stairs) her bedroom, a sewing room and a bathroom. Miss Bea herself is not there yet: she has no drawing.
- **Clothing store** (Fresh Threads): 10 x 11 m. A sales floor with a wall of hats, a rail of jackets, a wall of folded jeans, a sneaker wall, a table of shirts and a glass counter; fitting rooms with a three-way mirror; a stock room. Huff Daddy is shopping.

Out of doors nothing is hidden as he walks in: a park or a street is one room, in the street's own band. A place can be darker than the rest (`p.ambient`, `p.sun_energy` in its plan): the park is night, lit by its own lamps. The trees and shrubs are the old Pen Lucy game's own models (`assets/models/`, made from its plant templates by `make_plants.py` in the art folder's `borrow/`).

Every door opens with E. Floor plans of the police station, the courthouse and the crib are drawn by `make_layouts.py` (in the full working folder: `../artifacts/flat-pivot-20261112/layouts/`).

## The studio

Four spaces in a row, going away from the camera, with a door between each pair:

    street  |  front room  |  control room  |  vocal booth

- **Street:** a strip of pavement in front of the shopfront ("THE BACK ROOM"), between the wall and the kerb, with a laundry and a pawn shop either side. You cannot step into the road.
- **Front room:** counter, waiting chairs, soda machine, rate card. The padded red door leads on.
- **Control room:** the board, the couch, and Large Fry, who stays in this room.
- **Vocal booth:** through the door in the back wall, right of the glass. The mic and the lyric stand are at the window, so whoever is at the mic faces the control room.

The camera always looks from the street side. When he goes through a doorway the picture dips to black for a moment, everything between the camera and his room is taken away, and the camera takes up its place for that room. The wall he came through is left as a low strip on the floor. Its door still stands there, whole but see-through, and how see-through depends on how near he is: from across the room it cannot be seen at all, and it comes into view as he walks up to it, so the doorway can be found and used from behind without the door ever covering the room. That goes for every door in every place (`door.gd`: `cut_away`, `show_near`). The booth's window wall is the exception: from inside the booth it stays as a faint see-through wall with its window and door frames solid, so you look in at him through the glass.

Walking is relative to the screen. A character shows a different drawing for each way he walks: front when he comes towards you, back when he walks away, side when he walks across (mirrored to walk left). Changing drawing flips the card over like a sheet of paper. Expressions, blinking and talking work from the front and from the side; the back has no face.

The game view is `follow`: off to the right and turned about 30 degrees, a fixed step from him. In a conversation it eases in on the two of them. `angle` is the same side standing still, with the whole room in frame.

The names `TATTLETALE` and `LARGE FRY` are working names, and the lines in `assets/data/talk_fry.json` are placeholders. So are the names of the six street characters: `TRE`, `BIG DEE` and `CHUY`, and three parody rappers, `SNOOZY D`, `DOC DRAY` and `HUFF DADDY`, who are parodies of a type and of an era's clothes, not drawings of anyone. The lead no longer wears a whistle; his chain stays.

## Files

- `scripts/main.gd` is the scene: the building, the two characters, the cameras, the fade between rooms, the E key and the name tag.
- `scripts/building.gd` puts the rooms in a row and knows the floor plan. `rooms` lists them front to back, each with its floor and its camera numbers (how close, how high, how far right). `walls` lists the wall and door between each pair. `show_from(n)` shows room n and what is behind it. `walk_areas()` is everywhere someone may stand: each room's floor, plus each doorway whose door is open. To add a room, build its set, add a row to `rooms` and a `_wall(...)` to `walls`. A wall can leave a see-through copy behind when it is cut away (`walls[i]["ghost"] = _ghost_of(wall)`): the set marks each part of that wall with `set_meta("ghost", "wall")` (turns faint, `GHOST_WALL`) or `"keep"` (frames and glass, left solid); unmarked parts are left out. The back wall in `studio_set.gd` is the example.
- `scripts/street_set.gd`, `scripts/front_set.gd` and `scripts/studio_set.gd` build the street, the front room, and the control room with its booth, from boxes and cylinders. Sizes and positions are metres; move a prop by changing its numbers. `AREA` is the floor, and `OBSTACLES` lists the floor space each prop takes up, for walking round: if you move a prop, move its entry.
- `scripts/kit.gd` holds the helpers it uses (`box`, `block`, `cyl`, `disc`, flat colours, tiling textures).
- `scripts/flicker_check.gd` finds surfaces that lie exactly on one another (they flicker as the camera moves). Run it after moving walls, frames or anything flush with them: `python tools/shot.py out.png --check-faces`. A door or window frame must stand a little into its opening, never flush with the cut end of the wall.
- `scripts/door.gd` is a door that swings open and shut, for any door: put the node at the hinge and call `build_leaf(width, height, colour)` (or build your own leaf under `leaf`). `open_angle`, `open_time` and `shut_time` set the swing; `passage` is the floor that opens up with it (`building.gd` sets it). The three doors in `street_set.gd`, `building.gd` and `studio_set.gd` are the examples.
- **Anything E can be used on** has four things: `use_name()` (shown over it), `use_spot()` and `use_reach` (where and how near), `label_spot()` (where the name goes), and `use(by)`. Doors and characters have them; add the node to `_usables` in `main.gd`.
- `scripts/travel_menu.gd` is the travel list. The places are the `PLACES` table at the top of `main.gd`: a name, where he arrives, and `"built": false` for one that is listed but not there yet. `_travel_to(id)` in `main.gd` does the move.
- `scripts/place.gd` builds a place from a floor plan, and `scripts/plans/police.gd`, `court.gd` and `crib.gd` are the plans. A plan is written in metres as on a drawing (u from the left wall, v from the back wall): `room` lays a floor, `cross` and `side` put up walls with their doors and windows, `bars` and `rail` do cells and railings, and `prop` reserves floor for a piece of furniture. A building is a stack of bands from the street back, each band one or more rooms side by side; standing in a band, the bands nearer the street are hidden, as in the studio. A second floor is another stack, reached by a `portal` (`scripts/portal.gd`: the stairs); `Props.stairs` is the flight and `Props.stairwell` its top on the floor above, in a room whose floor has a `"hole"` there. The top of `place.gd` has the full list. To add a place: write a plan, add it to `PLANS` and `PLACES` in `main.gd`.
- `scripts/outdoor.gd` puts up the borrowed trees and shrubs (`Outdoor.tree`, `Outdoor.shrub`). `place.gd`'s `fence` is a railing, chain link or board fence with gateways, and `use_point` (`scripts/use_point.gd`) is a spot on the floor E can be used at for anything that is not a door, a person or stairs: `main.gd`'s `_use_point` acts on its id (`outfit:hat`, `outfit:reset`, `sleep`). The newer places keep their own furniture in `scripts/props_<place>.gd`.
- `scripts/props.gd` is the furniture: desks, benches, shelves, cells, the courtroom pieces, kitchen and bedroom things, cars, street furniture. Each takes the place, the band, where on the plan, and which way it faces.
- After changing a plan, run both checks (below): `--check-walk` proves every room can still be walked to, `--check-faces` that nothing flickers.
- `scripts/paper_actor.gd` is the flat character card: which drawing to show, the walk cycle, and stopping at walls, props and other characters. His middle stays `REACH` (0.4 m) from anything beside him and `RADIUS` (0.26 m) from anything in front or behind, so his hands, feet and face never go into a wall or a counter; leave at least 0.85 m between two pieces of furniture he should walk between. Doorways are only a little wider than he is: pushing at an open one he is drawn into line with it (`_step`). Give it a `display_name` and it can be talked to.
- **Holding things** is in `paper_actor.gd` too. `HOLDS` is the table of how each weapon is held for each way he faces, carrying and pointing: where the fist on the grip goes from the shoulder (in arm lengths), the weapon's angle, how much each arm bows, which arm holds, and what is drawn over what. `_hold` turns that into arm angles each frame. The weapons and their fists are drawn in code by `build_weapons.py` (in the art folder's `tools/`) into `assets/weapons/`, with `weapons.json` giving each one's grip, second-hand, butt and muzzle points; `shaders/paper_prop.gdshader` draws them. To judge the holds, `python tools/holds_sheet.py <folder>` photographs every one (see `--lineup` below).
- **Clothes**: `set_outfit({piece: Color})` on a paper actor. The pieces a drawing has are listed in its `rig.json` (`clothes`: the colour each was drawn in), with a `regions*.png` beside each view saying which pixels belong to which piece (`outfit.py` in the art folder's `tools/` makes them, and measures the arms: `arms` in `rig.json`). The colours on the racks are `WARDROBE` in `main.gd`.
- `scripts/wanderer.gd` walks a character about the floor on its own.
- `scripts/talk_box.gd` is the conversation box and runs a conversation from a table like `assets/data/talk_fry.json`: a node is either a list of things the player can say, or one line someone says. The format is at the top of the script. Text is in Bungee (`assets/fonts/`, with its licence, the SIL Open Font License; the font has capitals only).
- `shaders/paper_card.gdshader` moves the limbs inside a drawing without redrawing it: each leg is its own layer that can lift and swing, and each arm bends round its shoulder. The walk cycle in `paper_actor.gd` (`_pose`) only sets its numbers.
- `scripts/paper_face.gd` is the loose face: eyes, brows, mustache, goatee and mouth as small cards on the body card. It holds the expression table, blinks on its own, and flaps the mouth while `talking` is true. To add an expression, add a row to `EXPRESSIONS`: an eye drawing (or a different one per eye), a mouth, a brow, and where each brow sits; optionally `"fx"`, the extras it shows (a sweat drop, tears, a blush, an anger mark: the `FX` table), and `"talk"`, which set of mouths it talks with (plain, happy, angry, sad, scared, sly). The parts themselves are drawn in code by `face_parts.py` in the art folder's `tools/`. On the side profile it shows one eye, one brow and the profile version of the mouth (`parts/side_*.png`). The parts lie exactly on the body card and `shaders/paper_face.gdshader` draws them over it, so they cannot slide against the drawing when the camera is off to one side; eyes, brows, mouth, tears and blush are shown only over bare skin in every view, so a lifted brow goes under a hat and a profile mouth is cut off cleanly by the head outline.
- `assets/characters/e/` is the lead and `assets/characters/fry/` the second character: a drawing per view, `limbs*.png` (which pixels are arm), `legs*.png` (which leg each pixel below the hip belongs to), `parts/*.png` and `rig.json` (where everything sits, in pixels of the body drawing). They are written by two scripts, `build_lead.py` and `build_fry.py`, from the original drawings. Those scripts and drawings are not in this repository (in the full Tattletale working folder they are in `../artifacts/flat-pivot-20261112/tools/`): change the numbers there and run them again (lead first), then `python tools/shot.py --import`. Fry wears shades and a cap, so the only loose face part he shows is the mouth. The side-view mouths (`parts/side_*.png`) are made by `lead_views.profile_mouths`: each is cut to the inside of the head outline, and one that would touch the drawn mustache or goatee is moved up or made smaller until it does not. To check them without the game, paste each on the side drawing where `rig.json` puts it.
- `assets/textures` are 256 px tiles and `assets/characters/option_*.png` are single cut-out drawings. Both were made outside this repository (in the full working folder: `../artifacts/flat-pivot-20261112/`, with the briefs in `briefs/`, the raw images, and `tools/process_art.py`, which keys out the green background and shrinks the textures).

## Screenshots from the command line

For working on the game, not needed to play it. Needs Python 3. Run from this folder; Godot is found the way PLAY.cmd finds it. A screenshot window is a plain 1600 x 900 one on monitor 2 when there is one (`POPUP_MONITOR` picks another; 0 lets Godot choose); it never takes the keyboard and no console window opens, so it does not interrupt whoever is working on the main screen. `python tools/window_check.py out.png` proves it from Windows itself. Inside the full Tattletale working folder it waits for that project's one-Godot-at-a-time lock, so close the Pen Lucy game first.

    python tools/shot.py --import
    python tools/shot.py out.png --cam=angle --char=e
    python tools/shot.py out.png --char=e --close --face=angry
    python tools/shot.py out.png --char=e --at=-1.5,1.6 --walk=1,0,0.8
    python tools/shot.py out.png --at=-0.3,0.9 --fry-at=-1.4,0.5 --do=use,wait:1,hover:1
    python tools/shot.py out.png --at=2.2,-1.9 --do=use,wait:1.2
    python tools/shot.py out.png --do=use,wait:1,go:1.97:5.26,go:0.78:3.24,use,wait:1,go:0.75:1.76

`--lineup=weapon:rig:pose+pose` stands one character (or several: `tre,dee,chuy`) in a row on a plain backdrop, one for each pose, to judge how something is held: a pose is s, f or b (side, front, back), then c or a (carrying, pointing), then optionally m, w or r (mirrored, mid-walk, mid-run); the weapon may be `none`. More steps for `--do=`: `weapon:ak` (or `none`), `aim:1`, `sprint:1`, `face:side` (or `front`, `back`, `left`), `wear:hat:#cc2222` (`wear:` alone undoes it), `day:3`, `arm:TRE:ak:aim` (arm someone else there).

`--walk=x,y,seconds` walks him that way on screen (x right, y towards you) before the picture is taken. `--at=x,z` puts him anywhere on the floor plan (without it he starts on the pavement). `--do=` runs steps after that: `use` (press E), `wait:seconds`, `hover:n`, `pick:n`, `next`, `clickbox` (a mouse click on the talk box), `walk:x:y:seconds` (hold an arrow key: a direction on screen), `go:x:z` (walk straight to that spot; walls, props and shut doors stop him), `travel`, `travelhover:n`, `travelpick:n` (the travel list), `key:M` (a real key press, by name). The last line printed says which room he ended in. `--eye=x,y,z,x,y,z` takes the picture from anywhere (camera position, then the point it looks at). `--check-faces` lists flickering surfaces (see `flicker_check.gd`); `0 overlapping pairs` is clean. `--place=police` (or `court`, `crib`) starts him at that place, `--room=BOOKING` stands him in the room of that name, and `--check-walk` opens every door and reports how much of each room he can reach: `python tools/shot.py out.png --place=court --check-walk --check-faces`.
