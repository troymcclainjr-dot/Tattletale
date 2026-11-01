# Pen Lucy: implementation and independent review

Prepared October 31, 2026. This report covers the current neighborhood pass, the native and Opus reviews, and the remaining shipping work. The final implementation, independent review dispositions, measured performance and verified Windows package are recorded below. This is a playable prototype candidate; long-session and clean-machine human acceptance remain shipping gates.

## What this build is

Pen Lucy is a substantial walkable neighborhood prototype: grounded traversal, geographic maps, traffic, persistent NPC identities, daily routines, combat reactions, six local cases, a day/night clock, and checkpoint recovery. This pass improves its people, streets, vehicles, camera interaction, and reliability. It is **not a finished GTA-scale game**. Driving, a wanted/dispatch loop, meaningful player defeat consequences, an economy, and a longer mission progression remain design and production work.

The separate original block game still exists. Its arrest, dispatch, and finale do not count as features of the Pen Lucy neighborhood. Its source-project main scene remains unchanged. The standalone candidate is configured to start Pen Lucy through a staged project copy. F6 free-fly inspection remains available as explicitly requested.

The two independent reviews agree on the central issue: preserve the existing collision, bounded simulation, deterministic identities, and save protections; connect these foundations into a sustained play loop. Increasing population or prop density by itself will not solve that problem.

## Implemented in this pass

### People: twenty reusable appearances, stable identities

Twenty modular appearances replace the ambient and daily-resident blockouts. The roster contains 16 Black, two Hispanic, and two White fictional appearances, with different skin tones, faces, hair, clothing, and proportions. Bodies now include shaped heads and faces, hands, tapered limbs, shoes, collars, and several garment silhouettes. The existing named hero cast retains its authored appearance.

The **1,200 ambient people reuse those twenty appearances**. They are not 1,200 individually authored visual designs. Their canonical birth IDs, saved deaths, and deterministic identity mapping remain distinct. The twenty daily residents each use a different roster appearance, while retaining their existing routines and identities. Appearance does not change behavior, stats, or schedules.

The explicit population mapping is 964 Black ambient people, 16 Black daily residents, three existing authored characters, and five patrol characters: **988 of 1,235 total NPCs, exactly 80%**. This is an explicit fictional appearance assignment, not an inference from names or occupations.

Crowd promotion into combat now preserves the same roster appearance, including animated combat, death, and demotion back into the ambient batch. A provoked person no longer becomes an unrelated hero model. The collision system, canonical death IDs and active-combat limits remain intact; promoted capsules now match each roster height.

The measured visual budget is one shared crowd material and one surface per pose, with unchanged cell/pose batch counts in the fixture (18 before and after). The standing/bench mesh is 3,192 triangles at highest detail and 592 at the far LOD; chair-seated is 3,264 and 640. This is more geometry than the old blockouts, so batch equality alone is not a frame-rate guarantee. Daily actors use nine rig surfaces each: 180 across twenty people, down from 462. Early LOD index errors, overlapping waist geometry, oversized eye whites, and dress silhouette problems were corrected before the recorded clean people run.

Visual evidence: [standing roster](C:/files/projects/Tattletale/artifacts/alive-next/people/npc-roster.png), [daily actors](C:/files/projects/Tattletale/artifacts/alive-next/people/npc-daily-roster.png), and [seated roster](C:/files/projects/Tattletale/artifacts/alive-next/people/npc-seated-roster.png). These are private validation scenes, not proof that every location in the live neighborhood has been visually accepted.

### Phone photography

P opens a visible phone camera with an eye-level composition view, mouse look, wheel zoom, and LMB/Enter capture. O opens the photo directory; P or Escape closes the camera. Captures use a one-frame viewport, exclude the HUD and phone overlay, preserve aspect ratio, and cap width at 1,920 pixels. There is no continuously rendered second camera.

Each photo has a PNG and metadata JSON under the game's user photo directory. The pair is committed only when both writes succeed; failures retain previous photos and do not overwrite the checkpoint. Metadata records capture time, camera pose/FOV, player position, street, and world clock. This is photography, not a gallery, social system, mission-evidence mechanic, or NPC photo-reaction feature.

The phone owns player input while composing, preventing simultaneous movement, jumping, and attacks. Gravity, collisions, incoming damage, and vehicle impacts remain active; the phone does not provide invulnerability. Higher-priority modal flows cancel an in-flight capture.

### Tire behavior, vehicles, audio, and reactions

Punctures affect actual vehicle yaw, lateral motion, countersteering, and braking. The fine-step fixture measured approximately 0.66 m opposite-direction departures for opposite punctures and longer braking distance: 7.933 m healthy versus 11.045 m with one flat, starting at 8 m/s. More flats further reduce braking. Swept collision and road constraints retain authority. Parked cars remain parked. There is no player driving, towing, or repair game; traffic damage remains session state.

A bounded distant-damage update path and conservative offscreen recovery were also implemented. The integration3 coarse-solver road-progress failure was corrected; the root reports a passing integration4 traffic-budget run. Final matched-route and long-session checks remain separate gates.

Six distinct vehicle models were added: hatchback, midsize sedan, older long sedan, pickup, cargo van, and compact SUV. They have different body profiles and modeled details, including the pickup bed and SUV spare. They fit the existing traffic/parking envelope; the long sedan, pickup, and van are compressed representations of those real vehicle classes. Shared materials, lower-detail wheels, and at most six surfaces per new model bound rendering cost. Later catalog validation passed 284 checks and the showroom produced 21 captures, superseding the early thirteen-failure artifact. Further Fable fixes require the upcoming frozen vehicle/precision/jump/street reruns.

World sound uses a bounded spatial voice pool for shots, impacts, and horns; local player sounds remain local. Landed punches can trigger nearby witnesses through bounded facing/line-of-sight checks, civilian flight, and existing police intervention. This adds no wanted level or new firearm escalation rules. Combat passed in integration4 and the later melee/audio run passed 21 checks; further audit changes require the upcoming frozen regression run. No synthetic or beeping footsteps were introduced; recorded footsteps and broader audio direction remain decisions.

### World repairs

The source frontage rule now handles narrow units previously skipped: 27 fronts were corrected, including all seven affected Row170 fronts. Rear access and opposite-facing end-unit orientation were preserved, with a 2.4 m minimum porch ceiling. Two evergreen silhouettes vary eleven existing surveyed trees without increasing their height/radius/collision envelope.

The world pass restores continuous lawns for 537 existing grass front beds while retaining intentionally paved yards. Its source assertions report zero overlap with exact public sidewalk and door-path polygons. It adds grounded short private fences at fifteen locations, three Row050 shrub masses, and three Row170 rear-access dumpsters. The fire-station grass adjustment covers roughly 30.6 square metres on each side. Placement retains service access, approved courts, and removed-court decisions.

These changes use shared finishes, spatial cells, and culling. They do not introduce lawn collision. Fence collision remains intentional. Source geometry checks and the serialized world fixture passed; visual review of access and long routes is still part of final acceptance. See the detailed [world repair report](C:/files/projects/Tattletale/artifacts/alive-next/world-repairs-report.md).

### Save, settings, and case clarity

Settings expose checkpoint age and blocked-save reasons, explicit recovery, and accurate busy/failed-save feedback. Recovery preserves the prior checkpoint bytes. A failed save prevents an implicit destructive exit; canceling the exit keeps the world paused. Camera FOV applies immediately within bounds. Completing all six cases now leaves a truthful exploration objective and completion catalog.

The new Cases button derives a read-only ledger from existing completion IDs, active stage, and permanent contact deaths. Completed cases stay completed if a contact later dies. Active cases check only remaining contacts, so an already-used contact's death does not invalidate the displayed current objective. A confirmed death is distinguished from a contact who is simply not present. The parcel prerequisite is displayed explicitly.

This ledger does **not** invent a history of cancelled or previously accepted cases. The save does not store that history. It adds no save schema, rewards, resurrection, or new mission rules. It explains current unavailability after loading the existing checkpoint. Controls now state the finite starting pistol ammunition (12 loaded plus 72 reserve, no refill), the current 3.5-second knockdown/full-health recovery, and permanent NPC death consequences. The dedicated ledger fixture passed ten checks. The later normal-input integration fixture passed 44 checks through acceptance, authored dialogue, completion, an actual Save-button mouse event, a fresh scene and checkpoint reload.

### Standalone Windows packaging

A Windows x86-64 export preset and `export_city_release.py` build pipeline are implemented. The pipeline snapshots current working-tree runtime files, stages the Pen Lucy entry scene, retains F6, and excludes tests, tool sources, logs, scratch files, and repository metadata from the shipped payload. It reuses copied import data and the shared Godot process lock. It does not mutate the original project's main scene.

A successful build must create an executable plus PCK, boot that executable from its own output directory under an isolated user profile, verify the actual Pen Lucy population and no placeholder assets, collect engine license notices from the shipped runtime, hash payloads, and only then create the distribution ZIP. `--check`, `--prepare-only`, and six file-only unit tests passed. **The pen-lucy-rc4 executable/PCK exported, booted independently, and passed checksum verification.** Its ZIP SHA-256 is `b29f37f53f16990c1bee3139fdeae1ccc3f26bcb697930ce75082ee59fdacf29`. This validates packaged boot/resource closure; a clean-machine interactive playthrough and acceptance of later source changes are not implied.

The package includes human-readable runtime/external notices, the three font OFL notices and source checksums, OpenStreetMap attribution and a map-source archive, and Godot notices extracted from the actual exported template. This is verified provenance for those known inputs, not a blanket claim that every historical asset has undergone a complete commercial-rights review. The candidate is unsigned; signing, installer/store requirements, and distribution policy remain decisions.

## Final verification

**35 integration suites accepted**, with zero engine-error diagnostics in their accepted runs. The full serialized run kept all runtime scripts/assets unchanged. One older UI assertion mistook the required radar credit for help clutter; only that fixture was corrected and rerun. Every other runtime/test hash stayed identical. The original failure is retained, and the evidence index records the narrow replacement rather than rewriting the original result.

- [Accepted suite index and hashes](C:/files/projects/Tattletale/artifacts/alive-next/validation-acceptance.json)
- [Original frozen run](C:/files/projects/Tattletale/artifacts/alive-next/frozen-validation/summary.json)
- [UI fixture correction](C:/files/projects/Tattletale/artifacts/alive-next/ui-fixture-correction/summary.json)

Coverage includes vehicle hulls/roof jumping, production tire shooting on all six catalog models, traffic and damaged-car recycling, movement/streets, population/routines/promotion, combat/audio, phone and rendered photos, normal dialogue/case/save/reload input, checkpoint recovery, settings/layout/rendered attribution, maps/inspection, parks/backlots, world surfaces and day/night. Separate file-only tests passed: six release-pipeline, seven strict-runner and four surface-geometry tests.

Private captures were reviewed for all four requested locations, the two conifer shapes, three rear dumpsters, character rosters and vehicle silhouettes. The eight rear-door approaches reserve 1.9 m clear corridors; all 24 bin/door comparisons have zero overlap, with at least 0.570 m extra clearance beyond those corridors. The final source fix preserves original grades and public street curbs, and closes the former lawn-border surfaces with paving rather than leaving cracks.

The exported **pen-lucy-rc4** executable boots Pen Lucy independently of the source/editor, reports 1,200 ambient / 20 daily / 15 named or patrol NPCs, no placeholder assets, and preserved F6 inspection. Package verification checks hashes and only then creates the ZIP. This proves automated startup and packaging on this machine, not an ordinary clean-machine human playthrough.

## Review findings and decisions still required

The native audit and Opus gap review both support incremental work on this codebase. Neither recommends a rewrite or reducing the requested NPC population as the default solution. They distinguish ordinary defects from choices that would change the game.

1. **Driving:** decide whether v1 includes player enter/exit and driving, then specify controls, ownership, collision, saving, and vehicle consequences.
2. **Crime and response:** decide whether the player reports incidents, commits crimes, or both; define witnesses, heat, dispatch, and police escalation before adding systems independently.
3. **Defeat and mortality:** choose player death/arrest/recovery rules and how permanent named-contact deaths affect the intended campaign. The current ledger explains existing rules without changing them.
4. **Progression:** choose a mission/chapter structure and a purpose for community points, ammunition supply, and any economy. Six cases are not a long campaign.
5. **Places and routines:** decide which interiors and civic/business services are playable. Current daily schedules largely use frontage corridors rather than a complete citywide destination simulation.
6. **Platform and access:** define minimum hardware, target resolution/frame rate, controller and rebinding scope, storefront, installer, and signing requirements.
7. **Audio:** choose recorded footsteps, music, voices, and licensing direction. Do not reintroduce rejected synthetic footsteps.
8. **Entry flow:** confirm the candidate's Pen Lucy start and how the original block game is presented. F6 stays available under the current instruction.
9. **Persistence:** decide whether one checkpoint remains sufficient or whether slots, restart/new-game flows, and broader world-state saving are needed.

These are choices for a coherent vertical slice, not defects that should be silently filled with invented creative rules. The [shipping roadmap](C:/files/projects/Tattletale/artifacts/alive-next/SHIPPING_ROADMAP.md) sequences integration and defect closure, a standalone candidate, performance/soak acceptance, those decisions, one selected vertical slice, and release-candidate polish. It does not provide unsupported calendar estimates.

## Performance and remaining release gates

Final short-route runs at 1920×1080 Balanced / 4× MSAA delivered **135.2 and 123.1 FPS**, with **1,576 and 1,565 median draw calls**. Their frame-time p95 was **13.84–16.03 ms** and p99 **18.29–20.20 ms**. The old-vehicle-catalog comparison delivered 146.3 FPS / 1,533 draws. The single pre-integration run was 184.9 FPS / 1,495 draws. The integrated result is therefore **not performance-neutral**, and the old single baseline plus observed clock/run variability is insufficient to attribute the whole difference to one subsystem.

NPC simulation medians remained about 0.57–0.59 ms versus 0.56 ms before. Traffic measured 2.97–2.99 ms versus 2.58 ms before, and about 3.37 ms in an earlier integrated run. Rendering GPU medians were 2.13–2.24 ms versus 2.04 ms before. The wider car catalog adds batches and hull work; the crowd adds visible geometry without increasing its pose/cell batch scheme. The retained population is not reduced to buy frame rate.

[Full performance table, settings, provenance and caveats](C:/files/projects/Tattletale/artifacts/alive-next/PERFORMANCE.md). Healthy-car tire allocations, repeated idle-audio writes and persistent distant damaged-car collision work were removed. The next performance work should profile actual CPU contact/traffic and static submission costs across several routes, night and gunfire; more aggressive visual culling alone is not established as the answer.

Remaining shipping gates: target hardware/controller/accessibility decisions, repeated whole-map/night/combat measurements, long traffic/mixed-session soaks, clean-machine human play, signing/store packaging and a complete historical asset-rights review. The roadmap keeps these explicit. Passing short fixtures does not certify gameplay feel or an hour-long session.

## Final acceptance record

- Native Astra review, Opus 5.5 High gap review and roadmap, Opus 5.5 High six-vehicle implementation, and Fable 5.1 High independent final audit completed. External receipts confirm the actual model names; headless calls used no session persistence and no worker wall-clock cutoff.
- [Fable findings and dispositions](C:/files/projects/Tattletale/artifacts/alive-next/AUDIT_DISPOSITION.md). Concrete gameplay/runtime findings were corrected and covered by regression checks. Graphify still lacks GDScript AST coverage; direct scoped source review supplied that coverage for this audit, without claiming the graph itself was fixed.
- Accepted source-manifest SHA-256: `46dd0efdc55a1dbb744d7da7b54c947dac1a7c7ceb65149ef020cab32762ed32`.
- [Windows standalone ZIP](C:/files/projects/Tattletale/artifacts/releases/pen-lucy-rc4.zip), SHA-256 `8dce72e8f86e05698eda8fdae0c91b15383643a185c8225dd214fc8ee1cc0fa1`. Extract the entire folder and run `Tattletale-PenLucy.exe`; retain the adjacent PCK. The source project's original main scene was not changed.
- No desktop-control session was used. Engine checks were headless or private hidden viewports.

## Source reports

- [Native gap audit](C:/files/projects/Tattletale/artifacts/alive-next/native-gap-audit.md)
- [Opus gap audit](C:/files/projects/Tattletale/artifacts/alive-next/opus-gap-audit.md)
- [Bounded runtime follow-up](C:/files/projects/Tattletale/artifacts/alive-next/runtime-gap-followup.md)
- [Shipping roadmap](C:/files/projects/Tattletale/artifacts/alive-next/SHIPPING_ROADMAP.md)
- [Vehicle implementation report](C:/files/projects/Tattletale/artifacts/alive-next/vehicle-models.md)
- [World repairs](C:/files/projects/Tattletale/artifacts/alive-next/world-repairs-report.md)
- [Release build instructions](C:/files/projects/Tattletale/godot/release/README.md)

The external Opus gap review and roadmap and the final Fable 5.1 high-effort audit are complete. Fable findings are tracked individually; their final closure and frozen-source evidence belong with the acceptance addendum. A model-route probe alone was never treated as an audit.
