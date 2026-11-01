extends "res://scripts/city/city_npc_actor.gd"
const ModularPeople := preload("res://scripts/city/city_modular_people.gd")
const Appearance := preload("res://scripts/city/city_population_appearance.gd")
## A named adult with a daily destination; the provider owns route selection and LOD.
## Physical movement remains the same forward-only, collision-tested actor movement.

var routine: Dictionary = {}
var activity := "home"
var destination_label := "Home"
var route_points: Array[Vector3] = []
var route_cursor := 0
var physical := true
var routine_enabled := true
var schedule_transitions := 0
var route_completed := false
var _visual_meshes: Array[GeometryInstance3D] = []
var _fade := -1.0
var arrival_fade := 0.0
var recovery_points: Array[Vector3] = []
var recovery_cursor := 0
var recovery_wait := 0.0
var recovery_retry := 0.0
var recovery_count := 0
var needs_replan := false
var _recovery_hold := 0.0

func build_resident(owner_level: Node3D, definition: Dictionary) -> void:
	routine = definition
	# Reuse the tested speech/body setup, then bind a unique adult appearance.
	super.build(owner_level, str(definition.id), "mama", str(definition.name))
	puppet.g.free()
	puppet = Puppet.new()
	puppet.id = actor_id
	puppet.H = float(definition.get("appearance", {}).get("h", 1.7))
	puppet.g = ModularPeople.rig(actor_id, Appearance.modular_index(actor_id, definition.get("appearance", {})), puppet.H)
	add_child(puppet.g)
	puppet.bind()
	_collect_meshes(puppet.g)
	capsule.shape.height = puppet.H - 0.10
	capsule.position.y = capsule.shape.height * 0.5 + 0.08
	_speech_label.position.y = puppet.H + 0.78
	speed = float(definition.get("speed", 1.15))

func _collect_meshes(node: Node) -> void:
	if node is GeometryInstance3D:
		_visual_meshes.append(node)
	for child in node.get_children():
		_collect_meshes(child)

func _setup_render_detail() -> void:
	super._setup_render_detail()
	if render_detail != null:
		render_detail.set_fade(maxf(0.0, _fade))

func set_distance_fade(distance: float) -> void:
	# Finish fading before the physics activation boundary. Hysteresis in the
	# provider then changes representation while the puppet is fully invisible.
	var fade := maxf(smoothstep(70.0, 90.0, distance), arrival_fade)
	if fade == _fade or (fade > 0.0 and fade < 1.0 and absf(fade - _fade) < 0.005):
		return
	_fade = fade
	if render_detail != null:
		render_detail.set_fade(fade)
	for mesh in _visual_meshes:
		mesh.visible = fade < 0.999
		mesh.transparency = fade

func assign_route(points: Array[Vector3], next_activity: String, label: String) -> void:
	route_points = points.duplicate()
	route_cursor = 0
	activity = next_activity
	destination_label = label
	schedule_transitions += 1
	route_completed = route_points.is_empty()
	has_target = false
	manual_target = true
	recovery_points.clear()
	recovery_wait = 0.0
	needs_replan = false

func begin_recovery(points: Array[Vector3], resume_cursor: int, hold := 0.0) -> void:
	recovery_points = points.duplicate()
	recovery_cursor = 0
	route_cursor = resume_cursor
	_recovery_hold = hold
	has_target = false
	blocked = false
	blocked_seconds = 0.0
	recovery_retry = 1.5
	recovery_count += 1

func tick(delta: float) -> void:
	if has_meta("combat_controlled") or not enabled or not physical:
		return
	arrival_fade = maxf(0.0, arrival_fade - delta * 2.5)
	recovery_retry = maxf(0.0, recovery_retry - delta)
	if routine_enabled and not recovery_points.is_empty():
		while recovery_cursor < recovery_points.size() and global_position.distance_to(recovery_points[recovery_cursor]) < 0.16:
			recovery_cursor += 1
		if recovery_cursor < recovery_points.size():
			if not has_target:
				set_target(recovery_points[recovery_cursor])
		else:
			recovery_points.clear()
			has_target = false
			recovery_wait = _recovery_hold
	elif recovery_wait > 0.0 or needs_replan:
		recovery_wait = maxf(0.0, recovery_wait - delta)
		has_target = false
	elif routine_enabled:
		while route_cursor < route_points.size() and global_position.distance_to(route_points[route_cursor]) < 0.20:
			route_cursor += 1
		if route_cursor < route_points.size():
			if not has_target:
				set_target(route_points[route_cursor])
		else:
			route_completed = true
			has_target = false
	else:
		has_target = false
	super.tick(delta)
	# A sleeping resident is represented at their home frontage; no invented
	# traversable interior, disappearing body, or teleport through a locked door.
	if _pose_updated and activity == "sleep" and route_completed and not moving:
		puppet.pose({"nod": 0.22, "lean": 0.035})

func get_status() -> Dictionary:
	var result: Dictionary = super.get_status()
	result.merge({"name": display_name, "activity": activity, "destination": destination_label,
		"physical": physical, "route_cursor": route_cursor, "route_size": route_points.size(),
		"route_completed": route_completed, "schedule_transitions": schedule_transitions, "fade": _fade,
		"recovery_count": recovery_count, "recovering": not recovery_points.is_empty(), "needs_replan": needs_replan})
	return result
