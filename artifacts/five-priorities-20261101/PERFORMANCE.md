# Final sustained performance comparison

**Candidate-v3 passes the complete 180-second session cleanly; baseline-v3 reproduces six light-unpair errors during teardown. Overall frame performance is essentially unchanged.** Both pass all 37 gameplay/fixture checks. Baseline's native process exits 0, but the validation wrapper correctly fails with exit 1 because of the logged errors; candidate's native process and wrapper both exit 0. Neither times out. No errors occur inside either timed sample.

## Identity and conditions

Independent recomputation of every staged source hash matches both immutable manifests; both receipts also report unchanged source. Baseline is commit `c77e972d4a3e7bba78a6024d38f293115ba6feae`. Candidate is the converged working-source snapshot, not an isolated optimization. Both have identical v3 harness and launcher settings:

- Entry SHA256: `ff1222f9b26b1466e460fa4ed7c2c6999a389b103e3975726e93660e675ae8fc`.
- Runner SHA256: `85f2f3f83dc93b30fec46fa72ff88fa47bca0e984cde389fcbd2dbc923a0996b`.
- Real renderer, 1280×720, balanced, scale 1, uncapped, off-desktop/unfocusable, Dummy audio; same eight district/day-night phases and real walking/phone-camera input. Measured durations: 180.017 / 180.016 seconds.

All workers had finished before these sequential runs; user videos remained running. Native-engine CPU/memory telemetry and GPU timings are valid in both. System CPU averaged 4.446→4.166 occupied cores, indicating background conditions still differed. This is one observational pair, not a causal FPS experiment.

## Overall timings

Values are baseline → candidate. Percentiles retain relocation/loading spikes.

| Metric | Baseline | Candidate | Observed change |
|---|---:|---:|---:|
| Frame median | 3.633 ms | 3.643 ms | +0.3% |
| Frame p95 | 10.156 ms | 10.234 ms | +0.8% |
| Frame p99 | 12.994 ms | 12.983 ms | -0.1% |
| Frame mean / maximum | 4.883 / 264.489 ms | 4.933 / 272.996 ms | Mean +1.0% |
| GPU median / p95 | 1.899 / 3.721 ms | 1.911 / 3.751 ms | p95 +0.8% |
| Render CPU median / p95 | 1.398 / 2.556 ms | 1.418 / 2.450 ms | p95 -4.1% |
| Draw calls median / p95 | 609 / 1,134 | 601 / 1,134 | p95 unchanged |
| Native process CPU mean | 1.603 cores | 1.543 cores | -3.7%; contention-sensitive |
| Frames >33.3 / >50 / >100 ms | 11 / 4 / 2 | 10 / 6 / 3 | Transition tails persist |

## Phase comparison

Each cell is baseline → candidate. GPU timings can lag; per-phase aggregation is more useful than attributing a single frame to its concurrent GPU sample.

| Phase | Frame median ms | Frame p95 ms | Maximum ms | GPU p95 ms | Draw-call p95 |
|---|---:|---:|---:|---:|---:|
| Wyanoke day | 4.731→4.849 | 11.107→11.324 | 26.998→29.757 | 4.168→4.169 | 1,251→1,254 |
| Dumbarton day | 4.170→4.404 | 10.683→11.205 | 43.801→33.852 | 3.976→4.011 | 999→995 |
| Rose Hill/Cator day | 3.602→3.600 | 10.245→10.297 | 31.066→32.900 | 3.867→3.963 | 772→774 |
| Greenmount day | 4.951→4.372 | 10.964→9.948 | 256.747→272.996 | 4.170→4.133 | 1,275→1,270 |
| Wyanoke night | 3.640→3.569 | 10.082→10.231 | 99.180→103.817 | 3.038→3.082 | 801→802 |
| Dumbarton night | 3.208→3.247 | 9.163→9.352 | 31.084→33.248 | 2.906→2.878 | 629→629 |
| Rose Hill/Cator night | 2.902→2.953 | 8.712→8.991 | 30.615→34.389 | 2.805→2.846 | 476→474 |
| Greenmount night | 3.238→3.227 | 8.719→8.552 | 264.489→264.375 | 2.787→2.781 | 912→913 |

Greenmount day p95 improves 9.3%, while Dumbarton day worsens 4.9% and Rose Hill/Cator night worsens 3.2%. This mixed pattern and nearly identical overall p95/GPU/draw counts do not support a general speedup or broad frame regression.

| Phase | Render CPU p95 ms | Mean native CPU cores |
|---|---:|---:|
| Wyanoke day | 2.724→2.795 | 1.538→1.467 |
| Dumbarton day | 2.418→2.559 | 1.518→1.507 |
| Rose Hill/Cator day | 2.101→1.957 | 1.580→1.595 |
| Greenmount day | 3.437→2.747 | 1.689→1.552 |
| Wyanoke night | 2.527→2.366 | 1.618→1.508 |
| Dumbarton night | 1.964→1.957 | 1.684→1.670 |
| Rose Hill/Cator night | 1.606→1.660 | 1.504→1.590 |
| Greenmount night | 2.352→2.204 | 1.697→1.457 |

The three major transition spikes recur at the same locations: Greenmount day around t=67.8s, Wyanoke night around t=90.15s, and Greenmount night around t=157.8s. Candidate maxima there are 272.996, 103.817 and 264.375 ms. They occur within 0.31 seconds of the phase relocation; their GPU samples are below 3 ms. Streaming/scene activation remains the investigation target, but these data do not identify the exact CPU operation. As a diagnostic only, excluding the first second of each phase leaves worst frames of 36.060→34.389 ms; the acceptance figures above exclude nothing.

## Simulation CPU, population and memory

Grouped traffic mean is 2.740→2.765 ms per physics tick (+0.9%); NPCs 0.779→0.830 ms (+6.6%); daily residents 0.444→0.496 ms (+11.9%). The NPC/resident increase is an observed additional cost of about **0.104 ms per physics tick combined**, not a speedup. A single run cannot assign it to individual changes or fully separate variation, but it should remain visible in future profiling. Candidate has extra nested timing instrumentation absent from c77, so only the historical aggregate buckets are comparable.

Candidate traffic cars consume 157.692 ms/s, **95.2% of its 165.614 ms/s grouped traffic bucket**. Their mean/p95 is 2.632/3.501 ms per tick. Basketball is 2.820 ms/s, incidents 1.694, police assistance 1.267, and bicycle/reactions/driving/presentation each below 0.7. Bulk traffic motion/control remains the main CPU target; no population or update-cadence reduction was used.

Both retain 1,200/40/90 population in all 44 snapshots, zero orphans throughout, and zero streaming failures across all eight phases. Render frames advance 36,864→36,494; player walking is 277.348→277.474 m and aggregate traffic movement 55,430.198→55,480.443 m. Clock and unpaused-world checks pass. Both explicitly release the city before shutdown and drain audio after measurement.

Memory values below use decimal MB. Endpoints cross different districts/time-of-day and include retained fixture data.

| Metric | Baseline start→end (growth) | Candidate start→end (growth) |
|---|---:|---:|
| Engine static MB | 887.34→912.34 (+25.00) | 887.81→919.57 (+31.77) |
| Native private MB | 3,112.23→3,132.09 (+19.87) | 3,089.34→3,118.85 (+29.52) |
| Native working set MB | 2,145.97→2,170.55 (+24.58) | 2,125.42→2,156.58 (+31.17) |
| Objects | 18,984→18,298 (-686) | 19,007→18,321 (-686) |
| Nodes | 11,047→10,240 (-807) | 11,051→10,244 (-807) |

Static-memory OLS growth is 137.68→163.79 KB/s; private-memory growth 155.63→197.66 KB/s. Candidate grows more during the sample, although its ending native private/working-set totals are lower. Retained traces/profiling arrays, streaming and added instrumentation confound leak attribution. Zero orphans and identical node/object declines are reassuring, but **this is not a flat-memory or leak-free proof**. No progressive frame-time collapse appears; district changes prevent treating later faster windows as a same-scene endurance comparison.

## Acceptance and remaining work

The final candidate meets sustained functional/rendering/cleanup acceptance and confirms the NPC LOD light-unpair correction over the full workload. The retained fleet-concatenation cleanup has no demonstrated independent FPS benefit; the slower route-dictionary experiment was reverted and is absent from the final source. There is no basis to claim a causal FPS gain. Remaining measured concerns are transition hitches, modest NPC/resident CPU increases and memory-growth attribution, suitable for focused future investigations rather than speculative optimization now.

The [machine-readable comparison](C:/files/projects/Tattletale/.work/five-priorities-20261101/performance-final-comparison.json) includes exact snapshot hashes, full phase distributions/spikes, CPU summaries and trends. Source receipts: [baseline](C:/files/projects/Tattletale/.work/five-priorities-20261101/performance/baseline-v3/sustained-baseline-v3-602385832100/launch.json), [candidate](C:/files/projects/Tattletale/.work/five-priorities-20261101/performance/candidate-v3/sustained-candidate-v3-869464196400/launch.json). Earlier isolated correction and rejected-experiment evidence is retained in the [audit report](C:/files/projects/Tattletale/.work/five-priorities-20261101/performance-report.md).
