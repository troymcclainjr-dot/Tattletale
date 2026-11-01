# Bounded runtime follow-up

Reviewed `.work/alive-next/auto-fixes.json` against the current working tree after the world repairs. The JSON is a planning snapshot: several `not_started` entries now have implementations. This note records source evidence, not new engine certification. World geometry and published manifests were held stable.

## One safe fix implemented: AF-10

`city_npcs.gd::_spawn` silently omitted a failed mission contact after a warning. The living-world smoke checked only resident, lookout and officer, even though gardener, organizer and caretaker also supply cases. Added a required-contact list and an engine error on failed placement for those six IDs; added the three missing contact checks to `city_life_smoke_runner.gd`.

Patrol placement intentionally retries other streets. Escalating every unsuccessful attempt would incorrectly fail recoverable placement, so individual retries retain warnings. Only a final total below six patrols raises an error; the smoke now checks six complete foot patrols. No positions, identities, candidate selection, actor counts or saved recipes changed. Root should run the existing living-world fixture; no engine was launched here.

## Current source supersedes parts of the planning snapshot

| Items | Current evidence | Remaining bounded check |
|---|---|---|
| AF-01/02/03/15 | `pen_lucy_level.gd:306`, `:1049`, `:1064`; `city_settings.gd:73` now show blocked-save reasons, expose recovery, separate busy/blocked/write failures, and show checkpoint age. | Exercise recovery/cancel with original bytes preserved. Startup notice is transient; persistent blocked status currently lives in Settings. A small always-visible saving-paused badge would complete the persistent-notice requirement without redesigning save slots. |
| AF-04 | `city_map_overlay.gd:50` and `city_minimap.gd:67` now create attribution labels. | Visual/narrow-window check; no additional source fix proposed. |
| AF-05 | Settings now has a Credits action. | Source presence does not prove shipped notices or full provenance. Keep the export acceptance check. |
| AF-08 | `city_settings.gd:145` starts music on initial settings application; `pen_lucy_level.gd:900` synchronizes audio pause. | Run the pause/resume and saved-volume fixture after the audio worker integrates. No parallel audio edits. |
| AF-09 | `pen_lucy_level.gd:546` now queues notices and gives a minimum display time. | Queue is bounded to six and drops oldest on overflow; it has no priority classes. Some direct notice writes remain. Three-message burst acceptance should pass, but do not claim the full priority requirement without a test. No new notice framework is needed for this final pass. |
| AF-20/26/33 | Export, phone rerun and integrated external audit are owned by root. | Await their actual reports; do not infer success from source. |

## Remaining small fixes worth scheduling

1. **AF-29 — explain current combat rules in Controls.** `city_settings.gd:55` lists keys but does not state that defeat is a short knockdown/recovery or that pistol ammo is not replenished in this build. Two accurate sentences and a UI text assertion would improve discoverability without changing combat design. This is the smallest remaining unowned change.
2. **AF-01 — persistent saving-paused indicator.** Keep the current detailed Settings/recovery flow. Add a compact persistent indicator only while `world_save.get_status().write_blocked` is true; clear it after successful recovery. This prevents a queued/transient startup notice being the only warning during play. Root owns these shared UI files.
3. **AF-11 — explicit missing traffic bootstrap diagnosis.** `city_traffic.gd:81–108` still selects only Old York Road and silently returns for missing/short data. The present map has the route, so this is not a current-world traffic failure. A descriptive error on invalid bootstrap is a safe bounded guard; longest-road substitution should be validated against network/signal construction before being claimed safe. Vehicle/traffic worker owns that area, so no edit was made.

AF-12/13 recycling and long soaks belong after the current tire/traffic integration and need measured offscreen/visibility/reservation tests. AF-14 case history, AF-16 save identity migrations and AF-17 broad input mapping have wider contracts; they should not be rushed into a final visual pass. Creative decisions D1–D9 remain decisions, not automatic fixes.

## Offscreen capture handoff

New entry: `godot/tests/city_alive_next_render.gd`; runner: `city_alive_next_render_runner.gd`. Four exact user camera positions/headings/pitches use FOV68, followed by Row170 rear service and up to two actual conifer silhouettes with a clear architecture sightline. Uses a private SubViewport and hidden/unfocusable root; refuses headless dummy rendering. Outputs images and `integration-report.json` to `artifacts/alive-next/visual`.

```powershell
$env:APPDATA = 'C:\files\projects\Tattletale\.work\test-profile'
python godot/tools/godot_run.py --timeout 300 -- --log-file C:/files/projects/Tattletale/.work/alive-next/world-render-engine.log --script res://tests/city_alive_next_render.gd -- --offscreen-validation
```
