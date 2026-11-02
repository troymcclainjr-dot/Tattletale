# Next five non-quest priorities — November 1, 2026

Implementation and integration validation complete. This ledger records tested behavior and its limits.

## Changes

- Performance: fixed a GodotPhysics broadphase-bound refresh problem following long player relocations; narrowed hot traffic dispatch and added a bounded emergency-vehicle registry. Population and graphical quality remain unchanged. See [performance evidence](PERFORMANCE.md).
- Aftermath: a bounded ambulance service connects reported injuries to hospital departure, scene arrival, paramedic contact, treatment or honest failure, and return. Independent review covers walls/heights, scene deadlines, linked reports, visible recovery and traffic conflicts. Both headless and rendered actual-city lifecycle checks pass. See [EMS review](ems-service-review.md).
- Basketball: physical shootaround plus a reusable NPC opponent for first-to-11. One point inside the arc, two outside; defensive rebounds must be cleared. Loser's ball, out-of-bounds, quit/rematch, power feedback and pause/phone/map safeguards. No steals or contact defense; pickup games are not checkpointed.
- Commerce: Old York Pantry's service window sells health recovery, bicycle colors and bandana colors. Owned cosmetics re-equip without another charge and survive saves. No new hunger meter or player combat. See [commerce report](commerce-report.md).
- Usability: rebindable actions, 100/110/125% text, checkpoint loading and confirmed Start Fresh with archived recovery copies. Existing unsafe-state save/load barriers remain. Retired combat/driving acceptance fixtures were updated to the current pacifist policy while retaining backend checks.

## Completed integration checks

- Seven movement/bicycle suites passed, including 2,616 curb-matrix checks across 277 crossings; no collision bypass or population reduction.
- Basketball rules: 92 checks passed, including full authored court-plane agreement and inside-arc possession clearing. Physical match: 105 checks passed, including actual opponent shots, rebounds and scoring; clean teardown. Actual imported city session: 47 checks passed, with real input, physics, opponent movement and modal transitions.
- Fresh-start/load: 35 checks passed, including active-combat/incident refusal before disk load, warning preservation, exact-byte archive rollback under a locked file, and concise basketball HUD behavior.
- Commerce: 44 focused checks and 35 actual-city checks passed; imported/fallback cosmetics and rendered pantry/cosmetic captures inspected.
- Settings layout: all tested 720p/1080p tabs and text scales passed; 17 rebind rows and confirmations remained reachable. Phone: 124 checks passed.
- Persistence: 219 checks passed; retained vehicle backend/pacifist gate: 75 checks passed. Traffic dispatch: 19,200 differential comparisons; emergency registry and shared leases: 43 checks passed.
- Independent ambulance review regressions: 33 checks passed (physical wall/height obstruction, busy-patient deadline, linked incident reports, visible-crew preservation, sustained crossing conflicts, query accounting and bounded route joins). The end-to-end arena passed 90 checks. Fourteen parking/footprint checks, 20 responder curb checks, 43 emergency traffic-registry checks, 23 junction checks and 16 police/ambulance admission checks also passed. The actual city exposed and prompted repairs for a blocked hospital driveway, curb ascent/descent, stopped-car turn conflicts and competing junction ownership. Final headless actual-city acceptance passed 49 checks; the rendered version passed 51 with physical treatment, return, checkpoint interruption and no relocation. The treatment capture was inspected.
- Settings checkpoint controls: 31 actual-city checks passed, including sole temporary-copy recovery, protected save refusal, exact-byte archival and availability refresh after outcomes.
- Incident/police integration: incidents 72 checks, incident persistence 75 checks, and actual-city police assistance 22 checks passed; phone follow-up, dispatch labels and police lifecycle fixtures also completed without failures.
- Python performance cleanup, release validation and export pipeline suites passed. Private project TEMP was used where sandboxed system-temp permissions prevented fixture creation.
- Final integrated 600-second stationary endurance passed 19 checks; 180-second day/night traversal passed 37. At 1280×720, steady frame median/p95 were 3.4/9.7 ms (histogram upper bounds); traversal median/p95 were 3.234/11.225 ms, with a 49.959 ms maximum. Full population remained and no orphan nodes or streaming failures were recorded. Internal memory rose 1.777 MiB across the stationary run while native private memory fell 2.227 MiB. This is bounded evidence, not a guarantee against all long-session leaks. See [performance evidence](PERFORMANCE.md).

## Release and repository

Standalone `next-five-20261101-r2` passed exported boot, fresh play, save/reload and ordinary graphical startup restore. Installation write-denial and unchanged-source checks passed; the archive was verified. See [release receipt](release-validation.json). The first candidate was rejected by a stale 17-named-actor test; the corrected probes require exactly 15 base identities, two police crew and two paramedics. Only validation tools changed after the performance snapshot; gameplay scripts/assets stayed identical.

Imports and the final AST graph refresh are complete (2,977 nodes, 4,853 edges). Source, fixtures and concise evidence are prepared for the original `main` branch. Release binaries, screenshots, caches and raw measurements remain local and are excluded from Git.

## Measurement limits

Tests use isolated profiles; graphical fixtures are unfocused/off-desktop and leave the desktop pointer uncaptured. No personal application was closed. Background videos remain allowed, so timings are contended measurements. The measured relocation spike improvement is not a general FPS claim. Screenshots and raw runs stay local; concise reports and fixtures belong in Git.
