# Basketball activity report

Final root validation: 92 rules checks, 105 physical-match checks and 47 actual-city checks passed. Rendered court/power captures were inspected. The author-only account below predates that validation; [ACCEPTANCE.md](ACCEPTANCE.md) records the final integrated result.

Worker: basketball (Opus 5.5). The integration contract is in
`basketball-contract.md` (written first, updated to match the final code).
I did not launch Godot, use CUA, commit, push or run a graphify update. All results
below come from static review only. Root should treat the new tests as unrun
until it runs them.

## Graph query

I ran `graphify query` twice, as requested (court/hoop/possession and
`city_basketball.gd`). The graph indexes Python, JS and Markdown (Blender court
layout, `park_courts.py`, audio.js), not GDScript, so I read the Godot sources
directly. The court geometry (rims 1.575 m in, arc `min(6.75, w/2-.75)`, corner
lines `w/2-.90`, lane, poles 0.72 m outside, board 0.375 m behind the rim) comes
from `blender/city/park_courts.py`. The records come from `pen_lucy_courts.json`.

## What the player gets

- **Free shooting / shootaround.** Picking up any court ball (E) starts a
  tracked shootaround: makes/attempts, streak, best streak and points. Every
  shot gets feedback: Swish!, Bank shot!, Rattled in!, Dropped in!, Rim out,
  Off the rim, Off the glass, Long/Short/Wide by N m, or Air ball. R returns
  the ball and shows a summary. Walking away or idling 2 minutes also ends it.
  If a rebound rolls more than 2 m off the court, it is reset to the
  free-throw line.
- **Pickup game to 11.** T near any court (within 3 m of the lines) brings one
  court regular onto the court. The regular uses the shared modular cast rig,
  has a unisex name, and walks on from beside the court. Rules:
  - 1 point inside the arc, 2 beyond; first to 11 (a two from 10 wins).
  - After a basket or dead ball, the other side checks the ball at the top of
    the key (loser's ball).
  - Defensive rebounds and loose balls taken from the other side must be
    cleared beyond the arc. An uncleared make counts nothing and turns the ball
    over.
  - Out of bounds: the ball touching the floor outside the half in play, or a
    ball handler 0.5 m over a line after having been in bounds. It goes to the
    side that did not touch it last.
  - No goaltending: an untouched shot above 2 m cannot be grabbed. Nobody can
    reach above 2.4 m.
  - A ball that bounced on the floor cannot score. Each release scores at most
    once.
  - On a full court, a basket in the other hoop is refused.
- **Opponent behaviour.** The opponent walks up to check the ball, dribbles to
  a planned spot (drive, mid-range or beyond the arc; it leans long when
  trailing or needing exactly two), sets, gathers and releases a real
  ball. The launch speed comes from a stepped-gravity solver. Aim error is
  seeded and grows with distance, which gives roughly 45%, 30% and 20% by
  range before rim and board luck. It also crashes the boards after a reaction
  delay, chases loose balls, clears the arc and guards. Guarding means standing
  between the ball handler and the basket, 1.5 m off (2.6 m while they must
  clear), with a 1.15 m personal-space floor. It does not steal, block, push or
  make contact.
- **Controls.** T starts a game. During a game, T asks for confirmation and a
  second T within 2.5 s quits. In the 30 s result window, T starts a rematch
  with the loser's ball and the same opponent. Walking away ends the result
  window and the opponent leaves. The prompt shows current bindings
  (`city_input_bindings.gd`). Space/Shift and unrelated keys are never consumed.
- **Shot meter.** While charging, a small power bar (own CanvasLayer 13,
  mouse-ignoring) shows the charge against a green window: the ideal power for
  the current arc and distance, narrower with distance (0.075 down to 0.03).
  A release inside the window flies true. Outside it, errors grow normally.
  Lining up within about 12° of a rim gives the exact horizontal line from the
  hand, which removes the hand-beside-camera-ray offset. Arc still comes from
  view pitch. The prompt says "look up for more arc" when the entry would be too
  flat. Ball flight, rim, board and scoring stay fully physical.
- **Rim.** The ring was decorative mesh, so balls passed through it. It is now
  resolved analytically as a 0.225 m ring with a 0.017 m tube. Contact is
  sampled per step so fast balls cannot skip through it. That gives rim-outs,
  rattles and roll-offs. A ball perched on top of the tube is pushed off one
  side.

## Interruptions and cleanup

| Situation | Behaviour |
| --- | --- |
| Pause, map, dialogue, shop, F6 inspector | The level stops calling `tick` and everything freezes, including a ball mid-air. Play resumes exactly where it stopped. The charge is cancelled |
| Phone, law hold | The game is on hold: the opponent stands still and an in-flight ball finishes its real flight. The HUD says "Game on hold" |
| Vehicle impact, downed | A held ball pops loose: a live, nonlethal fumble |
| Bike mount, relocation, law placement (`suspend(true)`), taking a seat | The game is called off, the ball goes home and the opponent walks off |
| More than 4 m outside the half for 6 s (warned with a countdown), or more than 18 m at once | Abandoned with a notice |
| Combat aggression nearby | Abandoned |
| Loose ball untouched for 14 s | Dead ball, other side's ball at the top |
| Ball lost (under the world, 18 s flight, out of radius) | Dead ball, reset at the top |
| Ball perched above 1.7 m (board top, hoop arm) | Nudged toward the court up to 4 times, then put away |
| Opponent stalled 5 s or wandered | Stood back on a clear court spot. If none exists, the game ends |
| Reload | Nothing is saved; the courts reset. The start notice says "pickup games aren't saved" |

There is at most one opponent node per level (`CourtBasketballs/CourtOpponent`).
It is created lazily and reused for every game and rematch. When it is not
playing, it is hidden with collision layer and mask 0. A start/quit loop is
tested to keep exactly one instance.

## Files (all owned; no shared file edited)

- `godot/scripts/city/city_basketball.gd`: extended controller. Every existing
  method, field and status key is kept. New: sessions, rules bridge, opponent
  bridge, analytic rim, perch/lost safety, shot plan and meter, HUD lines,
  semantic API.
- `godot/scripts/city/city_basketball_court.gd` (new): pure court frame and
  launch-speed solver.
- `godot/scripts/city/city_basketball_rules.gd` (new): pure rules state.
- `godot/scripts/city/city_basketball_opponent.gd` (new): opponent actor and
  court-local AI.
- `godot/tests/city_basketball_smoke_runner.gd`: all prior assertions kept.
  It now resets bindings in memory so a personal controls file cannot change
  the results.
- `godot/tests/city_basketball_rules_smoke.gd` + `_runner.gd` (new, about 65
  checks): real `park_court_0` (full) and `park_court_11` (half) frames, arc and
  corner boundaries, centre-line and sideline distances, clamping, spawn and
  exit points, the stepped-gravity solver against a step simulation, and every
  rules transition, including duplicate-score refusal, the clear rule, out of
  bounds, the win, rematch and abandon.
- `godot/tests/city_basketball_match_smoke.gd` + `_runner.gd` (new, about 90
  checks): a half court and a full court on one floor with solid backboards.
  It covers:
  - Challenge routing (T, Space, Shift, empty-hand shoot button).
  - Opponent walk-on, turn-then-walk with no sidestep, and guarding gap and
    position.
  - Input-driven charge → meter window → real make (+1 once).
  - The opponent's check, real shot and score with its value.
  - Defensive rebound race and clear.
  - Goaltending refusal.
  - Phone hold while a flight lands.
  - The player's defensive rebound and an uncleared make (no basket).
  - Holder and loose-ball out of bounds.
  - Lost ball.
  - Pause freeze, impact fumble, leave-area warning and abandon, despawn with
    no collision left, reuse, suspend, seat and quit confirmation.
  - Win, rematch with the loser's ball and the same opponent.
  - Spawn churn (8 cycles).
  - Full-court half selection and centre-line out of bounds.
  - Remapped challenge key and key repeat.
  - Perched-ball recovery.
  - Shootaround stats, feedback and summary.

Run:
`python godot/tools/godot_run.py --timeout 240 -- --headless --script res://tests/city_basketball_rules_smoke.gd`
and the same for `city_basketball_match_smoke.gd` and `city_basketball_smoke.gd`.
Root's real-level runners that use basketball (`city_nonviolent_session_runner`,
bicycle session, mounted save) rely only on preserved API: `balls`, `_held`,
`shots`, `get_status()` keys and `suspend(true)`.

## Integration requests for root

None are required; the current level wiring already routes everything. These
are optional:
- Call `basketball.cancel_activity("…")` on case start, cutscenes and fresh
  world.
- `godot/README.md` still calls basketball "a shooting foundation, not a
  complete basketball match". Root owns that file and may update it.
- The power meter is its own small CanvasLayer, so the settings text-size
  scaling does not reach it. Root can move it into the HUD if wanted.

## Limitations and risks

- **Unrun.** Everything above is static review. GDScript typing, the physics
  fixtures and timing-based assertions (opponent reaching balls within time
  budgets, bounce paths staying in bounds) are the most likely places for
  first-run failures. Each check has its own message to make triage quick.
- **Simple AI.** Defense is positional only: no steals, blocks, help defense
  or pathfinding beyond alternating side detours. Courts are open slabs with
  poles outside the lines. Strict turn-in-place-then-forward movement (house
  rule) can look a little stiff when the guard repositions; hysteresis keeps
  it from shuffling.
- **Dribble is visual.** The opponent's dribble is not simulated. Its floor
  contact plays the existing `court_bounce` sound through
  `NeighborhoodAudio.play_activity`. The player still carries without
  dribbling, because the existing real-level test asserts the ball stays in
  the hand.
- **Floor height estimate.** The goaltending, reach and perch height checks
  use the court plane taken from the record origin and rim heights. Lateral
  grade is ignored; it is at most 1.5% on these courts. Physics uses the real
  collision floor.
- **Full courts** are played as half-court games at the challenger's end. Full
  courts are not played end to end.
- **New UI strings.** The opponent's speech lines and HUD strings are new
  text. No existing owner lines were changed.
- **Prompt line.** "T · Challenge a court regular to 11" appears whenever the
  explorer is within 3 m of any court. Root may find this too chatty.
- **Notices.** One-off messages use `level.show_notice` and its six-message
  queue. A burst of game events can be dropped from that queue, but the
  activity's own prompt line always carries the latest shot feedback.
