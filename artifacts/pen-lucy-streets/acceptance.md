# Baltimore streets, navigation and parks — 2026-10-30

## Changes

- Loading reads **WELCOME TO BALTIMORE**, without the prior kicker or “Real streets” line; the first-visit warning remains. Settings use a black background, light text, the original fonts, and half-width sliders with adjacent values.
- Accepting a case shows a yellow destination ring and route on both the full map and circular minimap. Guidance follows the current stage, refreshes for moving targets or deviation, trims followed segments, and clears on cancellation/completion. A shared cached AStar graph uses surveyed street and authored walking-route segments; endpoint links are checked against solid geometry. If no safe route exists, the destination remains without a guessed line through buildings. Static map geography stays cached.
- **Space** jumps during exploration, with running momentum, ceiling collision, a 120 ms input buffer and 100 ms coyote window. No double jump. Pausing freezes a jump; dialogue keeps Space as Confirm. Original-block controls are unchanged.
- Two small park half-courts (14×10 m and 12×9 m) have planar slabs, gentle aprons, painted markings and solid hoop poles. Court grade is at most 1.5%, apron slope at most 3.66 degrees and fill about 12 cm. One rendered surface per court, 2,818 triangles total. Floor collision remains when distant visuals cull. Three overlapping trees removed; 1,809 retained. Park residents remain outside playing areas.
- 275 continuous hedge rows along 271 homes replace the small front-yard bush clusters, preserving stair approaches. There are 469 original-port cans and 51 dumpsters (520 bins versus 350 before), plus 4,619 non-colliding litter pieces. All 5,414 yard anchors pass actual imported-ground checks within 2 cm. Sixty-eight litter placements near sidewalk height transitions were removed rather than relaxing grounding tolerance.
- All lamp/signal/stop bases are validated against actual sidewalk polygons and complete buffered footprints, including crossing roads, ground support and nearby obstacles. Old York/39th rejects road-intersection placements. There are 21 runtime streetlamps, four signal heads and 87 signs connected to unsignalized lane stop controls. Lamp and stop geometry share two batches. Thirty-seven worn crossings connect supported sidewalk landings, with every stripe wholly on asphalt.

The existing 1,215 NPCs, 90 moving vehicles, 144 parked vehicles, four police cars, driver profiles, collision-safe impacts, original model style, building collision and streaming remain. Cases still last for the current visit. Courts provide scenery and traversal, not a basketball minigame.

## Validation

- Jump/controller: 15 passed; movement/camera regression: 114 passed; vehicle-impact suite: all assertions passed.
- Navigation unit: 9 passed; all six playable cases and per-stage routes: 325 passed.
- Final rendered UI: 85 passed, zero failures or backend skips. Loading/settings/map/conversation/jump captures also completed. Space-confirm cannot trigger a player jump.
- Final rendered yard geometry, streaming and five captures: 24 passed. Only bins create collision, paths remain clear, all anchors grounded, no geometry rebuilds while travelling.
- Final rendered court grounding, actual player traversal/jump/landing, population clearance, culling and two captures: 20 passed.
- Final rendered street fixture/control/crossing audit and three captures: 125 passed. Headless equivalent: 122 passed.
- Traffic network: 28 passed. Near simulation: 13 cars observed, 12 progressed over 8 m and nine continued in the last interval; far simulation: 87/90 progressed, 76 in the last interval. No same-direction overlaps in either fixture.
- Source support audit: 11,410 samples; no court/road/building overlap or terrain penetrating a playing surface. Existing building/context geometry hashes are unchanged; the city GLB did not need rebuilding for this pass.
- Six focused Python regressions passed for garden/path clipping, original-can winding, continuous hedge placement, court constraints and empty-court vegetation retention. Final AST-only graph update: 1,540 nodes and 2,947 edges; Git whitespace validation passes.

PNG captures were rendered in unfocusable offscreen Godot windows with a separate test profile. No CUA, desktop keyboard/mouse capture or interruption of the user's running game was used. Loading and UI captures deliberately select their tested states; they are not performance measurements.

## Performance

`performance/metrics.json`: RTX 3070 Ti, 1920×1080, Balanced, 100% render scale, uncapped, VSync off. Actual 15-second offscreen walk with a real accepted mission and the full population/traffic active. Screenshot writes are outside the timed sample.

Delivered **178.87 FPS**; frame median **5.121 ms**, p95 **8.975 ms**, worst **29.076 ms**. Median draw calls **1,636**. Player covered **57.02 m**, zero stalled windows. One mission-route build, ten route points, two static map builds. Yard cache: 172 hits, zero travel geometry builds, errors or missing nearby cells; setup 153 ms, maximum activation 0.310 ms and attachment 0.054 ms.

The prior content-pass offscreen sample was 179.18 FPS with 1,617 median draws, p95 9.181 ms and worst 33.959 ms. These background samples suggest the additions did not introduce a large regression at this location, but are not controlled foreground comparisons or a promise of frame rate throughout the map.

## Team

Astra-root integration and validation (actual root model/effort not exposed); native GPT-6 Astra high for landscaping/source geometry; two native GPT-6.1 Sol high agents for UI/navigation and street fixtures/traffic controls. Root alone ran serialized engine validation. No Claude or Cursor agent used for this pass.
