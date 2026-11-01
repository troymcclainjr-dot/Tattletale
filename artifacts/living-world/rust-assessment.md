# Rust assessment for this project

Recommendation: keep gameplay authoring in GDScript. Do not rewrite all subsystems. Consider one batched native simulation module only after measuring script-only work inside the traffic/crowd hot paths.

The current city orchestration, player controller, traffic, missions, residents and UI are GDScript. Godot rendering, collision queries, physics and MultiMesh uploads already execute in native engine code. Blender/source export tooling is Python; the older web prototype is JavaScript. Translating a GDScript call to a physics query into Rust does not remove the query, draw call, shader cost, streamed mesh build or GPU bottleneck.

## What could benefit

Pure numeric lane/spacing decisions, spatial indexing and packed-array schedule batches are plausible candidates. Send a batch of packed data into one extension call per simulation tick, then apply results through a small engine-facing adapter. Avoid one cross-language call or Godot Dictionary conversion per NPC per frame. Keep collision authority and the current gameplay API intact, with a GDScript reference path for deterministic comparison. The current twenty-resident scale does not justify introducing a compiled dependency just for schedule selection.

Mission flow and dialogue are not credible optimization priorities: existing measured case work is only a few microseconds per physics tick. New resident component measurements are recorded in the adjacent benchmark folders; they include native physics calls and are not a measurement of interpreter overhead alone. Frame medians, direct per-physics-tick components and the engine's sampled CPU monitors have different denominators and must not be added together.

## Cost and acceptance gate

A Rust GDExtension requires a Rust toolchain, a compiled shared library, a binding/API compatibility decision for the installed Godot 4.7.2 engine, and debug/release binaries for each exported platform. Those binaries must be reproducibly built and included in clean-clone/export checks. This adds build and debugging complexity while the current content is still changing quickly. No Rust toolchain was available on PATH during this review; no Rust implementation or synthetic speedup claim is being presented.

Before a prototype, split traffic timing into numeric decisions versus physics/server calls and allocation. First try spatial indexing, cached queries and staggered walkers in GDScript. If a substantial numeric bottleneck remains, implement only that kernel and compare release builds on the same route, active population, time, quality and render target. Require a repeatable tail-frame improvement, identical traffic/gameplay outcomes, and successful clean-clone export. Retain the existing implementation if the difference is within run-to-run variance.

## Primary sources checked

Godot explicitly recommends profiling bottlenecks and repeated timings with cache effects considered: [CPU optimization](https://docs.godotengine.org/en/stable/tutorials/performance/cpu_optimization.html). Its engine/server costs are distinct from script work; the report's selective-migration recommendation is our project-specific inference.

The official godot-rust guide explains the compiled `cdylib`, GDExtension loading and platform-specific library mappings: [Hello World](https://godot-rust.github.io/book/intro/hello-world.html). This establishes feasibility and packaging requirements, not an FPS guarantee or a verified 4.7.2 binding version.

The independent Opus 5.5 high audit also recommended selective migration, not a rewrite. Its raw report is preserved in `opus-audit.md`; it did not browse documentation, so unverified platform-specific assertions there are not treated as acceptance facts. Root checked the primary sources above.
