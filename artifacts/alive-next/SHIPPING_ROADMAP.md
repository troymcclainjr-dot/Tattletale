# Pen Lucy shipping roadmap

**Author:** Claude Opus 5.5 (high effort), synthesis pass. **Date:** 2026-10-31.
**Inputs:** `artifacts/alive-next/native-gap-audit.md` (native review), `artifacts/alive-next/opus-gap-audit.md` (Opus review), and spot checks of the current source (cited below as `file:line`, read during this pass).
**Authorship:** Opus authored the roadmap read-only. The root agent subsequently updated its status tables against final integration evidence; the original planning checklist is retained in `.work/alive-next/auto-fixes.json`.
**Companion checklist:** `.work/alive-next/auto-fixes.json` holds the prioritized AUTO tasks this roadmap refers to as `AF-xx`.

**Current-status clarification (2026-10-31):** The missing OpenStreetMap credit finding is **resolved**, not an outstanding blocker. Credits are present on the full map, beside the radar, and in Settings/release notices; the clipped radar credit was also repaired and visually tested. Original review observations and milestone entry conditions below describe their earlier snapshot; use §11, `roadmap-status.json`, and `AUDIT_DISPOSITION.md` for implementation status. The later CPU and rendering work is recorded in `artifacts/performance-source/REPORT.md` and `artifacts/render-tightening/REPORT.md` (about 23% fewer draw calls on the measured route). This does not certify all public-release licensing obligations or all performance scenarios.

---

## 0. How to read this

- **Scope.** This is a roadmap for shipping a *small, reviewable* Pen Lucy build. It does not promise GTA scope and does not choose a product vision. Where the genre normally implies a feature (driving, police heat, death stakes), this document puts the choice to you as a **decision** (§3) and does not schedule production work for it.
- **Prototype defect vs creative decision.** A *defect* is behavior that is wrong or unsafe by the game's own current rules: lost save progress, a missing legal credit, unbounded cost, a silent failure. Defects are AUTO work, and you have authorized all non-fundamental fixes. A *creative decision* changes what the game is. Those wait for you.
- **Status words.** *Verified* = I read it in current source this pass. *Recorded* = an artifact or log says so. *Underway* = an owner is implementing it now; its acceptance is theirs. *Not finished* = AUTO work that this bounded pass did not implement. Every such item is listed by name in §11. None of them is hidden under "future".
- **Comparison sources.** The coordinator checked the official GTA V help manual (Xbox-hosted game manual URL in the brief) and the Godot docs pages *Using MultiMesh* and *Mesh level of detail (LOD)*. I do not quote any of them. The GTA manual is used only as a reminder of which genre categories the brief already names. No requirement here is derived from it. The Godot pages are paraphrased in §7 and should be checked against the live pages before anyone relies on the details.

---

## 1. Where the project actually is

### 1.1 Foundations both audits say to preserve

Both reviews independently reached the same conclusion: the engineering base is careful, and the gap is the **play loop and the shipping envelope**, not rigor or language. Do not churn these:

| Foundation | Why it matters |
|---|---|
| Swept capsule/camera/vehicle collision, curb/step solver, camera contraction | Traversal feel and stability; heavily fixture-tested |
| Deterministic combat with bounded fighter/panic/corpse budgets | Combat cannot run away with frame time |
| Atomic save (temp → validate → rename, `.bak`, rejected bytes preserved, future-version refusal) | Better than most indie saves. Fix the UX *around* it, not the protection |
| Directed lane network with junction reservations, signals and offscreen-only recycling | Traffic works. Driving is a missing verb, not a broken system |
| 20 canonical daily resident IDs + 1,200 canonical crowd identities with permanent deaths | Identity persistence is a feature. **Not to be cut.** See §1.3 |
| Batching, streaming, vegetation presence, provider timings | Measured work that a rewrite would throw away. Both audits reject an engine or language rewrite |

### 1.2 Completed current pass

Phone photography, six vehicle models, modular people, tire handling, world repairs, melee witnesses, bounded spatial audio, save recovery/exit feedback, FOV, case ledger, notices, attribution and standalone packaging are implemented. The final Fable audit is complete and its concrete runtime findings were applied.

See [implementation and final evidence](C:/files/projects/Tattletale/artifacts/alive-next/IMPLEMENTATION_AND_REVIEW.md), [audit dispositions](C:/files/projects/Tattletale/artifacts/alive-next/AUDIT_DISPOSITION.md), and [performance measurements](C:/files/projects/Tattletale/artifacts/alive-next/PERFORMANCE.md). The accepted suite index contains 35 cases; it preserves the historical failure and records the UI-only correction without changing runtime code.

### 1.3 Population: fixed facts (not open to optimization)

- The 20 canonical daily resident IDs and the 1,200 canonical crowd identities persist.
- Twenty new modular looks (16 Black, 2 Hispanic, 2 White) are **reused across** residents and crowd. That is an appearance system, **not a population cut**. No AUTO task in this roadmap reduces counts to buy performance.
- Future identities are **appended**, never renumbered. Saved crowd deaths are keyed `crowd_<index>` (`city_world_save.gd:252-254`), so reordering would move deaths onto different people.

### 1.4 Performance: what is known

- **Fresh baseline (coordinator-supplied, this checkout):** 1920×1080, Balanced, 4× MSAA, active private viewport: **184.88 FPS, 1,495 draw calls, 2.035 ms GPU median, 2.026 ms render-CPU median.**
- **Historical:** recorded runs at **125.54 and 100.80 FPS** on the same route (`artifacts/civic-build/neighborhood-final*/metrics.json`). The Opus audit also cites roughly 190–200 FPS and about 1,360 median draw calls from `artifacts/life-reactions/performance-summary.json`.
- **Interpretation:** the 100–126 FPS variability is **unresolved**. The higher fresh number is **not** evidence of a new optimization, and this roadmap does not treat it as one. Final integrated runs delivered 123.1–135.2 FPS, with 1,565–1,576 median draws. See PERFORMANCE.md for timings and controls; no minimum-spec guarantee is implied. All runs so far are on one RTX 3070 Ti. Nothing has been measured on low-end hardware, at a Low preset, at 720p, or in an exported build.

---

## 2. Reconciling the two audits

They agree on the large picture. Where they differ or the brief overrides them, this is the resolution:

| Topic | Native audit | Opus audit | Resolution in this roadmap |
|---|---|---|---|
| Save failure | Exit path unchecked; no Start-fresh; migration needed | Boot ignores a failed load; `_write_blocked` locks the session; roster hard-coded to 20 | Exit path is now handled by root (§1.2). **Still open (verified):** boot ignores `ok:false` (`pen_lucy_level.gd:276-277` only branches on success), and `save_progress` still says "previous checkpoint is retained" even when writes are blocked (`:1028`). → AF-01..AF-03 |
| Roster tolerance | Add migration fixtures before changing roster/rewards | Make the validator tolerant now (A-2) | The canonical 20/1,200 IDs persist, so roster churn is *not* imminent. Do migration fixtures and an append-only crowd fingerprint (AF-16, P2). Do not loosen validation ad hoc |
| OSM credit | Not raised | Missing in-game at review time; public-release attribution issue | **Resolved, AF-04.** Full-map and radar credits plus Settings/release notices are implemented. FA-01 repaired clipping; rendered attribution checks passed. |
| F6 inspector | Keep debug helpers out of the normal experience unless intentionally exposed | Gate F6 behind a flag (A-16) | **Overridden by you: F6 inspection stays available.** It remains listed in Controls (`city_settings.gd:52`). Not gated. Release exposure is recorded as decision D8 for later, not as an AUTO fix |
| Footsteps | "Grounded footstep cadence" | "No footsteps" listed as a gap | **You rejected synthesized beeping footsteps. Not recommended.** Footsteps exist only as a creative decision about *recorded/authored* surface sounds (D7) |
| Ammo | Explain the rules; keep behavior until a replacement is authored | A-5 refill stopgap "if product approves" | Refill policy is economy design → D4. AUTO is limited to *stating* the current rule (AF-29) |
| Contact mortality | Make loss legible; don't change permanent-death rules | Recommends non-lethal named contacts + fungible police | Rule change → D3. AUTO is limited to legibility: case-lost ledger entries and reasons (AF-14), plus a measurement of crossfire contact-death frequency (AF-30) |
| Damaged-car cost | — | Drop physics retention for flat-tire cars far away | Tire work *deliberately* keeps damaged moving cars physics-active so distant swerves stay collision-checked (`city_vehicle.gd:461`; tire report). Bound the cost by **offscreen recycling** of distant damaged cars instead (AF-12). Do not remove the retention |
| Destinations | One shop counter + one civic service anchor | Interiors are PRODUCT | Anchor plumbing plus an honest "closed/unavailable" message is AUTO-ready only once D5 says what a service does. Listed under D5, not AUTO |
| Resident routes | Give a subset real destinations | — | Behavior depth that depends on D5 (destinations). Kept in M5 |

---

## 3. Creative and product decisions (yours)

None of these are scheduled as production work. Each lists what it blocks, so you can see the cost of deferring it. The AUTO work in §4–§6 is designed to be valid under **any** answer.

| ID | Decision | Questions to answer | Blocks |
|---|---|---|---|
| **D1** | **Player driving** | In v1 or not? Arcade kinematic controller reusing the existing collision sweeps (both audits lean away from `VehicleBody3D`), or something else? Borrowed, owned or stolen cars? Can traffic cars change controller? What happens on pedestrian contact? | Vehicle missions, pursuits, any police vehicle role, map scale assumptions, the M5 driving slice |
| **D2** | **Crime/heat policy** | Is the city loop *reporting* crime (the snitch premise in `README.md:5`), *committing* it (heat on the player), or both? Who reports? How do police respond and de-escalate? Are civilian arming rates (about 1 in 3, plus all police) intended? | Any wanted/heat system, police car behavior, the M5 consequence slice. Melee witness (AF-06) is valid under any answer: it only makes existing local reactions consistent |
| **D3** | **Death/arrest stakes** (player and named contacts) | Keep the 3.5 s knockdown with full heal (`city_combat.gd` `_hurt_player`), or hospital/precinct recovery, checkpoint retry, penalties, or arrest/surrender? Named contacts: permanent lockout (current, test-asserted), non-lethal, or role substitution? | Any respawn or arrest flow, case resilience rules |
| **D4** | **Mission narrative and economy** | Chapter structure after the six cases; what community points are for (currently a score with no sink); ammunition sources (12 + 72 per save, never refilled); replayable jobs; an ending | Mission content production, any shop, the data-driven case pipeline's content (the loader itself is AUTO, AF-28) |
| **D5** | **Interiors and destinations** | Which places, if any, are enterable or have a counter/threshold scene? What does each service actually do? | Destination anchors, resident work/leisure routes, shop/civic gameplay |
| **D6** | **Platform and minimum spec** | Supported OS(es); minimum GPU/CPU/RAM; controller/Steam Deck support; zip vs installer; storefront; code signing | The performance gate in M3, input scope beyond keyboard/mouse, release packaging |
| **D7** | **Audio direction** | Music for the city (the bundled track was rendered from the original web game's `js/audio.js`); ambience bed; recorded surface footsteps or none (**not** synthesized beeps); voiced dialogue | Ambience/music production. Bounded spatial one-shots (AF-07) are not blocked |
| **D8** | **Entry flow and debug exposure** | `project.godot` still boots `res://scenes/main.tscn` (the original game). Does a shipped build start at a title screen, the original block, or the city? Should F6 remain in release builds? (It stays available **now**, per your instruction) | The export's entry scene; release controls text |
| **D9** | **Save model** | One slot or several; whether "Start fresh" is a normal menu action; how irreversible lost cases are presented | Save-slot UI beyond the non-destructive Start-fresh (AF-02) |

---

## 4. Milestones

Each milestone has entry conditions, exit acceptance and dependencies. **No time estimates are given.** Throughput depends on worker availability and on your decision turnaround, and I have no basis for durations.

```
M0 Integrate current pass ──► Fable 5.1 HIGH audit ──┐
                                                     ├─► M1 Defect closure ─┬─► M2 Standalone build candidate ─► M3 Performance envelope
                                                     │                      │                                          │
                                                     └──────────────────────┴─► M4 Decision gate (D1–D9) ───────────────┴─► M5 Vertical slice ─► M6 Release candidate
```

### M0. Integrate the current pass and audit it

- **Entry:** the owner of each §1.2 underway item reports it implemented.
- **Work:** root integrates and runs every touched fixture under the strict engine-error gate and serialized validation. The phone fixture is rerun (headless and `--phone-render`) because its last recorded run failed to compile.
- **Exit acceptance:**
  1. A fresh serialized validation summary with **zero** script/parse errors and every case passing, tied to source hashes. The existing `summary.json` already records `source_sha256`.
  2. Fresh normal-camera review of the user-identified world spots.
  3. **The Fable 5.1 HIGH audit runs against the integrated tree**, and its findings are triaged into AUTO (appended to `auto-fixes.json`) or decisions. That audit must follow integration, not precede it.
- **Depends on:** nothing new. This is the current pass.

### M1. Prototype-defect closure (AUTO, no creative input)

- **Entry:** M0 exit. Do not stack new edits onto uncertified integration.
- **Work (P1 in `auto-fixes.json`):** visible save failure on boot plus non-destructive Start fresh (AF-01, AF-02); honest blocked-save messages (AF-03); OSM attribution (AF-04) and credits/notices (AF-05); melee witness (AF-06) and bounded spatial audio (AF-07) if not finished in M0; audio pause with menu/phone/dialogue and saved-slider music on direct launch (AF-08); a notice queue (AF-09); hard failure for contact placement (AF-10); offscreen recycling for distant damaged cars (AF-12); case-lost reasons in the ledger (AF-14); and the normal-input full-session test (AF-25).
- **Exit acceptance:** every P1 task's acceptance in `auto-fixes.json` passes in a serialized run. No existing fixture is weakened (count reductions, skipped UI paths). One scripted *normal-input* session works: start → discover a case → complete → save → quit → relaunch → continue. Docs agree with behavior (AF-18).
- **Depends on:** M0.

### M2. Standalone Windows build candidate

- **Entry:** M0 exit. Can overlap M1, but **M2 exit requires AF-04 and AF-05** (legal credits), because a build without them must not be distributed.
- **Work:** root's export attempt (AF-20); `user://` save location and log location in the exported context (AF-21, AF-31); entry scene per D8. Until D8 is decided, the candidate may launch the city directly *for testing only*.
- **Exit acceptance:** on a clean Windows profile, with no source tree, no Godot editor, no `.work/` and no import cache: unzip → launch → play a case → save → quit → relaunch → continue → change settings → close cleanly. Also checked: no missing resources; first-run shader compilation observed and timed; install paths with spaces and non-ASCII characters; a read-only install directory with writes going to `user://`; logs written to `user://logs`; credits visible. The exported build passes the city smoke in the exported context.
- **Not claimed:** signing, installer, storefront (D6).
- **Depends on:** M0 (M1 legal items for exit).

### M3. Performance envelope

- **Entry:** M2 candidate exists, so measurements reflect the exported build and not only the editor's private viewport.
- **Work:** variance study first (AF-22), then the profiling matrix (§5) and soaks (AF-24).
- **Exit acceptance:** a written envelope with numbers *you* approve for the D6 minimum spec, plus regression gates. Until D6 is answered, M3 can only certify the reference machine. Even then it is reported as "reference only, not minimum spec".
- **Depends on:** M2, plus D6 for the minimum-spec half.

### M4. Decision gate

- **Entry:** any time. Answering D1–D9 early is the cheapest unblocker. M1 and M2 produce a playable, honest build to decide against.
- **Exit:** each decision is answered or explicitly deferred out of v1. Answers are recorded in a short decisions file. Each answered decision gets its own acceptance list before production starts.
- **Depends on:** you.

### M5. Vertical slice of the chosen loop (conditional)

Only what D1–D5 select. Candidate slices, each bounded to *one* instance:

- **If D1 = driving in v1:** one enterable vehicle. Acceptance (from the native audit): entry refused through walls; exit refused when blocked; no duplicate driver; parked and moving transitions; menu/focus pause; damage continuity; streaming while occupied; defined checkpoint behavior; passenger-roof traversal unchanged.
- **If D2 selects a consequence model:** one witnessed incident → bounded local response → explicit resolution. Acceptance: unwitnessed and obstructed-witness cases; duplicate reports; one response budget; save/reload of any durable consequence. No unlimited spawning.
- **If D5 selects a destination:** one shop or civic interaction anchor through the existing prompt/LOS/dialogue path, with a "closed" fallback, plus a small set of named residents routed to real destinations, with arrival reservation and blocked-route recovery.
- **D3/D4:** one implemented defeat rule and one points/ammo rule, each with save/restore fixtures at the edge states (zero ammo, near defeat).
- **Exit acceptance:** the slice passes its list; M3 regression gates still hold; the Fable (or successor) audit is rerun on the slice.
- **Depends on:** M4 answers, M1, M3 gates.

### M6. Release candidate

- **Entry:** M5 (or an explicit "no slice in v1" decision), with M2 and M3 green.
- **Exit acceptance:** clean-machine matrix on D6 hardware; 60-minute mixed soak plateaus; release manifest of tests run with pass/fail and source/content fingerprints; credits/notices complete; README is reduced to current controls and contracts (counts come from generated summaries).

---

## 5. Performance envelope and profiling matrix

### 5.1 Principles

- Report percentiles (frame-time p50/p95/p99, worst frame), not just mean FPS.
- Process, physics and render timings overlap. Do not sum them, and do not infer a single bottleneck without a targeted A/B.
- Every sample records: build type (editor or export), renderer, MSAA, preset, resolution, window mode (private viewport or real presentation), GPU/driver, CPU, RAM, shader cache state (cold or warm), active populations (physics cars, promoted actors, panic count, streamed cells), and a validity flag (moving, unpaused, onscreen).
- Do **not** respond to slowdowns by cutting population or art (§1.3). Look first for unbounded *work counts* (both audits).

### 5.2 Step 1: resolve variance before setting gates (AF-22)

Run the existing `city_life_benchmark_driver.gd` route N times in fresh processes on the reference machine at the coordinator baseline config, then report the spread. Hold cache state, power plan, background load and window mode fixed, and vary them one at a time. Only after the 100–126 vs 185 FPS spread is explained or bounded can a regression threshold mean anything.

### 5.3 Matrix

Rows are scenarios. Columns are configurations. Cells hold p50/p95/p99 frame time, draw calls, GPU median, render-CPU median, physics tick p95, and memory.

| Scenario | Ref: 1080p Balanced 4×MSAA (baseline) | Ref: 1080p real presentation (export) | Ref: Low preset 720p | D6 minimum spec (TBD) |
|---|---|---|---|---|
| Dense Old York Road walk (existing route) | ✔ baseline exists | M2/M3 | M3 | M3 after D6 |
| Civic frontage (police/fire/hospital/courthouse) | M3 | M3 | M3 | after D6 |
| Park and courts | M3 | M3 | M3 | after D6 |
| Narrow side street / back lots | M3 | M3 | M3 | after D6 |
| Night (lights/windows active) | M3 | M3 | M3 | after D6 |
| Combat panic: 8 fighters + 16 panic, sustained 5 min | M3 | M3 | M3 | after D6 |
| Fleet tire damage: puncture many cars, walk away | M3 | M3 | — | — |
| Streaming return: leave and come back across cells | M3 | M3 | M3 | after D6 |
| Phone raised + photo capture (SubViewport render) | M3 | M3 | M3 | after D6 |
| Cold vs warm startup to `level_ready` | M3 | M3 | M3 | after D6 |

**Soaks (AF-24):** 30-minute headless traffic (no car blocked offscreen for more than 60 s, no orphan reservations); 60-minute mixed walk/combat/traffic (object/resource counts and memory plateau); fleet tire damage (physics-car count returns near baseline after walking away). The life-reactions artifact already notes that no sustained-gunfight measurement exists.

### 5.4 Envelope shape (numbers deliberately not set)

The gate format is: *for each matrix row on target hardware, p95 frame time ≤ X and p99 ≤ Y, peak memory ≤ Z, warm startup ≤ S, and no regression > R% against the last certified run.* Picking X/Y/Z/S/R before D6 and the variance study would be fabrication. The Opus audit's suggested "≥ 60 FPS p95 on min spec" and "≤ 15 s warm start" are reasonable **candidates for you to accept or change**. They are not established requirements.

---

## 6. Content-production architecture

The pipeline already in the repo, and the rules that keep it shippable:

1. **Authoring.** `blender/city/*.py` and `blender/assets/*` generate geometry from OSM-derived footprints (`blender/city/data/pen_lucy_buildings.geojson`) and public-domain USGS 3DEP LiDAR. They publish GLB models and JSON data into `godot/assets/models` and `godot/assets/data`. Publication is atomic and checks counts and clearance (court and yard tests exist under `blender/city/test_*.py`). **Rule:** every published asset has a script source, a test, and a provenance entry (AF-05). The six new vehicle models from the external worker need the same provenance record.
2. **Runtime data.** Godot modules (`scripts/city/*.gd`) load JSON (`pen_lucy_level.json`, residents, crowd recipe, population appearance, modular roster, courts, civic, vegetation). **Rule:** identities are append-only. Dynamic counts belong in generated acceptance summaries, not the hand-written README (AF-18).
3. **People.** 20 canonical residents + 1,200 crowd identities, with 20 modular looks reused through `PopulationAppearance`/`ModularPeople`. The crowd renders batched; a person is promoted to a full actor only when needed (bounded budgets), keeping their look (underway). **Rule:** add variety by adding looks or animations to the roster, never by changing identity counts or order.
4. **Instancing and LOD (paraphrasing the Godot docs; verify against the live pages).** A MultiMesh draws many copies of one mesh in a single draw call, but it is culled as a whole, so very large spreads should be split into spatial chunks that can be culled independently. Mesh LOD reduces vertex work for distant meshes (Godot can generate LODs on import, selected by screen-space size), but **it does not reduce draw calls**. Draw-call pressure (≈1,495 at baseline) is a batching, MultiMesh and visibility-range problem. Implication for new props (fences, pines, facade details): batch per cell, reuse the existing streamed cells, and prefer MultiMesh or merged meshes over per-node instances.
5. **Missions.** The six cases are hard-coded in `city_missions.gd`. A behavior-preserving data-driven loader (AF-28) is AUTO-safe and makes D4 content cheaper. Writing new chapters is D4.
6. **Validation.** Headless smoke suites plus offscreen render validation, run serialized under a strict engine-error gate, produce a summary with source hashes. **Rule:** visual review stays separate from headless checks, and integration tests use normal input where the feature is player-facing (AF-25).

---

## 7. Source, export, build and asset-license requirements

| Requirement | Current state (verified unless noted) | Action |
|---|---|---|
| Export preset for Windows Desktop | No `godot/export_presets.cfg` | Root attempting (AF-20). Export templates must match engine **4.7.2.stable** (from engine logs) |
| Entry scene | `project.godot` `run/main_scene="res://scenes/main.tscn"` (original game) | D8; test candidates may boot the city directly |
| No editor dependency | `Play Pen Lucy.cmd` finds a Godot executable, redirects `APPDATA` into `.work/play-profile`, and imports on launch (both audits) | Exported build uses standard `user://`. Keep the `.cmd` for development. Document both save locations and never auto-move saves (AF-21) |
| **OSM attribution** | **Implemented:** full-map credit (`city_map_overlay.gd`), radar credit (`pen_lucy_level.gd`), Settings Credits and `release_notices.txt` | AF-04 complete; rendered bounds/pixel checks passed. Maintain credits and licence information in subsequent builds. OSMF's computer-game guidance permits suitable game/menu/credits/startup locations; permanent map-corner text is the project's choice, not the only permitted presentation. |
| **ODbL share-alike** | `pen_lucy_buildings.geojson` is a derived database "share it only under ODbL" (`blender/city/README.md:236-238`). The portable source distribution and shipped JSON contain OSM-derived data | Risk R6: confirm how shipped data files are licensed and offered before public distribution. This is a legal question, not an AUTO fix |
| Fonts | OFL texts and `SOURCES.json` with hashes in `godot/assets/fonts/` | Include the OFL texts in the export and credits (AF-05) |
| Godot engine license and third-party notices | Not surfaced in the city UI | Godot's license terms require its copyright/license notice (and its bundled third-party notices) to ship with the game. Add to credits/notices (AF-05). Check the Godot *Complying with licenses* doc page |
| Audio | Rendered from in-repo `js/audio.js` (`godot/README.md:210`) | Record provenance (AF-05) |
| Models | Built from in-repo Blender scripts (commit `e4ee494`); six new models from the external worker | Provenance record per model, including the six new ones (AF-05) |
| LiDAR | USGS 3DEP, public domain | Credit as courtesy |
| Excluded sources | Google Maps / Street View / 3D Tiles not used (`blender/city/README.md:239`) | Keep it that way. Add a review check to the asset manifest |
| Logs and crash surfacing | Development logs under `.work/`; exported behavior unverified | AF-31: logs to `user://logs`, collected by the exported smoke |
| Release test manifest | Serialized validation underway; no single release manifest | M6: manifest of every suite, timeout, isolated save profile, pass/fail, fingerprints |
| graphify coverage | My `graphify query` this pass again returned only JS/PY/MD nodes, no GDScript | AF-19 (tooling) |

---

## 8. Risks (no fabricated estimates)

| ID | Risk | Why it is real | Mitigation |
|---|---|---|---|
| R1 | Integration collisions | Phone, tires, people, models and world work all touch shared files (`pen_lucy_level.gd`, `city_player.gd`, `city_vehicle.gd`). The phone fixture already failed once on a parse error | M0 before M1; serialized validation; strict error gate |
| R2 | Save incompatibility after content changes | Exact-20 roster check (`city_world_save.gd:195`), index-keyed crowd deaths, reward-derived score validation. A blocked save is currently silent at boot | AF-01..03 now; AF-16 migration fixtures before any roster, crowd or reward change |
| R3 | Unexplained performance variance | 100.80 / 125.54 / 184.88 FPS across runs with no causal account | AF-22 before any gate; never claim an optimization from these deltas |
| R4 | Unmeasured hardware | Only an RTX 3070 Ti; Vulkan device loss seen in hidden-window benchmark startups (`artifacts/render-audit/acceptance.md`, recorded, cause unproven) | D6, then M3 on that hardware; keep device-loss logs in the exported smoke |
| R5 | Driving scope | No controller exists; touches camera, input, traffic, save, streaming and missions | D1 first; one-vehicle slice with explicit acceptance; reuse the existing collision sweeps |
| R6 | ODbL obligations | Derived OSM data ships inside source and game data | Legal review before public distribution; credits regardless |
| R7 | Mission content loss by crossfire | Seven mortal contacts serve all six cases. Logic is verified; frequency is unmeasured | AF-14 legibility now; AF-30 measurement; D3 policy |
| R8 | Unbounded damaged-traffic work | Flat-tire cars stay physics-active at any distance (`city_vehicle.gd:461`), and network cars recycle only when `parked` (`city_traffic.gd:411`) | AF-12 offscreen recycling, plus the tire soak |
| R9 | Test trust | Many fixtures call direct hooks; old green logs don't certify a changing tree | AF-25 normal-input session; summaries tied to source hashes |
| R10 | Docs drift | README contradicts itself on persistence; the living-world acceptance is stale | AF-18 |
| R11 | Input lock-in | Most verbs use raw keycodes (level, combat, jump, phone), so rebinding and controller support aren't possible | AF-17 (InputMap migration); controller scope is D6 |

---

## 9. What you can review now

1. **Decisions D1–D9 (§3).** These are the highest-leverage thing only you can do. Even "not in v1" answers unblock planning.
2. **The two source audits** and the reconciliation table (§2), especially where your instructions overrode an audit (F6 kept, no synthesized footsteps, no population cut).
3. **Exit confirmation:** close the window or choose Main menu while airborne or mid-fight. You should get the "Progress has not been saved" dialog (`pen_lucy_level.gd:1033-1059`). Root owns its fixture.
4. **FOV slider** in Settings → video (55–90°).
5. **Phone:** P to raise it, LMB/Enter to take a photo, O to open the folder. Its last *recorded* fixture run failed to compile, and a fix is in source but not yet rerun. Treat it as unverified until M0.
6. **Population visuals:** `.work/alive-next/npc-roster.png`, `npc-daily-roster.png`, `npc-seated-roster.png`, `npc-visual-report.md`.
7. **Validation evidence:** `artifacts/alive-next/validation/summary.json` and its logs (people and tires passed; phone failed at that snapshot).
8. **Baseline numbers (§1.4)** and the proposed profiling matrix (§5). Confirm the scenario rows match how you play.
9. **The AUTO checklist** `.work/alive-next/auto-fixes.json`. Remove anything you consider fundamental.

---

## 10. Explicitly not recommended

- Gating or removing F6 inspection now (your instruction).
- Synthesized/beeping footsteps (rejected by you).
- Reducing the 20 + 1,200 identities, or renumbering them.
- An engine or language rewrite (both audits).
- An unlimited police spawn/chase system, fines, inventory loss or forced respawn as defaults "because GTA does it" (native audit). These belong to D2/D3 if at all.
- Building every interior, multiplayer, or a radio system before driving exists.
- Weakening a fixture's counts or bypassing the UI under test to make a run go green.

---

## 11. AUTO work not finished in this bounded pass

The table below is the final implementation disposition. The original Opus checklist remains a planning snapshot. Completed, scoped alternatives and remaining engineering work are distinguished explicitly.

| ID | Pri | Task | State |
|---|---|---|---|
| AF-01 | P1 | Boot shows a failed load reason and save-blocked state | implemented; persistent reason and save-blocked HUD |
| AF-02 | P1 | Non-destructive "Start fresh" (archive slot/.bak/.tmp, never delete) | implemented as explicit Recover Saving; old bytes retained |
| AF-03 | P1 | Truthful blocked-save text in `save_progress` and the exit dialog | implemented and validated |
| AF-04 | P1 | "© OpenStreetMap contributors" on map/minimap/credits | implemented; rendered-pixel checks pass |
| AF-05 | P1 | Credits/notices: OSM/ODbL, OFL fonts, Godot license and third-party notices, asset provenance incl. 6 new models | known-input notices packaged; full historical rights audit remains |
| AF-06 | P1 | Melee witness event | implemented and validated |
| AF-07 | P1 | Bounded spatial one-shot audio pool | implemented; bounded 12-voice pool |
| AF-08 | P1 | Pause audio with menu/phone/dialogue; music honors saved slider on direct launch | implemented for actual paused states; phone keeps world running |
| AF-09 | P1 | Priority notice queue | bounded FIFO/dedup implemented; speculative priority policy not added |
| AF-10 | P1 | Contact/patrol placement failure is a test failure and `push_error` | implemented; errors and population gate |
| AF-11 | P2 | Traffic bootstrap fallback if "Old York Road" is missing | explicit failure implemented; unvalidated alternate-route fallback rejected |
| AF-12 | P1 | Offscreen recycling of distant damaged cars; clear flats on recycle | implemented and validated |
| AF-13 | P2 | Offscreen recovery for long-blocked cars | implemented and validated |
| AF-14 | P1 | Case-lost/closed reasons in the ledger and persistent case history | derived persistent-state ledger implemented; no invented historical failure data |
| AF-15 | P2 | Save freshness and "can save now?" indicator | implemented and validated |
| AF-16 | P2 | Save migration fixtures + append-only crowd fingerprint | future content-migration work; canonical IDs preserved now |
| AF-17 | P2 | InputMap migration for every verb (F6 preserved as an action) | deferred control-platform foundation; current inputs validated |
| AF-18 | P2 | Docs truth pass | current docs corrected |
| AF-19 | P3 | graphify GDScript coverage | tool limitation documented; GDScript reviewed directly |
| AF-20 | P1 | Windows export preset + exported smoke | rc4 exported, booted and verified |
| AF-21 | P2 | Exported save location documented; no auto-move | documented in PLAYING and release README; no automatic save movement |
| AF-22 | P1 | Performance variance study | repeat/categorical comparison measured; broad variance cause unresolved |
| AF-23 | P2 | Benchmark driver scenario matrix | active-route comparison implemented; scenario matrix remains |
| AF-24 | P2 | Soaks: traffic 30 min, mixed 60 min, firefight 5 min, fleet tires | long soaks not performed; shipping gate |
| AF-25 | P1 | Normal-input full-session test | 44-check real-input case/save/reload session passed |
| AF-26 | P1 | Rerun phone fixtures (headless and render) | headless and rendered phone checks passed |
| AF-27 | P2 | Promotion-appearance visual acceptance capture | all20 promotion identities/rigs/capsules validated; roster captures reviewed |
| AF-28 | P3 | Behavior-preserving data-driven case loader | deferred maintenance refactor; six existing cases validated |
| AF-29 | P2 | Help text states the current knockdown and ammo rules | implemented and validated |
| AF-30 | P2 | Seeded crossfire contact-death measurement | not performed; informs mortality/campaign design |
| AF-31 | P2 | Exported logs to `user://logs`, collected by the smoke | export boot logs collected; general crash-report workflow remains |
| AF-32 | P3 | Text-size option | not implemented; accessibility shipping work |
| AF-33 | P1 | Fable 5.1 HIGH audit after integration; triage into this list | completed; findings triaged and corrected as documented |


## Final evidence

The current implementation report contains the accepted 35-suite index, frozen runtime hashes, explicit UI-fixture correction, final performance comparison and verified rc4 standalone package. This closes the current integration/audit pass; it does not mark the creative decisions, longer shipping tests or the complete game as finished.
