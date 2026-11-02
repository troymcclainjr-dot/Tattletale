extends CharacterBody3D
## The pickup-game opponent: one reusable court regular in the shared modular
## cast. Only the court activity ticks it, and only the activity's rules move
## the ball. It turns in place before stepping forward, never sidesteps or
## backpedals, keeps a personal-space gap when guarding, and never touches the
## explorer: no steals, blocks or contact. Every goal stays inside the half in play.

const ModularPeople := preload("res://scripts/city/city_modular_people.gd")
const LAYER := 8
const MASK := 1 | 2 | 4 | 8 | 16
const BALL_RADIUS := 0.12
const TURN_RATE := 9.0
const ALIGNED := 0.2
const STROLL := 1.5
const JOG := 3.3
const SPRINT := 4.6
const SPACE := 1.15
const NAMES := ["Jordan", "Reese", "Avery", "Kendall", "Jamie", "Dakota", "Morgan", "Quinn"]

var display_name := "Jordan"
var puppet: Puppet
var capsule: CollisionShape3D
var look_index := -1
var yaw := 0.0
var present := false
var holding := false
var leaving := false
var moving := false
var blocked := false
## Seconds spent trying to move without getting anywhere. The activity
## relocates the opponent if this ever grows large.
var stalled := 0.0
var arms := ""
var gather := 0.0
var dribble_bounced := false
var distance_moved := 0.0
var _court: RefCounted
var _speech: Label3D
var _speech_left := 0.0
var _clock := 0.0
var _speed := 0.0
var _blocked_time := 0.0
var _detour := Vector3.ZERO
var _detour_time := 0.0
var _detour_side := 1.0
var _settling := false
var _leave_goal := Vector3.ZERO
var _leave_time := 0.0
var _wait := 0.0
var _react := 0.0
var _seen_shot := -1
var _plan := Vector3.INF
var _plan_time := 0.0
var _stage := ""
var _stage_time := 0.0
var _follow := 0.0
var _dribble := 0.0
var _ray := PhysicsRayQueryParameters3D.new()

func setup() -> void:
	if capsule != null:
		return
	var shape := CapsuleShape3D.new()
	shape.radius = 0.28
	shape.height = 1.62
	capsule = CollisionShape3D.new()
	capsule.shape = shape
	# The foot ray follows the slab; the capsule clears seams like other people.
	capsule.position.y = shape.height * 0.5 + 0.08
	add_child(capsule)
	_speech = Label3D.new()
	_speech.font_size = 28
	_speech.pixel_size = 0.0035
	_speech.width = 430.0
	_speech.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_speech.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_speech.outline_size = 9
	_speech.outline_modulate = Color("152c30")
	_speech.visibility_range_begin = 1.5
	_speech.visibility_range_end = 22.0
	_speech.hide()
	add_child(_speech)
	_ray.collision_mask = 1
	vanish()

## Rebuild the visual only when the court's regular changes.
func dress(index: int, label: String) -> void:
	display_name = label
	var roster: Array = ModularPeople.roster()
	index = clampi(index, 0, roster.size() - 1)
	if puppet != null and look_index == index:
		return
	if puppet != null and is_instance_valid(puppet.g):
		puppet.g.free()
	var look: Dictionary = roster[index]
	puppet = Puppet.new()
	puppet.id = "court_opponent"
	puppet.H = float(look.get("height", 1.75))
	puppet.g = ModularPeople.rig("CourtOpponentRig", index, puppet.H)
	add_child(puppet.g)
	puppet.bind()
	puppet.g.rotation.y = yaw
	look_index = index
	var shape := capsule.shape as CapsuleShape3D
	shape.height = maxf(0.8, puppet.H - 0.10)
	capsule.position.y = shape.height * 0.5 + 0.08
	_speech.position.y = puppet.H + 0.62

func appear(at: Vector3, facing: float, court: RefCounted) -> void:
	_court = court
	global_position = at
	yaw = facing
	velocity = Vector3.ZERO
	visible = true
	collision_layer = LAYER
	collision_mask = MASK
	present = true
	leaving = false
	holding = false
	stalled = 0.0
	reset_plan()
	if puppet != null:
		puppet.g.rotation.y = yaw
		puppet.pose({})

func vanish() -> void:
	present = false
	leaving = false
	holding = false
	moving = false
	visible = false
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	stalled = 0.0
	_speech_left = 0.0
	if _speech != null:
		_speech.hide()

func leave(goal: Vector3) -> void:
	if not present:
		return
	leaving = true
	holding = false
	_leave_goal = goal
	_leave_time = 0.0
	reset_plan()

func reset_plan() -> void:
	_plan = Vector3.INF
	_plan_time = 0.0
	_stage = ""
	_stage_time = 0.0
	gather = 0.0
	_wait = 0.0
	_react = 0.0
	_follow = 0.0
	_detour_time = 0.0
	_blocked_time = 0.0
	_settling = false
	arms = ""

## A short pause before walking up to check the ball.
func wait(seconds: float) -> void:
	_wait = maxf(_wait, seconds)

func speak(text: String, seconds := 3.0) -> void:
	if _speech == null:
		return
	_speech.text = text
	_speech_left = maxf(0.1, seconds)
	_speech.visible = present

## The activity calls this from its own tick. `thinking` is false while the
## explorer is unavailable (phone, recovery) or the game is decided: stand by.
func step(delta: float, game, thinking: bool) -> void:
	if not present or puppet == null:
		return
	_clock += delta
	_speech_left = maxf(0.0, _speech_left - delta)
	_speech.visible = _speech_left > 0.0
	dribble_bounced = false
	blocked = false
	var before := global_position
	if leaving:
		arms = ""
		_leave_time += delta
		if _walk(_leave_goal, STROLL, delta, 0.4) or _leave_time > 9.0:
			vanish()
			return
	elif thinking:
		_think(delta, game)
	else:
		arms = "hold" if holding else ""
		_face(game.player_position(), delta)
	var travelled := Vector2(global_position.x - before.x, global_position.z - before.z).length()
	distance_moved += travelled
	moving = travelled > 0.0005
	_speed = travelled / maxf(delta, 0.0001)
	stalled = stalled + delta if blocked and not moving else 0.0
	_animate(delta, travelled)

func _think(delta: float, game) -> void:
	var rules = game.rules
	var court = game.court
	var player_at: Vector3 = game.player_position()
	_follow = maxf(0.0, _follow - delta)
	match str(rules.phase):
		"check":
			_stage = ""
			if str(rules.possession) == "opponent":
				arms = ""
				_wait = maxf(0.0, _wait - delta)
				if game.opponent_pick_up():
					return
				var ball_at: Vector3 = game.match_ball_position()
				if _wait > 0.0:
					_face(ball_at, delta)
				else:
					_approach(ball_at, JOG, delta, 0.45)
			else:
				# Give the checking explorer room at the top of the key.
				arms = "defend"
				_hold_spot(court.guard_spot(court.check_spot(), 2.6), player_at, JOG, delta)
		"live":
			if holding:
				_attack(delta, game)
			elif str(rules.holder) == "player":
				_stage = ""
				arms = "defend"
				var gap := 2.6 if bool(rules.needs_clear) else 1.5
				_hold_spot(_spaced(court.guard_spot(player_at, gap), player_at), player_at, JOG, delta)
			else:
				_stage = ""
				_rebound(delta, game)
		"dead":
			_stage = ""
			arms = ""
			_hold_spot(court.free_throw_spot(), player_at, JOG, delta)
		_:
			arms = ""
			_face(player_at, delta)

func _rebound(delta: float, game) -> void:
	arms = "follow" if _follow > 0.0 else ""
	var shot: Dictionary = game.rules.shot
	if not shot.is_empty() and int(shot.get("id", -1)) != _seen_shot:
		_seen_shot = int(shot.id)
		# Watch the ball leave the shooter's hands before crashing the boards.
		_react = 0.35 if str(shot.by) == "player" else 0.1
	_react = maxf(0.0, _react - delta)
	if game.opponent_pick_up():
		return
	var ball_at: Vector3 = game.match_ball_position()
	if _react > 0.0:
		_face(ball_at, delta)
		return
	var court = game.court
	if game.match_ball_pickable("opponent"):
		var lead: Vector3 = game.match_ball_velocity() * 0.25
		_approach(court.clamp_in_play(ball_at + Vector3(lead.x, 0.0, lead.z), 0.3), SPRINT, delta, 0.3)
	else:
		# Still on or above the rim: take position under it on the ball's side.
		var side: Vector2 = court.hoop_local(ball_at)
		_approach(court.spot(1.5, clampf(atan2(side.x, maxf(side.y, 0.1)), -1.0, 1.0)), JOG, delta, 0.35)

func _attack(delta: float, game) -> void:
	var court = game.court
	if bool(game.rules.needs_clear):
		_stage = ""
		arms = "dribble"
		_approach(court.clear_spot(global_position), JOG, delta, 0.3)
		return
	var basket: Vector3 = court.rim()
	match _stage:
		"":
			arms = "dribble"
			if _plan == Vector3.INF:
				_plan = game.opponent_plan()
				_plan_time = 0.0
			_plan_time += delta
			if _approach(_plan, JOG, delta, 0.45) or _plan_time > 3.4 or _blocked_time > 1.2:
				_stage = "set"
				_stage_time = 0.0
		"set":
			arms = "hold"
			_stage_time += delta
			if _face(basket, delta) < 0.06 or _stage_time > 0.9:
				_stage = "gather"
				_stage_time = 0.0
				gather = 0.0
		"gather":
			arms = "gather"
			_stage_time += delta
			gather = clampf(_stage_time / 0.42, 0.0, 1.0)
			_face(basket, delta)
			if gather >= 1.0:
				_stage = ""
				_plan = Vector3.INF
				if game.opponent_shoot():
					_follow = 0.4
				gather = 0.0

func _hold_spot(spot: Vector3, face_at: Vector3, speed: float, delta: float) -> void:
	var gap := Vector2(spot.x - global_position.x, spot.z - global_position.z).length()
	# Small drift is answered by facing, not by shuffling about.
	if gap > 0.7:
		_settling = true
	if _settling and _approach(spot, speed, delta, 0.25):
		_settling = false
	if not _settling:
		_face(face_at, delta)

## Never pick a guarding spot inside the explorer's personal space.
func _spaced(spot: Vector3, from: Vector3) -> Vector3:
	var offset := Vector3(spot.x - from.x, 0.0, spot.z - from.z)
	if offset.length() >= SPACE:
		return spot
	var direction := offset.normalized() if offset.length_squared() > 0.0001 else Vector3(sin(yaw), 0.0, cos(yaw))
	var moved := from + direction * SPACE
	if _court != null:
		moved = _court.clamp_in_play(moved, 0.35)
	return moved

func _approach(goal: Vector3, speed: float, delta: float, arrive: float) -> bool:
	if _detour_time > 0.0:
		_detour_time -= delta
		_walk(_detour, speed, delta, 0.25)
		_note_block(delta)
		return false
	var arrived := _walk(goal, speed, delta, arrive)
	_note_block(delta)
	if _blocked_time > 0.6:
		# Someone has right of way: wait, then swing wide, alternating sides.
		var offset := Vector3(goal.x - global_position.x, 0.0, goal.z - global_position.z)
		if offset.length_squared() > 0.0001:
			var side := Vector3(-offset.z, 0.0, offset.x).normalized() * _detour_side
			_detour = global_position + side * 1.1 + offset.normalized() * 0.4
			if _court != null:
				_detour = _court.clamp_in_play(_detour, 0.3)
			_detour_time = 0.9
		_detour_side = -_detour_side
		_blocked_time = 0.0
	return arrived

func _note_block(delta: float) -> void:
	_blocked_time = _blocked_time + delta if blocked else maxf(0.0, _blocked_time - delta)

## Turn in place first; travel is only ever along the facing direction.
func _walk(goal: Vector3, speed: float, delta: float, arrive: float) -> bool:
	var offset := Vector3(goal.x - global_position.x, 0.0, goal.z - global_position.z)
	var distance := offset.length()
	if distance <= arrive:
		return true
	var wanted := atan2(offset.x, offset.z)
	yaw = rotate_toward(yaw, wanted, delta * TURN_RATE)
	if absf(angle_difference(yaw, wanted)) > ALIGNED:
		return false
	var horizontal := Vector3(sin(yaw), 0.0, cos(yaw)) * minf(speed * delta, distance)
	_ray.from = global_position + horizontal + Vector3.UP * 1.2
	_ray.to = global_position + horizontal - Vector3.UP * 1.5
	var ground := get_world_3d().direct_space_state.intersect_ray(_ray)
	if ground.is_empty() or ground.normal.y < 0.7:
		blocked = true
		return false
	var rise: float = ground.position.y + 0.01 - global_position.y
	if absf(rise) > 0.3:
		blocked = true
		return false
	blocked = move_and_collide(horizontal + Vector3.UP * rise) != null
	return false

func _face(point: Vector3, delta: float) -> float:
	var offset := Vector3(point.x - global_position.x, 0.0, point.z - global_position.z)
	if offset.length_squared() < 0.0004:
		return 0.0
	var wanted := atan2(offset.x, offset.z)
	yaw = rotate_toward(yaw, wanted, delta * TURN_RATE)
	return absf(angle_difference(yaw, wanted))

## Where the held ball sits this frame: chest, dribble or the shot's gather.
func ball_point() -> Vector3:
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	# +Z is the body's forward, so its right hand is on local -X.
	var right := Vector3(-forward.z, 0.0, forward.x)
	var height := puppet.H if puppet != null else 1.75
	var chest := global_position + Vector3.UP * height * 0.62 + forward * 0.32
	if arms == "dribble":
		var at := global_position + forward * 0.36 + right * 0.24
		at.y = lerpf(global_position.y + BALL_RADIUS, global_position.y + height * 0.48, absf(cos(_dribble * PI)))
		return at
	if arms == "gather":
		var overhead := global_position + Vector3.UP * (height + 0.24) + forward * 0.10
		return chest.lerp(overhead, smoothstep(0.0, 1.0, gather))
	return chest

func _animate(delta: float, travelled: float) -> void:
	puppet.g.rotation.y = yaw
	puppet.phase += travelled * 3.2
	var stride := clampf(_speed / JOG, 0.0, 1.0)
	var pose := {"walk": 0.55 * stride, "lean": 0.08 * stride, "bob": absf(sin(puppet.phase)) * 0.022 * stride}
	if arms == "dribble":
		var previous := _dribble
		_dribble = fmod(_dribble + delta * (2.4 if moving else 1.7), 1.0)
		# The visual dribble meets the floor halfway through each cycle.
		dribble_bounced = previous < 0.5 and _dribble >= 0.5
		pose["armR"] = [-0.6 + 0.22 * cos(_dribble * TAU), 0.12]
	elif arms == "hold":
		pose["armR"] = [-1.15, -0.32]
		pose["armL"] = [-1.15, -0.32]
	elif arms == "gather":
		pose["armR"] = [lerpf(-1.15, -2.8, gather), -0.12]
		pose["armL"] = [lerpf(-1.15, -2.55, gather), -0.24]
	elif arms == "follow":
		pose["armR"] = [-2.7, -0.08]
		pose["armL"] = [-2.2, -0.2]
	elif arms == "defend":
		pose["armR"] = [-0.35, 0.85]
		pose["armL"] = [-0.35, 0.85]
	if _speech_left > 0.0:
		pose["mouth"] = 0.15 + absf(sin(_clock * 12.0)) * 0.45
	puppet.pose(pose)

func get_status() -> Dictionary:
	return {"present": present, "name": display_name, "holding": holding, "leaving": leaving,
		"position": global_position, "yaw": yaw, "moving": moving, "blocked": blocked,
		"stalled": stalled, "stage": _stage, "arms": arms, "distance_moved": distance_moved}
