extends "res://tests/city_living_world_render_runner.gd"
## Production scene/lighting/UI, rendered only into a private SubViewport.
## This fixture travels between viewpoints; it does not write checkpoints,
## purchase inventory, change lighting materials or manufacture shop scenery.
const CAPTURE_MINUTES := 600.0
var finished := false
var evidence: Array[Dictionary] = []

func _ready() -> void:
	OUTPUT = "res://../artifacts/sandbox-foundations/full-world"
	super._ready()
	_watchdog()

func _watchdog() -> void:
	await get_tree().create_timer(240.0, true, false, true).timeout
	if not finished:
		check(false, "full-world capture watchdog")
		get_tree().quit(1)

func key(code: int) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		viewport.push_input(event, true)
		await frames(2)

func click(button: Button) -> void:
	var at: Vector2 = button.get_global_transform_with_canvas() * (button.size * 0.5)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = at
		event.global_position = at
		event.pressed = pressed
		viewport.push_input(event, true)
		await frames(2)

func button_named(parent: Node, label: String) -> Button:
	if parent is Button and parent.text == label:
		return parent
	for child in parent.get_children():
		var found := button_named(child, label)
		if found != null:
			return found
	return null

func frame_world(foot: Vector3, eye: Vector3, target: Vector3) -> void:
	if level.shops.is_open():
		level.shops.close()
	level.pause_exploring()
	level.player.global_position = foot
	level.player.velocity = Vector3.ZERO
	level.player.reset_jump()
	level.player.first_person = true
	level.player.puppet.g.hide()
	level._ui.hide()
	level.shops.hint.hide()
	level.world_time.set_time(CAPTURE_MINUTES)
	level.day_night.tick(1.0)
	level.capture_view(eye, target)
	# Streaming uses camera_override.target, so establish the final camera before
	# asking for the cells, then settle asynchronous provider geometry as well.
	await settle_streaming()
	if level.vegetation != null:
		await level.vegetation.prepare_presence(target, 55.0, 180.0)
		level.vegetation.set_wind_time(0.0)
	await frames(12)

func record_view(label: String, interior := false) -> void:
	await capture(label)
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	var bright := 0
	var total := 0
	var luminance := 0.0
	# Coarse centre-region measurement diagnoses black/wall-clipped interiors.
	# Visual acceptance still belongs to the reviewer; this is not a beauty score.
	for y in range(180, 720, 5):
		for x in range(320, 1280, 5):
			var color := image.get_pixel(x, y)
			var luma := color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
			luminance += luma
			bright += int(luma > 0.15)
			total += 1
	var mean := luminance / maxi(1, total)
	var visible_ratio := float(bright) / maxi(1, total)
	if interior:
		check(mean > 0.07 and visible_ratio > 0.10, label + " has visible production-lit interior pixels")
	evidence.append({"capture": label, "eye": level.player.camera.global_position, "camera_override": level.player.camera_override.duplicate(),
		"clock_minutes": level.world_time.total_minutes, "streaming": level.streaming.get_status(),
		"centre_mean_luminance": mean, "centre_bright_ratio": visible_ratio})

func _run() -> void:
	if not "--offscreen-validation" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		check(false, "requires graphical private renderer with --offscreen-validation")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	viewport = SubViewport.new()
	viewport.name = "PrivateSandboxAcceptance"
	viewport.size = Vector2i(1600, 900)
	viewport.own_world_3d = true
	viewport.gui_embed_subwindows = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.scaling_3d_scale = 1.0
	add_child(viewport)
	level = load("res://scenes/city/pen_lucy.tscn").instantiate()
	viewport.add_child(level)
	for frame in 2400:
		await frames(1)
		if level.level_ready:
			break
	check(level.level_ready, "production level initialized")
	if not level.level_ready:
		get_tree().quit(1)
		return
	check(level.get("shops") != null and level.shops.models.size() == 5, "all five production shops built")
	check(level.get("progression") != null, "production shop economy integrated")
	check(not level.world_save.enabled, "capture does not write or restore user checkpoints")
	if level.get("shops") == null or level.get("progression") == null:
		get_tree().quit(1)
		return
	level.world_time.frozen = true
	level.world_time.set_time(CAPTURE_MINUTES)
	level.day_night.tick(1.0)
	# Exact Wilsby alley repair sample from the source surface audit.
	var alley := Vector3(275.63, -4.5, -162.8)
	var hit: Dictionary = level.ground_at(alley)
	check(not hit.is_empty(), "Wilsby repaired alley has production ground")
	if not hit.is_empty():
		alley.y = hit.position.y
	var street_foot := Vector3(261.9, alley.y, -162.8)
	var street_hit: Dictionary = level.ground_at(street_foot)
	if not street_hit.is_empty():
		street_foot = street_hit.position + Vector3.UP * 0.05
	await frame_world(street_foot, alley + Vector3(0, 2.1, -7.0), alley + Vector3(0, 0.35, 5.0))
	await record_view("01-wilsby-alley-eye-level")
	await frame_world(street_foot, alley + Vector3(-3.0, 25.0, -3.0), alley)
	await record_view("02-wilsby-alley-overview")
	# A narrow eastern gun shop and the cannabis store cover both stock types.
	var shot := 3
	for identity in ["east_wyanoke_arms", "wyanoke_green"]:
		var model: Node3D = level.shops.models[identity]
		var entry: Dictionary = level.shops._entry(identity)
		var front := float(entry.depth) * 0.5
		var approach: Vector3 = level.vector(entry.approach_start) + Vector3.UP * 0.05
		await frame_world(approach, model.to_global(Vector3(float(entry.width) * 0.6, 3.7, front + 8.5)), model.to_global(Vector3(0, 1.5, front)))
		await record_view("%02d-%s-exterior" % [shot, identity])
		shot += 1
		var counter: Vector3 = model.get_meta("counter_local")
		var eye := model.to_global(Vector3(0, 1.65, front - 0.75))
		var target := model.to_global(Vector3(0, 1.5, -float(entry.depth) * 0.22))
		await frame_world(model.to_global(counter) + Vector3.UP * 0.05, eye, target)
		await record_view("%02d-%s-interior" % [shot, identity], true)
		shot += 1
		# Open the real shop via E. The purchase panel is captured without buying
		# anything, changing starter money, granting inventory or invoking hooks.
		level._ui.show()
		level.resume_exploring()
		await key(KEY_E)
		check(level.shops.is_open() and level.paused and not level.player.enabled, identity + " actual E opens paused production purchase panel")
		await record_view("%02d-%s-stock-panel" % [shot, identity])
		shot += 1
		await key(KEY_ESCAPE)
		check(not level.shops.is_open() and not level.paused, "Escape returns from shop to exploration")
	# Actual full map and current case ledger, at the same 10:00 world time.
	level._ui.show()
	level.resume_exploring()
	await key(KEY_M)
	check(level._map_overlay.visible, "M opens production map")
	check(level.civic_district.map_pois.filter(func(poi): return str(poi.get("service", "")) in ["gun_store", "weed_store"]).size() == 5, "all shop POIs reach production map data")
	await record_view("09-full-map-shops")
	await key(KEY_M)
	await key(KEY_ESCAPE)
	var cases := button_named(level._settings, "Cases")
	check(cases != null, "production Cases ledger button exists")
	if cases != null:
		await click(cases)
		check(level._settings._cases != null and level._settings._cases.visible, "actual click opens embedded case ledger")
		await record_view("10-case-ledger")
	var report := {"failures": failures, "captures": captures, "views": evidence, "viewport": [1600, 900],
		"clock_minutes": CAPTURE_MINUTES, "lighting": level.day_night.get_status(), "shops": level.shops.get_status(),
		"progression": level.progression.get_status(), "scope": "Production Pen Lucy, real lights/shadows/materials, settled streaming, no checkpoint writes or purchases"}
	var file := FileAccess.open(OUTPUT.path_join("capture-report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	finished = true
	print("[sandbox_render] captures=%d failures=%d" % [captures.size(), failures])
	get_tree().quit(1 if failures else 0)
