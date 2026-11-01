extends Node3D
## Visual-only moving fleet LOD. Physical vehicle bodies stay with CityVehicle.
## One cached merged far mesh/batch per kind replaces individual body/wheel
## submissions. Damaged and imported police models retain their exact geometry.
const Models := preload("res://scripts/city/city_car_models.gd")
const ENTER_DISTANCE := 55.0
const EXIT_DISTANCE := 45.0
const HIDE_DISTANCE := 220.0
const REFRESH_INTERVAL := .20
const INITIAL_CAPACITY := 32
var enabled: bool = not OS.get_cmdline_user_args().has("--no-vehicle-render-lod")
var vehicles: Array[Node3D] = []
var batches: Dictionary = {}
var _manager: Node3D
var _clock := 0.0
var transitions := 0
var pose_uploads := 0

static func paint_tint(encoded: Color) -> Color:
	# StandardMaterial albedo_color is source_color; MultiMesh COLOR is raw.
	# Keep catalog vertex shade multipliers linear and convert only the paint.
	# Compatibility shades in sRGB, whereas Forward+/Mobile shade in linear.
	return encoded if RenderingServer.get_current_rendering_method() == "gl_compatibility" else encoded.srgb_to_linear()

static func ensure(manager: Node3D) -> Node3D:
	var existing := manager.get_node_or_null("MovingVehicleRenderLOD") as Node3D
	if existing != null:
		return existing
	var renderer: Node3D = load("res://scripts/city/city_vehicle_render_lod.gd").new()
	renderer.name = "MovingVehicleRenderLOD"
	renderer._manager = manager
	manager.add_child(renderer)
	return renderer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	top_level = true
	global_transform = Transform3D.IDENTITY

func _viewer_position() -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		return camera.global_position
	var level: Node3D = _manager.get("level") if is_instance_valid(_manager) else null
	var player: Node3D = level.get("player") if is_instance_valid(level) else null
	return player.global_position if is_instance_valid(player) else Vector3.ZERO

func _process(delta: float) -> void:
	_clock += delta
	if _clock < REFRESH_INTERVAL:
		return
	_clock = 0.0
	refresh(_viewer_position())

func register_vehicle(car: Node3D) -> void:
	if not vehicles.has(car):
		vehicles.append(car)
	refresh_vehicle(car)

func unregister_vehicle(car: Node3D) -> void:
	_remove_slot(car)
	vehicles.erase(car)

func refresh(center: Vector3) -> void:
	for car in vehicles:
		if is_instance_valid(car):
			refresh_vehicle(car,center)

func refresh_vehicle(car: Node3D, center := Vector3.INF) -> void:
	if not is_instance_valid(car.model):
		return
	if not center.is_finite():
		center = _viewer_position()
	var distance := car.global_position.distance_squared_to(center)
	# An occupied car keeps its exact model (steered wheels, damage) even when an
	# inspector or overview camera is far away.
	var forced: bool = car.get("force_detailed") == true
	var visible_now := forced or distance < HIDE_DISTANCE*HIDE_DISTANCE
	var eligible: bool = enabled and not forced and not car.is_police and car.flat_tires.is_empty() and Models.has_kind(car.prototype_kind)
	var cutoff := EXIT_DISTANCE if car._render_lod_active else ENTER_DISTANCE
	var use_batch: bool = visible_now and eligible and distance > cutoff*cutoff
	if use_batch:
		if not car._render_lod_active:
			_add_slot(car)
		car.model.visible = false
		update_vehicle(car)
	else:
		var was_batched: bool = car._render_lod_active
		_remove_slot(car)
		car.model.visible = visible_now
		if was_batched and visible_now:
			car._update_wheels()

func _batch(kind: String) -> Dictionary:
	if batches.has(kind):
		return batches[kind]
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = Models.prototype(kind).far_parked
	multi.instance_count = INITIAL_CAPACITY
	multi.visible_instance_count = 0
	var node := MultiMeshInstance3D.new()
	node.name = "MovingFar_"+kind
	node.multimesh = multi
	# Close individual models retain their normal shadows; match parked far LOD.
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	var members: Array[Node3D] = []
	var poses: Array[Transform3D] = []
	var colors: Array[Color] = []
	var batch := {"node":node,"multi":multi,"members":members,"poses":poses,"colors":colors}
	batches[kind] = batch
	return batch

func _add_slot(car: Node3D) -> void:
	var kind: String = car.prototype_kind
	var batch := _batch(kind)
	var members: Array[Node3D] = batch.members
	var multi: MultiMesh = batch.multi
	if members.size() >= multi.instance_count:
		multi.instance_count *= 2
		for i in members.size():
			multi.set_instance_transform(i,batch.poses[i])
			multi.set_instance_color(i,batch.colors[i])
	car._render_lod_slot = members.size()
	car._render_lod_key = kind
	car._render_lod_active = true
	members.append(car)
	batch.poses.append(car.global_transform)
	batch.colors.append(paint_tint(Color(str(car.paint_color))))
	multi.set_instance_transform(car._render_lod_slot,car.global_transform)
	multi.set_instance_color(car._render_lod_slot,batch.colors[-1])
	multi.visible_instance_count = members.size()
	batch.node.visible = true
	transitions += 1

func _remove_slot(car: Node3D) -> void:
	if not car._render_lod_active:
		return
	var batch: Dictionary = batches[car._render_lod_key]
	var members: Array[Node3D] = batch.members
	var multi: MultiMesh = batch.multi
	var slot: int = car._render_lod_slot
	var last := members.size()-1
	if slot != last:
		var moved: Node3D = members[last]
		members[slot] = moved
		moved._render_lod_slot = slot
		batch.poses[slot] = moved.global_transform
		batch.colors[slot] = batch.colors[last]
		multi.set_instance_transform(slot,batch.poses[slot])
		multi.set_instance_color(slot,batch.colors[slot])
	members.pop_back()
	batch.poses.pop_back()
	batch.colors.pop_back()
	multi.visible_instance_count = members.size()
	batch.node.visible = not members.is_empty()
	car._render_lod_active = false
	car._render_lod_slot = -1
	car._render_lod_key = ""
	transitions += 1

func update_vehicle(car: Node3D) -> void:
	if car._render_lod_active:
		var batch: Dictionary = batches[car._render_lod_key]
		var slot: int = car._render_lod_slot
		var pose: Transform3D = car.global_transform
		if batch.poses[slot].is_equal_approx(pose):
			return
		batch.poses[slot] = pose
		batch.multi.set_instance_transform(slot,pose)
		pose_uploads += 1

func get_status() -> Dictionary:
	var batched := 0
	var active_batches := 0
	var submitted_surfaces := 0
	for batch in batches.values():
		var count: int = batch.members.size()
		batched += count
		if count > 0:
			active_batches += 1
			submitted_surfaces += batch.multi.mesh.get_surface_count()
	return {"enabled":enabled,"registered":vehicles.size(),"batched":batched,
		"active_batches":active_batches,"batch_surfaces":submitted_surfaces,
		"transitions":transitions,"pose_uploads":pose_uploads,
		"enter_distance":ENTER_DISTANCE,"exit_distance":EXIT_DISTANCE,"hide_distance":HIDE_DISTANCE}
