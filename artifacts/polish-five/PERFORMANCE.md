# Performance evidence — polish five

Frozen baseline `sustained-polish-five-matched-base-730506290100` and candidate `sustained-polish-five-matched-final-042157134600` completed 180.016 / 180.023 measured seconds. Checks: 37/0 and 37/0 passed/failed. Comparable configuration: **True**. Clean runs: **True / True**.

| Measurement | Baseline | Candidate |
| --- | ---: | ---: |
| Frame median (ms) | 3.556 | 3.873 |
| Frame p95 (ms) | 12.032 | 12.120 |
| Frame p99 (ms) | 16.272 | 15.063 |
| Frame max (ms) | 62.369 | 44.271 |
| Frames > 33.333 ms | 14 | 7 |
| Frames > 50 ms | 3 | 0 |
| Mean draw calls | 547.281 | 573.143 |
| Player move_and_slide maximum (ms) | 3.564 | 3.423 |
| Background logical cores, mean | 3.162 | 2.813 |
| Walked distance (m) | 277.412 | 277.222 |

Population ranges (ambient/daily/traffic): `{'ambient': [1200, 1200], 'daily': [40, 40], 'traffic': [90, 90]}` / `{'ambient': [1200, 1200], 'daily': [40, 40], 'traffic': [90, 90]}`.

| Streaming stage maximum (ms) | Baseline | Candidate |
| --- | ---: | ---: |
| refresh_with_details | 25.048 | not recorded |
| detail_frame_slice | not recorded | 11.529 |
| detail_pass_cpu | not recorded | 21.862 |
| detail:CityVegetation | 16.913 | 11.450 |

**Scheduling budget is soft.** A single indivisible provider can exceed it. `detail_frame_slice` measures a dispatch frame; `detail_pass_cpu` sums CPU across a pass’s frames and is **not** a single-frame hitch. `refresh_with_details` covers synchronous full refreshes; its changed call semantics prevent a simple like-for-like comparison with slices. Vegetation subphases are nested inside their parent and must not be added to it.

Candidate budget: 2500 µs; scheduling counters: `{'budget_overruns': 154, 'max_slices_per_pass': 5, 'passes': 714, 'slices': 1903}`.

| Candidate vegetation subphase | Mean (ms) | Max (ms) | Total CPU (ms) |
| --- | ---: | ---: | ---: |
| mesh_arrays | 0.098 | 1.243 | 70.098 |
| mesh_upload | 0.138 | 1.839 | 98.742 |
| physics | 0.032 | 5.864 | 22.651 |
| scan | 0.600 | 1.050 | 428.367 |
| unload | 0.002 | 0.104 | 1.625 |

Background applications were uncontrolled and not inventoried. Per-phase timings and raw-source hashes are retained in [performance-comparison.json](performance-comparison.json). This is a rendered off-desktop, uncapped fixture with scripted relocations, normal walking, phone previews, and stationary Greenmount camera sweeps. Profiling overhead is included; GPU timings may lag. The candidate contains the combined polish changes against the commit 98e4d488 baseline; this is not an isolated streaming-only comparison. One pair does not establish a general FPS gain or attribute any change solely to streaming, and traversal memory growth is not a leak test. Older frame-dependent camera captures are documented separately in [CAMERA_BENCHMARK.md](CAMERA_BENCHMARK.md).

Camera sweep signatures: `{'clock': 'elapsed_wall_usec', 'phase_heading': 'route_tangent_or_zero', 'pixels_per_second': 18.0, 'schema': 2}` / `{'clock': 'elapsed_wall_usec', 'phase_heading': 'route_tangent_or_zero', 'pixels_per_second': 18.0, 'schema': 2}`. Matching phase headings and verified shared fixture hashes are required for configuration equivalence.

Engine error/warning counts: 0/0 baseline, 0/0 candidate. Source unchanged at capture end: True / True. These receipts do not assert later working-tree equality.

Shared harness raw hashes differ only in CRLF/LF line endings for the files below. Every raw hash is still verified against its own frozen-source manifest. Equivalence additionally compares SHA-256 after **only** replacing CRLF bytes with LF; no other whitespace or text is normalized. Full raw and canonical hashes are in the JSON; prefixes below are 12 hex characters.

| Shared file | Baseline raw | Candidate raw | Shared canonical LF | CRLF count B/C |
| --- | --- | --- | --- | ---: |
| tests/city_priorities_session_fixture.gd | `cf106c18048d` | `027b36a888da` | `027b36a888da` | 363/0 |
| tools/city_perf_stats.gd | `35080173c1f3` | `7adc558f3d52` | `7adc558f3d52` | 77/0 |
| tools/city_perf_timeline.gd | `46f9b835dc9c` | `b4759d9b2b56` | `b4759d9b2b56` | 214/0 |

Separate candidate endurance (`sustained-polish-five-measured-565004463600`, mode `walk`): 600.008 seconds, 19/0 checks, clean run True; frame median/p95/max 9.800/18.400/988.315 ms. This workload has no matched baseline here and is not compared to traversal. Histogram percentiles may be upper-bin bounds; see its recorded notes in JSON.
