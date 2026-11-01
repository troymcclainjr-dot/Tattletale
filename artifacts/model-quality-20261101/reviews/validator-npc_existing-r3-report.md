# Validator report r3 (final): existing 20 NPC styles

Validator: Claude Opus 5.5 (independent visual review). I made no source edits, ran no engine and applied no fixes.

## Coverage: images actually viewed this round

- **All 20 after-r3 NPC sheets:** `after-r3/npcs/<ID>.png` for b01–b16, h01, h02, w01, w02. Each sheet has a front full body, a rear three-quarter full body and a head close-up.
- **All 24 garment pose sheets** in `after-r3/garments/`, for b08, b19, h03 and b18. For each ID I viewed standing_near, walk_left_near, walk_right_near, walk_left_far, chair and bench. Each sheet has front, rear three-quarter and side views.
- **Player reference:** `after-r2/cast/two_pack.png`. There is no `after-r3/cast/` folder, and the player was not in the r3 change.
- **Context files read:**
  - my prior `validator-npc_existing-r2-report.md` and `validator-npc_existing-r2-verdicts.json`;
  - `npc-report.md` ("R3 garment and scalp fit" section);
  - `after-r3/garments/garment-evidence.json`;
  - the b08 and h02 catalog entries in `npc-model-catalog.json`.
- **Not re-opened:** the `before/` and `after-r1/` images. As instructed, I relied on my r2 report for them; it records that I viewed all 60 of those images.
- **Missing images:** none.

Identity labels come only from the authored catalog. For example, b08 is authored as "teal dress and braided crown".

**Coverage: 20 / 20 IDs, 45 images viewed this round.**

## Recheck of the r3 must-fix items

| Item | IDs | after-r3 result |
|---|---|---|
| Bun/ponytail scalp-shell spikes below the ear | b02, b10, b14, w02 | **Fixed.** In all four close-ups the side rim now stops at or above the ear root, and nothing hangs onto the cheek or jaw. In the front full-body views, the light ticks beside the jaw on b14 (silver) and w02 (copper) are gone. Each rear view still shows a covered nape and an attached bun or ponytail. I also checked h03 (ponytail module 6) in the garment sheets: it has no spike in any of the three views. |
| Trouser triangles at the tunic hip | b19 (and h03; b23/b27 are outside this gallery) | **Fixed for the IDs I viewed.** In the standing and walking b19 and h03 sheets, the tunic hem forms a closed band, and no trouser triangles show at the hips from the front, rear or side. b23 and b27 are not in the garment gallery or my scope, so I have not seen them. |
| Skirt clearance while walking | b08 (and b19/h03 tunics) | **Fixed.** In both near walk poses and the far walk pose, b08's A-line skirt stays clear of the striding thighs: legs come out under the hem with no thigh pushing through the fabric in any view. The tunics on b19 and h03 behave the same. Feet are planted in every walk frame. The far-LOD sheets match the near ones, with no lost or holed garment. |

## New finding from the garment gallery (seated poses)

The seated garment defect described here is in the seated crowd mesh. It is not on the scoped must-fix list. I am escalating it anyway, because:
- you asked me to confirm that cloth reads correctly in the chair and bench poses;
- the base acceptance bar excludes obvious broken geometry.

**In the seated pose, the skirt or tunic flattens into a horizontal blade.** It looks the same in `b08_chair.png` and `b08_bench.png`:
- **Side view:** the skirt is a thin flat sheet at waist height. It sticks straight forward past the knees (about x 1345 vs the knees at about x 1440) and floats above the thighs instead of draping over the lap.
- **Rear three-quarter view:** it reads as a thin teal fin sticking out to the left of the chair back.
- **Front view:** it reads as a flat shelf or tray around the waist.

b19 and h03 show the same blade with a shorter reach (see the side views of `b19_chair`, `b19_bench`, `h03_chair` and `h03_bench`). The b18 control (waistcoat over trousers) sits cleanly. That points to the seated skirt/tunic cross-section ("seated/far modules share the corrected cross-section"), not to the seated body.

Apart from that, seated grounding is good for all four IDs:
- feet are flat on the floor;
- thighs rest on the chair or bench seat with no float or sink.

I did not view seated renders from r2, so I can't say whether this is a regression or pre-existing.

## Per-ID verdicts (after-r3)

| ID | Images seen (r3) | Verdict | Visual evidence |
|---|---|---|---|
| b01 | npcs/b01 | PASS | The crew cap is closed and the face reads. Shoes are grounded. Unchanged from r2. Polish: elbow cuff tabs. |
| b02 | npcs/b02 | PASS | **r2 spike fixed:** the left side of the close-up is clean below the ear. The bun and nape are covered in the rear view. |
| b03 | npcs/b03 | PASS | Compact natural crown that is distinct from b09 and b12. Hoodie is fine. No defects. |
| b04 | npcs/b04 | PASS | The bob covers the back of the head and the fringe is intact. Face is clean. Polish: faint rear parting notch. |
| b05 | npcs/b05 | PASS | The beard sits inside the jaw and the crop is clean. I can no longer see the r2 jaw-corner fleck in the rear view. |
| b06 | npcs/b06 | PASS | Full curtain of locs at the back, and the throat is clear. |
| b07 | npcs/b07 | PASS | The silver crop is a closed cap, and the grey beard fits the chin. Polish: elbow cuff tabs. |
| b08 | npcs/b08 + 6 garments/b08_* | **REVISE** | The standing sheet is clean: the back of the head is covered, the A-line dress matches the authored "teal dress", and there are no hip triangles. Walking skirt clearance passes near and far. **Must fix: in the chair and bench poses the skirt is a horizontal blade sticking out past the knees** (see the seated finding above). Polish: still not readable as a "braided crown", and shares its head with h02. |
| b09 | npcs/b09 | PASS | The rounded afro is wider than b03, and the features read. No defects. |
| b10 | npcs/b10 | PASS | **r2 spike fixed:** the left side of the close-up is clean. The ponytail is attached and has a small hair tie. |
| b11 | npcs/b11 | PASS | The crop is closed and the beard fits the chin. Polo is fine. |
| b12 | npcs/b12 | PASS | Distinct tall dome. Clean face. |
| b13 | npcs/b13 | PASS | Clean bald head and the beard sits inside the jaw. I can no longer see the r2 rear fleck. |
| b14 | npcs/b14 | PASS | **r2 spikes fixed:** both sides of the close-up are clean, and the front full-body view has no jaw ticks. The silver bun covers the back of the head. |
| b15 | npcs/b15 | PASS | The neck is clear and the rear locs layer over the hood. Polish: authored "tied locs" read as loose. |
| b16 | npcs/b16 | PASS | Bob coverage is good. Polish: the tiny dark dash at the right temple is still visible in the close-up. |
| h01 | npcs/h01 | PASS | Clean crop and beard. Polish: the authored "swept hair" still reads as the same crop as b05 and b11. |
| h02 | npcs/h02 | PASS | The back of the head is covered and the braid strands are attached. Polish: same head as b08. |
| w01 | npcs/w01 | PASS | The sandy crop and beard are clean. Polish: elbow tabs. |
| w02 | npcs/w02 | PASS | **r2 spikes fixed:** both sides of the close-up are clean against the background. The copper ponytail is attached. |

**Totals: 19 PASS, 1 REVISE, 0 BLOCKED.**

## Checks across all 20 IDs

- **Scale and grounding:** head heights and shoe lines are unchanged from r2 and still compatible with the `two_pack` player. Every shoe sits flat on the ground plane.
- **Material:** I saw no flicker, z-fighting or noise. Flat shared palettes.
- **Palette:** I treated the r2 sRGB decode as the correct, deliberate fix and am not asking for any palette change.
- **Shared-change regressions:** the r3 scalp-rim and garment edits caused no new artifacts on the 16 IDs that were already passing.
- **Performance:** according to the worker report, the budgets are unchanged:
  - high LOD: 3,967 standing, 3,959 chair, 3,887 bench;
  - far LOD: 720 standing, 768 chair, 720 bench;
  - all under the existing 4,500/900 caps, with one material per crowd pose.

  The fixes involved no extra geometry, and my verdicts are based on the images.

## Actionable defects

### Must fix (cause the 1 REVISE)

1. **The skirt/tunic flattens into a blade in the chair and bench crowd poses.**
   - b08 shows it in my scope. b19 and h03 show it in the same gallery; their verdicts belong to the new-20 validator.
   - Fix: in the seated module, drape the hem down over the thighs toward the knee, roughly following the thigh angle, rather than extending the standing cross-section horizontally from the waist.
   - Check in the side view: no fabric should extend past the knee or float above the lap.
   - No extra triangles should be needed.

### Optional polish (no change to verdicts)

2. Elbow-cuff hem tabs on short sleeves (b01, b07, w01, and visible on the b08/b19/h03 garment sheets).
3. b04 has a faint rear parting notch. b16 has a small dark dash at the right temple.
4. Label read only: b15's "tied locs", h01's "swept hair" (same crop as b05/b11), and b08/h02 sharing the same braid head, which doesn't read as a "braided crown".
5. Rig carry-overs: puffy shoulder caps and mitten hands. These are acceptable for background NPCs.

## Overall finding

R3 clears every scoped must-fix item I could see:
- the bun and ponytail ear spikes are gone on b02, b10, b14 and w02 (and h03), with no loss of nape coverage;
- tunic hips show no trouser triangles on b19 and h03;
- the skirt and tunics stay clear of the thighs in the near and far walk poses.

Scale, grounding and materials remain good across all 20 IDs.

The only remaining defect is in the seated crowd mesh: skirts and tunics become a horizontal blade sticking out past the knees in the chair and bench poses. In my scope this keeps b08 at REVISE, and it shows the same way on b19 and h03. If root decides seated garments are outside this sign-off, b08's standing and walking models pass.

**Result: 19 PASS / 1 REVISE / 0 BLOCKED. All 20 IDs viewed using after-r3 images, plus 24 garment pose sheets and the player reference.**
