# Final foundation audit: findings and disposition

The independent **Fable 5.1 / MAX** review completed on 2026-11-01. The worker receipt confirms `claude-fable-5-1`, exit 0, and no wall-clock cutoff. It performed a read-only source review; runtime validation belongs to the root's separately recorded test runs.

[Original review](C:/files/projects/Tattletale/artifacts/pacifist-foundation/FABLE_AUDIT.md) · [Machine-readable findings](C:/files/projects/Tattletale/.work/pacifist-foundation/final-audit-findings.json) · [Model receipt](C:/files/projects/Tattletale/.work/pacifist-foundation/final-audit-receipt.json)

The review found **no P0/P1 blockers**, two P2 findings, five P3 findings, and five optional notes. This is not a claim that a source review establishes every gameplay condition or that the whole game is ready to ship.

## Corrections implemented

| Finding | Disposition |
|---|---|
| F-01: photo visibility disagreed with case evidence policy | Align the phone's subject-listing mask with the case evidence contract. Real walls still obstruct; incidental moving bystanders do not invalidate otherwise usable case photos. Incidents retain their independent evidence verification. |
| F-02: repeated save parsing and validation | Reuse the same three slot-read results for selection, backup and preservation; retain the separate post-write verification and future-version refusal. |
| F-03: incident crowd witnesses treated as absent | Resolve incident participant presence/death through the incident service without changing named-resident behavior or allowing the player to fill a witness contact role. |
| F-04: report-and-wait cases could stall after reload | Restore a usable report step when an unpersisted police response has ended; preserve reward idempotence and evidence. |
| F-05: victim photo entries omitted their collider | Supply the actual victim body where available, matching offender photo entries. |
| F-06: hard-coded nested save versions | Read versions from the owning case, custody and death services. |
| F-07: duplicate police phone updates | Give the incident relay sole ownership of referenced incident notifications while retaining direct fallback-call updates. |
| D-03: mounted bike blocked retaliation sight | Confirmed against the actual bicycle capsule: allow the rider's currently occupied bicycle as the target hit, retaining walls/unrelated vehicles as obstructions. |
| D-05: duplicate photo evidence | Same photo ID, photographer and subject attach idempotently, even at the record cap. Distinct photos and statements retain their normal limits. |

The report retry is a derived interaction at the existing outcome-wait stage, rather than a rewind: saved evidence, completed objectives, and reward provenance remain intact. An expired/cancelled incident that cannot satisfy the authored outcome closes the case without a reward. Accepted terminal states still follow the author's rules.

## Root verification

- [Focused audit regression](C:/files/projects/Tattletale/.work/pacifist-foundation/audit-case-incidents.log): **50 passed, 0 failed**. Covers crowd roles, report/reload/retry, once-only reward, terminal cancellation, victim collider, photo deduplication and actual police/incident/phone relay.
- [Existing case regression](C:/files/projects/Tattletale/.work/pacifist-foundation/audit-case-regression.log): **170 passed, 0 failed**.
- [Save-slot regression](C:/files/projects/Tattletale/.work/pacifist-foundation/audit-incident-save-r2.log): **73 passed, 0 failed**. Successful writes perform **4 reads instead of 10**, including post-write verification. This is a measured operation count, not a claimed frame-time speedup.
- [Full-world save regression](C:/files/projects/Tattletale/.work/pacifist-foundation/audit-world-save.log): **82 passed, 0 failed**.
- [Mounted-rider sight](C:/files/projects/Tattletale/.work/pacifist-foundation/audit-bike-sight.log): **11 real-physics checks passed**. Walls, terrain and unrelated vehicles still block; the occupied-car ballistic branch retains priority.
- [Phone regression](C:/files/projects/Tattletale/.work/pacifist-foundation/audit-phone.log): **zero failures**, including new real-collider occlusion checks.
- [Pacifist combat](C:/files/projects/Tattletale/.work/pacifist-foundation/audit-pacifist-combat.log) and [police assistance](C:/files/projects/Tattletale/.work/pacifist-foundation/audit-police.log): **passed with no failure/error markers**.

- [Broad incident regression](C:/files/projects/Tattletale/.work/pacifist-foundation/audit-incidents-r2.log): passed, including physical warnings/custody, witnesses, truthful reports, snapshot recovery and exactly one phone route-failure notice.
- [Final rendered city acceptance](C:/files/projects/Tattletale/.work/pacifist-foundation/acceptance-final-audit.log): **80 passed, 0 failed** after all audit corrections, with fresh profile, actual input/evidence/report/reward/reload and live incident witness provenance. Native focus/pointer guards passed.
- [Standalone r2 validation](C:/files/projects/Tattletale/artifacts/priorities-five/release/pacifist-20261101-r2/standalone-gameplay-validation.json): **passed** for fresh, reload and ordinary startup. The native observer recorded **1,411 samples**, zero unknown/errors and no runtime foreground focus.
- [Rebuilt ZIP](C:/files/projects/Tattletale/artifacts/priorities-five/release/pacifist-20261101-r2.zip): integrity verified, SHA-256 `698f713bf12a465f3cdee3fa7af352b2ca17e77e88bd5a25d9f5f20542a1531e`.
- `graphify update .` completed after final production edits (AST-only); no code-graph topology changes were detected. Graphify's parser coverage does not replace the focused GDScript review.

**Disposition complete for this pass.** The listed runtime fixes are in the source playable and validated r2 package. No whole-game shipment claim is made.

Two fixture defects were corrected rather than hidden: comparing parsed JSON to original Variant dictionaries rejected correctly published numeric values (the replacement checks exact written bytes and temporary-file removal); the old incident fixture collected structured phone statuses without forwarding them as the production level does (it now does and requires exactly one notice per failed route).

## Deliberately retained boundaries

- D-01/D-02: checkpoints remain blocked while mounted or during an unsafe police response. Safe stationary-bike saving would be a separate feature with persistence/recovery design, not a necessary correction here.
- D-04: additional query-object pooling is deferred until profiling identifies material cost. The measured frame-time groups and the low-risk repeated save-read work are better evidence than speculative allocations.
- No new story cases were authored. The original parcel case exercises the template system, and the other original cases retain their existing path.
- The controlled bicycle tumble is collision-aware recovery, not a full articulated ragdoll simulation.

See [acceptance evidence](C:/files/projects/Tattletale/artifacts/pacifist-foundation/ACCEPTANCE.md) for scoped performance measurements, the retained full population, and the distinction between controlled fixtures and actual city runs.
