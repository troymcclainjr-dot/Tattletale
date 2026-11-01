extends CharacterBody3D
## Player bicycle. Root owns tick/input ordering; this never enters car damage/law.
## Motion is a kinematic solver rather than move_and_slide:
## * A raised hull (three capsules from HULL_CLEARANCE up) sweeps horizontally,
##   so walls, posts, cars and people block it and it slides along them, while
##   curbs and other low risers never touch it.
## * Ray-sampled wheel contact patches decide height. Each sample is read as the
##   rest height of a WHEEL_RADIUS tyre over it, so the bike rolls up any riser up
##   to STEP_HEIGHT at any approach angle or speed, onto raised and mixed ground.
##   Taller risers, steep faces and overhangs block instead of teleporting.
## * Contacts are judged by the closing speed of the RELATIVE velocity along the
##   contact normal: scrapes slide with friction and swing the bike along the
##   obstacle (it glances off posts), bumps recoil, crashes eject the rider
##   (city_bicycle_crash.gd) while the riderless bicycle recoils, slides and falls.
## Nothing here deals damage or reaches law, money or alignment.
## Contract: .work/pacifist-foundation/bike-contract.md
## Checkpoint hooks: .work/five-priorities-20261101/bicycle-save-contract.md
signal mounted
signal dismounted
signal pedestrian_contact(contact: Dictionary)
signal avoidance_requested(at: Vector3, motion: Vector3)
signal impact(event: Dictionary)
signal rider_ejected(event: Dictionary)
signal rider_recovered(event: Dictionary)

const CrashRig := preload("res://scripts/city/city_bicycle_crash.gd")
const MAX_SPEED := 9.0
const SPRINT_SPEED := 12.0
const REVERSE_SPEED := 2.4
const ACCELERATION := 3.8
const BRAKING := 12.0
const GRAVITY := 22.0
const HOP_SPEED := 6.2
const HOP_BUFFER := 0.14
const STEP_HEIGHT := 0.30
const HULL_FOOT_OFFSET := 0.015
## The collision hull starts above every climbable riser; the wheels own below.
const HULL_CLEARANCE := 0.31
const HULL_TOP := 1.465
const HULL_RADIUS := 0.28
## The three hull capsules sit at -/0/+ this far along the frame.
const HULL_HALF_SPAN := 0.52
const SNAP_DOWN := 0.32
const MOUNT_DISTANCE := 2.7
const EXIT_SPEED := 1.5
const WHEEL_RADIUS := 0.34
const REAR_AXLE := -0.67
const FRONT_AXLE := 0.68
const CRANK := -0.10
const CRANK_CLEARANCE := 0.18
## Offsets along the frame around each axle: the tyre's contact patch profile.
const WHEEL_SAMPLES := [-0.22, -0.11, 0.0, 0.11, 0.22]
const WORLD_MASK := 1 | 2 | 8 | 16
const SUPPORT_MASK := 1 | 2
## Closing speed (m/s, relative velocity along the contact normal) thresholds.
const SCRAPE_SPEED := 1.8
const CRASH_SPEED := 6.0
const BUMP_RESTITUTION := 0.3
const CONTACT_FRICTION := 0.35
const SLIP_DECAY := 6.5
const RIDERLESS_FRICTION := 5.5
const IMPACT_DEDUPE := 0.5
const PERSON_COOLDOWN := 2.0
## Bike plus rider against a pedestrian, for the reported push impulse (kg).
const REDUCED_MASS := 42.0
const MAX_CRASH_TIME := 7.0
const TURN_SHRINK := 0.015
## Checkpoints: a ridden bicycle saves only below this speed (m/s), and a saved
## pose must find wheel support within this height of where it was written.
const SAVE_VERSION := 1
const SAVE_STILL_SPEED := 0.05
const SAVE_SUPPORT_REACH := 0.35
## A standing explorer's capsule (city_player: radius 0.30) plus a little room.
const STANDING_RADIUS := 0.32
const STANDING_HEIGHT := 1.74

var level: Node3D
var player: CharacterBody3D
var active := false
var speed := 0.0
var yaw := 0.0
var spawned := false
var input_override: Dictionary = {}
var _visual: Node3D
var _front: Node3D
var _wheels: Array[Node3D] = []
var _rider: Puppet
var _legs: Array[MeshInstance3D] = []
var _shoes: Array[MeshInstance3D] = []
var _pedals: Array[MeshInstance3D] = []
var _phase := 0.0
var _near_clock := 0.0
var _clock := 0.0
var _contact_until: Dictionary = {}
var _impact_until: Dictionary = {}
var _last_seat := Vector3.INF
var _message := ""
var _message_until := 0.0
var _parked_position := Vector3.ZERO
var _saved_chase := 6.2
var contacts := 0
var avoidance_ticks := 0
var steps_climbed := 0
var hops_started := 0
var impacts := 0
var crashes := 0
var last_impact: Dictionary = {}
var debug_step_reason := "not attempted"
var _colliders: Array[CollisionShape3D] = []
var _shrunk_shapes: Dictionary = {}
var _support_rids: Array[RID] = []
var _steer := 0.0
var _hop_buffer := 0.0
var _hop_held := false
var _hop_active := false
## Kept for fixtures written against the previous solver; the wheels need no grace.
var _curb_grace := 0.0
var _sprinting := false
var _grounded := true
var _climbing := false
var _support: Dictionary = {}
## Horizontal velocity not along the frame (recoil, sideways slide), decays.
var _slip := Vector3.ZERO
var _yaw_deflect := 0.0
var _wobble := 0.0
var _jolt := 0.0
var _visual_pitch := 0.0
var _visual_drop := 0.0
var _crash: CrashRig
var _crashed := false
var _crash_heading := 0.0
var _crash_recovery: Dictionary = {}
var _recovery_retry := 0.0
var _fallen := false
var _fall_amount := 0.0
var _fall_side := 1.0
var _settling := false
var _spin_rate := 0.0
var _trail: Array[Vector3] = []
var _trail_clock := 0.0
var _mount_spot := Vector3.INF
var _impact_serial := 0

func setup(owner_level: Node3D) -> void:
	level = owner_level
	player = level.get("player") as CharacterBody3D
	name = "PlayerBicycle"
	collision_layer = 16
	collision_mask = WORLD_MASK
	floor_max_angle = deg_to_rad(46.0)
	var hull_height := HULL_TOP - HULL_CLEARANCE
	for z in [-HULL_HALF_SPAN, 0.0, HULL_HALF_SPAN]:
		var shape := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = HULL_RADIUS
		capsule.height = hull_height
		shape.shape = capsule
		shape.position = Vector3(0.0, HULL_CLEARANCE + hull_height * 0.5, z)
		add_child(shape)
		_colliders.append(shape)
	_build_model()
	_support_rids = [get_rid()]
	if player == null:
		visible = false
		collision_layer = 0
		return
	_crash = CrashRig.new()
	add_child(_crash)
	_crash.setup(self, player)
	_support_rids = [get_rid(), player.get_rid(), _crash.get_rid(), _crash.rider_rid()]
	# The upright hull is a coarse proxy for a few thin tubes (and stays upright
	# when the bicycle lies fallen): the explorer's camera never sweeps against it.
	var camera_ignore = player.get("camera_ignore")
	if camera_ignore is Array:
		camera_ignore.append(get_rid())
	yaw = float(player.get("yaw"))
	rotation.y = yaw
	var at := _find_parking(player.global_position)
	if at.is_finite():
		global_position = at
		_parked_position = at
		spawned = true
		return
	visible = false
	collision_layer = 0
	_flash("No clear bicycle parking spot nearby")

## Short bounded search on actual ground beside `origin`, with the complete
## bike hull clear at the current yaw. INF when nothing nearby fits.
func _find_parking(origin: Vector3) -> Vector3:
	for radius in [2.1, 3.0, 4.0, 5.0]:
		for step in 12:
			var angle := yaw + PI * 0.5 + float(step) * TAU / 12.0
			var wanted := origin + Vector3(sin(angle), 0.0, cos(angle)) * float(radius)
			var spot := _ground(wanted)
			if spot.is_empty():
				continue
			var at: Vector3 = spot.position + Vector3.UP * 0.01
			if absf(at.y - origin.y) > 0.65 or not _bike_clear(at):
				continue
			return at
	return Vector3.INF

func tick(delta: float) -> void:
	if not spawned or not is_instance_valid(player) or _paused() or delta <= 0.0:
		return
	_clock += delta
	if _crashed:
		_tick_crash(delta)
		return
	if not active:
		if _settling:
			_tick_riderless(delta)
		return
	# Recovery/checkpoint systems can relocate the explorer independently.
	if _last_seat.is_finite() and player.global_position.distance_squared_to(_last_seat) > 0.75 * 0.75:
		recovery_exit_at(player.global_position, float(player.get("yaw")))
		return
	var controls := _read_controls()
	var move: Vector2 = controls.move
	var brake: bool = controls.brake
	var hop_held := bool(controls.get("hop", false))
	if hop_held and not _hop_held:
		_hop_buffer = HOP_BUFFER
	_hop_held = hop_held
	_hop_buffer = maxf(0.0, _hop_buffer - delta)
	_wobble = maxf(0.0, _wobble - delta)
	var old_yaw := yaw
	var target_speed := 0.0
	var acceleration := 2.0
	_sprinting = bool(controls.get("sprint", false)) and move.y > 0.0 and not brake
	if brake:
		acceleration = BRAKING
	elif move.y > 0.01:
		target_speed = (SPRINT_SPEED if _sprinting else MAX_SPEED) * move.y
		acceleration = BRAKING if speed < -0.05 else (ACCELERATION * 1.5 if _sprinting else ACCELERATION)
		if _wobble > 0.0 and speed >= -0.05:
			acceleration *= 0.35 # Regaining balance after a knock.
	elif move.y < -0.01:
		# Holding S brakes a forward-moving bicycle before backing it up slowly.
		target_speed = 0.0 if speed > 0.05 else REVERSE_SPEED * move.y
		acceleration = BRAKING if speed > 0.05 else ACCELERATION * 0.65
	speed = move_toward(speed, target_speed, delta * acceleration)
	_steer = move_toward(_steer, move.x, delta * 5.0)
	# Positive steering is the rider's right (-X when facing +Z). The camera
	# is only a view: orbiting it cannot change throttle or steering direction.
	var turn_rate := lerpf(2.1, 1.25, clampf(absf(speed) / SPRINT_SPEED, 0.0, 1.0))
	var turning := -_steer * turn_rate * clampf(absf(speed) / 2.0, 0.25, 1.0) * (-1.0 if speed < -0.05 else 1.0)
	_try_turn(turning * delta * (0.4 if _hop_active else 1.0))
	if absf(_yaw_deflect) > 0.0005:
		# A glancing touch swings the frame along the obstacle over a few frames.
		# The travelling velocity is kept and re-split between pedal speed and slip.
		var travelling := Vector3(sin(yaw), 0.0, cos(yaw)) * speed + _slip
		var swing := clampf(_yaw_deflect, -3.0 * delta, 3.0 * delta)
		if _try_turn(swing):
			_yaw_deflect -= swing
			var aligned := Vector3(sin(yaw), 0.0, cos(yaw))
			var along_frame := travelling.dot(aligned)
			speed = clampf(along_frame, 0.0, SPRINT_SPEED) if speed >= 0.0 else clampf(along_frame, -REVERSE_SPEED, 0.0)
			_slip = travelling - aligned * speed
		else:
			_yaw_deflect = 0.0
	rotation.y = yaw
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	var planar := forward * speed + _slip
	if _grounded and not _hop_active and _hop_buffer > 0.0 and bool(player.get("enabled")):
		velocity.y = HOP_SPEED
		_hop_buffer = 0.0
		_hop_active = true
		_grounded = false
		hops_started += 1
	var before := global_position
	var commanded_speed := speed
	var touched: Array[Dictionary] = []
	_move(planar, delta, touched)
	var moved := global_position - before
	moved.y = 0.0
	# Slip pressing into what it touched is spent on that contact first.
	_absorb_slip(touched)
	# Pedalling speed only loses what walls, risers and people actually removed.
	# The slip left over moved the bike too, but it is not pedalled: measure
	# progress net of its share, or steering off the slip's line would brake
	# the pedals on every frame until the slip decayed.
	var along := moved.dot(forward) / delta - _slip.dot(forward)
	if speed > 0.0:
		speed = clampf(along, 0.0, speed)
	elif speed < 0.0:
		speed = clampf(along, speed, 0.0)
	_slip = _slip.move_toward(Vector3.ZERO, SLIP_DECAY * delta)
	_resolve_contacts(touched, planar, forward, absf(commanded_speed))
	if _crashed:
		return
	velocity.x = moved.x / delta
	velocity.z = moved.z / delta
	_phase += moved.length() * (-1.0 if commanded_speed < 0.0 else 1.0) / WHEEL_RADIUS
	_animate(delta, angle_difference(old_yaw, yaw) / maxf(delta, 0.001))
	_remember_trail(delta)
	player.follow_vehicle()
	_last_seat = player.global_position
	_near_clock -= delta
	if absf(speed) > 0.8 and _near_clock <= 0.0:
		_near_clock = 0.1
		avoidance_ticks += 1
		avoidance_requested.emit(global_position, Vector3(velocity.x, 0.0, velocity.z))
	# Sparse contact cooldowns expire without retaining the whole population.
	for id in _contact_until.keys():
		if float(_contact_until[id]) < _clock:
			_contact_until.erase(id)
	for id in _impact_until.keys():
		if float(_impact_until[id].until) < _clock:
			_impact_until.erase(id)

func handle_input(event: InputEvent) -> bool:
	if not spawned or _paused() or player == null:
		return false
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_F or event.physical_keycode == KEY_F):
		if active:
			exit_vehicle()
			return true
		if player.global_position.distance_to(global_position) <= MOUNT_DISTANCE:
			enter_bicycle()
			return true
	if not active:
		return false
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_SPACE or event.physical_keycode == KEY_SPACE):
		if not _crashed:
			_hop_buffer = HOP_BUFFER
		elif _crash.is_down():
			_crash.get_up_requested = true
		return true
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or DisplayServer.get_name() == "headless":
			player.vehicle_look(event.screen_relative)
		return true
	if event is InputEventMouseButton:
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			player.vehicle_zoom(1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
		return true
	if event is InputEventKey:
		return event.keycode in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_SPACE, KEY_SHIFT] \
			or event.physical_keycode in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_SPACE, KEY_SHIFT]
	return false

func enter_bicycle() -> bool:
	if not spawned or active or player == null or _paused() or not bool(player.get("enabled")) or player.is_seated():
		return false
	if player.global_position.distance_to(global_position) > MOUNT_DISTANCE:
		return false
	var ray := PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP, global_position + Vector3.UP, 1 | 2 | 16)
	ray.exclude = [get_rid(), player.get_rid()]
	if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
		_flash("Walk around to the bicycle")
		return false
	var combat = level.get("combat")
	if combat != null and combat.has_method("cancel_player_actions"):
		combat.cancel_player_actions()
	var phone = player.get("phone")
	if phone != null and bool(phone.get("active")):
		_flash("Put away the phone before riding")
		return false
	_seat_rider(player.global_position)
	return true

## Seats the explorer on the upright bicycle (mounting, or a mounted restore).
func _seat_rider(mount_spot: Vector3) -> void:
	if _fallen or _settling:
		_pick_up()
	active = true
	_mount_spot = mount_spot
	reset_motion_state()
	_trail.clear()
	_saved_chase = float(player.get("chase_distance"))
	player.set("chase_distance", 4.8)
	player.enter_vehicle(self)
	_rider.g.visible = true
	for part in _legs + _shoes:
		part.visible = true
	_last_seat = player.global_position
	_animate(0.0, 0.0)
	mounted.emit()

func exit_vehicle(force := false) -> bool:
	if not active:
		return false
	if _crashed:
		if not force:
			_flash("Wait until you're back on your feet")
			return false
		# Law/recovery release: only to a verified spot, never invented coordinates.
		var spot := _recovery_spot(false)
		if spot.is_empty():
			return false
		_end_crash(spot.position, float(spot.heading), "forced")
		return true
	if absf(speed) > EXIT_SPEED and not force:
		_flash("Brake to a stop before getting off")
		return false
	if _hop_active and not force:
		_flash("Land before getting off")
		return false
	var at := _exit_spot([1.0, 1.4, 2.0, 3.0] if force else [1.0, 1.4])
	if at.is_finite():
		_finish_exit(at, yaw)
		return true
	_flash("Move to a clear spot to get off")
	return false

## A verified spot beside the frame where the explorer can stand (INF: none):
## ground within reach, a clear standing capsule and an unobstructed step off.
## `avoid`: a pose the bicycle is about to take, which the spot must keep clear.
func _exit_spot(radii: Array, avoid: Variant = null) -> Vector3:
	for radius in radii:
		for side in [1.0, -1.0]:
			var wanted := global_position + Vector3(cos(yaw), 0.0, -sin(yaw)) * float(radius) * float(side)
			var spot := _ground(wanted)
			if spot.is_empty():
				continue
			var at: Vector3 = spot.position + Vector3.UP * 0.05
			if absf(at.y - global_position.y) > 0.65 or not _standing_clear(at):
				continue
			var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP, at + Vector3.UP, 1 | 2 | 8 | 16)
			ray.exclude = [get_rid(), player.get_rid()]
			if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
				continue
			if avoid is Transform3D and _hull_reaches(avoid, at):
				continue
			return at
	return Vector3.INF

func recovery_exit_at(at: Vector3, heading: float) -> bool:
	if not active or not at.is_finite() or not is_finite(heading):
		return false
	if _crashed:
		_end_crash(at, heading, "relocated")
		return true
	_finish_exit(at, heading)
	return true

func _finish_exit(at: Vector3, heading: float) -> void:
	active = false
	speed = 0.0
	velocity = Vector3.ZERO
	_hop_active = false
	_hop_buffer = 0.0
	_hop_held = false
	_curb_grace = 0.0
	_steer = 0.0
	_yaw_deflect = 0.0
	_wobble = 0.0
	if not _settling:
		_slip = Vector3.ZERO
	if not _fallen:
		_visual.rotation.z = 0.0
	_rider.g.visible = false
	for part in _legs + _shoes:
		part.visible = false
	player.leave_vehicle(at, heading)
	player.set("chase_distance", _saved_chase)
	_parked_position = global_position
	_last_seat = Vector3.INF
	dismounted.emit()

func set_control_override(move: Vector2, brake := false, sprint := false, hop := false) -> void:
	input_override = {"move": move.clamp(Vector2(-1.0, -1.0), Vector2.ONE), "brake": brake, "sprint": sprint, "hop": hop}

func clear_control_override() -> void:
	input_override.clear()

## Fixtures that place the bicycle directly clear the transient solver state.
func reset_motion_state() -> void:
	velocity = Vector3.ZERO
	_slip = Vector3.ZERO
	_yaw_deflect = 0.0
	_wobble = 0.0
	_jolt = 0.0
	_grounded = true
	_climbing = false
	_hop_active = false
	_hop_buffer = 0.0
	_hop_held = false
	_curb_grace = 0.0
	_steer = 0.0
	_visual_pitch = 0.0
	_visual_drop = 0.0
	_support = {}

func is_crashed() -> bool:
	return _crashed

## The checkpoint provider refuses saves/loads while a crash plays out.
func blocks_checkpoint() -> bool:
	return _crashed

# ------------------------------------------------------------------ checkpoint hooks
# The save helper owns schema, versioning, ordering and rollback. These only
# report the bicycle's state truthfully and place it, never faking a dismount.

## "" when the bicycle's present state may be written into a checkpoint, else
## the player-facing reason. A parked bicycle only waits out a crash slide; a
## ridden one must be stopped, on its wheels, steady after any knock and clear.
func save_blocker() -> String:
	if not spawned or not is_instance_valid(player):
		return ""
	if _crashed:
		return "recovering from a bicycle crash"
	if not active:
		return "your bicycle is still settling" if _settling else ""
	if _hop_active or not _grounded or absf(velocity.y) > 0.001:
		return "land the bicycle before saving"
	if absf(speed) > SAVE_STILL_SPEED or _slip.length() > SAVE_STILL_SPEED or Vector2(velocity.x, velocity.z).length() > SAVE_STILL_SPEED:
		return "stop the bicycle before saving"
	var knocked := not last_impact.is_empty() and _clock - float(last_impact.get("time", -INF)) < IMPACT_DEDUPE
	if _wobble > 0.0 or absf(_yaw_deflect) >= 0.0005 or knocked:
		return "steady the bicycle before saving"
	var footing := pose_blocker(global_position, yaw)
	if not footing.is_empty():
		return footing
	if not player.is_seated() or player.get("seated_vehicle") != self:
		return "bicycle seat state is changing"
	return ""

## The facts a checkpoint needs, so the save helper never reads solver internals.
func persistence_state() -> Dictionary:
	return {"version": SAVE_VERSION, "spawned": spawned, "mounted": active, "crashed": _crashed,
		"settling": _settling, "fallen": _fallen, "grounded": _grounded, "airborne": _hop_active,
		"steady": _wobble <= 0.0 and absf(_yaw_deflect) < 0.0005, "speed": speed,
		"planar_speed": Vector2(velocity.x, velocity.z).length(), "slip": _slip.length(),
		"position": global_position, "yaw": yaw, "parked_position": _parked_position,
		"blocker": save_blocker()}

## "" when the bicycle could stand at `at` facing `heading`, else why not: real
## wheel support (a car roof never counts) within SAVE_SUPPORT_REACH of that
## height, and a clear upright hull. With `explorer`, a standing explorer is an
## obstacle too. Changes nothing.
func pose_blocker(at: Vector3, heading: float, explorer := false) -> String:
	if player == null or not is_inside_tree():
		return "bicycle unavailable"
	if not at.is_finite() or not is_finite(heading):
		return "invalid bicycle pose"
	var pose := _supported_pose(at, heading)
	if not pose.origin.is_finite():
		return "no stable ground under the bicycle"
	# The same pivot allowance riding tolerates: a frame at rest against a wall
	# is restorable; anything deeper than that is a genuine overlap.
	if not _hull_clear(pose, 0.0, TURN_SHRINK) or (explorer and not player.is_seated() and _hull_reaches(pose, player.global_position)):
		return "something is pressing against the bicycle"
	return ""

## Places the bicycle for a checkpoint restore or its rollback. Refuses and
## changes nothing mid-crash, on a pose pose_blocker() rejects, with the phone
## up (mounted), or with no verified spot for a seated explorer to step off to.
## mounted: the explorer rides it at that pose (no walk-up distance is needed,
## every motion state is cleared, the chase view starts behind `heading`).
## Not mounted: a seated explorer first steps off beside the current pose, to a
## spot clear of the new one; `fallen` lays the riderless bicycle on its side.
func restore_pose(at: Vector3, heading: float, mounted: bool, fallen := false) -> Dictionary:
	var result := {"ok": false, "reason": "", "mounted": active, "position": global_position, "yaw": yaw, "fallen": _fallen}
	if player == null or not is_inside_tree():
		result.reason = "bicycle unavailable"
		return result
	if _crashed:
		result.reason = "recovering from a bicycle crash"
		return result
	var blocker := pose_blocker(at, heading, not mounted)
	if not blocker.is_empty():
		result.reason = blocker
		return result
	var pose := _supported_pose(at, heading)
	if mounted and not active and player.is_seated():
		result.reason = "leave the vehicle first"
		return result
	var phone = player.get("phone")
	if mounted and not active and phone != null and bool(phone.get("active")):
		result.reason = "put away the phone before riding"
		return result
	var step_off := Vector3.INF
	if not mounted and active:
		step_off = _exit_spot([1.0, 1.4, 2.0, 3.0], pose)
		if not step_off.is_finite():
			result.reason = "no clear spot to step off the bicycle"
			return result
		_finish_exit(step_off, yaw)
	_place_at(pose, heading, fallen and not mounted)
	if mounted:
		if active:
			player.follow_vehicle()
			_mount_spot = global_position
			_last_seat = player.global_position
		else:
			var combat = level.get("combat")
			if combat != null and combat.has_method("cancel_player_actions"):
				combat.cancel_player_actions()
			player.set("camera_yaw", heading)
			# As when mounting: the spot they stood on is the crash fallback.
			_seat_rider(player.global_position)
		if player.has_method("reset_vehicle_view"):
			player.reset_vehicle_view(heading)
		_animate(0.0, 0.0)
	return {"ok": true, "reason": "", "mounted": active, "position": global_position, "yaw": yaw, "fallen": _fallen}

## Parks the riderless bicycle beside the explorer where they stand now, as
## setup() does (a checkpoint with no usable bicycle section). Refuses, changing
## nothing, while ridden or crashed or when no clear spot is nearby.
func park_beside_explorer() -> Dictionary:
	if player == null or not is_inside_tree():
		return {"ok": false, "reason": "bicycle unavailable"}
	if active or _crashed:
		return {"ok": false, "reason": "the bicycle is being ridden"}
	var previous_yaw := yaw
	yaw = float(player.get("yaw"))
	var at := _find_parking(player.global_position)
	if not at.is_finite():
		yaw = previous_yaw
		return {"ok": false, "reason": "no clear bicycle parking spot nearby"}
	_place_at(Transform3D(Basis(Vector3.UP, yaw), at), yaw, false)
	return {"ok": true, "reason": "", "position": global_position, "yaw": yaw}

## `at` settled onto its sampled wheel support (INF origin: none).
func _supported_pose(at: Vector3, heading: float) -> Transform3D:
	var pose := Transform3D(Basis(Vector3.UP, heading), at)
	var profile := _support_profile(pose, SAVE_SUPPORT_REACH)
	var height := float(profile.height)
	if bool(profile.blocked) or not is_finite(height) or absf(height - at.y) > SAVE_SUPPORT_REACH:
		pose.origin = Vector3.INF
	else:
		pose.origin.y = height
	return pose

## Puts the bicycle at rest at `pose`: every transient solver state cleared.
func _place_at(pose: Transform3D, heading: float, lying: bool) -> void:
	global_position = pose.origin
	yaw = heading
	rotation.y = heading
	reset_motion_state()
	speed = 0.0
	_settling = false
	_spin_rate = 0.0
	_trail.clear()
	_parked_position = pose.origin
	if not spawned:
		spawned = true
		visible = true
		collision_layer = 16
	if lying:
		_fallen = true
		_fall_amount = 1.0
		_fall_side = _choose_fall_side(_fall_side)
		_visual.rotation = Vector3.ZERO
		_front.rotation.y = 0.5 * _fall_side
		_animate_riderless(0.0)
	else:
		_pick_up()
	_support = _support_profile(global_transform, SNAP_DOWN)

func _read_controls() -> Dictionary:
	if not bool(player.get("enabled")):
		return {"move": Vector2.ZERO, "brake": true}
	if not input_override.is_empty():
		return input_override
	var move := Vector2(Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_forward") - Input.get_action_strength("move_back"))
	return {"move": move, "brake": false, "sprint": Input.is_action_pressed("run"),
		"hop": Input.is_physical_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_SPACE)}

# ------------------------------------------------------------------ motion solver

## One kinematic step: hop rise or fall, raised-hull sweep, then wheel support.
func _move(planar: Vector3, delta: float, touched: Array[Dictionary]) -> void:
	if not _grounded:
		velocity.y = maxf(-25.0, velocity.y - GRAVITY * delta)
		if velocity.y > 0.0 and move_and_collide(Vector3.UP * velocity.y * delta, false, safe_margin) != null:
			velocity.y = 0.0 # Low ceiling or canopy: the hop stops rising.
	var start := global_position
	var motion := Vector3(planar.x, 0.0, planar.z) * delta
	if motion.length_squared() > 0.0000001:
		_sweep(motion, touched)
	var reach := SNAP_DOWN if _grounded else maxf(SNAP_DOWN, -velocity.y * delta + 0.08)
	var profile := _support_profile(global_transform, reach)
	if bool(profile.blocked):
		var attempted := global_position - start
		var origin := Transform3D(global_basis, start)
		var already := _support_profile(origin, reach)
		# Backing or turning away from a riser that already blocked the old pose
		# stays possible; any move toward it is undone (the raised hull let it by).
		var blocked_at: Vector3 = profile.blocked_at
		if not bool(already.blocked) or Vector2(attempted.x, attempted.z).dot(Vector2(blocked_at.x - start.x, blocked_at.z - start.z)) > 0.0:
			var face := _riser_contact(profile, attempted)
			global_position = start
			debug_step_reason = str(profile.reason)
			profile = already
			if not face.is_empty():
				touched.append(face)
				# Slide along the riser as along a wall: keep the parallel motion.
				var normal: Vector3 = face.normal
				var along_face := motion - normal * minf(0.0, motion.dot(normal))
				if along_face.length_squared() > 0.000001:
					_sweep(along_face, touched)
					var slid := _support_profile(global_transform, reach)
					if bool(slid.blocked):
						global_position = start
					else:
						profile = slid
	_settle_vertical(profile, reach, start, delta)

## Raised-hull sweep with up to four slide planes (walls, posts, cars, people).
func _sweep(motion: Vector3, touched: Array[Dictionary]) -> void:
	var foot := global_position.y
	var remaining := motion
	var planes: Array[Vector3] = []
	for iteration in 4:
		if remaining.length_squared() < 0.0000004:
			break
		var hit := move_and_collide(remaining, false, safe_margin, false, 4)
		if hit == null:
			break
		var plane := Vector3.ZERO
		for i in hit.get_collision_count():
			var normal := hit.get_normal(i)
			var flat := Vector3(normal.x, 0.0, normal.z)
			if flat.length() < 0.25:
				continue
			flat = flat.normalized()
			touched.append({"collider": hit.get_collider(i), "normal": flat, "position": hit.get_position(i)})
			if plane == Vector3.ZERO or flat.dot(remaining) < plane.dot(remaining):
				plane = flat
		if plane == Vector3.ZERO:
			break
		var rest := hit.get_remainder()
		rest.y = 0.0
		var into := rest.dot(plane)
		if into < 0.0:
			rest -= plane * into
		for previous in planes:
			# A concave corner (second wall facing back into the first) stops.
			if rest.dot(previous) < -0.00001:
				rest = Vector3.ZERO
				break
		planes.append(plane)
		remaining = rest
	global_position.y = foot

## Wheel contact patches. Per wheel, five vertical rays along the frame; each is
## read as the height a WHEEL_RADIUS tyre centred over the axle would rest at, so
## the bike rises smoothly as a riser edge reaches the tyre. Walkable tops up to
## STEP_HEIGHT carry the wheel; taller tops and steep faces report `blocked`.
## Rays start where the hull reaches its full radius: planters and low walls
## that its rounded underside would only meet late block at the tyre instead.
func _support_profile(pose: Transform3D, reach: float) -> Dictionary:
	var foot := pose.origin.y
	var forward := Vector3(pose.basis.z.x, 0.0, pose.basis.z.z).normalized()
	var walkable := cos(floor_max_angle)
	var top := foot + HULL_CLEARANCE + HULL_RADIUS
	var bottom := foot - reach
	var result := {"height": -INF, "rear": -INF, "front": -INF, "blocked": false, "reason": "",
		"blocked_at": Vector3.INF, "blocked_height": 0.0}
	for part in 3:
		var axle: float = [REAR_AXLE, FRONT_AXLE, CRANK][part]
		var samples: Array = WHEEL_SAMPLES if part < 2 else [0.0]
		var best := -INF
		var steep := -INF
		var steep_at := Vector3.INF
		for offset in samples:
			var x := float(offset)
			var at := pose.origin + forward * (axle + x)
			var hit := _support_ray(at, top, bottom)
			if hit.is_empty():
				continue
			var h := float(hit.position.y)
			var normal: Vector3 = hit.normal
			if normal.y < walkable:
				if h > steep:
					steep = h
					steep_at = at
				continue
			if h > foot + STEP_HEIGHT + 0.005:
				result.blocked = true
				result.reason = "riser above step limit"
				result.blocked_at = at
				result.blocked_height = h
				continue
			var rest := h + sqrt(WHEEL_RADIUS * WHEEL_RADIUS - x * x) - WHEEL_RADIUS if part < 2 else h - CRANK_CLEARANCE
			best = maxf(best, rest)
		if steep > foot + 0.04 and steep > best + 0.02:
			# A steep slope/face rising under the tyre, not the top of a step.
			result.blocked = true
			result.reason = "steep face under wheel"
			result.blocked_at = steep_at
			result.blocked_height = steep
		if part == 0:
			result.rear = best
		elif part == 1:
			result.front = best
		result.height = maxf(float(result.height), best)
	return result

func _support_ray(at: Vector3, top: float, bottom: float) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(Vector3(at.x, top, at.z), Vector3(at.x, bottom, at.z), SUPPORT_MASK)
	var excluded: Array[RID] = []
	excluded.append_array(_support_rids)
	query.exclude = excluded
	query.hit_back_faces = false
	var space := get_world_3d().direct_space_state
	for attempt in 3:
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return {}
		var body := hit.get("collider") as CollisionObject3D
		if body != null and (body.collision_layer & (8 | 16)) != 0:
			# Parked cars share the structure layer: never a wheel support.
			excluded.append(hit.rid)
			query.exclude = excluded
			continue
		return hit
	return {}

## Climb, follow the ground down, or fall and land, from one support profile.
func _settle_vertical(profile: Dictionary, reach: float, start: Vector3, delta: float) -> void:
	var support := float(profile.height)
	var foot := global_position.y
	var supported := is_finite(support)
	if supported and support > foot + 0.0005:
		var rise := support - foot
		if rise > STEP_HEIGHT + 0.005 or test_move(global_transform, Vector3.UP * rise, null, safe_margin):
			# A canopy or overhang above the riser: keep the old pose.
			global_position = Vector3(start.x, foot, start.z)
			debug_step_reason = "blocked climb under overhang"
			_support = _support_profile(global_transform, reach)
			return
		global_position.y = support
		if rise > 0.02 and not _climbing:
			steps_climbed += 1
			debug_step_reason = "stepped onto checked curb"
			if rise > 0.05 and absf(speed) > 2.5:
				_jolt = 1.0
				_shake(clampf(rise * absf(speed) * 0.2, 0.08, 0.4))
				speed *= 1.0 - clampf(rise * 0.4, 0.0, 0.08)
		# Step-like rises only: riding up a graded street must not mask its curbs.
		_climbing = rise > 0.02
		if velocity.y <= 0.0:
			_land()
	elif supported and _grounded and foot - support <= SNAP_DOWN:
		_climbing = false
		var drop := foot - support
		if drop > 0.0005 and move_and_collide(Vector3.DOWN * drop, false, safe_margin) == null:
			global_position.y = support
		velocity.y = 0.0
	else:
		_climbing = false
		if _grounded:
			# Rolled off a drop deeper than the snap: start falling.
			_grounded = false
			velocity.y = minf(velocity.y, 0.0)
			debug_step_reason = "rolled off a drop"
		elif velocity.y <= 0.0:
			var fall := velocity.y * delta
			if supported and foot + fall <= support:
				global_position.y = support
				_land()
			elif fall < 0.0:
				var hit := move_and_collide(Vector3.UP * fall, false, safe_margin)
				if hit != null and hit.get_normal().y > 0.5:
					_land() # The hull came to rest on something (bench, ledge).
	_support = profile

func _land() -> void:
	if not _grounded and velocity.y < -5.0:
		_jolt = 1.0
		_shake(clampf(-velocity.y * 0.05, 0.1, 0.4))
	velocity.y = 0.0
	_grounded = true
	_hop_active = false

## A riser or steep face blocked a wheel below the raised hull: report it as a
## contact with its measured face normal so it scrapes, bumps or crashes too.
func _riser_contact(profile: Dictionary, attempted: Vector3) -> Dictionary:
	var at: Vector3 = profile.blocked_at
	if not at.is_finite():
		return {}
	var foot := global_position.y
	var height := clampf(float(profile.blocked_height) - foot - 0.04, 0.03, STEP_HEIGHT + 0.03)
	var origin := Vector3(global_position.x, foot + height, global_position.z)
	var target := Vector3(at.x, foot + height, at.z)
	var reach := target - origin
	if reach.length() < 0.05:
		return {}
	var query := PhysicsRayQueryParameters3D.create(origin, target + reach.normalized() * 0.35, SUPPORT_MASK)
	query.exclude = _support_rids
	query.hit_back_faces = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var flat_motion := Vector3(attempted.x, 0.0, attempted.z)
	var normal := -flat_motion.normalized() if flat_motion.length() > 0.0001 else -reach.normalized()
	var point := target
	var collider: Object = null
	if not hit.is_empty():
		var face := Vector3(hit.normal.x, 0.0, hit.normal.z)
		if face.length() > 0.3:
			normal = face.normalized()
		point = hit.position
		collider = hit.get("collider")
	normal.y = 0.0
	if normal.length() < 0.5:
		return {}
	return {"collider": collider, "normal": normal.normalized(), "position": point, "riser": true}

## Slip (recoil/sideways) velocity cannot keep pushing into what it touched.
## (It decays in tick, after the pedal speed has been measured against it.)
func _absorb_slip(touched: Array[Dictionary]) -> void:
	for contact in touched:
		var normal: Vector3 = contact.normal
		var into := _slip.dot(normal)
		if into < 0.0:
			_slip -= normal * into

func _try_turn(amount: float) -> bool:
	if is_zero_approx(amount):
		return true
	var turned := yaw + amount
	# A hair narrower hull lets the frame pivot while it touches a post or wall;
	# the next sweep's recovery separates any sub-centimetre overlap.
	if _hull_clear(Transform3D(Basis(Vector3.UP, turned), global_position), 0.0, TURN_SHRINK):
		yaw = turned
		return true
	var half := yaw + amount * 0.5
	if _hull_clear(Transform3D(Basis(Vector3.UP, half), global_position), 0.0, TURN_SHRINK):
		yaw = half
		return true
	return false

func _remember_trail(delta: float) -> void:
	_trail_clock -= delta
	if _trail_clock > 0.0 or not _grounded:
		return
	_trail_clock = 0.2
	_trail.append(global_position)
	if _trail.size() > 10:
		_trail.remove_at(0)

func _shake(amount: float) -> void:
	if is_instance_valid(player) and player.has_method("vehicle_shake"):
		player.vehicle_shake(amount)

# ------------------------------------------------------------------ contacts and impacts

static func _contact_kind(collider) -> String:
	if not collider is CollisionObject3D:
		return "structure"
	var body := collider as CollisionObject3D
	if (body.collision_layer & 8) != 0:
		return "person"
	if body.has_meta("parked_vehicle") or (body is StaticBody3D and (body.collision_layer & 16) != 0):
		return "parked_vehicle"
	if (body.collision_layer & 16) != 0 or body.has_meta("traffic_vehicle"):
		return "vehicle"
	if (body.collision_layer & 1) != 0:
		return "terrain"
	return "structure"

static func _collider_velocity(collider) -> Vector3:
	if collider is CharacterBody3D:
		var value: Vector3 = (collider as CharacterBody3D).velocity
		return Vector3(value.x, 0.0, value.z)
	if collider is RigidBody3D:
		var linear: Vector3 = (collider as RigidBody3D).linear_velocity
		return Vector3(linear.x, 0.0, linear.z)
	return Vector3.ZERO

func _resolve_contacts(touched: Array[Dictionary], v_pre: Vector3, forward: Vector3, incoming_speed: float) -> void:
	var strongest: Dictionary = {}
	for contact in touched:
		var collider = contact.get("collider")
		var kind := _contact_kind(collider)
		if kind == "person":
			if is_instance_valid(collider):
				_note_person(collider as Node, contact, v_pre, incoming_speed)
			continue
		var other := _collider_velocity(collider)
		var relative := v_pre - other
		relative.y = 0.0
		var normal: Vector3 = contact.normal
		var closing := -relative.dot(normal)
		if strongest.is_empty() or closing > float(strongest.closing):
			strongest = {"collider": collider, "kind": kind, "normal": normal, "position": contact.position,
				"other": other, "relative": relative, "closing": closing}
	if not strongest.is_empty() and float(strongest.closing) > 0.05:
		_apply_impact(strongest, v_pre, forward)

func _apply_impact(contact: Dictionary, v_pre: Vector3, forward: Vector3) -> void:
	var normal: Vector3 = contact.normal
	var other: Vector3 = contact.other
	var relative: Vector3 = contact.relative
	var closing := float(contact.closing)
	var tangent := relative + normal * closing
	var tangential := tangent.length()
	var severity := "scrape" if closing < SCRAPE_SPEED else ("bump" if closing < CRASH_SPEED else "crash")
	var event := _impact_event(contact, severity, closing, tangential, v_pre)
	if severity == "crash":
		if _eject(event, v_pre):
			return
		severity = "bump" # No clear spot to launch the rider from: recoil instead.
		event.severity = severity
	var restitution := BUMP_RESTITUTION if severity == "bump" else 0.0
	var direction := tangent / tangential if tangential > 0.001 else Vector3.ZERO
	var kept := maxf(0.0, tangential - CONTACT_FRICTION * (1.0 + restitution) * closing)
	var after := other + direction * kept + normal * (restitution * closing)
	after.y = 0.0
	# Pedal speed never flips direction on impact: the bounce lives in decaying
	# slip velocity, so holding W cannot brake the recoil away in a frame.
	if v_pre.dot(forward) >= 0.0:
		speed = clampf(after.dot(forward), 0.0, SPRINT_SPEED)
	else:
		speed = clampf(after.dot(forward), -REVERSE_SPEED, 0.0)
	_slip = after - forward * speed
	_slip.y = 0.0
	# A glancing touch ahead of the centre (behind it while reversing) swings
	# the frame along the obstacle, so the bike slides off posts and walls.
	# It swings toward where the bike now travels along the face (a moving car's
	# drag included). The relative tangent alone points backwards when a faster
	# car brushes past, and would yank the frame into that car.
	var heading_sign := 1.0 if v_pre.dot(forward) >= 0.0 else -1.0
	var lever := (Vector3(contact.position) - global_position).dot(forward) * heading_sign
	var along_face := after - normal * after.dot(normal)
	if along_face.length() > 0.3 and lever > 0.15:
		var travel := along_face.normalized() * heading_sign
		var angle := atan2(forward.cross(travel).y, forward.dot(travel))
		_yaw_deflect = clampf(angle * clampf(closing / CRASH_SPEED + 0.25, 0.25, 0.85), -0.7, 0.7)
	if severity == "bump":
		_wobble = maxf(_wobble, clampf(0.25 + closing * 0.05, 0.25, 0.55))
		_shake(clampf(closing / 8.0, 0.15, 0.6))
	_emit_impact(event, false)

func _impact_event(contact: Dictionary, severity: String, closing: float, tangential: float, v_pre: Vector3) -> Dictionary:
	_impact_serial += 1
	var collider = contact.get("collider")
	var valid := is_instance_valid(collider)
	var vehicle_id := ""
	if valid:
		var named = (collider as Object).get("vehicle_id")
		if named is String:
			vehicle_id = named
		elif (collider as Object).has_meta("parked_index"):
			vehicle_id = "parked_%03d" % int((collider as Object).get_meta("parked_index"))
	return {"id": _impact_serial, "kind": str(contact.kind), "severity": severity, "ejected": false,
		"collider": collider if valid else null, "collider_id": (collider as Object).get_instance_id() if valid else 0,
		"vehicle_id": vehicle_id, "position": contact.position, "normal": contact.normal,
		"relative_velocity": contact.relative, "closing_speed": closing, "tangential_speed": tangential,
		"incidence_deg": rad_to_deg(atan2(closing, tangential)), "bike_speed": Vector2(v_pre.x, v_pre.z).length(),
		"other_velocity": contact.other, "time": _clock, "harmless": true, "body_damage": 0.0}

## At most one event per collider per IMPACT_DEDUPE, unless the new hit is harder.
func _emit_impact(event: Dictionary, force: bool) -> void:
	var rank: int = {"scrape": 0, "bump": 1, "crash": 2}.get(str(event.severity), 0)
	if not force and float(event.closing_speed) < 0.6:
		return
	var key := int(event.collider_id)
	var previous: Dictionary = _impact_until.get(key, {})
	if not force and not previous.is_empty() and float(previous.until) >= _clock and int(previous.rank) >= rank:
		return
	_impact_until[key] = {"until": _clock + IMPACT_DEDUPE, "rank": rank}
	impacts += 1
	last_impact = event.duplicate()
	impact.emit(event)

func _note_person(body: Node, contact: Dictionary, v_pre: Vector3, incoming_speed: float) -> void:
	if incoming_speed < 0.6 or _contact_until.has(body.get_instance_id()):
		return
	_contact_until[body.get_instance_id()] = _clock + PERSON_COOLDOWN
	contacts += 1
	var normal: Vector3 = contact.normal
	var relative := v_pre - _collider_velocity(body)
	relative.y = 0.0
	var closing := maxf(0.0, -relative.dot(normal))
	var direction := Vector3(sin(yaw), 0.0, cos(yaw)) * (-1.0 if speed < 0.0 else 1.0)
	var push := -normal * REDUCED_MASS * closing
	var actor_id := ""
	var named = body.get("actor_id")
	if named is String and not (named as String).is_empty():
		actor_id = named
	elif body.has_meta("city_crowd_index"):
		actor_id = "crowd_%d" % int(body.get_meta("city_crowd_index"))
	# People absorb the bike: it loses most of its speed and wobbles, the rider stays on.
	speed = signf(speed) * minf(absf(speed), 0.8)
	_slip = Vector3.ZERO
	_wobble = maxf(_wobble, 0.45)
	_flash("Watch where you're riding! Give people room.")
	pedestrian_contact.emit({"collider": body, "position": contact.position, "speed": incoming_speed,
		"direction": direction, "crowd_index": int(body.get_meta("city_crowd_index", -1)),
		"source": "bicycle", "harmless": true, "body_damage": 0.0,
		"relative_speed": closing, "relative_velocity": relative, "normal": normal,
		"impulse": push, "impulse_magnitude": push.length(), "bike_velocity": v_pre,
		"actor_id": actor_id, "knockdown_hint": closing >= 2.2})

# ------------------------------------------------------------------ crash and recovery

## Hard impact: launch the rider rig from a clear point inside the frame's own
## swept volume; the riderless bicycle recoils, slides and falls over.
func _eject(event: Dictionary, v_pre: Vector3) -> bool:
	if _crash == null or not _crash.is_inside_tree():
		return false
	var start := Vector3.INF
	for height in [1.05, 0.8, 0.62]:
		var at := global_position + Vector3.UP * float(height)
		if _crash.is_clear(at):
			start = at
			break
	if not start.is_finite():
		return false
	var normal: Vector3 = event.normal
	var into := minf(0.0, v_pre.dot(normal))
	var normal_part := normal * into
	var tangent := v_pre - normal_part
	tangent.y = 0.0
	var kind := str(event.kind)
	var vehicle := kind == "vehicle" or kind == "parked_vehicle"
	var closing := float(event.closing_speed)
	var launch := tangent * 0.85 + normal_part * (0.3 if vehicle else 0.45)
	# A car driving into the rider carries them off with it (as it does the
	# riderless bicycle below), never leaving them in its path.
	var other: Vector3 = event.other_velocity
	launch += normal * maxf(0.0, other.dot(normal))
	launch.y = clampf(1.7 + 0.2 * closing, 2.0, 3.0 if vehicle else 3.8)
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	var right := Vector3(-cos(yaw), 0.0, sin(yaw))
	var flat := Vector3(launch.x, 0.0, launch.z)
	var direction := flat.normalized() if flat.length() > 0.3 else forward
	var flip := Vector3.UP.cross(direction).normalized()
	var roll := clampf(tangent.length() / maxf(v_pre.length(), 0.1), 0.0, 1.0) * (1.0 if tangent.dot(right) >= 0.0 else -1.0)
	var spin := flip * clampf(4.0 + 0.45 * closing, 4.5, 9.0) + direction * roll * 2.5
	if not _crash.begin(start, launch, spin, yaw):
		return false
	_crashed = true
	crashes += 1
	_crash_heading = yaw
	_crash_recovery = {}
	_recovery_retry = 0.0
	var recoil := tangent * 0.5 + normal * (0.25 * closing + maxf(0.0, other.dot(normal)))
	recoil.y = 0.0
	var lever := Vector3(event.position) - global_position
	lever.y = 0.0
	speed = 0.0
	_slip = recoil
	_spin_rate = clampf(lever.cross(normal).y * closing * 0.6, -3.0, 3.0)
	_fall_side = _choose_fall_side(1.0 if tangent.dot(right) >= 0.0 else -1.0)
	_fall_amount = 0.0
	_fallen = true
	_settling = true
	_steer = 0.0
	_yaw_deflect = 0.0
	_hop_active = false
	_hop_buffer = 0.0
	_rider.g.visible = false
	for part in _legs + _shoes:
		part.visible = false
	player.set("seated_vehicle", _crash)
	player.follow_vehicle()
	_last_seat = player.global_position
	_flash("You came off the bike!")
	_shake(0.9)
	event.ejected = true
	_emit_impact(event, true)
	rider_ejected.emit({"impact": event.duplicate(), "launch_velocity": launch, "start": start,
		"spin": spin, "bike_velocity": recoil})
	return true

func _choose_fall_side(preferred: float) -> float:
	var right := Vector3(-cos(yaw), 0.0, sin(yaw))
	for side in [preferred, -preferred]:
		var from := global_position + Vector3.UP * 0.5
		var ray := PhysicsRayQueryParameters3D.create(from, from + right * float(side) * 1.1, 1 | 2 | 16)
		ray.exclude = _support_rids
		if get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			return float(side)
	return preferred

func _tick_crash(delta: float) -> void:
	if not player.is_seated():
		# Teardown or an external release already placed the explorer.
		_end_crash(player.global_position, float(player.get("yaw")), "external")
		return
	if _last_seat.is_finite() and player.global_position.distance_squared_to(_last_seat) > 0.75 * 0.75:
		_end_crash(player.global_position, float(player.get("yaw")), "relocated")
		return
	if _settling:
		_tick_riderless(delta)
	var controls := _read_controls()
	var move: Vector2 = controls.move
	if _crash.is_down() and (move.length() > 0.3 or bool(controls.get("hop", false))):
		_crash.get_up_requested = true
	_crash.step(delta)
	var overdue := _crash.elapsed >= MAX_CRASH_TIME
	if _crash_recovery.is_empty() and (_crash.ready_to_stand() or overdue):
		_recovery_retry -= delta
		if _recovery_retry <= 0.0:
			_recovery_retry = 0.25
			var spot := _recovery_spot(overdue)
			if not spot.is_empty():
				_crash_recovery = spot
				if _crash.is_down():
					_crash.begin_getup(spot.position, float(spot.heading))
				else:
					_end_crash(spot.position, float(spot.heading), str(spot.recovery))
					return
	if _crash.phase == "done" and not _crash_recovery.is_empty():
		_end_crash(_crash_recovery.position, float(_crash_recovery.heading), str(_crash_recovery.recovery))
		return
	player.follow_vehicle()
	_last_seat = player.global_position

## Where the explorer stands up: beside the rider and reachable from them
## without crossing anything solid, else beside the bicycle, else a recent clear
## riding pose or the mount point. `force` adds the rider's own ground point.
func _recovery_spot(force: bool) -> Dictionary:
	var origin: Vector3 = _crash.ground_point
	var from: Vector3 = _crash.center
	var toward := global_position - origin
	toward.y = 0.0
	var heading := atan2(toward.x, toward.z) if toward.length() > 0.6 else _crash_heading
	for ring in [0.0, 0.45, 0.9, 1.35]:
		var count := 1 if float(ring) == 0.0 else 8
		for k in count:
			var angle := heading + float(k) * TAU / float(count)
			var stand := _stand_point(origin + Vector3(sin(angle), 0.0, cos(angle)) * float(ring), origin.y)
			if stand.is_finite() and _reachable(from, stand):
				return {"position": stand, "heading": heading, "recovery": "nearby"}
	var space := get_world_3d().direct_space_state
	for radius in [1.0, 1.4, 2.0]:
		for side in [1.0, -1.0]:
			var stand := _stand_point(global_position + Vector3(cos(yaw), 0.0, -sin(yaw)) * float(radius) * float(side), global_position.y)
			if not stand.is_finite():
				continue
			var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP, stand + Vector3.UP, WORLD_MASK)
			ray.exclude = _support_rids
			if space.intersect_ray(ray).is_empty():
				return {"position": stand, "heading": heading, "recovery": "bike_side"}
	for i in range(_trail.size() - 1, -1, -1):
		var stand := _stand_point(_trail[i], _trail[i].y)
		if stand.is_finite():
			return {"position": stand, "heading": heading, "recovery": "pre_crash"}
	if _mount_spot.is_finite():
		var stand := _stand_point(_mount_spot, _mount_spot.y)
		if stand.is_finite():
			return {"position": stand, "heading": heading, "recovery": "mount_point"}
	if force:
		return {"position": origin + Vector3.UP * 0.05, "heading": heading, "recovery": "overdue"}
	return {}

func _stand_point(at: Vector3, reference_y: float) -> Vector3:
	var ground := _ground(at)
	if ground.is_empty():
		return Vector3.INF
	var stand: Vector3 = ground.position + Vector3.UP * 0.05
	if absf(stand.y - reference_y) > 0.65 or not _standing_clear(stand):
		return Vector3.INF
	return stand

## No wall, fence, car or roof between the rider and the spot. The fallen
## bicycle is low (its upright hull is not), so it never vetoes a path; the
## standing capsule test still keeps the explorer off the bicycle itself.
func _reachable(from: Vector3, stand: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	for height in [0.45, 1.1]:
		var ray := PhysicsRayQueryParameters3D.create(from, stand + Vector3.UP * float(height), 1 | 2 | 16)
		ray.exclude = _support_rids
		if not space.intersect_ray(ray).is_empty():
			return false
	return true

func _end_crash(at: Vector3, heading: float, kind: String) -> void:
	var duration := _crash.elapsed
	_crash.finish()
	_crashed = false
	_crash_recovery = {}
	_recovery_retry = 0.0
	if player.get("seated_vehicle") == _crash:
		player.set("seated_vehicle", self)
	_finish_exit(at, heading)
	_flash("Pick your bicycle back up with F")
	rider_recovered.emit({"position": at, "heading": heading, "duration": duration, "recovery": kind})

## The riderless bicycle: slip velocity decays, every move is the same hull
## sweep and wheel support as riding, and the frame falls onto its side.
func _tick_riderless(delta: float) -> void:
	_fall_amount = minf(1.0, _fall_amount + delta / 0.55)
	if absf(_spin_rate) > 0.001:
		if _try_turn(_spin_rate * delta):
			rotation.y = yaw
		else:
			_spin_rate = 0.0
		_spin_rate = move_toward(_spin_rate, 0.0, 5.0 * delta)
	var touched: Array[Dictionary] = []
	var before := global_position
	_move(_slip, delta, touched)
	var moved := global_position - before
	moved.y = 0.0
	for contact in touched:
		var normal: Vector3 = contact.normal
		var into := _slip.dot(normal)
		if into < 0.0:
			_slip -= normal * into * 1.25
	_slip = _slip.move_toward(Vector3.ZERO, RIDERLESS_FRICTION * delta)
	_phase += moved.length() * 0.5 / WHEEL_RADIUS
	velocity.x = moved.x / delta
	velocity.z = moved.z / delta
	_animate_riderless(delta)
	if _slip.length() < 0.04 and _grounded and _fall_amount >= 1.0 and absf(_spin_rate) < 0.01:
		_settling = false
		_slip = Vector3.ZERO
		velocity = Vector3.ZERO
		_parked_position = global_position

func _pick_up() -> void:
	_fallen = false
	_settling = false
	_fall_amount = 0.0
	_spin_rate = 0.0
	_slip = Vector3.ZERO
	_visual.rotation = Vector3.ZERO
	_visual.position = Vector3.ZERO
	_front.rotation.y = 0.0

# ------------------------------------------------------------------ status

func _paused() -> bool:
	return level == null or bool(level.get("paused")) or get_tree().paused

func _flash(message: String) -> void:
	_message = message
	_message_until = _clock + 3.0

func get_status() -> Dictionary:
	var prompt := ""
	if active:
		if not _crashed:
			prompt = "W pedal · S brake / reverse · A/D steer · Space hop · Shift pedal hard · F get off"
	elif spawned and is_instance_valid(player) and player.global_position.distance_to(global_position) <= MOUNT_DISTANCE:
		prompt = "F · Pick up bicycle" if _fallen else "F · Ride bicycle"
	var crash_phase := _crash.phase if _crash != null and _crashed else ""
	return {"active": active, "spawned": spawned, "speed": 0.0 if _crashed else speed, "speed_kmh": 0 if _crashed else roundi(absf(speed) * 3.6),
		"prompt": prompt, "message": _message if _clock < _message_until else "", "contacts": contacts,
		"avoidance_ticks": avoidance_ticks, "exit_available": active and not _crashed and absf(speed) <= EXIT_SPEED and not _hop_active,
		"hops": hops_started, "steps": steps_climbed, "airborne": _hop_active, "sprinting": _sprinting,
		"reversing": speed < -0.05, "step_reason": debug_step_reason,
		"position": global_position, "vehicle_id": "player_bicycle", "kind": "bicycle",
		"crashed": _crashed, "crash_phase": crash_phase, "fallen": _fallen, "impacts": impacts,
		"crashes": crashes, "last_impact": last_impact.duplicate(), "grounded": _grounded}

func get_map_pois() -> Array:
	return [{"id": "player_bicycle", "label": "Your bicycle", "kind": "vehicle", "position": global_position}] if spawned and not active else []

func _hull_clear(pose: Transform3D, lift := 0.0, shrink := 0.0) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = WORLD_MASK
	query.exclude = _support_rids
	query.margin = 0.001
	for collider in _colliders:
		if shrink > 0.0:
			query.shape = _shrunk_shape(shrink)
		else:
			query.shape = collider.shape
		query.transform = pose * collider.transform
		query.transform.origin.y += lift
		if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			return false
	return true

## A hull capsule narrower by `shrink` (pivot allowance, fixture tolerances).
func _shrunk_shape(shrink: float) -> CapsuleShape3D:
	var key := snappedf(shrink, 0.001)
	if not _shrunk_shapes.has(key):
		var capsule := CapsuleShape3D.new()
		capsule.radius = HULL_RADIUS - key
		capsule.height = HULL_TOP - HULL_CLEARANCE - key * 2.0
		_shrunk_shapes[key] = capsule
	return _shrunk_shapes[key]

func _ground(at: Vector3) -> Dictionary:
	var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.2, at - Vector3.UP * 1.6, 1 | 2)
	var excluded: Array[RID] = [get_rid()]
	ray.exclude = excluded
	var space := get_world_3d().direct_space_state
	for attempt in 3:
		var hit := space.intersect_ray(ray)
		if hit.is_empty():
			return {}
		var body := hit.get("collider") as CollisionObject3D
		if body != null and (body.collision_layer & (8 | 16)) != 0:
			# Never park or stand the explorer on a car roof.
			excluded.append(hit.rid)
			ray.exclude = excluded
			continue
		return hit if hit.normal.y > 0.7 else {}
	return {}

func _bike_clear(at: Vector3) -> bool:
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.7, 1.5, 2.1)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(Vector3.UP, yaw), at + Vector3.UP * 0.8)
	query.collision_mask = WORLD_MASK
	query.exclude = [get_rid(), player.get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

## Whether an explorer standing at `stand` would touch the upright hull at
## `pose` (the explorer's own layer is outside the hull's collision mask).
func _hull_reaches(pose: Transform3D, stand: Vector3) -> bool:
	if stand.y > pose.origin.y + HULL_TOP or stand.y + STANDING_HEIGHT < pose.origin.y + HULL_CLEARANCE:
		return false
	var forward := Vector3(pose.basis.z.x, 0.0, pose.basis.z.z).normalized()
	var offset := Vector3(stand.x - pose.origin.x, 0.0, stand.z - pose.origin.z)
	var along := clampf(offset.dot(forward), -HULL_HALF_SPAN, HULL_HALF_SPAN)
	return (offset - forward * along).length() < HULL_RADIUS + STANDING_RADIUS

func _standing_clear(at: Vector3) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = STANDING_RADIUS
	shape.height = STANDING_HEIGHT
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = at + Vector3.UP * 0.89
	query.collision_mask = WORLD_MASK
	query.exclude = [player.get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

# ------------------------------------------------------------------ model

func _material(color: String, metal := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color)
	mat.metallic = metal
	mat.roughness = 0.65
	return mat

func _mesh(parent: Node3D, mesh: Mesh, mat: Material, at := Vector3.ZERO) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = at
	parent.add_child(instance)
	return instance

func _box(parent: Node3D, at: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(parent, mesh, mat, at)

func _rod(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 1.0
	mesh.radial_segments = 8
	var instance := _mesh(parent, mesh, mat)
	_place_rod(instance, a, b)
	return instance

func _place_rod(part: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var direction := b - a
	part.position = (a + b) * 0.5
	part.quaternion = Quaternion(Vector3.UP, direction.normalized())
	part.scale = Vector3(1.0, direction.length(), 1.0)

func _build_model() -> void:
	_visual = Node3D.new()
	_visual.name = "BicycleModel"
	add_child(_visual)
	var paint := _material("#2db6a4", 0.35)
	var rubber := _material("#20282b")
	var chrome := _material("#b4c3c8", 0.8)
	var saddle := _material("#473525")
	var rear := Vector3(0.0, WHEEL_RADIUS, -0.67)
	var crank := Vector3(0.0, 0.34, -0.10)
	var seat := Vector3(0.0, 0.94, -0.24)
	var head := Vector3(0.0, 0.93, 0.53)
	for pair in [[rear, crank], [crank, seat], [seat, rear], [seat, head], [head, crank]]:
		_rod(_visual, pair[0], pair[1], 0.035, paint)
	_rod(_visual, seat, seat + Vector3.UP * 0.09, 0.024, chrome)
	_box(_visual, seat + Vector3.UP * 0.11, Vector3(0.23, 0.07, 0.32), saddle)
	# Rear rack, chain and kickstand make the silhouette a practical city bike.
	_box(_visual, Vector3(0.0, 0.79, -0.69), Vector3(0.28, 0.035, 0.43), chrome)
	_rod(_visual, rear + Vector3(0.11, 0.0, 0.0), Vector3(0.11, 0.79, -0.69), 0.014, chrome)
	_rod(_visual, rear + Vector3(-0.11, 0.0, 0.0), Vector3(-0.11, 0.79, -0.69), 0.014, chrome)
	_rod(_visual, crank + Vector3(0.09, 0.04, 0.0), rear + Vector3(0.09, 0.04, 0.0), 0.012, rubber)
	_wheel(_visual, rear, rubber, chrome)
	_front = Node3D.new()
	_front.position = head
	_visual.add_child(_front)
	var axle := Vector3(0.0, WHEEL_RADIUS, 0.68) - head
	for x in [-0.07, 0.07]:
		_rod(_front, Vector3(x, 0.0, 0.0), axle + Vector3(x, 0.0, 0.0), 0.024, chrome)
	_rod(_front, Vector3.ZERO, Vector3(0.0, 0.22, -0.04), 0.025, chrome)
	_rod(_front, Vector3(-0.33, 0.22, -0.04), Vector3(0.33, 0.22, -0.04), 0.023, chrome)
	for x in [-0.30, 0.30]:
		_box(_front, Vector3(x, 0.22, -0.04), Vector3(0.13, 0.055, 0.065), rubber)
	_wheel(_front, axle, rubber, chrome)
	_box(_front, Vector3(0.0, 0.12, 0.05), Vector3(0.10, 0.08, 0.07), _material("#fff0b0"))
	_box(_visual, Vector3(0.0, 0.81, -0.92), Vector3(0.09, 0.06, 0.035), _material("#e74a38"))
	for side in [-1.0, 1.0]:
		_pedals.append(_box(_visual, Vector3(float(side) * 0.19, 0.34, -0.10), Vector3(0.19, 0.04, 0.10), rubber))
	_rider = Cast.person("two_pack", _visual)
	_rider.g.name = "BicycleRider"
	_rider.g.position = Vector3(0.0, 0.19, -0.24)
	# +Z is the handlebar/front direction. Lean toward it, with the head
	# counter-rotated to keep the rider looking down the street.
	_rider.pose({"lean": 0.80, "nod": -0.62})
	for leg in _rider.legs:
		leg.visible = false
	var denim := _material("#2a4a7a")
	for side in [-1.0, 1.0]:
		for segment in 2:
			_legs.append(_rod(_visual, Vector3.ZERO, Vector3.UP, 0.075, denim))
		_shoes.append(_box(_visual, Vector3.ZERO, Vector3(0.14, 0.09, 0.25), _material("#f4f4f4")))
	_rider.g.visible = false
	for part in _legs + _shoes:
		part.visible = false
	_animate(0.0, 0.0)

func _wheel(parent: Node3D, at: Vector3, rubber: Material, chrome: Material) -> void:
	var wheel := Node3D.new()
	wheel.position = at
	parent.add_child(wheel)
	_wheels.append(wheel)
	var tire := TorusMesh.new()
	tire.inner_radius = WHEEL_RADIUS - 0.055
	tire.outer_radius = WHEEL_RADIUS
	tire.rings = 20
	tire.ring_segments = 6
	var ring := _mesh(wheel, tire, rubber)
	ring.rotation.z = PI * 0.5
	for i in 8:
		var angle := float(i) * PI / 8.0
		var end := Vector3(0.0, cos(angle), sin(angle)) * (WHEEL_RADIUS - 0.035)
		_rod(wheel, -end, end, 0.007, chrome)
	_rod(wheel, Vector3(-0.08, 0.0, 0.0), Vector3(0.08, 0.0, 0.0), 0.034, chrome)

func _animate(delta: float, turn: float) -> void:
	for wheel in _wheels:
		wheel.rotation.x = _phase
	_front.rotation.y = lerpf(_front.rotation.y, clampf(turn * 0.14, -0.45, 0.45), minf(1.0, delta * 12.0))
	var wobble := sin(_clock * 26.0) * 0.07 * clampf(_wobble / 0.4, 0.0, 1.0)
	_visual.rotation.z = lerpf(_visual.rotation.z, clampf(-turn * speed * 0.012, -0.16, 0.16) + wobble, minf(1.0, delta * 8.0))
	# Pitch the frame so both tyres meet the sampled ground: curbs, slopes, ledges.
	var rear := float(_support.get("rear", -INF))
	var front := float(_support.get("front", -INF))
	var pitch := 0.0
	var drop := 0.0
	if _grounded and is_finite(rear) and is_finite(front):
		pitch = -atan2(front - rear, FRONT_AXLE - REAR_AXLE)
		drop = (front + rear) * 0.5 - global_position.y
	var blend := minf(1.0, delta * 16.0)
	_visual_pitch = lerpf(_visual_pitch, clampf(pitch, -0.35, 0.35), blend)
	_visual_drop = lerpf(_visual_drop, clampf(drop, -0.2, 0.0), blend)
	_jolt = maxf(0.0, _jolt - delta * 3.0)
	_visual.rotation.x = _visual_pitch - _jolt * 0.1
	_visual.position.y = _visual_drop
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var phase := _phase * 0.55 + float(i) * PI
		var foot := Vector3(side * 0.19, 0.34 + sin(phase) * 0.14, -0.10 + cos(phase) * 0.14)
		_pedals[i].position = foot
		_shoes[i].position = foot + Vector3(0.0, 0.065, 0.035)
		var hip := Vector3(side * 0.14, 1.03, -0.24)
		var knee := Vector3(side * 0.17, 0.70 + sin(phase) * 0.06, 0.24)
		_place_rod(_legs[i * 2], hip, knee)
		_place_rod(_legs[i * 2 + 1], knee, foot + Vector3.UP * 0.08)
	_fit_rider_hands()

func _fit_rider_hands() -> void:
	# The legacy cast now has measured adult anatomy. Fit its actual hand
	# pivots to the real steering grips, instead of assuming old arm lengths.
	# Work in BicycleModel space, so frame pitch/lean and world placement cancel.
	# Only longitudinal arm scale changes; shoulder/hand thickness stays intact.
	var body_from_visual: Transform3D = (_rider.g.transform * _rider.body.transform).affine_inverse()
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var grip: Vector3 = _front.transform * Vector3(side * .30, .22, -.04)
		var arm: Node3D = _rider.arms[i]
		var hand: Node3D = _rider.hands[i]
		var target: Vector3 = body_from_visual * grip - arm.position
		var rest: Vector3 = hand.position
		var longitudinal := sqrt(maxf(.000001, target.length_squared() - rest.x * rest.x - rest.z * rest.z)) / maxf(absf(rest.y), .0001)
		arm.scale = Vector3(1.0, longitudinal, 1.0)
		var reach: Vector3 = rest * arm.scale
		arm.quaternion = Quaternion(reach.normalized(), target.normalized())

func _animate_riderless(delta: float) -> void:
	for wheel in _wheels:
		wheel.rotation.x = _phase
	var fall := _fall_amount * _fall_amount * (3.0 - 2.0 * _fall_amount)
	_visual.rotation.z = _fall_side * 1.38 * fall
	_visual.rotation.x = lerpf(_visual.rotation.x, 0.0, minf(1.0, delta * 6.0))
	_visual.position.y = 0.06 * fall
	_front.rotation.y = lerpf(_front.rotation.y, 0.5 * _fall_side * fall, minf(1.0, delta * 4.0))
