extends Node
## Full-level integration capture into a private SubViewport, never the desktop.
var OUTPUT := "res://../artifacts/living-world/visual"
var viewport: SubViewport
var level: Node3D
var failures := 0
var captures: Array[String] = []

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var output_index := args.find("--capture-outdir")
	if output_index >= 0 and output_index + 1 < args.size():
		OUTPUT = args[output_index + 1]
	_run.call_deferred()

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func check(ok: bool, label: String) -> void:
	failures += int(not ok)
	print("[living_render] %s %s" % ["PASS" if ok else "FAIL", label])

func capture(filename: String) -> void:
	await frames(3)
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		check(false, filename + " has rendered pixels")
		return
	var path := ProjectSettings.globalize_path(OUTPUT.path_join(filename + ".png"))
	var result := image.save_png(path)
	check(result == OK, "capture " + path)
	if result == OK:
		captures.append(path)

func settle_streaming() -> void:
	level.streaming.refresh_now()
	for i in 360:
		await frames(1)
		if level.streaming.get_status().near_cells_missing == 0:
			break
	check(level.streaming.get_status().near_cells_missing == 0, "nearby geometry streamed within bound")

func _run() -> void:
	if not ("--offscreen-validation" in OS.get_cmdline_user_args() or "--offscreen-validation" in OS.get_cmdline_args()):
		check(false, "requires --offscreen-validation; refusing visible capture")
		get_tree().quit(1)
		return
	if DisplayServer.get_name() == "headless":
		check(false, "requires a real offscreen renderer, not headless dummy rendering")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	viewport = SubViewport.new()
	viewport.name = "PrivateLivingWorldCapture"
	viewport.size = Vector2i(1600, 900)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.scaling_3d_scale = 1.0
	add_child(viewport)
	var scene = load("res://scenes/city/pen_lucy.tscn")
	if not scene is PackedScene:
		check(false, "Pen Lucy scene loads")
		get_tree().quit(1)
		return
	level = scene.instantiate()
	viewport.add_child(level)
	for i in 1800:
		await frames(1)
		if level.level_ready:
			break
	check(level.level_ready, "full level initialized within 1800 frames")
	if not level.level_ready:
		get_tree().quit(1)
		return
	check(level.residents.actors.size() == 40, "forty daily residents instantiated")
	level.world_time.frozen = true
	level.world_time.set_time(540.0)
	level.resume_exploring()
	await frames(30)
	# A passive fall, without a jump flag, must stop behind the menu. The shared
	# clock's animation seconds also stop; checking frozen wall time alone is weak.
	var safe: Vector3 = level.player.global_position
	level.player.position.y += 0.8
	level.player._jump_active = false
	level.player.velocity = Vector3(0, -1, 0)
	level.pause_exploring()
	var suspended: Vector3 = level.player.global_position
	var clock_before: float = level.world_time.elapsed_seconds
	var minutes_before: float = level.world_time.total_minutes
	await frames(15)
	check(level.player.global_position == suspended and level.player.velocity.y == -1.0, "menu freezes a passive fall")
	check(level.world_time.elapsed_seconds == clock_before and level.world_time.total_minutes == minutes_before, "menu freezes shared simulation clock")
	level.resume_exploring()
	await frames(30)
	check(level.player.global_position.y < suspended.y - 0.1, "resuming releases the same fall")
	level._place_player(safe, level.player.yaw)

	# Choose an actual imported lamp nearest spawn, with a camera on the nearest
	# surveyed road. Identical framing makes day/dusk/night comparison meaningful.
	var lamp: Dictionary = {}
	var nearest := INF
	for candidate in level.day_night._anchors:
		var distance: float = candidate.position.distance_squared_to(safe)
		if distance < nearest:
			nearest = distance
			lamp = candidate
	check(not lamp.is_empty(), "authored streetlamp anchor available")
	if lamp.is_empty():
		get_tree().quit(1)
		return
	var base: Vector3 = lamp.position
	var road := street_camera(base)
	level._place_player(road.foot, 0.0)
	await settle_streaming()
	level.pause_exploring()
	level._ui.hide()
	level.player.first_person = true
	level.capture_view(road.eye, base + Vector3.UP * 2.4)
	for setting in [{"minutes": 540.0, "file": "01-day-0900"}, {"minutes": 1125.0, "file": "02-dusk-1845"}, {"minutes": 1320.0, "file": "03-night-2200"}]:
		level.world_time.set_time(setting.minutes)
		for i in 40:
			level.day_night.tick(0.05)
			await frames(1)
		var lights: Dictionary = level.day_night.get_status()
		check(lights.active_lights == 0 if setting.minutes == 540.0 else lights.active_lights > 0, "streetlamp state at " + str(setting.file))
		check(lights.active_lights <= lights.max_lights, "streetlamp pool remains bounded")
		await capture(setting.file)

	# Real third-person controller framing, with UI and both hands, not a detached
	# fake weapon portrait. No shot is fired at uninvolved resident contacts.
	level.world_time.set_time(540.0)
	level.player.camera_override.clear()
	level.player.first_person = false
	level._ui.show()
	level._place_player(road.foot, road.yaw)
	level.resume_exploring()
	level.player.camera_pitch = 0.05
	level.combat.equip("pistol")
	level.combat.aiming = true
	await frames(45)
	check(level.combat._gun.visible and level.combat._gun.get_parent() == level.player.puppet.hands[0], "equipped pistol remains attached to right hand")
	check(level.player.puppet.g.visible and not level.player.first_person, "third-person aiming retains visible body and hands")
	await capture("04-third-person-pistol-aim")

	# Inspect a real member of the forty-person roster at their current location.
	var resident: CharacterBody3D
	nearest = INF
	for actor in level.residents.actors.values():
		var distance: float = actor.global_position.distance_squared_to(level.player.global_position)
		if distance < nearest:
			nearest = distance
			resident = actor
	if resident != null:
		level.combat.equip("fists")
		var resident_view := street_camera(resident.global_position)
		level._place_player(resident_view.foot, resident_view.yaw)
		await settle_streaming()
		await frames(45)
		level.pause_exploring()
		level._ui.hide()
		level.player.first_person = true
		level.capture_view(resident_view.eye, resident.global_position + Vector3.UP)
		check(resident.enabled and resident.visible, "nearby daily resident physically active: " + resident.actor_id)
		await capture("05-daily-resident-hotspot")
	# Actual Rose Hill facade at close range: brick, painted trim and dusty glass.
	var facade: Dictionary = level.level_data.facade_details[0]
	var bay: Vector3 = level.vector(facade.position)
	var outward: Vector3 = level.vector(facade.normal).normalized()
	var facade_view := street_camera(bay)
	level._place_player(facade_view.foot, facade_view.yaw)
	await settle_streaming()
	await level.vegetation.prepare_presence(level.player.global_position, 55.0, 180.0)
	level.world_time.set_time(540.0)
	level.day_night.tick(0.5)
	level.vegetation.set_wind_time(0.0)
	level.capture_view(bay + outward * 7.0 - Vector3.UP * 0.8, bay - Vector3.UP * 0.8)
	await capture("06-rose-hill-finishes")
	level._ui.show()
	level.pause_exploring()
	await frames(3)
	check(level._settings.get_global_rect().encloses(level._settings._save_feedback.get_global_rect()), "save feedback fits the settings panel")
	await capture("07-save-settings")
	var report := {"captures": captures, "failures": failures, "viewport": [1600, 900], "lamp": lamp,
		"lighting": level.day_night.get_status(), "combat": level.combat.get_status(), "residents": level.residents.get_status()}
	var file := FileAccess.open(OUTPUT.path_join("integration-report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
	print("[living_render] captures=%d failures=%d" % [captures.size(), failures])
	get_tree().quit(0 if failures == 0 else 1)

func street_camera(point: Vector3) -> Dictionary:
	var nearest := INF
	var foot := point + Vector3(6, 0, 6)
	var along := Vector3.FORWARD
	for road in level.level_data.roads:
		var points: Array = road.points
		for i in range(1, points.size()):
			var a: Vector3 = level.vector(points[i - 1])
			var b: Vector3 = level.vector(points[i])
			var closest := Geometry2D.get_closest_point_to_segment(Vector2(point.x, point.z), Vector2(a.x, a.z), Vector2(b.x, b.z))
			var distance := closest.distance_squared_to(Vector2(point.x, point.z))
			if distance < nearest:
				nearest = distance
				foot = Vector3(closest.x, point.y, closest.y)
				along = Vector3(b.x - a.x, 0, b.z - a.z).normalized()
	var ground: Dictionary = level.ground_at(foot)
	if not ground.is_empty():
		foot = ground.position + Vector3.UP * 0.05
	var eye := foot + along * 8.0 + Vector3.UP * 3.3
	# Camera may survey the road, but leave the physical player on a checked
	# sidewalk so a passing car cannot spoil the equipped-hand comparison.
	var sidewalk: Dictionary = level.npcs.find_safe_position(point + along * 2.5, 0.35)
	if sidewalk.get("ok", false):
		foot = sidewalk.position
	return {"foot": foot, "eye": eye, "yaw": atan2(along.x, along.z)}
