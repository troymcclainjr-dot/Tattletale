# Mixed real-city validation session

Entry: `godot/tests/city_polish_session.gd`.
Runner: `godot/tests/city_polish_session_runner.gd`, inheriting the existing foundation acceptance fixture and its real input, world startup, safe rendering, screenshot, checkpoint, and incident-observation helpers.

## Lifecycle and evidence

One production city remains alive through these phases, with its world instance ID checked after each activity:

1. Phone home/apps, a real private-gallery photo, map symbols/legend, and normal modal closure through existing input helpers.
2. Disabled attack controls, actual bicycle mount/pedal/brake/dismount, and camera-independent steering checks through the foundation helper.
3. Pantry: arrange a collision-clear street-side starting point, physically walk to the authored counter, press E, click the actual bandana purchase button, verify the exact 30-unit debit and equipped ownership, and close the shop.
4. Court: arrange a collision-clear approach, walk to the existing ball, press E to pick it up, interrupt actual shot charges with pause/phone/map, verify that release/challenge inputs do not leak through those modals, then release a real shot and observe displacement and physical floor contact.
5. Incident: the inherited real planner chooses a live crossing/performance; real sight/LOS establishes witness provenance, and the phone Police/Enter route files the report. No witness/evidence flags are assigned.
6. Observe the actual police response for up to 180 wall-clock seconds before checkpointing. Record dispatch stages, unit states, officer positions, incident resolution and the unchanged checkpoint barrier on transitions and every ten seconds. Require natural resolution and barrier release; a timeout, failed/cancelled call or stuck officer is a failure, never cleared by fixture mutation.
7. One explicit final checkpoint save and fresh-scene reload, using the established foundation roundtrip. Verify unchanged wallet/equipped purchase, retained private gallery, cleared transient court state, pacifist policy, and full population after reload.

No helper is run in a separate city or process before the explicit final reload. Failed physical pantry/court access remains a failed assertion; the runner never teleports to the interaction target to turn that failure into a pass. No money, rewards, ball velocities, baskets, scores, completion states, or report provenance are seeded.

## Boundaries

- Hard ten-minute watchdog includes initial boot and final reload, independent of optional session-duration arguments.
- Dynamic loader requires a rendered backend, explicit `--offscreen-validation`, and a private user-data directory beneath the project's `.work/` directory.
- Inherited guard keeps the render window off all monitors, unfocusable, and the pointer visible. Screenshots use the guarded inherited viewport capture.
- Private checkpoint, screenshots (including the bicycle still moving after real W input), result JSON, phase samples, and `response-wait.jsonl` dispatch diagnostics go to `.work/polish-five/session-<run-id>/`. The ordinary production user checkpoint provider stays disabled.
- Full 1,200 ambient / 40 daily residents / 90 traffic population is retained. Runtime code and population settings are untouched.

## Coverage limits

This is a continuous state/integration session with arranged scenario starting positions, not an uninterrupted route walked across the whole city. Basketball covers ball pickup, shot release, floor contact and modal cancellation; it does not claim a made basket, full match completion or rematch. It does not complete a quest, validate EMS response, or establish performance thresholds. Phase samples are diagnostic evidence only. The parent tests EMS separately.

The incident is requested through the production planner for repeatability; the player must then genuinely observe it before filing through the phone. The final reload intentionally creates a fresh city only after the continuous interaction portion has completed.

## Validation status

Source reviewed against the existing foundation, commerce-city and basketball-city runners. Static diff whitespace check passed. Parent owns parsing and all engine execution; this worker launched no Godot process. Runtime results must be taken from the parent's actual run and its `result.json`, not inferred from this design.

Parent's first rendered run (`polish-mixed-r1`) reached 101 passed / 2 failed checks. All interaction phases passed; the save correctly refused while police were still responding after the inherited 15-second wait, so no reload occurred. The revised fixture waits for the real response before entering that helper and skips restoration assertions if a reload did not happen. Rerun required to validate the revision.

The second rendered run exposed a real brake-to-reverse edge case after the moving screenshot: the inherited render-frame observation missed the brief zero crossing and continued holding S into reverse. The production bicycle now provides a short stopped dwell before held-S reverse, and this session observes every physics frame and releases the actual S key when the bike stops (bounded to three seconds). No manufactured speed or forced dismount is used. The new dwell also has fixed/uneven-timestep regression coverage in the bicycle polish runner; parent reruns are required.
