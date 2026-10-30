extends Node3D
## A neighborhood chapter built on the georeferenced Pen Lucy model.
## Physics layers: 1 terrain, 2 buildings/props, 4 explorer, 8 neighbors, 16 vehicles.

const Explorer := preload("res://scripts/city/city_player.gd")
const SettingsPanel := preload("res://scripts/city/city_settings.gd")
const MapOverlay := preload("res://scripts/city/city_map_overlay.gd")
const DATA_PATH := "res://assets/data/pen_lucy_level.json"
const CITY_PATH := "res://assets/models/city/pen_lucy.glb"

var player: CharacterBody3D
var level_data: Dictionary = {}
var landmarks: Array = []
var visited: Dictionary = {}
var route_index := 0
var ready_to_play := false
var level_ready := false
var paused := true
var collision_meshes := 0
var dressing_report: Dictionary = {}
var npcs: Node3D
var traffic: Node3D
var missions: Node3D
var render_optimizer: Node
var streaming: Node
var vegetation: Node
var vegetation_report: Dictionary = {}
var neighborhood_details: Node3D
var weathering_report: Dictionary = {}
var _settings: Control
var _map_overlay: Control
var _radar: Control
var _fps: Label
var _fps_time := 0.0
var _ui_time := 0.0
var _case_marker: Node3D
var _markers: Array[Node3D] = []
var _old_g_mode: int
var _old_hud_mode: int
var _old_hud_visible := true
var _ui: CanvasLayer
var _location: Label
var _objective: Label
var _progress: Label
var _distance: Label
var _prompt: Label
var _notice: Label
var _notice_panel: Control
var _menu: Control
var _resume: Button
var _time := 0.0
var _notice_until := 0.0
var _last_ground_check := 0.0
var _safe_position := Vector3.ZERO
var _loading: CanvasLayer
var _loading_status: Label

func _ready() -> void:
	_old_g_mode = G.process_mode
	_old_hud_mode = Hud.process_mode
	_old_hud_visible = Hud.visible
	G.built = false
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_loading_screen()
	# Two process boundaries guarantee a visible loading frame before synchronous import work.
	await get_tree().process_frame
	await get_tree().process_frame
	_load_data()
	if landmarks.size() < 3:
		push_error("Pen Lucy needs its exported level data and at least three route stops: " + DATA_PATH)
		G.open_original_block()
		return
	_build_environment()
	_loading_status.text = "Loading the neighborhood model…"
	await get_tree().process_frame
	await get_tree().process_frame
	var resource = ResourceLoader.load(CITY_PATH, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	if not resource is PackedScene:
		push_error("Pen Lucy model could not be loaded: " + CITY_PATH)
		G.open_original_block()
		return
	var city: Node3D = resource.instantiate()
	resource = null
	city.name = "NeighborhoodGeometry"
	add_child(city)
	if FileAccess.file_exists("res://assets/data/pen_lucy_vegetation.json"):
		vegetation = load("res://scripts/city/city_vegetation.gd").new()
		add_child(vegetation)
		vegetation_report = vegetation.setup(self, city)
		vegetation.set_presence(vector(level_data.spawn.position), 55.0, 180.0)
	_loading_status.text = "Preparing solid streets, buildings and trees…"
	await get_tree().process_frame
	await get_tree().process_frame
	_add_mesh_collision(city)
	_build_bounds()
	_loading_status.text = "Setting out the neighborhood walk…"
	await get_tree().process_frame
	await get_tree().process_frame
	var dressing_path := "res://scripts/city/city_dressing.gd"
	if ResourceLoader.exists(dressing_path):
		var dressing = load(dressing_path)
		dressing_report = dressing.build(self, level_data)
	player = Explorer.new()
	player.name = "Explorer"
	add_child(player)
	_build_markers()
	_build_ui()
	# Let the physics server register the imported static meshes before footing rays.
	_loading_status.text = "Finding your footing at Old York & Wyanoke…"
	await get_tree().physics_frame
	spawn_player()
	var optimizer_path := "res://scripts/city/city_render_optimizer.gd"
	if ResourceLoader.exists(optimizer_path):
		render_optimizer = load(optimizer_path).new()
		add_child(render_optimizer)
		render_optimizer.setup(self, city)
	var weathering_path := "res://scripts/city/city_weathering.gd"
	if ResourceLoader.exists(weathering_path):
		weathering_report = load(weathering_path).apply_materials(city)
	_loading_status.text = "Opening up the lived-in blocks…"
	weathering_report.merge(load("res://scripts/city/city_windows.gd").new().build(self, city), true)
	_loading_status.text = "Welcoming the neighbors…"
	npcs = load("res://scripts/city/city_npcs.gd").new()
	npcs.name = "Neighbors"
	add_child(npcs)
	npcs.setup(self)
	await get_tree().physics_frame
	if ResourceLoader.exists(weathering_path):
		var weathering = load(weathering_path).new()
		weathering_report.merge(weathering.build_litter(self), true)
	_loading_status.text = "Opening shops and setting out street details…"
	neighborhood_details = load("res://scripts/city/city_neighborhood_details.gd").new()
	add_child(neighborhood_details)
	neighborhood_details.setup(self)
	await get_tree().physics_frame
	traffic = load("res://scripts/city/city_traffic.gd").new()
	traffic.name = "StreetTraffic"
	add_child(traffic)
	traffic.setup(self)
	missions = load("res://scripts/city/city_missions.gd").new()
	missions.name = "NeighborhoodCases"
	add_child(missions)
	missions.setup(self, npcs)
	missions.changed.connect(_cases_changed)
	missions.notice.connect(show_notice)
	_build_case_marker()
	_cases_changed()
	_loading_status.text = "Preparing nearby blocks and distant views…"
	streaming = load("res://scripts/city/city_streaming.gd").new()
	add_child(streaming)
	var detail_providers: Array[Node] = []
	if npcs.crowd != null:
		detail_providers.append(npcs.crowd)
	if vegetation != null:
		detail_providers.append(vegetation)
	if neighborhood_details != null:
		detail_providers.append(neighborhood_details)
	if traffic.parked != null:
		detail_providers.append(traffic.parked)
	streaming.setup(self, render_optimizer, detail_providers)
	ready_to_play = true
	level_ready = true
	_update_ui()
	_settings.apply_settings(true)
	_loading.queue_free()
	_loading = null
	if DisplayServer.get_name() == "headless" or get_window().has_focus():
		resume_exploring()
	else:
		pause_exploring()

func _build_loading_screen() -> void:
	_loading = CanvasLayer.new()
	_loading.layer = 30
	add_child(_loading)
	var background := ColorRect.new()
	background.color = Color("112c2e")
	_loading.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	_loading.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 20)
	center.add_child(content)
	_text(content, "TATTLETALE  /  BALTIMORE", 16, Color("e9be71"))
	_text(content, "Welcome to Pen Lucy", 38)
	_loading_status = _text(content, "Preparing your neighborhood walk…", 21, Color("c4d7ce"))
	_text(content, "Real streets, porch-front rows and a walk with 2-Pack.\nThe first visit can take a little longer while the neighborhood loads.", 17, Color("8eaaa2"))

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	G.process_mode = _old_g_mode
	Hud.process_mode = _old_hud_mode
	Hud.visible = _old_hud_visible

static func vector(value) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO

func _load_data() -> void:
	if FileAccess.file_exists(DATA_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if parsed is Dictionary:
			level_data = parsed
	landmarks = level_data.get("landmarks", [])
	var ordered: Array = []
	var route = level_data.get("route", [])
	if route is Dictionary:
		route = route.get("landmark_ids", route.get("landmarks", route.get("stops", [])))
	for id in route:
		for mark in landmarks:
			if str(mark.get("id", "")) == str(id):
				ordered.append(mark)
	if not ordered.is_empty():
		landmarks = ordered

func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var atmosphere := ProceduralSkyMaterial.new()
	atmosphere.sky_top_color = Color("719bac")
	atmosphere.sky_horizon_color = Color("d4d8c5")
	atmosphere.ground_horizon_color = Color("d4d8c5")
	atmosphere.ground_bottom_color = Color("696e64")
	sky.sky_material = atmosphere
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.65
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("c7d2c7")
	environment.fog_density = 0.00055
	environment.ssao_enabled = true
	environment.ssao_radius = 1.5
	environment.ssao_intensity = 1.3
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.name = "LateAfternoonSun"
	sun.rotation_degrees = Vector3(-43, -32, 0)
	sun.light_color = Color("ffe0af")
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-32, 145, 0)
	fill.light_color = Color("b7d8e8")
	fill.light_energy = 0.24
	add_child(fill)

func _add_mesh_collision(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		var mesh_node: MeshInstance3D = node
		var body := StaticBody3D.new()
		body.name = "GeographicCollision"
		var is_ground := str(node.name).begins_with("Ground") or str(node.name).begins_with("Curbs")
		body.collision_layer = 1 if is_ground else 2
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		shape.shape = mesh_node.mesh.create_trimesh_shape()
		body.add_child(shape)
		mesh_node.add_child(body)
		collision_meshes += 1
	for child in node.get_children():
		if not child is StaticBody3D:
			_add_mesh_collision(child)

func _build_bounds() -> void:
	var extent: Dictionary = level_data.get("terrain_extent", {})
	if extent.is_empty():
		return
	var low := vector(extent.get("min"))
	var high := vector(extent.get("max"))
	# Invisible edge barriers prevent walking off the finite surveyed terrain.
	for axis in [0, 2]:
		for edge in [low[axis] + 2.0, high[axis] - 2.0]:
			var body := StaticBody3D.new()
			body.name = "SurveyBoundary"
			body.collision_layer = 2
			body.collision_mask = 0
			var size := high - low + Vector3(4, 80, 4)
			size[axis] = 1.0
			var box := BoxShape3D.new()
			box.size = size
			var shape := CollisionShape3D.new()
			shape.shape = box
			body.position = (low + high) * 0.5
			body.position[axis] = edge
			body.add_child(shape)
			add_child(body)

func ground_at(point: Vector3) -> Dictionary:
	var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 60.0, point - Vector3.UP * 120.0, 1)
	return get_world_3d().direct_space_state.intersect_ray(ray)

func spawn_player() -> void:
	var spawn: Dictionary = level_data.get("spawn", {"position": [0, 0, 0], "yaw": 0})
	var point := vector(spawn.get("position", [0, 0, 0]))
	_place_player(point, float(spawn.get("yaw", 0)))

func _place_player(point: Vector3, heading: float) -> void:
	var ground := ground_at(point)
	if not ground.is_empty():
		point.y = ground.position.y
	player.position = point + Vector3.UP * 0.05
	player.velocity = Vector3.ZERO
	player.current_speed = 0.0
	player.set_orbiting(false)
	player._orbit_basis_latched = false
	player.yaw = heading
	player.camera_yaw = heading
	player.camera_pitch = 0.24
	player.update_camera()
	_safe_position = player.position

func teleport_to_landmark(id: String) -> bool:
	for mark in landmarks:
		if str(mark.get("id", "")) == id:
			_place_player(vector(mark.get("position")), player.yaw)
			return true
	return false

func get_progress() -> Dictionary:
	return {"visited": visited.keys(), "completed": visited.size(), "total": landmarks.size(), "route_index": route_index, "finished": route_index >= landmarks.size(), "distance_walked": player.distance_walked if player else 0.0}

func capture_view(eye: Vector3, target: Vector3) -> void:
	player.camera_override = {"eye": eye, "target": target}
	player.update_camera()

func release_capture_view() -> void:
	player.camera_override = {}
	player.update_camera()

func _build_markers() -> void:
	for i in range(landmarks.size()):
		var mark: Dictionary = landmarks[i]
		var root := Node3D.new()
		root.name = "RouteStop_" + str(mark.get("id", i))
		root.position = vector(mark.get("position", [0, 0, 0]))
		add_child(root)
		var ring := MeshInstance3D.new()
		var mesh := TorusMesh.new()
		mesh.inner_radius = 1.5
		mesh.outer_radius = 1.64
		mesh.rings = 32
		mesh.ring_segments = 8
		ring.mesh = mesh
		ring.position.y = 0.15
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("f8c76d")
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring.material_override = material
		root.add_child(ring)
		var label := Label3D.new()
		label.text = "%02d  %s" % [i + 1, str(mark.get("label", "Explore"))]
		label.position.y = 3.2
		label.font_size = 42
		label.pixel_size = 0.0035
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color("fff1c8")
		label.outline_modulate = Color("13282c")
		label.outline_size = 10
		# The HUD supplies the nearby check-in prompt; avoid giant text filling the camera.
		label.visibility_range_begin = 7.0
		label.visibility_range_end = 140.0
		root.add_child(label)
		_markers.append(root)
	_update_markers()

func _update_markers() -> void:
	for i in range(_markers.size()):
		_markers[i].visible = i == route_index and not has_active_case()

func has_active_case() -> bool:
	return missions != null and not str(missions.get_status().get("active_id", "")).is_empty()

func _build_case_marker() -> void:
	_case_marker = Node3D.new()
	_case_marker.name = "CaseDestination"
	add_child(_case_marker)
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.75
	mesh.outer_radius = 0.83
	mesh.rings = 32
	mesh.ring_segments = 8
	var ring := MeshInstance3D.new()
	ring.mesh = mesh
	ring.position.y = 0.08
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("70e0da")
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = mat
	_case_marker.add_child(ring)
	_case_marker.hide()

func show_notice(message: String) -> void:
	_notice.text = message
	_notice_until = _time + 12.0

func _cases_changed() -> void:
	_update_markers()
	_update_ui()

func start_neighborhood_case(id: String) -> bool:
	if missions == null or not ready_to_play:
		return false
	if not missions.start_case(id):
		return false
	resume_exploring()
	return true

func interact() -> bool:
	if paused or not ready_to_play:
		return false
	if missions != null and missions.interact():
		return true
	if has_active_case():
		return false
	return check_in()

func _style(bg: Color, border: Color = Color("49635e")) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	return style

func _text(parent: Node, text: String, size: int = 18, color: Color = Color("f5f0df")) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _panel(parent: Node, position_: Vector2, width: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.position = position_
	panel.custom_minimum_size.x = width
	panel.add_theme_stylebox_override("panel", _style(Color(0.055, 0.12, 0.13, 0.94)))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	panel.add_child(box)
	return box

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 44
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_stylebox_override("normal", _style(Color("23433f")))
	button.add_theme_stylebox_override("hover", _style(Color("385a4d"), Color("f8cc7b")))
	button.add_theme_stylebox_override("focus", _style(Color("385a4d"), Color("f8cc7b")))
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 12
	add_child(_ui)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)
	_fps = _text(root, "FPS", 16, Color("f5f0df"))
	_fps.name = "FrameRate"
	_fps.position = Vector2(16, 12)
	_fps.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fps.add_theme_constant_override("outline_size", 4)
	_fps.add_theme_color_override("font_outline_color", Color("112025"))
	var route_anchor := Control.new()
	root.add_child(route_anchor)
	route_anchor.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	var ledger := _panel(route_anchor, Vector2(-348, 20), 328)
	_location = _text(ledger, "Old York Road", 18, Color("f5e3b8"))
	_location.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_location.custom_minimum_size.x = 292
	_progress = _text(ledger, "NEIGHBORHOOD WALK", 13, Color("9bb8b1"))
	_objective = _text(ledger, "", 20)
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective.custom_minimum_size.x = 292
	_distance = _text(ledger, "", 15, Color("a9bdb5"))
	_distance.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_distance.custom_minimum_size.x = 292
	_prompt = _text(ledger, "", 17, Color("70e0da"))
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt.custom_minimum_size.x = 292
	_notice = _text(ledger, "", 16, Color("eadfc7"))
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.custom_minimum_size.x = 292
	_notice_panel = _notice
	_notice.hide()
	_radar = load("res://scripts/city/city_radar.gd").new()
	root.add_child(_radar)
	_radar.setup(self)
	_radar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_radar.offset_left = 20
	_radar.offset_right = 228
	_radar.offset_top = -228
	_radar.offset_bottom = -20
	_settings = SettingsPanel.new()
	root.add_child(_settings)
	_settings.setup(self)
	_menu = _settings
	_resume = _settings.resume_button
	_map_overlay = MapOverlay.new()
	root.add_child(_map_overlay)
	_map_overlay.setup(self)

func resume_exploring() -> void:
	if not ready_to_play:
		return
	paused = false
	_menu.hide()
	_map_overlay.hide()
	_radar.show()
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null:
		focused.release_focus()
	player.enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func pause_exploring() -> void:
	if not ready_to_play:
		return
	paused = true
	player.enabled = false
	player.set_orbiting(false)
	_radar.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_map_overlay.hide()
	_menu.show()
	_resume.grab_focus()

func toggle_map() -> void:
	if not ready_to_play:
		return
	if _map_overlay.visible:
		resume_exploring()
		return
	paused = true
	player.enabled = false
	player.set_orbiting(false)
	_radar.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_menu.hide()
	_map_overlay.show()

func _input(event: InputEvent) -> void:
	if not ready_to_play:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		player.set_orbiting(event.pressed and not paused)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if paused:
				resume_exploring()
			else:
				pause_exploring()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_M:
			toggle_map()
			get_viewport().set_input_as_handled()
		elif _map_overlay.visible and event.keycode in [KEY_PLUS, KEY_EQUAL, KEY_KP_ADD, KEY_MINUS, KEY_KP_SUBTRACT]:
			_map_overlay.map.zoom_by(0.8 if event.keycode in [KEY_MINUS, KEY_KP_SUBTRACT] else 1.25)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not paused:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not ready_to_play or paused:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_V:
			player.toggle_view()
		elif event.keycode == KEY_E:
			interact()
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		player.look(event.screen_relative)

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT] and ready_to_play:
		if not paused or _map_overlay.visible:
			pause_exploring()

func check_in() -> bool:
	if paused or not ready_to_play:
		return false
	if route_index >= landmarks.size():
		return false
	var mark: Dictionary = landmarks[route_index]
	var target := vector(mark.get("position"))
	if Vector2(player.position.x - target.x, player.position.z - target.z).length() > 6.0:
		return false
	visited[str(mark.get("id", route_index))] = true
	route_index += 1
	Audio.sfx("pickup")
	_notice.text = str(mark.get("description", "Another corner of Pen Lucy explored."))
	_notice_until = _time + 9.0
	if route_index >= landmarks.size():
		_notice.text = "Neighborhood walk complete. You've checked in at every stop. Keep exploring, or return to the original block from Esc."
		_notice_until = _time + 18.0
		Audio.sfx("win")
	_update_markers()
	_update_ui()
	return true

func _process(delta: float) -> void:
	if not ready_to_play:
		return
	if not paused:
		_time += delta
	_last_ground_check += delta
	_fps_time += delta
	_ui_time += delta
	if _fps_time >= 0.25:
		_fps_time = 0.0
		_fps.text = "%d FPS" % Engine.get_frames_per_second()
	if _time > _notice_until:
		_notice.text = ""
	_notice_panel.visible = not _notice.text.is_empty()
	if _last_ground_check > 0.5:
		_last_ground_check = 0.0
		if player.is_on_floor():
			_safe_position = player.position
		if player.position.y < _safe_position.y - 12.0:
			_place_player(_safe_position, player.yaw)
			_notice.text = "Back on solid ground. Continue your neighborhood walk."
			_notice_until = _time + 5.0
	if _ui_time >= 0.1:
		_ui_time = 0.0
		_update_ui()

func _physics_process(delta: float) -> void:
	if not ready_to_play or paused:
		return
	if npcs:
		npcs.tick(delta)
	if traffic:
		traffic.tick(delta)
	if missions:
		missions.tick(delta)

func _update_ui() -> void:
	if player == null or _progress == null:
		return
	_location.text = _nearest_street()
	_progress.text = "NEIGHBORHOOD WALK  ·  %d / %d" % [visited.size(), landmarks.size()]
	_prompt.text = ""
	if missions:
		var status: Dictionary = missions.get_status()
		var active := not str(status.get("active_id", "")).is_empty()
		if _case_marker:
			_case_marker.visible = active
		_prompt.text = str(status.get("prompt", ""))
		_prompt.visible = not _prompt.text.is_empty()
		if active:
			var target: Vector3 = vector(status.get("target_position", player.position))
			if _case_marker:
				_case_marker.position = target
			_progress.text = "CASE  ·  " + str(status.get("title", "Neighborhood case"))
			_objective.text = str(status.get("objective", ""))
			_distance.text = "%dm away" % roundi(Vector2(target.x - player.position.x, target.z - player.position.z).length())
			return
	if route_index < landmarks.size():
		var mark: Dictionary = landmarks[route_index]
		var target := vector(mark.get("position"))
		var metres := Vector2(player.position.x - target.x, player.position.z - target.z).length()
		_objective.text = str(mark.get("label", "Next stop"))
		_distance.text = "%dm away" % roundi(metres)
		if _prompt.text.is_empty() and metres <= 6.0:
			_prompt.text = "E  Check in"
	else:
		_objective.text = "Neighborhood explored"
		_distance.text = ""
	_prompt.visible = not _prompt.text.is_empty()

func _nearest_street() -> String:
	var closest := INF
	var street := "Pen Lucy · Baltimore"
	var point := Vector2(player.position.x, player.position.z)
	for road in level_data.get("roads", []):
		var points: Array = road.get("points", [])
		for i in range(1, points.size()):
			var p := vector(points[i - 1])
			var q := vector(points[i])
			var near := Geometry2D.get_closest_point_to_segment(point, Vector2(p.x, p.z), Vector2(q.x, q.z))
			var distance := near.distance_squared_to(point)
			if distance < closest:
				closest = distance
				street = str(road.get("name", "Pen Lucy"))
	return street
