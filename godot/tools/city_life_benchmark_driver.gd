extends Node
## Measures wall-clock frame delivery while real input moves the explorer on the route.
## Leaves NPCs, traffic, HUD, collisions and the normal chase camera running.
## Schema 2 adds a per-cycle phase timeline (extreme-priority bracketing nodes
## plus SceneTree/RenderingServer signals), a CPU calibration probe, pinned
## 3D scale/FOV, engine counter deltas, per-second budgets and raw traces.
## Earlier keys keep their meaning. The same driver bytes must run in both
## trees of an A/B comparison; tools/city_perf_ab.py stages that.
const Stats := preload("res://tools/city_perf_stats.gd")
const Timeline := preload("res://tools/city_perf_timeline.gd")
const COUNTERS_PATH := "res://scripts/city/city_perf_counters.gd"
const SCHEMA := "city_life_benchmark/2"
const WARMUP_FRAMES := 120
const DEFAULT_FOV := 68.0
# No production node sets a process priority; these bracket every callback.
const FIRST_PRIORITY := -1073741824
const LAST_PRIORITY := 1073741823
const PIPELINE_MONITORS: Array[String] = ["PIPELINE_COMPILATIONS_CANVAS", "PIPELINE_COMPILATIONS_MESH",
	"PIPELINE_COMPILATIONS_SURFACE", "PIPELINE_COMPILATIONS_DRAW", "PIPELINE_COMPILATIONS_SPECIALIZATION"]
var sample_seconds := 7.0
var render_size := Vector2i(1280, 720)
var output := "res://../.work/city/life_benchmark"
var fps_cap := 0
var lead_in_seconds := 0
var pinned_fov := DEFAULT_FOV
var level: Node3D
var _walking := false
var _route: Array[Vector3] = []
var _waypoint := 1
var _progress_elapsed := 0.0
var _progress_position := Vector3.ZERO
var _stalled_seconds := 0.0
var _stalled_windows := 0
var start_route_index := 0
var _masked_roots: Array[Node] = []
var _render_inventory := {}
var _hidden_group := ""
var timeline: Timeline
var _marks: Array[Node] = []
var _probe_sink := 0.0

## Timestamp forwarders. The first mark runs before, the last after, every other
## _process/_physics_process callback in the tree.
class ProcessMark extends Node:
	var timeline
	var last := false
	func _process(_delta: float) -> void:
		if last:
			timeline.process_end(Time.get_ticks_usec())
		else:
			timeline.process_begin(Time.get_ticks_usec())

class PhysicsMark extends Node:
	var timeline
	var last := false
	func _physics_process(_delta: float) -> void:
		if last:
			timeline.physics_end(Time.get_ticks_usec())
		else:
			timeline.physics_begin(Time.get_ticks_usec())

func _mask_new_geometry(node: Node) -> void:
	if node is GeometryInstance3D:
		for root_node in _masked_roots:
			if root_node == node or root_node.is_ancestor_of(node):
				node.layers = 0
				break

func _inventory_geometry(node: Node, tally: Dictionary, hide_geometry: bool) -> void:
	# A later NPC detail transition must not restore cached render layers in a
	# render-only diagnostic. Physics layers and actor simulation stay intact.
	if hide_geometry and node.name == "RenderDetail":
		var saved_layers: Variant = node.get("original_layers")
		if saved_layers is Array:
			saved_layers.fill(0)
	var mesh: Mesh
	if node is MeshInstance3D:
		mesh = node.mesh
	elif node is MultiMeshInstance3D and node.multimesh != null:
		mesh = node.multimesh.mesh
	if mesh != null and node.layers != 0:
		tally.nodes += 1
		tally.surfaces += mesh.get_surface_count()
	if hide_geometry and node is GeometryInstance3D:
		node.layers = 0
	for child in node.get_children():
		_inventory_geometry(child, tally, hide_geometry)

func _configure_render_diagnostic(args: PackedStringArray) -> void:
	# Benchmark-only ablation: retain authored geometry/collision/population and
	# manager nodes, disconnect only the root's new sandbox polling/tick hooks.
	# Normal launch never calls this tool or supplies this diagnostic flag.
	# The manager nodes themselves keep processing (law/shops _process, signals).
	if args.has("--diagnostic-no-sandbox-logic"):
		for subsystem in ["progression", "law", "driving", "shops"]:
			level.set(subsystem, null)
	var index := args.find("--diagnostic-hide-group")
	if index >= 0 and index + 1 < args.size():
		_hidden_group = args[index + 1]
	var traffic: Node = _node(level, "traffic")
	var groups := {
		"city": [_read(_node(level, "render_optimizer"), "city"), _read(_node(level, "streaming"), "_proxy_root")],
		"people": [_node(level, "npcs"), _node(level, "residents")],
		"vehicles": [_read(traffic, "parked"), _node(level, "civic_fleet")],
		"details": [_node(level, "civic_district"), _node(level, "neighborhood_details"), _node(level, "power_grid"),
			_node(level, "yard_details"), _node(level, "park_courts"), _node(level, "park_furniture"),
			_node(level, "backlot_details"), _node(level, "alive_world"), _node(level, "vegetation")],
	}
	if traffic != null:
		for car in _read(traffic, "vehicles", []):
			groups.vehicles.append(car)
		var vehicle_renderer: Node = traffic.get_node_or_null("MovingVehicleRenderLOD")
		if vehicle_renderer != null:
			groups.vehicles.append(vehicle_renderer)
	for key in groups:
		var tally := {"nodes": 0, "surfaces": 0}
		for root_node in groups[key]:
			if _live(root_node) and root_node is Node:
				_inventory_geometry(root_node, tally, key == _hidden_group)
				if key == _hidden_group:
					_masked_roots.append(root_node)
		_render_inventory[key] = tally
	if not _masked_roots.is_empty():
		get_tree().node_added.connect(_mask_new_geometry)

## Defensive reads keep one driver usable against older and newer trees.
## Validity is tested before `is`: a type test on a freed instance is an error.
func _live(target: Variant) -> bool:
	return typeof(target) == TYPE_OBJECT and is_instance_valid(target)

func _read(target: Variant, property: String, fallback: Variant = null) -> Variant:
	if not _live(target):
		return fallback
	var value: Variant = (target as Object).get(property)
	return fallback if value == null else value

func _node(target: Variant, property: String) -> Node:
	var value: Variant = _read(target, property)
	if _live(value) and value is Node:
		return value
	return null

func _status(target: Variant, method := "get_status") -> Dictionary:
	if _live(target) and (target as Object).has_method(method):
		var value: Variant = (target as Object).call(method)
		if value is Dictionary:
			return value
	return {}

func _size(value: Variant) -> int:
	if value is Array or value is PackedVector3Array or value is PackedVector2Array:
		return value.size()
	return 0

func _int_option(args: PackedStringArray, option: String, minimum: int, maximum: int, current: int) -> int:
	var index := args.find(option)
	if index < 0:
		return current
	if index + 1 >= args.size() or not args[index + 1].is_valid_int():
		_fail(option + " requires an integer value")
		return -1
	var value := int(args[index + 1])
	if value < minimum or value > maximum:
		_fail("%s must be between %d and %d" % [option, minimum, maximum])
		return -1
	return value

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--outdir")
	if index >= 0 and index + 1 < args.size():
		output = args[index + 1]
	index = args.find("--start-route-index")
	if index >= 0:
		if index + 1 >= args.size() or not args[index + 1].is_valid_int():
			_fail("--start-route-index requires a nonnegative integer")
			return
		start_route_index = int(args[index + 1])
	for option in ["--render-width", "--render-height", "--sample-seconds"]:
		index = args.find(option)
		if index < 0:
			continue
		if index + 1 >= args.size() or not args[index + 1].is_valid_int():
			_fail(option + " requires an integer value")
			return
		var value := int(args[index + 1])
		if option == "--sample-seconds":
			if value < 5 or value > 30:
				_fail("--sample-seconds must be between 5 and 30")
				return
			sample_seconds = float(value)
		else:
			var minimum := 640 if option == "--render-width" else 360
			var maximum := 3840 if option == "--render-width" else 2160
			if value < minimum or value > maximum:
				_fail("%s must be between %d and %d" % [option, minimum, maximum])
				return
			if option == "--render-width":
				render_size.x = value
			else:
				render_size.y = value
	fps_cap = _int_option(args, "--fps-cap", 0, 1000, fps_cap)
	lead_in_seconds = _int_option(args, "--lead-in-seconds", 0, 10, lead_in_seconds)
	var fov := _int_option(args, "--pin-fov", 55, 90, roundi(DEFAULT_FOV))
	if fps_cap < 0 or lead_in_seconds < 0 or fov < 0:
		return
	pinned_fov = float(fov)
	_run.call_deferred()

func _physics_process(delta: float) -> void:
	if not _walking or level == null or _route.is_empty():
		return
	var here: Vector3 = level.player.global_position
	_progress_elapsed += delta
	if _progress_elapsed >= 0.5:
		var moved := Vector2(here.x - _progress_position.x, here.z - _progress_position.z).length()
		# A half-second window below 20 cm/s is effectively stopped, even if
		# collision jitter increments the player's total distance counter.
		if moved < 0.2 * _progress_elapsed:
			_stalled_seconds += _progress_elapsed
			_stalled_windows += 1
		_progress_position = here
		_progress_elapsed = 0.0
	while _waypoint < _route.size() - 1 and Vector2(here.x - _route[_waypoint].x, here.z - _route[_waypoint].z).length() < 0.35:
		_waypoint += 1
	var toward: Vector3 = _route[_waypoint] - here
	level.player.look(Vector2(-angle_difference(level.player.camera_yaw, atan2(toward.x, toward.z)) / level.player.mouse_sensitivity, 0.0))

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func _fail(message: String) -> void:
	Input.action_release("move_forward")
	_walking = false
	push_error("[city_life_benchmark] " + message)
	get_tree().quit(1)

func _distribution(values: Variant) -> Dictionary:
	return Stats.distribution(values)

func _save_image(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(output.path_join(filename))
	if error != OK:
		push_error("[city_life_benchmark] Could not write " + filename)

## Fixed CPU workload on the main thread, outside the sample. A paired run
## whose probe differs by more than a few percent ran on a different effective
## CPU (clock, scheduling, contention) and cannot support a code comparison.
func _cpu_probe() -> Dictionary:
	var script_best := INF
	for _repeat in 5:
		var began := Time.get_ticks_usec()
		var accumulator := 0.0
		var ring := PackedFloat64Array()
		ring.resize(256)
		for i in 60000:
			var x := float(i % 251) * 0.37
			accumulator += sqrt(x + 1.0) * 0.5
			ring[i & 255] = accumulator
		script_best = minf(script_best, float(Time.get_ticks_usec() - began))
		_probe_sink += ring[17]
	var source := PackedFloat64Array()
	source.resize(100000)
	var state := 12345
	for i in source.size():
		state = (state * 1103515245 + 12345) & 0x7fffffff
		source[i] = float(state)
	var native_best := INF
	for _repeat in 3:
		var data := source.duplicate()
		var began := Time.get_ticks_usec()
		data.sort()
		native_best = minf(native_best, float(Time.get_ticks_usec() - began))
		_probe_sink += data[50000]
	return {"script_usec": script_best, "native_sort_usec": native_best, "script_iterations": 60000,
		"sort_elements": source.size(), "repeats": {"script": 5, "native": 3}, "unix": Time.get_unix_time_from_system()}

func _pipeline_compilations() -> Dictionary:
	var result := {}
	for monitor in PIPELINE_MONITORS:
		if ClassDB.class_has_integer_constant("Performance", monitor):
			result[monitor.to_lower()] = Performance.get_monitor(ClassDB.class_get_integer_constant("Performance", monitor))
	return result

func _pipeline_total() -> float:
	var sum := 0.0
	for value in _pipeline_compilations().values():
		sum += float(value)
	return sum

func _engine_counters() -> Dictionary:
	return {
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"orphan_nodes": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"static_memory_bytes": float(OS.get_static_memory_usage()),
		"static_memory_peak_bytes": float(OS.get_static_memory_peak_usage()),
		"video_memory_bytes": float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)),
		"texture_memory_bytes": float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)),
		"buffer_memory_bytes": float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED)),
		"physics_3d_active_objects": Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
		"physics_3d_collision_pairs": Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),
		"physics_3d_islands": Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT),
		"frames_drawn": float(Engine.get_frames_drawn()),
		"pipeline_compilations": _pipeline_compilations(),
	}

func _numeric_delta(before: Dictionary, after: Dictionary) -> Dictionary:
	var result := {}
	for key in after:
		if before.get(key) is Dictionary and after[key] is Dictionary:
			result[key] = _numeric_delta(before[key], after[key])
		elif (after[key] is float or after[key] is int) and (before.get(key) is float or before.get(key) is int):
			result[key] = float(after[key]) - float(before[key])
	return result

func _engine_info() -> Dictionary:
	var info := {
		"version": Engine.get_version_info(), "debug_build": OS.is_debug_build(),
		"physics_ticks_per_second": Engine.physics_ticks_per_second,
		"max_physics_steps_per_frame": Engine.max_physics_steps_per_frame,
		"physics_jitter_fix": Engine.physics_jitter_fix, "max_fps": Engine.max_fps,
		"vsync_mode": DisplayServer.window_get_vsync_mode(), "display_server": DisplayServer.get_name(),
		"thread_model": ProjectSettings.get_setting("rendering/driver/threads/thread_model", "default"),
		"physics_engine_3d": ProjectSettings.get_setting("physics/3d/physics_engine", "default"),
		"physics_interpolation": ProjectSettings.get_setting("physics/common/physics_interpolation", false),
	}
	# Called dynamically: availability differs between engine minor versions.
	for method in ["get_current_rendering_method", "get_current_rendering_driver_name"]:
		if RenderingServer.has_method(method):
			info[method.trim_prefix("get_current_")] = RenderingServer.call(method)
	return info

func _host_info() -> Dictionary:
	var info := {"os": OS.get_name(), "os_version": OS.get_version(), "processor": OS.get_processor_name(),
		"logical_processors": OS.get_processor_count(), "adapter": RenderingServer.get_video_adapter_name(),
		"adapter_vendor": RenderingServer.get_video_adapter_vendor(),
		"adapter_api": RenderingServer.get_video_adapter_api_version()}
	if OS.has_method("get_video_adapter_driver_info"):
		info["adapter_driver"] = OS.call("get_video_adapter_driver_info")
	return info

func _view_state() -> Dictionary:
	var player: Node = _node(level, "player")
	var window := get_tree().root
	return {"viewport_3d_scale": get_viewport().scaling_3d_scale, "window_3d_scale": window.scaling_3d_scale,
		"camera_fov": _read(player, "camera_fov", -1.0), "max_fps": Engine.max_fps,
		"vsync_mode": DisplayServer.window_get_vsync_mode(), "window_focused": window.has_focus(),
		"window_mode": DisplayServer.window_get_mode(), "window_position": [DisplayServer.window_get_position().x, DisplayServer.window_get_position().y]}

## The level applies the active profile's render scale/FOV to its own viewport,
## which is the private SubViewport here. Benchmarks pin the defaults instead;
## nothing is saved, and the profile values are reported for reference.
func _pin_view(args: PackedStringArray) -> Dictionary:
	var profile := {}
	var settings: Variant = _read(level, "_settings")
	var values: Variant = _read(settings, "values")
	if values is Dictionary:
		profile = (values as Dictionary).duplicate()
	get_viewport().scaling_3d_scale = 1.0
	var player: Node = _node(level, "player")
	var fov_pinned := not args.has("--profile-fov") and player != null and player.get("camera_fov") != null
	if fov_pinned:
		player.set("camera_fov", pinned_fov)
		if player.has_method("update_camera"):
			player.call("update_camera")
	return {"profile_settings": profile, "pinned_3d_scale": 1.0, "pinned_fov": pinned_fov if fov_pinned else null,
		"music_enabled_by_profile": float(profile.get("music", 0.0)) > 0.0}

func _on_physics_frame() -> void:
	timeline.physics_frame(Time.get_ticks_usec())

func _on_pre_draw() -> void:
	timeline.draw_begin(Time.get_ticks_usec())

func _on_post_draw() -> void:
	timeline.draw_end(Time.get_ticks_usec())

func _add_marks() -> void:
	for last in [false, true]:
		var process_mark := ProcessMark.new()
		process_mark.name = "BenchmarkProcessLast" if last else "BenchmarkProcessFirst"
		process_mark.timeline = timeline
		process_mark.last = last
		process_mark.process_priority = LAST_PRIORITY if last else FIRST_PRIORITY
		process_mark.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(process_mark)
		_marks.append(process_mark)
		var physics_mark := PhysicsMark.new()
		physics_mark.name = "BenchmarkPhysicsLast" if last else "BenchmarkPhysicsFirst"
		physics_mark.timeline = timeline
		physics_mark.last = last
		physics_mark.process_physics_priority = LAST_PRIORITY if last else FIRST_PRIORITY
		physics_mark.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(physics_mark)
		_marks.append(physics_mark)

func _remove_marks() -> void:
	for mark in _marks:
		if is_instance_valid(mark):
			mark.queue_free()
	_marks.clear()

func _write_traces(columns: Dictionary, physics_columns: Dictionary) -> Dictionary:
	var written := {}
	var file := FileAccess.open(output.path_join("frames.csv"), FileAccess.WRITE)
	if file != null:
		var names: Array = ["index"] + columns.keys()
		file.store_line(",".join(PackedStringArray(names)))
		var rows: int = timeline.cycles()
		for i in rows:
			var cells := PackedStringArray([str(i)])
			for key in columns:
				var values: Variant = columns[key]
				cells.append(String.num(float(values[i]), 4) if i < values.size() else "")
			file.store_line(",".join(cells))
		file.close()
		written["frames"] = "frames.csv"
	file = FileAccess.open(output.path_join("ticks.csv"), FileAccess.WRITE)
	if file != null:
		var names: Array = ["tick", "cycle", "pre_ms", "scripts_ms", "engine_ms"] + physics_columns.keys()
		file.store_line(",".join(PackedStringArray(names)))
		for i in timeline.tick_scripts_ms.size():
			var cells := PackedStringArray([str(i), str(timeline.tick_cycle[i]), String.num(timeline.tick_pre_ms[i], 4),
				String.num(timeline.tick_scripts_ms[i], 4), String.num(timeline.tick_engine_ms[i], 4)])
			for key in physics_columns:
				var values: Variant = physics_columns[key]
				cells.append(String.num(float(values[i]), 4) if i < values.size() else "")
			file.store_line(",".join(cells))
		file.close()
		written["ticks"] = "ticks.csv"
	return written

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_fail("Run graphically: headless timings do not measure rendered play")
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var started := Time.get_ticks_msec()
	# Hidden Windows swapchains can lose their Vulkan device while the loading
	# screen submits UI-only frames. The same private target used by visual QA
	# avoids depending on an occluded presentation surface for benchmark rendering.
	var private_target := "--private-viewport" in OS.get_cmdline_user_args()
	if private_target:
		var target := SubViewport.new()
		target.name = "PrivateBenchmarkTarget"
		target.size = render_size
		# Match the playable window, including its project's 4x MSAA. SubViewports
		# default to no AA; that would make their timing deceptively cheaper.
		var window_view := get_tree().root
		target.msaa_3d = window_view.msaa_3d
		target.screen_space_aa = window_view.screen_space_aa
		target.use_taa = window_view.use_taa
		target.use_debanding = window_view.use_debanding
		target.mesh_lod_threshold = window_view.mesh_lod_threshold
		target.scaling_3d_mode = window_view.scaling_3d_mode
		target.scaling_3d_scale = 1.0
		target.own_world_3d = true
		target.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		get_tree().root.add_child(target)
		reparent(target)
		var scene = load("res://scenes/city/pen_lucy.tscn")
		if not scene is PackedScene:
			_fail("Neighborhood scene could not load")
			return
		level = scene.instantiate()
		target.add_child(level)
	else:
		if get_tree().change_scene_to_file("res://scenes/city/pen_lucy.tscn") != OK:
			_fail("Neighborhood scene could not load")
			return
		await frames(5)
		level = get_tree().current_scene
	if level == null or level.get("level_ready") == null:
		_fail("Neighborhood initialization failed")
		return
	for i in 600:
		if level.level_ready:
			break
		await frames(1)
	if not level.level_ready:
		_fail("Neighborhood did not initialize within 600 rendered frames")
		return
	var startup_ms := Time.get_ticks_msec() - started
	var args := OS.get_cmdline_user_args()
	var quality := "balanced"
	var quality_index := args.find("--render-quality")
	if quality_index >= 0 and quality_index + 1 < args.size():
		quality = args[quality_index + 1]
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var window := get_tree().root
	# Fix the render target itself, not just the OS window. The project's default
	# 1600x900 canvas stretch and display scaling can make these sizes differ.
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	window.content_scale_size = render_size
	window.content_scale_factor = 1.0
	window.size = render_size
	window.scaling_3d_scale = 1.0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = fps_cap
	if level.render_optimizer != null:
		level.render_optimizer.set_quality(quality)
	level.spawn_player()
	level.resume_exploring()
	if args.has("--mission-route"):
		if not level.missions.start_case("missing_tools"):
			_fail("Requested mission-route workload could not start")
			return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	level.residents.set_routines_enabled(not args.has("--no-resident-routines"))
	var view_pin := _pin_view(args)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	# Startup shader compilation is outside the sample; the world remains active.
	await frames(WARMUP_FRAMES)
	# Daily corridor generation belongs to startup, never the steady-state sample.
	for i in 240:
		if level.residents._build_queue.is_empty():
			break
		await get_tree().physics_frame
	if not level.residents._build_queue.is_empty():
		_fail("Daily resident routes did not finish before profiling")
		return
	await RenderingServer.frame_post_draw
	var verified_render_size := get_viewport().get_texture().get_image().get_size()
	if verified_render_size != render_size or not is_equal_approx(window.scaling_3d_scale, 1.0) or not is_equal_approx(get_viewport().scaling_3d_scale, 1.0):
		_fail("Render target mismatch: requested %s, actual image %s, window %s, 3D scale %s/%s" % [render_size, verified_render_size, window.size, window.scaling_3d_scale, get_viewport().scaling_3d_scale])
		return
	for point in level.level_data.get("route", {}).get("points", []):
		_route.append(level.vector(point))
	if _route.size() < 2:
		_fail("A walk route is required")
		return
	if start_route_index < 0 or start_route_index >= _route.size() - 1:
		_fail("Start route index is outside the walking route")
		return
	if start_route_index > 0:
		var toward: Vector3 = _route[start_route_index + 1] - _route[start_route_index]
		level._place_player(_route[start_route_index], atan2(toward.x, toward.z))
		_waypoint = start_route_index + 1
		level.streaming.refresh_now()
		for i in 900:
			if level.streaming.get_status().near_cells_missing == 0:
				break
			await frames(1)
		await frames(WARMUP_FRAMES)
	_configure_render_diagnostic(args)
	if args.has("--diagnostic-hide-world"):
		level.player.camera.cull_mask = 0
	load("res://scripts/city/city_vehicle.gd").use_route_distance_cache = not args.has("--uncached-route-distances")
	load("res://scripts/city/city_crowd.gd").use_staggered_idle = not args.has("--synchronized-crowd-idle")
	# Setup remnants: an outstanding threaded cell load or missing near cell would
	# otherwise land in the first sampled frames. Bounded; reported, not fatal.
	var quiescence_frames := 0
	var streaming: Node = _node(level, "streaming")
	for i in 300:
		var stream_status := _status(streaming)
		var pending: Variant = _read(streaming, "_pending", "")
		if int(stream_status.get("near_cells_missing", 0)) == 0 and str(pending).is_empty():
			break
		quiescence_frames += 1
		await frames(1)
	var probe_before := {} if args.has("--no-cpu-probe") else _cpu_probe()
	await _save_image("walk_start.png")
	# Readback/PNG encoding and the probe contaminate Godot's rolling CPU
	# monitors. Let that reporting window expire before any measurements.
	await get_tree().create_timer(1.3).timeout
	var counters: Variant = load(COUNTERS_PATH) if ResourceLoader.exists(COUNTERS_PATH) else null
	var counters_enabled := counters != null and args.has("--perf-counters")
	var gpu_ms: Array[float] = []
	var render_cpu_ms: Array[float] = []
	var setup_cpu_ms: Array[float] = []
	var slow_frames: Array[Dictionary] = []
	var timings: Array[float] = []
	var draw_calls: Array[float] = []
	var objects_in_frame: Array[float] = []
	var primitives_in_frame: Array[float] = []
	var physics_cost: Array[float] = []
	var process_cost: Array[float] = []
	var physics_frame_times: Array[float] = []
	var render_only_frame_times: Array[float] = []
	var any_paused := false
	_walking = true
	Input.action_press("move_forward")
	if lead_in_seconds > 0:
		await get_tree().create_timer(float(lead_in_seconds)).timeout
	timeline = Timeline.new()
	_add_marks()
	get_tree().physics_frame.connect(_on_physics_frame)
	RenderingServer.frame_pre_draw.connect(_on_pre_draw)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	# Align the first sampled cycle to a process_frame boundary; the marks have
	# then entered the process lists.
	await get_tree().process_frame
	var before: Vector3 = level.player.global_position
	var distance_before: float = level.player.distance_walked
	var npc_before: float = level.npcs._elapsed
	var car_distance_before := 0.0
	for car in level.traffic.vehicles:
		car_distance_before += car.distance_travelled
	var event_before := _event_counters()
	var engine_before := _engine_counters()
	var view_before := _view_state()
	var world_clock_before := _status(_node(level, "world_time"))
	_progress_position = before
	_progress_elapsed = 0.0
	_stalled_seconds = 0.0
	_stalled_windows = 0
	if args.has("--profile-city"):
		level.residents._max_tick_usec = 0
		level.residents._near_updates = 0
		level.residents._far_updates = 0
		for samples in level.physics_samples.values():
			samples.clear()
		level.profile_physics = true
		level.player.profile_costs = true
		level.player.profile_samples.clear()
		level.process_samples.clear()
		var vehicle_script = load("res://scripts/city/city_vehicle.gd")
		vehicle_script.profile_totals.clear()
		vehicle_script.profile_queries = args.has("--profile-vehicle")
		var crowd_script = load("res://scripts/city/city_crowd.gd")
		crowd_script.profile_totals.clear()
		crowd_script.profile_idle = args.has("--profile-vehicle")
	if counters_enabled:
		counters.reset()
		counters.enabled = true
	# One line each, so a log reader can count engine output inside the window.
	print("[city_life_benchmark] SAMPLE_BEGIN unix=%.3f" % Time.get_unix_time_from_system())
	var sample_unix_start := Time.get_unix_time_from_system()
	var physics_start := Engine.get_physics_frames()
	var previous_physics := physics_start
	var began := Time.get_ticks_usec()
	var previous := began
	timeline.start(began)
	timeline.driver_done(Time.get_ticks_usec())
	while Time.get_ticks_usec() - began < int(sample_seconds * 1000000.0):
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		timeline.process_frame(now)
		timings.append(float(now - previous) / 1000.0)
		var current_physics := Engine.get_physics_frames()
		if current_physics > previous_physics:
			physics_frame_times.append(timings.back())
		else:
			render_only_frame_times.append(timings.back())
		previous_physics = current_physics
		gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
		render_cpu_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()))
		setup_cpu_ms.append(RenderingServer.get_frame_setup_time_cpu())
		var event_after := _event_counters()
		var events := {}
		for key in event_after:
			if event_after[key] != event_before.get(key):
				events[key] = event_after[key] - event_before.get(key, 0)
		event_before = event_after
		if timings.back() > 20.0 or not events.is_empty():
			slow_frames.append({"elapsed_ms": float(now - began) / 1000.0, "frame_ms": timings.back(), "gpu_ms": gpu_ms.back(), "render_cpu_ms": render_cpu_ms.back(), "events": events})
		previous = now
		draw_calls.append(float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)))
		objects_in_frame.append(float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)))
		primitives_in_frame.append(float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)))
		physics_cost.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		process_cost.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		any_paused = any_paused or bool(level.paused)
		timeline.driver_done(Time.get_ticks_usec())
	timeline.stop()
	var sample_unix_end := Time.get_unix_time_from_system()
	print("[city_life_benchmark] SAMPLE_END unix=%.3f" % sample_unix_end)
	if counters_enabled:
		counters.enabled = false
	get_tree().physics_frame.disconnect(_on_physics_frame)
	RenderingServer.frame_pre_draw.disconnect(_on_pre_draw)
	RenderingServer.frame_post_draw.disconnect(_on_post_draw)
	_remove_marks()
	Input.action_release("move_forward")
	_walking = false
	level.profile_physics = false
	level.player.profile_costs = false
	load("res://scripts/city/city_vehicle.gd").profile_queries = false
	load("res://scripts/city/city_crowd.gd").profile_idle = false
	var engine_after := _engine_counters()
	var view_after := _view_state()
	var world_clock_after := _status(_node(level, "world_time"))
	var probe_after := {} if args.has("--no-cpu-probe") else _cpu_probe()
	var duration := float(previous - began) / 1000000.0
	var component_cost := {}
	var component_budget := {}
	var physics_columns := {}
	for key in level.physics_samples:
		var samples := PackedFloat64Array(level.physics_samples[key])
		if not samples.is_empty():
			component_cost[key] = _distribution(samples)
			component_budget[key] = Stats.per_second(samples, duration)
			physics_columns[str(key) + "_ms"] = samples
	var physics_frames := Engine.get_physics_frames() - physics_start
	var distance: float = level.player.distance_walked - distance_before
	var frame_ms := _distribution(timings)
	var car_distance := -car_distance_before
	for car in level.traffic.vehicles:
		car_distance += car.distance_travelled
	var npc_status: Dictionary = level.npcs.get_status()
	var valid: bool = not any_paused and distance >= sample_seconds * 1.5 and level.npcs._elapsed - npc_before > sample_seconds * 0.8 and car_distance > 1.0 and _stalled_seconds <= 1.0
	var window_size := DisplayServer.window_get_size()
	var texture_size := get_viewport().get_texture().get_size()
	var image_size := get_viewport().get_texture().get_image().get_size()
	var viewport_size := get_viewport().get_visible_rect().size
	valid = valid and image_size == render_size and is_equal_approx(window.scaling_3d_scale, 1.0) and is_equal_approx(get_viewport().scaling_3d_scale, 1.0)
	# Phase timeline: per-cycle distributions and ms per wall second.
	var timeline_columns := {}
	for key in Timeline.COLUMNS:
		timeline_columns[key] = timeline.column(key)
	var work := PackedFloat64Array()
	var render_only_cycles := PackedFloat64Array()
	var physics_cycles := PackedFloat64Array()
	for i in timeline.cycles():
		var cycle: float = timeline.cycle_ms[i]
		work.append(cycle - timeline.tail_ms[i])
		if timeline.physics_ticks[i] > 0.0:
			physics_cycles.append(cycle)
		else:
			render_only_cycles.append(cycle)
	var trace_columns := timeline_columns.duplicate()
	trace_columns["work_ms"] = work
	trace_columns["viewport_render_cpu_ms"] = render_cpu_ms
	trace_columns["viewport_gpu_ms"] = gpu_ms
	trace_columns["draw_calls"] = draw_calls
	trace_columns["objects"] = objects_in_frame
	trace_columns["primitives"] = primitives_in_frame
	var traces := {} if args.has("--no-frame-trace") else _write_traces(trace_columns, physics_columns)
	var engine_delta := _numeric_delta(engine_before, engine_after)
	var pipeline_classes: Dictionary = engine_delta.get("pipeline_compilations", {})
	var pipeline_delta := 0.0
	for value in pipeline_classes.values():
		pipeline_delta += float(value)
	# Godot compiles optimized Specialization pipelines asynchronously during play.
	# Keep every class as workload evidence; only on-draw Canvas/Draw compilation
	# is a blocking-compilation exclusion. Mesh/Surface loading stays in the trace.
	# https://docs.godotengine.org/en/stable/tutorials/performance/pipeline_compilations.html
	var pipeline_blocking := float(pipeline_classes.get("pipeline_compilations_canvas", 0.0)) + float(pipeline_classes.get("pipeline_compilations_draw", 0.0))
	var pipeline_async := float(pipeline_classes.get("pipeline_compilations_specialization", 0.0))
	var unattributed_total := Stats.total(timeline.unattributed_ms)
	var issues: Array[String] = []
	if pipeline_blocking > 0.0:
		issues.append("blocking canvas/draw pipeline compilations during sample: %d" % roundi(pipeline_blocking))
	if timeline.anomalies > maxi(2, floori(timeline.cycles() / 100.0)):
		issues.append("timeline ordering anomalies: %d" % timeline.anomalies)
	if absf(unattributed_total) > 0.01 * Stats.total(timeline.cycle_ms):
		issues.append("unattributed timeline time %.1f ms" % unattributed_total)
	if not is_equal_approx(float(view_after.viewport_3d_scale), 1.0):
		issues.append("3D viewport scale changed to %s" % view_after.viewport_3d_scale)
	if view_pin.pinned_fov != null and not is_equal_approx(float(view_after.camera_fov), pinned_fov):
		issues.append("camera FOV changed to %s" % view_after.camera_fov)
	if quiescence_frames >= 300:
		issues.append("streaming did not become idle before the sample")
	if int(engine_delta.get("frames_drawn", timeline.cycles())) < timeline.cycles():
		issues.append("only %d of %d cycles drew a frame" % [int(engine_delta.get("frames_drawn", 0)), timeline.cycles()])
	var counter_snapshot: Dictionary = counters.snapshot() if counters_enabled else {}
	var counter_rates := {}
	for key in counter_snapshot:
		var entry: Dictionary = counter_snapshot[key]
		counter_rates[key] = {"calls_per_second": float(entry.get("count", 0)) / maxf(duration, 0.001),
			"ms_per_second": float(entry.get("usec", 0)) / 1000.0 / maxf(duration, 0.001)}
	var report := {
		"schema": SCHEMA,
		"driver_sha256": FileAccess.get_sha256(get_script().resource_path),
		"helper_sha256": {"stats": FileAccess.get_sha256("res://tools/city_perf_stats.gd"), "timeline": FileAccess.get_sha256("res://tools/city_perf_timeline.gd")},
		"engine": _engine_info(), "host": _host_info(),
		"view_pin": view_pin, "view_state_start": view_before, "view_state_end": view_after,
		"cpu_probe": {"before": probe_before, "after": probe_after},
		"timeline_ms": Stats.summarize_columns(timeline_columns, duration),
		"timeline_cycles": timeline.cycles(), "timeline_anomalies": timeline.anomalies,
		"timeline_ticks_ms": Stats.summarize_columns({"pre_ms": timeline.tick_pre_ms, "scripts_ms": timeline.tick_scripts_ms, "engine_ms": timeline.tick_engine_ms}, duration),
		"work_ms": Stats.distribution(work), "render_only_cycle_ms": Stats.distribution(render_only_cycles), "physics_cycle_ms": Stats.distribution(physics_cycles),
		"mean_frame_ms": Stats.total(timings) / maxf(timings.size(), 1),
		"time_weighted_frame_ms": {"p50": Stats.time_weighted_percentile(timings, 0.5), "p90": Stats.time_weighted_percentile(timings, 0.9),
			"p95": Stats.time_weighted_percentile(timings, 0.95), "p99": Stats.time_weighted_percentile(timings, 0.99)},
		"hitches": {"over_2x_median": Stats.count_over(timings, 2.0 * float(frame_ms.get("median", 0.0))), "over_16_7ms": Stats.count_over(timings, 16.667), "over_33_3ms": Stats.count_over(timings, 33.333)},
		"physics_components_ms_per_second": component_budget,
		"level_ui_ms_per_second": Stats.per_second(level.process_samples, duration),
		"player_physics_ms_per_second": Stats.per_second(level.player.profile_samples, duration),
		"engine_counters_start": engine_before, "engine_counters_end": engine_after, "engine_counters_delta": engine_delta,
		"pipeline_compilations_during_sample": pipeline_delta,
		"pipeline_compilation_policy": "canvas_draw_blocking_v1",
		"pipeline_blocking_compilations_during_sample": pipeline_blocking,
		"pipeline_async_specializations_during_sample": pipeline_async,
		"perf_counters_available": counters != null, "perf_counters_enabled": counters_enabled,
		"perf_counters": counter_snapshot, "perf_counter_rates": counter_rates,
		"world_clock_start": world_clock_before, "world_clock_end": world_clock_after,
		"quiescence_wait_frames": quiescence_frames, "lead_in_seconds": lead_in_seconds,
		"traces": traces,
		"measurement_issues": issues,
		"residents": level.residents.get_status(),
		"world_time": level.world_time.get_status(),
		"day_night": level.day_night.get_status() if level.day_night != null else {},
		"viewport_gpu_ms": _distribution(gpu_ms),
		"viewport_render_cpu_ms": _distribution(render_cpu_ms),
		"render_frame_setup_cpu_ms": _distribution(setup_cpu_ms),
		"objects_in_frame": _distribution(objects_in_frame),
		"primitives_in_frame": _distribution(primitives_in_frame),
		"slow_or_event_frames": slow_frames,
		"render_optimizer": level.render_optimizer.get_stats(),
		"weathering": level.weathering_report,
		"sample_unix_start": sample_unix_start,
		"sample_unix_end": sample_unix_end,
		"frames_with_physics_ms": _distribution(physics_frame_times),
		"frames_without_physics_ms": _distribution(render_only_frame_times),
		"diagnostic_hide_group": _hidden_group,
		"moving_vehicle_render_lod": level.traffic.get_node("MovingVehicleRenderLOD").get_status() if level.traffic.has_node("MovingVehicleRenderLOD") else {},
		"npc_render_lod_enabled": not args.has("--no-npc-render-lod"),
		"civic_palette_enabled": not args.has("--no-civic-palette"),
		"render_inventory_all_loaded_surfaces_not_draw_calls": _render_inventory,
		"diagnostic_hide_world": args.has("--diagnostic-hide-world"),
		"diagnostic_no_sandbox_logic": args.has("--diagnostic-no-sandbox-logic"),
		"route_distance_cache": not args.has("--uncached-route-distances"),
		"vehicle_query_profiling": args.has("--profile-city") and args.has("--profile-vehicle"),
		"physics_components_ms": component_cost,
		"player_physics_ms": _distribution(level.player.profile_samples),
		"level_ui_ms": _distribution(level.process_samples),
		"vehicle_queries": load("res://scripts/city/city_vehicle.gd").profile_totals.duplicate(),
		"crowd_idle": load("res://scripts/city/city_crowd.gd").profile_totals.duplicate(),
		"staggered_crowd_idle": not args.has("--synchronized-crowd-idle"),
		"mission_route_active": args.has("--mission-route"),
		"mission_route_builds": _read(_node(level, "mission_navigation"), "route_build_count", 0),
		"mission_route_points": _size(_read(_node(level, "mission_navigation"), "route", [])),
		"offscreen_validation": level.offscreen_validation,
		"private_viewport": private_target,
		"viewport_msaa_3d": get_viewport().msaa_3d,
		"viewport_screen_space_aa": get_viewport().screen_space_aa,
		"viewport_taa": get_viewport().use_taa,
		"map_static_draw_builds": _read(_read(_read(_node(level, "_radar"), "map"), "geography"), "build_count", 0),
		"map_live_redraws": _read(_read(_node(level, "_radar"), "map"), "redraw_count", 0),
		"valid_active_play": valid, "startup_ms": startup_ms, "quality": quality,
		"requested_resolution": [render_size.x, render_size.y], "resolution": [image_size.x, image_size.y],
		"texture_size": [texture_size.x, texture_size.y], "render_scale": window.scaling_3d_scale,
		"viewport_3d_scale": get_viewport().scaling_3d_scale,
		"content_scale_mode": window.content_scale_mode, "content_scale_factor": window.content_scale_factor,
		"window_size": [window_size.x, window_size.y], "viewport_size": [viewport_size.x, viewport_size.y],
		"vsync": false, "fps_cap": fps_cap, "warmup_frames": WARMUP_FRAMES,
		"sample_seconds": duration, "rendered_frames": timings.size(), "physics_frames": physics_frames,
		"delivered_fps": timings.size() / maxf(duration, 0.001), "physics_fps": physics_frames / maxf(duration, 0.001),
		"frame_ms": frame_ms, "median_fps": 1000.0 / maxf(float(frame_ms.median), 0.001),
		"p95_frame_equivalent_fps": 1000.0 / maxf(float(frame_ms.p95), 0.001),
		"worst_frame_equivalent_fps": 1000.0 / maxf(float(frame_ms.max), 0.001),
		"draw_calls": _distribution(draw_calls), "physics_cpu_ms": _distribution(physics_cost), "process_cpu_ms": _distribution(process_cost),
		"player_distance_m": distance, "player_start": [before.x, before.y, before.z],
		"elapsed_stalled_seconds": _stalled_seconds, "stalled_half_second_windows": _stalled_windows,
		"minimum_distance_m": sample_seconds * 1.5, "maximum_allowed_stall_seconds": 1.0,
		"player_end": [level.player.global_position.x, level.player.global_position.y, level.player.global_position.z],
		"route_waypoint_start": start_route_index, "route_waypoint_reached": _waypoint, "paused_during_sample": any_paused,
		"npc_simulated_seconds": level.npcs._elapsed - npc_before, "npc_count": npc_status.count,
		"streaming": level.streaming.get_status() if level.streaming != null else {},
		"neighborhood_details": level.neighborhood_details.get_status() if level.neighborhood_details != null else {},
		"vegetation": level.vegetation.get_stats() if level.vegetation != null else {},
		"parked_cars": level.traffic.parked.get_status() if level.traffic.parked != null else {},
		"yard_details": level.yard_details.get_status() if level.yard_details != null else {},
		"park_courts": level.park_courts.get_status() if level.park_courts != null else {},
		"power_grid": level.power_grid.get_status() if level.power_grid != null else {},
		"crowd": npc_status.crowd, "cars": level.traffic.vehicles.size(), "traffic_distance_m": car_distance,
		"optimization_disabled": args.has("--no-city-optimization"),
		"static_memory_bytes": Performance.get_monitor(Performance.MEMORY_STATIC),
		"video_memory_bytes": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED),
		"notes": "Wall-clock frames during actual forward input; active collision, normal chase camera, HUD, NPCs and traffic. Half-second movement windows detect stalls; more than one cumulative stalled second invalidates play. physics_cpu_ms/process_cpu_ms are Godot's per-second MAXIMUM step times (Performance.TIME_*), sampled per frame; use timeline_ms (per-cycle phases from bracketing nodes and signals) and *_per_second budgets for costs. Timeline phases: driver bookkeeping, process pre (timers/tweens/deferred), _process scripts, process post (deletes, navigation, render sync), render (pre_draw..post_draw incl. present), tail (frame end, audio, frame delay, next physics sync/flush), physics pre/scripts/engine (engine = timers, deferred calls, transform flush, navigation, PhysicsServer step). Direct viewport GPU/render CPU and global render setup timings are milliseconds; GPU results can lag. Screenshot writes, CPU probes plus 1.3s cooldown excluded. Slow/event frame counters indicate correlation, not causation."
	}
	var file := FileAccess.open(output.path_join("metrics.json"), FileAccess.WRITE)
	if file == null:
		_fail("Could not write metrics.json")
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	await _save_image("walk_end.png")
	print("[city_life_benchmark] " + JSON.stringify(report))
	get_tree().quit(0 if valid else 1)

func _event_counters() -> Dictionary:
	return {
		"vegetation_builds": _read(_node(level, "vegetation"), "_cell_mesh_builds", 0),
		"building_loads": _read(_node(level, "streaming"), "_loads", 0),
		"yard_loads": _read(_node(level, "yard_details"), "_async_loads", 0),
		"crowd_activations": _read(_read(_node(level, "npcs"), "crowd"), "_cell_activations", 0),
		"sky_updates": _read(_node(level, "day_night"), "_sky_updates", 0),
		"save_writes": _read(_node(level, "world_save"), "save_count", 0),
		"pipeline_compilations": _pipeline_total(),
	}
