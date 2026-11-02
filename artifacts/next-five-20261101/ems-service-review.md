# EMS implementation review — 2026-11-01

The ambulance now has a physically clear hospital departure, isolated crew exits, collision-safe curb traversal, and shared intersection ownership with ordinary traffic. The resumed headless actual-city session passed all 49 checks; the graphical counterpart passed all 51, including treatment, physical return without relocation, and checkpoint interruption. The root inspected the rendered treatment capture.

## Confirmed behavior and fixes

- Treatment requires the actual patient's identity, horizontal reach, same-level feet and an unobstructed physical link. Walls, different floors, death, custody and busy combat do not qualify as treatment. The overall scene deadline covers all early-return branches.
- One physical call can relay progress to up to eight incident refs naming the same patient. Identity mismatches and overflow are refused. Loading resets transient response ownership and preserves an honest interrupted result in the durable incident record.
- Crew dismount reserves each enabled paramedic's actual capsule pose before the physics broadphase catches up. Both crew cannot spawn at the same exit. The final arena validates physical walking and treatment rather than elapsed-time resolution.
- Hospital parking respects the authored emergency approach between z=-148 and -135, from the canopy apron to the exact Elkader centreline intersections. This is a parking-only reservation at generation: no live car deletion, road/collider changes, or enlarged NPC/metadata clearance. Adjacent north/south and opposite-curb parking remain eligible.
- Parked-car route checks use each actual kind/pose's full collision-envelope footprint with 20 cm clearance, including pitch/roll projection. The previous five-metre centre disk incorrectly blocked clear side-by-side traffic. Hospital exit search retains a total 24-check physics budget, shared across bays and approach lengths.
- Shared police/paramedic walking handles the leading capsule edge on ascent and trailing edge on descent. Near/leading support, the existing 23 cm rise/drop limit and full up/forward/down capsule sweeps precede `move_and_collide`. No actor pose assignment, mask relaxation, wall/ceiling bypass or larger horizontal step is used.
- Junction entry never becomes safe merely because a timer elapsed. Moving conflicts and reservations remain authoritative. A stopped car is now checked against the full grounded connector envelopes before entry; the connector's bounded samples are cached for that route. The actual Wilsby/Dumbarton waiting-car geometry is covered by a focused regression.
- Ordinary traffic's emergency-obstacle exit check uses the requesting vehicle's actual collision width, the oriented ambulance width and the existing clearance margin. It no longer double-counts a generic corridor width. The actual opposing departure remains available while the ambulance waits aligned before the turn.
- The later rendered probe identified a second junction defect: Car33 owned node `3740_-1964` while the ambulance entered from lane 52 toward lane 31. Shared reservation acquisition now denies every other live owner, including aligned cars. Driver ownership survives an occupied-junction replan/stop and releases only after projected rear clearance or a geometrically clear alternative exit; forced cleanup belongs to relocation/teardown. Focused and headless actual-city reruns now pass.
- An independent Astra High review found police cruisers could ignore aligned ambulance ownership or let the wait expire. Ambulance ownership now takes precedence over heading, cached clearance and elapsed waiting. Sixteen dedicated police-admission checks pass, including release, unregister and freed-body cleanup.
- Route kind owns emergency mode: response enables lights/signal exemption; routine return clears it. Driver motion remains within speed × delta plus floating-point tolerance; every attempted pose retains its ground and compound-hull sweep checks.
- Hidden-vehicle recovery does not relocate visible crew. Genuine unresolved obstacles retain bounded retry/failure handling; the final selected route must return physically without invoking recovery to pass the city fixture.

## Validation reported by the root runner

| Fixture | Result |
| --- | --- |
| EMS arena (`city_emergency_response_smoke`) | 90 passed, 0 failed |
| Independent EMS review regressions | 33 passed, 0 failed |
| Parked envelopes and authored driveway | 14 passed, 0 failed |
| Curb ascent/descent, diagonal, wall, tall step, low ceiling and people | 20 passed, 0 failed |
| Traffic emergency registry, actual widths, shared leases and full 90-car population | 43 passed, 0 failed |
| Actual connector, shared lease acquisition/release, opposing departure and return mode | 23 passed, 0 failed |
| Police respecting emergency junction ownership | 16 passed, 0 failed |
| Actual-city police session after shared walking changes | 22 passed, 0 failed |
| Police assistance smoke | Passed |
| Resumed headless actual-city EMS lifecycle | 49 passed, 0 failed |
| Final rendered actual-city EMS lifecycle | 51 passed, 0 failed |

The resumed actual-city session establishes hospital availability, a clear grounded departure, 9/9 neighborhood road plans, real treatment, both crew boarding after descending the curb, physical return, durable medical reporting and checkpoint interruption. All 623 sampled headless lane positions kept the full hull on the carriageway; no building/prop overlaps or lifecycle invariant violations were recorded. The rendered counterpart also passed its whole-hull, population and no-relocation checks. Earlier failed runs remain in local evidence and motivated the repairs above.

## Evidence and scope

- Runtime diagnosis and detailed review history: `.work/next-five-20261101/ems-service-review.md`.
- Actual-city evidence: `aftermath-city-ems-crew-probe-20261101/result.json`, `aftermath-city-ems-city-return-20261101/result.json`, and `aftermath-city-ems-return-probe-20261101/result.json` under the same work directory.
- Final passing actual-city evidence: `aftermath-city-ems-resume-city-20261101/result.json` (headless) and `aftermath-city-ems-resume-render-20261101/result.json` (rendered) under `.work/next-five-20261101/`. The private rendered launch receipt confirms unchanged source/staging and a clean exit. Capture: `artifacts/next-five-20261101/ambulance-city-treatment.png` (local only).
- Hospital geometry probes: `ems-base-probe-ems-base-20261101`, `ems-base-probe-ems-base-footprints-20261101`, and `ems-base-shortleads.log`.
- Root alone ran engines, imports and final freeze checks. This worker performed code/fixture changes and static diff checks. No personal checkpoint was used, and no gameplay guns, driving authority, combat, quests, or survival meters were enabled.

These checks cover the supplied scenes and the tested geometry, not universal reachability through arbitrary blocked streets or crowds. A genuinely inaccessible person must still receive an honest failed response rather than fabricated care.
