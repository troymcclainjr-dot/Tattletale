extends Node3D
## A neighborhood chapter built on the georeferenced Pen Lucy model.
## Physics layers: 1 terrain, 2 buildings/props, 4 explorer, 8 neighbors, 16 vehicles.

const C := preload("res://scripts/city/city_theme.gd")
const T := C.T
const Dialogue := preload("res://scripts/city/city_dialogue.gd")
const Explorer := preload("res://scripts/city/city_player.gd")
const SettingsPanel := preload("res://scripts/city/city_settings.gd")
const MapOverlay := preload("res://scripts/city/city_map_overlay.gd")
const PerfCounters := preload("res://scripts/city/city_perf_counters.gd")
const DATA_PATH := "res://assets/data/pen_lucy_level.json"
const CITY_PATH := "res://assets/models/city/pen_lucy.glb"

var player: CharacterBody3D
var level_data: Dictionary = {}:
	set(value):
		level_data = value
		_street_locator = null
var _street_locator: RefCounted
var landmarks: Array = []
var visited: Dictionary = {}
var route_index := 0
var offscreen_validation := false
var ready_to_play := false
var level_ready := false
var paused := true
var collision_meshes := 0
var dressing_report: Dictionary = {}
var progression: Node
var driving: Node
var bicycle: CharacterBody3D
var bicycle_reactions: Node3D
var basketball: Node3D
var police_assistance: Node
var incidents: Node
var _bike_contact_history: Dictionary = {}
var vehicle_presentation: Node3D
var law: Node
var shops: Node3D
var _sandbox_label: Label
var world_save: Node
var _old_auto_accept_quit := true
var world_time: Node
var day_night: Node
var residents: Node3D
var combat: Node3D
var _clock_label: Label
var _combat_label: Label
var _aim_dot: Label
var _wind_accumulator := 0.0
var npcs: Node3D
var traffic: Node3D
var missions: Node3D
var render_optimizer: Node
var streaming: Node
var vegetation: Node
var yard_details: Node3D
var yard_report: Dictionary = {}
var park_courts: Node3D
var park_furniture: Node3D
var civic_fleet: Node3D
var backlot_details: Node3D
var alive_world: Node3D
var park_report: Dictionary = {}
var vegetation_report: Dictionary = {}
var neighborhood_details: Node3D
var power_grid: Node3D
var civic_district: Node3D
var inspector: Node
var weathering_report: Dictionary = {}
var mission_navigation: RefCounted
var _dialogue: Control
var conversations: Dictionary = {}
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
var _save_warning: Label
var _menu: Control
var _resume: Button
var _time := 0.0
var _notice_until := 0.0
var _notice_queue: Array[String] = []
var _audio_paused := false
var _last_ground_check := 0.0
var _safe_position := Vector3.ZERO
var _loading: CanvasLayer
var _loading_status: Label
var _exit_confirmation: ConfirmationDialog
var _exit_to_menu := false
## Enabled only for the bounded benchmark sample; normal play records nothing.
var profile_physics := false
var physics_samples: Dictionary = {"clock": [], "combat": [], "residents": [], "npcs": [], "traffic": [], "missions": []}

func _ready() -> void:
	_old_auto_accept_quit = get_tree().auto_accept_quit
	offscreen_validation = "--offscreen-validation" in OS.get_cmdline_args() or "--offscreen-validation" in OS.get_cmdline_user_args()
	if offscreen_validation and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		get_window().unfocusable = true
		DisplayServer.window_set_position(Vector2i(-10000, -10000))
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
	world_time = load("res://scripts/city/city_world_time.gd").new()
	add_child(world_time)
	world_time.frozen = "--freeze-world-time" in OS.get_cmdline_user_args()
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
	if not "--no-civic-district" in OS.get_cmdline_user_args():
		civic_district = load("res://scripts/city/city_civic_district.gd").new()
		add_child(civic_district)
		civic_district.setup(self, city)
		shops = load("res://scripts/city/city_shops.gd").new()
		add_child(shops)
		var shop_build: Dictionary = shops.apply_before_collision(city, civic_district)
		if not bool(shop_build.get("ok", false)):
			push_error("Shop redevelopment failed: " + str(shop_build.get("message", "unknown")))
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
	if render_optimizer != null:
		render_optimizer.consolidate_material_palette()
	_loading_status.text = "Welcoming the neighbors…"
	yard_details = load("res://scripts/city/city_yard_details.gd").new()
	add_child(yard_details)
	yard_report = yard_details.setup(self)
	yard_details.set_presence(player.global_position, 55.0, 180.0)
	if ResourceLoader.exists("res://scripts/city/city_park_courts.gd"):
		park_courts = load("res://scripts/city/city_park_courts.gd").new()
		add_child(park_courts)
		park_report = park_courts.setup(self)
		park_courts.set_presence(player.global_position, 55.0, 180.0)
	if ResourceLoader.exists("res://scripts/city/city_park_furniture.gd"):
		park_furniture = load("res://scripts/city/city_park_furniture.gd").new()
		add_child(park_furniture)
		park_furniture.setup(self)
		park_furniture.set_presence(player.global_position, 55.0, 180.0)
	await get_tree().physics_frame
	if civic_district != null and not "--no-civic-fleet" in OS.get_cmdline_user_args() and ResourceLoader.exists("res://scripts/city/city_civic_parking_fleet.gd"):
		civic_fleet = load("res://scripts/city/city_civic_parking_fleet.gd").build(self)
		add_child(civic_fleet)
	if ResourceLoader.exists("res://scripts/city/city_backlot_details.gd"):
		backlot_details = load("res://scripts/city/city_backlot_details.gd").new()
		add_child(backlot_details)
		backlot_details.setup(self)
	alive_world = load("res://scripts/city/city_alive_world.gd").new()
	add_child(alive_world)
	alive_world.setup(self)
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
	if not "--no-city-power" in OS.get_cmdline_user_args():
		power_grid = load("res://scripts/city/city_power_grid.gd").new()
		add_child(power_grid)
		power_grid.setup(self)
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
	residents = load("res://scripts/city/city_residents.gd").new()
	add_child(residents)
	if not "--no-daily-residents" in OS.get_cmdline_user_args():
		residents.setup(self)
		_loading_status.text = "Preparing the neighbors' daily routes…"
		# Complete bounded corridor work while the loading screen is still up,
		# rather than borrowing the first twenty frames of player movement.
		while not residents._build_queue.is_empty():
			residents._build_route(residents._build_queue.pop_front())
			await get_tree().process_frame
	combat = load("res://scripts/city/city_combat.gd").new()
	add_child(combat)
	combat.setup(self)
	player.vehicle_impact.connect(combat.receive_traffic_impact)
	progression = load("res://scripts/city/city_progression.gd").new()
	add_child(progression)
	progression.setup(self)
	driving = load("res://scripts/city/city_driving.gd").new()
	add_child(driving)
	driving.setup(self)
	vehicle_presentation = load("res://scripts/city/city_vehicle_presentation.gd").new()
	add_child(vehicle_presentation)
	vehicle_presentation.setup(self)
	if driving.has_signal("vehicle_collision"):
		driving.connect("vehicle_collision", combat.receive_vehicle_collision)
	law = load("res://scripts/city/city_law.gd").new()
	add_child(law)
	law.setup(self)
	law.offense_observed.connect(_on_observed_offense)
	combat.player_offense.connect(_on_player_offense)
	combat.player_defeated.connect(law.on_player_defeated)
	if shops != null:
		shops.setup(self)
		shops.modal_changed.connect(_shop_modal_changed)
	var phone: Node3D = load("res://scripts/city/city_player_phone.gd").new()
	add_child(phone)
	phone.setup(self, player)
	# Police assistance targets world incidents; the caller is not the suspect.
	police_assistance = load("res://scripts/city/city_police_assistance.gd").new()
	add_child(police_assistance)
	police_assistance.setup(self)
	incidents = load("res://scripts/city/city_incidents.gd").new()
	incidents.name = "NeighborhoodIncidents"
	add_child(incidents)
	incidents.setup(self)
	incidents.incident_changed.connect(missions.on_incident_event)
	incidents.report_status_changed.connect(_on_incident_report_status)
	phone.photo_captured.connect(_on_phone_photo_captured)
	phone.police_requested.connect(_request_police_help)
	combat.actor_died.connect(missions.on_actor_died)
	if ResourceLoader.exists("res://scripts/city/city_day_night.gd"):
		day_night = load("res://scripts/city/city_day_night.gd").new()
		add_child(day_night)
		day_night.setup(self)
	_build_case_marker()
	_cases_changed()
	_loading_status.text = "Preparing nearby blocks and distant views…"
	streaming = load("res://scripts/city/city_streaming.gd").new()
	add_child(streaming)
	var detail_providers: Array[Node] = []
	if yard_details != null:
		detail_providers.append(yard_details)
	if park_courts != null:
		detail_providers.append(park_courts)
	if park_furniture != null:
		detail_providers.append(park_furniture)
	if backlot_details != null:
		detail_providers.append(backlot_details)
	if alive_world != null:
		detail_providers.append(alive_world)
	if npcs.crowd != null:
		detail_providers.append(npcs.crowd)
	if vegetation != null:
		detail_providers.append(vegetation)
	if neighborhood_details != null:
		detail_providers.append(neighborhood_details)
	if power_grid != null:
		detail_providers.append(power_grid)
	if civic_district != null:
		detail_providers.append(civic_district)
	if traffic.parked != null:
		detail_providers.append(traffic.parked)
	streaming.setup(self, render_optimizer, detail_providers)
	if vegetation != null:
		_loading_status.text = "Preparing tree cover…"
		await vegetation.prepare_presence(player.global_position, 55.0, 180.0)
	world_save = load("res://scripts/city/city_world_save.gd").new()
	add_child(world_save)
	world_save.setup(self)
	var restored: Dictionary = world_save.load_state()
	if not bool(restored.get("ok", false)):
		progression.begin_new_game()
	if bool(restored.get("ok", false)):
		_update_markers()
		if day_night != null:
			day_night.tick(0.5)
		streaming.refresh_now()
		if vegetation != null:
			await vegetation.prepare_presence(player.global_position, 55.0, 180.0)
	# Place the bicycle beside the restored explorer, never at an old spawn.
	bicycle = load("res://scripts/city/city_bicycle.gd").new()
	add_child(bicycle)
	bicycle.setup(self)
	bicycle_reactions = load("res://scripts/city/city_bicycle_reactions.gd").new()
	add_child(bicycle_reactions)
	bicycle_reactions.setup(self, bicycle)
	bicycle.pedestrian_contact.connect(_on_bicycle_contact)
	basketball = load("res://scripts/city/city_basketball.gd").new()
	add_child(basketball)
	basketball.setup(self, park_courts)
	bicycle.mounted.connect(func(): basketball.suspend(true))
	get_tree().auto_accept_quit = false
	inspector = load("res://scripts/city/city_inspector.gd").new()
	add_child(inspector)
	inspector.setup(self)
	ready_to_play = true
	level_ready = true
	_update_ui()
	_settings.apply_settings(true)
	_loading.queue_free()
	_loading = null
	if offscreen_validation or DisplayServer.get_name() == "headless" or get_window().has_focus():
		resume_exploring()
	else:
		pause_exploring()
	if world_save.enabled and bool(world_save.get_status().write_blocked):
		show_notice("Your checkpoint could not be restored: %s. It is preserved. Open Settings to recover saving." % world_save.last_result)
	elif bool(restored.get("ok", false)) and (bool(restored.get("player_fallback", false)) or int(restored.get("vehicle_fallbacks", 0)) > 0):
		show_notice(str(world_save.last_result))

func _build_loading_screen() -> void:
	_loading = CanvasLayer.new()
	_loading.layer = 30
	add_child(_loading)
	var background := ColorRect.new()
	background.color = T.INK
	_loading.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	_loading.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 20)
	center.add_child(content)
	var welcome := _text(content, "WELCOME TO BALTIMORE", 38, T.PAPER)
	C.text(welcome, "display", 38, T.PAPER)
	_loading_status = _text(content, "Preparing your neighborhood walk…", 21, T.PAPER)
	_text(content, "The first visit can take a little longer while the neighborhood loads.", 17, T.DIM)

func _exit_tree() -> void:
	Audio.set_paused(false)
	get_tree().auto_accept_quit = _old_auto_accept_quit
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
	# Shared by every graphics preset: lower the illumination by twenty percent.
	environment.ambient_light_energy = 0.52
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("c7d2c7")
	environment.fog_density = 0.00055
	# Preserve distance haze on buildings without flattening the whole sky to
	# the fog colour. The sky shader supplies its own horizon haze and clouds.
	environment.fog_sky_affect = 0.12
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
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.name = "SkyFill"
	fill.rotation_degrees = Vector3(-32, 145, 0)
	fill.light_color = Color("b7d8e8")
	fill.light_energy = 0.192
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
	if police_assistance != null and police_assistance.is_busy():
		police_assistance.reset_state()
	var ground := ground_at(point)
	if not ground.is_empty():
		point.y = ground.position.y
	if bicycle != null and bicycle.active:
		bicycle.recovery_exit_at(point + Vector3.UP * 0.05, heading)
	if basketball != null:
		basketball.suspend(true)
	player.position = point + Vector3.UP * 0.05
	player.velocity = Vector3.ZERO
	player.current_speed = 0.0
	player.reset_jump()
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
	if message.is_empty() or message == _notice.text or message in _notice_queue:
		return
	if not _notice.text.is_empty() and _time <= _notice_until:
		if _notice_queue.size() >= 6:
			_notice_queue.pop_front()
		_notice_queue.append(message)
		return
	_display_notice(message)

func _display_notice(message: String) -> void:
	_notice.text = message
	_notice_until = _time + clampf(message.length() * 0.045, 3.0, 8.0)

func _navigation_clear_link(a: Vector3, b: Vector3) -> bool:
	if a.distance_squared_to(b) < 0.01:
		return true
	var query := PhysicsRayQueryParameters3D.create(a + Vector3.UP * 0.8, b + Vector3.UP * 0.8, 2)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _cases_changed() -> void:
	if mission_navigation == null:
		mission_navigation = preload("res://scripts/city/city_mission_navigation.gd").new()
		mission_navigation.setup(level_data, _navigation_clear_link)
	mission_navigation.update(missions.get_status(), player.global_position, 0.0, true)
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
	if bicycle != null and bicycle.active:
		return false
	if basketball != null and basketball.interact():
		return true
	if (driving != null and driving.active) or (law != null and bool(law.get_status().get("recovering", false))):
		return false
	if combat != null and (combat.downed > 0.0 or combat.get_status().aggro_count > 0):
		show_notice("Move away from the fight before talking.")
		return false
	if paused or not ready_to_play:
		return false
	if missions != null:
		var preview: Dictionary = missions.conversation_preview()
		if not preview.is_empty():
			return open_conversation(preview)
	var talker := nearby_talker()
	if not talker.is_empty():
		var graph: Dictionary = conversations[talker].duplicate(true)
		graph["actor_id"] = talker
		return open_conversation(graph)
	if has_active_case():
		return false
	return check_in()

## Register authored dialogue for any actor exposed by npcs.actor_position(id).
func register_conversation(actor_id: String, data: Dictionary) -> void:
	conversations[actor_id] = data.duplicate(true)

func nearby_talker() -> String:
	if npcs == null or missions == null:
		return ""
	var nearest := ""
	var distance := INF
	for id in conversations:
		var actor = npcs.get_actor(str(id))
		if actor == null or not actor.enabled or actor.combat_override:
			continue
		var at: Vector3 = npcs.actor_position(str(id))
		if at.is_finite() and missions._can_interact(at):
			var metres := player.global_position.distance_squared_to(at)
			if metres < distance:
				distance = metres
				nearest = str(id)
	return nearest

func conversation_condition(key) -> bool:
	if progression != null and progression.handles_condition(key):
		return progression.meets(key)
	# Named flags supplied by authored resident data; no implicit quest mutation.
	return bool(level_data.get("dialogue_flags", {}).get(str(key), false))

func conversation_hook(action: Dictionary) -> bool:
	if str(action.get("kind", "")) == "progression":
		return progression != null and progression.commit_dialogue_action(action)
	return missions != null and missions.commit_dialogue_action(action)

func open_conversation(data: Dictionary) -> bool:
	if paused or not ready_to_play:
		return false
	_suspend_phone()
	var graph := data.duplicate(true)
	var actor_id := str(graph.get("actor_id", ""))
	if progression != null and not actor_id.is_empty():
		if actor_id == "lookout":
			var reputation_chat: Dictionary = progression.dialogue_example("lookout_reputation")
			if not reputation_chat.is_empty():
				for node_id in reputation_chat.nodes:
					var node: Dictionary = reputation_chat.nodes[node_id].duplicate(true)
					for choice in node.get("choices", []):
						if choice.has("next"):
							choice.next = "reputation_" + str(choice.next)
					graph.nodes["reputation_" + str(node_id)] = node
				var entry: Dictionary = graph.nodes[str(graph.get("start", "start"))]
				if not entry.has("choices"):
					entry["choices"] = []
				entry.choices.append({"text": "What are people saying about me?", "next": "reputation_start"})
		graph = progression.decorate_conversation(graph, progression.role_for_actor(actor_id))
	if not _dialogue.open(graph, conversation_condition, conversation_hook):
		return false
	paused = true
	if combat != null:
		combat.cancel_player_actions()
	player.enabled = false
	player.velocity = Vector3.ZERO
	player.current_speed = 0.0
	player.set_orbiting(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_prompt.hide()
	return true

func _text(parent: Node, text: String, size: int = 18, color: Color = T.INK) -> Label:
	var label := Label.new()
	label.text = text
	C.text(label, "body600", size, color)
	parent.add_child(label)
	return label

func _panel(parent: Node, position_: Vector2, width: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.position = position_
	panel.custom_minimum_size.x = width
	panel.add_theme_stylebox_override("panel", C.case_file())
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	panel.add_child(box)
	return box

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 12
	add_child(_ui)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = C.theme()
	_ui.add_child(root)
	_fps = _text(root, "FPS", 16, T.PAPER)
	_fps.label_settings = T.ls(T.mono(true), 16, T.PAPER, [], 0.0, 4, T.INK)
	_fps.name = "FrameRate"
	_fps.position = Vector2(16, 12)
	_fps.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fps.add_theme_constant_override("outline_size", 4)
	_fps.add_theme_color_override("font_outline_color", Color("112025"))
	var route_anchor := Control.new()
	root.add_child(route_anchor)
	route_anchor.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	var ledger := _panel(route_anchor, Vector2(-348, 20), 328)
	_location = _text(ledger, "Old York Road", 18, T.INK)
	C.text(_location, "display", 18, T.INK)
	_location.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_location.custom_minimum_size.x = 292
	_clock_label = _text(ledger, "DAY 1 · 09:00", 13, T.INK)
	C.text(_clock_label, "mono", 13, T.INK)
	_combat_label = _text(ledger, "", 13, T.INK)
	_combat_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_combat_label.custom_minimum_size.x = 292
	_sandbox_label = _text(ledger, "", 13, T.INK)
	_sandbox_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sandbox_label.custom_minimum_size.x = 292
	_progress = _text(ledger, "NEIGHBORHOOD WALK", 13, T.SIREN)
	C.text(_progress, "monob", 13, T.SIREN)
	_objective = _text(ledger, "", 20)
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective.custom_minimum_size.x = 292
	_distance = _text(ledger, "", 15, T.INK)
	C.text(_distance, "mono", 15, T.INK)
	_distance.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_distance.custom_minimum_size.x = 292
	_prompt = _text(ledger, "", 17, T.SIREN)
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt.custom_minimum_size.x = 292
	_notice = _text(ledger, "", 16, T.INK)
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.custom_minimum_size.x = 292
	_notice_panel = _notice
	_notice.hide()
	_save_warning = _text(ledger, "SAVING PAUSED · Open Esc → Recover saving", 14, T.SIREN)
	_save_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_save_warning.custom_minimum_size.x = 292
	_save_warning.hide()
	_radar = load("res://scripts/city/city_radar.gd").new()
	root.add_child(_radar)
	_radar.setup(self)
	_radar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_radar.offset_left = 20
	_radar.offset_right = 228
	_radar.offset_top = -228
	_radar.offset_bottom = -20
	_aim_dot = _text(root, "+", 24, T.PAPER)
	_aim_dot.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_aim_dot.position -= Vector2(7, 15)
	_aim_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aim_dot.add_theme_constant_override("outline_size", 3)
	_aim_dot.add_theme_color_override("font_outline_color", T.INK)
	_aim_dot.hide()
	_settings = SettingsPanel.new()
	root.add_child(_settings)
	_settings.setup(self)
	_menu = _settings
	_resume = _settings.resume_button
	_map_overlay = MapOverlay.new()
	root.add_child(_map_overlay)
	_map_overlay.setup(self)
	_dialogue = Dialogue.new()
	root.add_child(_dialogue)
	_dialogue.closed.connect(resume_exploring)
	var dialogue_path := "res://assets/data/pen_lucy_dialogue.json"
	var authored = JSON.parse_string(FileAccess.get_file_as_string(dialogue_path))
	if authored is Dictionary:
		conversations = authored

func resume_exploring() -> void:
	if not ready_to_play:
		return
	if _dialogue != null and _dialogue.state.active:
		_dialogue.close()
	paused = false
	_menu.hide()
	_map_overlay.hide()
	_radar.show()
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null:
		focused.release_focus()
	player.enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if offscreen_validation else Input.MOUSE_MODE_CAPTURED

func pause_exploring() -> void:
	if not ready_to_play:
		return
	_suspend_phone()
	if _dialogue != null and _dialogue.state.active:
		_dialogue.close()
	paused = true
	if combat != null:
		combat.cancel_player_actions()
	player.enabled = false
	player.set_orbiting(false)
	_radar.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_map_overlay.hide()
	_menu.show()
	if _settings.has_method("refresh_checkpoint_status"):
		_settings.refresh_checkpoint_status()
	_resume.grab_focus()

func toggle_map() -> void:
	if _dialogue != null and _dialogue.state.active:
		return
	if not ready_to_play:
		return
	_suspend_phone()
	if _map_overlay.visible:
		resume_exploring()
		return
	paused = true
	if combat != null:
		combat.cancel_player_actions()
	player.enabled = false
	player.set_orbiting(false)
	_radar.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_menu.hide()
	_map_overlay.show()
	_map_overlay.map.fit_neighborhood()

func _input(event: InputEvent) -> void:
	if not ready_to_play:
		return
	if _dialogue != null and _dialogue.state.active:
		if _dialogue.handle_input(event):
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F6:
		if inspector.active:
			inspector.leave()
		else:
			_suspend_phone()
			if combat != null:
				combat.cancel_player_actions()
			inspector.enter()
		get_viewport().set_input_as_handled()
		return
	if inspector != null and inspector.active:
		inspector.handle_input(event)
		# Inspection map still needs GUI mouse events for buttons, drag and wheel.
		if not inspector.map_open or event is InputEventKey:
			get_viewport().set_input_as_handled()
		return
	if shops != null and shops.is_open():
		if shops.handle_input(event):
			get_viewport().set_input_as_handled()
		return
	if (law == null or not law.recovering) and not player.is_seated() and player.phone != null:
		var phone_handled: bool = player.phone.handle_input(event)
		if phone_handled:
			get_viewport().set_input_as_handled()
		if phone_handled or player.phone.active:
			if basketball != null:
				basketball.cancel_charge()
			return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if paused:
				resume_exploring()
			else:
				pause_exploring()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_M:
			toggle_map()
			get_viewport().set_input_as_handled()
			return
		if _map_overlay.visible and event.keycode in [KEY_PLUS, KEY_EQUAL, KEY_KP_ADD, KEY_MINUS, KEY_KP_SUBTRACT]:
			_map_overlay.map.zoom_by(0.8 if event.keycode in [KEY_MINUS, KEY_KP_SUBTRACT] else 1.25)
			get_viewport().set_input_as_handled()
			return
	if paused:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not offscreen_validation and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
			return
	if law != null and law.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if bicycle != null and bicycle.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if bicycle != null and bicycle.active:
		return
	if basketball != null and basketball.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if vehicle_presentation != null and vehicle_presentation.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if driving != null and driving.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if driving != null and driving.active:
		return
	if shops != null and shops.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if combat != null and (offscreen_validation or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED) and combat.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		player.set_orbiting(event.pressed)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not ready_to_play or paused or player.is_seated() or (player.phone != null and player.phone.active) or (law != null and law.recovering):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_V:
			player.toggle_view()
		elif event.keycode == KEY_E:
			interact()
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		player.look(event.screen_relative)

func _suspend_phone() -> void:
	if basketball != null:
		basketball.cancel_charge()
	if player != null and player.phone != null:
		player.phone.suspend()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_request_exit(false)
		return
	if offscreen_validation:
		return
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT] and ready_to_play:
		if inspector != null and inspector.active:
			inspector.release_mouse()
			return
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
	show_notice(str(mark.get("description", "Another corner of Pen Lucy explored.")))
	if route_index >= landmarks.size():
		show_notice("Neighborhood walk complete. You've checked in at every stop. Keep exploring, or return to the original block from Esc.")
		Audio.sfx("win")
	_update_markers()
	_update_ui()
	return true

var process_samples: Array[float] = []

func _process(delta: float) -> void:
	var began := Time.get_ticks_usec() if profile_physics else 0
	_process_ui(delta)
	if profile_physics:
		process_samples.append(float(Time.get_ticks_usec() - began) / 1000.0)

func _process_ui(delta: float) -> void:
	if not ready_to_play:
		return
	if _audio_paused != paused:
		_audio_paused = paused
		Audio.set_paused(paused)
	if not paused:
		_time += delta
	_last_ground_check += delta
	_fps_time += delta
	_ui_time += delta
	if _fps_time >= 0.25:
		_fps_time = 0.0
		_fps.text = "%d FPS" % Engine.get_frames_per_second()
	if _time > _notice_until:
		if not _notice_queue.is_empty():
			_display_notice(_notice_queue.pop_front())
		else:
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
	var began := Time.get_ticks_usec() if profile_physics else 0
	if world_save != null:
		world_save.tick(delta)
	world_time.tick(delta)
	if progression != null:
		var stamp := PerfCounters.begin() if PerfCounters.enabled else 0
		progression.tick(delta)
		if PerfCounters.enabled:
			PerfCounters.end(PerfCounters.PROGRESSION_TICK, stamp)
	if day_night != null:
		day_night.tick(delta)
	_wind_accumulator += delta
	if _wind_accumulator >= 0.05:
		_wind_accumulator = 0.0
		if vegetation != null:
			vegetation.set_wind_time(world_time.elapsed_seconds)
	if profile_physics:
		physics_samples.clock.append(float(Time.get_ticks_usec() - began) / 1000.0)
		began = Time.get_ticks_usec()
	if combat != null:
		var stamp := PerfCounters.begin() if PerfCounters.enabled else 0
		combat.tick(delta)
		if PerfCounters.enabled:
			PerfCounters.end(PerfCounters.COMBAT_TICK, stamp)
	if law != null:
		var stamp := PerfCounters.begin() if PerfCounters.enabled else 0
		law.tick(delta)
		if PerfCounters.enabled:
			PerfCounters.end(PerfCounters.LAW_TICK, stamp)
	if shops != null:
		var stamp := PerfCounters.begin() if PerfCounters.enabled else 0
		shops.tick(delta)
		if PerfCounters.enabled:
			PerfCounters.end(PerfCounters.SHOP_TICK, stamp)
	if profile_physics:
		physics_samples.combat.append(float(Time.get_ticks_usec() - began) / 1000.0)
		began = Time.get_ticks_usec()
	if residents != null:
		var stamp := PerfCounters.begin() if PerfCounters.enabled else 0
		residents.tick(delta)
		if PerfCounters.enabled:
			PerfCounters.end(PerfCounters.RESIDENT_TICK, stamp)
	if profile_physics:
		physics_samples.residents.append(float(Time.get_ticks_usec() - began) / 1000.0)
		began = Time.get_ticks_usec()
	if npcs:
		var stamp := PerfCounters.begin() if PerfCounters.enabled else 0
		npcs.tick(delta)
		if PerfCounters.enabled:
			PerfCounters.end(PerfCounters.NPC_TICK, stamp)
	if profile_physics:
		physics_samples.npcs.append(float(Time.get_ticks_usec() - began) / 1000.0)
		began = Time.get_ticks_usec()
	if traffic:
		traffic.tick(delta)
	if bicycle != null:
		bicycle.tick(delta)
	if bicycle_reactions != null:
		bicycle_reactions.tick(delta)
	if basketball != null:
		basketball.tick(delta)
	if police_assistance != null:
		police_assistance.tick(delta)
	if incidents != null:
		incidents.tick(delta)
	if driving != null:
		var stamp := PerfCounters.begin() if PerfCounters.enabled else 0
		driving.tick(delta)
		if PerfCounters.enabled:
			PerfCounters.end(PerfCounters.DRIVING_TICK, stamp)
	if vehicle_presentation != null:
		vehicle_presentation.tick(delta)
	if profile_physics:
		physics_samples.traffic.append(float(Time.get_ticks_usec() - began) / 1000.0)
		began = Time.get_ticks_usec()
	if missions:
		missions.tick(delta)
	if profile_physics:
		physics_samples.missions.append(float(Time.get_ticks_usec() - began) / 1000.0)

func _update_ui() -> void:
	var began := PerfCounters.begin() if PerfCounters.enabled else 0
	_update_ui_content()
	if PerfCounters.enabled:
		PerfCounters.end(PerfCounters.LEVEL_UI_UPDATE, began)

func _update_ui_content() -> void:
	if player == null or _progress == null:
		return
	_location.text = _nearest_street()
	if _save_warning != null:
		_save_warning.visible = world_save != null and world_save.enabled and bool(world_save.get_status().get("write_blocked", false))
	if world_time != null and _clock_label != null:
		_clock_label.text = world_time.get_status().label
	if combat != null and _combat_label != null:
		var fight: Dictionary = combat.get_status()
		_combat_label.text = "HEALTH %d" % roundi(fight.health)
		_combat_label.modulate = T.SIREN if fight.damage_flash > 0.0 else Color.WHITE
		if fight.aggro_count > 0:
			_combat_label.text += "\n%d hostile · move away to disengage" % fight.aggro_count
		if fight.downed > 0.0:
			_combat_label.text += "\nCatching your breath…"
		_aim_dot.visible = false
		_aim_dot.modulate = T.SIREN if fight.hit_flash > 0.0 else T.PAPER
	_update_sandbox_ui()
	_progress.text = "NEIGHBORHOOD WALK  ·  %d / %d" % [visited.size(), landmarks.size()]
	_prompt.text = ""
	if missions:
		var status: Dictionary = missions.get_status()
		if mission_navigation != null:
			mission_navigation.update(status, player.global_position, 0.1)
		var active := not str(status.get("active_id", "")).is_empty()
		if _case_marker:
			_case_marker.visible = active
		_prompt.text = str(status.get("prompt", ""))
		_prompt.visible = not _prompt.text.is_empty() and not paused
		if active:
			var target: Vector3 = vector(status.get("target_position", player.position))
			if _case_marker:
				_case_marker.position = target
			_progress.text = "CASE  ·  " + str(status.get("title", "Neighborhood case"))
			_objective.text = str(status.get("objective", ""))
			_distance.text = "%dm away" % roundi(Vector2(target.x - player.position.x, target.z - player.position.z).length())
			return
		if bool(status.get("all_complete", false)):
			_progress.text = "NEIGHBORHOOD CASES  ·  %d / %d" % [status.completed, status.total]
			_objective.text = str(status.objective)
			_distance.text = "%d community points" % int(status.score)
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
	if _prompt.text.is_empty() and not nearby_talker().is_empty():
		_prompt.text = "E  Talk"
	_prompt.visible = not _prompt.text.is_empty() and not paused

func _nearest_street(at := Vector3.INF) -> String:
	var began := PerfCounters.begin() if PerfCounters.enabled else 0
	if _street_locator == null:
		_street_locator = preload("res://scripts/city/city_street_locator.gd").new()
		_street_locator.setup(level_data.get("roads", []))
	var position_: Vector3 = player.position if at == Vector3.INF else at
	var street: String = _street_locator.nearest(position_)
	if PerfCounters.enabled:
		PerfCounters.end(PerfCounters.LEVEL_NEAREST_STREET, began)
	return street

func save_progress() -> String:
	if world_save == null or not world_save.enabled:
		return "Progress saving is unavailable in this session."
	var result: Error = world_save.save_state()
	if result == OK:
		return "Progress saved."
	if result == ERR_BUSY:
		var blocker := str(world_save.checkpoint_blocker())
		return "Cannot save: " + blocker + "." if not blocker.is_empty() else "Stand on solid ground to save."
	if bool(world_save.get_status().write_blocked):
		return "Saving is paused to protect an incompatible checkpoint. Use Recover saving in Settings."
	return "Could not save. Your previous checkpoint is retained."

func return_to_original() -> void:
	_request_exit(true)

func _request_exit(to_menu: bool) -> void:
	# Never silently discard progress because the player is in combat, airborne,
	# or a checkpoint write failed. Validation sessions do not own a save slot.
	if not ready_to_play or world_save == null or not world_save.enabled:
		_finish_exit(to_menu)
		return
	if _exit_confirmation != null and _exit_confirmation.visible:
		return
	var result: Error = world_save.save_state()
	if result == OK:
		_finish_exit(to_menu)
		return
	_exit_to_menu = to_menu
	if inspector != null and inspector.active:
		inspector.leave()
	pause_exploring()
	if _exit_confirmation == null:
		_exit_confirmation = ConfirmationDialog.new()
		_exit_confirmation.title = "Progress has not been saved"
		_exit_confirmation.ok_button_text = "Leave without saving"
		_exit_confirmation.cancel_button_text = "Stay here"
		_exit_confirmation.exclusive = true
		_exit_confirmation.confirmed.connect(func(): _finish_exit(_exit_to_menu))
		add_child(_exit_confirmation)
	var reason := "A checkpoint needs solid ground and no active fight." if result == ERR_BUSY else "The checkpoint could not be written."
	if bool(world_save.get_status().write_blocked):
		reason = "Saving is paused because the old checkpoint could not be restored. Use Recover saving in Settings."
	_exit_confirmation.dialog_text = reason + "\nYour old save files are preserved. Leaving now will discard unsaved progress from this visit."
	_exit_confirmation.popup_centered(Vector2i(580, 180))

func _finish_exit(to_menu: bool) -> void:
	if to_menu:
		G.open_original_block()
	else:
		get_tree().quit()

func _on_player_offense(kind: String, at: Vector3, victim_id: String) -> void:
	if law != null:
		law.on_offense(kind, at, victim_id)

func _on_observed_offense(kind: String, at: Vector3, victim_id: String) -> void:
	if progression != null:
		progression.on_offense(kind, at, victim_id, {"witnessed": true})

func _shop_modal_changed(open: bool) -> void:
	if open:
		_suspend_phone()
		combat.cancel_player_actions()
		paused = true
		player.enabled = false
		player.velocity = Vector3.ZERO
		player.set_orbiting(false)
		_prompt.hide()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		resume_exploring()

func _update_sandbox_ui() -> void:
	if _sandbox_label == null:
		return
	var lines: Array[String] = []
	if bicycle != null:
		var bike_status: Dictionary = bicycle.get_status()
		if bool(bike_status.get("active", false)) and not bool(bike_status.get("crashed", false)):
			lines.append("BICYCLE · %d KM/H" % roundi(float(bike_status.get("speed_kmh", 0.0))))
		if not str(bike_status.get("prompt", "")).is_empty():
			lines.append(str(bike_status.prompt))
		if not str(bike_status.get("message", "")).is_empty():
			lines.append(str(bike_status.message))
	if basketball != null:
		var ball_prompt: String = basketball.interaction_prompt()
		if not ball_prompt.is_empty():
			lines.append(ball_prompt)
	if progression != null:
		lines.append(progression.hud_text())
	if law != null:
		var state: Dictionary = law.get_status()
		if int(state.get("wanted", 0)) > 0 or bool(state.get("recovering", false)):
			lines.append(str(state.get("message", "")))
	if driving != null:
		var state: Dictionary = driving.get_status()
		if bool(state.get("active", false)):
			lines.append("%s · %d MPH" % [str(state.get("gear", "N")), roundi(float(state.get("speed_mph", 0.0)))])
			var car = driving.get("vehicle")
			if is_instance_valid(car) and car.has_method("get_damage_status"):
				var damage: Dictionary = car.get_damage_status()
				lines.append("CAR %d%% · %s" % [roundi(float(damage.get("health", 100.0))), "ENGINE DISABLED" if bool(damage.get("disabled", false)) else "H Horn"])
		if not str(state.get("prompt", "")).is_empty():
			lines.append(str(state.prompt))
	_sandbox_label.text = "\n".join(lines)

func _request_police_help(at: Vector3) -> void:
	if police_assistance == null:
		return
	var result: Dictionary = incidents.report_from_phone(at) if incidents != null else police_assistance.request_help(at)
	if player.phone != null:
		player.phone.set_report_status(str(result.get("message", "Police notified.")))

func _on_bicycle_contact(contact: Dictionary) -> void:
	# Nonlethal impact and temporary fists-only retaliation, never a player
	# assault reward, armed escalation or fabricated criminal incident.
	if combat == null:
		return
	var speed := float(contact.get("relative_speed", contact.get("speed", 0.0)))
	var push: Vector3 = contact.get("impulse", Vector3.ZERO)
	if push == Vector3.ZERO and contact.get("direction") is Vector3:
		push = contact.direction * speed
	combat.knockdown_from_bicycle(contact.get("collider"), speed, push, contact)

func _on_phone_photo_captured(context: Dictionary) -> void:
	if missions != null:
		missions.on_photo_captured(context)
	if incidents != null:
		for incident in incidents.list_incidents():
			if str(incident.get("state", "")) in ["active", "ended", "reported", "responding"]:
				incidents.evaluate_photo(str(incident.id), context)

func _on_incident_report_status(status: Dictionary) -> void:
	if not bool(status.get("phone", false)):
		return
	if player != null and player.phone != null:
		player.phone.set_report_status(str(status.get("text", "Report updated.")))
