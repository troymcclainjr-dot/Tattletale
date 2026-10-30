extends CharacterBody3D
## A local neighborhood actor. Only CityNpcs.tick advances this body or its animation.

const ACTOR_LAYER := 8
const ACTOR_MASK := 1 | 2 | 4 | 8 | 16
var actor_id := ""
var display_name := "Neighbor"
var cast_id := "mama"
var level: Node3D
var puppet: Puppet
var yaw := 0.0
var enabled := true
var speed := 1.15
var moving := false
var blocked := false
var blocked_seconds := 0.0
var distance_walked := 0.0
var target := Vector3.ZERO
var has_target := false
var patrol_points: Array[Vector3] = []
var patrol_index := 0
var manual_target := false
var capsule: CollisionShape3D
var _wait := 1.0
var _clock := 0.0
var _speech_remaining := 0.0
var _speech_label: Label3D

func build(owner_level: Node3D, identity: String, character: String, label: String) -> void:
	level = owner_level
	actor_id = identity
	cast_id = character
	display_name = label
	name = identity
	collision_layer = ACTOR_LAYER
	collision_mask = ACTOR_MASK
	puppet = Cast.person(cast_id, self)
	var shape := CapsuleShape3D.new()
	shape.radius = 0.28
	shape.height = maxf(0.8, puppet.H - 0.10)
	capsule = CollisionShape3D.new()
	capsule.shape = shape
	# The foot ray follows the surveyed terrain; the capsule clears tiny surface
	# seams while retaining full-height collision against people and street objects.
	capsule.position.y = shape.height * 0.5 + 0.08
	add_child(capsule)
	_speech_label = Label3D.new()
	_speech_label.position.y = puppet.H + 0.78
	_speech_label.font_size = 28
	_speech_label.pixel_size = 0.0035
	_speech_label.width = 430.0
	_speech_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_speech_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_speech_label.outline_size = 9
	_speech_label.outline_modulate = Color("152c30")
	_speech_label.visibility_range_end = 18.0
	_speech_label.visibility_range_begin = 2.5
	_speech_label.hide()
	add_child(_speech_label)

func set_target(destination: Vector3, manual := true) -> void:
	target = destination
	has_target = true
	manual_target = manual
	blocked = false
	blocked_seconds = 0.0
	_wait = 0.0

func set_patrol(points: Array[Vector3]) -> void:
	patrol_points = points.duplicate()
	patrol_index = 0
	manual_target = false
	has_target = false
	_wait = 1.0

func speak(text: String, seconds := 4.0) -> void:
	_speech_label.text = text
	_speech_remaining = maxf(0.1, seconds)
	_speech_label.show()

func set_enabled(value: bool) -> void:
	enabled = value
	visible = value
	collision_layer = ACTOR_LAYER if value else 0
	collision_mask = ACTOR_MASK if value else 0
	velocity = Vector3.ZERO
	moving = false

func tick(delta: float) -> void:
	if not enabled or puppet == null:
		return
	_clock += delta
	_speech_remaining = maxf(0.0, _speech_remaining - delta)
	_speech_label.visible = _speech_remaining > 0.0
	moving = false
	velocity = Vector3.ZERO
	var before := global_position
	if _wait > 0.0:
		_wait = maxf(0.0, _wait - delta)
	elif not has_target and not manual_target and patrol_points.size() >= 2:
		set_target(patrol_points[patrol_index], false)
	if has_target and _wait <= 0.0:
		var offset := target - global_position
		offset.y = 0.0
		if offset.length() <= 0.16:
			has_target = false
			blocked = false
			blocked_seconds = 0.0
			if not manual_target and not patrol_points.is_empty():
				patrol_index = (patrol_index + 1) % patrol_points.size()
				_wait = 1.5 + fposmod(_clock, 1.8)
		else:
			var wanted := atan2(offset.x, offset.z)
			yaw = rotate_toward(yaw, wanted, delta * 3.8)
			# Complete the turn before taking a forward step. No backwards/sideways slide.
			if absf(angle_difference(yaw, wanted)) < 0.035:
				var horizontal := Vector3(sin(yaw), 0.0, cos(yaw)) * minf(speed * delta, offset.length())
				var ground: Dictionary = level.ground_at(global_position + horizontal)
				if ground.is_empty() or ground.normal.y < cos(deg_to_rad(45.0)):
					blocked = true
				else:
					var rise: float = ground.position.y + 0.012 - global_position.y
					if absf(rise) > 0.22:
						blocked = true
					else:
						var motion := horizontal + Vector3.UP * rise
						var contact := move_and_collide(motion)
						blocked = contact != null
						velocity = (global_position - before) / maxf(delta, 0.0001)
	else:
		# A stationary contact turns toward a nearby visitor without changing position.
		if patrol_points.is_empty() and level.player != null:
			var toward: Vector3 = level.player.global_position - global_position
			if Vector2(toward.x, toward.z).length() < 5.0:
				yaw = rotate_toward(yaw, atan2(toward.x, toward.z), delta * 1.4)
	var travelled := Vector2(global_position.x - before.x, global_position.z - before.z).length()
	distance_walked += travelled
	moving = travelled > 0.001
	blocked_seconds = blocked_seconds + delta if blocked else 0.0
	if blocked_seconds > 1.6 and not manual_target and patrol_points.size() >= 2:
		# A neighbor or car has right of way: wait, turn, and use the other end of the walk.
		patrol_index = (patrol_index + 1) % patrol_points.size()
		target = patrol_points[patrol_index]
		blocked_seconds = 0.0
		blocked = false
		_wait = 1.5
	puppet.g.rotation.y = yaw
	puppet.phase += travelled * 3.5
	puppet.pose({"walk": 0.40 if moving else 0.0, "bob": absf(sin(puppet.phase)) * 0.018 if moving else sin(_clock * 1.4) * 0.004, "mouth": (0.15 + absf(sin(_clock * 12.0)) * 0.45) if _speech_remaining > 0.0 else 0.0})

func get_status() -> Dictionary:
	return {"id": actor_id, "enabled": enabled, "position": global_position, "yaw": yaw, "moving": moving, "blocked": blocked, "has_target": has_target, "target": target, "distance_walked": distance_walked, "patrol_points": patrol_points.size()}
