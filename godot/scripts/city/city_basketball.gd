extends Node3D
## Court activity: free shooting, a tracked shootaround, and a pickup game to
## 11 against one reusable court regular. Static balls cost no physics ticks;
## only throws move. The level owns input/modal priority and calls tick from its
## gameplay loop. Nothing here is saved: a reload resets every court.
const Bindings := preload("res://scripts/city/city_input_bindings.gd")
const Court := preload("res://scripts/city/city_basketball_court.gd")
const Rules := preload("res://scripts/city/city_basketball_rules.gd")
const Opponent := preload("res://scripts/city/city_basketball_opponent.gd")
const Appearance := preload("res://scripts/city/city_population_appearance.gd")
const BALL_RADIUS := 0.12
const PICKUP_DISTANCE := 2.3
const ACTIVE_DISTANCE := 65.0
const MAX_ACTIVE := 3
const MAX_FLIGHT_SECONDS := 18.0
const CHARGE_SECONDS := 1.1
const GRAVITY := 9.8
const WORLD_MASK := 1 | 2
# The painted ring from park_courts.py: .225 m radius, .017 m tube. Its mesh is
# decorative, so the ring is resolved analytically against flying balls.
const RIM_RADIUS := 0.225
const RIM_TUBE := 0.017
const RIM_BOUNCE := 0.5
# Lining up within ~12 degrees of a rim takes the exact line from the hand.
const ASSIST_ANGLE := 0.21
const ASSIST_RANGE := 12.0
const MIN_ENTRY := 0.35
const SWEET_GRIP := 0.15
const METER_WIDTH := 260.0
const CHALLENGE_MARGIN := 3.0
const REACH_HEIGHT := 2.4
const INTERFERENCE_HEIGHT := 2.0
const OPPONENT_REACH := 0.95
const OUT_TOLERANCE := 0.05
const HOLDER_OUT := 0.5
const CENTRE_SLACK := 2.0
const LEAVE_WARN := 4.0
const LEAVE_FAR := 18.0
const LEAVE_SECONDS := 6.0
const LOOSE_LIMIT := 14.0
const RESULT_SECONDS := 30.0
const QUIT_CONFIRM := 2.5
const SHOOTAROUND_RANGE := 25.0

signal activity_changed(state: String)

var balls: Array[Dictionary] = []
## Court frames (city_basketball_court.gd), one per ball, same order.
var frames: Array = []
var baskets := 0
var shots := 0
## free, shootaround, match (a game in progress) or result (rematch window).
var mode := "free"
var session := -1
var court: RefCounted
var rules: RefCounted
var opponent: CharacterBody3D
var opponent_instances := 0
var opponent_appearances := 0
var games_started := 0
var last_result: Dictionary = {}
var shootaround: Dictionary = {}
## Opponent tuning: accuracy scales aim error (0 shoots perfectly); bias offsets every aim.
var opponent_accuracy := 1.0
var opponent_aim_bias := Vector3.ZERO
var rng := RandomNumberGenerator.new()
var _level: Node3D
var _player: Node3D
var _held := -1
var _charging := false
var _charge := 0.0
var _mesh: ArrayMesh
var _shape: SphereShape3D
var _notice := ""
var _notice_time := 0.0
var _quit_armed := 0.0
var _leave_time := 0.0
var _loose_time := 0.0
var _result_time := 0.0
var _aggro_check := 0.0
## A ball taken just outside a line is only called out once its holder has
## been on the floor in play: a reach from the apron is not an instant turnover.
var _holder_inbounds := false
var _plan: Dictionary = {}
var _meter: Control
var _meter_fill: ColorRect
var _meter_window: ColorRect
var _meter_mark: ColorRect

func setup(level: Node3D, courts: Node3D) -> Dictionary:
	name = "CourtBasketballs"
	_level = level
	_player = level.player
	if _player.has_method("set_court_activity"):
		_player.set_court_activity(self)
	_mesh = _make_ball_mesh()
	_shape = SphereShape3D.new()
	_shape.radius = BALL_RADIUS
	rng.seed = 11012026
	for record in courts.records:
		var body := CharacterBody3D.new()
		body.name = "Basketball_%s" % str(record.id)
		# Balls collide with terrain/backboards, never strike residents or player.
		body.collision_layer = 0
		body.collision_mask = WORLD_MASK
		body.safe_margin = 0.002
		var collider := CollisionShape3D.new()
		collider.shape = _shape
		body.add_child(collider)
		var visual := MeshInstance3D.new()
		visual.mesh = _mesh
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(visual)
		add_child(body)
		var home: Vector3 = record.position + Vector3.UP * (BALL_RADIUS + 0.04)
		body.global_position = home
		frames.append(Court.new().setup(record))
		balls.append({"body": body, "visual": visual, "home": home,
			"court_id": str(record.id), "hoops": record.hoops, "active": false,
			"age": 0.0, "scored": false, "radius": float(record.get("length_m", 28.0)) * 0.5 + 12.0,
			"holder": "", "release": {}, "nudges": 0, "resting_out": 0.0})
	_build_meter()
	set_presence(_player.global_position)
	return get_status()

func _world_running() -> bool:
	if not is_instance_valid(_player) or not is_instance_valid(_level):
		return false
	return not _level.paused and _level.ready_to_play and not get_tree().paused

func _playable() -> bool:
	if not _world_running() or not _player.enabled:
		return false
	if _player.has_method("is_seated") and _player.is_seated():
		return false
	if _recovering():
		return false
	var phone = _player.get("phone")
	return phone == null or not bool(phone.get("active"))

func _recovering() -> bool:
	var impact = _player.get("impact_recovery")
	if (impact is float or impact is int) and float(impact) > 0.0:
		return true
	var combat = _player.get("combat")
	return is_instance_valid(combat) and combat.has_method("blocks_movement") and combat.blocks_movement()

func tick(delta: float) -> void:
	if not _world_running():
		cancel_charge()
		return
	var available := _playable()
	if not available:
		cancel_charge()
		_while_unavailable()
	_notice_time = maxf(0.0, _notice_time - delta)
	_quit_armed = maxf(0.0, _quit_armed - delta)
	if _held >= 0:
		var held: Dictionary = balls[_held]
		if _player.global_position.distance_to(held.home) > ACTIVE_DISTANCE:
			_carried_away()
		elif available:
			held.body.global_position = _hold_position()
			if _charging:
				_charge = minf(1.0, _charge + delta / CHARGE_SECONDS)
	for i in balls.size():
		if balls[i].active:
			_step_ball(i, delta)
	if rules != null:
		_tick_match(delta, available)
	elif mode == "shootaround":
		_tick_shootaround(delta)
	if is_instance_valid(opponent) and opponent.present:
		opponent.step(delta, self, rules != null and available and mode == "match")
		if rules != null:
			_follow_opponent_ball()
			_watch_opponent()
	_update_meter()
	set_presence(_player.global_position)

func _step_ball(i: int, delta: float) -> void:
	var ball: Dictionary = balls[i]
	var body: CharacterBody3D = ball.body
	ball.age += delta
	if not body.global_position.is_finite() or body.global_position.y < ball.home.y - 5.0 or ball.age > MAX_FLIGHT_SECONDS or body.global_position.distance_to(ball.home) > ball.radius or body.global_position.distance_to(_player.global_position) > ACTIVE_DISTANCE:
		_ball_lost(i)
		return
	var before := body.global_position
	body.velocity.y -= GRAVITY * delta
	var collision := body.move_and_collide(body.velocity * delta)
	if collision != null:
		var normal := collision.get_normal()
		# Only real, energetic contacts sound; resting/rolling balls stay quiet.
		if absf(body.velocity.dot(normal)) >= 1.0:
			_bounce_sound(collision.get_position())
		var kind := contact_kind(collision.get_collider(), normal)
		body.velocity = body.velocity.bounce(normal) * 0.68
		if normal.y > 0.65 and absf(body.velocity.y) < 0.75:
			body.velocity.y = 0.0
			body.velocity.x *= 0.75
			body.velocity.z *= 0.75
			if body.velocity.length() < 0.4:
				ball.active = false
				body.velocity = Vector3.ZERO
		_ball_contact(i, kind, collision.get_position())
	var ring := _rim_contact(ball, before)
	if not ring.is_empty():
		if float(ring.speed) >= 1.0:
			_bounce_sound(ring.position)
		_ball_contact(i, "rim", ring.position)
	if not ball.scored:
		for hoop in ball.hoops:
			if crosses_rim(before, body.global_position, hoop.rim_position):
				ball.scored = true
				_ball_scored(i, hoop.rim_position)
				break
	_track_flight(ball, before)
	ball.visual.rotate_x(body.velocity.z * delta / BALL_RADIUS)
	ball.visual.rotate_z(-body.velocity.x * delta / BALL_RADIUS)
	if not ball.active:
		_settled(i)

## Pass E here before the ordinary conversation/check-in interaction.
func interact() -> bool:
	if not _playable():
		return false
	if _held >= 0:
		_make_room_for_throw()
		var index := _held
		var dropped: Dictionary = balls[index]
		dropped.active = true
		dropped.age = 0.0
		dropped.scored = false
		dropped.holder = ""
		dropped.body.velocity = Vector3.ZERO
		_held = -1
		cancel_charge()
		_player_released(index, false)
		return true
	var nearest := _nearest_ball()
	if nearest < 0:
		return _explain_game_ball()
	_take(nearest)
	return true

## Context-only input through the shared bindings. An empty hand never consumes
## the shoot button; jump, sprint and every unrelated key always fall through.
func handle_input(event: InputEvent) -> bool:
	if not _playable():
		cancel_charge()
		return false
	if Bindings.matches(event, "city_basketball_challenge"):
		return challenge()
	if _held < 0:
		cancel_charge()
		return false
	if Bindings.matches(event, "city_ball_shoot", true):
		return begin_charge()
	if Bindings.matches(event, "city_ball_shoot", false):
		release_charge()
		return true
	if Bindings.matches(event, "city_ball_return"):
		return return_held()
	return false

func begin_charge() -> bool:
	if not _playable() or _held < 0:
		return false
	_charging = true
	_charge = 0.0
	return true

func release_charge() -> bool:
	if not _charging:
		return false
	return shoot()

func return_held() -> bool:
	if not _playable() or _held < 0:
		return false
	if mode == "match":
		_say("Finish the game first, or press %s twice to quit." % _key("city_basketball_challenge"))
		return true
	return_ball(_held)
	_end_shootaround(true)
	return true

## The court challenge action: start a game here, press twice to quit one, or
## run it back during the result window. Away from courts it is not consumed.
func challenge() -> bool:
	if not _playable():
		return false
	if mode == "match":
		if _quit_armed > 0.0:
			return quit_match()
		_quit_armed = QUIT_CONFIRM
		_say("Press %s again to quit the game." % _key("city_basketball_challenge"), QUIT_CONFIRM)
		return true
	if mode == "result":
		return rematch()
	return start_match()

func cancel_charge() -> void:
	_charging = false
	_charge = 0.0
	if _meter != null:
		_meter.hide()

func suspend(put_away := false) -> void:
	cancel_charge()
	if not put_away:
		return
	if _held >= 0:
		return_ball(_held)
	cancel_activity("Pickup game called off · you left the court.")

## Hard stop for root (cutscene, case start, relocation, fresh world).
func cancel_activity(reason := "") -> void:
	cancel_charge()
	if rules != null:
		_end_match(reason if not reason.is_empty() else "Pickup game called off.", true)
	elif mode == "shootaround":
		_end_shootaround(true)

func is_busy() -> bool:
	return rules != null

func shoot() -> bool:
	if _held < 0 or not _playable():
		cancel_charge()
		return false
	_make_room_for_throw()
	var index := _held
	var ball: Dictionary = balls[index]
	var from := _hold_position()
	ball.body.global_position = from
	ball.body.velocity = _player_shot_velocity(index, from, _charge)
	ball.active = true
	ball.age = 0.0
	ball.scored = false
	ball.holder = ""
	shots += 1
	_held = -1
	cancel_charge()
	_player_released(index, true)
	return true

func _make_room_for_throw() -> void:
	# A fixed cap includes other balls left bouncing on adjacent courts. The
	# game ball is never the one put away.
	var active := 0
	for ball in balls:
		active += int(ball.active)
	if active >= MAX_ACTIVE:
		for i in balls.size():
			if balls[i].active and not _is_match_ball(i):
				return_ball(i)
				break

static func shot_velocity(aim: Vector3, charge: float) -> Vector3:
	var flat := Vector3(aim.x, 0.0, aim.z).normalized()
	if flat.length_squared() < 0.1:
		flat = Vector3.FORWARD
	# Camera normally looks slightly down from the walking boom. Give throws an
	# upward arc while still allowing deliberate higher/lower camera aiming.
	var elevation := clampf(aim.y + 0.65, 0.38, 0.88)
	return (flat * sqrt(1.0 - elevation * elevation) + Vector3.UP * elevation) * lerpf(6.5, 13.5, clampf(charge, 0.0, 1.0))

static func crosses_rim(before: Vector3, after: Vector3, rim: Vector3) -> bool:
	if before.y <= rim.y or after.y > rim.y or before.y <= after.y:
		return false
	var at := before.lerp(after, (before.y - rim.y) / (before.y - after.y))
	# Actual visual rim radius .225m; the whole .12m ball must fit inside it.
	return Vector2(at.x - rim.x, at.z - rim.z).length() <= 0.225 - BALL_RADIUS

## Where a shot from `from` goes with the current view: the rim it lines up
## with, the corrected aim, the ideal power for that arc and its timing window.
func shot_plan(index: int, from: Vector3) -> Dictionary:
	var aim := _aim_direction()
	var plan := {"aim": aim, "rim": Vector3.INF, "ideal": -1.0, "window": 0.0, "hint": ""}
	var frame = _assist_frame(index)
	if frame == null:
		return plan
	var target := _aim_rim(from, aim, frame)
	if not target.is_finite():
		return plan
	var flat := Vector3(target.x - from.x, 0.0, target.z - from.z)
	var distance := flat.length()
	# The hand sits right of the camera ray: aim from the hand, keep the view's pitch.
	var vertical := clampf(aim.y, -0.95, 0.95)
	plan.aim = flat / distance * sqrt(1.0 - vertical * vertical) + Vector3.UP * vertical
	plan.rim = target
	var angle := asin(clampf(vertical + 0.65, 0.38, 0.88))
	var rise := target.y - from.y
	if Court.entry_angle(distance, rise, angle) < MIN_ENTRY:
		plan.hint = "look up for more arc"
		return plan
	var speed := Court.launch_speed(distance, rise, angle, GRAVITY, _step())
	var ideal := (speed - 6.5) / 7.0
	if speed <= 0.0 or ideal > 1.0:
		plan.hint = "too far for this arc · look up or move in"
		return plan
	if ideal < 0.0:
		plan.hint = "too close for this arc · step back"
		return plan
	plan.ideal = ideal
	plan.window = clampf(0.085 - 0.007 * distance, 0.03, 0.075)
	return plan

func _player_shot_velocity(index: int, from: Vector3, charge: float) -> Vector3:
	_plan = shot_plan(index, from)
	var ideal := float(_plan.ideal)
	if ideal >= 0.0:
		var window := float(_plan.window)
		var error := charge - ideal
		# A release inside the window flies true; beyond it errors grow normally.
		var excess := maxf(0.0, absf(error) - window)
		charge = ideal + signf(error) * (minf(absf(error), window) * SWEET_GRIP + excess)
	return shot_velocity(_plan.aim, charge)

func _aim_rim(from: Vector3, aim: Vector3, frame) -> Vector3:
	var flat := Vector3(aim.x, 0.0, aim.z)
	if flat.length_squared() < 0.0001:
		return Vector3.INF
	flat = flat.normalized()
	var best := Vector3.INF
	var best_angle := ASSIST_ANGLE
	var candidates: Array = [frame.rim()] if frame == court and mode == "match" else frame.rims
	for candidate in candidates:
		var to := Vector3(candidate.x - from.x, 0.0, candidate.z - from.z)
		var distance := to.length()
		if distance < 0.25 or distance > ASSIST_RANGE:
			continue
		var angle := flat.angle_to(to)
		if angle < best_angle:
			best_angle = angle
			best = candidate
	return best

func _assist_frame(index: int):
	if index >= 0 and index < frames.size() and frames[index].contains(_player.global_position, 6.0):
		return frames[index]
	var nearest := _court_at(_player.global_position, 6.0)
	return frames[nearest] if nearest >= 0 else null

func _step() -> float:
	return 1.0 / float(maxi(1, Engine.physics_ticks_per_second))

func return_ball(index: int) -> void:
	if index < 0 or index >= balls.size():
		return
	if _held == index:
		_held = -1
		cancel_charge()
	var ball: Dictionary = balls[index]
	if str(ball.holder) == "opponent" and is_instance_valid(opponent):
		opponent.holding = false
	ball.holder = ""
	ball.release = {}
	ball.nudges = 0
	ball.active = false
	ball.age = 0.0
	ball.scored = false
	ball.body.velocity = Vector3.ZERO
	ball.body.global_position = ball.home

func _aim_direction() -> Vector3:
	var camera: Camera3D = _player.get("camera")
	if is_instance_valid(camera):
		return -camera.global_basis.z
	return -_player.global_basis.z

## Final upper-body layer after the ordinary walk/jump pose. The lower body
## and free arm retain locomotion; charging brings up the supporting hand.
func apply_player_pose(delta: float) -> void:
	if _held < 0 or not _playable():
		return
	var combat = _player.get("combat")
	if is_instance_valid(combat) and (bool(combat.get("aiming")) or float(combat.get("reloading")) > 0.0):
		return
	var puppet: Puppet = _player.get("puppet")
	if puppet == null or puppet.arms.size() < 2:
		return
	# Settle into the view only while standing. A running player's torso keeps
	# its movement heading, and the ball follows that body rather than orbiting it.
	if float(_player.get("current_speed")) < 0.1 and not bool(_player.get("_jump_active")):
		_player.yaw = rotate_toward(float(_player.get("yaw")), float(_player.get("camera_yaw")), delta * 4.0)
		puppet.g.rotation.y = float(_player.yaw)
	var lift := smoothstep(0.0, 1.0, _charge) if _charging else 0.0
	var sway := sin(puppet.phase) * 0.035 * clampf(float(_player.get("current_speed")) / 3.8, 0.0, 1.0)
	puppet.arms[0].rotation = Vector3(lerpf(-1.05, -1.95, lift) + sway, 0.0, 0.22)
	if _charging:
		puppet.arms[1].rotation.x = lerpf(-0.65, -1.75, lift)
		puppet.arms[1].rotation.z = -0.45
	# Player physics can run after the level's activity tick: attach after the
	# final pose too, so the palm and ball never separate by a frame of walking.
	balls[_held].body.global_position = _hold_position()

func _hold_position() -> Vector3:
	var puppet: Puppet = _player.get("puppet")
	var forward := -_player.global_basis.z
	if puppet != null:
		forward = puppet.g.global_basis.z.normalized()
	var origin := _player.global_position + Vector3.UP * 1.25
	var target := origin + forward * 0.45 + forward.cross(Vector3.UP) * 0.20
	if puppet != null and not puppet.hands.is_empty():
		target = puppet.hand_pos(0) + forward * BALL_RADIUS + Vector3.UP * (BALL_RADIUS * 0.45)
	# Prevent carrying/launching the ball through a wall at arm's length.
	var ray := PhysicsRayQueryParameters3D.create(origin, target + forward * BALL_RADIUS, WORLD_MASK)
	if _player is CollisionObject3D:
		ray.exclude = [_player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		return hit.position + hit.normal * (BALL_RADIUS + 0.02)
	return target

func _nearest_ball() -> int:
	var nearest := -1
	var distance := PICKUP_DISTANCE * PICKUP_DISTANCE
	var origin := _player.global_position + Vector3.UP
	for i in balls.size():
		if not _can_pick(i, "player"):
			continue
		var ball: Dictionary = balls[i]
		var at: Vector3 = ball.body.global_position
		var squared := origin.distance_squared_to(at)
		if squared >= distance:
			continue
		var ray := PhysicsRayQueryParameters3D.create(origin, at, WORLD_MASK)
		if _player is CollisionObject3D:
			ray.exclude = [_player.get_rid()]
		if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			continue
		distance = squared
		nearest = i
	return nearest

## Who may take a loose or checked ball right now (distance is checked by the taker).
func _can_pick(index: int, side: String) -> bool:
	var ball: Dictionary = balls[index]
	if not str(ball.holder).is_empty():
		return false
	if mode == "match" and index != session:
		return false
	if not _is_match_ball(index) or mode != "match":
		return side == "player"
	if not rules.can_pick_up(side):
		return false
	var at: Vector3 = ball.body.global_position
	var height: float = at.y - court.floor_y(at)
	# No goaltending: an untouched shot above head height belongs to the rim.
	if not rules.shot.is_empty() and not bool(rules.shot.touched) and height > INTERFERENCE_HEIGHT:
		return false
	return height <= REACH_HEIGHT

func _is_match_ball(index: int) -> bool:
	return rules != null and index == session

func _take(index: int) -> void:
	var ball: Dictionary = balls[index]
	# A caught rebound settles the previous shot's feedback first.
	_resolve_release(index)
	_held = index
	ball.active = false
	ball.scored = false
	ball.holder = "player"
	ball.release = {}
	ball.body.velocity = Vector3.ZERO
	ball.body.global_position = _hold_position()
	cancel_charge()
	if _is_match_ball(index) and mode == "match":
		_announce_pickup(rules.pick_up("player", court.beyond_arc(_player.global_position)))
		return
	if _is_match_ball(index):
		return # Free shots with the game ball while the rematch offer stands.
	if rules != null:
		_end_match("", false) # Another court's ball closes the rematch window.
	_begin_shootaround(index)

## E beside the game ball when it is not yours to take: say why, keep the key.
func _explain_game_ball() -> bool:
	if mode != "match" or session < 0:
		return false
	var at: Vector3 = balls[session].body.global_position
	if at.distance_to(_player.global_position + Vector3.UP) > PICKUP_DISTANCE:
		return false
	if str(balls[session].holder) == "opponent":
		_say("%s has the ball · guard the basket." % _rival())
	elif str(rules.phase) == "dead":
		_say("Dead ball · it goes back to the top of the key.")
	elif str(rules.phase) == "check":
		_say("%s checks this one at the top of the key." % _rival())
	else:
		_say("Let the shot come off the rim first.")
	return true

func _player_released(index: int, is_shot: bool) -> void:
	var frame = frames[index]
	var feet := _player.global_position
	var game_ball := _is_match_ball(index) and mode == "match"
	var hoop_index: int = court.hoop if game_ball else frame.nearest_hoop(feet)
	var target: Vector3 = frame.rim(hoop_index)
	var aimed: Vector3 = _plan.get("rim", Vector3.INF)
	if is_shot and aimed.is_finite():
		target = aimed
	var value: int = frame.shot_value(feet, hoop_index) if frame.playable() else 1
	_begin_release(index, "player", is_shot, value, target)
	if game_ball:
		rules.release("player", value, is_shot)
	elif mode == "shootaround" and session == index and is_shot:
		shootaround.attempts = int(shootaround.attempts) + 1
		shootaround.idle = 0.0

func _begin_release(index: int, by: String, is_shot: bool, value: int, target: Vector3) -> void:
	var ball: Dictionary = balls[index]
	var from: Vector3 = ball.body.global_position
	var direction := Vector3(target.x - from.x, 0.0, target.z - from.z)
	ball.release = {"by": by, "shot": is_shot, "value": value, "rim": target, "contacts": {}, "peak": from.y,
		"dir": direction.normalized() if direction.length_squared() > 0.0001 else Vector3.FORWARD,
		"resolved": false, "grounded": false}

func _ball_contact(index: int, kind: String, at: Vector3) -> void:
	var ball: Dictionary = balls[index]
	var release: Dictionary = ball.release
	if not release.is_empty():
		release.contacts[kind] = true
		if kind == "floor" and not ball.scored:
			release.grounded = true
			_resolve_release(index)
	if not _is_match_ball(index) or mode != "match":
		return
	rules.touch()
	if kind == "floor" and str(rules.phase) == "live" and str(rules.holder).is_empty() and court.outside_distance(at) > OUT_TOLERANCE:
		if not rules.out_of_bounds().is_empty():
			_say("Out of bounds · %s." % _possession_text())
			_sfx("whistle")

func _ball_scored(index: int, rim: Vector3) -> void:
	var ball: Dictionary = balls[index]
	var release: Dictionary = ball.release
	var by := str(release.get("by", "player"))
	if by != "opponent":
		baskets += 1
	var style := make_text(release)
	if _is_match_ball(index) and mode == "match":
		release.resolved = true
		if bool(release.get("grounded", false)):
			_say("It bounced first · no basket.")
			return
		if not rim.is_equal_approx(court.rim()):
			_say("Wrong basket · this game is played at the other end.")
			return
		var event: Dictionary = rules.basket()
		if event.is_empty():
			return
		if str(event.kind) == "no_basket":
			_say("%s didn't clear it past the arc · no basket · %s." % ["You" if by == "player" else _rival(), _possession_text()])
			_sfx("whistle")
		elif event.has("winner"):
			_finish_game(event, style)
		else:
			_say("%s%s +%d · %s" % ["" if by == "player" else _rival() + ": ", style, int(event.points), _score_text()])
			_sfx("tick")
		return
	if release.is_empty():
		_say("Basket! %d made" % baskets)
		return
	release.resolved = true
	if mode == "shootaround" and session == index and by == "player":
		shootaround.makes = int(shootaround.makes) + 1
		shootaround.streak = int(shootaround.streak) + 1
		shootaround.best = maxi(int(shootaround.best), int(shootaround.streak))
		shootaround.points = int(shootaround.points) + int(release.value)
		_say("%s +%d · %d/%d" % [style, int(release.value), int(shootaround.makes), int(shootaround.attempts)])
		_sfx("tick")
	else:
		_say("%s Basket! %d made" % [style, baskets])

## Miss feedback, once per shot, at the first floor contact or a caught rebound.
func _resolve_release(index: int) -> void:
	var ball: Dictionary = balls[index]
	var release: Dictionary = ball.release
	if release.is_empty() or bool(release.get("resolved", false)):
		return
	release.resolved = true
	if ball.scored or not bool(release.get("shot", false)):
		return
	var text := miss_text(release)
	if str(release.by) == "opponent":
		_say("%s misses · %s" % [_rival(), text.to_lower()])
	elif mode == "shootaround" and session == index:
		shootaround.streak = 0
		_say("%s · %d/%d" % [text, int(shootaround.makes), int(shootaround.attempts)])
	else:
		_say(text)

func _track_flight(ball: Dictionary, before: Vector3) -> void:
	var release: Dictionary = ball.release
	if release.is_empty() or bool(release.get("resolved", false)):
		return
	var at: Vector3 = ball.body.global_position
	release.peak = maxf(float(release.peak), at.y)
	var target: Vector3 = release.rim
	if not release.has("plane") and before.y > target.y and at.y <= target.y:
		var crossing := before.lerp(at, (before.y - target.y) / maxf(before.y - at.y, 0.0001))
		release["plane"] = crossing - target

static func contact_kind(collider: Object, normal: Vector3) -> String:
	var label := str(collider.name) if collider is Node else ""
	if label.begins_with("SolidHoopBackboard"):
		return "board"
	if label.begins_with("SolidHoop"):
		return "hoop"
	return "floor" if normal.y > 0.65 else "wall"

static func make_text(release: Dictionary) -> String:
	var contacts: Dictionary = release.get("contacts", {})
	if contacts.has("board"):
		return "Bank shot!"
	if contacts.has("rim"):
		return "Rattled in!"
	return "Swish!" if bool(release.get("shot", true)) else "Dropped in!"

static func miss_text(release: Dictionary) -> String:
	var contacts: Dictionary = release.get("contacts", {})
	var offset = release.get("plane")
	if contacts.has("rim"):
		return "Rim out" if offset is Vector3 and Vector2(offset.x, offset.z).length() < 0.32 else "Off the rim"
	if contacts.has("board"):
		return "Off the glass"
	if offset is Vector3:
		var direction: Vector3 = release.get("dir", Vector3.FORWARD)
		var depth: float = offset.dot(direction)
		var side: float = offset.dot(Vector3(-direction.z, 0.0, direction.x))
		if absf(depth) >= absf(side):
			return ("Long by %.1f m" if depth > 0.0 else "Short by %.1f m") % absf(depth)
		return ("Wide right by %.1f m" if side > 0.0 else "Wide left by %.1f m") % absf(side)
	var target = release.get("rim")
	if target is Vector3 and float(release.get("peak", 0.0)) < target.y:
		return "Air ball · never reached the rim"
	return "Air ball"

## The ring is decorative geometry: resolve a ball against the .017 m tube here,
## sampling the step so a fast ball cannot skip through it.
func _rim_contact(ball: Dictionary, before: Vector3) -> Dictionary:
	var body: CharacterBody3D = ball.body
	var after := body.global_position
	var reach := RIM_TUBE + BALL_RADIUS
	for hoop in ball.hoops:
		var rim: Vector3 = hoop.rim_position
		if after.distance_squared_to(rim) > 1.0 and before.distance_squared_to(rim) > 1.0:
			continue
		var steps := maxi(1, ceili(before.distance_to(after) / 0.04))
		for step in range(1, steps + 1):
			var point := before.lerp(after, float(step) / steps)
			var flat := Vector3(point.x - rim.x, 0.0, point.z - rim.z)
			var radial := flat.normalized() if flat.length_squared() > 0.00000001 else Vector3.RIGHT
			var ring := rim + radial * RIM_RADIUS
			var offset := point - ring
			if offset.length_squared() >= reach * reach:
				continue
			var normal := offset.normalized() if offset.length_squared() > 0.0000001 else Vector3.UP
			body.global_position = ring + normal * (reach + 0.002)
			var closing := body.velocity.dot(normal)
			if closing < 0.0:
				body.velocity -= normal * closing * (1.0 + RIM_BOUNCE)
				body.velocity *= 0.9
			# A ball balanced on top of the tube still rolls off one side or the other.
			if normal.y > 0.92:
				body.velocity += radial * (0.35 if flat.length() > RIM_RADIUS else -0.35)
			return {"position": ring + normal * RIM_TUBE, "speed": absf(closing)}
	return {}

## A ball that came to rest above head height (backboard top, hoop arm) is
## nudged back toward the court, then put away if it keeps perching.
func _settled(i: int) -> void:
	var ball: Dictionary = balls[i]
	var body: CharacterBody3D = ball.body
	var frame = frames[i]
	if body.global_position.y - float(frame.floor_y(body.global_position)) < 1.7:
		ball.nudges = 0
		return
	ball.nudges = int(ball.nudges) + 1
	if int(ball.nudges) > 4:
		_ball_lost(i)
		return
	var toward: Vector3 = frame.center - body.global_position
	toward.y = 0.0
	ball.active = true
	body.velocity = (toward.normalized() if toward.length_squared() > 0.01 else Vector3.FORWARD) * 1.4 + Vector3.UP * 0.6

func _ball_lost(i: int) -> void:
	if _is_match_ball(i) and mode == "match":
		if not rules.out_of_bounds().is_empty():
			_say("Ball out of play · %s." % _possession_text())
		# The dead-ball pause then hands it over from the top of the key.
		_rest_ball(i, court.check_spot())
		return
	return_ball(i)

func _carried_away() -> void:
	if _is_match_ball(_held):
		_end_match("You left the court with the ball · game over.", true)
		return
	return_ball(_held)
	_say("Ball returned to its court.")
	_end_shootaround(true)

func _rest_ball(index: int, at: Vector3) -> void:
	var ball: Dictionary = balls[index]
	if _held == index:
		_held = -1
		cancel_charge()
	if str(ball.holder) == "opponent" and is_instance_valid(opponent):
		opponent.holding = false
	ball.holder = ""
	ball.release = {}
	ball.nudges = 0
	ball.active = false
	ball.age = 0.0
	ball.scored = false
	ball.body.velocity = Vector3.ZERO
	var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.0, at - Vector3.UP * 2.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	var ground: Vector3 = hit.position if not hit.is_empty() else at
	ball.body.global_position = ground + Vector3.UP * (BALL_RADIUS + 0.02)

func _while_unavailable() -> void:
	if not is_instance_valid(_player):
		return
	if _player.has_method("is_seated") and _player.is_seated():
		if _held >= 0:
			return_ball(_held)
		cancel_activity("Pickup game called off · you left the court.")
		return
	if _held >= 0 and _recovering():
		_fumble()

## Knocked off balance: the ball pops loose, live for whoever reaches it.
func _fumble() -> void:
	var index := _held
	var ball: Dictionary = balls[index]
	_make_room_for_throw()
	_held = -1
	cancel_charge()
	var forward := -_player.global_basis.z
	ball.holder = ""
	ball.active = true
	ball.age = 0.0
	ball.scored = false
	ball.body.velocity = Vector3(forward.x, 0.0, forward.z).normalized() * 1.2 + Vector3.UP * 1.0
	_player_released(index, false)
	_say("You lost the handle.")

# ------------------------------------------------------------------ shootaround

func _begin_shootaround(index: int) -> void:
	if mode == "shootaround" and session == index:
		shootaround.idle = 0.0
		return
	_end_shootaround(true)
	mode = "shootaround"
	session = index
	shootaround = {"court": str(balls[index].court_id), "attempts": 0, "makes": 0, "streak": 0, "best": 0, "points": 0, "idle": 0.0}
	activity_changed.emit(mode)

func _end_shootaround(announce: bool) -> void:
	if mode != "shootaround":
		return
	var attempts := int(shootaround.get("attempts", 0))
	if announce and attempts > 0:
		var makes := int(shootaround.makes)
		_announce("Shootaround · %d/%d (%d%%) · best streak %d" % [makes, attempts, roundi(100.0 * makes / attempts), int(shootaround.best)])
	mode = "free"
	session = -1
	activity_changed.emit(mode)

func _tick_shootaround(delta: float) -> void:
	var ball: Dictionary = balls[session]
	var frame = frames[session]
	shootaround.idle = float(shootaround.idle) + delta if _held != session else 0.0
	if _held != session and (not frame.contains(_player.global_position, SHOOTAROUND_RANGE) or float(shootaround.idle) > 120.0):
		_end_shootaround(true)
		return
	# A rebound that rolled well off the court comes back to the free-throw line.
	if not ball.active and _held != session and str(ball.holder).is_empty() and not frame.contains(ball.body.global_position, 2.0):
		ball.resting_out = float(ball.resting_out) + delta
		if float(ball.resting_out) > 2.0:
			ball.resting_out = 0.0
			_rest_ball(session, frame.free_throw_spot(frame.nearest_hoop(_player.global_position)))
			_say("Ball rolled off the court · it's back at the free-throw line.")
	else:
		ball.resting_out = 0.0

# ------------------------------------------------------------------ pickup game

func start_match(index := -1) -> bool:
	if not _playable() or rules != null:
		return false
	if index < 0:
		index = _court_at(_player.global_position, CHALLENGE_MARGIN)
	if index < 0 or index >= balls.size() or not frames[index].playable():
		return false
	if _held >= 0 and _held != index:
		return_ball(_held)
	_end_shootaround(false)
	session = index
	court = frames[index]
	court.select_hoop(_player.global_position)
	if not _summon_opponent():
		_say("Nobody is free to play here right now.")
		court = null
		session = -1
		if _held >= 0:
			_begin_shootaround(_held)
		return true
	rules = Rules.new()
	rng.seed = hash(str(court.id)) + games_started * 7919
	games_started += 1
	rules.start("player")
	_hand_over_or_check()
	mode = "match"
	_quit_armed = 0.0
	_leave_time = 0.0
	_loose_time = 0.0
	opponent.speak("Game to 11. Your ball.", 3.5)
	_announce("Pickup game with %s · first to 11 · 1 inside the arc, 2 beyond · after a basket the other side checks it at the top · take defensive rebounds past the arc · %s twice quits · pickup games aren't saved." % [_rival(), _key("city_basketball_challenge")])
	_sfx("whistle")
	activity_changed.emit(mode)
	return true

func quit_match(reason := "") -> bool:
	if rules == null:
		return false
	_end_match(reason if not reason.is_empty() else "You walked off · game over.", true)
	return true

## Loser's ball. The same regular stays; nobody new is spawned.
func rematch() -> bool:
	if mode != "result" or rules == null or not rules.rematch():
		return false
	mode = "match"
	_quit_armed = 0.0
	_leave_time = 0.0
	_loose_time = 0.0
	games_started += 1
	if _held >= 0 and _held != session:
		return_ball(_held)
	if is_instance_valid(opponent):
		opponent.reset_plan()
	_hand_over_or_check()
	opponent.speak("Run it back.", 2.5)
	_announce("Rematch with %s · first to 11 · %s." % [_rival(), _possession_text()])
	_sfx("whistle")
	activity_changed.emit(mode)
	return true

func _end_match(message: String, abandon: bool) -> void:
	if rules == null:
		return
	if abandon:
		rules.abandon(message)
		return_ball(session)
	last_result = rules.summary()
	rules = null
	_quit_armed = 0.0
	_leave_time = 0.0
	if is_instance_valid(opponent):
		opponent.holding = false
		if opponent.present:
			opponent.speak("Later." if abandon else "Good run.", 2.5)
			opponent.leave(court.exit_point(opponent.global_position))
	court = null
	session = -1
	mode = "free"
	if _held >= 0:
		_begin_shootaround(_held)
	if not message.is_empty():
		_announce(message)
	activity_changed.emit(mode)

func _finish_game(event: Dictionary, style: String) -> void:
	mode = "result"
	_result_time = RESULT_SECONDS
	var won := str(event.winner) == "player"
	var tally: Dictionary = event.score
	var line := "%s +%d · " % [style, int(event.points)]
	if won:
		_announce(line + "You win %d–%d! %s for a rematch." % [int(tally.player), int(tally.opponent), _key("city_basketball_challenge")])
		opponent.speak("Good game. Run it back?", 4.0)
	else:
		_announce(line + "%s wins %d–%d. %s for a rematch." % [_rival(), int(tally.opponent), int(tally.player), _key("city_basketball_challenge")])
		opponent.speak("Good game. Again?", 4.0)
	_sfx("win" if won else "buzz")
	last_result = rules.summary()
	activity_changed.emit(mode)

func _summon_opponent() -> bool:
	if not is_instance_valid(opponent):
		opponent = Opponent.new()
		opponent.name = "CourtOpponent"
		add_child(opponent)
		opponent.setup()
		opponent_instances += 1
	opponent.dress(_regular_look(session), Opponent.NAMES[session % Opponent.NAMES.size()])
	if opponent.present and court.contains(opponent.global_position, 6.0):
		# Still walking off after the last game here: call them back.
		opponent.appear(opponent.global_position, opponent.yaw, court)
		return true
	for candidate in court.spawn_points(_player.global_position):
		var at := _standing_point(candidate)
		if at.is_finite() and Vector2(at.x - _player.global_position.x, at.z - _player.global_position.z).length() > 2.0:
			var toward: Vector3 = court.on_floor(court.rim()) - at
			opponent.appear(at, atan2(toward.x, toward.z), court)
			opponent_appearances += 1
			return true
	return false

## Floor under a walk-on candidate with room for a standing person, else INF.
func _standing_point(candidate: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(candidate + Vector3.UP * 2.0, candidate - Vector3.UP * 2.5, 1))
	if hit.is_empty() or hit.normal.y < 0.7:
		return Vector3.INF
	var ground: Vector3 = hit.position
	var body := CapsuleShape3D.new()
	body.radius = 0.32
	body.height = 1.6
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = body
	query.transform = Transform3D(Basis.IDENTITY, ground + Vector3.UP * 0.92)
	query.collision_mask = 2 | 4 | 8 | 16
	if is_instance_valid(opponent):
		query.exclude = [opponent.get_rid()]
	return ground if space.intersect_shape(query, 1).is_empty() else Vector3.INF

func _regular_look(index: int) -> int:
	var profile: Dictionary = Appearance.profile("crowd_%d" % ((index * 389 + 71) % Appearance.CROWD_TOTAL))
	return int(profile.get("roster_index", index))

## A game opened with the ball in hand on the floor in play keeps it (it must
## still clear the arc); otherwise the ball is checked at the top of the key.
func _hand_over_or_check() -> void:
	var feet := _player.global_position
	if str(rules.possession) == "player" and _held == session and court.outside_distance(feet) <= 0.0:
		rules.give("player", court.beyond_arc(feet))
	else:
		_place_for_check()

## The receiving side walks up to the ball resting at the top of the key.
func _place_for_check() -> void:
	_rest_ball(session, court.check_spot())
	if str(rules.possession) == "opponent" and is_instance_valid(opponent):
		opponent.wait(0.6)

func _tick_match(delta: float, available: bool) -> void:
	var event: Dictionary = rules.tick(delta)
	if str(event.get("kind", "")) == "check_ready":
		_place_for_check()
		_say("Your ball · pick it up at the top of the key." if str(rules.possession) == "player" else "%s checks it at the top of the key." % _rival())
	if mode == "match" and (not is_instance_valid(opponent) or not opponent.present or opponent.leaving):
		_end_match("Your opponent had to go · game over.", true)
		return
	if not available:
		return
	var away: float = court.outside_distance(_player.global_position)
	if mode == "result":
		_result_time -= delta
		if _result_time <= 0.0 or away > LEAVE_WARN:
			_end_match("", false)
		return
	_referee(delta)
	if rules == null:
		return
	if away > LEAVE_FAR:
		_end_match("You left the court · game abandoned.", true)
		return
	_leave_time = _leave_time + delta if away > LEAVE_WARN else 0.0
	if _leave_time > LEAVE_SECONDS:
		_end_match("You left the court · game abandoned.", true)
		return
	_aggro_check -= delta
	if _aggro_check <= 0.0:
		_aggro_check = 0.5
		if _fight_nearby():
			_end_match("A scuffle broke out nearby · game called off.", true)

## Possession facts the rules cannot see: clearing the arc, holders stepping
## out, and loose balls nobody goes after.
func _referee(delta: float) -> void:
	if str(rules.phase) != "live":
		_loose_time = 0.0
		_holder_inbounds = false
		return
	var holder := str(rules.holder)
	if holder == "player":
		_loose_time = 0.0
		if _held != session:
			_end_match("The game ball left play · game over.", true)
			return
		var feet := _player.global_position
		_holder_inbounds = _holder_inbounds or court.outside_distance(feet) <= 0.0
		if bool(rules.needs_clear) and court.beyond_arc(feet):
			rules.clear("player")
			_say("Cleared · now attack the basket.")
		elif _holder_inbounds and court.outside_distance(feet, CENTRE_SLACK) > HOLDER_OUT:
			_holder_out("player")
	elif holder == "opponent":
		_loose_time = 0.0
		var at := opponent.global_position
		_holder_inbounds = _holder_inbounds or court.outside_distance(at) <= 0.0
		if bool(rules.needs_clear) and court.beyond_arc(at):
			rules.clear("opponent")
		elif _holder_inbounds and court.outside_distance(at, CENTRE_SLACK) > HOLDER_OUT:
			_holder_out("opponent")
	else:
		_holder_inbounds = false
		_loose_time += delta
		if _loose_time > LOOSE_LIMIT:
			_loose_time = 0.0
			rules.out_of_bounds()
			_say("Nobody went after it · %s at the top." % _possession_text())

func _holder_out(side: String) -> void:
	var ball: Dictionary = balls[session]
	if side == "player":
		_held = -1
		cancel_charge()
	elif is_instance_valid(opponent):
		opponent.holding = false
	ball.holder = ""
	ball.active = true
	ball.age = 0.0
	ball.body.velocity = Vector3.ZERO
	rules.out_of_bounds(side)
	if side == "player":
		_say("You stepped out of bounds · %s." % _possession_text())
	else:
		_say("%s stepped out of bounds · your ball." % _rival())
	_sfx("whistle")

func _follow_opponent_ball() -> void:
	var ball: Dictionary = balls[session]
	if not opponent.holding or str(ball.holder) != "opponent":
		return
	ball.body.global_position = opponent.ball_point()
	if opponent.dribble_bounced:
		_bounce_sound(court.on_floor(ball.body.global_position))

## Never leave the regular wedged or wandering: stand them back on the court.
func _watch_opponent() -> void:
	if opponent.leaving:
		return
	var at := opponent.global_position
	var lost: bool = not at.is_finite() or at.y < float(court.floor_y(at)) - 3.0 or float(court.outside_distance(at)) > 12.0
	if not lost and opponent.stalled < 5.0:
		return
	for candidate in [court.free_throw_spot(), court.check_spot(), court.spot(2.0, 1.2), court.spot(2.0, -1.2)]:
		var spot := _standing_point(candidate)
		if spot.is_finite() and spot.distance_to(_player.global_position) > 1.5:
			opponent.global_position = spot
			opponent.stalled = 0.0
			opponent.reset_plan()
			return
	_end_match("Your opponent had to go · game over.", true)

func _fight_nearby() -> bool:
	var combat = _level.get("combat")
	if combat == null or not combat.has_method("get_status"):
		return false
	var status = combat.get_status()
	return status is Dictionary and int(status.get("aggro_count", 0)) > 0

func _court_at(point: Vector3, margin: float) -> int:
	var nearest := -1
	var best := INF
	for i in frames.size():
		var frame = frames[i]
		if not frame.playable() or not frame.contains(point, margin):
			continue
		var distance: float = point.distance_squared_to(frame.center)
		if distance < best:
			best = distance
			nearest = i
	return nearest

# ------------------------------------------------------------------ opponent bridge

func player_position() -> Vector3:
	return _player.global_position

func match_ball_position() -> Vector3:
	return balls[session].body.global_position if session >= 0 else Vector3.ZERO

func match_ball_velocity() -> Vector3:
	if session < 0 or not balls[session].active:
		return Vector3.ZERO
	return balls[session].body.velocity

func match_ball_pickable(side: String) -> bool:
	return rules != null and session >= 0 and _can_pick(session, side)

func opponent_pick_up() -> bool:
	if rules == null or mode != "match" or not is_instance_valid(opponent) or not opponent.present or opponent.holding:
		return false
	if not _can_pick(session, "opponent"):
		return false
	var ball: Dictionary = balls[session]
	var at: Vector3 = ball.body.global_position
	if Vector2(at.x - opponent.global_position.x, at.z - opponent.global_position.z).length() > OPPONENT_REACH:
		return false
	if ball.active and ball.body.velocity.length() > 7.0:
		return false
	_resolve_release(session)
	var event: Dictionary = rules.pick_up("opponent", court.beyond_arc(opponent.global_position))
	if event.is_empty():
		return false
	ball.holder = "opponent"
	ball.active = false
	ball.scored = false
	ball.release = {}
	ball.body.velocity = Vector3.ZERO
	opponent.holding = true
	opponent.reset_plan()
	_announce_pickup(event)
	return true

## The opponent's release: a real launch from the gathered ball toward the rim,
## off by a seeded aim error that grows with distance. Physics decides the rest.
func opponent_shoot() -> bool:
	if rules == null or mode != "match" or not is_instance_valid(opponent) or not opponent.holding or str(rules.holder) != "opponent":
		return false
	var ball: Dictionary = balls[session]
	var from: Vector3 = opponent.ball_point()
	var basket: Vector3 = court.rim()
	var flat := Vector3(basket.x - from.x, 0.0, basket.z - from.z)
	var distance := maxf(flat.length(), 0.05)
	var target := basket + _aim_error(distance, flat / distance)
	var to := Vector3(target.x - from.x, 0.0, target.z - from.z)
	var reach := maxf(to.length(), 0.05)
	var rise := target.y - from.y
	# Steep enough to drop through the ring instead of clipping its front.
	var angle := clampf(atan(1.05 + 2.0 * rise / reach), deg_to_rad(45.0), deg_to_rad(72.0))
	var speed := Court.launch_speed(reach, rise, angle, GRAVITY, _step())
	if speed <= 0.0:
		speed = 7.5
	_make_room_for_throw()
	ball.holder = ""
	ball.body.global_position = from
	ball.body.velocity = (to / reach * cos(angle) + Vector3.UP * sin(angle)) * speed
	ball.active = true
	ball.age = 0.0
	ball.scored = false
	ball.nudges = 0
	opponent.holding = false
	var value: int = court.shot_value(opponent.global_position)
	_begin_release(session, "opponent", true, value, basket)
	rules.release("opponent", value, true)
	return true

func _aim_error(distance: float, direction: Vector3) -> Vector3:
	var sigma := (0.07 + 0.012 * distance) * opponent_accuracy
	var lateral := Vector3(-direction.z, 0.0, direction.x)
	return direction * rng.randfn(0.0, 1.0) * sigma + lateral * rng.randfn(0.0, 1.0) * sigma + opponent_aim_bias

## Where the opponent wants to shoot from this possession: drives, mid-range or
## beyond the arc, leaning long when trailing or needing exactly two.
func opponent_plan() -> Vector3:
	var mine := int(rules.score.opponent)
	var theirs := int(rules.score.player)
	var long_bias := 0.22 + (0.2 if theirs - mine >= 3 else 0.0) + (0.25 if int(rules.target) - mine == 2 else 0.0)
	var roll := rng.randf()
	var spot: Vector3
	if roll < long_bias:
		spot = court.spot(float(court.arc_radius()) + 0.6, rng.randf_range(-0.9, 0.9))
	elif roll < long_bias + 0.38:
		spot = court.spot(rng.randf_range(2.6, 4.2), rng.randf_range(-1.1, 1.1))
	else:
		spot = court.spot(1.2, rng.randf_range(-0.7, 0.7))
	return court.clamp_in_play(spot, 0.45)

func _announce_pickup(event: Dictionary) -> void:
	var mine := str(event.get("side", "")) == "player"
	var clear := bool(event.get("needs_clear", false))
	match str(event.get("kind", "")):
		"defensive_rebound":
			if mine:
				_say("Rebound · take it back beyond the arc." if clear else "Rebound · attack the basket.")
			else:
				_say("%s grabs the rebound." % _rival())
		"offensive_rebound":
			_say("Offensive rebound · put it back up." if mine else "%s keeps the possession alive." % _rival())
		"loose_ball":
			if mine:
				_say("Loose ball is yours · clear it past the arc." if clear else "Loose ball is yours · attack.")
			else:
				_say("%s scoops up the loose ball." % _rival())
		"check":
			if mine:
				_say("Checked · take it back beyond the arc." if clear else "Checked · attack the basket.")

# ------------------------------------------------------------------ feedback

func interaction_prompt() -> String:
	if not _world_running():
		return ""
	var playable := _playable()
	var lines: Array[String] = []
	if rules != null:
		lines.append(_score_line())
		var guidance := _match_guidance() if playable else "Game on hold"
		if not guidance.is_empty():
			lines.append(guidance)
	elif not playable:
		return ""
	if playable:
		var controls := _control_line()
		if not controls.is_empty():
			lines.append(controls)
		if mode == "shootaround" and int(shootaround.get("attempts", 0)) > 0:
			lines.append("SHOOTAROUND %d/%d · streak %d · best %d" % [int(shootaround.makes), int(shootaround.attempts), int(shootaround.streak), int(shootaround.best)])
	if _notice_time > 0.0 and not _notice.is_empty() and not lines.has(_notice):
		lines.append(_notice)
	return "\n".join(lines)

func _score_line() -> String:
	return "PICKUP · YOU %d – %d %s · FIRST TO %d" % [int(rules.score.player), int(rules.score.opponent), _rival().to_upper(), int(rules.target)]

func _match_guidance() -> String:
	var name_ := _rival()
	if mode == "result":
		return ("You won! " if str(rules.winner) == "player" else "%s won. " % name_) + "%s · rematch · walk away to leave" % _key("city_basketball_challenge")
	if _leave_time > 0.0:
		return "Head back to the court · game ends in %ds" % ceili(LEAVE_SECONDS - _leave_time)
	match str(rules.phase):
		"check":
			if str(rules.possession) == "player":
				return "Your ball · pick it up at the top of the key (%s)" % _key("city_interact")
			return "%s checks the ball at the top · get on defense" % name_
		"dead":
			return "Dead ball · %s next" % _possession_text()
		"live":
			if str(rules.holder) == "player":
				if bool(rules.needs_clear):
					return "Your ball · take it back beyond the arc first"
				return "Your ball · worth %d from here" % int(court.shot_value(_player.global_position))
			if str(rules.holder) == "opponent":
				return ("%s is clearing it" if bool(rules.needs_clear) else "%s's ball · guard the basket") % name_
			if not rules.shot.is_empty() and not bool(rules.shot.touched):
				return "Shot up!"
			return "Loose ball · rebound it (%s)" % _key("city_interact")
	return ""

func _control_line() -> String:
	var shoot_key := _key("city_ball_shoot")
	var challenge_key := _key("city_basketball_challenge")
	var challenge_here := rules == null and _court_at(_player.global_position, CHALLENGE_MARGIN) >= 0
	if _held >= 0:
		if _charging:
			var ideal := float(_plan.get("ideal", -1.0))
			var aim_hint := str(_plan.get("hint", ""))
			if ideal >= 0.0:
				var window := float(_plan.window)
				aim_hint = "green %d–%d%%" % [roundi(clampf(ideal - window, 0.0, 1.0) * 100.0), roundi(clampf(ideal + window, 0.0, 1.0) * 100.0)]
			return "Shot power %d%%%s · release %s to shoot" % [roundi(_charge * 100.0), "" if aim_hint.is_empty() else " · " + aim_hint, shoot_key]
		var line := "Aim with mouse · hold %s to charge, release to shoot · %s drop" % [shoot_key, _key("city_interact")]
		if mode != "match":
			line += " · %s return" % _key("city_ball_return")
		if challenge_here:
			line += " · %s challenge" % challenge_key
		return line
	if _nearest_ball() >= 0:
		var pickup := "%s · Pick up basketball" % _key("city_interact")
		if challenge_here:
			pickup += "  ·  %s · Challenge a court regular to 11" % challenge_key
		return pickup
	if challenge_here:
		return "%s · Challenge a court regular to 11" % challenge_key
	if mode == "match":
		return "%s twice · quit game" % challenge_key
	return ""

func _possession_text() -> String:
	var side := str(rules.possession) if rules != null else ""
	if side == "player":
		return "your ball"
	if side == "opponent":
		return "%s's ball" % _rival()
	return "loose ball"

func _score_text() -> String:
	return "You %d–%d %s" % [int(rules.score.player), int(rules.score.opponent), _rival()]

func _rival() -> String:
	return str(opponent.display_name) if is_instance_valid(opponent) else "Your opponent"

static func _key(action: String) -> String:
	var label := Bindings.label(action)
	return "LMB" if label == "Left mouse" else label

func _say(text: String, seconds := 3.0) -> void:
	_notice = text
	_notice_time = seconds

## Important one-off messages go through the level's notice queue, so they are
## seen even after walking away; the activity line carries them otherwise.
func _announce(text: String) -> void:
	if is_instance_valid(_level) and _level.has_method("show_notice"):
		_level.show_notice(text)
	else:
		_say(text, 4.0)

func _sfx(sound: String) -> void:
	var audio := get_node_or_null("/root/Audio")
	if audio != null and audio.has_method("sfx"):
		audio.sfx(sound)

func _bounce_sound(at: Vector3) -> void:
	var ambience := _level.get_node_or_null("NeighborhoodAudio")
	if ambience != null:
		ambience.play_activity("court_bounce", at)

func _build_meter() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ShotMeter"
	layer.layer = 13
	add_child(layer)
	_meter = Control.new()
	_meter.name = "Power"
	_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_meter.anchor_left = 0.5
	_meter.anchor_right = 0.5
	_meter.anchor_top = 1.0
	_meter.anchor_bottom = 1.0
	_meter.offset_left = -METER_WIDTH * 0.5
	_meter.offset_right = METER_WIDTH * 0.5
	_meter.offset_top = -148.0
	_meter.offset_bottom = -132.0
	layer.add_child(_meter)
	_meter_rect(Color(0.07, 0.09, 0.10, 0.78), Vector2(METER_WIDTH, 16.0))
	_meter_window = _meter_rect(Color(0.38, 0.80, 0.46, 0.9), Vector2(0.0, 16.0))
	_meter_fill = _meter_rect(Color(0.96, 0.56, 0.16, 0.95), Vector2(0.0, 8.0))
	_meter_fill.position.y = 4.0
	_meter_mark = _meter_rect(Color(1, 1, 1, 0.95), Vector2(2.0, 16.0))
	_meter.hide()

func _meter_rect(color: Color, extent: Vector2) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.size = extent
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_meter.add_child(rect)
	return rect

## Charging shows power against the clean-release window for the current arc.
func _update_meter() -> void:
	if _meter == null:
		return
	_meter.visible = _charging and _held >= 0
	if not _meter.visible:
		return
	_plan = shot_plan(_held, balls[_held].body.global_position)
	_meter_fill.size.x = METER_WIDTH * _charge
	var ideal := float(_plan.ideal)
	_meter_window.visible = ideal >= 0.0
	_meter_mark.visible = ideal >= 0.0
	if ideal >= 0.0:
		var low := clampf(ideal - float(_plan.window), 0.0, 1.0)
		var high := clampf(ideal + float(_plan.window), 0.0, 1.0)
		_meter_window.position.x = METER_WIDTH * low
		_meter_window.size.x = METER_WIDTH * (high - low)
		_meter_mark.position.x = METER_WIDTH * ideal - 1.0

func set_presence(center: Vector3, _near_radius := 55.0, _far_radius := 180.0) -> void:
	for i in balls.size():
		balls[i].visual.visible = i == _held or center.distance_squared_to(balls[i].body.global_position) < ACTIVE_DISTANCE * ACTIVE_DISTANCE

func get_status() -> Dictionary:
	var active := 0
	var visible_count := 0
	for ball in balls:
		active += int(ball.active)
		visible_count += int(ball.visual.visible)
	var status := {"enabled": not balls.is_empty(), "balls": balls.size(), "active": active,
		"visible": visible_count, "held": _held >= 0, "charging": _charging, "charge": _charge,
		"shots": shots, "baskets": baskets, "max_active": MAX_ACTIVE, "mode": mode,
		"court": str(court.id) if court != null else "", "persistent": false,
		"opponent_present": is_instance_valid(opponent) and opponent.present,
		"opponent_instances": opponent_instances, "opponent_appearances": opponent_appearances,
		"games_started": games_started, "shootaround": shootaround.duplicate()}
	if rules != null:
		status["match"] = rules.summary()
	if not last_result.is_empty():
		status["last_match"] = last_result.duplicate()
	return status

func _make_ball_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	const SLICES := 32
	const RINGS := 16
	for ring in RINGS:
		for segment in SLICES:
			for corner in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var latitude := PI * float(ring + corner.y) / RINGS
				var longitude := TAU * float(segment + corner.x) / SLICES
				var normal := Vector3(sin(latitude) * cos(longitude), cos(latitude), sin(latitude) * sin(longitude))
				vertices.append(normal * BALL_RADIUS)
				normals.append(normal)
				var seam := absf(normal.y) < 0.025 or absf(normal.x) < 0.025 or absf(normal.z) < 0.025
				colors.append(Color(0.10, 0.045, 0.016) if seam else Color(0.88, 0.30, 0.055))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.92
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, material)
	return mesh
