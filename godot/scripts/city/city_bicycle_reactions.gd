extends Node3D
## Small social reactions only. No combat, threat, health, or law hooks.
const MAX_NEARBY := 12
const MAX_TASKS := 12
const SCAN_INTERVAL := 0.2
const SIDESTEP_SPEED := 2.0
const TASK_TIMEOUT := 8.0
const COMPLAINTS := ["Watch where you're riding!", "Hey! Give people some room!", "Slow down! This is a sidewalk!", "Careful with that bike!"]

var level: Node3D
var bicycle: CharacterBody3D
var crowd: Node3D
var _clock := 0.0
var _next_scan := 0.0
var _tasks: Dictionary = {}
var _cooldowns: Dictionary = {}
var _labels: Array[Dictionary] = []
var scans := 0
var candidates_checked := 0
var sidesteps := 0
var complaints := 0

func setup(owner_level: Node3D, bike: CharacterBody3D) -> void:
	level = owner_level
	bicycle = bike
	var npcs := level.get("npcs") as Node3D
	crowd = npcs.get("crowd") as Node3D if npcs != null else level.get("crowd") as Node3D
	name = "BicycleReactions"
	bicycle.avoidance_requested.connect(_avoid_nearby)
	bicycle.pedestrian_contact.connect(_on_contact)

func tick(delta: float) -> void:
	if level == null or bool(level.get("paused")) or get_tree().paused:
		return
	_clock += delta
	for id in _tasks.keys():
		var task: Dictionary = _tasks[id]
		if not _valid_task(task):
			_release(id)
			continue
		if _clock >= float(task.deadline):
			_resume_displaced(task)
			_release(id)
			continue
		_step(task, delta)
		if bool(task.get("done", false)):
			_release(id)
	for id in _cooldowns.keys():
		if float(_cooldowns[id]) < _clock:
			_cooldowns.erase(id)
	for i in range(_labels.size() - 1, -1, -1):
		var row: Dictionary = _labels[i]
		if _clock >= float(row.until) or not is_instance_valid(row.body):
			row.label.queue_free()
			_labels.remove_at(i)
		else:
			row.label.global_position = row.body.global_position + Vector3.UP * 2.25

func _avoid_nearby(at: Vector3, motion: Vector3) -> void:
	if _clock < _next_scan or motion.length_squared() < 0.64:
		return
	_next_scan = _clock + SCAN_INTERVAL
	var direction := motion.normalized()
	var reach := clampf(motion.length() * 0.5 + 1.2, 1.8, 5.2)
	var sphere := SphereShape3D.new()
	sphere.radius = reach * 0.5 + 0.9
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform.origin = at + direction * (reach * 0.5) + Vector3.UP * 0.9
	query.collision_mask = 8
	var nearby := get_world_3d().direct_space_state.intersect_shape(query, MAX_NEARBY)
	scans += 1
	for hit in nearby:
		candidates_checked += 1
		var body := hit.collider as Node3D
		if body == null:
			continue
		var offset := body.global_position - at
		var along := Vector3(offset.x, 0.0, offset.z).dot(direction)
		if along < -0.3 or along > reach:
			continue
		var nearest := at + direction * along
		if Vector2(offset.x, offset.z).length_squared() > 0.01 and Vector2(body.global_position.x - nearest.x, body.global_position.z - nearest.z).length() > 1.1:
			continue
		if absf(offset.y) > 0.75:
			continue
		_begin(body, at, direction, false)

func _on_contact(contact: Dictionary) -> void:
	var body := contact.get("collider") as Node3D
	if body == null:
		return
	complaints += 1
	var text := str(COMPLAINTS[(complaints - 1) % COMPLAINTS.size()])
	if body.has_method("speak"):
		body.speak(text, 3.0)
	else:
		_speech(body, text)
	_begin(body, bicycle.global_position, contact.get("direction", Vector3.FORWARD), true)
	if _tasks.has(body.get_instance_id()):
		var task: Dictionary = _tasks[body.get_instance_id()]
		task.angry = true
		task.until = maxf(float(task.until), _clock + 2.0)

func _begin(body: Node3D, threat: Vector3, direction: Vector3, angry: bool) -> void:
	var id := body.get_instance_id()
	if _tasks.has(id) or _tasks.size() >= MAX_TASKS or (not angry and _cooldowns.has(id)):
		return
	var index := int(body.get_meta("city_crowd_index", -1))
	var resident: Dictionary = {}
	var revision := -1
	var old_yaw := 0.0
	if index >= 0:
		if crowd == null or index >= crowd.residents.size():
			return
		resident = crowd.residents[index]
		if resident.get("dead", false) or resident.get("panic", false) or resident.get("combat_controlled", false) or resident.get("identity_unplaced", false) or resident.has("bicycle_rejoin"):
			return
		# Seated/porch people stay on their safely placed seat or deck.
		if int(resident.pose) != 0 or str(resident.activity) == "porch":
			return
		old_yaw = float(resident.yaw)
	elif body.has_method("set_target") and body.has_method("walking_ground_at"):
		if bool(body.get("dead")) or not bool(body.get("enabled")) or bool(body.get("combat_override")):
			return
		revision = int(body.get("target_revision"))
		old_yaw = float(body.get("yaw"))
	else:
		return
	var side := Vector3(direction.z, 0.0, -direction.x).normalized()
	if side.dot(body.global_position - threat) < 0.0:
		side = -side
	var task := {"body": body, "index": index, "home": body.global_position, "yaw": old_yaw,
		"revision": revision, "goal": body.global_position, "mode": "out", "until": _clock + 1.1,
		"angry": angry, "threat": threat, "done": false, "deadline": _clock + TASK_TIMEOUT}
	var found := false
	for sign_value in [1.0, -1.0]:
		var offset := side * float(sign_value) * 1.15
		var wanted := body.global_position + offset
		var grounded := _safe_ground(wanted, body.global_position.y)
		if grounded.is_empty():
			continue
		var goal: Vector3 = grounded.position
		if _clear_motion(task, goal):
			task.goal = goal
			found = true
			break
	if not found:
		return
	if index >= 0:
		resident.bicycle_avoiding = true
	else:
		body.set("bicycle_override", true)
		var detail = body.get("render_detail")
		if detail != null:
			detail.force_full()
	_tasks[id] = task
	sidesteps += 1

func _valid_task(task: Dictionary) -> bool:
	if not is_instance_valid(task.body):
		return false
	if int(task.index) >= 0:
		if crowd == null or int(task.index) >= crowd.residents.size():
			return false
		var resident: Dictionary = crowd.residents[int(task.index)]
		return not resident.get("dead", false) and not resident.get("panic", false) and not resident.get("combat_controlled", false)
	return not bool(task.body.get("dead")) and bool(task.body.get("enabled")) and not bool(task.body.get("combat_override")) \
		and int(task.body.get("target_revision")) == int(task.revision)

func _step(task: Dictionary, delta: float) -> void:
	var body: Node3D = task.body
	var at := body.global_position
	if str(task.mode) == "hold":
		if bool(task.angry):
			var face: Vector3 = bicycle.global_position - at
			if face.length_squared() > 0.01:
				_pose(task, atan2(face.x, face.z), false, delta)
		if _clock < float(task.until):
			return
		if int(task.index) < 0:
			task.done = true # Existing actor target/revision was never replaced.
			return
		task.mode = "return"
		task.goal = task.home
	var offset: Vector3 = task.goal - at
	if offset.length() < 0.035:
		if str(task.mode) == "return":
			_set_position(task, task.home)
			crowd.residents[int(task.index)].yaw = float(task.yaw)
			_pose(task, float(task.yaw), false, delta)
			task.done = true
		else:
			task.mode = "hold"
			task.until = maxf(float(task.until), _clock + (1.6 if bool(task.angry) else 0.8))
		return
	var next := at.move_toward(task.goal, delta * SIDESTEP_SPEED)
	var ground := _safe_ground(next, at.y)
	if ground.is_empty():
		if str(task.mode) == "out":
			task.mode = "hold"
			task.until = _clock + 0.8
		return
	next = ground.position
	if not _clear_motion(task, next):
		if str(task.mode) == "out":
			task.mode = "hold"
			task.until = _clock + 0.8
		return
	_set_position(task, next)
	_pose(task, atan2(offset.x, offset.z), true, delta)

func _set_position(task: Dictionary, at: Vector3) -> void:
	var body: Node3D = task.body
	if int(task.index) >= 0:
		var index := int(task.index)
		var previous: Vector3 = crowd.residents[index].position
		crowd._relocate(index, previous, at, true)
	body.global_position = at

func _pose(task: Dictionary, heading: float, moving: bool, delta: float) -> void:
	if int(task.index) >= 0:
		var resident: Dictionary = crowd.residents[int(task.index)]
		resident.yaw = rotate_toward(float(resident.yaw), heading, delta * 7.0)
		crowd._apply_transform(int(task.index), "run" if moving else "idle")
	else:
		var actor: Node3D = task.body
		actor.set("yaw", rotate_toward(float(actor.get("yaw")), heading, delta * 7.0))
		actor.set("moving", moving)
		var puppet: Puppet = actor.get("puppet")
		puppet.g.rotation.y = float(actor.get("yaw"))
		puppet.phase += delta * 7.0 if moving else 0.0
		puppet.pose({"walk": 0.38 if moving else 0.0, "armR": [-0.6, 0.25] if bool(task.angry) else null,
			"mouth": 0.5 if bool(task.angry) else 0.0})

func _clear_motion(task: Dictionary, goal: Vector3) -> bool:
	var body := task.body as CollisionObject3D
	if body == null:
		return false
	var shape: Shape3D
	var offset := Vector3.UP * 0.9
	if int(task.index) >= 0:
		var resident: Dictionary = crowd.residents[int(task.index)]
		shape = resident.get("body_shape", crowd.get("_shape"))
		offset = resident.get("body_shape_offset", offset)
	else:
		var capsule: CollisionShape3D = body.get("capsule")
		shape = capsule.shape
		offset = capsule.position
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1 | 2 | 4 | 8 | 16
	query.margin = 0.015
	query.exclude = [body.get_rid()]
	# Lift the query clear of terrain contact; feet are checked separately.
	# Crowd capsules may begin exactly on their surveyed floor plane.
	offset += Vector3.UP * 0.035
	query.transform.origin = body.global_position + offset
	query.motion = goal - body.global_position
	var space := get_world_3d().direct_space_state
	var fractions := space.cast_motion(query)
	if fractions.size() < 2 or fractions[0] < 0.999:
		return false
	query.transform.origin = goal + offset
	query.motion = Vector3.ZERO
	return space.intersect_shape(query, 1).is_empty()

func _safe_ground(at: Vector3, height: float) -> Dictionary:
	var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.45, at - Vector3.UP * 0.45, 1 | 2)
	var ground := get_world_3d().direct_space_state.intersect_ray(ray)
	if ground.is_empty() or ground.normal.y < 0.75 or absf(float(ground.position.y) - height) > 0.22:
		return {}
	return {"position": ground.position + Vector3.UP * 0.012}

func _release(id: int) -> void:
	var task: Dictionary = _tasks[id]
	if int(task.index) >= 0 and is_instance_valid(crowd) and int(task.index) < crowd.residents.size():
		crowd.residents[int(task.index)].erase("bicycle_avoiding")
	elif is_instance_valid(task.body):
		task.body.set("bicycle_override", false)
		task.body.set("moving", false)
	_tasks.erase(id)
	_cooldowns[id] = _clock + 2.0

func _resume_displaced(task: Dictionary) -> void:
	if int(task.index) < 0 or crowd == null:
		return # Articulated actors resume their unchanged destination directly.
	var resident: Dictionary = crowd.residents[int(task.index)]
	# Release the capped avoidance task without teleporting through an obstruction.
	# The ordinary walker cadence retries this short join at walking speed, using
	# its normal collision sweep. Original path/progress/activity remain intact.
	if str(resident.activity) == "walking" and resident.position.distance_to(task.home) > 0.035:
		resident.bicycle_rejoin = task.home
	resident.yaw = float(task.yaw)
	crowd._apply_transform(int(task.index), "idle")

func _speech(body: Node3D, text: String) -> void:
	# Tiny bounded label pool; never instantiate actors just to show a complaint.
	if _labels.size() >= 4:
		_labels[0].label.queue_free()
		_labels.remove_at(0)
	var label := Label3D.new()
	label.text = text
	label.font_size = 28
	label.pixel_size = 0.0035
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.visibility_range_end = 22.0
	add_child(label)
	label.global_position = body.global_position + Vector3.UP * 2.25
	_labels.append({"body": body, "label": label, "until": _clock + 3.0})

func get_status() -> Dictionary:
	return {"active": _tasks.size(), "scans": scans, "candidates_checked": candidates_checked,
		"sidesteps": sidesteps, "complaints": complaints, "max_candidates": MAX_NEARBY}
