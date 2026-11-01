# Pacifist foundation: priorities and content handoff

Status: 2026-11-01. The foundation, full-city interaction/visual checks, final Fable review, applied corrections and standalone candidate r2 are validated within the scopes recorded below. This pass is complete; the entire game is not claimed ready for shipment. Templates are not additional finished story cases.

## Implemented foundation

| Priority | Current behavior | Validation / next content work |
|---|---|---|
| Explore and help neighbors | Player attacks, car driving and alignment scoring are disabled. Walking, bicycle travel, basketball, existing conversations/cases and F6 inspection remain. | Full-city interaction acceptance passed 80/0. |
| Document and report | The phone has Contacts, Camera, internal Photos, Cases, Police and map access. Trusted capture context records visible subjects; stored gallery metadata cannot award new evidence. Maps use place symbols with hover/selection names. | Real phone/map input, capture and report flow passed; root reviewed phone-home/map images. |
| Physical bicycle consequences | Contact severity uses relative motion. Structures/traffic can produce scrapes, recoil or rider ejection/recovery; people can stumble or fall and recover through combat's bounded nonlethal path. These contacts do not award offense, money or alignment. | Crash 88/0, curb/post matrix 2,616/0 over 277 crossings, real-city curb/parked-car checks 186/0. These do not establish every possible sustained-session condition. |
| A neighborhood that acts independently | Bounded live jaywalking, mail tampering, dumping, theft and fights use real neighbors. Witness/evidence gates control reports; real police handle warnings or custody. Duplicate reports do not redispatch. Player phone corroboration can subscribe to later updates without rewriting the original reporter. | Natural production incident fixture passed 36/0; interaction acceptance separately observed a real moving offender and reported through the phone. |
| Cases that authors can extend | Schema validation, seven templates, evidence-gated interviews/reports, strict photos, visit/follow/flee, incident outcomes and checkpoint records are implemented. The original `parcel_report` is migrated with an inspection-or-photo scene step. | **No new specific story cases shipped.** Five other original cases remain on their existing path; templates and the example are scaffolds. |
| Preserve progress | Case evidence/replay state and incident records join world saves; old supported saves migrate, future versions are refused, and unsafe bike/recovery states block checkpoints. | Standalone r2 fresh, reload and ordinary-startup phases passed with nonempty case/incident state. |
| Improve the world | Shared architecture, vegetation, props and sky improvements preserve existing placement/collision contracts; players and vehicles were excluded from this model-quality pass. | Full-city sky 63/0 and final frontage gallery 69/0; root accepted repaired Argonne/hospital views. [WORLD_QUALITY.md](C:/files/projects/Tattletale/artifacts/pacifist-foundation/WORLD_QUALITY.md) records changed/retained coverage and costs. |

## Evidence and next gates

The current [case regression](C:/files/projects/Tattletale/.work/pacifist-foundation/audit-case-regression.log) passed **170 checks, 0 failures**: schema/content loading, original parcel flow, evidence/refusal rules, replay/payout protection, save migration, stand-ins, continuous verbs and incident-photo restrictions. The [world-save regression](C:/files/projects/Tattletale/.work/pacifist-foundation/audit-world-save.log) passed **82 checks, 0 failures**, including authoritative NPC/law death persistence while player lethal damage stays blocked. [Bicycle mobility](C:/files/projects/Tattletale/.work/pacifist-foundation/bike-mobility.log) passed **27 checks, 0 failures**; [phone smoke](C:/files/projects/Tattletale/.work/pacifist-foundation/phone-smoke.log) reports zero failures. These are focused evidence, not a full-game release verdict.

The latest [interaction acceptance](C:/files/projects/Tattletale/.work/pacifist-foundation/acceptance-final-audit.log) passed **80/0**, including actual dialogue/evidence/report/reward, scene reload, live incident sight provenance and phone reporting. The startup no-focus launcher passed native desktop-isolation checks without weakening the guards. [ACCEPTANCE.md](C:/files/projects/Tattletale/artifacts/pacifist-foundation/ACCEPTANCE.md) records the completed natural-incident, curb/crash, full-city rendering and live-world performance results with their scope limits; older failed runs are historical rather than the current verdict.

Standalone candidate **`pacifist-20261101-r2` is verified, with gameplay passed**. Its [packaged receipt](C:/files/projects/Tattletale/artifacts/priorities-five/release/pacifist-20261101-r2/standalone-gameplay-validation.json) reports fresh, reload and ordinary startup all passed, preserving nonempty case/incident state and source/install contents. The ordinary-startup native observer recorded 1,411 samples with no runtime foreground focus, unknown samples or errors.

The independent **`claude-fable-5-1` / MAX** audit completed without P0/P1 blockers. All seven actionable findings and two optional improvements were addressed, affected checks passed, and r2 was built and verified from those corrections. See [AUDIT_DISPOSITION.md](C:/files/projects/Tattletale/artifacts/pacifist-foundation/AUDIT_DISPOSITION.md) for changes, tests and intentionally retained design limits.

## Next content-authoring workflow

1. Start with [CASE_AUTHORING.md](C:/files/projects/Tattletale/artifacts/pacifist-foundation/CASE_AUTHORING.md) and `godot/assets/data/cases/examples/rapid_authoring.example.json`. Choose one existing template and authored contacts/locations; create one small case before expanding the catalog.
2. Give it a stable ID and version, retain `status: draft`, replace every draft line, and set explicit evidence, reward, placement and completion rules. Add its relative JSON path to `cases/index.json`. Drafts validate but are not offered to players; the example is not indexed.
3. For photos, author the actual distance, framing, tags, time/area and interval requirements. `require_tags` permits **at most eight unique nonempty tags of up to 96 characters**. Only full trusted capture context awards case photos. Incident evidence summaries never bypass those checks; the older cases-worker report's summary-auto-credit note is superseded by the [integration fix](C:/files/projects/Tattletale/.work/pacifist-foundation/case-photo-integration-fixes.md).
4. Run library/smoke validation through the root-owned engine runner, then play the new case in the real city from offer through evidence, report/outcome and save/reload. Add focused assertions for its meaningful refusal paths and payout-once behavior. Clear warnings before changing it to `ready`.
5. Preserve shipped IDs and stage compatibility. A template load or synthetic hook test is not proof that a clue is reachable, a subject is visible, or a police route works in production. Rebuild/verify the standalone after accepted content changes.

```powershell
python godot/tools/godot_run.py --timeout 240 -- --headless --script res://tests/city_case_engine_smoke.gd
```

The next content investment should use these validated verbs and existing neighborhood assets. The next milestone is a small authored case built and played end to end with these templates, before expanding the story catalog.
