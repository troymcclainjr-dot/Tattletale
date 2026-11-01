# Validator report: motion integration, round 2 (corrected production poses)

Validator: Opus 5.5 (visual validation only; no implementation, no engine runs)
Date: 2026-11-01

## Evidence reviewed

- **Images:** I opened and inspected all 23 PNGs in `lineup/` and all 24 PNGs in `after-r3/garments/`, one by one.
- **JSON:** I read `motion-evidence.json`, `child-pose-evidence.json` and `garment-evidence.json` for the stated limits only. Every verdict below rests on what is visible in the images.
- **Prior report:** `validator-motion-report.md`, for the four open defects.

## Overall verdict: **REVISE**

All four defects from round 1 are visibly fixed, and I found no regressions in the same-scale lineup or the bicycle. One new must-fix showed up in the garment sheets: **seated skirts and tunics collapse into a rigid horizontal blade**. It affects b08, b19 and h03, on both chair and bench. Nothing is BLOCKED.

## Accepted scope limits (not counted as defects)

- The poses are fixed samples, not continuous gameplay. There is no cloth simulation and no collision check.
- **Bicycle:** it uses production replacement pedal-legs and shoes, not skinned IK. The character's own LegL and LegR are hidden.
- **Phone:** it is a first-person viewmodel on Camera3D. There is no third-person phone pose.
- **Bench:** the bench is a neutral fixture block.
- **Rear-view labels:** the labels in `03_walk_rear.png` are mirrored, which comes from the capture harness.

## Stylization vs. defect

These are deliberate style, and I treated them as fine:

- Puffed shoulder caps.
- Flat-shaded faceted clay.
- Rigid, faceted bell skirts that do not swing while walking.
- Large cartoon eyes on the children.
- The infant curl.
- Faceted box pedal-legs and white box shoes on the bicycle.
- The rounded capsule cup.
- The infant crawling with legs fairly straight and hips high (a bear-crawl). That is a stylized gait, not a contact error, now that hands and feet share one support line.

## Round-1 defects re-checked

| Round-1 defect | Status | What I saw |
|---|---|---|
| Binocular hands off the prop | **Fixed** | `04`: both hands are raised to face level. One fist wraps the screen-left barrel and the other closes on the screen-right barrel. The forearms fold in close to the face. There is no V-pose and no gap between hand and prop. |
| b08 skirt splitting while walking | **Fixed** | Phases 1 and 3 and `03` rear show the teal skirt as a closed bell with no dark wedge on either side. The `after-r3` walk sheets for b08 (left and right, near and far, in front, rear-3/4 and side views) show the legs coming out cleanly under an intact hem. |
| Baby hands floating above the feet | **Fixed** | Detailed below. |
| Timmy legs converging | **Fixed (camera projection)** | Detailed below. |

## Findings by image

### 01 Same-scale front lineup: PASS (no regression)

- All seven adults share one foot line, and the 1.80 m rail meets the tops of the heads of 2-PACK and w01.
- The height order matches the nominal heights:
  - w04 rises above the rail.
  - b24 is at or just above the rail.
  - b01 and b17 sit below it.
  - b08 is the shortest.
- 2-PACK reads as an ordinary adult among the NPCs. His bulk comes from his torso, not his height.
- The player's identity elements are all present: headband, chain, sash, belly text, waistband, jeans and sneakers.

### 02 Walk phases 0–3 and 03 rear: PASS

- **Neutral phases:** phases 0 and 2 are the neutral sine crossings and are identical to the rest pose. That is expected.
- **Swing phases:** phases 1 and 3 mirror each other. A lifted sole tilts toward the camera and the opposite arm swings, on all seven characters.
- **Skirt:** b08's skirt stays closed in every frame.
- **Rear view:** the sash wraps around the back, the knotted headband tails and the back text are in place, and the hair caps stay attached.
- I saw no detached parts, stretching or crossed lanes.

### 04 Player binoculars: PASS

- Both hands are on the binocular barrels, and the prop sits over the eyes just under the headband.
- Minor and not blocking: the screen-right fist overlaps the brow and temple area. It reads as a hand pressed to the face, not as clipping.

### 05 Player cup: PASS (unchanged)

- The cup and straw sit at the top of the extended left fist. Nothing is floating.

### 06 Bicycle pedal phases 0–3: PASS (no regression)

- In all four frames, both hands wrap the grip ends of the bar.
- The shoes change position from frame to frame:
  - Phase 1: near shoe low, far shoe high.
  - Phase 3: the reverse.
  - Phases 0 and 2: both shoes at mid-stroke in opposite front and back arrangements.
- Thigh and shin lengths look the same in every frame, so I saw no stretching.
- The near shin passes in front of the down tube, which is correct for the near side. I saw no leg passing through a tube or a wheel.
- The original legs are hidden, and I saw no second set of legs.

### 07 Bicycle side contact: PASS (no regression)

- The hand is on the bar end.
- Both shoes rest on dark pedal blocks stacked above and below the bottom bracket.
- The hips sit over the junction of the seat tube and top tube.
- The saddle is still mostly hidden by the jeans. That was already noted in round 1 and is not blocking.

### 08 Phone viewmodel: PASS (unchanged)

- The dark handset with its earpiece sits at the lower right, held by a cropped skin-toned hand.
- The screen is a blank teal panel.
- The rail sits at NPC head height, which is consistent with the player's eye height.

### 09 Baby rest: PASS

- The large head with its curl, the onesie with the diaper bulge, the rolled cuffs and the short legs with bare feet all read unmistakably as an infant.

### 10 Crawl (3/4 view), 11 crawl side, and steps 0 and 1: PASS

- **Hand and foot contact:**
  - In the side view, the bottoms of the closed fists and the soles of the feet end on the same horizontal line, at about y≈715 px.
  - In the 3/4 view, the fists reach the same lowest line as the feet (about y≈735–750 px).
  - Round 1 had a gap of 70–80 px; it is gone.
- **Step alternation:**
  - Step 0: one arm is forward and the opposite leg is back.
  - Step 1: the reverse.
  - Each hand and foot ends on the support line in both steps, and I saw no hierarchy breaks.
- **Waist ridge:** the vertical ridge where the onesie torso meets the diaper is still faintly visible in the side views. I'd call it cosmetic and non-blocking.
- **Evidence gap (not a model defect):** I could not find a separate baby contact gallery with the floor at true 0 and contact shadows.
  - The crawl images contain no visible floor edge and no cast shadow. In contrast, `12` and `13` do show a cast shadow on the floor.
  - Because of this, the images let me confirm that hands and feet are coplanar, but not that they touch the floor itself.
  - If that gallery exists, it was not in `lineup/` or `after-r3/`.

### 12 Timmy rest: PASS

- Clearly an older child, distinct from both the infant and the adults.

### 13, 14, 15 Timmy walk: PASS

- **`13` (oblique, π/2):** the shoes still overlap in projection.
- **`14` (straight front):**
  - The two yellow trouser legs hang in separate vertical lanes with a clear dark gap between them, from the crotch down to the cuffs.
  - The planted red shoe and the lifted shoe (grey sole toward the camera) sit side by side, roughly a shoe-width apart, and do not touch.
  - No leg crosses the midline.
- **`15` (side):** a clear stride. The front heel strikes and the rear toe pushes off, and the two legs form a clean inverted V with no interpenetration.
- **Conclusion:** the round-1 overlap came from the oblique camera angle, not from leg yaw. This agrees with the stated 3.9 cm left/right separation.

### after-r3 garments: walking (b08, b19, h03, b18): PASS

- **Views checked:** walk left and right (near) and walk left (far), in front, rear-3/4 and side views.
- **b08:** the teal bell skirt stays closed and intact while both legs swing. There is no wedge, split, or leg breaking through the hem.
- **b19:** the sage tunic with its lilac hem stays intact, and the legs come out cleanly below it.
- **h03:** the blue tunic with its cream hem stays intact, and the legs come out cleanly below it.
- **b18 (vest, control):** clean.
- **Rear-3/4 views:** where the legs appear to cross, that is projection. The side views of the same poses show a clean stride.
- **Far LOD:** the far images (5 surfaces) are visually the same as the near images at this framing. I saw no popping or missing parts.
- **Standing:** clean for all four.

### after-r3 garments: seated chair and bench, b08, b19, h03: **REVISE (must-fix)**

**Front view.** The skirt or tunic hem becomes a flat, horizontal, plate-like rim at hip height. The thighs come out underneath it, and the plate does not drape over them.

**Side view.** The garment front is a thin, rigid, straight blade that sticks out level from the waist and floats above the thighs. It does not rest on the lap and does not fold over the knees. I saw this in both chair and bench poses for all three characters:

| Character | Garment | Blade tip vs. knee | Gap above thigh | Visible trim at tip |
|---|---|---|---|---|
| b08 | Skirt | Tip at about x≈1345 px; front of knees at about x≈1435 px. The blade sticks out about 90 px beyond the knees. Worst case. | About 10–15 px of air between the blade and the top of the thigh | None |
| b19 | Tunic | Ends at about the front of the knee (x≈1430 px) | Floats above the thigh | Lilac hem trim shows as a sharp pale sliver at the tip |
| h03 | Tunic | Ends at about the front of the knee (x≈1420 px) | Floats above the thigh | Cream hem trim shows as a sharp pale sliver at the tip |

**Rear-3/4 view.** The blade pokes out past the left edge of the body as a thin teal, sage or blue fin, at about x≈775 px for b08 and x≈830 px for b19 and h03. It reads clearly as a detached sheet rather than cloth.

**Control.** b18 (vest and trousers, no skirt) seats cleanly on both chair and bench. The defect is specific to the skirt and tunic in the seated crowd mesh.

**Expected result.** The seated hem should lie on and follow the top of the thighs, ending at or just short of the knees. It should not have a free horizontal edge, should not float, and should not protrude past the knee. A stylized rigid drape is fine; a level plane cantilevered from the waist is not.

**Not defects in the seated sheets:** the seat height, feet on the floor, hands resting at the sides and the torso against the chair back all look correct for b08, b19, h03 and b18.

## Remaining must-fix (complete list)

1. **Seated skirt and tunic blade.** This affects b08 (skirt), b19 (tunic) and h03 (tunic), in both the `chair` and `bench` poses (`People.crowd_mesh` seated). In every view the hem becomes a rigid horizontal plane at hip height that floats above the thighs:
   - Front: a flat rim.
   - Side: a cantilevered blade. For b08 it reaches about 90 px past the knee, with the hem trim visible as a pale sliver at the tip for b19 and h03.
   - Rear-3/4: a thin fin sticking out beyond the silhouette.

   The hem needs to drape onto the lap and end at the knees.

There are no other must-fix items. One non-blocking item is open: the infant crawl images do not show floor contact or contact shadows, so ground contact relative to the floor is not independently visible. Hand and foot coplanarity is confirmed.

## Verdict summary

| Model / pose | Verdict |
|---|---|
| Same-scale lineup and player size | PASS |
| Adult walk, phases 0–3 and rear (all 7, including the b08 skirt) | PASS |
| Player binoculars | PASS |
| Player cup | PASS |
| Bicycle pedalling (4 phases) | PASS |
| Bicycle side contact | PASS |
| Phone viewmodel | PASS |
| Baby rest | PASS |
| Baby crawl (3/4, side, step 0, step 1) | PASS |
| Timmy rest | PASS |
| Timmy walk (oblique, front, side) | PASS |
| Garments: standing (b08, b19, h03, b18) | PASS |
| Garments: walking near and far (b08, b19, h03, b18) | PASS |
| Garments: seated chair and bench, b18 | PASS |
| Garments: seated chair and bench, b08 | REVISE |
| Garments: seated chair and bench, b19 | REVISE |
| Garments: seated chair and bench, h03 | REVISE |
