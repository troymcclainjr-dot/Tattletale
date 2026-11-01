# Validator report r3 (final): new 20 NPC styles

Validator: Claude Opus 5.5 (medium), independent. No source edited, no engine run, no fixes implemented.
Current truth: `after-r3/`. Each NPC PNG is 1920x800 with three views: front full body, rear three-quarter on the grey plane, and a head/shoulder closeup. Each garment-pose PNG has three views: front, rear three-quarter and side.

## Images actually viewed (this pass)

- **New IDs, after-r3 (all 20 viewed once):** b17, b18, b19, b20, b21, b22, b23, b24, b25, b26, b27, b28, b29, b30, b31, b32, h03, h04, w03, w04 (`after-r3/npcs/<ID>.png`).
- **Garment pose gallery (12 of 24 viewed):** `b08_walk_left_near`, `b08_walk_right_near`, `b08_walk_left_far`, `b08_chair`, `b08_bench`, `b19_walk_left_near`, `b19_chair`, `b19_bench`, `h03_walk_right_near`, `h03_bench`, `b18_walk_left_near`, `b18_chair`. I did not open the other 12: b08/b18/b19/h03 `standing_near`; b18 `walk_right_near`, `walk_left_far` and `bench`; b19 `walk_right_near` and `walk_left_far`; h03 `walk_left_near`, `walk_left_far` and `chair`.
- **Missing:** `after-r3/cast/two_pack.png` does not exist. Only before, after-r1 and after-r2 cast renders exist. For the player scale reference I relied on my r2 comparison against `after-r2/cast/two_pack.png`. I did not re-open it this pass.
- **Before images:** none exist for the new 20, which is expected. Per the brief, older baselines and r1/r2 renders were not re-opened. The r2 state comes from `validator-npc_new-r2-report.md`.
- **Text read:** `validator-npc_new-r2-report.md`, `after-r3/garments/garment-evidence.json`, and a grep of worker/validator reports for seat/skirt context (`validator-motion-report.md` b08 walk skirt split).
- **Not re-checked:** the bun/ponytail spikes on b02, b10, b14 and w02. Those IDs are outside this validator's list, and I did not open their renders. On the new IDs that use the same bun/ponytail modules (b23 bun, h03 ponytail), the r3 closeups show no shell spike below the ears.

Identity labels come from the authored catalog (r2 report table), not from appearance. Palette r2 is accepted as the correct single-decode sRGB fix. Raw identity colours are unchanged, and I am not asking for any revert.

## Status of r3-scoped must-fix items

| Item | IDs | r3 result | Evidence |
|---|---|---|---|
| D4 tunic hip trouser triangles | b19, b23, b27, h03 | **Fixed** | All four tunic hems are a clean trapezoid with a continuous trim band: lilac on b19/b23/b27, tan on h03. Front y≈535–545 and rear y≈540–550 show no dark notches at the hip corners (old r2 locations x≈260–280 / 360–378 and x≈903–940). The b19 walk shows the same clean hem in the front, rear and side views. |
| Bun/ponytail shell spikes below ear | new-ID users b23, h03 (b02, b10, b14, w02 not in scope) | **Fixed on b23/h03** | The b23 closeup (ears x≈1455–1745, y≈410–500) and the h03 closeup show clean ear-to-neck transitions. The r2 dark slivers below the ears at x≈1475/1722 are gone. |
| Walking skirt clearance | b08 dress (peer) and tunic b19, h03 | **Fixed** | `b08_walk_left_near` and `walk_right_near`: the legs come out cleanly under the hem in all three views. The wedge/split reported in `validator-motion-report.md` is gone, and no leg pokes through the skirt. Tunic walks (b19, h03) are clean. Shoes plant on the ground with a natural toe-off tilt. The far-LOD walk (b08) reads the same as near. |

## New finding from the seated garment gallery

The seated chair and bench poses show a problem the standing renders could not. The skirt or tunic lower panel collapses into a **paper-thin horizontal blade** that sticks straight out forward from the lap.

- `b08_chair` and `b08_bench` (dress): in the side view the blade runs x≈1345–1650 at y≈480–500, ending about one shin-length beyond the knees (knee ≈ x 1440). In the rear three-quarter view it sticks out left of the body as a flat triangle at x≈775–860, y≈465–480. In the front view it reads as a flat tray at y≈470–500, with the thighs visible beneath it.
- `b19_chair` and `b19_bench` (tunic): side-view blade at x≈1430–1590, y≈465–480, with an exposed lilac hem edge forming a spike tip at x≈1430. In front it's a horizontal tray at y≈455–480, and the trouser thighs show below it.
- `h03_bench` (tunic): side-view blade at x≈1420–1590, y≈470–485, with a tan tip. In the rear three-quarter view the edge sticks out past the left side at x≈825–860.

It reads as broken geometry, not cloth. Legs, feet and seat contact are otherwise fine: the hips sit on the seat, and the shoes are flat on the ground in the chair and bench poses. The non-skirt control `b18_chair` is clean: the waistcoat sits on the torso and the trousers drape over the knees.

This is outside the three must-fix categories named for r3. I'm listing it as must-fix because it fails the core acceptance criterion (no obvious broken geometry) at normal camera distance, wherever residents sit. The final call is root's.

## Per-ID results

"Seated" means seated pose evidence. Only b19 and h03 among the 20 have seated captures.

| ID | Authored identity | Images seen | Verdict | Visual evidence |
|---|---|---|---|---|
| b17 | Simone Avery: ink varsity / sculpted high fade | after-r3 b17 | PASS | Varsity read (navy body, tan sleeves with stripes, tan waistband). The fade is compact, the face reads, and the feet are grounded. Small light fleck at the left temple in the rear view (x≈925, y≈265) remains, P7. |
| b18 | Malcolm Ellis: copper waistcoat / side part | after-r3 b18; garments b18_walk_left_near, b18_chair | PASS | Waistcoat over a pale-blue shirt with a tie reads well. The walk and chair poses are clean, with no cloth intrusion. In the rear view the waistcoat flank stands slightly past the back at x≈893, y≈400–470 (P9). The side-part top step remains (P3). |
| b19 | Tessa Monroe: sage tunic / angled pixie | after-r3 b19; garments b19_walk_left_near, b19_chair, b19_bench | **REVISE** | D4 is fixed: the hem is clean front and rear, and the walk is clean. **Seated tunic blade (D5)** at side x≈1430–1590, y≈465–480, with a lilac spike tip, plus a front tray. A small dark tuft at the left rear of the head (x≈915–930, y≈225–260) is the angled pixie, acceptable. |
| b20 | Darius Coleman: sand overshirt / swept crown | after-r3 b20 | PASS | Collar points, buttons and pockets read. The swept crown is layered, the face is readable and the feet are grounded. Nothing broken. |
| b21 | Yvette Freeman: cranberry dress / close silver crop | after-r3 b21 | **REVISE** (seated, shared) | The standing render is clean. The dress flares over the trousers with a clean hem front and rear, the silver crop and brows read, and the feet are grounded. There is no b21 seated capture, but the dress uses the same skirt geometry that is broken in `b08_chair` and `b08_bench`, so I can't approve it seated. It clears once D5 is fixed and confirmed. |
| b22 | Ellis Chandler: petrol varsity / compact natural | after-r3 b22 | PASS | Rounded natural crown with a softened edge. The beard is a bounded chin form, the varsity reads and the feet are grounded. Pale-teal sleeves are shared with b30/h04 (P6). |
| b23 | Nia Lawson: indigo tunic / gathered bun | after-r3 b23 | **REVISE** (seated, shared) | D4 is fixed: clean hem with lilac trim, front and rear. The bun reads front and rear with no spike below the ear, and the r2 ear sliver is gone. Grounded. Standing is acceptable, but the tunic shares the seated blade seen on b19 and h03 (D5). No b23 seated capture was seen. |
| b24 | Warren Miles: moss waistcoat / bare scalp | after-r3 b24 | PASS | Cream sleeves and V with a moss tie. Clean scalp, bounded beard, readable face, grounded. Waistcoat flank stands slightly off in the rear view at x≈890, y≈410–470 (P9). |
| b25 | Camille Porter: ochre jacket / angular bob | after-r3 b25 | PASS | Jacket with zip stripes and a hem band. The bob covers the back and sides to the collar. Readable face, grounded. A small jacket-panel edge shows past the back in the rear view at x≈898, y≈430–480 (P9-type). |
| b26 | Jonah Bishop: maroon knit / tapered high fade | after-r3 b26 | PASS | Coherent knit and bounded beard, grounded. The fade is still a flat-topped vertical block that reads cap-like (P3, polish). |
| b27 | Alana Reid: peacock tunic / long braids | after-r3 b27 | **REVISE** (seated, shared) | D4 is fixed: the teal hem is clean, with no purple triangles front (x≈255–385, y≈540) or rear. The braids hang behind the ears to the shoulders, a coherent strand read. Grounded. Shares the tunic seated blade (D5). No b27 seated capture was seen. |
| b28 | Desmond Hayes: slate collared shirt / side part | after-r3 b28 | PASS | Clean collared shirt, side part and bounded beard, grounded. Silhouette is close to b20 (P6). |
| b29 | Marisol Benton: paprika cardigan / swept pixie | after-r3 b29 | PASS | Cardigan V reads, the crown is covered and the feet are grounded. A thin skin-coloured crown seam remains (closeup x≈1570–1630, y≈284), P8, too small to matter at game distance. |
| b30 | Quentin Shaw: plum varsity / shoulder locs | after-r3 b30 | PASS | Locs sit beside and behind the neck, with a full curtain in the rear view ending at the shoulders. The neck front is clear, the varsity reads and the feet are grounded. |
| b31 | Imani Fletcher: olive dress / high natural crown | after-r3 b31 | **REVISE** (seated, shared) | The standing render is clean: the dress flares cleanly, and the tall crown is distinct, with a mushroom brim (P3, polish). Readable face, grounded. Same dress seated concern as b21 (D5). |
| b32 | Hugo Sterling: cream waistcoat / silver swept crown | after-r3 b32 | PASS | V, tie and separate sleeves are present. The silver crown and grey beard read, and the feet are grounded. Cream on pale-yellow layering is still low-contrast (P10), and the rear flank is slightly off (P9). |
| h03 | Elena Vega: blue tunic / long ponytail | after-r3 h03; garments h03_walk_right_near, h03_bench | **REVISE** | D4 is fixed: the hem is clean with tan trim, and the walk is clean. The ponytail with its tan tie reads, and the ear transitions are clean, with no spike. **Seated tunic blade (D5)** at side x≈1420–1590, y≈470–485, with a tan tip. It also sticks out in the rear three-quarter view at x≈825–860. |
| h04 | Rafael Ortiz: umber varsity / swept part | after-r3 h04 | PASS | Varsity, side part and bounded beard are clean, and the feet are grounded. Shared pale-teal sleeves (P6). |
| w03 | Clara Whitmore: sage dress / copper pixie | after-r3 w03 | **REVISE** (seated, shared) | The standing render is clean: copper hair covers the crown front and rear, the dress flares cleanly, the face is good and the feet are grounded. Same dress seated concern (D5). |
| w04 | Graham Mercer: navy waistcoat / ash swept crown | after-r3 w04 | PASS | Strong waistcoat over shirt with a tie. Clean ash crown, readable face, grounded. Slight rear flank offset (P9). |

Coverage: 20 of 20 IDs viewed on after-r3. PASS 13, REVISE 7, BLOCKED 0.

- All 20 are acceptable **standing and walking**. Every r3-scoped must-fix that applies to these IDs is visibly fixed.
- The 7 REVISE verdicts come from one shared seated garment defect. Seen directly on b19 and h03 (and peer b08). Applied to b21, b23, b27, b31 and w03 because they use the same skirt/tunic geometry; their own seated captures were not rendered.

## Must-fix defects

1. **D5: seated skirt/tunic collapses into a flat forward blade (shared seated crowd mesh).** In the chair and bench poses, the lower skirt/tunic panel becomes a zero-thickness horizontal plane that sticks out forward from the lap. On the dress it extends well past the knees. On the tunic it ends near the knee with a coloured hem spike tip. It also sticks out sideways in the rear three-quarter view. Evidence is in `b08_chair`/`b08_bench`, `b19_chair`/`b19_bench` and `h03_bench`, with coordinates above.
   - **Fix:** in the seated pose, drape the front skirt/tunic vertices over the thighs, following the thigh top and ending at or just before the knee, then drop the rest down toward the shins (dress) or end at mid-thigh (tunic). Keep it in the same shared mesh and material, with no new surface.
   - **Confirm:** re-capture chair and bench for b08, b19 and h03, plus at least one each of b21, b31 or w03 (dress) and b23 or b27 (tunic).
   - **Scope note:** this falls outside the r3 must-fix list. Root may choose to defer it, but it is obvious broken geometry wherever residents sit.

No other must-fix issues remain for these 20 IDs. D4 (tunic hip triangles), the below-ear shell slivers on bun/ponytail users, and walking skirt clearance are all visibly fixed.

## Optional polish (not blocking)

- **P3, hair that reads as headwear:** b26 flat-top fade, b31 brimmed crown, and the side-part top step on b18, b28 and h04.
- **P6, accent variety:** pale-teal varsity sleeves on b22, b30 and h04. Similar silhouettes on b20 and b28.
- **P7, rear-view temple fleck:** b17 (x≈925, y≈265).
- **P8, b29 crown seam:** skin-coloured line on the crown.
- **P9, rear flank stand-off:** waistcoat/jacket edge past the back below the left sleeve on b18, b24, b25, b32 and w04.
- **P10, b32 layering contrast:** cream waistcoat on pale-yellow shirt.
- **P1, elbow ticks:** small sleeve-break ticks in front views, family-wide.

## Not verifiable from these renders

- Continuous motion flicker or z-fighting: the stills show none.
- Seated poses for the 18 IDs without captures.
- Bun/ponytail fixes on b02, b10, b14 and w02 (out of this validator's ID list).
- The r3 player render, which is missing.

## Overall finding

R3 cleanly fixes the scoped issues. The tunic hems on b19, b23, b27 and h03 no longer show trouser triangles. The bun and ponytail users have clean ear and neck transitions. The walking dress (b08) no longer splits around the swinging leg. All 20 new styles are coherent, grounded and varied in garment and hair silhouette, not just recolours, within the shared one-mesh, one-material budget. Standing and walking, they meet the bar.

The new seated garment gallery shows one remaining shared defect: in chair and bench poses the skirt/tunic becomes a flat blade sticking out from the lap. That holds the 7 skirt/tunic styles at REVISE (2 seen directly, 5 by shared geometry). The other 13 PASS. One fix to the seated shared mesh plus a re-capture should clear all seven.
