# Neighborhood polish: five priorities

Baseline: `98e4d488c9c69583bdec6fbba0adb89ebd748142`. This pass preserves the nonviolent player policy, existing currency/save formats, and the full 1,200 ambient residents, 40 scheduled residents, and 90 traffic vehicles. No desktop input or foreground control was used.

## Implemented

1. **Traversal streaming:** periodic detail-provider updates are spread across frames; distant building/vegetation retirement is paced. Vegetation meshes use cached CPU template arrays instead of repeated per-plant renderer readback. Mesh content, wind attributes, visibility distances, collision decisions, and explicit camera/capture refresh contracts are retained. The frame budget is a soft target between indivisible provider calls, not a guaranteed maximum.
2. **Residents:** richer local outings, arrival gestures, and bounded neighbor greetings for the existing scheduled residents. Destinations must lie on validated existing pedestrian corridors. The actual map qualifies one court destination (Yvette, 2.40 m from its edge), and no shop approaches; cross-block route connections are still needed for broader errands. Population and schedule/save schemas are unchanged.
3. **Bicycle:** input-driven pedaling, coasting, hard-pedal effort, braking brace, landing compression, and continuous crash presentation. Actual mixed play exposed brake-to-reverse overshoot; a 0.30-second stopped dwell now separates braking from deliberate reverse. A second regression test exposed and fixed a pre-existing 120 Hz startup deadzone while retaining real hull sweeps and collision-slide limits.
4. **Audio:** restrained traffic horns, bicycle handling, response-only spatial sirens, localized bird variation, and impact-scaled basketball sounds. Existing voice budgets remain 12 shared world voices plus three neighborhood voices. Focus, pause, mute and source cleanup are covered. Existing procedural assets are reused; this is not a new recorded sound library or a subjective listening approval.
5. **Mixed session:** an automated rendered session uses ordinary gameplay inputs across phone/photos/map, cycling, a real pantry purchase, basketball and modal interruptions, a live witnessed incident, phone reporting, natural police response, and a real fresh-scene checkpoint restore. This found and drove the braking fix. Scenario starting positions are arranged by the fixture; physical approaches, interactions, purchase, evidence and police outcome are not fabricated.

## Validation evidence

- Bicycle polish: 40 checks; mobility: 27; existing feel, curb matrix (2,616 checks), save hooks and rider fit pass. The mobility fixture required binding initialization before injecting input; the same original failure reproduced on the untouched baseline.
- Resident full-city validation: 389 checks; focused activity, movement and recovery checks pass. The single qualifying destination and lack of shop routes are explicit limitations.
- Audio polish and neighborhood smoke pass; retained combat/audio backend fixture passes 22 checks while separately asserting the playable offense gate remains disabled. Police assistance, emergency response and basketball integration assertions pass. The older police-assistance arena still reports a 12-object shutdown warning; its passing assertions are not described as a warning-free run.
- Streaming: existing mesh merge, cadence, capture residency and city streaming checks pass. New vegetation parity fixture passes 67 checks, comparing old/new geometry, LOD, physics and bounded retirement. New scheduler fixture covers pacing, synchronous captures, repeated relocations, freed providers, threaded-load teardown and profiling semantics.
- Final integrated rendered mixed session: **123 passed, zero failed** on completed code (`.work/polish-five/mixed-final.log`). It waited for the actual police response to resolve before checkpointing, then restored the wallet, purchase and internal phone gallery twice without replaying rewards.
- Scheduler fixture: 36 checks; rendered vegetation quality: 11 checks with near/far/wind captures inspected. Utility placement regression passes after repairing baseline-reproduced fixture assumptions about already-existing pointed shrubs; no runtime plants were changed by that repair.

## Final performance and package

The corrected matched 180-second rendered comparison passed 37 checks on each snapshot. Frames above 33.3 ms fell from 14 to 7; the maximum fell from 62.369 to 44.271 ms. Median/p95 were slightly worse (3.556/12.032 to 3.873/12.120 ms), so this is evidence of a smaller long-hitch tail, **not a general FPS gain**. Full population was retained. The benchmark camera now follows elapsed time instead of rendered-frame count; older camera-confounded runs are excluded. See [PERFORMANCE.md](PERFORMANCE.md).

The separate ten-minute walking endurance run passed 19 functional checks with stable population, zero orphan nodes and modest bounded memory growth. It also recorded an **unresolved 988.315 ms stall**. The available telemetry cannot distinguish an internal wait from external descheduling; timestamped bounded slow-frame diagnostics were added for future reproduction. This pass does not claim hitching is fully solved. See [ENDURANCE.md](ENDURANCE.md).

Standalone build `polish-five-20261101-r1` passed export, source-free/read-only installation, fresh/reload gameplay checks, ordinary graphical startup and checkpoint preservation. Source runtime and installation remained unchanged. ZIP integrity verified: 16 files, SHA-256 `dcf0eee4af11f4e996884a99d72611daedda880bdfa6f785078d4722e25fc90d`. The package remains local under `artifacts/priorities-five/release/`; binaries, caches and raw captures are not added to Git. The repository's existing `Play Pen Lucy.lnk` launches the updated source. All test engines exited; no desktop input was used. Graphify AST update completed.

## Models and review

- Supporting implementation and independent peer reviews: native `gpt-6-astra`, high effort (resident, bicycle and audio workers).
- Streaming/vegetation implementation: verified `claude-opus-5-5`, max effort, headless with `--no-session-persistence`, no fixed worker wall-clock cutoff. A first network-failed attempt was retried successfully; the final worker receipt records the actual model.
- Root integration, serialized engine validation, evidence and delivery: current parent GPT session; exact parent model identifier is not exposed by the session tools.

## Next useful work

Connect pedestrian routes between blocks and into real shop approaches so more residents can make purposeful trips. A listening pass with suitable recorded bicycle/traffic assets would provide a larger audio improvement than adding more procedural cues. Continue profiling measured single-provider and chunk-activation spikes rather than reducing population speculatively.
