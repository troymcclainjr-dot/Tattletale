# Integrated performance measurements

All runs use the same active Old York route, 1920×1080, Balanced, 4× MSAA, private viewport, uncapped frames, 90 moving cars, 1,200 ambient people and 20 daily residents. Each sample is 20 seconds after startup/warm-up. These are short route measurements, not a whole-map or long-session guarantee.

| Run | Delivered FPS | Frame p50/p95/p99 ms | Draw calls median | GPU ms | Render CPU ms | Traffic ms | NPC ms |
|---|---:|---|---:|---:|---:|---:|---:|
| alive-next-before | 184.9 | 4.47 / 9.78 / 13.21 | 1495 | 2.04 | 2.03 | 2.58 | 0.56 |
| alive-next-after-a | 94.9 | 10.57 / 17.42 / 22.31 | 1576 | 2.87 | 3.15 | 3.75 | 0.67 |
| alive-next-after-b | 121.5 | 7.83 / 15.93 / 21.00 | 1563 | 2.31 | 2.47 | 3.37 | 0.59 |
| alive-next-legacy-cars | 101.5 | 9.11 / 18.53 / 24.28 | 1523 | 2.32 | 2.85 | 3.87 | 0.69 |
| alive-next-final-a | 135.2 | 6.71 / 13.84 / 18.29 | 1576 | 2.13 | 2.41 | 2.99 | 0.59 |
| alive-next-final-legacy | 146.3 | 5.83 / 12.80 / 16.56 | 1533 | 2.09 | 2.31 | 3.01 | 0.56 |
| alive-next-final-b | 123.1 | 7.62 / 16.03 / 20.20 | 1565 | 2.24 | 2.60 | 2.97 | 0.57 |

## Interpretation and limits

The early `legacy-cars` run overlapped a graph update and is excluded from causal comparisons. Final A / legacy / B were run serially with no build, graph, other engine or agent CPU job launched alongside them. GPU telemetry is retained; clock state was observed, not forced. The baseline is one pre-integration run, not a statistically stable baseline distribution.

The legacy flag changes both model selection and collision hulls, while preserving population, routes, placement and settings. It isolates combined catalog cost; it does not independently isolate rendering, physics or the new crowd meshes. The two normal final runs bound observed repeat variation. Differences smaller than that variation must not be assigned to one feature.

The new cars expand parked model batches from 7 to at most 19; actual submitted draw counts are in the table. The modular crowd retains spatial/pose batching but adds geometry: 3,192 triangles for the detailed standing mesh and 592 for its far version, compared with the old blockouts. Twenty daily rigs use 180 surfaces rather than 462. These are implementation budgets, not proof of an FPS improvement.

Applied conservative improvements: no tire-profile allocation for healthy-car braking; cached damaged profiles with content-based invalidation; idle audio property-write suppression; bounded offscreen damage updates; recycled damaged cars release unnecessary collision presence. No people or traffic were removed to obtain these results.

Raw measurements and source provenance remain under `artifacts/civic-build/<run>/`; this report has a machine-readable companion `performance-results.json`. The final frozen validation manifest additionally hashes runtime assets. Long firefight, night, whole-map flyover and hour-long mixed-session acceptance remain shipping work.
