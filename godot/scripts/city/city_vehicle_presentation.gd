extends Node3D
## Single occupied-player-car presentation, independent of movement/ownership.
## setup(level), tick(delta) after driving.tick(), handle_input(event) before
## driving's input consumption. Always-process pause sync also covers menus.
const Interior := preload("res://scripts/city/city_vehicle_interior.gd")
const Models := preload("res://scripts/city/city_car_models.gd")
const AUDIO_ROOT := "res://assets/audio/"
const HORN_COOLDOWN := 0.55
var level: Node3D
var vehicle: Node3D
var driver: Puppet
var cabin: Node3D
var wheel: MeshInstance3D
var engine: AudioStreamPlayer3D
var skid: AudioStreamPlayer3D
var horn: AudioStreamPlayer3D
var horns_played := 0
var _body: MeshInstance3D
var _source_mesh: Mesh
var _glass_overrides: Dictionary = {}
var _window_triangles: Array = []
var _paused := false
var _horn_clock := 0.0
var _previous_speed := 0.0
var _skid_gain := 0.0
var _pitch := 0.85
var _disabled_property: StringName = &""
var _attached := false

func setup(owner_level: Node3D) -> void:
	level = owner_level
	name = "VehiclePresentation"
	process_mode = Node.PROCESS_MODE_ALWAYS
	if engine != null:
		return
	engine = _voice("Engine", "vehicle_engine.wav", true, 45.0, -14.0)
	skid = _voice("Tires", "vehicle_skid.wav", true, 55.0, -80.0)
	horn = _voice("Horn", "vehicle_horn.wav", false, 65.0, -8.0)

func _voice(label: String, path: String, looped: bool, reach: float, volume: float) -> AudioStreamPlayer3D:
	var voice := AudioStreamPlayer3D.new()
	voice.name = label
	voice.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
	voice.max_distance = reach
	voice.unit_size = 7.0
	voice.max_db = 0.0
	voice.volume_db = volume
	voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
	voice.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	if ResourceLoader.exists(AUDIO_ROOT + path):
		var stream := load(AUDIO_ROOT + path) as AudioStreamWAV
		if stream != null:
			stream = stream.duplicate() as AudioStreamWAV
			if looped:
				stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
				stream.loop_begin = 0
				stream.loop_end = stream.data.size() / 2
			voice.stream = stream
	add_child(voice)
	return voice

func _process(_delta: float) -> void:
	sync_pause()

func sync_pause() -> void:
	_paused = (is_inside_tree() and get_tree().paused) or (is_instance_valid(level) and level.get("paused") == true)
	for voice in [engine, skid, horn]:
		if is_instance_valid(voice):
			voice.stream_paused = _paused

func tick(delta: float) -> void:
	if not is_instance_valid(level):
		return
	var driving = level.get("driving")
	var wanted: Node3D = driving.get("vehicle") if is_instance_valid(driving) and driving.get("active") == true else null
	# Godot treats a freed Object reference as null in equality comparisons.
	# Keep attachment lifecycle state separately so freeing the car still hides
	# its independent driver and stops pending spatial playback.
	if not is_instance_valid(vehicle):
		if _attached:
			detach()
		if is_instance_valid(wanted):
			attach(wanted)
	elif not is_instance_valid(wanted):
		detach()
	elif wanted != vehicle:
		attach(wanted)
	sync_pause()
	if not is_instance_valid(vehicle) or _paused or delta <= 0.0:
		return
	global_transform = vehicle.global_transform
	_horn_clock = maxf(0.0, _horn_clock - delta)
	var speed := absf(float(vehicle.get("speed")))
	var acceleration := clampf((speed - _previous_speed) / maxf(delta, 0.001), 0.0, 7.0)
	_previous_speed = speed
	var controls: Dictionary = {}
	if is_instance_valid(driving):
		if driving.has_method("current_controls"):
			controls = driving.current_controls()
		else:
			# Older isolated fixtures predate the public telemetry contract.
			var fixture_controls = driving.get("_controls")
			if fixture_controls is Dictionary:
				controls = fixture_controls
	var load_amount := maxf(acceleration / 7.0, float(controls.get("throttle", 0.0)) * 0.65)
	_pitch = lerpf(_pitch, clampf(0.85 + speed * 0.045 + load_amount * 0.22, 0.85, 2.15), 1.0 - exp(-delta * 5.0))
	engine.pitch_scale = _pitch
	engine.volume_db = -16.0 + load_amount * 4.0 + minf(speed / 25.0, 1.0) * 3.0
	var drift: Vector3 = vehicle.get("drive_velocity")
	var lateral := absf(drift.dot(vehicle.global_basis.x))
	var slide := clampf((lateral - 0.8) / 4.0, 0.0, 1.0)
	if bool(controls.get("handbrake", false)) and speed > 3.0:
		slide = maxf(slide, clampf((speed - 3.0) / 10.0, 0.0, 1.0))
	if speed < 2.0 or vehicle.get("drive_airborne") == true:
		slide = 0.0
	_skid_gain = move_toward(_skid_gain, slide, delta * (5.0 if slide > _skid_gain else 3.0))
	skid.volume_db = linear_to_db(maxf(0.0001, _skid_gain)) - 12.0
	skid.pitch_scale = 0.85 + minf(speed / 35.0, 0.4)
	if _skid_gain > 0.01 and not skid.playing:
		skid.play()
	elif _skid_gain <= 0.001:
		skid.stop()
	var disabled: bool = not _disabled_property.is_empty() and vehicle.get(_disabled_property) == true
	if disabled:
		engine.stop()
	elif not engine.playing and engine.stream != null:
		engine.play()
	_pose(float(vehicle.get("drive_steer")))

func attach(car: Node3D) -> void:
	if car == vehicle and is_instance_valid(vehicle):
		return
	detach()
	if not is_instance_valid(car) or engine == null:
		return
	vehicle = car
	_attached = true
	for property in car.get_property_list():
		if str(property.name) in ["disabled", "body_disabled", "drive_disabled"]:
			_disabled_property = StringName(property.name)
			break
	global_transform = car.global_transform
	_previous_speed = absf(float(car.get("speed")))
	var kind := str(car.get("prototype_kind"))
	if not Models.has_kind(kind):
		return
	var model: Node3D = car.get("model")
	_body = model.get_node_or_null("Body") as MeshInstance3D if is_instance_valid(model) else null
	if _body != null and _body.mesh != null:
		_source_mesh = _body.mesh
		for surface in _source_mesh.get_surface_count():
			var source_material := _source_mesh.surface_get_material(surface)
			if source_material != null and source_material.resource_name == "city_vehicle_glass":
				_window_triangles.append_array(Interior._triangles(_source_mesh.surface_get_arrays(surface)))
		_body.mesh = Interior.open_windows(_source_mesh, kind)
		for surface in _body.mesh.get_surface_count():
			var material := _body.mesh.surface_get_material(surface)
			if material is StandardMaterial3D and material.resource_name == "city_vehicle_glass":
				_glass_overrides[surface] = _body.get_surface_override_material(surface)
				var glass := material.duplicate() as StandardMaterial3D
				glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				glass.albedo_color = Color(0.22, 0.30, 0.34, 0.17)
				glass.cull_mode = BaseMaterial3D.CULL_BACK
				glass.metallic = 0.0
				_body.set_surface_override_material(surface, glass)
	if driver == null:
		driver = Cast.person("two_pack", self)
		driver.g.name = "Seated2Pack"
	var hip := seat_local_point(kind)
	driver.g.scale = Vector3.ONE * 0.92
	driver.g.position = hip - Vector3.UP * (driver.body_y * 0.92)
	driver.g.rotation = Vector3.ZERO
	driver.g.visible = true
	for leg in driver.legs:
		# This rig has no knee joints. Compact the entirely enclosed lower
		# limbs and lift their shoe soles above the unchanged chassis floor.
		leg.scale = Vector3(0.90, 0.50, 0.55)
		leg.position.y = driver.body_y + 0.05
	_build_cabin(hip, kind)
	_pose(0.0)
	engine.position = Vector3(0, 0.55, 1.1)
	skid.position = Vector3(0, 0.3, -0.8)
	horn.position = Vector3(0, 0.7, 1.2)
	sync_pause()
	var disabled: bool = not _disabled_property.is_empty() and vehicle.get(_disabled_property) == true
	if not _paused and not disabled and engine.stream != null:
		engine.play()

static func seat_local_point(kind: String) -> Vector3:
	return Interior.seat_local_point(kind)

func _pose(steer: float) -> void:
	if driver == null or not is_instance_valid(driver.g):
		return
	var turn := clampf(steer, -1.0, 1.0)
	driver.pose({"armR": [-1.35 - turn * 0.13, -0.14], "armL": [-1.35 + turn * 0.13, -0.14], "lean": -0.10, "look": -turn * 0.12})
	# Existing clay rig has rigid limbs (no knee bones). Feet extend forward
	# into the enclosed footwell; the original recognizable upper body remains.
	for leg in driver.legs:
		leg.rotation.x = -PI * 0.5
	if is_instance_valid(wheel):
		wheel.rotation.z = turn * 0.5

func _build_cabin(hip: Vector3, kind: String) -> void:
	cabin = Node3D.new()
	cabin.name = "OccupiedInterior"
	add_child(cabin)
	var fabric := StandardMaterial3D.new()
	fabric.albedo_color = Color("303137")
	fabric.roughness = 0.95
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	builder.set_material(fabric)
	for x in [hip.x, -hip.x]:
		for piece in [[Vector3(0.54, 0.14, 0.60), Vector3(x, hip.y - 0.05, hip.z + 0.12)],
			[Vector3(0.54, 0.63, 0.12), Vector3(x, hip.y + 0.26, hip.z - 0.17)]]:
			var box := BoxMesh.new()
			box.size = piece[0]
			builder.append_from(box, 0, Transform3D(Basis.IDENTITY, piece[1]))
	var bounds := Interior.cabin_bounds(kind)
	# Dark carpet and dashboard remain private to this occupied instance.
	# Neither changes the physical hull or removes the opaque chassis floor.
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(bounds.size.x, 0.035, bounds.size.z)
	builder.append_from(floor_mesh, 0, Transform3D(Basis.IDENTITY,
		Vector3(0, 0.285, bounds.get_center().z)))
	var dashboard := BoxMesh.new()
	dashboard.size = Vector3(bounds.size.x, 0.10, 0.25)
	builder.append_from(dashboard, 0, Transform3D(Basis.IDENTITY,
		Vector3(0, Interior.deck_height(kind, bounds.end.z) + 0.035, bounds.end.z + 0.02)))
	var seats := MeshInstance3D.new()
	seats.mesh = builder.commit()
	cabin.add_child(seats)
	wheel = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.145
	ring.outer_radius = 0.175
	ring.rings = 12
	ring.ring_segments = 6
	wheel.mesh = ring
	wheel.material_override = fabric
	cabin.add_child(wheel)
	wheel.position = hip + Vector3(0, 0.48, 0.55)
	wheel.rotation.x = 1.15

func handle_input(event: InputEvent) -> bool:
	if not event is InputEventKey or (event.keycode != KEY_H and event.physical_keycode != KEY_H):
		return false
	if not is_instance_valid(vehicle):
		return false
	if event.pressed and not event.echo:
		honk()
	return true

func honk() -> bool:
	sync_pause()
	if not is_instance_valid(vehicle) or _paused or _horn_clock > 0.0 or horn == null or horn.stream == null:
		return false
	horn.play()
	_horn_clock = HORN_COOLDOWN
	horns_played += 1
	return true

func get_occupant_hit_zones(car: Node3D) -> Array[Dictionary]:
	if not is_instance_valid(vehicle) or car != vehicle or driver == null or not driver.g.visible:
		return []
	return [{"center": driver.head.global_transform * Vector3(0, driver.hy, 0), "radius": 0.18, "part": "head", "actor_id": "player"},
		{"center": driver.body.global_transform * Vector3(0, 0.27, 0), "radius": 0.23, "part": "chest", "actor_id": "player"}]

## Combat must ALSO establish first-world-hit ownership; this only verifies
## that its ray to a virtual seated target crosses a real authored window.
## Buildings, other cars and low chassis remain cover in the caller's raycast.
func ray_hits_window(car: Node3D, from: Vector3, to: Vector3) -> bool:
	if car != vehicle or not is_instance_valid(_body) or not from.is_finite() or not to.is_finite():
		return false
	var inverse := _body.global_transform.affine_inverse()
	var a: Vector3 = inverse * from
	var b: Vector3 = inverse * to
	for triangle in _window_triangles:
		if Geometry3D.segment_intersects_triangle(a, b, triangle[0].p, triangle[1].p, triangle[2].p) != null:
			return true
	return false

func detach() -> void:
	for voice in [engine, skid, horn]:
		if is_instance_valid(voice):
			voice.stop()
	if is_instance_valid(_body) and _source_mesh != null:
		_body.mesh = _source_mesh
		for surface in _glass_overrides:
			_body.set_surface_override_material(int(surface), _glass_overrides[surface])
	_glass_overrides.clear()
	_window_triangles.clear()
	_source_mesh = null
	_body = null
	vehicle = null
	_attached = false
	if driver != null and is_instance_valid(driver.g):
		driver.g.visible = false
	if is_instance_valid(cabin):
		cabin.free()
	cabin = null
	wheel = null
	_horn_clock = 0.0
	_previous_speed = 0.0
	_skid_gain = 0.0
	_pitch = 0.85
	_disabled_property = &""

func reset() -> void:
	detach()

func get_status() -> Dictionary:
	return {"attached": is_instance_valid(vehicle), "driver_visible": driver != null and is_instance_valid(driver.g) and driver.g.visible,
		"voices": 3 if engine != null else 0, "paused": _paused, "horns": horns_played, "engine_pitch": _pitch, "skid_gain": _skid_gain}

func _exit_tree() -> void:
	detach()
