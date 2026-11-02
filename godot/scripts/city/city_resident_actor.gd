extends "res://scripts/city/city_npc_actor.gd"
const ModularPeople := preload("res://scripts/city/city_modular_people.gd")
const Appearance := preload("res://scripts/city/city_population_appearance.gd")
const LocalActivity := preload("res://scripts/city/city_resident_activity.gd")
## A named adult with a daily destination; the provider owns route selection and LOD.
## Physical movement remains the same forward-only, collision-tested actor movement.

var routine: Dictionary = {}
var activity := "home"
var destination_label := "Home"
var destination_site: Dictionary = {}
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
var local_activity: Dictionary = {"phase": "travelling", "elapsed": 0.0, "home_path": []}
var social_partner: Node3D
var social_remaining := 0.0
var social_cooldown := 0.0

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

func assign_route(points: Array[Vector3], next_activity: String, label: String, site: Dictionary = {}) -> void:
	social_partner = null
	social_remaining = 0.0
	local_activity = {"phase": "travelling", "elapsed": 0.0, "home_path": []}
	route_points = points.duplicate()
	route_cursor = 0
	activity = next_activity
	destination_label = label
	destination_site = site
	schedule_transitions += 1
	route_completed = route_points.is_empty()
	has_target = false
	manual_target = true
	recovery_points.clear()
	recovery_wait = 0.0
	needs_replan = false

func begin_local_greeting(partner: Node3D, reply: bool) -> void:
	social_partner = partner
	social_remaining = 3.5
	social_cooldown = 45.0 + float(posmod(actor_id.hash(), 16))
	var first_name: String = str(partner.display_name).get_slice(" ", 0)
	speak(("You too, %s." if reply else "Good to see you, %s.") % first_name, 3.0)

func _update_local_greeting(delta: float) -> void:
	social_cooldown = maxf(0.0, social_cooldown - delta)
	if social_remaining <= 0.0:
		return
	if not LocalActivity.available(self) or not is_instance_valid(social_partner) or not LocalActivity.available(social_partner) or not social_partner.route_completed or social_partner.has_target or social_partner.global_position.distance_squared_to(global_position) > 4.0 * 4.0:
		social_remaining = 0.0
		social_partner = null
		return
	social_remaining = maxf(0.0, social_remaining - delta)
	var toward: Vector3 = social_partner.global_position - global_position
	yaw = rotate_toward(yaw, atan2(toward.x, toward.z), delta * 2.5)
	puppet.g.rotation.y = yaw

func assign_activity_route(points: Array[Vector3]) -> void:
	# A local stroll is not a timetable change. Keep identity, activity and label.
	route_points = points.duplicate()
	route_cursor = 0
	route_completed = route_points.is_empty()
	has_target = false
	manual_target = true

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
	if dead or combat_override or bicycle_override or has_meta("combat_controlled") or has_meta("police_custody_completed") or has_meta("police_custody") or not enabled or not physical:
		social_remaining = 0.0
		social_partner = null
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
	_update_local_greeting(delta)
	if not destination_site.is_empty() and LocalActivity.available(self) and route_completed and not has_target and not moving and social_remaining <= 0.0 and _speech_remaining <= 0.0 and str(local_activity.phase) in ["arriving", "dwelling", "settled"]:
		var toward: Vector3 = destination_site.focus - global_position
		yaw = rotate_toward(yaw, atan2(toward.x, toward.z), delta * 2.5)
		puppet.g.rotation.y = yaw
	# A sleeping resident is represented at their home frontage; no invented
	# traversable interior, disappearing body, or teleport through a locked door.
	if _pose_updated and activity == "sleep" and route_completed and not moving:
		puppet.pose({"nod": 0.22, "lean": 0.035})
	elif _pose_updated and social_remaining > 0.0:
		puppet.pose({"nod": sin(_clock * 2.0) * .08, "armR": [-.35, .22], "mouth": .25 + absf(sin(_clock * 12.0)) * .3})
	elif _pose_updated and routine_enabled and route_completed and not moving and _speech_remaining <= 0.0 and level.player != null and global_position.distance_squared_to(level.player.global_position) <= 26.0 * 26.0:
		# Arrival, purposeful stops and work use different existing rig channels;
		# no props or full-rate animation work is added outside the near detail tier.
		var elapsed: float = local_activity.elapsed
		var arriving := str(local_activity.phase) == "arriving"
		var pose := {"nod": sin(elapsed * 1.6) * (0.10 if arriving else 0.025), "lean": sin(elapsed * 0.8) * 0.018}
		if str(local_activity.phase) == "short_pause":
			match str(LocalActivity.outing(actor_id).gesture):
				"stretch":
					pose.armL = [-.65, .38]
					pose.armR = [-.65, .38]
					pose.tilt = sin(elapsed * .8) * .045
				"look":
					pose.look = sin(elapsed * .7) * .32
				"rest":
					pose.nod = .1
		elif activity == "work" and not arriving:
			pose.armR = [-.4 + sin(elapsed * 1.3) * .1, .12]
			pose.nod = .10 + sin(elapsed) * .035
		elif activity == "leisure":
			pose.look = sin(elapsed * .45) * .22
		puppet.pose(pose)

func get_status() -> Dictionary:
	var result: Dictionary = super.get_status()
	result.merge({"name": display_name, "activity": activity, "destination": destination_label,
		"physical": physical, "route_cursor": route_cursor, "route_size": route_points.size(),
		"route_completed": route_completed, "schedule_transitions": schedule_transitions, "fade": _fade,
		"recovery_count": recovery_count, "recovering": not recovery_points.is_empty(), "needs_replan": needs_replan,
		"local_activity": str(local_activity.phase), "dwell_elapsed": float(local_activity.elapsed),
		"destination_id": str(destination_site.get("id", "")), "destination_kind": str(destination_site.get("kind", "")),
		"local_destination": str(LocalActivity.outing(actor_id).label) if str(local_activity.phase) in ["short_walk", "short_pause", "returning"] else destination_label,
		"social_remaining": social_remaining, "social_partner": str(social_partner.actor_id) if is_instance_valid(social_partner) and social_remaining > 0.0 else ""})
	return result
