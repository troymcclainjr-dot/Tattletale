# Usability validation — November 1, 2026

## Runtime evidence

Root serialized all Godot runs; this worker launched no engine processes.

- Input bindings smoke: passed (root runner). Real physical-key InputMap movement/sprint, key press/release, duplicate/reserved-key rejection, reset/reload, and held-input reset are covered.
- Save story-context audit: passed after replacing preload-before-autoload entry with the normal deferred wrapper.
- Retired driving smoke: **75 passed, 0 failed**. Player boarding remains disabled. Dedicated external-owner fixture retains acceleration, braking/reverse, steering/grip/slip, handbrake, swept head-on/thin/glancing collisions, pedestrians/vehicles, curb/riser behavior, tires, LOD, safe placement and ownership/pause coverage.
- World persistence smoke: **219 passed, 0 failed** (root confirmed final completion). Disk round trips, frozen legacy files, inventory holstering with ownership/ammunition preserved, promoted cars, corrupt/future sections, rollback, duplicate prevention and case/death contexts remain covered.
- Fresh-start smoke: **27 passed, 0 failed**. Primary/backup/temp bytes preserved; queued save cancelled once; outgoing autosaves disabled; unsafe/unavailable requests leave candidates unchanged. Holding the backup open on Windows exercised a real partial-rename failure and byte-for-byte primary rollback.

## Persistence fixture correction

A parked curbside car is not necessarily within the external-controller road footprint: vehicle `_external_road_clear` requires every `ROAD_CORNER` on `traffic.on_road`. Extra throttle time therefore cannot prove a moved parking checkpoint. The persistence fixture records an external probe, then chooses a different grounded, collision-clear pose using production `_restore_pose` before `place_parked`. Its >1 m displacement assertion and exact restored pose/damage checks remain intact. Runtime movement physics are independently covered by the driving smoke's valid AI-road fixture.

## Rendered settings acceptance

The enhanced `city_settings_layout_runner.gd` checks 18 viewport/tab/scale combinations and repeated scaling without compounding. At 1280×720/125%, it scrolls every binding row into view, checks full labels and button bounds, verifies Reset reachability and tests the embedded fresh-start confirmation. With `--offscreen-validation` on a real renderer it writes Controls top/row groups/bottom, Video top/bottom and fresh-start PNGs plus `settings-layout-captures.json` into this directory. **Passed, 0 failures**, on the root-owned offscreen renderer. The capture manifest records ten 1280×720 PNGs. Root visually inspected the lower Controls rows and fresh-start confirmation at 125% and confirmed readable text and intact layout.

## Independent save-flow review

Load callback now surfaces provider fallback/backup warnings. Fresh-start preserves candidates before reload, verifies reload errors and reenables saving if reload fails. Archive clears incompatible-slot write protection only after all old candidates are safely archived; rollback failure keeps writes blocked. The service-apron safe-position hook requires a narrow authored frontage, strict local height range, the exact registered foundation collider, a real ray intersection, slope checks and the normal final capsule-clearance check.

The root callback now enforces the existing `checkpoint_blocker` before mid-visit loading, covering live fight/incident transitions as well as the provider startup guards.

## UI scope

Settings and ordinary HUD/dialogue/map label text scale to 100/110/125% without changing viewport scale. Dialog internal labels/buttons are explicitly scaled and descriptions wrap. Phone content/cards/buttons are scaled after page rebuild inside its existing scroll container; fixed handset chrome, custom-drawn app/nav glyph labels and camera framing remain fixed size. Binding editor supports one keyboard primary per action, with LMB reserved for basketball shooting; no gamepad/chord editor is claimed.

## Final integration regression additions

The fresh-start fixture now inherits the actual level callback and uses the production checkpoint guard, substituting only disk loading and presentation dependencies. It covers active combat, downed player, incident transition, one stable load, exact fallback-warning preservation and one presentation refresh. It also verifies basketball HUD duplicate filtering preserves score/possession/charge controls, unrelated dispatch notices and unannounced basketball feedback. The root-owned fresh-start/integration run passed all 35 checks. The actual-city Settings checkpoint-candidate session passed all 31 checks, including real confirmation input, sole-temp recovery, protected-save refusal and post-outcome availability refresh. A final independent review found no material modal, purchase, lifecycle or pacifist-policy conflict.
