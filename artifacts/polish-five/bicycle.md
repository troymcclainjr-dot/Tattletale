# Bicycle feel polish

Implemented in `godot/scripts/city/city_bicycle.gd`.

- Rider cadence is separate from tyre rotation: feet settle during coasting/braking, reverse follows reverse input, and hard pedaling uses a bounded faster cadence.
- Smoothed effort tuck, pedal sway, braking brace, airborne pitch and landing compression make transitions readable. Hands remain fitted to the grips and feet stay on the pedals. A crashed bicycle falls from its current visual pose instead of snapping upright first.
- Holding S while moving forward produces a 0.30-second stop before reverse. S from rest reverses immediately; releasing S or changing control/state clears the pending dwell. Existing WASD/Shift/Space bindings remain unchanged.
- Initial movement now enters the real hull sweep even below one millimetre. This fixes a 120 Hz startup deadzone: a roughly 0.000172 m reverse step was previously discarded, resetting speed to zero every tick. Secondary collision-slide cutoffs, support profiles and recovery placement remain unchanged.
- Successful ordinary mount/dismount triggers optional quiet handling audio. Motion reset clears transient animation and reverse-dwell state. Save schema, population and pacifist policy remain unchanged.

## Verified validation

- **40 focused bicycle checks passed:** cadence/freewheel, body transitions, grip contact, landing, 30/60/120 Hz and uneven-step braking, intentional reverse, steering, 120 Hz startup, hop/save barriers and reset behavior.
- **27 mobility checks passed:** independent controls, reverse/sprint limits, hopping, angled curbs, overhangs, walls and harmless pedestrian contact. Evidence: `.work/polish-five/city_bicycle_mobility_smoke.log`.
- Existing **feel, curb matrix, save hooks and rider-fit** suites passed.
- Rendered mixed city session: **123 passed, 0 failed**, including actual bicycle input/capture and stop/dismount, subsequent activities, natural police-response resolution and durable checkpoint reload. Evidence: `.work/polish-five/mixed-r3.log`.
- `git diff --check` passed; independent bicycle review found no concrete regression.

The mobility fixture required one initialization fix: call `Bindings.ensure()` before injecting W. Its lazy first binding load otherwise released that input. The same failure was reproduced on isolated baseline `98e4d48` (`.work/polish-five/baseline-mobility.log`); no assertion or threshold was weakened.
