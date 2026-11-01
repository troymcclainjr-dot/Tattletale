# Vehicle visual validation — after-r2 (Opus 5.5 MEDIUM, independent, second review)

Date: 2026-11-01. Scope: 12 vehicle IDs. Method: I looked at every rendered PNG directly with the image reader (1920x800, 3 views: front 3/4, side, rear 3/4). For every ID I viewed the after-r2 image, the after-r1 image (to check the r1 findings) and the before image (to check improvement over the baseline). I re-checked each concrete issue in my prior `validator-vehicles-report.md` against the r2 renders. I used `after-r2/vehicles-metrics.json`, `before/vehicles-metrics.json` and `vehicle-report.md` only to confirm what I saw. I did not edit any source, run an engine or apply a fix.

**Coverage: 12/12 IDs reviewed. 36/36 images viewed. No images are missing.**

Images viewed (all under `.work/model-quality-20261101/`):
- `after-r2/vehicles/{box_sedan,compact,minivan,hatchback,midsize_sedan,long_sedan,pickup,cargo_van,compact_suv,cop_car,sedan,ambulance}.png`
- `after-r1/vehicles/` the same 12 IDs
- `before/vehicles/` the same 12 IDs

Capture limits, unchanged from r1:
- There is no ground plane or contact shadow, so I judged grounding from wheel-bottom alignment across the three views.
- Each catalog kind was rendered in one paint only, so I could not judge paint variety.
- I did not see the far/parked LOD meshes, so I am not claiming anything about LOD switches.

## Recheck of the r1 must-fix issues

| r1 defect | r2 status | Evidence |
|---|---|---|
| D1 pickup tail lamps rendered dark grey/black | **Fixed** | In the r2 rear 3/4 view, both vertical tailgate-pillar lamps are red again, each with a dark bezel (about px 1333,425 and 1492,460). The r1 image showed them as black. Surfaces went back from 13 to 14, which matches the before image and the other catalog kinds. |
| D2 sedan pale arch-lip hairlines floating above the wheel openings | **Fixed** | The pale arcs (r1 side view about y 410 over both wheels, also in both 3/4 views) are gone in all three r2 views. The pink panels above the arches are clean, and the r2 render matches the before image in that area. |
| D3 ambulance livery band was a protruding slab, crossed the rear arch crown and had a stand-off rear frame with fins | **Fixed** | In the r2 side view, the red band is a flat panel that runs only between the wheel openings (about x 845–1075, y 418–440) and no longer crosses either arch. In the rear 3/4 view, the tailgate band is a flat strip between the two short rear lamps. The wrap-around frame and the tall fins that stood off the tailgate are gone. The band is now a clean, even red with no mottling. The black pinstripe below it is still visible. |
| D7 (polish) tall red rear-lamp fins sticking out past the minivan/ambulance silhouette | **Fixed** | On both the minivan and the ambulance, the rear lamps are now short red blocks seated in the rear face, and nothing sticks out in the side or 3/4 views. |

## Per-ID results (after-r2)

| ID | Images seen | Verdict | Visual evidence |
|---|---|---|---|
| box_sedan | before + r1 + r2 | **PASS** | r2 looks the same as r1. Compared with the before image, the wheel covers are finer and recessed, and you can see a hood shut line and wipers. The grille, chrome bumpers and red tail lamps are kept, and wheel placement is unchanged. The pale arch-crown fragments and a thin vertical seam line dropping into the front arch are pre-existing (both are in the before image). |
| compact | before + r1 + r2 | **PASS** | r2 looks the same as r1. The flat tick-mark disc covers set it apart from the box_sedan, and hood seams are present. The light jagged fragments at the arch crowns in the side view (about px 790,430 and 1120,430) are still there. They are pre-existing and reduced from before (polish item 2). |
| minivan | before + r1 + r2 | **PASS** | The r2 change is a clear fix: the tall rear-lamp fins that stuck past the roofline in the before and r1 images are now short red lamps seated in the rear face. The sliding-door runner, tailgate handle, finer hubcaps and wipers are kept, and the silhouette is unchanged. Pre-existing pale fragments remain at the arch crowns. |
| hatchback | before + r1 + r2 | **PASS** | The r2 tail lamps now show a visible bezel outline and a thin vertical reflector divider, consistent with the width/height chamfer fix. The rounded headlamps, railed grille, hood seam and spoiler are kept. No new artifacts. |
| midsize_sedan | before + r1 + r2 | **PASS** | r2 looks the same as r1. Compared with the before image: rounded headlamps, a railed grille, beveled red tail lamps with a reflector division, and hood seams. The tapered skirt and greenhouse are unchanged. No artifacts. |
| long_sedan | before + r1 + r2 | **PASS** | r2 looks the same as r1. Rounded lamps, a railed grille and divided red tail lamps, and the skirted rear opening is kept on purpose. The tiny white slivers at the chrome bumper ends in the rear 3/4 view (about px 1490,510 and 1866,408) are still there. They are only a few pixels, so this is polish item 1, not a blocker. |
| pickup | before + r1 + r2 | **PASS** | D1 is fixed: the red tail lamps with dark bezels are back. The front gains are kept (rounded bezelled headlamps, grille rails, hood seams), and so are the open bed and the stance. A small light bevel at the bumper ends is still visible (polish item 1). |
| cargo_van | before + r1 + r2 | **PASS** | The r2 tail lamps show a lighter bezel rim around the red lens. Rounded headlamps, a railed grille, wipers, barn doors and blackout bumpers are kept. Pre-existing arch-crown fragments remain (polish item 2). |
| compact_suv | before + r1 + r2 | **PASS** | The r2 tail lamps show the bezel and divider, and the headlamps have a fine inset strip. The spare wheel, roof rails and dark cladding are kept, and proportions are unchanged. |
| cop_car | before + r1 + r2 | **PASS** | r2 looks the same as r1. The opaque slate glass and blackout B-pillar are visible in all three views. The livery, lightbar, push bar, PRECINCT plate, antenna and wheel pivots match the before image. Shared changes caused no regression. The windshield looks lighter than the side glass (polish item 3). |
| sedan | before + r1 + r2 | **PASS** | D2 is fixed: the arch hairlines are gone. The character features are kept: pink paint, roof pom, dented panel, and the missing rear hubcap (dark hub on the far rear wheel in the front 3/4). The visible change from the before image is now small. It is mostly the glass finish, with wipers that are hard to make out at this framing. The windshield and backlight read as flat light grey next to darker side glass (front 3/4 about px 180–320). That is optional polish, not a defect. For a hero story asset whose character must be kept, a small coherent change is acceptable. |
| ambulance | before + r1 + r2 | **PASS** | D3 is fixed (see the recheck table). The split lightbar pods with the grey centre bar and the ambulance lettering are kept. The thin grey bar sticking out past the far-side front corner in the rear 3/4 view (about px 1800–1870, y 370) is pre-existing (it is in the before image) and minor (polish item 4). |

## Defects

Must fix: **none remaining.** All three r1 must-fix defects (pickup tail lamps, sedan arch hairlines, ambulance livery band) are fixed in the r2 renders, and none of the shared changes caused a regression in any peer.

Optional polish (not blocking):

1. **long_sedan / pickup:** tiny light bevel slivers at the chrome bumper ends in the rear 3/4 view. The worker says these are lit chamfer faces, not broken geometry. That fits what I see, but check it once in a close view.
2. **Catalog-wide, especially compact, box_sedan, minivan and cargo_van:** pale jagged fragments at the wheel-arch crowns in the side view. These are pre-existing and could shimmer in motion.
3. **sedan / cop_car:** the windshield and backlight are noticeably lighter than the side glass. Consider matching the tones.
4. **ambulance and minivan (pre-existing):** a thin grey bar sticks out at the far front corner in the rear 3/4 view. It is probably the mirror or bumper end. Confirm it is intended.
5. **compact / box_sedan:** the thin hood shut lines may alias in motion. This is unchanged from r1.

## Performance note

Triangle counts stay well within the stated limits. The catalog kinds range from 2406 to 2840. box_sedan, compact, minivan and ambulance are all below their before counts (for example, the ambulance went from 3260 to 2738). cop_car is 15867 (before 15447) and sedan is 15402 (before 15398). The pickup's surface count is back to 14, and no ID has more surfaces than before (ambulance went from 22 to 18). The added detail is merged into existing materials, which fits the shared-material/mesh approach. I did not count polygon counts as a quality gain.

## Overall finding

**12 PASS, 0 REVISE, 0 BLOCKED. 12/12 IDs covered and 36/36 images viewed.** All three r1 revisions are fixed visibly in the r2 renders, and the extra minivan/ambulance rear-lamp fix removed a pre-existing silhouette problem. Scale, wheel placement and the identity of each vehicle are kept across the fleet. The improvement over the baseline is modest but real: bezelled lamps, grille rails, seams, finer wheel covers and a cleaner ambulance livery. The story sedan's improvement is the smallest. What remains is polish only, mainly the arch-crown fragments and the glass-tone mismatch.
