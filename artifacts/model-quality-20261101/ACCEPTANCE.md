# Character and vehicle quality pass — 2026-11-01

Status: complete. All 68 model presentations passed independent visual validation. The final standalone package passed boot, fresh gameplay, save/reload and normal startup checks.

## Delivered

- Refit all 16 authored player/cast assets. Two-Pack now measures 1.799 m tall instead of 2.004 m, with narrower shoulders and adult proportions consistent with nearby NPCs. Existing character identities, accessories and rig contracts remain intact. Children retain age-appropriate proportions.
- Improved all 20 existing modular NPC appearances and added 20 new ones: 16 Black, two Hispanic and two White characters. Each has an authored combination of face, hair, body proportions, clothing and palette. These are shared modular models with individual configurations, rather than 40 independently sculpted meshes.
- Deployed all 40 appearances across the existing 1,200 ambient slots and expanded the named daily-routine roster from 20 to 40. New residents have home locations and safe routes across the neighborhood. The prior 20 identities are preserved, including restoration of old saves containing exactly those 20 residents.
- Refined 12 vehicle presentations: nine procedural vehicle types, the ambulance, imported police cruiser and legacy sedan. Changes include body transitions, lamps, trim, grilles, wipers, wheel detail and cleaner livery. Vehicle dimensions, collision contracts, wheel pivots and behavior hooks remain compatible.
- Corrected integration defects found during review: double gamma conversion on crowd colors, old 20-style LOD clamping, held binocular contact, bicycle hand placement, baby crawl grounding, clothing intersections and seated garment shapes.

See [the model gallery](MODEL_GALLERY.md) for every new resident's name, street and preview, plus all authored cast and vehicle previews.

## Validation scope

Three native Astra HIGH workers implemented player/cast, modular NPCs and vehicles. Headless Opus 5.5 MEDIUM independently inspected rendered images for all 68 model identities/presentations (16 cast, 40 modular NPCs, 12 vehicles), with revision reviews for concrete defects. All Claude invocations used `--no-session-persistence`. Root integrated and tested; root model/effort are not exposed by this session.

Final visual acceptance: all 68 pass the requested reasonable-quality bar. [The final garment review](reviews/validator-garments-final-report.md) resolves the eight remaining NPC revisions from earlier rounds and checks all 12 affected garment styles, standing/walking/far LOD and five control styles. [Review receipts](reviews/receipts.json) confirm the actual model and MEDIUM effort. Earlier reports retain their original findings; the final garment report supersedes their seated-clothing revisions. Optional polish observations remain documented rather than being represented as defects that were fixed.

Engine evidence is under `.work/model-quality-20261101/`:

| Check | Result |
|---|---|
| Authored cast proportions, pivots, accessories and pose regressions | 558 checks, zero failures |
| Vehicle catalog | 284 checks, zero failures |
| Vehicle presentation and target visibility | 67 checks, zero failures |
| Vehicle LOD | 17 checks, zero failures |
| Bicycle rider hand contact | 20 contacts, zero failures |
| World save and legacy resident migration | 86 checks, zero failures |
| Real-render resident deployment and routes | 386 checks, zero failures |
| Real-render modular population transitions | 13 checks, zero failures |
| Full production gameplay flow | 80 checks, zero failures |
| Release-tool unit tests | 30 tests, zero failures |
| Final standalone package | Fresh, reload and normal startup all passed; archive integrity verified |

Standalone candidate: [model-quality-20261101-r2.zip](<C:/files/projects/Tattletale/artifacts/priorities-five/release/model-quality-20261101-r2.zip>). The first candidate exposed a stale validation expectation of 20 daily residents; it was corrected to 40 without weakening other gates, then rebuilt and retested. [Standalone evidence](<C:/files/projects/Tattletale/artifacts/priorities-five/release/model-quality-20261101-r2/standalone-gameplay-validation.json>) records the final result. The project knowledge graph was updated after code changes.

The gameplay flow covers movement, phone use, an existing case, saves and police reporting. Offscreen render fixtures use private profiles and do not take desktop focus or modify the user's play profile. Headless GPU readback is explicitly skipped; real-render GPU custom-data checks cover all 1,200 ambient slots and all 40 styles.

## Performance evidence

An active 10.003-second walking sample at 1920×1080, Balanced Forward+, uncapped with VSync off, retained 1,200 ambient people, 40 daily residents and 90 cars. It traversed 37.87 m and passed the benchmark's active-play checks.

| Metric | Measured |
|---|---:|
| Delivered average FPS | 178.35 |
| Mean / p95 frame time | 5.61 / 10.73 ms |
| Mean / p95 draw calls | 1,191 / 1,334 |
| Mean / p95 GPU time | 2.19 / 2.39 ms |
| Mean / p95 render CPU time | 1.92 / 2.84 ms |
| Daily-resident logic mean per physics tick | 0.407 ms |
| Frames over 16.7 / 33.3 ms | 7 / 0 |

This is a short route sample on this machine, with the user's normal background applications running. It is not a controlled before/after speedup claim or a guarantee for every location. It predates the last seated-garment geometry correction; subsequent mesh budgets remained bounded. Final high-detail modular models stay below 4,500 triangles and distant models below 900; ambient geometry retains one shared surface/material. Authored cast triangle counts did not increase.

## Remaining polish limits

The cast remains deliberately stylized and low-poly. Shared hair/clothing modules recur across residents. Seated clothing uses cached pose geometry, not cloth simulation. Bicycle legs still use the existing dedicated riding geometry rather than a new full-body IK system. Vehicle visual review covers representative paint colors; runtime tests separately cover LOD and collision contracts. This pass does not claim the whole game is ready to ship.

## Play

[Play Pen Lucy](<C:/files/projects/Tattletale/Play Pen Lucy.lnk>) launches the current source build and imports updated assets as needed. Restart an already-running game to load these changes.
