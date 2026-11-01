# Audit disposition

The independent Fable 5.1 High review is preserved in `fable-final-audit.md`. It reviewed a moving integration snapshot; several reported acceptance failures were already fixed while the review was running. This page records the disposition, rather than rewriting the review as if it had inspected the final build.

| Finding | Action |
|---|---|
| FA-01: radar attribution clipped | Moved attribution outside the circular radar's clipping hierarchy. Both radar and full-map credit pass bounds and actual rendered-pixel checks. |
| FA-02: normal-input save click | Corrected the fixture's stretched-canvas coordinates. The actual mouse click now writes exactly one checkpoint; the 44-check case session completes and reloads without repeating rewards. |
| FA-03: mixed/stale test evidence | Added a single serialized validation manifest, explicit completion status and start/end hashes for runtime assets, scripts and fixtures. A changing tree fails acceptance. Final results are linked from the main report. |
| FA-04: integrated performance unmeasured | Ran integrated and legacy-catalog comparisons, retained every measurement and its provenance. The main report separates observed cost from clock/run variability; no unsupported improvement claim. |
| FA-05: export not booted | Isolated editor/export temporary and profile directories. The pipeline now exports, boots the actual release executable, checks population and missing assets, verifies payload hashes, and only then creates its ZIP. |
| FA-06: rear-bin camera inconclusive | Replaced rooftop view with two rear-lane views and a separate opposite-facing end-unit view. Doors and dumpsters are visible. |
| FA-07: tire shot rounding margin | Increased catalog tire exposure to 5 mm. Added production `_fire` tests for all 24 tires on the six new models; all puncture successfully. |
| FA-08: recycled cars retain flats | Recycling clears flats, cached handling and panic; restores wheel geometry; reapplies distance-based collision presence. Added damaged-jam recycling assertions. |
| FA-09: documentation contradictions | Corrected checkpoint persistence, phone O/F5 controls, current population/court/car descriptions and release instructions. Historical review snapshots are explicitly superseded by final evidence. |
| FA-10: healthy braking/audio overhead | Healthy cars return constant braking without constructing tire profiles. Damaged profiles are cached with content-based invalidation. Idle, unpaused audio skips repeated property writes while paused/new playback remains correctly synchronized. |
| FA-11: silent traffic bootstrap | Missing or undersized Old York data now produces an explicit engine error. Living-world validation requires at least 80 moving vehicles. No unvalidated fallback route is silently substituted. |
| FA-12: fixture recovery litter | Reliability fixture cleans only its exact, project-owned checkpoint basename and dotted suffixes. Player saves are untouched. |
| FA-13: graphify lacks GDScript | Tooling limitation retained explicitly: this installed graph indexes Python/JS/Markdown, not GDScript ASTs. Audits used graph-first orientation followed by direct scoped GDScript review. A graph refresh is not represented as full Godot indexing. Adding a tested extractor is separate tooling work. |
| FA-14: promoted actor capsule height | Promoted collision capsule height and offset now match the modular roster. The people fixture checks all twenty appearances and their demotion shapes. |
| FA-15: creative decisions | Preserved current rules. Player driving, wanted/dispatch policy, defeat consequences, progression/economy and playable interiors remain explicit roadmap decisions. |

## How the broader roadmap was used

The implemented automatic work prioritizes demonstrated defects and missing acceptance checks: save truth/recovery, notice delivery, mission ledger accuracy, input ownership, witness reactions, bounded spatial audio, traffic recycling, appearance preservation, attribution, packaging and strict validation. The phone intentionally leaves the world running; a roadmap suggestion describing it as paused was not applied.

Some suggestions are engineering extensions, not fixes for a demonstrated failure. Replacing every raw key with InputMap actions, converting six stable cases to a data loader, changing content-version migration rules, adding text scaling, broadening benchmark scenarios and running hour-long soaks remain named work in the shipping roadmap. They are not claimed complete. In particular, an automated session and a standalone boot do not certify a clean-machine human playthrough, long-session stability or minimum hardware.

The case ledger derives completed/active/unavailable states from existing persistent data. It does not invent a historical failure record that was never saved. The bounded notice queue preserves order and suppresses repeats; it does not add a speculative priority system. Asset notices cover known engine/font/map inputs and current original assets, without claiming a complete rights audit of every historical file.
