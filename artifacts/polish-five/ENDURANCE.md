# Ten-minute steady-walk endurance

Run `sustained-polish-five-measured-565004463600` completed **19 checks with 0 failures**, using the real renderer at 1280×720, balanced quality, scale 1, uncapped frames and a 30-second warmup. The measured interval was **600.007538 seconds**: **87 sidewalk loops, 2,249.87 m walked**, within 12.35 m of the starting neighborhood. Normal simulation, traffic, residents and isolated test autosaves remained active.

| Measurement | Result |
|---|---:|
| Frame median / p95 / p99 | 9.8 / 18.4 / 28.8 ms |
| Maximum frame interval | **988.315 ms — unresolved** |
| Frames measured | 59,319 |
| Maximum measured GPU / render CPU | 18.360 / 29.888 ms |
| Population throughout | 1,200 ambient / 40 daily / 90 traffic |
| Godot static memory change | +3,151,906 bytes |
| Object / node change | +24 objects / +1 node |
| Orphan nodes | 0 throughout |
| Process private memory, first → last measured sample | 3,128,143,872 → 3,132,641,280 bytes (+4,497,408) |
| Process working set, first → last measured sample | 2,153,627,648 → 2,165,477,376 bytes (+11,849,728) |

Frame percentiles are histogram upper bounds at 0.1 ms resolution; the maximum is exact. Process memory comes from the external sampler's first and last rows inside the measurement interval, rather than startup peaks. These modest increases and zero orphan samples are evidence from a bounded ten-minute run, **not proof of indefinitely leak-free operation**.

## Unresolved long frame

The histogram did not retain the maximum frame's timestamp. Five-second samples show a unique 0.829-second wall-versus-simulation loss in approximately measurement seconds 390.064–394.994. Separately, three consecutive process samples report **zero Godot CPU time** across approximately seconds 390.317–391.085, with unchanged private memory/working set, normal reported CPU performance and only 1.68–4.71 logical cores of total host activity. This is consistent with a blocked or suspended process interval, but it does **not** establish that it was the 988.315 ms frame or identify an external cause. Internal I/O or driver waits remain possible. The independent telemetry sampler had no gap longer than 0.303 seconds.

Heavy background CPU activity occurred elsewhere in the run; it does not explain this specific interval by itself. There were no measured-window engine warnings, errors or log output, no runtime building background loads, and no streaming failures. Neither the rendering maxima nor these clean checks establish the cause of the long frame.

## Source and diagnostic scope

The measured source snapshot predates the final streaming null-player guard and the newly added slow-frame diagnostics. Those changes do not reduce population or simulation behavior. Future runs retain only the worst 32 frame intervals over 50 ms, with timestamps, process/physics/render counters and cheap save metadata. This bounded diagnostic cannot retrospectively attribute the older 988.315 ms result.

Raw evidence:

- [Result and all 19 checks](C:/files/projects/Tattletale/.work/priorities-five/session-validation/sustained-polish-five-measured-565004463600/result.json)
- [Five-second world samples](C:/files/projects/Tattletale/.work/priorities-five/session-validation/sustained-polish-five-measured-565004463600/samples.jsonl)
- [Process telemetry](C:/files/projects/Tattletale/.work/five-priorities-20261101/performance/polish-five-measured/sustained-polish-five-measured-565004463600/process-telemetry.csv)
- [Launch receipt, command and source verification](C:/files/projects/Tattletale/.work/five-priorities-20261101/performance/polish-five-measured/sustained-polish-five-measured-565004463600/launch.json)
- [Engine log](C:/files/projects/Tattletale/.work/five-priorities-20261101/performance/polish-five-measured/sustained-polish-five-measured-565004463600/engine.log)
- [Measured source snapshot](C:/files/projects/Tattletale/.work/five-priorities-20261101/performance/polish-five-measured/source/snapshot.json)
