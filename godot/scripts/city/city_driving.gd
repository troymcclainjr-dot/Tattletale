extends Node3D
## Player driving. F boards a nearby stopped civilian car, or the starter car
## parked near spawn; WASD drives, Space is the handbrake, the mouse orbits the
## chase camera and F gets out at a checked door. One car at a time. An occupied
## car leaves AI control (no lane track, reservation, AI tick or recycling) and
## always renders its exact model (city_vehicle.gd player control).
##
## Integration (pen_lucy_level.gd):
## - setup(level) after traffic and combat. Newer managers are read with
##   level.get(), so fixtures without combat/law/shops/phone keep working.
## - tick(delta) in _physics_process after traffic.tick, before missions.
##   Traffic first moves AI cars against the player's previous pose; driving
##   then sweeps the player's car against their new poses, so neither overlaps.
##   tick() returns at once while level.paused (menu, map, dialogue, shop,
##   inspector) or the tree is paused: neither the car nor its seat moves.
## - handle_input(event) in _input after Esc/M/pause handling; true = consumed.
##   While active, root skips phone, shops, combat, interaction and saving.
## - exit_vehicle(force) widens the safe exit search for law/recovery.
##   recovery_exit_at(at, heading) detaches at a separately ground-validated
##   facility destination when the car is trapped; both may refuse obstacles.
## The explorer's own _physics_process runs after the level tick and only
## redraws the chase view while seated (city_player.gd enter/leave_vehicle).
##
## Ordinary curbside parked cars are boardable too: F promotes exactly that
## batch record into one live body (city_parked_cars hide_record). The starter
## and promoted cars form a bounded remembered registry that persists through
## snapshot/validate/preflight/restore/reset_persistent_state. Contract:
## .work/priorities-five/vehicle-contract.md.
##
## PlayMode.PLAYER_DRIVING false (city_play_mode.gd): nothing can be boarded,
## F is never consumed, no candidate prompt, label or map marker is shown, and
## a seat taken by any other path is vacated at once. The starter still spawns
## as a parked car and every persistence method is unchanged.

signal vehicle_entered(vehicle_id: String, starter: bool)
signal vehicle_exited(vehicle_id: String, forced: bool)
signal vehicle_impact(kind: String, at: Vector3, speed: float)
## Deduplicated contact episodes of the player's car (one per collider touch;
## see city_vehicle._note_contact). Root bridges person damage and law.
signal vehicle_collision(contact: Dictionary)

const PlayMode := preload("res://scripts/city/city_play_mode.gd")
const Vehicle := preload("res://scripts/city/city_vehicle.gd")
const Models := preload("res://scripts/city/city_car_models.gd")
const Catalog := preload("res://scripts/city/city_car_catalog.gd")
const Collision := preload("res://scripts/city/city_car_collision.gd")
const CivicClearance := preload("res://scripts/city/city_civic_clearance.gd")
const ENTER_REACH := 1.6
const ENTER_HEIGHT := 1.3
const ENTER_MAX_SPEED := 2.0
const EXIT_MAX_SPEED := 1.5
const IMPACT_REPORT_SPEED := 2.5
const STARTER_ID := "player_starter"
# Catalog.traffic_kind(3) is the hatchback; palette entry 3 is the deep red.
const STARTER_PAINT := 3
const STARTER_MIN_DISTANCE := 6.0
const STARTER_MAX_DISTANCE := 75.0
const STARTER_MAX_CHECKS := 600
# Same curbside rules as city_parked_cars.gd: clear of moving lanes and
# connectors, junction mouths, the guided walk, driveways and other cars.
const LANE_CLEARANCE := 2.35
const ROUTE_CLEARANCE := 3.5
const JUNCTION_CLEARANCE := 7.5
const PARKED_SPACING := 6.2
const DRIVE_KEYS := [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_SPACE, KEY_SHIFT, KEY_V, KEY_E]
# Remembered registry: the starter plus promoted parked cars, LRU-evicted.
# An evicted car is only forgotten (not persisted) and stays a live parked
# body until it and its curb spot are both unseen and far, then reverts.
const MAX_REMEMBERED := 8
const MAX_FORGOTTEN := 1
const FORGET_DISTANCE := 80.0
const CLEANUP_INTERVAL := 1.0
const PERSIST_VERSION := 1
const MAX_PARKED_DAMAGE := 64
const VEHICLE_FIELDS := ["id", "source", "source_id", "source_key", "prototype", "paint", "position", "yaw",
	"health", "disabled", "flat_tires", "last_used"]
const DAMAGE_FIELDS := ["source_id", "source_key", "health", "flat_tires"]
const RESTORE_SUPPORT_TOLERANCE := 0.35

var level: Node3D
var traffic: Node3D
var player: CharacterBody3D
var active := false
var vehicle: Node3D
var starter: Node3D
var starter_report: Dictionary = {}
var entries := 0
var exits := 0
var forced_exits := 0
var refused_exits := 0
var impacts := 0
var last_impact: Dictionary = {}
var last_exit: Dictionary = {}
var paused_ticks := 0
## Test/automation hook: {"throttle", "brake", "steer", "handbrake"} replaces
## the polled keys while non-empty. Normal play leaves it empty.
var input_override: Dictionary = {}
var _candidate: Node3D
var _scan_clock := 0.0
var _exit_clock := 0.0
var _exit_ready := false
var _was_slow := false
var _message := ""
var _message_time := 0.0
var _last_seat := Vector3.INF
var _controls: Dictionary = {"throttle": 0.0, "brake": 0.0, "steer": 0.0, "handbrake": false}
var _announced := false
var _label: Label3D
var _rejects: Dictionary = {}
var _near_roads: Array[Dictionary] = []
var _near_route: Array[PackedVector3Array] = []
var _near_lanes: Array[PackedVector3Array] = []
var remembered: Array[Node3D] = []
var forgotten: Array[Node3D] = []
var sequence := 0
var collisions := 0
var last_collision: Dictionary = {}
var promotions := 0
var evictions := 0
var cleanups := 0
var last_restore: Dictionary = {}
var starter_home := Transform3D.IDENTITY
var starter_home_yaw := 0.0
var _starter_home_valid := false
var _cleanup_clock := 0.0

func setup(owner_level: Node3D) -> void:
	level = owner_level
	name = "PlayerDriving"
	traffic = level.get("traffic")
	player = level.get("player")
	if traffic == null or player == null:
		starter_report = {"spawned": false, "reason": "no traffic or explorer"}
		return
	if OS.get_cmdline_user_args().has("--no-starter-car"):
		starter_report = {"spawned": false, "reason": "--no-starter-car"}
		return
	_spawn_starter()

func _exit_tree() -> void:
	if not is_instance_valid(traffic) or not traffic.has_method("unregister_player_vehicle"):
		return
	if is_instance_valid(starter):
		traffic.unregister_player_vehicle(starter)
	for car in remembered + forgotten:
		if is_instance_valid(car):
			traffic.unregister_player_vehicle(car)

# --- Frame ---------------------------------------------------------------------

func tick(delta: float) -> void:
	if level == null or player == null:
		return
	if bool(level.get("paused")) or get_tree().paused:
		paused_ticks += 1
		return
	_message_time = maxf(0.0, _message_time - delta)
	if not forgotten.is_empty():
		_cleanup_clock -= delta
		if _cleanup_clock <= 0.0:
			_cleanup_clock = CLEANUP_INTERVAL
			_cleanup_forgotten()
	if not PlayMode.player_driving_enabled():
		_candidate = null
		if active:
			_vacate_disabled_seat(delta)
		return
	if not active:
		_scan_clock -= delta
		if _scan_clock <= 0.0:
			_scan_clock = 0.1
			_candidate = _nearest_candidate()
			_announce_starter()
		return
	if not is_instance_valid(vehicle):
		_finish_exit(player.global_position + Vector3.UP * 0.05, float(player.yaw), true, "lost")
		return
	if _last_seat.is_finite() and player.global_position.distance_squared_to(_last_seat) > 0.75 * 0.75:
		# Root moved the explorer (respawn, checkpoint restore) without calling
		# exit_vehicle(): leave the car where it stopped and keep the new spot.
		_finish_exit(player.global_position, float(player.yaw), true, "relocated")
		return
	_controls = _read_controls()
	var report: Dictionary = vehicle.player_step(delta, float(_controls.throttle), float(_controls.brake),
		float(_controls.steer), bool(_controls.handbrake))
	player.follow_vehicle()
	_last_seat = player.global_position
	_report_contact(report.contact)
	for event in report.get("events", []):
		collisions += 1
		last_collision = event
		if bool(event.get("disabled", false)) and float(event.get("body_damage", 0.0)) > 0.0:
			_flash("Engine dead · the car is wrecked")
		vehicle_collision.emit(event)
	var slow := absf(float(vehicle.speed)) <= EXIT_MAX_SPEED
	_exit_clock -= delta
	if slow and (not _was_slow or _exit_clock <= 0.0):
		_exit_clock = 0.25
		_exit_ready = not _find_exit(false).is_empty()
	_was_slow = slow

## Driving disabled: the seat is never kept. A forced exit is retried twice a
## second (brakes held meanwhile) so a blocked door cannot strand the explorer.
func _vacate_disabled_seat(delta: float) -> void:
	if not is_instance_valid(vehicle):
		_finish_exit(player.global_position + Vector3.UP * 0.05, float(player.yaw), true, "lost")
		return
	_exit_clock -= delta
	if _exit_clock <= 0.0:
		_exit_clock = 0.5
		if exit_vehicle(true):
			return
	vehicle.player_step(delta, 0.0, 1.0, 0.0, true)
	player.follow_vehicle()
	_last_seat = player.global_position

func handle_input(event: InputEvent) -> bool:
	if level == null or player == null or bool(level.get("paused")) or get_tree().paused:
		return false
	if not PlayMode.player_driving_enabled():
		return false
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_F or event.physical_keycode == KEY_F):
		if active:
			exit_vehicle(false)
			return true
		var car := _nearest_candidate()
		if car == null:
			return false
		var reason := _entry_reason()
		if not reason.is_empty():
			_flash(reason)
			return true
		if _wrecked(car):
			_flash("This car won't start")
			return true
		enter_vehicle(car)
		return true
	if not active:
		return false
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or bool(level.get("offscreen_validation")) or DisplayServer.get_name() == "headless":
			player.vehicle_look(event.screen_relative)
		return true
	if event is InputEventMouseButton:
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			player.vehicle_zoom(1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
		return true
	if event is InputEventKey:
		# Drive keys are polled in tick; nothing else may act on them meanwhile.
		return event.keycode in DRIVE_KEYS or event.physical_keycode in DRIVE_KEYS
	return false

# --- Entry and exit ------------------------------------------------------------

func enter_vehicle(car: Node3D) -> bool:
	if not PlayMode.player_driving_enabled():
		return false
	if active or player == null or level == null or bool(level.get("paused")) or get_tree().paused:
		return false
	if _parked_index(car) >= 0:
		# An ordinary parked car: prove the door first, then promote exactly
		# that record into its one live body.
		if not _boardable(car) or not _entry_reason().is_empty() or not _entry_accessible(car):
			return false
		car = _promote_parked(car)
		if car == null:
			return false
	if not _boardable(car) or not _entry_reason().is_empty() or not _entry_accessible(car):
		return false
	if traffic != null and traffic.has_method("claim_vehicle"):
		if not traffic.claim_vehicle(car):
			return false
	else:
		car.begin_player_control()
	vehicle = car
	active = true
	_controls = {"throttle": 0.0, "brake": 0.0, "steer": 0.0, "handbrake": false}
	_exit_ready = false
	_was_slow = false
	_exit_clock = 0.0
	_message_time = 0.0
	var combat = level.get("combat")
	if combat != null and combat.has_method("cancel_player_actions"):
		combat.cancel_player_actions()
	var phone = player.get("phone")
	if phone != null and phone.has_method("suspend"):
		phone.suspend()
	player.enter_vehicle(car)
	_last_seat = player.global_position
	if is_instance_valid(_label):
		_label.visible = car != starter
	_touch_registry(car)
	entries += 1
	vehicle_entered.emit(str(car.vehicle_id), car == starter)
	return true

## Normal exits need a stopped car and a clear door path; a blocked exit is
## refused and the player stays seated. force=true (arrest, defeat, recovery)
## widens the search and checks the roof, but never detaches into an obstacle.
func exit_vehicle(force := false) -> bool:
	if not active:
		return false
	if not is_instance_valid(vehicle):
		_finish_exit(player.global_position + Vector3.UP * 0.05, float(player.yaw), true, "lost")
		return true
	if not force and absf(float(vehicle.speed)) > EXIT_MAX_SPEED:
		refused_exits += 1
		_flash("Stop the car to get out")
		return false
	var spot := _find_exit(force)
	if spot.is_empty():
		refused_exits += 1
		_flash("No room to open a door here · move the car")
		return false
	_finish_exit(spot.position, float(spot.heading), force, str(spot.door))
	return true

## Recovery owns ground/support validation (Facilities.release_point). This
## final occupancy check must succeed before either actor releases ownership.
func recovery_exit_at(at: Vector3, heading: float) -> bool:
	if not active or not is_instance_valid(player) or not at.is_finite() or not is_finite(heading):
		return false
	if not _standing_clear(at):
		return false
	_finish_exit(at, heading, true, "recovery")
	return true

func _finish_exit(at: Vector3, heading: float, forced: bool, door: String) -> void:
	var car := vehicle
	var id := str(car.vehicle_id) if is_instance_valid(car) else ""
	active = false
	vehicle = null
	if is_instance_valid(car):
		if traffic != null and traffic.has_method("release_vehicle"):
			traffic.release_vehicle(car)
		else:
			car.end_player_control()
	player.leave_vehicle(at, heading)
	_last_seat = Vector3.INF
	_controls = {"throttle": 0.0, "brake": 0.0, "steer": 0.0, "handbrake": false}
	_exit_ready = false
	_candidate = null
	_scan_clock = 0.0
	exits += 1
	forced_exits += int(forced)
	last_exit = {"vehicle_id": id, "door": door, "forced": forced, "position": at}
	if is_instance_valid(_label):
		_label.visible = true
	vehicle_exited.emit(id, forced)

func _entry_reason() -> String:
	if not bool(player.get("enabled")):
		return "Not now"
	var combat = level.get("combat")
	if combat != null and combat.has_method("blocks_movement") and combat.blocks_movement():
		return "Catch your breath before driving"
	if float(player.get("impact_recovery")) > 0.0:
		return "Steady yourself first"
	var phone = player.get("phone")
	if phone != null and bool(phone.get("active")):
		return "Put the phone away first"
	var law = level.get("law")
	if law != null and law.has_method("get_status") and bool(law.get_status().get("recovering", false)):
		return "Not now"
	if not player.is_on_floor():
		return "Land before getting in"
	return ""

## Can be boarded right now (a wrecked car is a candidate, not boardable).
func _boardable(car: Node3D) -> bool:
	return _candidate_ok(car) and not _wrecked(car)

## Stopped civilian cars, the starter, remembered cars and nearby unpromoted
## parked records. Never patrol, police-held, occupied or moving cars.
func _candidate_ok(car: Node3D) -> bool:
	var index := _parked_index(car)
	if index >= 0:
		var record: Dictionary = _parked_manager().records[index]
		return car.is_inside_tree() and int(record.presence) == 2 and str(record.get("promoted", "")).is_empty()
	if not is_instance_valid(car) or not car is Vehicle or not car.is_inside_tree():
		return false
	return not car.is_police and not car.player_controlled and car.external_owner.is_empty() \
		and not car.collision_parts.is_empty() and absf(float(car.speed)) <= ENTER_MAX_SPEED

func _wrecked(car: Node3D) -> bool:
	var index := _parked_index(car)
	if index >= 0:
		return float(_parked_manager().records[index].get("health", Vehicle.MAX_HEALTH)) <= 0.0
	return is_instance_valid(car) and car is Vehicle and car.disabled

func _nearest_candidate() -> Node3D:
	if player == null or traffic == null:
		return null
	var at := player.global_position
	var pool: Array = []
	if is_instance_valid(starter):
		pool.append(starter)
	var fleet = traffic.get("player_fleet")
	if fleet is Array:
		pool.append_array(fleet)
	var cars = traffic.get("vehicles")
	if cars is Array:
		pool.append_array(cars)
	var parked = _parked_manager()
	if parked != null and parked.has_method("records_near"):
		for index in parked.records_near(at, 8.0):
			pool.append(parked.records[index].body)
	var best: Node3D = null
	var best_reach := ENTER_REACH
	for car in pool:
		if not is_instance_valid(car) or car.global_position.distance_squared_to(at) > 64.0:
			continue
		if absf(at.y - car.global_position.y) > ENTER_HEIGHT or not _candidate_ok(car):
			continue
		var reach := _footprint_distance(car, at)
		if reach <= best_reach and _entry_accessible(car):
			best = car
			best_reach = reach
	return best

func _car_size(car: Node3D) -> Vector3:
	var kind := _kind_of(car)
	return Models.dimensions(kind) if Models.has_kind(kind) else Vehicle.BODY_SIZE

func _kind_of(car: Node3D) -> String:
	var index := _parked_index(car)
	if index >= 0:
		return str(_parked_manager().records[index].kind)
	var kind = car.get("prototype_kind") if is_instance_valid(car) else null
	return str(kind) if kind is String else ""

func _parked_manager():
	return traffic.get("parked") if traffic != null else null

## Record index of a parked batch body (its StaticBody3D), else -1.
func _parked_index(body: Node3D) -> int:
	if not is_instance_valid(body) or not body.has_meta("parked_index"):
		return -1
	var parked = _parked_manager()
	if parked == null:
		return -1
	var index := int(body.get_meta("parked_index"))
	if index < 0 or index >= parked.records.size() or parked.records[index].body != body:
		return -1
	return index

func _candidate_id(car: Node3D) -> String:
	var index := _parked_index(car)
	if index >= 0:
		return str(_parked_manager().records[index].get("source_id", "parked_%03d" % index))
	return str(car.vehicle_id) if is_instance_valid(car) and car is Vehicle else ""

func _footprint_distance(car: Node3D, at: Vector3) -> float:
	var local: Vector3 = car.global_transform.affine_inverse() * at
	var size := _car_size(car)
	return Vector2(maxf(0.0, absf(local.x) - size.x * 0.5), maxf(0.0, absf(local.z) - size.z * 0.5)).length()

func _entry_accessible(car: Node3D) -> bool:
	var at := player.global_position
	if not at.is_finite() or absf(at.y - car.global_position.y) > ENTER_HEIGHT or _footprint_distance(car, at) > ENTER_REACH:
		return false
	# Sweep the explorer to the nearest body edge. Ignore only the explorer
	# and the car being boarded, so even a thin fence prevents boarding.
	var local: Vector3 = car.global_transform.affine_inverse() * at
	var size := _car_size(car)
	var edge: Vector3 = car.global_transform * Vector3(clampf(local.x, -size.x * 0.5, size.x * 0.5), 0.0, clampf(local.z, -size.z * 0.5, size.z * 0.5))
	# Keep feet above both endpoints: a legal curb drop must not make the
	# straight sweep descend through the sidewalk before reaching its edge.
	var sweep_start := Vector3(at.x, maxf(at.y, edge.y), at.z)
	edge.y = sweep_start.y
	var query := _standing_query(sweep_start + Vector3.UP * 0.05)
	query.exclude = [player.get_rid(), (car as CollisionObject3D).get_rid()]
	var space := get_world_3d().direct_space_state
	if not space.intersect_shape(query, 1).is_empty():
		return false
	query.motion = edge - sweep_start
	var fractions := space.cast_motion(query)
	return fractions.size() >= 2 and fractions[0] >= 1.0

func _standing_query(at: Vector3) -> PhysicsShapeQueryParameters3D:
	var capsule: Shape3D = null
	var center_height := 0.87
	var collider = player.get("_capsule")
	if collider is CollisionShape3D:
		capsule = (collider as CollisionShape3D).shape
		center_height = (collider as CollisionShape3D).position.y
	if capsule == null:
		var fallback := CapsuleShape3D.new()
		fallback.radius = 0.30
		fallback.height = 1.72
		capsule = fallback
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * center_height)
	query.collision_mask = 1 | 2 | 8 | 16
	query.margin = 0.02
	query.exclude = [player.get_rid()]
	return query

func _standing_clear(at: Vector3) -> bool:
	return at.is_finite() and get_world_3d().direct_space_state.intersect_shape(_standing_query(at), 1).is_empty()

func _find_exit(force: bool) -> Dictionary:
	var car := vehicle
	var size := _car_size(car)
	var lateral := size.x * 0.5 + 0.50
	# Local +X is the driver's (left) side; -X is the kerb/passenger side.
	var doors := [["driver", lateral, 0.25], ["passenger", -lateral, 0.25], ["driver_rear", lateral, -0.95],
		["passenger_rear", -lateral, -0.95], ["rear", 0.0, -(size.z * 0.5 + 0.65)], ["front", 0.0, size.z * 0.5 + 0.65]]
	for door in doors:
		var spot := _exit_spot(car, float(door[1]), float(door[2]), true)
		if not spot.is_empty():
			spot["door"] = door[0]
			return spot
	if not force:
		return {}
	for radius in [2.6, 3.4, 4.5, 6.0]:
		for step in 12:
			var angle := TAU * float(step) / 12.0
			var spot := _exit_spot(car, sin(angle) * float(radius), cos(angle) * float(radius), false)
			if not spot.is_empty():
				spot["door"] = "forced_ring"
				return spot
	# A low ceiling can trap even this last resort. Recovery may instead use
	# a validated facility destination through recovery_exit_at().
	var roof := car.global_position + car.global_basis.y * (size.y + 0.08)
	if _standing_clear(roof):
		return {"position": roof, "heading": float(car.yaw), "door": "roof"}
	return {}

func _exit_spot(car: Node3D, lateral: float, along: float, door_path: bool) -> Dictionary:
	var forward := Vector3(sin(car.yaw), 0.0, cos(car.yaw))
	var side := Vector3(forward.z, 0.0, -forward.x)
	var base: Vector3 = car.global_position
	var at := base + side * lateral + forward * along
	var space := get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.0, at - Vector3.UP * 1.5, 1 | 2)
	ray.hit_back_faces = false
	var ground := space.intersect_ray(ray)
	if ground.is_empty() or ground.normal.y < cos(deg_to_rad(48.0)):
		return {}
	var foot: Vector3 = ground.position
	if absf(foot.y - base.y) > 0.6:
		return {}
	var capsule: Shape3D = null
	var center_height := 0.87
	var collider = player.get("_capsule")
	if collider is CollisionShape3D:
		capsule = (collider as CollisionShape3D).shape
		center_height = (collider as CollisionShape3D).position.y
	if capsule == null:
		var fallback := CapsuleShape3D.new()
		fallback.radius = 0.30
		fallback.height = 1.72
		capsule = fallback
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, foot + Vector3.UP * (0.05 + center_height))
	query.collision_mask = 2 | 8 | 16
	query.margin = 0.02
	query.exclude = [player.get_rid()]
	if not space.intersect_shape(query, 1).is_empty():
		return {}
	# Terrain above curb height where the body would stand: a bank or wall.
	query.transform.origin += Vector3.UP * 0.30
	query.collision_mask = 1
	if not space.intersect_shape(query, 1).is_empty():
		return {}
	if door_path:
		# The body passes beside the car, never through a wall, post or fence.
		var ball := SphereShape3D.new()
		ball.radius = 0.22
		var sweep := PhysicsShapeQueryParameters3D.new()
		sweep.shape = ball
		var seat := base + forward * clampf(along, -1.2, 1.2) + Vector3.UP * 1.0
		sweep.transform = Transform3D(Basis.IDENTITY, seat)
		sweep.motion = foot + Vector3.UP * 1.0 - seat
		sweep.collision_mask = 2 | 8 | 16
		sweep.exclude = [(car as CollisionObject3D).get_rid(), player.get_rid()]
		var fractions := space.cast_motion(sweep)
		if fractions.size() < 2 or fractions[0] < 1.0:
			return {}
	return {"position": foot + Vector3.UP * 0.05, "heading": float(car.yaw)}

# --- Controls, contacts and status ---------------------------------------------

func set_control_override(throttle: float, brake: float, steer: float, handbrake := false) -> void:
	input_override = {"throttle": throttle, "brake": brake, "steer": steer, "handbrake": handbrake}

func clear_control_override() -> void:
	input_override = {}

func _read_controls() -> Dictionary:
	if not input_override.is_empty():
		return {"throttle": clampf(float(input_override.get("throttle", 0.0)), 0.0, 1.0),
			"brake": clampf(float(input_override.get("brake", 0.0)), 0.0, 1.0),
			"steer": clampf(float(input_override.get("steer", 0.0)), -1.0, 1.0),
			"handbrake": bool(input_override.get("handbrake", false))}
	if not bool(player.get("enabled")):
		return {"throttle": 0.0, "brake": 0.0, "steer": 0.0, "handbrake": true}
	var steer := Input.get_action_strength("move_right") - Input.get_action_strength("move_left") \
		+ Input.get_action_strength("turn_right") - Input.get_action_strength("turn_left")
	return {"throttle": Input.get_action_strength("move_forward"), "brake": Input.get_action_strength("move_back"),
		"steer": clampf(steer, -1.0, 1.0), "handbrake": Input.is_physical_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_SPACE)}

func _report_contact(contact: Dictionary) -> void:
	if contact.is_empty() or float(contact.get("speed", 0.0)) < IMPACT_REPORT_SPEED:
		return
	impacts += 1
	var at: Vector3 = contact.get("position", vehicle.global_position)
	last_impact = {"kind": str(contact.get("kind", "structure")), "speed": float(contact.speed), "position": at}
	player.vehicle_shake(clampf(float(contact.speed) / 14.0, 0.15, 1.0))
	vehicle_impact.emit(str(last_impact.kind), at, float(contact.speed))

func _flash(text: String) -> void:
	_message = text
	_message_time = 2.5

func _prompt() -> String:
	if _message_time > 0.0 and not _message.is_empty():
		return _message
	if not PlayMode.player_driving_enabled():
		return ""
	if active:
		if not is_instance_valid(vehicle) or absf(float(vehicle.speed)) > EXIT_MAX_SPEED:
			return ""
		if vehicle.disabled:
			return "Engine dead · F  Get out" if _exit_ready else "Engine dead · no room to get out here"
		return "F  Get out" if _exit_ready else "No room to get out here · move the car"
	if is_instance_valid(_candidate) and _boardable(_candidate):
		return "F  Drive your car" if _candidate == starter else "F  Drive this car"
	if is_instance_valid(_candidate) and _candidate_ok(_candidate) and _wrecked(_candidate):
		return "Wrecked · won't start"
	return ""

func get_status() -> Dictionary:
	var driving := active and is_instance_valid(vehicle)
	var speed := float(vehicle.speed) if driving else 0.0
	var starter_at: Variant = null
	if is_instance_valid(starter):
		starter_at = [starter.global_position.x, starter.global_position.y, starter.global_position.z]
	return {"active": active, "vehicle_id": str(vehicle.vehicle_id) if driving else "",
		"prompt": _prompt(), "message": _message if _message_time > 0.0 else "",
		"speed": speed, "speed_kmh": absf(speed) * 3.6, "speed_mph": absf(speed) * 2.23694,
		"gear": "R" if speed < -0.3 else ("D" if speed > 0.3 else "N"),
		"steer": float(vehicle.drive_steer) if driving else 0.0, "handbrake": bool(_controls.handbrake),
		"flat_tires": vehicle.flat_tires.duplicate() if driving else [],
		"exit_available": driving and _exit_ready and absf(speed) <= EXIT_MAX_SPEED,
		"candidate_id": _candidate_id(_candidate) if is_instance_valid(_candidate) and not active else "",
		"starter_spawned": is_instance_valid(starter), "starter_id": STARTER_ID if is_instance_valid(starter) else "",
		"starter_position": starter_at, "starter": starter_report.duplicate(true),
		"entries": entries, "exits": exits, "forced_exits": forced_exits, "refused_exits": refused_exits,
		"impacts": impacts, "last_impact": last_impact.duplicate(), "last_exit": last_exit.duplicate(),
		"paused_ticks": paused_ticks, "controls": "WASD drive · Space handbrake · Mouse look · F get out",
		"collisions": collisions, "last_collision": _public_contact(last_collision),
		"vehicle_health": float(vehicle.health) if driving else 0.0, "vehicle_disabled": driving and bool(vehicle.disabled),
		"remembered": remembered.size(), "remembered_ids": registry_ids(), "forgotten": forgotten.size(),
		"promotions": promotions, "evictions": evictions, "cleanups": cleanups, "last_restore": last_restore.duplicate(true),
		"player_driving_enabled": PlayMode.player_driving_enabled()}

## Map/radar hook for root: the starter car while it is not being driven.
func get_map_pois() -> Array:
	if not PlayMode.player_driving_enabled() or not is_instance_valid(starter) or (active and vehicle == starter):
		return []
	return [{"id": "player_car", "label": "Your car", "kind": "vehicle", "position": starter.global_position}]

func _announce_starter() -> void:
	if not PlayMode.player_driving_enabled() or _announced or not is_instance_valid(starter) or not level.has_method("show_notice"):
		return
	if player.global_position.distance_to(starter.global_position) <= 24.0:
		_announced = true
		level.show_notice("Your car is parked nearby. Walk up to it and press F to drive.")

## Presentation hook: the controls applied this tick (zero when not driving).
func current_controls() -> Dictionary:
	return _controls.duplicate() if active else {"throttle": 0.0, "brake": 0.0, "steer": 0.0, "handbrake": false}

func registry_ids() -> Array:
	var ids: Array = []
	for car in remembered:
		if is_instance_valid(car):
			ids.append(str(car.registry_id))
	ids.sort()
	return ids

static func _public_contact(contact: Dictionary) -> Dictionary:
	var copy := contact.duplicate()
	copy.erase("collider")
	return copy

# --- Parked promotion and the remembered registry ----------------------------

func _promote_parked(body: Node3D) -> Node3D:
	var parked = _parked_manager()
	var index := _parked_index(body)
	if parked == null or index < 0:
		return null
	var record: Dictionary = parked.records[index]
	var id := str(record.get("source_id", "parked_%03d" % index))
	if not str(record.get("promoted", "")).is_empty():
		return null
	var pose: Transform3D = record.pose
	var kind := str(record.kind)
	# The record's own collider occupies this exact space; anything else does not.
	if not _hull_clear_of(kind, pose, 2 | 8 | 16, [(body as CollisionObject3D).get_rid(), player.get_rid()]):
		_flash("Something is wedged against this car")
		return null
	if not _make_registry_room(null):
		_flash("Too many of your cars nearby · leave one behind first")
		return null
	var damage: Dictionary = parked.record_damage(index)
	if not parked.hide_record(index, id):
		return null
	var car := _spawn_remembered(id, pose, int(record.paint), kind)
	if car == null:
		parked.restore_record(index)
		return null
	# The live body now carries the record's dents and flats; the hidden
	# original returns pristine only if this car is ever forgotten.
	parked.set_record_damage(index, Vehicle.MAX_HEALTH, [])
	car.set_damage_state(float(damage.health), damage.flat_tires)
	car.source_id = id
	car.source_key = (record.get("source_key", {}) as Dictionary).duplicate(true)
	remembered.append(car)
	promotions += 1
	return car

func _spawn_remembered(id: String, pose: Transform3D, paint: int, kind: String) -> Node3D:
	var car: Node3D = Vehicle.new()
	car.name = "Remembered_" + id
	car.position = to_local(pose.origin)
	add_child(car)
	if not car.setup_parked(traffic, pose, id, paint, kind, false):
		car.free()
		return null
	car.registry_id = id
	if traffic.has_method("register_player_vehicle"):
		traffic.register_player_vehicle(car)
	return car

func _touch_registry(car: Node3D) -> void:
	if forgotten.has(car):
		# Driving a forgotten car again re-remembers it if another can yield.
		forgotten.erase(car)
		if _make_registry_room(car):
			car.registry_id = str(car.source_id)
			remembered.append(car)
		else:
			forgotten.append(car)
	if remembered.has(car):
		sequence += 1
		car.last_used = sequence

func _prune_registry() -> void:
	for list in [remembered, forgotten]:
		for index in range(list.size() - 1, -1, -1):
			if not is_instance_valid(list[index]) or not (list[index] as Node3D).is_inside_tree():
				list.remove_at(index)

## Forget the least recently used remembered car (never the starter, the
## occupied car or `keep`) when the registry is full. Forgotten bodies stay
## until safely unseen; while one is pending, a full registry refuses.
func _make_registry_room(keep: Node3D) -> bool:
	_prune_registry()
	if remembered.size() < MAX_REMEMBERED:
		return true
	if forgotten.size() >= MAX_FORGOTTEN:
		_cleanup_forgotten()
		if forgotten.size() >= MAX_FORGOTTEN:
			return false
	var victim: Node3D = null
	for car in remembered:
		if car == starter or car == keep or (active and car == vehicle):
			continue
		if victim == null or int(car.last_used) < int(victim.last_used):
			victim = car
	if victim == null:
		return false
	remembered.erase(victim)
	victim.registry_id = ""
	forgotten.append(victim)
	evictions += 1
	return true

## Revert forgotten cars only where nobody can see it happen: the body and its
## original curb spot both >80m away and outside the camera view, and that spot
## not taken by another car meanwhile.
func _cleanup_forgotten() -> void:
	_prune_registry()
	var camera := player.get("camera") as Camera3D
	if camera == null:
		return
	var parked = _parked_manager()
	for car in forgotten.duplicate():
		if active and car == vehicle:
			continue
		var index: int = parked.promoted_index(str(car.source_id)) if parked != null else -1
		var spot: Transform3D = parked.records[index].pose if index >= 0 else car.global_transform
		if not _unseen(car, car.global_position, camera) or not _unseen(car, spot.origin, camera):
			continue
		if index >= 0 and _pose_conflicts(str(car.prototype_kind), spot, [car], index):
			continue
		_demote(car)
		cleanups += 1

func _unseen(car: Node3D, point: Vector3, camera: Camera3D) -> bool:
	return player.global_position.distance_to(point) > FORGET_DISTANCE and car._outside_view(point, camera)

## Remove a promoted body and return its original record to the batch.
func _demote(car: Node3D) -> void:
	var index := _remove_body(car)
	if index >= 0:
		_parked_manager().restore_record(index)

## Take a live body out of the world and every registry. Returns the index of
## the record it was hiding (still hidden; the caller decides), else -1.
func _remove_body(car: Node3D) -> int:
	var parked = _parked_manager()
	var index: int = parked.promoted_index(str(car.source_id)) if parked != null and not str(car.source_id).is_empty() else -1
	if traffic != null and traffic.has_method("unregister_player_vehicle"):
		traffic.unregister_player_vehicle(car)
	remembered.erase(car)
	forgotten.erase(car)
	if car.get_parent() != null:
		car.get_parent().remove_child(car)
	car.queue_free()
	return index

func _hull_clear_of(kind: String, pose: Transform3D, mask: int, exclude: Array[RID]) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = mask
	query.margin = 0.0
	query.transform = pose
	query.exclude = exclude
	var space := get_world_3d().direct_space_state
	for part in Collision.parts(kind):
		query.shape = part.shape
		if not space.intersect_shape(query, 1).is_empty():
			return false
	return true

## Footprint overlap with every other car, independent of physics presence:
## parked records (culled or not), traffic and driving's own bodies. With
## after_reset, records hidden by this session's cars count as present again
## unless listed in `vacated` (sources that restore will hide).
func _pose_conflicts(kind: String, pose: Transform3D, ignore: Array, ignore_record := -1, vacated: Array = [], after_reset := false) -> bool:
	var size := Models.dimensions(kind) if Models.has_kind(kind) else Vehicle.BODY_SIZE
	var center := Vector2(pose.origin.x, pose.origin.z)
	var heading := atan2(pose.basis.z.x, pose.basis.z.z)
	# Declared bounds can exceed a hull by a few cm: cars whose hulls merely
	# touch are not a conflict; any real interpenetration (>6cm) is.
	var half := Vector2(maxf(0.1, size.x * 0.5 - 0.06), maxf(0.1, size.z * 0.5 - 0.06))
	var parked = _parked_manager()
	if parked != null:
		for index in parked.records.size():
			var record: Dictionary = parked.records[index]
			if index == ignore_record or vacated.has(index) or (not after_reset and not str(record.get("promoted", "")).is_empty()):
				continue
			var other: Transform3D = record.pose
			var other_size := Models.dimensions(str(record.kind))
			if absf(other.origin.y - pose.origin.y) < 2.5 and _rects_overlap(center, heading, half,
				Vector2(other.origin.x, other.origin.z), atan2(other.basis.z.x, other.basis.z.z), Vector2(other_size.x, other_size.z) * 0.5):
				return true
	var cars: Array = []
	if traffic != null:
		cars.append_array(traffic.vehicles)
		cars.append_array(traffic.player_fleet)
	for car in cars:
		if not is_instance_valid(car) or not car.is_inside_tree() or ignore.has(car):
			continue
		var other_size := _car_size(car)
		var at: Vector3 = car.global_position
		if absf(at.y - pose.origin.y) < 2.5 and _rects_overlap(center, heading, half,
			Vector2(at.x, at.z), float(car.yaw), Vector2(other_size.x, other_size.z) * 0.5):
			return true
	return false

## Separating-axis test for two yawed rectangles in XZ (half = width/2, length/2).
static func _rects_overlap(a: Vector2, a_yaw: float, a_half: Vector2, b: Vector2, b_yaw: float, b_half: Vector2) -> bool:
	var reach := a_half.length() + b_half.length()
	if a.distance_squared_to(b) > reach * reach:
		return false
	var a_forward := Vector2(sin(a_yaw), cos(a_yaw))
	var a_side := Vector2(cos(a_yaw), -sin(a_yaw))
	var b_forward := Vector2(sin(b_yaw), cos(b_yaw))
	var b_side := Vector2(cos(b_yaw), -sin(b_yaw))
	var delta := b - a
	for axis in [a_forward, a_side, b_forward, b_side]:
		var ra := a_half.y * absf(axis.dot(a_forward)) + a_half.x * absf(axis.dot(a_side))
		var rb := b_half.y * absf(axis.dot(b_forward)) + b_half.x * absf(axis.dot(b_side))
		if absf(delta.dot(axis)) > ra + rb:
			return false
	return true

# --- Persistence (contract §5; the save owner validates the containing file) ---

func snapshot_state() -> Dictionary:
	_prune_registry()
	var cars: Array = []
	for car in remembered:
		if not (active and car == vehicle):
			cars.append(car)
	cars.sort_custom(func(a: Node3D, b: Node3D) -> bool: return str(a.registry_id) < str(b.registry_id))
	var vehicles: Array = []
	for car in cars:
		vehicles.append(_vehicle_snapshot(car))
	var parked = _parked_manager()
	var damage: Array = parked.damage_snapshot() if parked != null and parked.has_method("damage_snapshot") else []
	return {"version": PERSIST_VERSION, "sequence": sequence, "vehicles": vehicles, "parked_damage": damage}

func _vehicle_snapshot(car: Node3D) -> Dictionary:
	var at: Vector3 = car.global_position
	var is_starter: bool = car == starter
	var tires: Array = []
	for tire in car.flat_tires:
		tires.append(int(tire))
	tires.sort()
	var stored_health := 0.0 if car.disabled else maxf(0.01, snappedf(float(car.health), 0.01))
	return {"id": str(car.registry_id), "source": "starter" if is_starter else "parked",
		"source_id": "" if is_starter else str(car.source_id),
		"source_key": {} if is_starter else (car.source_key as Dictionary).duplicate(true),
		"prototype": str(car.prototype_kind), "paint": int(car.paint_index),
		"position": [snappedf(at.x, 0.001), snappedf(at.y, 0.001), snappedf(at.z, 0.001)],
		"yaw": canonical_yaw(float(car.yaw)), "health": stored_health,
		"disabled": bool(car.disabled), "flat_tires": tires, "last_used": mini(int(car.last_used), sequence)}

## Quantized heading with one representation for ±PI, so a restored car
## (whose yaw is the stored value) snapshots to the identical number.
static func canonical_yaw(yaw: float) -> float:
	var stored := snappedf(wrapf(yaw, -PI, PI), 0.0001)
	return -3.1416 if stored >= 3.1416 else stored

func validate_state(value) -> String:
	if not value is Dictionary:
		return "payload is not a dictionary"
	var state: Dictionary = value
	for key in state:
		if not str(key) in ["version", "sequence", "vehicles", "parked_damage"]:
			return "unknown field " + str(key)
	if not _integer(state.get("version"), PERSIST_VERSION, PERSIST_VERSION):
		return "unsupported version"
	if not _integer(state.get("sequence"), 0, 1000000000):
		return "invalid sequence"
	if not state.get("vehicles") is Array or not state.get("parked_damage") is Array:
		return "missing vehicle lists"
	var vehicles: Array = state.vehicles
	var damage: Array = state.parked_damage
	if vehicles.size() > MAX_REMEMBERED:
		return "too many remembered vehicles"
	if damage.size() > MAX_PARKED_DAMAGE:
		return "too many damaged parked records"
	var ids: Dictionary = {}
	var sources: Dictionary = {}
	var starters := 0
	for entry in vehicles:
		var error := _validate_vehicle_entry(entry, int(state.sequence))
		if not error.is_empty():
			return error
		if ids.has(entry.id):
			return "duplicate vehicle id"
		ids[entry.id] = true
		if entry.source == "starter":
			starters += 1
		elif sources.has(entry.source_id):
			return "duplicate parked source"
		else:
			sources[entry.source_id] = true
	if starters > 1:
		return "more than one starter"
	for entry in damage:
		var error := _validate_damage_entry(entry)
		if not error.is_empty():
			return error
		if sources.has(entry.source_id):
			return "duplicate parked source"
		sources[entry.source_id] = true
	return ""

func _validate_vehicle_entry(entry, max_sequence: int) -> String:
	if not entry is Dictionary:
		return "vehicle record is not a dictionary"
	var record: Dictionary = entry
	for key in record:
		if not str(key) in VEHICLE_FIELDS:
			return "unknown vehicle field " + str(key)
	for key in VEHICLE_FIELDS:
		if not record.has(key):
			return "missing vehicle field " + key
	if not _valid_id(record.id):
		return "invalid vehicle id"
	if not record.source is String or not str(record.source) in ["starter", "parked"]:
		return "invalid vehicle source"
	if not record.prototype is String or not Models.has_kind(str(record.prototype)):
		return "unknown vehicle prototype"
	if record.source == "starter":
		if record.id != STARTER_ID or not record.source_id is String or not str(record.source_id).is_empty() \
			or not record.source_key is Dictionary or not (record.source_key as Dictionary).is_empty():
			return "invalid starter identity"
	else:
		if not _valid_id(record.source_id) or not str(record.source_id).begins_with("parked_") or record.source_id != record.id:
			return "invalid parked identity"
		var key_error := _validate_source_key(record.source_key)
		if not key_error.is_empty():
			return key_error
		if record.prototype != record.source_key.kind:
			return "prototype does not match its parked source"
	if not _integer(record.paint, 0, Models.PALETTE.size() - 1):
		return "invalid paint"
	if not _position(record.position):
		return "invalid vehicle position"
	if not _number(record.yaw, -PI - 0.001, PI + 0.001):
		return "invalid vehicle yaw"
	if not _number(record.health, 0.0, Vehicle.MAX_HEALTH):
		return "invalid vehicle health"
	if not record.disabled is bool or bool(record.disabled) != (float(record.health) <= 0.0):
		return "disabled state does not match health"
	var tire_error := _validate_tires(record.flat_tires)
	if not tire_error.is_empty():
		return tire_error
	if not _integer(record.last_used, 0, max_sequence):
		return "invalid last use"
	return ""

func _validate_damage_entry(entry) -> String:
	if not entry is Dictionary:
		return "parked damage is not a dictionary"
	var record: Dictionary = entry
	for key in record:
		if not str(key) in DAMAGE_FIELDS:
			return "unknown parked damage field " + str(key)
	for key in DAMAGE_FIELDS:
		if not record.has(key):
			return "missing parked damage field " + key
	if not _valid_id(record.source_id) or not str(record.source_id).begins_with("parked_"):
		return "invalid parked damage source"
	var key_error := _validate_source_key(record.source_key)
	if not key_error.is_empty():
		return key_error
	if not _number(record.health, 0.0, Vehicle.MAX_HEALTH):
		return "invalid parked damage health"
	return _validate_tires(record.flat_tires)

func _validate_source_key(value) -> String:
	if not value is Dictionary:
		return "invalid parked source key"
	var key: Dictionary = value
	if key.size() != 3 or not key.get("street") is String or str(key.street).is_empty() or str(key.street).length() > 96:
		return "invalid parked source street"
	if not key.get("kind") is String or not Models.has_kind(str(key.kind)):
		return "invalid parked source kind"
	if not _position(key.get("origin")):
		return "invalid parked source origin"
	return ""

func _validate_tires(value) -> String:
	if not value is Array or (value as Array).size() > 4:
		return "invalid flat tires"
	var seen: Dictionary = {}
	for tire in value:
		if not _integer(tire, 0, 3) or seen.has(int(tire)):
			return "invalid flat tires"
		seen[int(tire)] = true
	return ""

static func _valid_id(value) -> bool:
	if not value is String or (value as String).is_empty() or (value as String).length() > 48:
		return false
	for character in (value as String):
		if not character in "abcdefghijklmnopqrstuvwxyz0123456789_":
			return false
	return true

static func _number(value, low: float, high: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) >= low and float(value) <= high

static func _integer(value, low: int, high: int) -> bool:
	return _number(value, low, high) and float(value) == floorf(float(value))

static func _position(value) -> bool:
	if not value is Array or (value as Array).size() != 3:
		return false
	return _number(value[0], -100000.0, 100000.0) and _number(value[1], -1000.0, 1000.0) and _number(value[2], -100000.0, 100000.0)

## No mutation. Fails only for an invalid payload or an occupied car; scene
## mismatches are the plan's predicted fallbacks ("<id>:<reason>").
func preflight_state(value) -> Dictionary:
	var error := validate_state(value)
	if not error.is_empty():
		return {"ok": false, "reason": "invalid: " + error, "fallbacks": []}
	if active:
		return {"ok": false, "reason": "vehicle occupied", "fallbacks": []}
	var plan := _plan_restore(value)
	if not bool(plan.ok):
		return {"ok": false, "reason": str(plan.reason), "fallbacks": []}
	var predicted: Array[String] = []
	for fallback in plan.fallbacks:
		predicted.append(str(fallback.id) + ":" + str(fallback.reason))
	return {"ok": true, "reason": "", "fallbacks": predicted}

## Replace the remembered world with `value`. Invalid payloads (or an occupied
## car) change nothing. Otherwise every destination is planned against the
## post-reset world first, then committed in one pass; a repeated restore never
## duplicates a car, and each mismatch is an explicit fallback, never invented.
func restore_state(value) -> Dictionary:
	var error := validate_state(value)
	if not error.is_empty():
		last_restore = {"ok": false, "restored": 0, "fallbacks": [], "reason": "invalid: " + error}
		return last_restore.duplicate(true)
	if active:
		last_restore = {"ok": false, "restored": 0, "fallbacks": [], "reason": "vehicle occupied"}
		return last_restore.duplicate(true)
	var plan := _plan_restore(value)
	if not bool(plan.ok) or not _commit_plan(plan):
		last_restore = {"ok": false, "restored": 0, "fallbacks": [], "reason": str(plan.reason) if not bool(plan.ok) else "vehicle staging failed"}
		return last_restore.duplicate(true)
	last_restore = {"ok": true, "restored": int(plan.restored), "fallbacks": (plan.fallbacks as Array).duplicate(true), "reason": ""}
	return last_restore.duplicate(true)

## New game / legacy-checkpoint baseline: every promoted or forgotten car
## reverts to its record, parked damage clears and the starter returns home
## repaired (or stays put if home is blocked and where it stands is safe).
## Refused, changing nothing, while the player occupies a car or when no safe
## starter placement exists. True when applied.
func reset_persistent_state() -> bool:
	if active:
		return false
	var plan := _plan_restore({"version": PERSIST_VERSION, "sequence": 0, "vehicles": [], "parked_damage": []})
	if not bool(plan.ok) or not _commit_plan(plan):
		last_restore = {"ok": false, "restored": 0, "fallbacks": [], "reason": str(plan.reason)}
		return false
	last_restore = {"ok": true, "restored": 0, "fallbacks": (plan.fallbacks as Array).duplicate(true), "reason": "reset"}
	return true

func _entry_position(entry: Dictionary) -> Vector3:
	return Vector3(float(entry.position[0]), float(entry.position[1]), float(entry.position[2]))

## Pure planning against the world as it will be after the reset: current
## remembered/forgotten bodies are gone (ignored), their hidden records are
## back unless reserved, and the source of every car being restored is
## reserved (vacated). A destination that fails returns its source to the curb
## and the remaining cars are re-planned around it (bounded: one row per pass).
func _plan_restore(value: Dictionary) -> Dictionary:
	var parked = _parked_manager()
	var ignore: Array = []
	ignore.append_array(remembered)
	ignore.append_array(forgotten)
	if is_instance_valid(starter) and not ignore.has(starter):
		ignore.append(starter)
	var fallbacks: Array = []
	var starter_entry: Dictionary = {}
	var ordered: Array = []
	for entry in value.vehicles:
		if entry.source == "starter":
			starter_entry = entry
		else:
			ordered.append(entry)
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.id) < str(b.id))
	var rows: Array = []
	var claimed: Array = []
	for entry in ordered:
		var index: int = parked.source_index(str(entry.source_id), entry.source_key) if parked != null else -1
		if index < 0 or claimed.has(index):
			fallbacks.append({"id": str(entry.id), "reason": "source_missing" if index < 0 else "source_taken", "action": "dropped"})
			continue
		claimed.append(index)
		rows.append({"entry": entry, "index": index, "kind": str(parked.records[index].kind), "live": true, "pose": Transform3D.IDENTITY})
	var starter_plan: Dictionary = {}
	for _pass in rows.size() + 1:
		var reserved: Array = []
		for row in rows:
			if row.live:
				reserved.append(int(row.index))
		starter_plan = _plan_starter(starter_entry, ignore, reserved)
		var placed: Array = []
		if starter_plan.has("pose"):
			placed.append({"kind": str(starter.prototype_kind), "pose": starter_plan.pose})
		var settled := true
		for row in rows:
			if not row.live:
				continue
			var entry: Dictionary = row.entry
			var spot := _restore_pose(str(row.kind), _entry_position(entry), float(entry.yaw), null, int(row.index), ignore, reserved, placed)
			if spot.is_empty():
				row.live = false
				settled = false
				break
			row.pose = spot.transform
			placed.append({"kind": str(row.kind), "pose": row.pose})
		if settled:
			break
	var restored := 0
	if not starter_entry.is_empty() and is_instance_valid(starter):
		restored += 1
	if not (starter_plan.get("fallback", {}) as Dictionary).is_empty():
		fallbacks.append(starter_plan.fallback)
	for row in rows:
		var entry: Dictionary = row.entry
		if not row.live:
			fallbacks.append({"id": str(entry.id), "reason": "pose_blocked", "action": "returned_to_source"})
			continue
		restored += 1
		var source := str(parked.records[int(row.index)].get("source_id", "parked_%03d" % int(row.index)))
		if source != str(entry.id):
			fallbacks.append({"id": str(entry.id), "reason": "source_reassigned", "action": "restored_as_" + source})
	var damage: Array = []
	for entry in value.parked_damage:
		var index: int = parked.source_index(str(entry.source_id), entry.source_key) if parked != null else -1
		if index < 0 or claimed.has(index):
			fallbacks.append({"id": str(entry.source_id), "reason": "source_missing" if index < 0 else "source_taken", "action": "dropped"})
		else:
			claimed.append(index)
			damage.append({"index": index, "entry": entry})
	var reason := "no safe starter placement" if bool(starter_plan.get("blocked", false)) else _check_returning_sources(rows, starter_plan, ignore)
	return {"ok": reason.is_empty(), "reason": reason, "rows": rows, "starter": starter_plan,
		"starter_entry": starter_entry, "damage": damage, "fallbacks": fallbacks, "restored": restored, "sequence": int(value.sequence)}

## Originals this commit would bring back (hidden by a body being removed and
## not reserved by a restored car) must have a clear curb spot: no explorer,
## person, other car or planned destination there. Otherwise refuse atomically.
## The curb pose itself is map data, validated when the batch was generated.
func _check_returning_sources(rows: Array, starter_plan: Dictionary, ignore: Array) -> String:
	var parked = _parked_manager()
	if parked == null:
		return ""
	var reserved: Array = []
	var placed: Array = []
	if starter_plan.has("pose"):
		placed.append({"kind": str(starter.prototype_kind), "pose": starter_plan.pose})
	for row in rows:
		if row.live:
			reserved.append(int(row.index))
			placed.append({"kind": str(row.kind), "pose": row.pose})
	for index in parked.records.size():
		var record: Dictionary = parked.records[index]
		if reserved.has(index) or str(record.get("promoted", "")).is_empty():
			continue
		var kind := str(record.kind)
		var pose: Transform3D = record.pose
		var empty: Array[RID] = []
		if not _hull_clear_of(kind, pose, 4 | 8, empty) or _pose_conflicts(kind, pose, ignore, index, reserved, true) \
				or _overlaps_planned(kind, pose, placed):
			return "no safe returned source: " + str(record.get("source_id", "parked_%03d" % index))
	return ""

## Saved pose if valid; else the validated home spot (exactly as spawned);
## else where it stands now, if that is also valid in the post-reset world.
## With no safe candidate the whole plan refuses ("blocked": true).
func _plan_starter(entry: Dictionary, ignore: Array, reserved: Array) -> Dictionary:
	if not is_instance_valid(starter):
		return {} if entry.is_empty() else {"fallback": {"id": STARTER_ID, "reason": "starter_unavailable", "action": "dropped"}}
	var kind := str(starter.prototype_kind)
	if not entry.is_empty():
		var saved := _restore_pose(kind, _entry_position(entry), float(entry.yaw), starter, -1, ignore, reserved)
		if not saved.is_empty():
			return {"pose": saved.transform, "heading": float(entry.yaw), "fallback": {}}
	if _starter_home_valid and not _restore_pose(kind, starter_home.origin, starter_home_yaw, starter, -1, ignore, reserved).is_empty():
		return {"pose": starter_home, "heading": starter_home_yaw,
			"fallback": {} if entry.is_empty() else {"id": STARTER_ID, "reason": "pose_blocked", "action": "kept_spawn"}}
	var current := _restore_pose(kind, starter.global_position, float(starter.yaw), starter, -1, ignore, reserved)
	if not current.is_empty():
		return {"pose": starter.global_transform, "heading": float(starter.yaw),
			"fallback": {"id": STARTER_ID, "reason": "pose_blocked" if not entry.is_empty() else "home_blocked", "action": "kept_current"}}
	return {"blocked": true, "fallback": {}}

## Stage every new body first (hidden, non-solid, unregistered) so a failed
## allocation leaves the old world untouched; then, in one uninterrupted pass,
## revert this session's cars (their originals settle back) and publish
## exactly what the plan validated. False = refused without mutation.
func _commit_plan(plan: Dictionary) -> bool:
	var parked = _parked_manager()
	var staged: Array = []
	for row in plan.rows:
		if not row.live:
			continue
		var record: Dictionary = parked.records[int(row.index)]
		var car := _spawn_remembered(str(record.get("source_id", "parked_%03d" % int(row.index))), row.pose, int(record.paint), str(record.kind))
		if car == null:
			for other in staged:
				_remove_body(other)
			plan.reason = "vehicle staging failed"
			return false
		car.visible = false
		car.collision_layer = 0
		car.near_physics = false
		row["car"] = car
		staged.append(car)
	# Remove every old body before any original returns, so none is judged
	# against a car that is itself leaving; planned sources stay hidden.
	_prune_registry()
	var returning: Array[int] = []
	for car in remembered.duplicate() + forgotten.duplicate():
		if car != starter:
			var index := _remove_body(car)
			if index >= 0:
				returning.append(index)
	for row in plan.rows:
		if row.live:
			var index := int(row.index)
			returning.erase(index)
			parked.hide_record(index, str(parked.records[index].get("source_id", "parked_%03d" % index)))
	if parked != null and parked.has_method("clear_damage"):
		parked.clear_damage()
	if is_instance_valid(starter):
		var target: Dictionary = plan.starter
		var saved: Dictionary = plan.starter_entry
		if target.has("pose"):
			starter.place_parked(target.pose, float(target.heading))
		starter.set_damage_state(Vehicle.MAX_HEALTH if saved.is_empty() else float(saved.health), [] if saved.is_empty() else saved.flat_tires)
		starter.last_used = 0 if saved.is_empty() else int(saved.last_used)
		if not remembered.has(starter):
			remembered.append(starter)
		_settle_collider(starter)
	# Originals come back only after the starter has moved; each was checked
	# clear, and still settles if something arrived in the same frame.
	for index in returning:
		parked.restore_record(index)
	for row in plan.rows:
		var entry: Dictionary = row.entry
		var index := int(row.index)
		if not row.live:
			parked.set_record_damage(index, float(entry.health), entry.flat_tires)
			continue
		var record: Dictionary = parked.records[index]
		var source := str(record.get("source_id", "parked_%03d" % index))
		var car: Node3D = row.car
		car.visible = true
		car.place_parked(row.pose, float(entry.yaw))
		car.set_damage_state(float(entry.health), entry.flat_tires)
		car.source_id = source
		car.source_key = (record.get("source_key", {}) as Dictionary).duplicate(true)
		car.last_used = int(entry.last_used)
		remembered.append(car)
		_settle_collider(car)
	for item in plan.damage:
		parked.set_record_damage(int(item.index), float(item.entry.health), item.entry.flat_tires)
	sequence = int(plan.sequence)
	for car in remembered:
		sequence = maxi(sequence, int(car.last_used))
	return true

## Restored bodies re-enter physics through the activation guard (zero margin,
## people, explorer, props and cars): someone standing in the spot keeps the
## collider off until clear; it never switches on inside anyone.
func _settle_collider(car: Node3D) -> void:
	car.near_physics = false
	car.collision_layer = 0
	if is_instance_valid(player):
		car.set_presence(player.global_position)

## The saved pose, tilted to the ground under it, if a car of `kind` can sit
## there now: supported within tolerance, clear of props and terrain risers,
## and not overlapping any other car (culled parked colliders included). For
## restore planning, `ignore` bodies are about to be removed, `reserved`
## records are about to be vacated, currently hidden records count as back,
## and `placed` holds destinations already planned.
func _restore_pose(kind: String, at: Vector3, heading: float, own: Node3D, own_record: int, ignore: Array = [],
		reserved: Array = [], placed: Array = []) -> Dictionary:
	if not at.is_finite() or not is_finite(heading):
		return {}
	var forward := Vector3(sin(heading), 0.0, cos(heading))
	var right := Vector3(forward.z, 0.0, -forward.x)
	var heights: Array[float] = []
	var space := get_world_3d().direct_space_state
	for offset in [Vector3.ZERO, forward * 1.35, -forward * 1.35, right * 0.80, -right * 0.80]:
		var point: Vector3 = at + offset
		var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 1.5, point - Vector3.UP * 3.0, 1)
		ray.hit_back_faces = false
		var hit := space.intersect_ray(ray)
		if hit.is_empty() or hit.normal.y < 0.6:
			return {}
		heights.append(float(hit.position.y))
	var support := (heights[1] + heights[2] + heights[3] + heights[4]) * 0.25 + 0.025
	var pitch := (heights[1] - heights[2]) / 2.70
	var roll := (heights[3] - heights[4]) / 1.60
	if absf(at.y - support) > RESTORE_SUPPORT_TOLERANCE or absf(pitch) > Vehicle.DRIVE_MAX_SLOPE or absf(roll) > Vehicle.DRIVE_MAX_SLOPE:
		return {}
	forward.y = pitch
	right.y = roll
	forward = forward.normalized()
	var up := forward.cross(right).normalized()
	right = up.cross(forward).normalized()
	var pose := Transform3D(Basis(right, up, forward), at)
	var exclude: Array[RID] = [player.get_rid()]
	var skip: Array = ignore.duplicate()
	if is_instance_valid(own):
		exclude.append((own as CollisionObject3D).get_rid())
		skip.append(own)
	var parked = _parked_manager()
	var vacated: Array = reserved.duplicate()
	if own_record >= 0:
		vacated.append(own_record)
	if parked != null:
		for index in vacated:
			exclude.append((parked.records[int(index)].body as CollisionObject3D).get_rid())
	for car in skip:
		if is_instance_valid(car) and car is CollisionObject3D:
			exclude.append((car as CollisionObject3D).get_rid())
	# Props and people. The explorer is excluded (world-save places them after
	# vehicles; the activation guard still keeps a collider off inside them).
	if not _hull_clear_of(kind, pose, 2 | 8, exclude):
		return {}
	var lifted := pose * Transform3D(Basis.IDENTITY, Vector3.UP * Vehicle.DRIVE_TERRAIN_LIFT)
	if not _hull_clear_of(kind, lifted, 1, exclude):
		return {}
	if _pose_conflicts(kind, pose, skip, own_record, vacated, true) or _overlaps_planned(kind, pose, placed):
		return {}
	return {"transform": pose}

func _overlaps_planned(kind: String, pose: Transform3D, placed: Array) -> bool:
	var size := Models.dimensions(kind) if Models.has_kind(kind) else Vehicle.BODY_SIZE
	var half := Vector2(maxf(0.1, size.x * 0.5 - 0.06), maxf(0.1, size.z * 0.5 - 0.06))
	for item in placed:
		var other: Transform3D = item.pose
		var other_kind := str(item.kind)
		var other_size := Models.dimensions(other_kind) if Models.has_kind(other_kind) else Vehicle.BODY_SIZE
		if absf(other.origin.y - pose.origin.y) < 2.5 and _rects_overlap(Vector2(pose.origin.x, pose.origin.z), atan2(pose.basis.z.x, pose.basis.z.z), half,
			Vector2(other.origin.x, other.origin.z), atan2(other.basis.z.x, other.basis.z.z), Vector2(other_size.x, other_size.z) * 0.5):
			return true
	return false

# --- Starter car ---------------------------------------------------------------

func _spawn_starter() -> void:
	var data = level.get("level_data")
	if not data is Dictionary or (data as Dictionary).get("roads", []).is_empty():
		starter_report = {"spawned": false, "reason": "no road data"}
		return
	var spawn: Dictionary = data.get("spawn", {})
	var origin := _vector(spawn.get("position")) if spawn.has("position") else player.global_position
	var facing := float(spawn.get("yaw", player.yaw))
	var kind := Catalog.traffic_kind(STARTER_PAINT)
	_index_surroundings(data, origin)
	var candidates := _starter_candidates(data, origin, facing, Models.dimensions(kind).x * 0.5)
	var fallback: Dictionary = {}
	var checked := 0
	for candidate in candidates:
		if checked >= STARTER_MAX_CHECKS:
			break
		checked += 1
		var placed := _validate_starter(candidate, kind)
		if placed.is_empty():
			continue
		# Prefer a car the player can see from the spawn view.
		if _visible_from(origin, placed.transform.origin):
			if _place_starter(placed.transform, candidate, checked, true):
				return
		elif fallback.is_empty():
			fallback = {"transform": placed.transform, "candidate": candidate}
	if not fallback.is_empty() and _place_starter(fallback.transform, fallback.candidate, checked, false):
		return
	starter_report = {"spawned": false, "reason": "no clear curbside spot", "checked": checked,
		"candidates": candidates.size(), "rejects": _rejects.duplicate()}
	push_warning("Driving: no clear starter car spot within %dm of spawn (%d checked)." % [int(STARTER_MAX_DISTANCE), checked])

func _place_starter(pose: Transform3D, candidate: Dictionary, checked: int, visible_from_spawn: bool) -> bool:
	var car: Node3D = Vehicle.new()
	car.name = "StarterCar"
	car.position = to_local(pose.origin)
	add_child(car)
	if not car.setup_parked(traffic, pose, STARTER_ID, STARTER_PAINT):
		car.free()
		return false
	starter = car
	car.registry_id = STARTER_ID
	starter_home = car.global_transform
	starter_home_yaw = float(car.yaw)
	_starter_home_valid = true
	remembered.append(car)
	if traffic.has_method("register_player_vehicle"):
		traffic.register_player_vehicle(car)
	_build_label(car)
	starter_report = {"spawned": true, "street": str(candidate.street), "kind": str(car.prototype_kind),
		"position": [pose.origin.x, pose.origin.y, pose.origin.z], "yaw": float(car.yaw),
		"visible_from_spawn": visible_from_spawn, "checked": checked, "rejects": _rejects.duplicate()}
	return true

func _build_label(car: Node3D) -> void:
	if not PlayMode.player_driving_enabled():
		return # A plain parked car: no "YOUR CAR · F Drive" invitation.
	_label = Label3D.new()
	_label.name = "StarterCarLabel"
	_label.text = "YOUR CAR\nF  Drive"
	_label.position = Vector3(0.0, _car_size(car).y + 0.8, 0.0)
	_label.font_size = 40
	_label.pixel_size = 0.0035
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.modulate = Color("fff1c8")
	_label.outline_modulate = Color("13282c")
	_label.outline_size = 10
	# The HUD prompt takes over at the door; keep the label off the windshield.
	_label.visibility_range_begin = 2.2
	_label.visibility_range_end = 90.0
	car.add_child(_label)

func _index_surroundings(data: Dictionary, origin: Vector3) -> void:
	# Bound the per-candidate checks to roads, walk route and lanes near spawn.
	var reach := STARTER_MAX_DISTANCE + 40.0
	_near_roads.clear()
	for road in data.get("roads", []):
		var points := PackedVector3Array()
		var near := false
		for value in road.get("points", []):
			var point := _vector(value)
			points.append(point)
			near = near or Vector2(point.x - origin.x, point.z - origin.z).length() < reach
		if near and points.size() >= 2:
			_near_roads.append({"name": str(road.get("name", "")), "width": float(road.get("width", 0.0)), "points": points})
	_near_route.clear()
	var route = data.get("route", {})
	if route is Dictionary:
		var points := PackedVector3Array()
		for value in route.get("points", []):
			points.append(_vector(value))
		if points.size() >= 2:
			_near_route.append(points)
	_near_lanes.clear()
	var network = traffic.get("network")
	if network == null:
		return
	var paths: Array = []
	for lane in network.lanes:
		if bool(lane.enabled):
			paths.append(lane.points)
	var cached = network.get("_connector_cache")
	if cached is Dictionary:
		paths.append_array(cached.values())
	for path in paths:
		if path.size() < 2:
			continue
		for point in path:
			if Vector2(point.x - origin.x, point.z - origin.z).length() < reach:
				_near_lanes.append(PackedVector3Array(path))
				break

func _starter_candidates(data: Dictionary, origin: Vector3, facing: float, half_width: float) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var view := Vector3(sin(facing), 0.0, cos(facing))
	for road in _near_roads:
		var width := float(road.width)
		if width < 7.0:
			continue
		var points: PackedVector3Array = road.points
		for i in range(1, points.size()):
			var a := points[i - 1]
			var b := points[i]
			var length := Vector2(b.x - a.x, b.z - a.z).length()
			if length < 1.0:
				continue
			var forward := Vector3(b.x - a.x, 0.0, b.z - a.z) / length
			var right := forward.cross(Vector3.UP)
			var along := 0.75
			while along < length - 0.75:
				var center := a.lerp(b, along / length)
				for side in [1.0, -1.0]:
					var at: Vector3 = center + right * float(side) * (width * 0.5 - half_width - 0.25)
					var offset := Vector3(at.x - origin.x, 0.0, at.z - origin.z)
					var distance := offset.length()
					if distance >= STARTER_MIN_DISTANCE and distance <= STARTER_MAX_DISTANCE:
						# Nearest first, favouring spots ahead of the spawn view.
						var ahead := view.dot(offset / distance)
						found.append({"at": at, "forward": forward * float(side), "road_forward": forward,
							"curb": right * float(side), "center": center, "width": width,
							"street": str(road.name), "score": distance - 8.0 * ahead})
				along += 1.5
	found.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x.score) < float(y.score))
	return found

func _reject(reason: String) -> Dictionary:
	_rejects[reason] = int(_rejects.get(reason, 0)) + 1
	return {}

func _validate_starter(candidate: Dictionary, kind: String) -> Dictionary:
	var at: Vector3 = candidate.at
	var flat := Vector2(at.x, at.z)
	for path in _near_lanes:
		for i in range(1, path.size()):
			if _segment_distance(flat, path[i - 1], path[i]) < LANE_CLEARANCE:
				return _reject("moving_lane")
	for road in _near_roads:
		if str(road.name) == str(candidate.street):
			continue
		var points: PackedVector3Array = road.points
		var mouth := float(road.width) * 0.5 + JUNCTION_CLEARANCE
		for i in range(1, points.size()):
			if _segment_distance(flat, points[i - 1], points[i]) < mouth:
				return _reject("junction")
	for path in _near_route:
		for i in range(1, path.size()):
			if _segment_distance(flat, path[i - 1], path[i]) < ROUTE_CLEARANCE:
				return _reject("walk_route")
	var parked = traffic.get("parked")
	if parked != null:
		for record in parked.records:
			var pose: Transform3D = record.pose
			if Vector2(pose.origin.x - at.x, pose.origin.z - at.z).length() < PARKED_SPACING:
				return _reject("parked_car")
	if CivicClearance.blocked(level, at, 2.5):
		return _reject("civic_approach")
	var vegetation = level.get("vegetation")
	if vegetation != null and vegetation.has_method("is_trunk_clear") and not vegetation.is_trunk_clear(at, 2.7):
		return _reject("tree_trunk")
	var forward: Vector3 = candidate.forward
	var right := Vector3(forward.z, 0.0, -forward.x)
	var heights: Array[float] = []
	for offset in [Vector3.ZERO, forward * 1.4, -forward * 1.4, right * 0.78, -right * 0.78]:
		var hit := _ground(at + offset)
		if hit.is_empty() or hit.normal.y < 0.90:
			return _reject("ground")
		heights.append(float(hit.position.y))
	if heights.max() - heights.min() > 0.12:
		return _reject("uneven")
	# A continuous raised curb at both ends: never a driveway, alley or curb cut.
	var road_forward: Vector3 = candidate.road_forward
	var curb: Vector3 = candidate.curb
	var width := float(candidate.width)
	for offset in [-1.8, 0.0, 1.8]:
		var section: Vector3 = candidate.center + road_forward * float(offset)
		var inside := _ground(section + curb * (width * 0.5 - 0.32))
		var outside := _ground(section + curb * (width * 0.5 + 0.32))
		if inside.is_empty() or outside.is_empty():
			return _reject("curb_gap")
		var rise: float = outside.position.y - inside.position.y
		if rise < 0.055 or rise > 0.32:
			return _reject("driveway_or_curb_cut")
	forward.y = (heights[1] - heights[2]) / 2.8
	right.y = (heights[3] - heights[4]) / 1.56
	forward = forward.normalized()
	var up := forward.cross(right).normalized()
	right = up.cross(forward).normalized()
	at.y = (heights[1] + heights[2] + heights[3] + heights[4]) * 0.25 + 0.025
	var pose := Transform3D(Basis(right, up, forward), at)
	# The exact compound hull, with margin, clear of props, people and vehicles.
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = 2 | 4 | 8 | 16
	query.margin = 0.05
	query.transform = pose
	var space := get_world_3d().direct_space_state
	for part in Collision.parts(kind):
		query.shape = part.shape
		if not space.intersect_shape(query, 1).is_empty():
			return _reject("occupied")
	return {"transform": pose}

func _ground(at: Vector3) -> Dictionary:
	var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.5, at - Vector3.UP * 2.5, 1)
	ray.hit_back_faces = false
	return get_world_3d().direct_space_state.intersect_ray(ray)

func _visible_from(origin: Vector3, point: Vector3) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(origin + Vector3.UP * 1.6, point + Vector3.UP * 1.0, 2)
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

static func _segment_distance(point: Vector2, a: Vector3, b: Vector3) -> float:
	return Geometry2D.get_closest_point_to_segment(point, Vector2(a.x, a.z), Vector2(b.x, b.z)).distance_to(point)

static func _vector(value) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO
