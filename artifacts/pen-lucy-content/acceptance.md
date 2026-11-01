# Pen Lucy content and original UI pass — 2026-10-30

Local playable: `C:/files/projects/Tattletale/Play Pen Lucy.lnk`. Restart the launcher to load the new code and exported world. No commit or push in this pass.

## Implemented

- Bundled the actual original Bungee, Barlow Condensed and Courier Prime font files, with OFL notices and official source hashes. City ledger, settings, map and conversation cards reuse the original paper/red/navy style.
- Six authored ambient dialogue graphs and a reusable multiline/choice/condition/branch/hook system. E opens nearby conversations; E/Enter/Space confirms, arrows choose, mouse buttons work, Esc leaves. Case offers and steps only mutate progress on explicit validated choices. All six existing cases complete through the new UI; their authored case lines remain unchanged.
- 654 homes receive 9,242.5 square metres of front garden beds, 619 shrubs and preserved 1.68 m paved approaches. All 384 building/context geometry objects retain identical source hashes. Ground slopes remain below four degrees.
- 319 original-asset cans, 31 dumpsters and 4,308 loose litter pieces across 171 occupied litter cells. All 5,277 dressing anchors verified against actual imported ground within 2 cm. Only substantial bins have collision; loose litter is non-blocking. Bins avoid road, walking and porch-stair corridors.
- Parked cars increase from 96 to 144; moving traffic from 72 to 90. Seventeen aggressive drivers cruise at 12–15 m/s; cautious drivers and all four police retain 8–10.5 m/s speeds. Swept contacts trigger a finite collision-safe player stumble. Full solid checks, signal rules, junction reservations, leader search and distance-based physics remain.
- Fixed vehicle registration at the origin: new bodies are positioned before entering the scene tree, preventing a transient collider from displacing the player.

## Performance and visual evidence

The yard provider uses one indexed surface per resident 48 m cell. Cell assembly happens once during cold setup, then compressed resources are loaded asynchronously with a 45 m prefetch margin. Far meshes and bin bodies are released. No per-piece visual processing is added.

The initial 25-cell reload blocked for 478.8 ms, with individual assembly up to 41 ms. Final GPU-backed validation measured 2.417 ms of immediate reload work, 171.234 ms asynchronous settle, maximum cell activation 0.319 ms and mesh attachment 0.091 ms. Cold cache setup took 5.303 seconds in that rendered test; later runs reuse the files. Source density and every indexed position/normal/color were checked.

GPU captures in this directory show the ledger, ambient dialogue, case offer, case text, settings and map; `yards/` contains three frontages and can/dumpster alley views. They were rendered by Godot in an unfocusable offscreen window. No desktop screenshots, keyboard/mouse capture or computer-use session was used. The user's existing game was left alone.

`performance-before-cache/metrics.json` and `performance-final/metrics.json` record actual 15-second walks at 1920×1080, Balanced, 100% render scale, VSync off, uncapped, on the RTX 3070 Ti. These are background offscreen samples, not controlled foreground comparisons with the previous pass. Screenshot writes are outside the timing interval. All NPCs, traffic, collisions, HUD and camera remain active.

Final sample: **179.18 FPS**, median frame 5.095 ms, p95 9.181 ms, worst 33.959 ms, 1,617 median draw calls. The player walked 57.02 m with zero stalled windows; all 1,215 people and 90 moving cars remained simulated. Yard cache: 172 hits, zero travel mesh builds/errors/missing near cells, 149 ms setup, maximum activation 0.243 ms and attachment 0.095 ms. The earlier uncached sample averaged 201.41 FPS but had a 54.778 ms worst frame; average FPS did not improve in these two background samples. The defensible improvement is removal of synchronous yard assembly, with a smaller observed worst frame, not a general FPS uplift claim.

## Validation

- Dialogue state and bundled fonts: 17 passed.
- GPU UI integration: 65 passed, zero skips.
- GPU vehicle models/parking/spinners: 37 passed, zero failures.
- Full living world and six ordered cases: 204 passed.
- Traffic network: 28 passed; 89/90 cars progressed during the far simulation, with 451 junction transfers and no same-direction overlaps. Near 45-second test: 12 observed, 11 moved over 8 m, seven still progressed in the last 15 seconds, zero overlaps.
- Leader-grid/physics optimization: nine passed.
- Movement/camera regressions: 114 passed.
- Actual imported porch traversal: 50 passed.
- Building streaming: 19 passed.
- Final rendered yard geometry/physics/streaming and five captures: 23 passed.
- Vehicle impacts, braking, shielded contacts, cooldown, recovery and pause behavior: all assertions pass. The fixture disables irrelevant honks to avoid audio-device teardown warnings during accelerated physics testing.
- Source audit: zero garden/path overlap, zero uncovered approaches, zero forbidden bin overlap, no changed building geometry, no paved area above four degrees.

## Unique residents: next content layer

The current crowd remains 1,200 ambient residents plus 15 individual actors. It is not yet 75% uniquely authored. About 900 distinct residents is feasible using persistent identity records with home/work anchors, relationships, appearance, a daily schedule and individual dialogue/event flags. Shared activity implementations can serve those records: porch time, work, shopping, park visits, walking and social groups.

Nearby residents would have physical agents, mid-distance residents batched visuals, and distant residents only schedule/state updates. Dialogue can be authored against the graph scaffold already added. Persistent NPC and case saves are still future work; current cases last for the visit. Start with roughly 30 fully authored residents and a complete block's routines, then expand block rosters. Distinct stories and reactive lines require content authoring; assigning random names alone does not satisfy meaningful uniqueness. Runtime dialogue need not call an AI service.

## Team

Astra-root coordination/integration (actual root model and effort not exposed); native GPT-6 Astra high for source landscaping and streaming; two native GPT-6.1 Sol high agents for UI/dialogue and traffic/impacts. Root alone ran serialized Blender/Godot validation. No Claude or Cursor agent used in this pass.
