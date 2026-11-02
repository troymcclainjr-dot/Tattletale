extends RefCounted
## Police cruisers for the law response, composed, ticked and reset by
## city_law.gd. At most two real police cars from traffic are claimed under the
## vehicle owner's external authority (traffic.claim_external_vehicle) and
## driven through car.external_step: the same swept hull, terrain and curb
## physics as the player's car, so nothing passes through buildings, cars or
## people and nothing is ever teleported. The player's car is never touched.
##
## Each claimed car carries one dedicated officer, a registered actor with a
## persistent id (patrol_officer_cruiser_1/2) in level.npcs.actors, so a death
## is recorded and validated like any other. Exactly one representation exists:
## seated (disabled, hidden, no collider) or on foot (an ordinary law responder
## that combat may own through engage_actor). A dead officer is never re-seated.
##
## Cruisers learn where to go only from filed reports and real sightings: their
## own crew's line of sight, or another officer's radioed sighting. Lost sight
## leaves the last known position as the goal; nothing reads the hidden player.
## Driving follows the traffic network's directed lanes and validated junction
## connectors, slows for curves and junctions, yields to crossing traffic, stops
## behind cars and people, passes a stopped car only along a clear on-road
## offset, and reverses and replans when stuck. Every failure is bounded and
## falls back to the officer continuing on foot.
##
## city_police_assistance.gd may also claim a car for a neighbor's call
## (request_assist). Those units are tagged `assist` and never read the player:
## no perception, radio, law dispatch or phase counting touches them.

const Lanes := preload("res://scripts/city/city_police_lanes.gd")
const Driver := preload("res://scripts/city/city_police_driver.gd")
const Actor := preload("res://scripts/city/city_npc_actor.gd")
const Appearance := preload("res://scripts/city/city_population_appearance.gd")
const Facilities := preload("res://scripts/city/city_law_facilities.gd")
const Models := preload("res://scripts/city/city_car_models.gd")

const MAX_CRUISERS := 2
## Cruisers wanted per wanted tier (index = tier).
const CRUISERS_BY_TIER := [0, 1, 1, 2]
const CREW_IDS := ["patrol_officer_cruiser_1", "patrol_officer_cruiser_2"]
const CREW_PREFIX := "patrol_officer_cruiser_"
const CREW_CAST := "cop_steve"
const OWNER_PREFIX := "law_cruiser_"
const BODY_SIZE := Vector3(2.12, 2.30, 4.70)
const CAR_LENGTH := 4.7
## Another car's centre within this distance of the path blocks it.
const CAR_CORRIDOR := 2.4
const SIGHT_MASK := 1 | 2 | 16
## Driver's eye and seat, car-local (+X is the driver's side).
const EYE_LOCAL := Vector3(0.38, 1.25, 0.25)
const SEAT_LOCAL := Vector3(0.38, 1.0, 0.15)
const DISPATCH_RADIUS := 480.0
const ROUTE_LIMIT := 1000.0
const SIGHT_RANGE := 55.0
const VIEW_DOT := -0.35
const NOTICE_RADIUS := 3.0
const RESPOND_SPEED := 12.0
const PURSUIT_SPEED := 14.0
const SEARCH_SPEED := 7.0
const DEPART_SPEED := 8.0
const JUNCTION_SPEED := 5.0
const BRAKE_PLAN := 5.0
const LATERAL_PLAN := 4.5
const STOP_GAP := 2.0
const PERSON_GAP := 3.5
const SENSE_INTERVAL := 0.1
const REPLAN_INTERVAL := 1.5
const GOAL_REPLAN_DISTANCE := 10.0
const STUCK_SECONDS := 1.8
const MAX_UNSTICK := 3
const BLOCKED_DISPATCH_COOLDOWN := 60.0
const UNSTICK_RESET_DISTANCE := 25.0
## Backing out retraces the car's own recent ground (or backs straight without one).
const REVERSE_SECONDS := 6.0
const REVERSE_DISTANCE := 7.0
const REVERSE_LIMIT := 18.0
## Backing all the way out of a street just turned into (a junction's length).
const BACK_OUT_SECONDS := 20.0
const BACK_OUT_LIMIT := 45.0
const TRAIL_SPACING := 1.0
const MAX_TRAIL := 40
## A wall or prop stopped in the lane ahead: wait this long, then avoid that street.
const STRUCTURE_WAIT := 1.5
const PASS_WAIT := 3.0
const PASS_OFFSET := 3.2
## Leave room for the six-metre lateral transition before a stationary car.
const PASS_START_GAP := 5.0
const BLOCK_GIVE_UP := 12.0
const YIELD_LIMIT := 5.0
const DISMOUNT_RANGE := 18.0
const CAR_DISMOUNT_RANGE := 14.0
const FOOT_RANGE := 70.0
const DIRECT_RANGE := 32.0
const ARRIVE_DISTANCE := 5.0
const SEARCH_EXTENSION := 80.0
const DEPART_DISTANCE := 70.0
const DEPART_SECONDS := 20.0
const HIDE_DISTANCE := 45.0
const REMOUNT_DISTANCE := 30.0
const MAX_EXIT_TRIES := 4
const MAX_HOMECOMINGS := 3

var law: Node
var level: Node
var traffic: Node
var lanes: Lanes
var available := false
var reason := "not set up"
## slot (1 or 2) -> unit Dictionary.
var units: Dictionary = {}
## One entry per crew identity: {id, actor, state: station|seated|foot|dead, slot, homecomings}.
var crew: Array[Dictionary] = []
var counters := {"dispatches": 0, "claims": 0, "claim_failures": 0, "releases": 0, "release_failures": 0,
	"routes": 0, "route_failures": 0, "los_rays": 0, "sightings": 0, "recognitions": 0, "witnessed": 0,
	"dismounts": 0, "dismount_failures": 0, "remounts": 0, "stand_downs": 0, "unsticks": 0, "passes": 0,
	"yields": 0, "abandoned": 0, "contacts": 0, "searches": 0, "departures": 0, "hidden": 0,
	"blocked_dispatches": 0}
var last_blocked_dispatch: Dictionary = {}
## Incident assistance (city_police_assistance.gd). A unit claimed through
## request_assist carries `assist` (the caller's tag): it never perceives,
## pursues or is radioed toward the player, and its dismounted officer is
## handed to this handler (on_assist_dismount) instead of law. Null = unused.
var assist_handler: Object = null
var assist_counters := {"requests": 0, "claims": 0, "refused": 0, "dismounts": 0, "remounts": 0, "door_failures": 0}
var _clock := 0.0
var _ticks := 0
var _plan_tick := -1
var _recognize_cursor := -1
var _crew_clock := 0.0
var _pending := Vector3.INF
## Law's last-known clock when a cruiser last searched it: the same spot is not
## responded to again (so the cooldown can run), only newer information is.
var _searched_lkp := -INF
var _failed_cars: Dictionary = {}
var _police_cache: Array = []
var _resetting := false
var _ray := PhysicsRayQueryParameters3D.new()
var _ground_ray := PhysicsRayQueryParameters3D.new()
var _cast_query: PhysicsShapeQueryParameters3D
var _hull_query: PhysicsShapeQueryParameters3D
var _slot_query: PhysicsShapeQueryParameters3D
var _sweep_query: PhysicsShapeQueryParameters3D

static func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

static func forward_of(car: Node3D) -> Vector3:
	var yaw: Variant = car.get("yaw")
	if yaw is float or yaw is int:
		return Vector3(sin(float(yaw)), 0.0, cos(float(yaw)))
	# Registered emergency bodies share reservations without a Vehicle script.
	var forward := car.global_basis.z
	forward.y = 0.0
	return forward.normalized() if forward.length_squared() > 0.0001 else Vector3.BACK

# --------------------------------------------------------------- setup

func setup(owner_law: Node, owner_level: Node) -> void:
	law = owner_law
	level = owner_level
	units.clear()
	lanes = Lanes.new()
	_ray.collision_mask = SIGHT_MASK
	_ray.hit_from_inside = false
	_ground_ray.collision_mask = 1 | 2
	_ground_ray.hit_back_faces = false
	traffic = level.get("traffic") if level != null else null
	available = false
	if traffic == null:
		reason = "no traffic"
		return
	lanes.setup(traffic.get("network"))
	# Identities exist whenever traffic does, so a saved death always validates.
	_build_crew()
	_police_cache = _scan_police()
	if not traffic.has_method("claim_external_vehicle") or not traffic.has_method("release_external_vehicle"):
		reason = "traffic has no external vehicle authority"
	elif lanes.lane_count() == 0:
		reason = "no lane network"
	elif crew.is_empty():
		reason = "no crew registry"
	elif _police_cache.is_empty():
		reason = "no police cars in traffic"
	else:
		available = true
		reason = ""
		Driver.configure(_police_cache[0])

func _build_crew() -> void:
	crew.clear()
	var npcs = level.get("npcs")
	if not npcs is Node or not npcs.get("actors") is Dictionary:
		return
	var actors: Dictionary = npcs.actors
	var station := _station_point()
	for id in CREW_IDS:
		var actor = actors.get(id)
		if not is_instance_valid(actor):
			actor = Actor.new()
			npcs.add_child(actor)
			actor.build(level, id, CREW_CAST, "Patrol officer")
			var appearance: Dictionary = Appearance.profile(id)
			actor.set_meta("population_appearance", appearance)
			if bool(appearance.get("apply_skin", false)) and appearance.has("skin"):
				var changed := Appearance.apply_patrol_skin(actor.puppet.g, Color(str(Cast.LOOKS[CREW_CAST].skin)), Color(str(appearance.skin)))
				actor.set_meta("appearance_skin_surfaces", changed)
			actor.global_position = station
			actor.yaw = 0.0
			actors[id] = actor
		actor.set_meta("police_crew", true)
		if actor.dead != true:
			actor.set_enabled(false)
		crew.append({"id": id, "actor": actor, "state": "dead" if actor.dead == true else "station", "slot": 0, "homecomings": 0})

func _station_point() -> Vector3:
	var info: Dictionary = Facilities.candidates(level, "police")
	var points: Array = info.get("points", [])
	if not points.is_empty():
		return points[0]
	var data = level.get("level_data")
	if data is Dictionary and (data as Dictionary).get("spawn", {}) is Dictionary:
		var spawn = data.spawn.get("position")
		if spawn is Array and spawn.size() >= 3:
			return Vector3(float(spawn[0]), float(spawn[1]), float(spawn[2]))
	return Vector3.ZERO

func _scan_police() -> Array:
	var result: Array = []
	var pool = traffic.get("vehicles") if traffic != null else null
	if pool is Array:
		for car in pool:
			if is_instance_valid(car) and car.get("is_police") == true:
				result.append(car)
	return result

func _police_cars() -> Array:
	for car in _police_cache:
		if not is_instance_valid(car):
			_police_cache = _scan_police()
			break
	return _police_cache

# --------------------------------------------------------------- queries

func is_crew(actor) -> bool:
	return is_instance_valid(actor) and str(actor.get("actor_id")).begins_with(CREW_PREFIX)

func is_police_vehicle_id(id: String) -> bool:
	if id.is_empty():
		return false
	for car in _police_cars():
		if is_instance_valid(car) and str(car.get("vehicle_id")) == id:
			return true
	return false

func claimed_count() -> int:
	return units.size()

## Units that count as responders for the law phase (dismounted crews are
## counted by law itself as foot responders).
func summary() -> Dictionary:
	var active := 0
	var en_route := 0
	for unit in units.values():
		var mode := str(unit.mode)
		if _is_assist(unit):
			continue # Incident cars are not part of the player's response phase.
		if mode in ["respond", "pursue", "search", "hold"]:
			active += 1
			en_route += int(mode == "respond")
	return {"active": active, "en_route": en_route}

func crew_door(actor) -> Vector3:
	var entry := _crew_entry(actor)
	var unit: Dictionary = units.get(int(entry.get("slot", 0)), {})
	if not unit.is_empty() and Vector3(unit.get("door", Vector3.INF)).is_finite():
		return unit.door
	return actor.global_position if is_instance_valid(actor) else Vector3.INF

## A crew officer on foot whose suspect was last seen driving away goes back to
## the cruiser rather than searching yards on foot.
func crew_should_remount(actor) -> bool:
	var entry := _crew_entry(actor)
	var unit: Dictionary = units.get(int(entry.get("slot", 0)), {})
	if unit.is_empty() or str(unit.mode) != "dismounted" or not _car_usable(unit.car):
		return false
	var known: Vector3 = law.last_known_position
	return known.is_finite() and flat(known, actor.global_position) > REMOUNT_DISTANCE

func _crew_entry(actor) -> Dictionary:
	for entry in crew:
		if entry.actor == actor:
			return entry
	return {}

func _crew_of(unit: Dictionary) -> Dictionary:
	var index := int(unit.get("crew", -1))
	return crew[index] if index >= 0 and index < crew.size() else {}

func _free_crew() -> int:
	for index in crew.size():
		var entry: Dictionary = crew[index]
		var actor = entry.actor
		if str(entry.state) == "station" and is_instance_valid(actor) and actor.dead != true and not _combat_dead(str(entry.id)):
			return index
	return -1

func _free_slot() -> int:
	for slot in range(1, MAX_CRUISERS + 1):
		if not units.has(slot):
			return slot
	return -1

func _unit_of(car) -> Dictionary:
	for unit in units.values():
		if unit.car == car:
			return unit
	return {}

func _combat_dead(id: String) -> bool:
	var combat = level.get("combat") if level != null else null
	return combat != null and combat.has_method("is_actor_dead") and bool(combat.is_actor_dead(id))

func _car_disabled(car) -> bool:
	if not is_instance_valid(car):
		return true
	if car.get("disabled") == true:
		return true
	if car.has_method("is_disabled") and bool(car.is_disabled()):
		return true
	return false

func _car_usable(car) -> bool:
	return is_instance_valid(car) and car.is_inside_tree() and not _car_disabled(car)

func _eligible(car) -> bool:
	if not _car_usable(car) or car.get("is_police") != true or car.get("player_controlled") == true:
		return false
	if not str(car.get("external_owner")).is_empty() or not car.has_method("external_step"):
		return false
	var flats = car.get("flat_tires")
	if flats is Array and (flats as Array).size() >= 2:
		return false
	return float(_failed_cars.get(str(car.get("vehicle_id")), -INF)) <= _clock

func _space() -> PhysicsDirectSpaceState3D:
	if level is Node3D and (level as Node3D).is_inside_tree():
		var world := (level as Node3D).get_world_3d()
		if world != null:
			return world.direct_space_state
	return null

func _can_plan() -> bool:
	return _plan_tick != _ticks

# --------------------------------------------------------------- law hooks

## A filed report (identified offender) or a raised tier: remember where.
func request(goal: Vector3, _tier: int, _source := "") -> void:
	if not goal.is_finite():
		return
	_pending = goal
	for unit in units.values():
		if not _is_assist(unit):
			_inform(unit, goal)

## Another officer saw the suspect: units without their own sight head there.
func radio(goal: Vector3) -> void:
	for unit in units.values():
		if not bool(unit.seen) and not _is_assist(unit):
			_inform(unit, goal)

# --------------------------------------------------------------- incident assistance

static func _is_assist(unit: Dictionary) -> bool:
	return not str(unit.get("assist", "")).is_empty()

## Claims the best free police car (same eligibility, mobility preference and
## route-before-claim rule as law's dispatch) to drive to `goal` for incident
## `tag`. On arrival the crew dismounts through the normal capsule-checked door
## and is handed to assist_handler.on_assist_dismount(actor, tag, door).
## Returns {ok, slot, vehicle_id, distance, crew} or {ok: false, reason}.
func request_assist(goal: Vector3, tag: String) -> Dictionary:
	assist_counters.requests = int(assist_counters.requests) + 1
	var why := ""
	if not available:
		why = reason if not reason.is_empty() else "cruisers unavailable"
	elif tag.is_empty() or not goal.is_finite():
		why = "invalid request"
	elif law != null and bool(law.get("recovering")):
		why = "law recovery in progress"
	elif units.size() >= MAX_CRUISERS:
		why = "no free cruiser"
	elif _free_crew() < 0:
		why = "no free crew"
	elif not _can_plan():
		why = "route budget"
	if not why.is_empty():
		assist_counters.refused = int(assist_counters.refused) + 1
		return {"ok": false, "reason": why}
	var best: Node3D = null
	var best_distance := DISPATCH_RADIUS
	var best_mobile := false
	for car in _police_cars():
		if not _eligible(car):
			continue
		var distance := flat(car.global_position, goal)
		if distance >= DISPATCH_RADIUS:
			continue
		var mobile := _dispatch_mobile(car)
		if best == null or (mobile and not best_mobile) or (mobile == best_mobile and distance < best_distance):
			best_distance = distance
			best_mobile = mobile
			best = car
	if best == null:
		assist_counters.refused = int(assist_counters.refused) + 1
		return {"ok": false, "reason": "no police car within range"}
	var unit := _claim(best, _free_crew(), goal, "respond")
	if unit.is_empty():
		assist_counters.refused = int(assist_counters.refused) + 1
		return {"ok": false, "reason": "no lane route or claim refused"}
	unit.assist = tag
	assist_counters.claims = int(assist_counters.claims) + 1
	return {"ok": true, "slot": int(unit.slot), "vehicle_id": str(unit.vehicle_id), "distance": best_distance,
		"crew": str(_crew_of(unit).get("id", ""))}

## Read-only progress of an assist unit; {} once the claim is gone.
func assist_status(slot: int, tag: String) -> Dictionary:
	var unit: Dictionary = units.get(slot, {})
	if unit.is_empty() or str(unit.get("assist", "")) != tag:
		return {}
	var car = unit.car
	return {"mode": str(unit.mode), "vehicle_id": str(unit.vehicle_id), "hold_reason": str(unit.hold_reason),
		"position": car.global_position if is_instance_valid(car) else Vector3.INF,
		"remaining": float(unit.remaining), "door": unit.door, "crew_state": str(_crew_of(unit).get("state", "")),
		"abandon_reason": str(unit.get("abandon_reason", ""))}

## The incident no longer needs this car. A seated crew drives off before the
## claim is released; a dismounted officer is returned by the handler.
func cancel_assist(slot: int, tag: String) -> void:
	var unit: Dictionary = units.get(slot, {})
	if unit.is_empty() or str(unit.get("assist", "")) != tag:
		return
	if str(unit.mode) in ["respond", "pursue", "search", "hold"]:
		_assist_depart(unit)

func _assist_depart(unit: Dictionary) -> void:
	unit.frozen = false
	_begin_depart(unit)

## The handler walked its officer back to the car door: re-seat and drive off.
## False (no change) when not beside a usable assist car.
func assist_remount(actor) -> bool:
	var entry := _crew_entry(actor)
	if entry.is_empty() or str(entry.state) != "foot" or not is_instance_valid(actor) or actor.dead == true or actor.get("combat_override") == true:
		return false
	var unit: Dictionary = units.get(int(entry.slot), {})
	if unit.is_empty() or not _is_assist(unit) or str(unit.mode) != "dismounted" or not _car_usable(unit.car):
		return false
	var door: Vector3 = unit.get("door", unit.car.global_position)
	if flat(actor.global_position, door) > 2.5 and flat(actor.global_position, unit.car.global_position) > 3.6:
		return false
	_hide(entry, unit)
	counters.remounts = int(counters.remounts) + 1
	assist_counters.remounts = int(assist_counters.remounts) + 1
	entry.homecomings = 0
	_assist_depart(unit)
	return true

## Recovery started: every cruiser stops where it is and waits.
func hold_all() -> void:
	for unit in units.values():
		unit.frozen = true

## The incident ended. Immediately (recovery relocation behind a full fade, or
## reset) every crew is re-seated and every claim released; otherwise crews walk
## back, re-enter and drive off before their cars are released.
func stand_down(immediate: bool) -> void:
	counters.stand_downs = int(counters.stand_downs) + 1
	_pending = Vector3.INF
	_searched_lkp = -INF
	for slot in units.keys().duplicate():
		if not units.has(slot):
			continue
		var unit: Dictionary = units[slot]
		if immediate:
			_release_unit(unit)
			continue
		unit.frozen = false
		if _is_assist(unit):
			continue # The player's incident ending does not end a neighbor's call.
		if str(unit.mode) in ["respond", "pursue", "search", "hold"]:
			_begin_depart(unit)
	if immediate:
		for entry in crew:
			if str(entry.state) == "foot":
				_recall(entry)

func reset() -> void:
	_resetting = true
	stand_down(true)
	for entry in crew:
		if str(entry.state) == "foot":
			var actor = entry.actor
			if is_instance_valid(actor) and actor.get("combat_override") == true and actor.dead != true:
				law._disengage(actor)
			_recall(entry)
	_failed_cars.clear()
	_resetting = false

## Bystander/police witness candidates for law's bounded offense scan: crewed
## cruisers, and unclaimed police cars only while a crew and slot are free.
func witness_entries(center: Vector3, radius: float, victims: Array, eye_height: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not available:
		return result
	var claimable := units.size() < MAX_CRUISERS and _free_crew() >= 0
	for car in _police_cars():
		if not is_instance_valid(car):
			continue
		var distance := flat(car.global_position, center)
		if distance > radius:
			continue
		var unit := _unit_of(car)
		var crewed := not unit.is_empty() and str(_crew_of(unit).get("state", "")) == "seated"
		if not crewed and not (unit.is_empty() and claimable and _eligible(car)):
			continue
		var eye: Vector3 = car.global_transform * EYE_LOCAL
		result.append({"id": "cruiser:" + str(car.get("vehicle_id")), "node": null, "vehicle": car, "rid": car.get_rid(),
			"position": eye - Vector3.UP * eye_height, "yaw": float(car.get("yaw")), "police": true,
			"distance": distance, "victim": victims.has(str(car.get("vehicle_id")))})
	return result

## A cruiser crew watched the offense happen: that car pursues the offender.
func on_witness(car, offender: Vector3) -> void:
	counters.witnessed = int(counters.witnessed) + 1
	var unit := _unit_of(car)
	if not unit.is_empty():
		if not _is_assist(unit):
			_sighted(unit, offender)
		return
	var index := _free_crew()
	if index >= 0 and units.size() < MAX_CRUISERS and _eligible(car):
		var claimed := _claim(car, index, offender, "pursue")
		if not claimed.is_empty():
			_sighted(claimed, offender)

## Law finished a crew officer's walk back (return mode). True when re-seated.
func crew_arrived(actor, _state: Dictionary) -> bool:
	var entry := _crew_entry(actor)
	if entry.is_empty():
		return false
	if _resetting:
		_hide(entry, {})
		return true
	var unit: Dictionary = units.get(int(entry.slot), {})
	if unit.is_empty() or not _car_usable(unit.car) or not is_instance_valid(actor) or actor.dead == true or actor.get("combat_override") == true:
		return false
	var door: Vector3 = unit.get("door", unit.car.global_position)
	if flat(actor.global_position, door) > 2.5 and flat(actor.global_position, unit.car.global_position) > 3.6:
		return false
	_hide(entry, unit)
	counters.remounts = int(counters.remounts) + 1
	entry.homecomings = 0
	unit.frozen = false
	var newer: bool = float(law.last_known_clock()) > float(unit.get("dismount_clock", INF)) + 0.5
	if not _is_assist(unit) and int(law.wanted) > 0 and not bool(law.recovering) and law.last_known_position.is_finite() and newer:
		unit.mode = "respond"
		unit.goal = law.last_known_position
		unit.want_plan = true
		_set_emergency(unit, true)
	else:
		_begin_depart(unit)
	return true

## Law dropped a crew responder whose body became unusable.
func crew_lost(actor) -> void:
	var entry := _crew_entry(actor)
	if entry.is_empty():
		return
	if is_instance_valid(actor) and actor.dead != true and not _combat_dead(str(entry.id)):
		return # Hidden by a re-seat, not lost.
	entry.state = "dead"
	var unit: Dictionary = units.get(int(entry.slot), {})
	if not unit.is_empty() and int(unit.get("crew", -1)) == crew.find(entry):
		_abandon(unit, "crew lost")

# --------------------------------------------------------------- perception (4 Hz)

func perceive(_elapsed: float) -> void:
	if crew.is_empty():
		return
	_sync_seated()
	if not available:
		return
	for slot in units.keys().duplicate():
		if units.has(slot):
			_unit_perceive(units[slot])
	if int(law.wanted) > 0 and not bool(law.recovering):
		_recognize()
		_update_dispatch()

func _sync_seated() -> void:
	for entry in crew:
		if str(entry.state) != "seated":
			continue
		var unit: Dictionary = units.get(int(entry.slot), {})
		var actor = entry.actor
		if not unit.is_empty() and is_instance_valid(unit.car) and is_instance_valid(actor):
			actor.global_position = unit.car.global_transform * SEAT_LOCAL

func _unit_perceive(unit: Dictionary) -> void:
	var entry := _crew_of(unit)
	var mode := str(unit.mode)
	# An assist unit answers a neighbor's call: it never looks for the player.
	if _is_assist(unit) or entry.is_empty() or str(entry.state) != "seated" or bool(unit.frozen) or int(law.wanted) <= 0 or mode in ["depart", "abandoned", "dismounted"]:
		unit.seen = false
		unit.had_sight = false
		return
	var car: Node3D = unit.car
	var sees := _crew_sees(car)
	unit.seen = sees
	if sees:
		if not bool(unit.had_sight):
			counters.sightings = int(counters.sightings) + 1
		var feet: Vector3 = law._player_feet()
		law._observe_player(feet)
		_sighted(unit, feet)
	unit.had_sight = sees
	if not sees and str(unit.mode) == "pursue" and _clock - float(unit.seen_clock) >= float(law.lost_sight_seconds):
		# Out of sight: drive to where they were last seen, nothing newer.
		unit.mode = "respond"
		_inform(unit, law.last_known_position)
	_maybe_dismount(unit)

## Facing plus one ray from the driver's eye; own car excluded, buildings,
## terrain and other cars occlude (law's seated-occupant endpoint rule).
func _crew_sees(car: Node3D) -> bool:
	return _crew_can_look(car) and _crew_ray(car)

## Range and the crew's field of view through the windshield and side windows.
func _crew_can_look(car: Node3D) -> bool:
	var feet: Vector3 = law._player_feet()
	if not feet.is_finite():
		return false
	var eye: Vector3 = car.global_transform * EYE_LOCAL
	var offset := Vector3(feet.x - eye.x, 0.0, feet.z - eye.z)
	var distance := offset.length()
	if distance > SIGHT_RANGE:
		return false
	return distance <= NOTICE_RADIUS or forward_of(car).dot(offset / maxf(distance, 0.001)) >= VIEW_DOT

func _crew_ray(car: Node3D) -> bool:
	counters.los_rays = int(counters.los_rays) + 1
	return bool(law._sees_player(car.global_transform * EYE_LOCAL, car.get_rid()))

func _sighted(unit: Dictionary, goal: Vector3) -> void:
	unit.seen = true
	unit.seen_clock = _clock
	unit.goal = goal
	unit.target_seated = law._vehicle_body() != null
	if str(unit.mode) in ["respond", "search", "depart", "pursue"]:
		if str(unit.mode) != "pursue":
			_set_emergency(unit, true)
		unit.mode = "pursue"
	if str(unit.mode) == "pursue":
		if not _direct_path(unit, goal) and _needs_replan(unit, goal):
			_replan(unit, goal)
	# Only real crew sightings and witnessed offenses reach here: share the fix
	# with units that cannot see (radio never reads the player's position).
	radio(goal)

func _inform(unit: Dictionary, goal: Vector3) -> void:
	if not goal.is_finite() or str(unit.mode) in ["abandoned", "hold", "dismounted"]:
		return
	if str(unit.mode) in ["depart", "search"] and not _news():
		return # Already searched there; only newer information turns it back.
	if str(unit.mode) == "depart":
		if int(law.wanted) <= 0:
			return
		_set_emergency(unit, true)
	if str(unit.mode) == "pursue" and bool(unit.seen):
		return # Its own eyes are newer than any radio call.
	if str(unit.mode) in ["depart", "search"]:
		unit.mode = "respond"
		unit.release_pending = false
	unit.goal = goal
	if _needs_replan(unit, goal):
		_replan(unit, goal)

## Whether law knows something newer than the last spot a cruiser searched.
func _news() -> bool:
	return float(law.last_known_clock()) > _searched_lkp + 0.5

func _mark_searched() -> void:
	if law != null:
		_searched_lkp = maxf(_searched_lkp, float(law.last_known_clock()))

func _needs_replan(unit: Dictionary, goal: Vector3) -> bool:
	if bool(unit.want_plan) or str(unit.path_kind) == "direct" or str(unit.path_kind) == "continuation":
		return _clock - float(unit.plan_clock) >= 0.5
	return flat(Vector3(unit.planned_goal), goal) > GOAL_REPLAN_DISTANCE and _clock - float(unit.plan_clock) >= REPLAN_INTERVAL

func _maybe_dismount(unit: Dictionary) -> void:
	# After two blocked exits here the crew stays in and keeps watching instead.
	if str(unit.mode) != "pursue" or not bool(unit.seen) or int(unit.get("hold_failures", 0)) >= 2:
		return
	var feet: Vector3 = law._player_feet()
	var distance := flat(unit.car.global_position, feet)
	var vehicle = law._vehicle_body()
	if vehicle == null:
		if distance <= DISMOUNT_RANGE:
			_begin_hold(unit, "engage")
	elif distance <= CAR_DISMOUNT_RANGE and absf(float(vehicle.get("speed"))) <= 2.0:
		_begin_hold(unit, "engage")

## An unclaimed police car on its beat recognises a wanted player by its own
## crew's sight: one ray per perception tick, only while a slot and crew are free.
func _recognize() -> void:
	if units.size() >= MAX_CRUISERS or _free_crew() < 0 or not _can_plan():
		return
	var cars := _police_cars()
	if cars.is_empty():
		return
	for attempt in cars.size():
		_recognize_cursor = (_recognize_cursor + 1) % cars.size()
		var car = cars[_recognize_cursor]
		if not _eligible(car) or not _crew_can_look(car):
			continue
		if not _crew_ray(car):
			return
		var feet: Vector3 = law._player_feet()
		law._observe_player(feet)
		counters.recognitions = int(counters.recognitions) + 1
		var unit := _claim(car, _free_crew(), feet, "pursue")
		if not unit.is_empty():
			_sighted(unit, feet)
		return

func _update_dispatch() -> void:
	var tier := clampi(int(law.wanted), 0, CRUISERS_BY_TIER.size() - 1)
	var desired := mini(MAX_CRUISERS, int(CRUISERS_BY_TIER[tier]))
	var engaged := 0
	for unit in units.values():
		engaged += int(not str(unit.mode) in ["depart", "abandoned"] and not _is_assist(unit))
	if engaged >= desired or units.size() >= MAX_CRUISERS or not _can_plan() or not _news():
		return
	var goal: Vector3 = law.last_known_position
	if not goal.is_finite():
		goal = _pending
	if not goal.is_finite():
		return
	# A departing unit turns back before a fresh car is claimed.
	for unit in units.values():
		if str(unit.mode) == "depart" and not _is_assist(unit):
			_inform(unit, goal)
			return
	var index := _free_crew()
	if index < 0:
		return
	var best: Node3D = null
	var best_distance := DISPATCH_RADIUS
	var best_mobile := false
	for car in _police_cars():
		if not _eligible(car):
			continue
		var distance := flat(car.global_position, goal)
		if distance >= DISPATCH_RADIUS:
			continue
		var mobile := _dispatch_mobile(car)
		# A slightly nearer car boxed into a civilian queue cannot begin the
		# response. Prefer an already moving or clear-headed car within radius;
		# retain the nearest queued option when none has current mobility.
		if best == null or (mobile and not best_mobile) or (mobile == best_mobile and distance < best_distance):
			best_distance = distance
			best_mobile = mobile
			best = car
	if best != null:
		_claim(best, index, goal, "respond")

func _dispatch_mobile(car: Node3D) -> bool:
	if absf(float(car.get("speed"))) >= 0.5:
		return true
	if car.get("_presence_blocked") == true:
		return false
	# Existing traffic snapshots include its following buffer. Requiring the
	# pass allowance here is conservative; this is priority, never permission
	# to bypass the cruiser's ordinary sensing, junction or collision checks.
	if float(car.get("leader_distance")) < PASS_START_GAP:
		return false
	return car.get("near_physics") != true or float(car.get("_obstacle_distance")) >= PASS_START_GAP

# --------------------------------------------------------------- claim and release

func _claim(car: Node3D, crew_index: int, goal: Vector3, mode: String) -> Dictionary:
	var slot := _free_slot()
	if slot < 0 or crew_index < 0 or not _can_plan():
		return {}
	var owner := OWNER_PREFIX + str(slot)
	# Traffic would refuse this car (e.g. its culled hull overlaps something):
	# skip it for a while instead of spending a route plan on it every tick.
	if traffic.has_method("can_claim_external") and not str(traffic.can_claim_external(car, owner)).is_empty():
		counters.claim_failures = int(counters.claim_failures) + 1
		_failed_cars[str(car.get("vehicle_id"))] = _clock + 8.0
		return {}
	# Plan before taking authority: an unreachable goal never stops a car in traffic.
	var start := _start_from_ai(car)
	var plan := _route(car, goal, start)
	if not bool(plan.ok):
		_failed_cars[str(car.get("vehicle_id"))] = _clock + 8.0
		return {}
	if not bool(traffic.claim_external_vehicle(car, owner)) or str(car.get("external_owner")) != owner:
		counters.claim_failures = int(counters.claim_failures) + 1
		_failed_cars[str(car.get("vehicle_id"))] = _clock + 8.0
		return {}
	counters.claims = int(counters.claims) + 1
	counters.dispatches = int(counters.dispatches) + 1
	var unit := {"slot": slot, "owner": owner, "car": car, "vehicle_id": str(car.get("vehicle_id")), "crew": crew_index,
		"mode": mode, "emergency": true, "frozen": false, "goal": goal, "planned_goal": goal, "plan_clock": -INF,
		"path": PackedVector3Array(), "sums": PackedFloat64Array(), "limits": PackedFloat32Array(), "length": 0.0,
		"segments": [], "junctions": [], "path_kind": "lanes", "cursor": 0, "s": 0.0, "lateral": 0.0, "remaining": INF,
		"end_gap": 0.0, "replans": 0, "plan_failures": 0, "want_plan": false, "sense_left": 0.0,
		"obstacle": INF, "obstacle_s": INF, "obstacle_kind": "", "obstacle_speed": 0.0, "junction": {}, "cleared": {},
		"yielding": false, "yield_time": 0.0, "blocked_time": 0.0, "pass_tried": false,
		"stuck": 0.0, "unstick": 0, "unstick_odometer": 0.0, "odometer": 0.0, "reverse_left": 0.0, "reverse_steer": 0.0,
		"reverse_moved": 0.0, "reverse_to_s": -INF, "trail": PackedVector3Array([car.global_position]), "structure_time": 0.0,
		"last_steer": 0.0, "seen": false, "had_sight": false, "seen_clock": -INF, "target_seated": false,
		"search_until": -INF, "depart_until": INF, "depart_odometer": 0.0, "release_pending": false,
		"hold_reason": "", "hold_time": 0.0, "exit_tries": 0, "next_exit_try": 0.0, "door": Vector3.INF,
		"dismount_clock": INF, "claimed_at": _clock, "contacts": 0, "last_contact": {}, "respond_until": INF}
	units[slot] = unit
	_seat(crew_index, unit)
	_apply_path(unit, plan)
	_set_emergency(unit, true)
	return unit

## The AI route the car was following, read before authority changes it: on its
## lane, or (inside a junction) the rest of its own connector as a lead.
func _start_from_ai(car: Node3D) -> Dictionary:
	var lane := int(car.get("lane_id")) if car.get("lane_id") != null else -1
	if not lanes.has_lane(lane):
		return {}
	var at: Vector3 = car.global_position
	var hit := lanes.project(lane, at)
	if float(hit.distance) <= 1.6:
		return {"lane": lane, "along": float(hit.along), "lead": PackedVector3Array()}
	var route = car.get("route")
	if not route is Array:
		return {}
	var lane_start: Vector3 = lanes.lane_points(lane)[0]
	var lead := PackedVector3Array([at])
	var index := clampi(int(car.get("route_index")), 0, (route as Array).size())
	for i in range(index, (route as Array).size()):
		var point: Vector3 = route[i]
		lead.append(point)
		if flat(point, lane_start) <= 0.6 or lead.size() > 256:
			break
	if flat(lead[-1], lane_start) > 0.6:
		return {}
	return {"lane": lane, "along": 0.0, "lead": lead}

func _route(car: Node3D, goal: Vector3, start: Dictionary) -> Dictionary:
	if not _can_plan():
		return {"ok": false, "reason": "route budget"}
	_plan_tick = _ticks
	counters.routes = int(counters.routes) + 1
	var plan: Dictionary
	if start.is_empty():
		plan = lanes.plan(car.global_position, forward_of(car), goal, -1, -1.0, PackedVector3Array(), ROUTE_LIMIT, _clock)
	else:
		plan = lanes.plan(car.global_position, forward_of(car), goal, int(start.lane), float(start.along), start.lead, ROUTE_LIMIT, _clock)
	if not bool(plan.ok):
		counters.route_failures = int(counters.route_failures) + 1
	return plan

func _replan(unit: Dictionary, goal: Vector3) -> bool:
	var plan := _route(unit.car, goal, _start_from_path(unit))
	if str(plan.get("reason", "")) == "route budget":
		unit.want_plan = true
		return false
	unit.want_plan = false
	unit.plan_clock = _clock
	if not bool(plan.ok):
		unit.plan_failures = int(unit.plan_failures) + 1
		return false
	_apply_path(unit, plan)
	unit.planned_goal = goal
	unit.replans = int(unit.replans) + 1
	return true

## Resume on whatever lane the car is driving now (or finish its connector).
func _start_from_path(unit: Dictionary) -> Dictionary:
	var segments: Array = unit.segments
	if segments.is_empty() or str(unit.path_kind) == "direct":
		return {}
	var s := float(unit.s)
	var current := -1
	for i in segments.size():
		if float(segments[i].s) <= s + 0.01:
			current = i
	if current < 0:
		return {}
	var segment: Dictionary = segments[current]
	if str(segment.kind) == "lane":
		var along := float(segment.along) + s - float(segment.s)
		if lanes.has_lane(int(segment.lane)) and not lanes.is_blocked(int(segment.lane)) and along <= lanes.lane_length(int(segment.lane)) + 0.5:
			return {"lane": int(segment.lane), "along": minf(along, lanes.lane_length(int(segment.lane))), "lead": PackedVector3Array()}
		return {}
	var end_s := float(unit.length)
	var lane := int(segment.lane)
	var along := 0.0
	if current + 1 < segments.size():
		end_s = float(segments[current + 1].s)
		if str(segments[current + 1].kind) == "lane":
			lane = int(segments[current + 1].lane)
			along = float(segments[current + 1].along)
	if not lanes.has_lane(lane) or lanes.is_blocked(lane):
		# Never start a plan on the street just found blocked.
		return {}
	var path: PackedVector3Array = unit.path
	var sums: PackedFloat64Array = unit.sums
	var lead := PackedVector3Array([unit.car.global_position])
	for i in path.size():
		if sums[i] > s + 0.5 and sums[i] <= end_s + 0.01:
			lead.append(path[i])
	return {"lane": lane, "along": along, "lead": lead}

func _apply_path(unit: Dictionary, plan: Dictionary) -> void:
	var points: PackedVector3Array = plan.points
	unit.path = points
	unit.sums = plan.get("sums", Lanes.cumulative(points))
	unit.length = float(plan.get("length", (unit.sums as PackedFloat64Array)[-1] if not points.is_empty() else 0.0))
	unit.segments = plan.get("segments", [])
	unit.junctions = plan.get("junctions", [])
	unit.limits = Driver.curve_limits(points, LATERAL_PLAN, PURSUIT_SPEED)
	unit.path_kind = str(plan.get("kind", "lanes"))
	unit.end_gap = float(plan.get("end_gap", 0.0))
	unit.cursor = 0
	unit.s = 0.0
	unit.remaining = float(unit.length)
	unit.plan_clock = _clock
	unit.planned_goal = unit.goal
	# A response that cannot arrive in reasonable time is given up (bounded).
	unit.respond_until = _clock + float(unit.length) / 5.0 + 30.0
	unit.cleared = {}
	unit.junction = {}
	unit.yielding = false
	unit.yield_time = 0.0
	unit.want_plan = false
	# Path distances restart: sense the new path at once.
	unit.obstacle = INF
	unit.obstacle_s = INF
	unit.sense_left = 0.0

## Close and on the carriageway: drive straight at the sighting, wheels on the
## road for the whole footprint, never across a curb.
func _direct_path(unit: Dictionary, goal: Vector3) -> bool:
	var car: Node3D = unit.car
	var from: Vector3 = car.global_position
	var offset := Vector3(goal.x - from.x, 0.0, goal.z - from.z)
	var distance := offset.length()
	if distance > DIRECT_RANGE or distance < 3.0 or not lanes.on_road(goal, 0.6):
		return false
	var direction := offset / distance
	if direction.dot(forward_of(car)) < 0.5:
		return false
	# Never shortcut across a junction (that would drop its yield and speed
	# rules): both poses, with bumper room, must lie on the lane being driven.
	var lane := _current_lane(unit)
	if not lanes.has_lane(lane):
		return false
	var start := lanes.project(lane, from)
	var finish := lanes.project(lane, goal)
	if float(start.distance) > 1.6 or float(finish.distance) > 1.6:
		return false
	if float(start.along) < CAR_LENGTH * 0.5 or float(finish.along) > lanes.lane_length(lane) - CAR_LENGTH * 0.5:
		return false
	if float(finish.along) < float(start.along) + 3.0:
		return false
	var side := Vector3(direction.z, 0.0, -direction.x)
	var raw := PackedVector3Array([from, goal])
	var points := Lanes.resample(raw, Lanes.SPACING)
	for i in range(0, points.size(), 2):
		var point := points[i]
		for corner in [side * 1.1 + direction * 2.4, -side * 1.1 + direction * 2.4, side * 1.1 - direction * 2.4, -side * 1.1 - direction * 2.4]:
			if not lanes.on_road(point + corner, 0.15):
				return false
	var sums := Lanes.cumulative(points)
	_apply_path(unit, {"points": points, "sums": sums, "length": sums[-1],
		"segments": [{"kind": "lane", "s": 0.0, "lane": lane, "along": float(start.along)}],
		"junctions": [], "kind": "direct", "end_gap": 0.0})
	return true

func _seat(index: int, unit: Dictionary) -> void:
	var entry: Dictionary = crew[index]
	entry.state = "seated"
	entry.slot = int(unit.slot)
	unit.crew = index
	var actor = entry.actor
	if is_instance_valid(actor):
		actor.set_enabled(false)
		actor.global_position = unit.car.global_transform * SEAT_LOCAL

func _hide(entry: Dictionary, unit: Dictionary) -> void:
	var actor = entry.actor
	if is_instance_valid(actor) and actor.dead != true:
		actor.set_enabled(false)
		actor.velocity = Vector3.ZERO
	if unit.is_empty():
		entry.state = "station"
		entry.slot = 0
		counters.hidden = int(counters.hidden) + 1
	else:
		entry.state = "seated"
		entry.slot = int(unit.slot)
		unit.crew = crew.find(entry)
		if is_instance_valid(actor) and is_instance_valid(unit.car):
			actor.global_position = unit.car.global_transform * SEAT_LOCAL

## An on-foot crew officer leaves the response at once (reset or relocation
## behind the recovery fade). Combat's own holds (a downed officer) are kept;
## that body hides later, once nobody can see it.
func _recall(entry: Dictionary) -> void:
	var actor = entry.actor
	if not is_instance_valid(actor) or actor.dead == true:
		entry.state = "dead"
		return
	if actor.get("combat_override") == true:
		return
	law._drop_crew(actor)
	_hide(entry, {})

func _set_emergency(unit: Dictionary, on: bool) -> void:
	unit.emergency = on
	var car = unit.car
	if is_instance_valid(car):
		car.set_meta("police_unit", str(unit.owner))
		car.set_meta("police_emergency", on)
		if not on:
			_response_audio(car, false)

func _response_audio(car: Node3D, responding: bool) -> void:
	var audio := level.get_node_or_null("CityWorldAudio") if is_instance_valid(level) else null
	if audio == null:
		return
	if responding and audio.has_method("emergency"):
		audio.emergency(car)
	elif audio.has_method("stop_emergency"):
		audio.stop_emergency(car)

func _release_unit(unit: Dictionary) -> void:
	units.erase(int(unit.slot))
	var entry := _crew_of(unit)
	if not entry.is_empty() and str(entry.state) == "seated":
		# The officer stays with the car it returns to traffic.
		entry.state = "station"
	if not entry.is_empty():
		# Dead/on-foot entries cannot retain a slot another crew may reuse.
		entry.slot = 0
	var car = unit.car
	if not is_instance_valid(car):
		return
	_response_audio(car, false)
	if car.has_meta("police_emergency"):
		car.remove_meta("police_emergency")
	if car.has_meta("police_unit"):
		car.remove_meta("police_unit")
	if str(car.get("external_owner")) == str(unit.owner):
		if bool(traffic.release_external_vehicle(car, str(unit.owner))):
			counters.releases = int(counters.releases) + 1
		else:
			counters.release_failures = int(counters.release_failures) + 1

func _abandon(unit: Dictionary, why: String) -> void:
	if str(unit.mode) == "abandoned":
		return
	unit.mode = "abandoned"
	unit.abandon_reason = why
	counters.abandoned = int(counters.abandoned) + 1
	_set_emergency(unit, false)
	var entry := _crew_of(unit)
	if not entry.is_empty() and str(entry.state) == "seated":
		entry.state = "station"
		entry.slot = 0

# --------------------------------------------------------------- per tick

func tick(delta: float) -> void:
	_ticks += 1
	_clock += delta
	if crew.is_empty():
		return
	for slot in units.keys().duplicate():
		if units.has(slot):
			_tick_unit(units[slot], delta)
	_crew_clock -= delta
	if _crew_clock <= 0.0:
		_crew_clock = 1.0
		_tick_crew()

func _tick_unit(unit: Dictionary, delta: float) -> void:
	var car = unit.car
	if not is_instance_valid(car) or not car.is_inside_tree() or str(car.get("external_owner")) != str(unit.owner):
		# Authority is gone (the car was removed or reclaimed): nothing left to move.
		if is_instance_valid(car):
			_response_audio(car, false)
		var entry := _crew_of(unit)
		if not entry.is_empty() and str(entry.state) == "seated":
			entry.state = "station"
			entry.slot = 0
		units.erase(int(unit.slot))
		return
	var entry := _crew_of(unit)
	var actor = entry.get("actor")
	var dead: bool = entry.is_empty() or not is_instance_valid(actor) or actor.dead == true or _combat_dead(str(entry.get("id", "")))
	if dead and not entry.is_empty():
		entry.state = "dead"
	var mode := str(unit.mode)
	if dead and mode != "abandoned":
		_abandon(unit, "crew lost")
	elif _car_disabled(car) and not mode in ["abandoned", "dismounted", "hold"]:
		if str(entry.get("state", "")) == "seated":
			_begin_hold(unit, "disabled")
		else:
			_abandon(unit, "disabled")
	match str(unit.mode):
		"hold":
			_tick_hold(unit, delta)
		"dismounted", "abandoned":
			_tick_parked(unit, delta)
		_:
			_tick_drive(unit, delta)
	_response_audio(car, bool(unit.emergency) and str(unit.mode) in ["respond", "pursue", "assist"])

func _step(car: Node3D, delta: float, controls: Dictionary) -> Dictionary:
	var result = car.external_step(delta, float(controls.get("throttle", 0.0)), float(controls.get("brake", 0.0)),
		float(controls.get("steer", 0.0)), bool(controls.get("handbrake", false)))
	return result if result is Dictionary else {}

func _tick_parked(unit: Dictionary, delta: float) -> void:
	var car: Node3D = unit.car
	_step(car, delta, Driver.pedals(float(car.speed), 0.0))
	if str(unit.mode) == "abandoned" and absf(float(car.speed)) < 0.3:
		_release_unit(unit)

func _begin_hold(unit: Dictionary, why: String) -> void:
	if str(unit.mode) == "hold":
		return
	if _is_assist(unit) and why != "disabled":
		# Every "continue on foot near the goal" exit of an assist unit hands
		# the officer to the incident handler, never to law's player search.
		why = "assist"
	if why == "search":
		_mark_searched()
	unit.mode = "hold"
	unit.hold_reason = why
	unit.hold_time = 0.0
	unit.exit_tries = 0
	unit.next_exit_try = 0.0

func _tick_hold(unit: Dictionary, delta: float) -> void:
	var car: Node3D = unit.car
	_step(car, delta, Driver.pedals(float(car.speed), 0.0))
	unit.hold_time = float(unit.hold_time) + delta
	if bool(unit.frozen) or absf(float(car.speed)) > 0.3 or _clock < float(unit.next_exit_try):
		return
	unit.next_exit_try = _clock + 0.25
	if _dismount(unit):
		return
	unit.exit_tries = int(unit.exit_tries) + 1
	counters.dismount_failures = int(counters.dismount_failures) + 1
	if int(unit.exit_tries) < MAX_EXIT_TRIES:
		return
	# No clear door: keep the officer in the car and do the next best thing.
	unit.hold_failures = int(unit.get("hold_failures", 0)) + 1
	match str(unit.hold_reason):
		"engage":
			unit.mode = "pursue"
			unit.want_plan = true
		"search":
			_begin_search(unit)
		"blocked_search":
			# No actual officer reached the area. Keep the report outstanding and
			# replace the boxed car instead of searching in it without mobility.
			_blocked_dispatch(unit, true)
		"assist":
			# No clear door here: the incident handler sees the claim end and
			# falls back to a foot patrol (assist_status() becomes empty).
			assist_counters.door_failures = int(assist_counters.door_failures) + 1
			_abandon(unit, "no clear door")
		_:
			_abandon(unit, "no clear door")

func _tick_drive(unit: Dictionary, delta: float) -> void:
	var car: Node3D = unit.car
	var speed := float(car.speed)
	if bool(unit.frozen):
		_step(car, delta, Driver.pedals(speed, 0.0))
		return
	if float(unit.reverse_left) > 0.0:
		_tick_reverse(unit, delta)
		return
	if bool(unit.want_plan):
		_resume_plan(unit)
	var path: PackedVector3Array = unit.path
	if path.size() < 2:
		_step(car, delta, Driver.pedals(speed, 0.0))
		if absf(speed) < 1.0:
			_arrive(unit)
		return
	var tracked := Driver.track(path, unit.sums, int(unit.cursor), car.global_position)
	unit.cursor = int(tracked.cursor)
	unit.s = float(tracked.s)
	unit.lateral = float(tracked.lateral)
	unit.remaining = maxf(0.0, float(unit.length) - float(unit.s))
	if float(unit.lateral) > 4.5 and _clock - float(unit.plan_clock) >= REPLAN_INTERVAL:
		unit.want_plan = true
	_sense(unit, delta)
	unit.obstacle = float(unit.obstacle_s) - float(unit.s)
	var target := _target_speed(unit, speed)
	var lookahead := clampf(3.0 + absf(speed) * 0.45, 4.0, 11.0)
	var steer := 0.0
	if float(unit.remaining) > 1.5:
		var aim := Driver.point_at(path, unit.sums, float(unit.s) + lookahead, int(unit.cursor))
		steer = Driver.steer_toward(car.global_position, float(car.yaw), speed, aim)
	var controls := Driver.pedals(speed, target, BRAKE_PLAN)
	controls.steer = steer
	unit.last_steer = steer
	var result := _step(car, delta, controls)
	_after_step(unit, result, target, delta)

## Back out along the ground this car just covered (its trail), at walking
## pace, stopping for anyone behind it; then replan from where it ends up.
func _tick_reverse(unit: Dictionary, delta: float) -> void:
	var car: Node3D = unit.car
	var speed := float(car.speed)
	unit.reverse_left = float(unit.reverse_left) - delta
	var path: PackedVector3Array = unit.path
	var on_path := path.size() >= 2
	if on_path:
		# Keep the position on the old path current while backing along it.
		var tracked := Driver.track(path, unit.sums, maxi(0, int(unit.cursor) - 6), car.global_position, 12)
		unit.cursor = int(tracked.cursor)
		unit.s = float(tracked.s)
		# Being near the beginning does not mean we lost the path. In
		# particular a reverse target below 3.5 m must still be reachable.
		on_path = float(tracked.lateral) < 3.0
	var trail: PackedVector3Array = unit.trail
	var rear := car.global_position - forward_of(car) * Driver.pivot
	while trail.size() > 1 and flat(trail[trail.size() - 1], rear) < 1.5:
		trail.remove_at(trail.size() - 1)
	unit.trail = trail
	var controls := Driver.reverse_pedals(speed)
	var aim := Vector3.INF
	if on_path:
		var aim_s := float(unit.s) - 3.0 - Driver.pivot
		aim = Driver.point_at(path, unit.sums, maxf(0.0, aim_s), int(unit.cursor))
		if aim_s < 0.0:
			# Continue the initial lane tangent for the steering aim only;
			# arrival still stops at reverse_to_s and every pose is road-checked.
			# Switching to old centre breadcrumbs here turns the tail sideways.
			aim += Driver.direction_at(path, unit.sums, 0.0) * aim_s
	elif not trail.is_empty() and flat(trail[trail.size() - 1], rear) >= 1.5:
		aim = trail[trail.size() - 1]
	controls.steer = Driver.reverse_steer_toward(car.global_position, float(car.get("yaw")), speed, aim) if aim.is_finite() else float(unit.reverse_steer)
	var rear_blocked := _sweep_behind(car) < 1.5
	if rear_blocked:
		controls = Driver.pedals(speed, 0.0) # Someone is behind the car: hold.
	var result := _step(car, delta, controls)
	unit.last_blocked = "rear_occupied" if rear_blocked else str(result.get("blocked", ""))
	var moved := float(result.get("moved", 0.0))
	unit.reverse_moved = float(unit.reverse_moved) + moved
	unit.odometer = float(unit.odometer) + moved
	var arrived: bool = on_path and float(unit.s) <= float(unit.get("reverse_to_s", -INF))
	if float(unit.reverse_left) <= 0.0 and float(unit.reverse_moved) < 0.25 \
		and absf(float(car.speed)) < 0.3 and str(unit.obstacle_kind) == "vehicle" and bool(unit.emergency):
		# Replanning from an identical boxed-in pose just restarts the same
		# zero-progress reverse. Free this dispatch slot instead of oscillating.
		_blocked_dispatch(unit)
		return
	if float(unit.reverse_left) <= 0.0 or arrived or float(unit.reverse_moved) >= float(unit.get("reverse_limit", REVERSE_LIMIT)):
		# Replan from wherever this left the car on its old path: the previous
		# lane or connector, never the blocked spot ahead.
		unit.reverse_left = 0.0
		unit.want_plan = true
		unit.trail = PackedVector3Array([car.global_position])

func _blocked_dispatch(unit: Dictionary, force_replacement := false) -> void:
	unit.reverse_left = 0.0
	var car: Node3D = unit.car
	var near := not force_replacement and flat(car.global_position, Vector3(unit.goal)) <= FOOT_RANGE
	unit.response_fallback = "foot" if near else "replacement"
	_failed_cars[str(unit.vehicle_id)] = _clock + BLOCKED_DISPATCH_COOLDOWN
	counters.blocked_dispatches = int(counters.blocked_dispatches) + 1
	last_blocked_dispatch = {"vehicle_id": str(unit.vehicle_id), "position": car.global_position,
		"goal": unit.goal, "action": unit.response_fallback, "clock": _clock,
		"retry_after": _clock + BLOCKED_DISPATCH_COOLDOWN, "reverse_moved": float(unit.reverse_moved)}
	if near:
		# Mark searched only once the checked exit succeeds. A blocked door must
		# still permit another cruiser to act on the outstanding report.
		_begin_hold(unit, "blocked_search")
	else:
		# The caller proved the car stopped. Release before perception can reuse
		# its crew/slot; the outstanding report still needs another eligible car.
		_abandon(unit, "boxed in without reverse clearance")
		_release_unit(unit)

## Distance to the first person or car within a few metres behind the car.
func _sweep_behind(car: Node3D) -> float:
	var space := _space()
	if space == null:
		return INF
	if _cast_query == null:
		_make_cast_query()
	var backward := -forward_of(car)
	_cast_query.transform = Transform3D(Basis.looking_at(backward, Vector3.UP), car.global_position + backward * (CAR_LENGTH * 0.5 + 0.4) + Vector3.UP * 0.95)
	_cast_query.motion = backward * 3.0
	_cast_query.collision_mask = 4 | 8 | 16
	var skip: Array[RID] = [car.get_rid()]
	_cast_query.exclude = skip
	var fractions := space.cast_motion(_cast_query)
	if fractions.size() < 2 or fractions[0] >= 1.0:
		return INF
	return fractions[0] * 3.0

func _resume_plan(unit: Dictionary) -> void:
	var goal: Vector3 = unit.goal
	if str(unit.mode) in ["search", "depart"]:
		_extend(unit)
		return
	if not goal.is_finite() or not _can_plan():
		return
	if _replan(unit, goal):
		return
	if int(unit.plan_failures) >= 3:
		# No lane route from here: close enough continues on foot, else give up.
		if flat(unit.car.global_position, goal) <= FOOT_RANGE:
			_begin_hold(unit, "search")
		else:
			_abandon(unit, "no route")

func _after_step(unit: Dictionary, result: Dictionary, target: float, delta: float) -> void:
	var car: Node3D = unit.car
	unit.last_blocked = str(result.get("blocked", ""))
	var moved := float(result.get("moved", 0.0))
	unit.odometer = float(unit.odometer) + moved
	var contact: Dictionary = result.get("contact", {}) if result.get("contact", {}) is Dictionary else {}
	if not contact.is_empty() and float(contact.get("speed", 0.0)) > 0.5:
		counters.contacts = int(counters.contacts) + 1
		unit.contacts = int(unit.contacts) + 1
		unit.last_contact = {"kind": str(contact.get("kind", "")), "speed": float(contact.get("speed", 0.0))}
	if float(unit.odometer) - float(unit.unstick_odometer) > UNSTICK_RESET_DISTANCE:
		unit.unstick = 0
		unit.unstick_odometer = float(unit.odometer)
	# Breadcrumbs of covered ground: backing out retraces them, never guesses.
	var trail: PackedVector3Array = unit.get("trail", PackedVector3Array())
	if trail.is_empty() or flat(trail[trail.size() - 1], car.global_position) >= TRAIL_SPACING:
		trail.append(car.global_position)
		if trail.size() > MAX_TRAIL:
			trail.remove_at(0)
		unit.trail = trail
	var speed := absf(float(car.speed))
	var walled := str(unit.obstacle_kind) == "structure" and float(unit.obstacle) <= PERSON_GAP + 2.0 and speed < 0.5
	unit.structure_time = float(unit.get("structure_time", 0.0)) + delta if walled else 0.0
	if float(unit.structure_time) >= STRUCTURE_WAIT:
		# A wall or prop across the lane ahead: back out and avoid that street.
		unit.structure_time = 0.0
		_unstick(unit, _lane_at(unit, float(unit.get("obstacle_s", INF))))
		return
	var follow_gap := _following_gap(unit)
	var waiting := bool(unit.yielding) or float(unit.obstacle) <= follow_gap + 1.5 or target < 0.6
	if not waiting and speed < 0.35:
		unit.stuck = float(unit.stuck) + delta
	else:
		unit.stuck = maxf(0.0, float(unit.stuck) - delta * 2.0)
	if float(unit.stuck) >= STUCK_SECONDS:
		_unstick(unit)
		return
	var queued := str(unit.obstacle_kind) == "vehicle" and float(unit.obstacle) <= follow_gap + 2.5 and absf(float(unit.obstacle_speed)) < 0.5 and speed < 0.5
	# Someone standing in front: never passed or reversed toward, but the same
	# bounded wait ends on foot (near the goal) or in a replan around the street.
	var pedestrian_wait := str(unit.obstacle_kind) == "person" and float(unit.obstacle) <= PERSON_GAP + 0.5 and speed < 0.5
	unit.blocked_time = float(unit.blocked_time) + delta if queued or pedestrian_wait else 0.0
	if not queued:
		unit.pass_tried = false
	if queued and float(unit.blocked_time) >= PASS_WAIT and not bool(unit.pass_tried) and bool(unit.emergency) and not bool(unit.yielding):
		# A car claimed in an existing queue may start inside our planned pass
		# clearance. Recover room with the same swept, road-constrained reverse
		# used for other blockages; never force the lateral ramp into its bumper.
		if float(unit.obstacle) < PASS_START_GAP - 0.25:
			_unstick(unit)
			return
		unit.pass_tried = true
		if _plan_pass(unit):
			counters.passes = int(counters.passes) + 1
			unit.blocked_time = 0.0
	if float(unit.blocked_time) >= BLOCK_GIVE_UP:
		unit.blocked_time = 0.0
		if bool(unit.emergency) and flat(car.global_position, Vector3(unit.goal)) <= FOOT_RANGE:
			_begin_hold(unit, "search")
		else:
			var lane := _current_lane(unit)
			if lane >= 0:
				lanes.block(lane, _clock)
			unit.want_plan = true
	if str(unit.mode) == "respond" and _clock >= float(unit.get("respond_until", INF)):
		# Too slow to get there: search on foot if close, else stand down.
		if flat(car.global_position, Vector3(unit.goal)) <= FOOT_RANGE:
			_begin_hold(unit, "search")
		else:
			if not _is_assist(unit):
				_mark_searched()
			_begin_depart(unit)
		return
	if str(unit.mode) == "depart":
		var travelled := float(unit.odometer) - float(unit.depart_odometer)
		if travelled >= DEPART_DISTANCE or _clock >= float(unit.depart_until):
			unit.release_pending = true
		if bool(unit.release_pending) and speed < 0.3:
			_release_unit(unit)
			return
	if float(unit.remaining) <= ARRIVE_DISTANCE and speed < 1.0:
		_arrive(unit)

## Bounded recovery from a blocked step: back away at an angle and replan;
## the second failure also avoids that street for a while; past the limit the
## officer continues on foot.
func _unstick(unit: Dictionary, avoid_lane := -1) -> void:
	unit.stuck = 0.0
	unit.blocked_time = 0.0
	unit.unstick = int(unit.unstick) + 1
	counters.unsticks = int(counters.unsticks) + 1
	if int(unit.unstick) > MAX_UNSTICK:
		_begin_hold(unit, "stuck")
		return
	if avoid_lane < 0 and int(unit.unstick) >= 2:
		avoid_lane = _current_lane(unit)
	if avoid_lane >= 0:
		lanes.block(avoid_lane, _clock)
	# Back up REVERSE_DISTANCE, or out of a junction just taken (onto the lane
	# before it) so the replan can choose another exit.
	var s := float(unit.s)
	var target := s - REVERSE_DISTANCE
	var junction_exit := false
	for junction in unit.junctions:
		var entry := float(junction.s)
		if entry <= s and s <= float(junction.get("exit_s", entry + 12.0)) + 24.0:
			target = minf(target, entry - 3.0)
			junction_exit = true
	unit.reverse_limit = BACK_OUT_LIMIT if junction_exit else REVERSE_LIMIT
	unit.reverse_to_s = maxf(target, s - float(unit.reverse_limit))
	unit.reverse_left = BACK_OUT_SECONDS if junction_exit else REVERSE_SECONDS
	unit.reverse_moved = 0.0
	unit.reverse_steer = -clampf(float(unit.last_steer) * 2.0, -1.0, 1.0)

func _current_lane(unit: Dictionary) -> int:
	return _lane_at(unit, float(unit.s))

## The lane a path distance lies on (a connector reports the lane it leads into).
func _lane_at(unit: Dictionary, s: float) -> int:
	var lane := -1
	if not is_finite(s):
		return lane
	for segment in unit.segments:
		if float(segment.s) <= s + 0.01:
			lane = int(segment.lane)
	return lane

func _arrive(unit: Dictionary) -> void:
	if _is_assist(unit) and str(unit.mode) in ["respond", "pursue", "search"]:
		_begin_hold(unit, "assist")
		return
	match str(unit.mode):
		"respond", "pursue":
			if _clock - float(unit.seen_clock) < 1.0:
				if bool(unit.target_seated) and flat(Vector3(unit.goal), Vector3(unit.planned_goal)) > 3.0:
					unit.want_plan = true # Their car moved on: keep driving after it.
				elif int(unit.get("hold_failures", 0)) < 2:
					# Seen, but the road ends short of them: the officer goes on foot.
					_begin_hold(unit, "engage")
			elif bool(law.last_seen_seated):
				_begin_search(unit)
			else:
				_begin_hold(unit, "search")
		"search":
			if _clock >= float(unit.search_until):
				_begin_depart(unit)
			else:
				_extend(unit)
		"depart":
			unit.release_pending = true

## The suspect was last seen driving: follow the road they took for the
## tier's search time, at search speed, from the last known position on.
func _begin_search(unit: Dictionary) -> void:
	unit.mode = "search"
	_mark_searched()
	counters.searches = int(counters.searches) + 1
	var times: Array = law.search_seconds
	unit.search_until = _clock + float(times[clampi(int(law.wanted), 0, times.size() - 1)])
	_extend(unit)

func _begin_depart(unit: Dictionary) -> void:
	if str(unit.mode) == "depart":
		return
	unit.mode = "depart"
	unit.release_pending = false
	unit.depart_until = _clock + DEPART_SECONDS
	unit.depart_odometer = float(unit.odometer)
	counters.departures = int(counters.departures) + 1
	_set_emergency(unit, false)
	_extend(unit)

## Continue along the lanes (search follows the last seen heading; departure
## keeps the car's own heading).
func _extend(unit: Dictionary) -> void:
	if not _can_plan():
		unit.want_plan = true
		return
	_plan_tick = _ticks
	unit.want_plan = false
	var car: Node3D = unit.car
	var heading: Vector3 = forward_of(car)
	if str(unit.mode) == "search" and Vector3(law.last_seen_heading).length_squared() > 0.01:
		heading = law.last_seen_heading
	var start := _start_from_path(unit)
	if start.is_empty():
		var near := lanes.nearest(car.global_position, forward_of(car), Lanes.START_RADIUS, 0.45, 1)
		if near.is_empty():
			if str(unit.mode) == "depart":
				unit.release_pending = true
			else:
				_begin_depart(unit)
			return
		start = {"lane": int(near[0].lane), "along": float(near[0].along), "lead": PackedVector3Array()}
	var plan := lanes.continuation(int(start.lane), float(start.along), heading, SEARCH_EXTENSION, start.lead)
	if not bool(plan.ok) or float(plan.get("length", 0.0)) < 2.0:
		unit.release_pending = true
		if str(unit.mode) == "search":
			_begin_depart(unit)
		return
	plan["kind"] = "continuation"
	_apply_path(unit, plan)

# --------------------------------------------------------------- sensing (10 Hz)

func _sense(unit: Dictionary, delta: float) -> void:
	unit.sense_left = float(unit.sense_left) - delta
	if float(unit.sense_left) > 0.0:
		return
	unit.sense_left = SENSE_INTERVAL
	var car: Node3D = unit.car
	var at := car.global_position
	var speed := absf(float(car.speed))
	var horizon := clampf(speed * speed / (2.0 * BRAKE_PLAN) + 16.0, 16.0, 48.0)
	var s := float(unit.s)
	var best := INF
	var kind := ""
	var along_speed := 0.0
	for pool in [traffic.get("vehicles"), traffic.get("player_fleet")]:
		if not pool is Array:
			continue
		for other in pool:
			if other == car or not is_instance_valid(other) or not other is Node3D:
				continue
			var point: Vector3 = other.global_position
			if absf(point.x - at.x) > horizon + 6.0 or absf(point.z - at.z) > horizon + 6.0:
				continue
			var hit := _path_hit(unit, point, s + horizon, CAR_CORRIDOR)
			if hit < 0.0:
				continue
			var gap := hit - s - CAR_LENGTH
			if gap < best:
				best = gap
				kind = "vehicle"
				var direction := Driver.direction_at(unit.path, unit.sums, hit, int(unit.cursor))
				along_speed = float(other.get("speed")) * forward_of(other).dot(direction)
	var ahead := _sweep_ahead(unit, minf(horizon, 22.0))
	if float(ahead.distance) < best:
		best = float(ahead.distance)
		kind = str(ahead.kind)
		along_speed = 0.0
	# Absolute path positions: braking between scans uses the current distance.
	unit.obstacle_s = s + best
	unit.obstacle = best
	unit.obstacle_kind = kind
	unit.obstacle_speed = along_speed
	unit.junction = _junction_state(unit)

## Path distance where `point` comes within `corridor` of the path ahead, or -1.
func _path_hit(unit: Dictionary, point: Vector3, s_end: float, corridor: float) -> float:
	var path: PackedVector3Array = unit.path
	var sums: PackedFloat64Array = unit.sums
	var i := int(unit.cursor)
	var best := -1.0
	var best_distance := corridor
	while i < path.size() - 1 and sums[i] <= s_end:
		var j := mini(i + 2, path.size() - 1)
		var a := path[i]
		var b := path[j]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var length_squared := ab.length_squared()
		var t := 0.0 if length_squared < 0.000001 else clampf(Vector2(point.x - a.x, point.z - a.z).dot(ab) / length_squared, 0.0, 1.0)
		var distance := (Vector2(a.x, a.z) + ab * t).distance_to(Vector2(point.x, point.z))
		if distance < best_distance:
			best_distance = distance
			best = sums[i] + (sums[j] - sums[i]) * t
		i = j
	return best

func _make_cast_query() -> void:
	_cast_query = PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.1, 1.5, 0.6)
	_cast_query.shape = box
	_cast_query.margin = 0.02

## People, the on-foot player and props/walls in the lane ahead: one box sweep
## along the path, no longer than the path stays straight (so a bend never
## "sees" the buildings it curves past). {distance, kind: person|structure}.
func _sweep_ahead(unit: Dictionary, length: float) -> Dictionary:
	var none := {"distance": INF, "kind": ""}
	var space := _space()
	if space == null:
		return none
	if _cast_query == null:
		_make_cast_query()
	var car: Node3D = unit.car
	var forward := forward_of(car)
	var start := car.global_position + forward * (CAR_LENGTH * 0.5 + 0.4) + Vector3.UP * 0.95
	var direction := Driver.direction_at(unit.path, unit.sums, float(unit.s) + 4.0, int(unit.cursor))
	if direction == Vector3.ZERO:
		direction = forward
	length = minf(length, _straight_reach(unit, start, direction, length))
	if length < 0.5:
		return none
	_cast_query.transform = Transform3D(Basis.looking_at(direction, Vector3.UP), start)
	_cast_query.motion = direction * length
	_cast_query.collision_mask = 2 | 4 | 8
	var skip: Array[RID] = [car.get_rid()]
	_cast_query.exclude = skip
	var fractions := space.cast_motion(_cast_query)
	if fractions.size() < 2 or fractions[0] >= 1.0:
		return none
	# Which body: one rest query just past the safe fraction.
	var kind := "person"
	_cast_query.transform = Transform3D(_cast_query.transform.basis, start + direction * length * minf(1.0, fractions[1] + 0.02))
	_cast_query.motion = Vector3.ZERO
	var info := space.get_rest_info(_cast_query)
	if not info.is_empty():
		var body := instance_from_id(int(info.collider_id))
		if body is CollisionObject3D and ((body as CollisionObject3D).collision_layer & (4 | 8)) == 0:
			kind = "structure"
	return {"distance": fractions[0] * length + 0.4, "kind": kind}

## How far the sweep can run along `direction` before the path bends more than
## about a metre away from it.
func _straight_reach(unit: Dictionary, start: Vector3, direction: Vector3, length: float) -> float:
	var path: PackedVector3Array = unit.path
	var sums: PackedFloat64Array = unit.sums
	var side := Vector3(direction.z, 0.0, -direction.x)
	var i := int(unit.cursor)
	var s := float(unit.s)
	while i < path.size() and sums[i] <= s + length + CAR_LENGTH:
		var offset := Vector3(path[i].x - start.x, 0.0, path[i].z - start.z)
		var along := offset.dot(direction)
		if along > 0.0 and absf(offset.dot(side)) > 1.3:
			return maxf(0.0, along - 1.0)
		i += 2
	return length

func _junction_state(unit: Dictionary) -> Dictionary:
	unit.yielding = false
	var s := float(unit.s)
	var junctions: Array = unit.junctions
	for index in junctions.size():
		var junction: Dictionary = junctions[index]
		var entry := float(junction.s)
		var leave := float(junction.get("exit_s", entry + 12.0))
		if leave < s:
			continue
		var distance := entry - s
		if distance > 30.0:
			unit.yield_time = 0.0
			return {}
		var key := str(index)
		var cleared: Dictionary = unit.cleared
		# An ambulance owns the shared crossing until its rear has cleared.
		# Neither an earlier approach decision nor elapsed waiting can revoke it.
		if _emergency_junction_owned_by_other(unit.car, junction):
			cleared.erase(key)
			unit.yield_time = float(unit.yield_time) + SENSE_INTERVAL
			if float(unit.yield_time) <= SENSE_INTERVAL + 0.001:
				counters.yields = int(counters.yields) + 1
			unit.yielding = true
			return {"entry_s": entry, "yield": true}
		if cleared.has(key) or distance <= 0.5:
			cleared[key] = true
			unit.yield_time = 0.0
			return {"entry_s": entry, "yield": false}
		var red := not bool(unit.emergency) and bool(junction.get("signal", false)) and _signal_red(str(junction.get("axis", "")))
		if red or _crossing_traffic(unit, junction):
			unit.yield_time = float(unit.yield_time) + SENSE_INTERVAL
			if red or float(unit.yield_time) < YIELD_LIMIT:
				if float(unit.yield_time) <= SENSE_INTERVAL + 0.001:
					counters.yields = int(counters.yields) + 1
				unit.yielding = true
				return {"entry_s": entry, "yield": true}
		if distance <= 6.0:
			cleared[key] = true
			unit.yield_time = 0.0
		return {"entry_s": entry, "yield": false}
	return {}

func _signal_red(axis: String) -> bool:
	var signals = traffic.get("signals")
	return signals != null and signals.has_method("phase") and str(signals.phase(axis)) != "Green"

func _emergency_junction_owned_by_other(car: Node3D, junction: Dictionary) -> bool:
	if not is_instance_valid(traffic):
		return false
	var reservations = traffic.get("reservations")
	var emergency = traffic.get("emergency_vehicles")
	if not reservations is Dictionary or not emergency is Array:
		return false
	var holder = reservations.get(str(junction.get("node", "")))
	return is_instance_valid(holder) and holder is Node3D and holder != car \
		and holder.is_inside_tree() and emergency.has(holder)

## A car moving through the junction, or approaching it across our way, or
## holding traffic's own reservation of it.
func _crossing_traffic(unit: Dictionary, junction: Dictionary) -> bool:
	var car: Node3D = unit.car
	if _emergency_junction_owned_by_other(car, junction):
		return true
	var center: Vector3 = junction.center
	var radius := float(junction.radius)
	var ours := Driver.direction_at(unit.path, unit.sums, float(junction.s) + 2.0, int(unit.cursor))
	var reservations = traffic.get("reservations")
	if reservations is Dictionary:
		var holder = reservations.get(str(junction.get("node", "")))
		if is_instance_valid(holder) and holder != car and flat(holder.global_position, center) <= radius + 8.0 \
				and forward_of(holder).dot(ours) <= 0.8:
			return true
	for pool in [traffic.get("vehicles"), traffic.get("player_fleet")]:
		if not pool is Array:
			continue
		for other in pool:
			if other == car or not is_instance_valid(other) or not other is Node3D:
				continue
			var point: Vector3 = other.global_position
			var distance := flat(point, center)
			if distance > radius + 8.0:
				continue
			var heading := forward_of(other)
			if heading.dot(ours) > 0.8:
				continue # Same way as us: following is handled by the obstacle scan.
			var speed := absf(float(other.get("speed")))
			var toward := Vector3(center.x - point.x, 0.0, center.z - point.z)
			if distance <= radius and speed > 0.5:
				return true
			if speed > 1.0 and toward.length() > 0.1 and heading.dot(toward.normalized()) * signf(float(other.get("speed"))) > 0.3:
				return true
	return false

func _target_speed(unit: Dictionary, speed: float) -> float:
	if bool(unit.release_pending):
		return 0.0
	var cap := RESPOND_SPEED
	match str(unit.mode):
		"pursue":
			cap = PURSUIT_SPEED
		"search":
			cap = SEARCH_SPEED
		"depart":
			cap = DEPART_SPEED
	var s := float(unit.s)
	var horizon := clampf(speed * speed / (2.0 * BRAKE_PLAN) + 12.0, 12.0, 60.0)
	var target := minf(cap, Driver.allowed_speed(unit.limits, unit.sums, int(unit.cursor), s, horizon, BRAKE_PLAN))
	target = minf(target, Driver.stop_speed(float(unit.remaining) - 0.5, BRAKE_PLAN))
	var obstacle := float(unit.obstacle)
	if is_finite(obstacle):
		var gap := obstacle - (_following_gap(unit) if str(unit.obstacle_kind) == "vehicle" else PERSON_GAP)
		var follow := maxf(0.0, float(unit.obstacle_speed))
		target = minf(target, sqrt(follow * follow + 2.0 * BRAKE_PLAN * gap) if gap > 0.0 else 0.0)
	var junction: Dictionary = unit.junction
	if not junction.is_empty():
		var distance := float(junction.entry_s) - s
		if bool(junction.yield):
			target = minf(target, Driver.stop_speed(distance - 1.0, BRAKE_PLAN))
		else:
			target = minf(target, sqrt(JUNCTION_SPEED * JUNCTION_SPEED + 2.0 * BRAKE_PLAN * maxf(0.0, distance)))
	return maxf(0.0, target)

func _following_gap(unit: Dictionary) -> float:
	if bool(unit.emergency) and str(unit.obstacle_kind) == "vehicle" and absf(float(unit.obstacle_speed)) < 0.5:
		return PASS_START_GAP
	return STOP_GAP

## A stopped car blocks the lane: pass along a smooth on-road offset with the
## whole footprint on the carriageway and no car in or approaching the gap.
func _plan_pass(unit: Dictionary) -> bool:
	var path: PackedVector3Array = unit.path
	var sums: PackedFloat64Array = unit.sums
	var start_s := float(unit.s)
	var obstacle_s := start_s + float(unit.obstacle) + CAR_LENGTH
	var end_s := obstacle_s + CAR_LENGTH + 4.0
	if end_s + 6.0 >= float(unit.length) - 1.0:
		return false
	for side in [1.0, -1.0]:
		var points := PackedVector3Array()
		var clear := true
		var s := start_s
		while s <= end_s + 6.0 and clear:
			var base := Driver.point_at(path, sums, s, int(unit.cursor))
			var direction := Driver.direction_at(path, sums, s, int(unit.cursor))
			var left := Vector3(direction.z, 0.0, -direction.x)
			var ramp := clampf((s - start_s) / 6.0, 0.0, 1.0) * clampf((end_s + 6.0 - s) / 6.0, 0.0, 1.0)
			var point := base + left * float(side) * PASS_OFFSET * ramp
			for corner in [left * 1.1 + direction * 2.4, -left * 1.1 + direction * 2.4, left * 1.1 - direction * 2.4, -left * 1.1 - direction * 2.4]:
				if not lanes.on_road(point + corner, 0.1):
					clear = false
			if clear and ramp > 0.3 and not _offset_clear(unit, point, direction):
				clear = false
			if clear and ramp > 0.3 and points.size() % 3 == 0 and not _hull_clear_at(unit.car, point, direction):
				clear = false # Parked batch cars and props are not in the traffic list.
			points.append(point)
			s += Lanes.SPACING
		if clear and points.size() >= 4:
			_splice(unit, points, end_s + 6.0)
			return true
	return false

## The car's whole envelope (with a small margin) is free at a pose: no prop,
## wall or parked/driving car there.
func _hull_clear_at(car: Node3D, point: Vector3, direction: Vector3) -> bool:
	var space := _space()
	if space == null:
		return false
	if _hull_query == null:
		_hull_query = PhysicsShapeQueryParameters3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(BODY_SIZE.x + 0.2, 1.4, BODY_SIZE.z + 0.3)
		_hull_query.shape = box
		_hull_query.collision_mask = 2 | 16
		_hull_query.margin = 0.02
	_hull_query.transform = Transform3D(Basis.looking_at(direction, Vector3.UP), point + Vector3.UP * 0.95)
	var skip: Array[RID] = [car.get_rid()]
	_hull_query.exclude = skip
	return space.intersect_shape(_hull_query, 1).is_empty()

## No car within reach of an offset point, nor one coming toward it.
func _offset_clear(unit: Dictionary, point: Vector3, direction: Vector3) -> bool:
	var car: Node3D = unit.car
	for pool in [traffic.get("vehicles"), traffic.get("player_fleet")]:
		if not pool is Array:
			continue
		for other in pool:
			if other == car or not is_instance_valid(other) or not other is Node3D:
				continue
			var at: Vector3 = other.global_position
			var offset := Vector3(at.x - point.x, 0.0, at.z - point.z)
			if offset.length() < 2.6:
				return false
			var ahead := offset.dot(direction)
			var lateral := absf(offset.dot(Vector3(direction.z, 0.0, -direction.x)))
			if ahead > 0.0 and ahead < 40.0 and lateral < 2.6 and float(other.get("speed")) * forward_of(other).dot(direction) < -0.5:
				return false
	return true

## Replace the path from here to join_s with `prefix`, keeping the rest (and its
## lane/junction metadata, shifted to the new distances).
func _splice(unit: Dictionary, prefix: PackedVector3Array, join_s: float) -> void:
	var path: PackedVector3Array = unit.path
	var sums: PackedFloat64Array = unit.sums
	var raw := PackedVector3Array([unit.car.global_position])
	raw.append_array(prefix)
	var join_index := path.size()
	for i in path.size():
		if sums[i] >= join_s:
			join_index = i
			break
	var prefix_length := Lanes.cumulative(raw)[-1]
	if join_index < path.size():
		prefix_length += flat(raw[-1], path[join_index])
		for i in range(join_index, path.size()):
			raw.append(path[i])
	var points := Lanes.resample(raw, Lanes.SPACING)
	var new_sums := Lanes.cumulative(points)
	var shift := prefix_length - (sums[join_index] if join_index < path.size() else join_s)
	var segments: Array = [{"kind": "lead", "s": 0.0, "lane": -1, "along": 0.0}]
	var previous: Dictionary = {}
	for segment in unit.segments:
		if float(segment.s) < join_s:
			previous = segment
			continue
		var moved: Dictionary = segment.duplicate()
		moved.s = float(segment.s) + shift
		segments.append(moved)
	if not previous.is_empty() and str(previous.kind) == "lane":
		var resumed: Dictionary = previous.duplicate()
		resumed.along = float(previous.along) + join_s - float(previous.s)
		resumed.s = prefix_length
		segments.insert(1, resumed)
		(segments[0] as Dictionary).lane = int(previous.lane)
	var junctions: Array = []
	for junction in unit.junctions:
		if float(junction.s) < join_s:
			continue
		var moved: Dictionary = junction.duplicate()
		moved.s = float(junction.s) + shift
		if moved.has("exit_s"):
			moved.exit_s = float(junction.exit_s) + shift
		junctions.append(moved)
	var goal: Vector3 = unit.planned_goal
	_apply_path(unit, {"points": points, "sums": new_sums, "length": new_sums[-1], "segments": segments,
		"junctions": junctions, "kind": "lanes", "end_gap": float(unit.end_gap)})
	unit.planned_goal = goal

# --------------------------------------------------------------- dismount

func _dismount(unit: Dictionary) -> bool:
	var entry := _crew_of(unit)
	var actor = entry.get("actor")
	if str(entry.get("state", "")) != "seated" or not is_instance_valid(actor) or actor.dead == true:
		return false
	var car: Node3D = unit.car
	var slot := _exit_slot(car, actor)
	if slot.is_empty():
		return false
	var at: Vector3 = slot.position
	var assist := _is_assist(unit)
	var goal: Vector3 = law.last_known_position if law.last_known_position.is_finite() and not assist else Vector3(unit.goal)
	var facing := Vector3(goal.x - at.x, 0.0, goal.z - at.z)
	var heading := atan2(facing.x, facing.z) if facing.length() > 0.2 else float(car.get("yaw"))
	actor.global_position = at
	actor.yaw = heading
	actor.velocity = Vector3.ZERO
	if actor.puppet != null:
		actor.puppet.g.rotation.y = heading
	actor.set_enabled(true)
	if actor.enabled != true:
		return false
	if actor.has_method("reset_physics_interpolation"):
		actor.reset_physics_interpolation()
	entry.state = "foot"
	entry.homecomings = 0
	unit.mode = "dismounted"
	unit.door = at
	unit.dismount_clock = _clock
	counters.dismounts = int(counters.dismounts) + 1
	if str(unit.hold_reason) == "blocked_search":
		_mark_searched()
	if assist:
		assist_counters.dismounts = int(assist_counters.dismounts) + 1
		var adopted := false
		if is_instance_valid(assist_handler) and assist_handler.has_method("on_assist_dismount"):
			adopted = bool(assist_handler.on_assist_dismount(actor, str(unit.assist), at))
		if not adopted and actor.has_method("speak"):
			# No incident to join: the crew upkeep walks them back and the car departs.
			actor.speak("Dispatch, nothing here. Heading back.", 1.8)
		return true
	var sighted := _clock - float(unit.seen_clock) <= 1.0
	law._enlist_crew(actor, at, sighted)
	if actor.has_method("speak"):
		actor.speak("Police! Stay where you are!" if sighted else "Dispatch, I'm out checking the area.", 1.8)
	return true

func _car_size(car: Node3D) -> Vector3:
	var kind := str(car.get("prototype_kind"))
	return Models.dimensions(kind) if Models.has_kind(kind) else BODY_SIZE

## A capsule-checked spot beside a door: walkable ground near the car's height,
## the officer's own capsule clear of walls, props, people, the player and cars
## (including this one), no bank above curb height, and a clear path from the
## seat out through the door rather than through a wall or post.
func _exit_slot(car: Node3D, actor: Node3D) -> Dictionary:
	var size := _car_size(car)
	var lateral := size.x * 0.5 + 0.55
	var doors := [["driver", lateral, 0.25], ["passenger", -lateral, 0.25], ["driver_rear", lateral, -0.95],
		["passenger_rear", -lateral, -0.95], ["rear", 0.0, -(size.z * 0.5 + 0.7)], ["front", 0.0, size.z * 0.5 + 0.7]]
	for door in doors:
		var spot := _slot(car, actor, float(door[1]), float(door[2]))
		if not spot.is_empty():
			spot["door"] = door[0]
			return spot
	return {}

func _slot(car: Node3D, actor: Node3D, lateral: float, along: float) -> Dictionary:
	var space := _space()
	if space == null:
		return {}
	var forward := forward_of(car)
	var side := Vector3(forward.z, 0.0, -forward.x)
	var base: Vector3 = car.global_position
	var at := base + side * lateral + forward * along
	_ground_ray.from = at + Vector3.UP * 1.0
	_ground_ray.to = at - Vector3.UP * 1.5
	var ground := space.intersect_ray(_ground_ray)
	if ground.is_empty() or Vector3(ground.normal).y < cos(deg_to_rad(48.0)):
		return {}
	var foot: Vector3 = ground.position
	if absf(foot.y - base.y) > 0.6:
		return {}
	var shape: Shape3D = null
	var center := 0.9
	var collider = actor.get("capsule")
	if collider is CollisionShape3D:
		shape = (collider as CollisionShape3D).shape
		center = (collider as CollisionShape3D).position.y
	if shape == null:
		var fallback := CapsuleShape3D.new()
		fallback.radius = 0.28
		fallback.height = 1.7
		shape = fallback
	if _slot_query == null:
		_slot_query = PhysicsShapeQueryParameters3D.new()
		_slot_query.margin = 0.03
	_slot_query.shape = shape
	_slot_query.transform = Transform3D(Basis.IDENTITY, foot + Vector3.UP * (center + 0.05))
	_slot_query.collision_mask = 2 | 4 | 8 | 16
	var skip: Array[RID] = [actor.get_rid()]
	_slot_query.exclude = skip
	_slot_query.motion = Vector3.ZERO
	if not space.intersect_shape(_slot_query, 1).is_empty():
		return {}
	_slot_query.transform.origin += Vector3.UP * 0.30
	_slot_query.collision_mask = 1
	if not space.intersect_shape(_slot_query, 1).is_empty():
		return {}
	if _sweep_query == null:
		_sweep_query = PhysicsShapeQueryParameters3D.new()
		var ball := SphereShape3D.new()
		ball.radius = 0.22
		_sweep_query.shape = ball
		_sweep_query.collision_mask = 2 | 4 | 8 | 16
	var seat := base + forward * clampf(along, -1.2, 1.2) + Vector3.UP * 1.0
	_sweep_query.transform = Transform3D(Basis.IDENTITY, seat)
	_sweep_query.motion = foot + Vector3.UP * 1.0 - seat
	var ignore: Array[RID] = [car.get_rid(), actor.get_rid()]
	_sweep_query.exclude = ignore
	var fractions := space.cast_motion(_sweep_query)
	if fractions.size() < 2 or fractions[0] < 1.0:
		return {}
	return {"position": foot + Vector3.UP * 0.012}

# --------------------------------------------------------------- crew upkeep (1 Hz)

func _tick_crew() -> void:
	for entry in crew:
		var actor = entry.actor
		if not is_instance_valid(actor) or actor.dead == true or _combat_dead(str(entry.id)):
			if str(entry.state) != "dead":
				entry.state = "dead"
				var unit: Dictionary = units.get(int(entry.slot), {})
				if not unit.is_empty():
					_abandon(unit, "crew lost")
			continue
		if str(entry.state) != "foot" or law._responders.has(str(entry.id)) or actor.get("combat_override") == true:
			continue
		var unit: Dictionary = units.get(int(entry.slot), {})
		if not unit.is_empty() and str(unit.mode) == "dismounted" and _car_usable(unit.car) and int(entry.homecomings) < MAX_HOMECOMINGS:
			entry.homecomings = int(entry.homecomings) + 1
			law._send_crew_home(actor, Vector3(unit.get("door", unit.car.global_position)))
		elif _unseen(actor):
			# Walked off toward the station out of everyone's sight.
			_hide(entry, {})
			if not unit.is_empty() and str(unit.mode) == "dismounted":
				_abandon(unit, "crew left the car")

func _unseen(actor: Node3D) -> bool:
	var player = level.get("player") if level != null else null
	if not player is Node3D:
		return true
	var at := actor.global_position + Vector3.UP * 1.0
	var distance := flat(at, (player as Node3D).global_position)
	if distance < HIDE_DISTANCE:
		return false
	var camera = player.get("camera")
	if camera is Camera3D and (camera as Camera3D).is_inside_tree() and distance < 160.0 and (camera as Camera3D).is_position_in_frustum(at):
		return false
	return true

# --------------------------------------------------------------- status

func get_status() -> Dictionary:
	var unit_list: Array = []
	for slot in units:
		var unit: Dictionary = units[slot]
		var entry := _crew_of(unit)
		var car = unit.car
		unit_list.append({"slot": int(slot), "vehicle_id": str(unit.vehicle_id), "owner": str(unit.owner), "mode": str(unit.mode),
			"emergency": bool(unit.emergency), "goal": unit.goal, "position": car.global_position if is_instance_valid(car) else Vector3.INF,
			"speed": float(car.speed) if is_instance_valid(car) else 0.0, "seen": bool(unit.seen),
			"remaining": float(unit.remaining), "path_points": (unit.path as PackedVector3Array).size(), "path_kind": str(unit.path_kind),
			"stuck": float(unit.stuck), "unsticks": int(unit.unstick), "replans": int(unit.replans), "yielding": bool(unit.yielding),
			"obstacle": float(unit.obstacle), "obstacle_kind": str(unit.obstacle_kind), "contacts": int(unit.contacts),
			"obstacle_speed": float(unit.obstacle_speed), "blocked_time": float(unit.blocked_time),
			"pass_tried": bool(unit.pass_tried), "reverse_left": float(unit.reverse_left),
			"last_blocked": str(unit.get("last_blocked", "")), "odometer": float(unit.odometer),
			"response_fallback": str(unit.get("response_fallback", "")),
			"crew": str(entry.get("id", "")), "crew_state": str(entry.get("state", "")), "frozen": bool(unit.frozen),
			"hold_reason": str(unit.hold_reason), "door": unit.door, "assist": str(unit.get("assist", ""))})
	var crew_list: Array = []
	for entry in crew:
		var unit: Dictionary = units.get(int(entry.slot), {})
		crew_list.append({"id": str(entry.id), "state": str(entry.state), "vehicle_id": str(unit.get("vehicle_id", ""))})
	var totals := summary()
	return {"available": available, "reason": reason, "max": MAX_CRUISERS, "active": int(totals.active),
		"en_route": int(totals.en_route), "claimed": units.size(), "crew": crew_list, "units": unit_list,
		"counters": counters.duplicate(), "assist_counters": assist_counters.duplicate(),
		"last_blocked_dispatch": last_blocked_dispatch.duplicate(),
		"lanes": lanes.lane_count() if lanes != null else 0,
		"route_reason": lanes.last_reason if lanes != null else "", "police_cars": _police_cache.size()}
