# Neighborhood audio polish

Implemented in `godot/scripts/city/city_world_audio.gd` and `godot/scripts/city/city_neighborhood_audio.gd`.

- Traffic uses the existing layered `vehicle_horn.wav`, softened to -10 dB with a 60 m range and a neighborhood-wide 0.75-second cooldown. Rejected distant events do not consume that cooldown.
- `bicycle_contact(at)` uses the existing non-tonal door/rustle transient at -20 dB, 14 m range, and a 0.4-second cooldown. Intended only for successful mount/dismount; there is no pedal or footstep loop.
- `emergency(source)` uses the existing short siren at -17 dB, 70 m range, at most once every eight seconds across the neighborhood. The position follows the actual responder. `stop_emergency(source)` stops it when the response ends; freed/distant sources are released. Serial ownership protects other gameplay sounds when the fixed pool reuses a voice.
- World audio now rejects focus-lost/muted events and clears transients on focus loss or mute. Existing game/tree pause behavior is retained. All sounds route through the existing SFX bus and Master gain.
- Bird phrases choose among nearby authored green anchors instead of always the nearest tree. Bird and basketball pitch vary subtly within 0.96–1.04. No new ambience schedules, actor scans, or audio nodes were introduced.
- Basketball `play_activity("court_bounce", at, strength)` accepts optional normalized impact strength; 0.25 produces a roughly 12 dB softer impact than 1.0. Existing two-argument callers remain compatible.
- Neighborhood mute stops existing transients and freezes its sparse scheduling without accumulating a resume burst.

The budget remains 12 shared world voices plus three reserved neighborhood voices. Existing sparse air and day-only bird scheduling remains intact.

## Integration

The shared bicycle/police/basketball hooks were integrated by their owners:

- Successful mount/dismount: `WorldAudio.ensure(level).bicycle_contact(at)`.
- Police request audio only with emergency state enabled in response/pursuit modes. Hold, parked, search, departure, release, and authority-loss paths stop the tracked source. Repeated response ticks remain globally rate-limited.
- Ambulance audio requires emergency lights, a visible valid vehicle, and `responding` mode. Nonresponse modes and immediate reset stop the tracked source.
- Basketball strength is derived from pre-bounce normal contact speed and rim impact speed; resting/rolling contacts remain excluded.

## Validation

- Passed all three existing `godot/tools/audio/test_neighborhood_audio.py` offline tests: PCM matches deterministic generation, clips preserve headroom/soft ends, birds contain silence between phrases.
- `git diff --check` passed for the owned changes.
- Added `godot/tests/city_audio_polish_smoke.gd` and runner covering budgets, cooldowns, real source-following, range/freed-source cleanup, focus, pause, bus mute/gain, localized greens, and basketball strength/variation.
- Root's audio-polish rerun passed cleanly after the fixture was updated to stop both pools, free its arena, and drain physics/process updates before quitting: `.work/polish-five/city_audio_polish_smoke.log`, `AUDIO_POLISH_SMOKE failures=0`. Existing neighborhood smoke also passed: `.work/polish-five/city_neighborhood_audio_smoke.log`, `NEIGHBORHOOD_AUDIO_SMOKE failures=0`. This worker did not launch Godot or claim audible playback validation.
- Existing melee/audio smoke had stale assumptions about player attacks being available in the nonviolent build. Its fixture now explicitly verifies the production policy remains disabled, then uses a test-only subclass override to exercise the retained combat backend. No production gate or player-facing unlock was added. Root rerun passed **22 checks, zero failures**: `.work/polish-five/city_melee_audio_smoke.log`.
- Rendered mixed integration passed **123 checks, zero failures**: `.work/polish-five/mixed-r3.log`. Emergency response smoke passed 90 checks and basketball match smoke reported zero failures. These fixtures establish functional integration, not subjective sound quality.

## Final read-only integration review

Reviewed world/neighborhood audio, police cruisers, emergency response and basketball after integration. No blocking correctness issue found. Focus/mute stop transients and reject fresh events; game/tree pause suspends world playback and freezes cooldowns. Neighborhood scheduling does not build a resume backlog. Weak source references and serial ownership prevent deleted/reused emergency voices from affecting replacement gameplay audio. Both earlier lifecycle observations—police authority loss and ambulance reset—now have immediate cleanup hooks.

Evidence caveat: `.work/polish-five/city_police_assistance_smoke.log` has passing assertions but still contains a 12-object teardown warning. It is not described here as a clean engine run, and the warning is not attributed to these audio changes without evidence.

## Asset limitation

All shipped sound clips are procedural originals. This pass reuses those clips without generating more tones. The bicycle cue is a quiet handling rustle, not a realistic bicycle drivetrain recording. The siren remains stylized. A convincing drivetrain, rolling tire texture, and natural emergency recording require suitable recorded/licensed assets and a listening pass; these are not represented as completed here.
