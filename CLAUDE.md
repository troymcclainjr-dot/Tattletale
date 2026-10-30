# Notes for Claude (and anyone else helping on this project)

## House rules (from the owners — always follow these)
- **Nobody walks in a different direction from the way they're facing.** NPCs and cars turn in place first, then move forward. The Pen Lucy player smoothly steers body and forward travel together, preserving speed through directional changes without hard turn-in-place pauses. No sideways or backwards sliding.
- **No solid props or people passing through each other.** Walkers wait or detour; cars stop and honk; solid props get a collider (`solidC` / `solidB`) or a body (`addBody`). Per the owner's later request, loose trash (including paper, cans and dumped-waste case props) is decorative and deliberately non-blocking.
- **Keep the owners' wording.** Lyrics and lines from "Still There" are used word for word. New lines are fine, but never "improve" existing ones.
- **Don't cut the camera between back-to-back lines by the same person** in cutscenes.
- This game is separate from the owners' claymation movie project (`claymation_movie_maker`). Don't touch those files from here.

## How the code is put together
- Plain HTML + classic `<script>` tags, no build step. Open `index.html` to run.
- The scripts in `index.html` share one global scope and **load in order**. Anything that runs at load time can only use things from files above it. Functions are only *called* once everything has loaded, so most cross-file references are fine.
- three.js r128 is loaded from cdnjs as the global `THREE`. If you upgrade, check for removed APIs.
- World coordinates: x runs east along the street, y is up, houses are at negative z (z = -7 is the house fronts), the street is z 0..14. Facing: `yaw` 0 faces +z; forward is `(sin(yaw), cos(yaw))`.
- People are built with `makePerson()` and posed every frame with `pose()`. NPCs that walk use `makeWalker()` + `stepWalker()`.

## Adding a crime
1. `defCrime("id", {...})` in a `crimes-stage*.js` file: `title`, `who`, `time` (seconds), `pts`, `line` (what 2-Pack says), `target()` (where it is), and `steps` (each one has `k` (kind), `t` (case-file text) and `m` (marker text)).
2. Step kinds: `spy` and `tail` use the binoculars (optional `spyOk()` gate, optional `onSpy()`), `call` uses the payphones/precinct (cop car comes, so give it `bust` lines and `slots`), and anything else is handled by the crime's own `act()` (returns `{x,z,r,label,fn}` for the E key).
3. Call `adv(this)` to move to the next step and `busted(this,"LABEL!")` when it's done.
4. Add it to a stage's `pool` in `crimes-core.js`, plus `EXPIRE` and `TOLD_NAMES`.

## Testing
Open `index.html` in Chrome or Edge. `window.__tt` exposes the game state and a `tick(dt)` function for quick checks in the browser console (for example `__tt.startCrime("ricky")`).
