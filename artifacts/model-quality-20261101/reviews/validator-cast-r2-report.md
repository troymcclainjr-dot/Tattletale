# Validator report: legacy cast, after-r2 (Opus 5.5 MEDIUM, second visual review)

Scope: the 16 legacy cast IDs in the brief. Each image is 1920x800 with three panels: front full body, rear 3/4 view against the backdrop, and a face/chest close-up.

## Images actually viewed

- `after-r2/cast/<ID>.png`: **16/16** viewed with Read (baby, cop_dan, cop_steve, dad, gary, granny, liner_1, liner_2, liner_3, liner_4, mailman, mama, ricky, timmy, two_pack, vendor).
- `before/cast/<ID>.png`: **16/16** viewed with Read.
- `after-r1/cast/<ID>.png`: **5** viewed for change comparison (baby, timmy, two_pack, ricky, cop_dan).
- Total: 37 images viewed. No images were missing.
- I did not view `npcs/*` or `vehicles/*` this round. All 16 IDs are existing cast with baselines, so the "new NPC, compare to peers" path did not apply. This report does **not** assess the variety of the new 20 NPCs.
- Supporting data read: my prior `validator-cast-report.md` and `after-r2/cast-metrics.json` (bounds and triangle counts). These only back up what the images show. They are not the basis for any verdict.

## What changed since r1

- **baby and timmy** are the only IDs with a visible change between after-r1 and after-r2.
- **two_pack, ricky and cop_dan:** I compared their r1 and r2 images directly, and each pair looks the same.
- **The other 11 IDs:** checked only against `before`. Their r2 renders match my r1 notes (the same props, the same proportions, the same carried-over polish items).
- **Triangle counts:** unchanged in r2 (e.g. baby 20810, timmy 22170, the same as the r1 logs). That fits the shared-mesh/material performance approach: the fixes are proportion changes, not added polys.

## Recheck of prior defects

| # (r1) | Issue | r2 status (visual evidence) |
|---|---|---|
| 1 must-fix | baby read as a miniature adult | **Fixed.** In the r2 front panel the head spans about 50 px of about 180 px of body height (about 3.6 heads; r1 was about 4.8). The head is now clearly larger than in r1, and visibly larger relative to the body than in the baseline too. The legs are short and stubby, with the hip/diaper line sitting low; in the close-up the knees are barely below the diaper. It reads as an infant at game distance. Bare feet are grounded front and rear. The bounds height is 0.573 m against a 0.55 m contract (about +4%, fine). |
| 2 polish | timmy lost some childlike read | **Improved.** The r2 head is a little larger than r1 (front panel head about 67 px vs about 60 px at the same body height) and the cheeks are rounder. The shirt hem is slightly lower. He reads as a child again. Shoes grounded. |
| 3 polish | puffy squared shoulder caps on all bodies | Unchanged (shared mesh). Still visible on every ID, most obviously on baby, granny, mama and liner_3. |
| 4 polish | cop cap crown white from rear, navy from front | Unchanged on cop_dan and cop_steve. |
| 5 polish | cop_dan donut crowded against the holster/baton | Unchanged: the pink donut still overlaps the black holster at the left hip in the front view. |
| 6 polish | liner_2 faceted curls | Unchanged: triangle-faceted shading on the hair in the close-up and rear view. |
| 7 polish | vendor paper hat perched on top | Unchanged: a flat white cylinder sitting on the hair crown, visible in all three panels. |
| 8 polish | dad jagged undershirt strap edge | Unchanged: the strap and armhole edges at the shoulders are still ragged/serrated in the close-up. |
| 9 polish | two_pack sash faceting and cramped back text | Unchanged: the sash is still faceted in the rear view and "NEIGHBORHOOD" is still hard to read. |

## Per-ID table

| ID | Images seen | Verdict | Visual evidence (r2) |
|---|---|---|---|
| baby | before + after-r1 + after-r2 | **PASS** | r1 must-fix resolved. Large round head (about 3.6 heads tall), short chubby legs, low diaper bulge, tuft and brows intact, bare feet grounded. No new intersections. The face, eyes and mouth stay registered on the larger head. Remaining polish is the shared puffy shoulders and the faint chest fold creases. |
| cop_dan | before + after-r1 + after-r2 | PASS | Cap badge, DAN tag, chest badge, radio cord, belt gear and donut all kept. Head smaller than baseline. Boots grounded. Polish items 4 and 5 remain. |
| cop_steve | before + after-r2 | PASS | Taller than Dan, so the pair stays distinct. Glasses seated with no gap from the face. STEVE tag, badge, duty belt and holster intact. Boots grounded. Polish item 4 remains. |
| dad | before + after-r2 | PASS | Bald head, heavy mustache, sleepy lids, undershirt and belly kept. Narrower, longer-legged silhouette than baseline. Boots grounded. Polish item 8 remains. |
| gary | before + after-r2 | PASS | Beanie, long hair, beard, under-eye bags, arm patches and ember hand kept. The hair no longer flares wide. Boots grounded. No clipping of the beard into the collar. |
| granny | before + after-r2 | PASS | Bun, round glasses, pearl collar and lavender cardigan intact. The walker legs and tennis balls are on the ground, hands are at the grips, and the purse hangs from the crossbar with no clipping into the leg. Shorter than the adults. Head less doll-like than baseline. |
| liner_1 | before + after-r2 | PASS | The copper hair stays outside the shoulders. Clean V-neck. Lashes and brows kept. Shoes grounded. Clear proportion gain over baseline. |
| liner_2 | before + after-r2 | PASS | Curls, orange pocket shirt and dark trousers kept. Shoes grounded. Taller build. Polish item 6 remains. |
| liner_3 | before + after-r2 | PASS | The bob wraps the smaller head with no scalp gaps front or rear. Violet collar and two buttons intact. Shoes grounded. |
| liner_4 | before + after-r2 | PASS | Blond side part, blue short-sleeve shirt, bare forearms. Shoes grounded. Clear proportion gain. |
| mailman | before + after-r2 | PASS | Pith helmet with band, mustache, satchel and strap, letter at the hand, shoulder patch. Boots grounded. The satchel hides less of the leg than in baseline. |
| mama | before + after-r2 | PASS | Bun with yellow tie, hoop earrings, lashes, clean scoop neckline, pink top, cream sneakers grounded. Improved proportions. |
| ricky | before + after-r1 + after-r2 | PASS | Beanie, mask band and eyes registered. Stripes continuous. The money bag and strap sit over the shoulder without clipping into the head. Boots grounded. |
| timmy | before + after-r1 + after-r2 | **PASS** | The rounder, slightly larger head restores the child read (r1 polish item 2 addressed). Cowlick hair, big eyes, green shirt with the "7" pocket, yellow pants, red sneakers grounded. Clearly smaller than all the adults. |
| two_pack | before + after-r1 + after-r2 | PASS | Player reference. Bandana and knot, tear tattoo, 911 / SNITCH 4 LIFE / back text, sash, chain and whistle, striped waistband, smirk and gold tooth all intact. Sneakers grounded. Head about 1/7 of height. Polish item 9 remains. |
| vendor | before + after-r2 | PASS | Paper hat, swept hair, red bow tie, white shirt and belt kept. Shoes grounded. Polish item 7 remains. |

## Numbered actionable defects

**Must-fix:** none remaining. (r1 must-fix #1, baby infant proportions, is resolved in after-r2.)

**Optional polish (non-blocking, carried over and still visible in r2):**
1. **All bodies (shared mesh):** soften the squared, puffy deltoid/shoulder caps. This is the most toy-like remaining feature, and most noticeable on baby, granny and mama.
2. **cop_dan / cop_steve:** confirm whether the white cap crown seen from the rear is intended. If not, make it navy to match the front.
3. **cop_dan:** offset the donut from the holster/baton so the left hand reads clearly.
4. **liner_2:** smooth the faceted curl shading (normals only).
5. **vendor:** seat the paper hat lower so it reads as worn.
6. **dad:** clean the serrated undershirt strap and armhole edges.
7. **two_pack:** smooth the faceting on the rear of the sash. The "NEIGHBORHOOD" back text is still cramped.

**Not verified (no images provided):** walk/run, binoculars, held-prop, dad hammock, baby crawl and grandma walker animation poses. The baby crawl hooks should be rechecked in-engine after the r2 proportion change. The renders show only the rest pose.

## Overall finding

**16/16 PASS, 0 REVISE, 0 BLOCKED.** The r2 pass fixed the one must-fix from r1: baby now reads clearly as an infant, with a large head and short legs. It also restored timmy's childlike head ratio. Neither change added triangles, and I saw no regressions in any peer. The other 14 IDs keep the r1 improvements over baseline: smaller heads, longer legs, grounded feet and intact identity details. They show no new intersections, broken geometry or material flicker. The remaining items are optional polish carried over from r1. Coverage: 16/16 IDs, with 37 images viewed (16 after-r2, 16 before, 5 after-r1). None missing.
