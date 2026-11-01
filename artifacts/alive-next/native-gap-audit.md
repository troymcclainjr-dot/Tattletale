# Native review: what Pen Lucy needs next

Reviewed 2026-10-31. This is an independent source-and-evidence review of the **Godot Pen Lucy neighborhood**, not an inventory of features in an unrelated commercial game. The original two-stage block game is separate; its dispatch, arrest and finale code must not be counted as neighborhood functionality. No engine, build or gameplay mutation was performed for this review. Findings distinguish inspected implementation, recorded test evidence and proposed design.

## Assessment

Pen Lucy is already a substantial walkable neighborhood with grounded traversal, traffic, a large persistent-identity crowd, combat reactions, six cases, daily schedules, daylight, save recovery and geographic maps. Its main next step is **connecting those systems into a lasting play loop**. More people and props alone will not supply that loop.

The best bounded milestone is a complete neighborhood session: a clear opening goal; a case with an observable, saved outcome; believable response to violence; a reason to return to a business or civic place; and reliable continue/finish/restart UX. Player driving could substantially change the game, but should be an explicit design choice before production work starts.

No newly reproduced release-blocking engine bug is claimed here. P1 means needed for the next coherent playable/releasable milestone; P2 means worthwhile depth or polish after that milestone. Existing smoke tests are real strengths, but source inspection and old green logs do not certify the currently changing world.

## Foundations that should be preserved

| Area | Inspected implementation and evidence |
| --- | --- |
| Traversal/camera | `city_player.gd:588` sweeps a camera volume, contracts immediately at obstacles, eases outward, blends shoulder aiming and hides the player mesh when compressed. Movement, jump, porch and vehicle-roof suites exercise real collision; `city_movement_smoke_runner.gd:539–611` includes headroom, sloped curbs and camera-height continuity. |
| Cases/dialogue | Six explicit case definitions at `city_missions.gd:8`; read-only preview and validated commit at `:280–302`; range/sight checks at `:440`; one-time rewards and restoration. The corrected expansion fixture checks preview without mutation, then a committed choice. |
| Persistence | Versioned checkpoint, temporary/backup recovery, malformed-file preservation, equipment, clock, case state and deaths in `city_world_save.gd:1–120, 295–354`. The save fixture includes real scene teardown/reload and dead contacts at `city_world_save_smoke_runner.gd:232–268`. |
| Population | Twenty authored daily residents and 1,200 canonical crowd identities are separate systems. The recipe compatibility asset preserves ordinal death IDs through construction and crowd redistribution. Recent park/identity fixtures check birth anchors and restored deaths, not just population totals. |
| Traffic | Directed connected lanes, signals, junction reservations, braking and grounded collision are implemented; `city_traffic.gd:282–353,390–407` and `city_vehicle.gd:453–589`. Offscreen recycling checks both current and destination visibility/collision at `city_vehicle.gd:614`. Tire damage and gunfire reactions exist. |
| Performance architecture | Building/material batching, immutable map geography, vegetation LOD history, bounded mesh refreshes, streamed yard cells, bounded combat promotions and provider timings already exist. A blanket engine/language rewrite would discard useful measured work. |

References throughout use repository-relative source paths and verified line anchors so this report stays portable. Latest court evidence is in `.work/courts-lots-pass/published-check.json`; current world/camera tests remain root-owned.

## P1: connect the existing systems

### 1. The six-case loop finishes without a new chapter, durable outcome layer or clear completion experience

**Evidence.** `city_missions.gd:8–15` defines six cases. `case_steps()` at `:187–230` returns fixed sequences of contact/clue interactions. Its generated dialogue at `:280–291` offers continue or defer, while `:304–323` advances one linear stage. Completion at `:375–400` awards community points, shows a five-second effect, destroys the case objects and tells the player to keep looking for neighbors. `snapshot_state()` at `:326` stores active ID, stage, completed IDs and score. After all six are complete, `_available_offers()` skips every completed case; the general objective remains “Talk to people who need a hand.”

**Impact.** The player can finish all available work while the UI continues implying more offers. Repair/cleanup resolutions are predominantly text and transient case visuals. The current points have no inspected spending/unlock loop; they are a score, which is valid but should be presented that way.

**Safe next work.** Add an all-cases-complete objective and persistent case history; preserve spatial contact discovery rather than reinstating a generic case board. Derive a small world-outcome table from existing completed IDs, then restore exactly one visible result per suitable case: a repaired fixture, replacement notice or changed follow-up conversation. Do not award points again when rebuilding those visuals.

**Creative decision.** Choose whether the longer game is community investigation, crime sandbox, or an intentional mixture. Branching accusations, reputation, money, replayable jobs and new chapters require authored rules and consequences, not only additional JSON nodes.

**Acceptance.** Finish all six through the actual dialogue UI, save/reload, verify completion text, each selected world result and unchanged score; replay stale hooks and ensure no duplicate rewards. Existing `city_life_smoke`, `city_expansion_smoke` and `city_dialogue_smoke` are the base, with a fresh-process chapter-completion test added.

### 2. Violence has local reactions and permanent victims, but no coherent neighborhood consequence system

**Evidence.** `city_combat.gd:449–458` distinguishes local police/civilian reactions. `:494–499` deterministically arms roughly one civilian identity in three and all police. Melee ends after distance/visibility/time limits (`:833–858`); firearm confrontations similarly return after distance, lost sight or forty seconds (`:894–910`). The reviewed city modules contain no wanted-level, witness-report, dispatch, arrest or legal-state subsystem. Police traffic still uses the normal lane controller. In contrast, NPC deaths are recorded permanently (`:723–748`), and a required contact's death closes a case without reward (`city_missions.gd:67–74`).

**Impact.** Local fights can cool off while their permanent effects remain. A player can lose future case access without a broader visible account of what changed. The death/closed-case behavior is implemented and tested; it is not a save bug.

**Safe next work.** Make permanent consequences legible: a case-history reason for closure, persistent deceased-contact state in relevant dialogue, and clear distinction between local combat ending and a case being lost. Introduce a small event interface for witnessed incidents without yet choosing a wanted mechanic.

**Creative decision.** Define who reports violence, how police respond, whether surrender/arrest is possible, how escalation clears, and whether civilian arming rates fit the intended experience. Avoid automatically turning every nearby officer into an unlimited spawn/chase system. A single bounded witnessed-incident → local patrol response → resolution sequence would be a useful vertical slice.

**Acceptance.** Existing combat/reaction/death suites plus tests for an unwitnessed incident, an obstructed witness, duplicate reports, one response budget, explicit resolution and save/reload of any durable consequence.

### 3. Player defeat and resources need an intentional rule set

**Evidence.** `_hurt_player()` at `city_combat.gd:1196` sets a 3.5-second knockdown and sends aggressors home; `tick()` at `:220–225` restores health to 100 with temporary invulnerability. Passive health regeneration follows a safe interval at `:251`. Ammunition/reload exists (`:155,227–232,308–318`), but the reviewed neighborhood path has no replenishment/shop/medical transaction loop. Equipment is saved.

**Impact.** Permanent NPC death and short player knockdown are markedly different rules. That may be deliberate, but it currently does not connect to the new hospital/police/shop architecture. Exhausted ammunition naturally falls back to fists; it is not an established economy.

**Safe next work.** Explain the existing defeat and ammunition rules in onboarding/HUD, and test save/restore at zero ammo and near defeat. Keep current behavior stable until a chosen replacement is authored.

**Creative decision.** Decide between forgiving knockdown, hospital recovery, checkpoint retry, penalties or another model; choose how scarce ammunition should be. Do not add fines, inventory loss or forced respawn just because another game uses them.

### 4. Save protection is strong; continue/new-world UX and content migration are the gap

**Evidence.** `city_world_save.gd:32–41` deliberately refuses unstable combat/airborne checkpoints. `pen_lucy_level.gd:824–829` attempts saving on window close and then quits regardless of `ERR_BUSY`; `return_to_original()` at `:1011` also does not surface failure. Manual save provides useful feedback at `:1001`. Settings has Resume, Return to starting corner, Save progress and Main menu (`city_settings.gd:52–64`), but no inspected new-world/save-slot management flow. `city_world_save.gd:201–205` requires exactly twenty resident definitions; later validation derives the exact score from current case rewards. A new resident or reward rebalance can therefore reject an otherwise sound earlier checkpoint. Rejected bytes are protected, which is correct, but protection is not migration.

**Safe next work.** Show last successful checkpoint age and whether the current state can be saved. On the in-game return-to-menu route, report a failed checkpoint and offer a clear deliberate exit choice. Provide a backed-up, explicit Start fresh action rather than requiring file deletion. Add schema/content migration fixtures before increasing the authored roster or changing saved reward rules. Preserve canonical crowd IDs and append future identities.

**Creative decision.** Number of save slots, checkpoint versus full simulation persistence, treatment of irreversible lost cases, and whether restart is a normal menu action.

**Acceptance.** Existing corrupt/future/backup tests plus old-content migration fixtures, failed-save menu feedback, and restart that leaves a recoverable archive. Never silently replace an unsupported slot with an empty world.

**This-pass remediation.** Root is implementing a shared `request_leave` path for WM_CLOSE and Main menu: successful saving exits normally; a failed checkpoint presents the precise loss warning with explicit leave-without-saving or cancel. This addresses the original unchecked-save exit finding above. Implementation/fixture confirmation remains root-owned; migration and new-world UX are separate gaps.

### 5. The city needs a few usable destinations, not immediate interiors for every building

**Evidence.** `city_civic_district.gd:20–80` removes/replaces geometry and builds civic/shop meshes; `city_civic_businesses.gd` constructs signs and architecture. The level's interaction path at `pen_lucy_level.gd:556–615` is cases, registered conversations and walk check-ins. Civic documentation explicitly identifies the buildings as exterior architecture (`godot/README.md:318–322`). Courts/benches/playgrounds supply environments and crowd poses rather than player activity systems.

**Safe next work.** Define stable interaction anchors for one shop counter/front door and one civic service. Route through the existing prompt/LOS/dialogue system, use genuinely available destinations and preserve approach clearance. Add a refusal/closed message where relevant instead of an unexplained inert door. One court activity can be prototyped separately without changing ambient court reservations.

**Creative decision.** What the services actually do: purchases, information, reporting, recovery, social activity or mission handoff. Choose limited interiors/threshold scenes only when a concrete activity requires them.

## P1/P2: movement, population and presentation

### 6. Driving is a missing player verb, not a broken traffic system

**Evidence.** `city_vehicle.gd` is an autonomous path-following `CharacterBody3D` with damage and collision; `:389` accepts a route, and `:453` advances it. The player and city input handlers contain walking, jumping, orbit/aim, interaction, map and inspector controls, but no enter/exit vehicle or driving ownership state. Standing on moving roofs is a supported traversal feature, not vehicle control.

**Priority/design.** P1 **if** driving is part of the target fantasy; otherwise defer. First choose whether player vehicles are borrowed/owned/stolen and whether traffic cars can change controller. Prototype one enterable vehicle, explicit driver ownership, safe exit placements, camera transitions and save behavior before adding pursuit or vehicle missions. Reuse the collision model and lane data, not AI waypoint motion as raw steering physics.

**Acceptance.** Entry denied through walls; exit refused when blocked; no duplicate driver; parked and moving transition; menu/focus pause; damage continuity; streaming while occupied; checkpoint behavior; passenger roof behavior unchanged.

### 7. Scheduled residents currently commute along a frontage, not to actual work or leisure places

**Evidence.** `city_residents.gd:161–198` builds up to eighty one-metre steps in each direction along one selected street frontage. Work and leisure are corridor endpoints; home and sleep share a home index. Schedule timing and near/far simulation are real. The larger crowd separately has batched poses, walkers and bounded panic. There is no need to replace 1,200 identities with 1,200 expensive agents to improve this.

**Safe next work.** Give a small subset of the twenty named residents real business/park destinations and two or three visible context animations. Add a reusable arrival reservation and “unavailable destination” fallback. Validate cross-street links and doorway thresholds before expanding route reach.

**Creative decision.** Whether anyone enters interiors, what sleep looks like, which activities are persistent, and how much behavioral memory matters. Population density and varied groups already improved; further work should make activity readable rather than increasing the count.

**Acceptance.** A complete day transition test, destination conflict/yield cases, blocked-route recovery, after-combat rejoin, death persistence, and near/far activation without teleporting into view. Existing resident/recovery/crowd-cadence fixtures provide useful infrastructure.

### 8. Audio is a conspicuous connection gap

**Evidence.** `scripts/audio/audio.gd:20–77` pools ordinary `AudioStreamPlayer` effects and a short looping music track. Combat synthesizes shot/hit/swing/click samples and uses four nonspatial players (`city_combat.gd:1330–1370`). City calls inspected include combat, global horns (`city_vehicle.gd:385`), check-in and win effects. The city module search found no spatial audio player implementation or player-footstep calls.

**Safe next work.** Introduce a bounded spatial one-shot pool for existing world-position events; separate player feedback from distant-world events. Add distance attenuation for horns/shots, grounded footstep cadence with a few actual surface categories, and a restrained neighborhood ambience bed. Keep voice limits, pause behavior and volume buses explicit.

**Creative decision.** Music direction, voiced dialogue, ambient conversations and radio content need creative assets and an audio budget. No need to produce a radio system before driving exists.

**Acceptance.** Audible left/right/distance behavior, occluded sounds if implemented, no footsteps airborne/paused, pool saturation without leaks, saved volume settings, and an audio listening review. A screenshot cannot validate this.

### 9. Input/accessibility and camera options lag the existing controller quality

**Evidence.** `city_settings.gd:7,35–50` exposes display, quality, audio, sensitivity and invert-Y. Camera FOV exists (`city_player.gd:16,596`) and has a direct fixture check, but is not exposed in the current settings dictionary/UI. Reviewed project/city input is keyboard/mouse; no joypad binding/control path was found. Important actions also use direct keycodes in level/combat handlers. Text sizes and the keyboard reference are fixed.

**Safe next work.** Expose supported FOV and a modest text-size option; consolidate gameplay actions before building rebinding so direct keycode shortcuts do not bypass it. Add hold/toggle preference where the input state machine can honor it. Preserve existing orbit/movement-bearing behavior and the aim/camera collision tests.

**Creative decision.** Controller as a supported platform target, aim assistance, color/contrast modes and dialogue presentation scope. Design a real controller navigation/focus pass rather than adding stick movement alone.

**Acceptance.** Rebind every gameplay action including combat, correct prompts, conflicting binding handling, keyboard-only menus, controller disconnect/focus loss if supported, readable narrow-window UI, and aiming under porch/vehicle occlusion. Existing UI/movement tests remain required.

### 10. World continuity still needs targeted visual repair and believable edges

**Evidence.** Runtime retains AABB boundary collision (`pen_lucy_level.gd:401`) and fall recovery (`:879–885`); these are safety fallbacks rather than authored neighborhood boundaries. Current user-supplied location evidence identifies Row050 lawn coverage, a Frisby corner fence, Row170's blank front and firehouse-side grass. Source work already emphasizes access reservations and court/civic geometry; the recent court pass demonstrates why a bounding-box fit alone is inadequate.

**Safe next work.** Repair those exact places first, retain rear doors and bin collection access, then run a sampled facade/lot audit to find the same failure classes elsewhere. Add deterministic tree silhouette variation with existing batching/culling rather than hundreds of independent animated nodes. At edges use actual adjoining streets, service yards, walls/fences and restrained distant context; preserve traffic entrances/exits. Do not invent terrain features absent from the level.

**Creative decision.** The playable boundary's visual treatment and which side/rear yards are private versus accessible. A consistent rule should drive mapwide fences; surrounding every parcel would block existing routes and make the city less walkable.

## P1: verification, performance and delivery

### 11. Measured performance is useful but not a release envelope

**Evidence.** Recorded 1920×1080 Balanced private-viewport runs in `artifacts/civic-build/neighborhood-final/metrics.json` and `neighborhood-final-repeat/metrics.json` are both valid active-play samples of about twenty seconds on the same 75.5 m route. Delivered FPS was **125.54 and 100.80**; frame-time p95 **13.507 and 16.334 ms**, p99 **18.029 and 22.138 ms**. Startup was **23.879 and 24.741 s**; reported static memory about **827 MB**, video memory about **545 MB**. These are historical runs before the latest court/lot work, not fresh certification of this checkout. Private viewport results do not prove desktop presentation latency or all hardware behavior.

**Interpretation.** Variation is material. The sampled GPU times are low relative to several CPU metrics, but the source reports alone do not establish a single causal bottleneck; process/physics/render timings overlap and should not be summed. Recent batching work should be retained. Do not respond to every slowdown by lowering art detail or proposing a rewrite.

**Safe next work.** Make a fixed, versioned benchmark route matrix: dense Old York, civic frontage, park, narrow side street, night, combat panic and streaming return. Include cold/warm startup, repeated fresh runs, percentiles, active populations and cache status. Add a 10–20 minute traffic/resident/streaming soak. Record renderer/hardware/drivers and test an agreed minimum machine.

**Acceptance.** Set a frame-time and memory budget for the actual target configuration, then gate repeated regressions against it. Keep no-movement/paused/offscreen sample validity explicit. The existing `city_life_benchmark_driver.gd:1–40` and component flags are a strong starting point.

### 12. Shipping currently means a source checkout plus Godot, not a verified standalone package

**Evidence.** `Play Pen Lucy.cmd` discovers a Godot executable, falls back to a workstation installation, redirects APPDATA into `.work/play-profile`, imports source assets, then launches the city scene. `project.godot` still starts the original title scene. No `godot/export_presets.cfg` or `.github/` directory was present in this reviewed checkout. Many focused fixtures exist; a single release manifest/runner and clean-machine exported-build smoke were not found in the inspected delivery paths.

**Safe next work.** Add a versioned export preset and explicit entry/continue experience; validate an exported package from a clean profile with no editor/.work/cache dependencies. Package asset attribution/font notices and a concise controls/help page. Keep authoring inspector/debug helpers out of the normal player experience unless intentionally exposed. Add a serialized test manifest with timeouts, isolated save profile, log collection and a final pass/fail summary.

**Creative/product decision.** Supported operating systems, installer versus archive, intended title-screen flow, development inspector availability, and minimum hardware. Do not imply a Steam/cloud/console plan without those choices.

**Acceptance.** Unzip/install on a machine without the source tree or Godot editor; launch, play a case, save, quit, relaunch, continue, change settings and close cleanly. Check missing assets, runtime shader compilation, first-run load time, paths with spaces/non-ASCII names and write permissions.

### 13. Documentation and verification need one current source of truth

**Evidence.** Earlier sections of `godot/README.md` still state visit-only mission progress and old crowd/park/court totals, while the later daily-resident section describes persistent checkpoints correctly. Recent court evidence now has different counts again. There are numerous valuable individual fixtures, but many are called by direct hooks; an integrated normal-input session remains a distinct test obligation.

**Safe next work.** Keep dynamic counts in generated acceptance summaries, shorten the hand-maintained README to actual controls/contracts, and maintain a test map linking each user-visible feature to its integration fixture and last run. Add one normal-input “start → discover → complete → save → reload → quit” run, plus an irreversible-action scenario using an isolated slot. Continue keeping visual review separate from headless checks.

**Acceptance.** Documentation agrees with saved behavior and current runtime counts; fixture versions are tied to source/content fingerprints; failures never get resolved by weakening counts or bypassing the UI behavior being tested.

## Suggested order and ownership boundaries

1. Finish the authorized location repairs with geometry/access tests and fresh normal-camera review. This is already requested work, not a substitute for the gameplay milestone.
2. Implement small correctness/clarity work: case completion state, persistent closure reasons, save freshness/failure feedback, supported camera/settings options, and current documentation.
3. Choose the defining gameplay direction and player-driving requirement. Author one connected civic/business/case consequence slice under that decision.
4. Add bounded spatial sound and a small number of real resident destinations, with measured population/update budgets.
5. Build the standalone release/test path and run a longer stability matrix before increasing content scale.

The following are **not authorized by this report alone**: inventing a wanted/arrest economy, changing the existing permanent-death rules, deleting saves, converting every crowd identity to a full AI actor, building every interior, adding multiplayer, or replacing the engine. They are optional creative/product decisions, not fixes justified by the present evidence.

## Current review limits

This review inspected source, metadata, existing fixtures and recorded measurements. It did not run new gameplay sessions, claim the latest geometry has passed engine integration, compare copyrighted game implementations, or use web material as a proxy for this repository. Independent Opus findings should be compared against these file-level claims; disagreements should be resolved by a focused reproduction before edits.
