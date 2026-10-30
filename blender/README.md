# Tattletale 2-Pack: Blender assets

Every model in the Godot port is built by a Python script in `blender/assets/`, using the
shared helpers in `claykit.py`. The scripts are the source of truth. Each run writes:

- `godot/assets/models/<id>.glb` (characters in `godot/assets/models/characters/`), which Godot imports
- `blender/blend/<id>.blend`, the same model for hand editing
- `.work/previews/<id>.png`, a 2x2 preview sheet (not committed)

```bash
"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b --factory-startup --python blender/assets/<script>.py
python godot/tools/godot_preview.py res://assets/models/<id>.glb .work/previews/<id>_godot.png
```

The second command renders the model inside Godot with the game's shared surface shader and lighting.
That render is the one that counts.

## Art direction: clean stylized surfaces

Keep each asset's identity, palette, scale, position and function. Use clean base colors
and material-appropriate roughness. Do not add blanket grain, thumbprint bumps, mottling,
plasticine sheen, or random deformation to make assets look like clay. The legacy `clay_`
material names remain for compatibility; they now render as clean surfaces.

Use readable silhouettes and purposeful details such as frames, sills, seams, handles
and lettering. Preserve the owners' exact wording. Existing modeled shapes remain;
this material correction does not rebuild character or building geometry.

Budget: props 500-8k triangles, buildings up to about 40k, characters about 10k-25k.
Join static parts into a few meshes to keep node counts manageable.

## Conventions (Godot depends on these)

- **Units and axes.** 1 unit = 1 m. Build in GAME coordinates with the claykit helpers
  (x east, y up, z toward the street; the houses' front walls are at z = -7, the street is z 0..14).
  Local assets face game **+z** (Blender's Front view) unless their entry below says otherwise.
- **Origins.** World-space assets: Blender origin = game origin, everything at its real
  position. Local assets: origin at the ground contact point (bottom center) unless stated.
- **Materials** are named by `ck.mat()`: `clay_`, `gloss_`, `metal_`, `glow_`, `glass_` + hex + value.
  Godot rebuilds them from the name (`godot/scripts/core/clay_lib.gd`). No image textures, no UV work.
  Anything the game switches on and off or recolors must be its **own object with its own
  material**, named as listed below.
- **Node names** listed below are what the game code looks up. Use them exactly. Name other
  objects descriptively (`House_m12_Door`, not `box.031`).
- **Collision** is handled in code (the same circles and boxes as the JS), so don't add collision meshes.
  Keep footprints where the JS has them so the invisible walls still match the visible ones.

## Asset list

`W` = world-space (instanced at the origin), `L` = local (the game places it). Positions are game coords.

| id | kind | contents (see the JS for exact numbers) | names the code uses |
|---|---|---|---|
| `street` | W | world.js `buildBlock` ground: asphalt, sidewalks, curb, grass strip, lane dashes, cracks, crosswalk, fire lane curb and painted "FIRE LANE", end walls, chain-link fence, power line and insulators; `buildStage2` stop line | none. Walkable tops must stay at the `groundY` heights: street 0, north sidewalk 0.16 (z -3.2..0), grass 0.12 (z < -3.2), south sidewalk 0.16 (z > 13) |
| `houses` | W | 8 row houses (x -30,-24,-18,-12,-6,6,12,17), 2-Pack's house (x 0), graffiti on -6, 6, 12 | one object per house: `House_m30` ... `House_p17`, `House_2Pack` |
| `shops` | W | Corner Store, Bank, Liquor, Precinct 9 (sign, door, blue globes, steps, donut box) | `CornerStore`, `Bank`, `Liquor`, `Precinct9` |
| `furniture` | W | street lamps, hydrants, trash cans, house mailboxes, blue mail drop, "THE JOHNSONS" sign, pines | none |
| `lawn` | L at (11.5, 0.12, -5.0) | Mrs. Johnson's lawn patch, 5.4 x 3.4 | `Brown` (#8a6a3a) and `Green` (#6a8a3a) versions, toggled |
| `gary_spot` | W | welcome mat and "WELCOME", shopping cart and bags, "WELCOME HOME" sign, "GARY" mailbox, black kettle grill, Gary's blanket and clutter | none (Gary himself is a character) |
| `payphone` | L at (x, 0.12, -3.0) ×3 | post, blue box, plate, handset, keypad, "PHONE", "OUT OF ORDER" sticker | none |
| `lemonade_stand` | L at (16.5, 0.12, -3.05) | stand, "LEMONADE 25 CENTS", pitcher, cups | `SignOpen`, `SignClosed` |
| `cop_car` | L, faces **+x** | black and white car, "POLICE" both sides, light bar | `LightRed`, `LightBlue` (own glow materials), `WheelFL` `WheelFR` `WheelRL` `WheelRR` (pivots at wheel centers), `Headlights` |
| `sedan` | L, faces **+x** | Mama's pink car, roof pom | `Plate` (empty at the rear plate's center, facing -x; the game puts the plate number there), `WheelFL`...`WheelRR` |
| `traffic_light` | L at (-0.5, 0, 13.6) | pole, arm over the far lane, signal head facing -x | `LampRed`, `LampYellow`, `LampGreen` (own glow materials) |
| `hammock` | L at (-17.5, 0, -5.0) | two posts at x ±1.4, hammock bed | none |
| `county_jail` | L at (-9.0, 0.12, -4.7) | tiny barred cage, "COUNTY JAIL" | none |
| `ice_cream_cart` | L at (24.6, 0.16, -2.2) | cart, pole, pink and white umbrella, wheels, "ICE CREAM" on the -x side | none |
| `cash_bill` | L, origin at center | a dropped bill (glows a little) | none |
| `squirrel` | L, faces +z | the squirrel with Gary's sandwich | `Tail`, `Sandwich` |
| `characters/<id>` | L, faces +z | see Characters | see Characters |

## Characters: segmented clay puppets

The game poses everyone procedurally every frame (`pose()` in characters.js) by rotating limb
pivots, exactly as the JS does. So characters are **rigid parts under pivot empties**, not
skinned meshes. Hide the joints the way a puppet maker would (sleeves over shoulders, a
pelvis under the hips). The shared builder is `blender/lib/person.py`.

Hierarchy (empties are pivots; every position is relative to the parent; H = character height):

```
Rig                     origin at the feet, faces +z
├─ LegR   (-0.085H, 0.47H, 0)   hip pivot; pants leg and shoe hang down to y = -0.47H
├─ LegL   (+0.085H, 0.47H, 0)
└─ Body   (0, 0.47H, 0)         pelvis, torso, shoulders
   ├─ ArmR (-0.185H, 0.31H, 0)  shoulder pivot; sleeve, then the hand
   │  └─ HandR (0, -0.30H, 0)   empty at the hand's center (held props attach here)
   ├─ ArmL (+0.185H, 0.31H, 0)
   │  └─ HandL (0, -0.30H, 0)
   └─ Head (0, 0.36H, 0)        neck pivot; head sphere center at (0, 0.165H, 0), radius 0.115H
      └─ Mouth (0, 0.115H, 0.1H)  dark mouth, modeled OPEN, node scale exactly (1,1,1):
                                   the game squashes its local y to 0.3 when closed
```

The character's right side is -x. Keep these pivot positions and limb lengths. Poses like
"binoculars to the eyes" (arms at -2.45 rad) depend on them. Improve the **shapes**: sculpted
heads with brow, nose, ears and cheeks, eyes with lids and highlights, mitten hands with a
thumb, shoes with soles, cuffs, collars, hems, fabric creases, hair sculpted in clay strands.
Heights from the JS: 2-Pack 1.8, Ricky 1.76, Grandma 1.5, Gary 1.72, Timmy 0.95, mailman 1.75,
Dan 1.8, Steve 1.88, Timmy's mama 1.68, Daddy 1.8, vendor 1.78, the four people in line
1.7 / 1.85 / 1.6 / 1.78, baby 0.55.

Accessory nodes the code toggles or moves (exact names):
`two_pack`: `Binoculars` (child of Head, hidden by default), `Cup` (child of HandL, hidden).
`cop_dan`, `cop_steve`: `Donut` (child of HandR). `mailman`: `Letter` (child of HandR).
`gary`: `Pipe` (child of HandR) with `Ember` (own glow material) at its bowl.
Everything else (bandana, sash, mask, money bag, hats, walker, satchel) is a permanent part.
