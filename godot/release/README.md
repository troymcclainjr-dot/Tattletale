# Windows standalone release candidate

Run from the repository root:

```powershell
python godot/tools/export_city_release.py --check
python godot/tools/test_export_city_release.py
python godot/tools/export_city_release.py --prepare-only --build-id staging-review
python godot/tools/export_city_release.py --build --build-id pen-lucy-next
```

`--check`, the Python tests, and `--prepare-only` do not launch Godot. A build ID must be new: the pipeline never overwrites previous stages or candidates. Use a fresh ID after reviewing a preparation-only snapshot.

`--build` acquires the same `GodotLock` used by `godot_run.py`. It imports and exports the isolated staged project with a headless Godot editor, then boots the **exported executable** headlessly from its own output folder. No second editor/engine should be launched outside that shared lock. A heartbeat keeps the shared lock current during long builds. Logs stay in `.work/release-stage/<build-id>/`.

The exporter takes the current runtime filesystem, including dirty/untracked runtime files; it does not export a stale Git checkout. Assets, scripts and scenes are copied, along with a separate copy of the import cache. No hardlinks, `.git`, tests, development scripts, editor state or source logs are copied into the runtime snapshot. The one import helper exists only for staged GLB imports and is excluded by the export filter. Runtime JSON and the credits text are explicitly included.

Only the staged `project.godot` changes its main scene to `res://scenes/city/pen_lucy.tscn`. The original remains `res://scenes/main.tscn`, byte-for-byte checked before/after export. Input settings, save paths and in-game F6 inspector are preserved. Exporting the preset directly from the source editor retains that source main scene; use this pipeline for the Pen Lucy candidate.

Godot 4.7.2 Windows x86_64 release/debug templates are expected at `%USERPROFILE%/AppData/Roaming/Godot/export_templates/4.7.2.stable`; `--templates-dir` overrides this. `GODOT_EXE` uses the existing wrapper's executable selection. Explicit template paths work with isolated profiles. Import/export and standalone validation each receive workspace-local APPDATA, LOCALAPPDATA, TEMP, TMP and TMPDIR, with directories created before launch.

Output is gitignored `artifacts/releases/<build-id>/`, containing the executable, separate PCK, controls, checksums, source snapshot hashes, font licenses, exact engine/dependency notices and map-derived data. A ZIP is created only after the packaged runtime passes and payload checksums verify. The package requires no editor, Python, Blender or source checkout. It is an unsigned candidate; code signing and store publication are separate release actions.

The stage-only boot probe is dormant during normal play. With the pipeline's smoke flag it verifies the actual main scene, ready state, release template, 1,200 crowd / 20 daily / 15 named actors, absence of placeholder assets, and inspector availability. It also obtains engine copyright/license text directly from the **shipped template**. The validation process uses isolated APPDATA and `--offscreen-validation`, preserving player saves. Logs and reports are outside the PCK and distribution folder. This verifies boot/resource closure, not final interactive or performance acceptance.

Verify a candidate again with:

```powershell
python godot/tools/export_city_release.py --verify artifacts/releases/pen-lucy-rc3
```

`manifest.json` records checked-in provenance, not a claim that an export already succeeded. The final `release-manifest.json` includes the actual packaged-runtime receipt and payload hashes. The runtime credits file is `res://assets/data/release_notices.txt`; Settings can read it without depending on external distribution files.

Implementation follows Godot's [command-line export workflow](https://docs.godotengine.org/en/stable/tutorials/export/exporting_projects.html#exporting-from-the-command-line) and [Windows executable/PCK packaging](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_windows.html). Engine notices use the documented [license and copyright APIs](https://docs.godotengine.org/en/stable/classes/class_engine.html).

The `pen-lucy-rc3` package completed export, standalone boot and checksum verification. It is evidence of runtime packaging, not final play/performance acceptance. Later source edits require a fresh build ID; never relabel the existing rc3 snapshot as a newer tree.
