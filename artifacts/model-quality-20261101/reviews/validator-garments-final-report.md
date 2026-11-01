# Validator report: final seated-garment regression review (after-r5)

Validator: Claude Opus 5.5 (medium), independent visual review. I made no source edits and ran no engine. Every verdict below rests on rendered images I opened and inspected one by one with the image reader. I did not use code or JSON math as a substitute for looking.

## Context read

- `validator-npc_existing-r3-report.md`: b08 was REVISE because the seated skirt was a horizontal blade.
- `validator-npc_new-r3-report.md`: D5 put b19, b21, b23, b27, b31, h03 and w03 at REVISE.
- `validator-motion-r2-report.md`: seated skirt/tunic blade on b08, b19 and h03.
- `after-r5/garments/garment-evidence.json`. I used it only for pose, LOD and surface metadata:
  - seated poses are 1 surface (the `People.crowd_mesh` seated chair/bench);
  - near standing and walking are 9 surfaces;
  - far walking is 5 surfaces (the baked production proxy).

Each garment sheet is 1920x800 with three panels, in this order:
- front view;
- rear three-quarter view (grey plane);
- side view.

## Images actually viewed (57)

**after-r5 garments: chair, bench and standing_near for all 12 IDs (36 images)**
- b08, b18, b19, b21, b23, b24, b27, b31, b32, h03, w03, w04, each as `<ID>_chair.png`, `<ID>_bench.png` and `<ID>_standing_near.png`.

**after-r5 garments: walk set for the 4 required IDs (12 images)**
- b08, b19, h03, b18, each as `<ID>_walk_left_near.png`, `<ID>_walk_right_near.png` and `<ID>_walk_left_far.png`.

**after-r5 garments: extra LOD spot checks (2 images)**
- `b21_walk_left_far.png` (dress, far proxy)
- `b23_walk_left_far.png` (tunic, far proxy)

**after-r5 unaffected control styles (5 images)**
- `npcs/b01.png`, `npcs/b03.png`, `npcs/b05.png`, `npcs/b06.png`, `npcs/b29.png`

**after-r3 comparison sheets (2 images)**
- `after-r3/garments/b19_chair.png`
- `after-r3/garments/b08_bench.png`

**Not opened**
- Walk sheets for b21, b23, b24, b27, b31, b32, w03 and w04, apart from the two far spot checks above. The brief did not require them, and walking had already passed. I give no new walk verdict for those IDs from images I did not see.
- The other 35 standalone NPC sheets.

None of the images I needed were missing.

## Comparison to r3 (the previous defect)

In `after-r3/garments/b08_bench.png` the skirt was a paper-thin horizontal blade at waist height.
- **Side view:** it ran from about x 1345 to 1650 at y≈480–500, well past the knees.
- **Rear three-quarter view:** it showed as a teal fin sticking out left at about x 775.
- **Front view:** it showed as a flat tray.

`after-r3/garments/b19_chair.png` showed the tunic version of the same defect.
- **Side view:** a horizontal sage blade ending at x≈1430, with a lilac spike tip.
- **Rear three-quarter view:** a fin at x≈830.
- **Front view:** a tray rim.

In after-r5 that geometry is gone on every affected ID. Details follow.

## What R5 changed, as seen in the renders

### Dresses (b08, b21, b31, w03)

**Side view: no blade.** The seated skirt is now a closed, solid lap volume.
- The top surface sits on the thighs from the hip forward.
- The front edge turns down to a vertical hem at about the knee line: x≈1415–1435, y≈480–555.
- The bottom of the volume rests on the chair or bench seat.
- The shins drop straight down from under the hem to flat-planted shoes.
- Nothing sticks out past the knee more than a hem's thickness, and I see no air gap above the lap.

**Front view: an apron block, not a flat shelf.** The dress reads as a boxy apron-like block covering the lap from the waist (y≈465) to just past the seat front (y≈550–555). Both shins come out cleanly below it.

**Rear three-quarter view: the R4 pelvis patch is fixed.** I looked specifically for the rear pelvis patch reported after R4.
- The skirt wraps the rear and sides of the hips continuously, down to the seat surface, on both chair and bench, for all four dresses.
- No skin- or trouser-coloured patch shows through the back of the skirt.
- No fin sticks out sideways.
- The legs are still visible below the seat and are not hidden.
- The resting hand overlaps the side of the skirt and reads as a hand on the lap.

Readability: stylized and rigid, but it reads as a dress over a seated lap. That is acceptable for a low-poly NPC family.

### Tunics (b19, b23, b27, h03)

**Side view: a short, downturned panel.** The tunic front is now short and slopes down from the waist toward mid-thigh.
- The hem trim (lilac on b19/b23/b27, tan on h03) runs diagonally down and back, roughly from x≈1500, y≈470 to x≈1590, y≈525. The near thigh hides part of it.
- The front tip ends around mid-thigh, about 60–70 px short of where the r3 tip was, and well short of the knee.
- Nothing extends horizontally or past the knee.

**Front view:** a narrow flared hem band with trim sits on top of the thighs at y≈465–490. The trousers show below it as they should.

**Rear three-quarter view:**
- **Chair:** the trim edge shows tidily below the arm.
- **Bench:** the tunic forms a closed band around the hips down to the seat, with the trim at its lower edge.
- No fin and no pelvis patch.

**Residual (polish only, not blocking):** in the side view the leading tip of the tunic panel is thin. It sits roughly 10–20 px above the top line of the thigh at this 5 m framing. It reads as cloth tenting slightly over the lap, not as a cantilevered blade. It is not visible as a defect in the front or rear views.

### Waistcoats and shirts (b18, b24, b32, w04)

**Hem position:** on chair and bench, the waistcoat and shirt bottoms now end at the waist (y≈455–465), above the thighs.
- Nothing pushes into or through the lap.
- Front and side views show a clean waistcoat-to-trouser transition.

**No intrusion:** I saw no waistcoat panel intruding into the thighs. The r3 rear-flank stand-off (P9) is not prominent in the seated views.

**Polish:** in the bench rear three-quarter view for b18, b24, b32 and w04, the trouser seat over the hips shows as a slightly faceted, lumpy dark form (x≈900–1020, y≈465–540). It is trouser-coloured, closed and grounded on the seat. It is not a skin patch, not clipping and not a floating piece. Treat it as cosmetic.

### Standing, walking and LOD (regression check)

**Standing:** all 12 `standing_near` sheets match the accepted r3 standing state.
- Dresses are clean A-line bells.
- Tunic hems are closed trapezoids with continuous trim and no hip triangles.
- Waistcoats sit over shirt and tie.
- Shoes are grounded.
- No regression.

**Walking (near, left and right) for b08, b19, h03 and b18:**
- The hem stays closed, and the legs come out cleanly beneath it in front, rear three-quarter and side views.
- I saw no thigh pushing through the skirt or tunic.
- The far crossing of the legs in the rear three-quarter view is projection; the side views show a clean stride.

**Far LOD (`walk_left_far`, baked 5-surface proxies) for b08, b19, h03, b18, and the spot checks on b21 and b23:**
- Visually equivalent to the near renders.
- No holes, missing garment parts or popping.

**Bodies on seat (chair and bench, all 12):**
- Hips are on the seat and torsos rest against the chair back.
- Feet are flat on the floor and hands rest at the sides.
- No leg clips through a garment or fixture.

### Unaffected control styles

These are standing sheets: front, rear three-quarter and head close-up.

| Control | Result |
|---|---|
| b01 | Crew cap, shirt and collar tabs are clean. |
| b03 | Natural crown and hoodie are clean. |
| b05 | Crop, beard inside the jaw, jacket. |
| b06 | Loc curtain, throat clear. |
| b29 | Cardigan and swept pixie. The thin crown seam (old polish P8) is still faintly visible in the close-up. |

All five match their r3 PASS state. The shared seated-garment change caused no regression.

## Per-ID verdicts

| ID | Garment | r3 status | Images viewed (after-r5 unless noted) | Verdict | Concrete findings |
|---|---|---|---|---|---|
| b08 | teal dress | REVISE | chair, bench, standing_near, walk_left_near, walk_right_near, walk_left_far; r3 b08_bench (comparison) | **PASS** | The blade is gone. Side: a lap volume with a turned-down hem at about the knee (x≈1415), resting on the seat. Rear three-quarter (chair and bench): the skirt fully encloses rear and sides of the pelvis down to the seat, no patch, no fin. Front: apron block with the shins below. Walk near/far: closed bell, legs clear. Standing unchanged. |
| b18 | copper waistcoat | PASS (control) | chair, bench, standing_near, walk_left_near, walk_right_near, walk_left_far | **PASS** | The waistcoat hem ends at the waist above the thighs when seated, with no intrusion. Walk near/far clean. Polish: faceted trouser seat in the bench rear three-quarter view. |
| b19 | sage tunic | REVISE | chair, bench, standing_near, walk_left_near, walk_right_near, walk_left_far; r3 b19_chair (comparison) | **PASS** | The r3 horizontal blade to x≈1430 and the rear fin are gone. Now a short downturned panel ending about mid-thigh, with the lilac trim sloping down. Front: hem band on the lap. Rear: tidy trim, no fin. Polish: thin leading tip about 10–20 px above the thigh in side view. Walk near/far clean. |
| b21 | cranberry dress | REVISE (shared) | chair, bench, standing_near, walk_left_far (spot check) | **PASS** | Same correct seated dress volume as b08. Side hem turns down at the knee and rests on the seat. Rear three-quarter encloses the hips with no patch. Standing and far walk clean. |
| b23 | indigo tunic | REVISE (shared) | chair, bench, standing_near, walk_left_far (spot check) | **PASS** | Seated tunic panel turns down and ends mid-thigh. Lilac trim tidy front and rear, closed band around the hips on the bench. No blade or fin. Same tip-lift polish as b19. Standing and far walk clean. |
| b24 | moss waistcoat | PASS | chair, bench, standing_near | **PASS** | Waistcoat bottom sits above the thighs when seated, with no lap intrusion. Standing clean. Polish: faceted trouser seat in the bench rear three-quarter view. |
| b27 | peacock tunic | REVISE (shared) | chair, bench, standing_near | **PASS** | Downturned seated panel ends mid-thigh, with lilac trim. Closed rear band on the bench. No blade or fin. Braids attached. Standing clean. |
| b31 | olive dress | REVISE (shared) | chair, bench, standing_near | **PASS** | Seated dress volume with a turned-down hem at the knee, enclosing the rear of the pelvis on chair and bench. Shins clear below. Standing clean. |
| b32 | cream waistcoat | PASS | chair, bench, standing_near | **PASS** | Shirt and waistcoat hem above the thighs when seated, with no intrusion. Standing clean. Polish: faceted trouser seat (bench rear three-quarter) and low cream-on-cream contrast (P10). |
| h03 | blue tunic | REVISE | chair, bench, standing_near, walk_left_near, walk_right_near, walk_left_far | **PASS** | r3 blade and fin gone. Downturned seated panel with tan trim ends mid-thigh. Closed rear band on the bench. Ponytail fine. Walk near/far clean. Same tip-lift polish as b19. |
| w03 | sage dress | REVISE (shared) | chair, bench, standing_near | **PASS** | Seated dress volume with a turned-down knee hem, full rear and side enclosure, legs visible below the seat. Standing clean. |
| w04 | navy waistcoat | PASS | chair, bench, standing_near | **PASS** | Waistcoat bottom above the thighs when seated, with no intrusion. Standing clean. Polish: faceted trouser seat in the bench rear three-quarter view. |

**Totals: 12 PASS, 0 REVISE, 0 BLOCKED.**

## Resolution of the previously REVISE IDs (shared skirt/tunic D5)

**The final seated model revision resolves D5 for all eight IDs that were previously REVISE: b08, b19, b21, b23, b27, b31, h03 and w03.**

| ID | Previously REVISE | Resolved in after-r5? |
|---|---|---|
| b08 | yes (seen directly in r3) | **Yes.** The blade is replaced by a lap volume with a downturned hem. The R4 rear pelvis patch is also fixed. |
| b19 | yes (seen directly in r3) | **Yes.** |
| b21 | yes (shared geometry, not seen in r3) | **Yes.** Seated renders now seen and correct. |
| b23 | yes (shared geometry, not seen in r3) | **Yes.** Seated renders now seen and correct. |
| b27 | yes (shared geometry, not seen in r3) | **Yes.** Seated renders now seen and correct. |
| b31 | yes (shared geometry, not seen in r3) | **Yes.** Seated renders now seen and correct. |
| h03 | yes (seen directly in r3) | **Yes.** |
| w03 | yes (shared geometry, not seen in r3) | **Yes.** Seated renders now seen and correct. |

These checks hold across all eight:
- no flat floating lap blade;
- nothing sticks out past the knee;
- no rear or side fin;
- no rear pelvis patch;
- no leg clipping;
- feet and hips grounded.

The R5 shirt/waistcoat adjustment (b18, b24, b32, w04) left those IDs clean when seated and caused no regressions.

## Remaining items (optional polish, none blocking)

1. **Tunic tip lift (b19, b23, b27, h03).** In side view, the thin front tip of the seated panel sits about 10–20 px above the thigh at 5 m.
   - Optional fix: lower the tip vertices a little onto the thigh line.
2. **Trouser seat faceting (b18, b24, b32, w04).** In the bench rear three-quarter view, the trouser seat is faceted and looks lumpy.
3. **Boxy seated dress.** The front view reads as a squared-off apron block. It is acceptable stylization.
4. **Carry-overs from earlier rounds:**
   - elbow cuff tabs on short sleeves (P1);
   - b29 crown seam (P8);
   - b32 low layering contrast (P10);
   - b08 and h02 share a braid head.

## Scope limits

- These renders are discrete deterministic poses with no cloth simulation.
- The bench is a neutral fixture block.
- Far renders use baked production proxies.
- Source-geometry and math checks are separate from this visual acceptance and were not performed here.

## Overall finding

R5 fixes the last open defect, the shared seated skirt/tunic flat blade.
- **Dresses:** now a closed lap volume with a turned-down hem at the knee, enclosing the pelvis at the rear and sides. The R4 rear patch is gone and the legs are still visible.
- **Tunics:** now a short panel that slopes down to mid-thigh.
- **Waistcoats and shirts:** end above the thighs.

I found no regression in standing, near walking or far-LOD walking, or in the five unaffected control styles.

**Result: 12 / 12 PASS. All eight previously REVISE skirt/tunic IDs are resolved.**
