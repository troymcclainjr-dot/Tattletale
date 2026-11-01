extends RefCounted
## Save-side half of a mounted-bicycle checkpoint (owner: world save).
## The bicycle owns its motion, hull and wheel-support truth and the single
## mutation hook (bicycle-save-contract.md sections 2-3). This file owns the optional
## checkpoint section {"version": 1, "mounted": true, "position": [x, y, z], "yaw"},
## the standing spot written as player.position (never the seat, so every reader,
## including builds that ignore this section, stands the explorer clear of the
## frame), resident reservations around the frame, and the restore preflight,
## verification and standing fallback. A parked bicycle is not persisted: a walking
## checkpoint re-parks it beside the explorer, as before.
## Contract: artifacts/five-priorities-20261101/save-contract.md
const VERSION := 1
const API := ["save_blocker", "persistence_state", "pose_blocker", "restore_pose"]
## city_bicycle._bike_clear's box: the frame and both wheels, ground to bars.
const HALF_WIDTH := 0.35
const HALF_LENGTH := 1.05
## The explorer capsule, and a resident (the provider reserves 0.66 m centre to centre).
const STAND_RADIUS := 0.30
const RESIDENT_RADIUS := 0.36
## Used only when the bicycle declares no SAVE_STILL_SPEED.
const STILL_SPEED := 0.05
## The bicycle's own unforced dismount offsets, then behind and ahead of the frame.
const SIDE_OFFSETS := [1.0, 1.4]
const END_OFFSET := 1.6
const MAX_STAND_DISTANCE := 2.6
const MAX_STAND_RISE := 0.65
const PLANAR_TOLERANCE := 0.02
## restore_pose may settle the frame onto measured wheel support by up to 0.05 m.
const RISE_TOLERANCE := 0.06
const YAW_TOLERANCE := 0.01
const LEGACY_SEATED := "step off your bicycle before saving"
const NO_ROOM := "no room to step off the bicycle here"
const PRESSED := "something is pressing against the bicycle"

## level.bicycle when it publishes every persistence hook, else null.
static func api(level) -> Node:
	var bike = level.get("bicycle") if level != null else null
	if not is_instance_valid(bike):
		return null
	for method in API:
		if not bike.has_method(method):
			return null
	return bike

## The seated explorer's bicycle verdict and facts from one query. reason "" means
## the seat may be written: the provider still waits for police and fights, then
## passes these facts to capture().
static func seat_check(level) -> Dictionary:
	var driving = level.get("driving")
	if driving != null and driving.get("active") == true:
		return {"reason": "leave the vehicle first"}
	var bike := api(level)
	if bike == null:
		return {"reason": LEGACY_SEATED}
	if level.player.get("seated_vehicle") != bike:
		return {"reason": "bicycle seat state is changing"}
	var facts = bike.persistence_state()
	# The facts carry save_blocker() (its pose check is physics): ask only if absent.
	var verdict = facts.get("blocker") if facts is Dictionary else null
	var reason := str(verdict) if verdict is String else str(bike.save_blocker())
	if reason.is_empty():
		reason = _motion_blocker(facts, _still(bike))
	return {"reason": reason, "facts": facts}

## Physics half for the current mounted pose: residents reserved around the
## frame, then a checked standing spot beside it. {"reason": ""} carries the section.
static func capture(save, facts: Dictionary) -> Dictionary:
	var at: Vector3 = facts.position
	var yaw := float(facts.yaw)
	if not residents_clear(save.level, at, yaw):
		return {"reason": PRESSED}
	var stand := standing_spot(save, at, yaw)
	if stand.is_empty():
		return {"reason": NO_ROOM}
	return {"reason": "", "stand": stand.position, "yaw": yaw,
		"section": {"version": VERSION, "mounted": true, "position": [at.x, at.y, at.z], "yaw": yaw}}

## A checked spot where the explorer could stand after getting off: the provider's
## own ground/capsule/resident test (the frame itself is solid on layer 16), clear
## of the frame footprint, on the bicycle's side of every wall and fence.
static func standing_spot(save, at: Vector3, yaw: float) -> Dictionary:
	var level = save.level
	var side := Vector3(cos(yaw), 0.0, -sin(yaw))
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	var offsets: Array[Vector3] = []
	for radius in SIDE_OFFSETS:
		for direction in [1.0, -1.0]:
			offsets.append(side * float(radius) * float(direction))
	offsets.append(-forward * END_OFFSET)
	offsets.append(forward * END_OFFSET)
	var space: PhysicsDirectSpaceState3D = level.get_world_3d().direct_space_state
	for offset in offsets:
		var spot: Dictionary = save.safe_player_position(at + offset)
		if spot.is_empty():
			continue
		var point: Vector3 = spot.position
		if footprint_gap(point, at, yaw) < STAND_RADIUS or absf(point.y - at.y) > MAX_STAND_RISE:
			continue
		var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP, point + Vector3.UP, 1 | 2)
		if level.player is CollisionObject3D:
			ray.exclude = [level.player.get_rid()]
		if space.intersect_ray(ray).is_empty():
			return {"position": point}
	return {}

## Planar distance from `point` to the frame footprint at `at`/`yaw`; 0 inside it.
static func footprint_gap(point: Vector3, at: Vector3, yaw: float) -> float:
	var offset := point - at
	var along := absf(offset.x * sin(yaw) + offset.z * cos(yaw)) - HALF_LENGTH
	var across := absf(offset.x * cos(yaw) - offset.z * sin(yaw)) - HALF_WIDTH
	return Vector2(maxf(along, 0.0), maxf(across, 0.0)).length()

## Distant residents may have disabled bodies the hull test cannot see: reserve
## their real positions around the frame, as safe_player_position does for a person.
static func residents_clear(level, at: Vector3, yaw: float) -> bool:
	var residents = level.get("residents")
	if residents == null or not residents.get("actors") is Dictionary:
		return true
	for actor in residents.actors.values():
		if not actor is Node3D or actor.get_meta("city_dead", false):
			continue
		var point: Vector3 = actor.global_position
		if footprint_gap(point, at, yaw) < RESIDENT_RADIUS and absf(point.y - at.y) < 1.9:
			return false
	return true

## Static checks of a snapshot that carries the section ("" when valid). The provider
## has already checked the container version, both positions and future versions.
static func validate(value: Dictionary) -> String:
	var section: Dictionary = value.bicycle
	if not _integer(section.get("version"), 1, VERSION) or not _is_true(section.get("mounted")) or not _number(section.get("yaw"), -100000.0, 100000.0):
		return "invalid bicycle"
	var at := _vector(section.position)
	var stand := _vector(value.player.position)
	if footprint_gap(stand, at, float(section.yaw)) < STAND_RADIUS:
		return "saved explorer overlaps the bicycle"
	if Vector2(stand.x - at.x, stand.z - at.z).length() > MAX_STAND_DISTANCE or absf(stand.y - at.y) > MAX_STAND_RISE:
		return "saved explorer is not beside the bicycle"
	return ""

## A load replaces the bicycle's state, so only from a riderless bicycle at rest.
## Seated explorers are refused by the provider before this is asked.
static func load_blocker(level) -> String:
	var bike := api(level)
	if bike == null or str(bike.save_blocker()).is_empty():
		return ""
	return "wait for your bicycle to come to rest before loading a checkpoint"

## Final load step: nothing after it can refuse, so it never has to be unwound.
## A mounted section seats the explorer at the saved pose or explains why they
## stand beside it; any other checkpoint re-parks the bicycle beside the explorer.
## state: "mounted" | "standing" | "parked" | "not parked" | "unchanged" | "unverified".
static func restore(save, state: Dictionary) -> Dictionary:
	var level = save.level
	if not state.has("bicycle"):
		return {"state": _park(level), "reason": ""}
	var section: Dictionary = state.bicycle
	var at := _vector(section.position)
	var yaw := float(section.yaw)
	var bike := api(level)
	if bike == null:
		return _standing(level, "the bicycle is not ready")
	var reason := _pose_refusal(save, bike, at, yaw)
	if reason.is_empty():
		var placed: Vector3 = level.player.global_position
		var heading := float(level.player.yaw)
		var applied = bike.restore_pose(at, yaw, true, false)
		if applied is Dictionary and bool(applied.get("ok", false)):
			reason = _verify(level, bike, at, yaw)
			if reason.is_empty():
				return {"state": "mounted", "reason": "", "position": at, "yaw": yaw}
			if not _unseat(save, bike, placed, heading):
				return {"state": "unverified", "reason": reason}
		else:
			reason = str(applied.get("reason", "")) if applied is Dictionary else ""
			reason = "the bicycle refused the saved spot" if reason.is_empty() else reason
	return _standing(level, reason)

static func _pose_refusal(save, bike: Node, at: Vector3, yaw: float) -> String:
	if not save._in_bounds(at) or save._inside_closed_shop(at):
		return "its saved spot is closed"
	if not residents_clear(save.level, at, yaw):
		return "someone is standing there"
	return str(bike.pose_blocker(at, yaw))

## After restore_pose: the bicycle's own facts must show this explorer seated, still
## and grounded at the saved pose; the hook's "ok" alone is not proof.
static func _verify(level, bike: Node, at: Vector3, yaw: float) -> String:
	var facts = bike.persistence_state()
	var motion := _motion_blocker(facts, _still(bike))
	if not motion.is_empty():
		return "the bicycle did not settle with you seated (%s)" % motion
	if not level.player.is_seated() or level.player.get("seated_vehicle") != bike:
		return "you were not seated on the bicycle"
	var seat: Vector3 = facts.position
	if Vector2(seat.x - at.x, seat.z - at.z).length() > PLANAR_TOLERANCE or absf(seat.y - at.y) > RISE_TOLERANCE \
		or absf(angle_difference(float(facts.yaw), yaw)) > YAW_TOLERANCE:
		return "the bicycle came to rest away from its saved spot"
	if Vector2(level.player.global_position.x - seat.x, level.player.global_position.z - seat.z).length() > PLANAR_TOLERANCE:
		return "you were not seated on the bicycle"
	return ""

## An unverifiable mount is undone through the bicycle (never by moving a seated
## explorer), back to the standing spot the load already checked.
static func _unseat(save, bike: Node, at: Vector3, heading: float) -> bool:
	var player = save.level.player
	if player.is_seated() and bool(bike.get("active")) and bike.has_method("recovery_exit_at"):
		bike.recovery_exit_at(at, heading)
	if player.is_seated():
		return false
	save._put_player(at, heading)
	return true

static func _standing(level, reason: String) -> Dictionary:
	return {"state": "standing", "reason": reason, "parked": _park(level)}

static func _park(level) -> String:
	var bike = level.get("bicycle") if level != null else null
	if not is_instance_valid(bike) or not bike.has_method("park_beside_explorer"):
		return "unchanged"
	var parked = bike.park_beside_explorer()
	var ok: bool = typeof(parked) == TYPE_NIL or _is_true(parked) or (parked is Dictionary and _is_true(parked.get("ok")))
	return "parked" if ok else "not parked"

## The bicycle's published facts must agree with its own verdict: whatever the
## solver says, a moving, airborne or crashed frame is never written.
static func _motion_blocker(facts, still: float) -> String:
	if not facts is Dictionary or not _is_true(facts.get("mounted")):
		return "bicycle seat state is changing"
	if not _is_false(facts.get("crashed")):
		return "recovering from a bicycle crash"
	if not _is_true(facts.get("grounded")) or not _is_false(facts.get("airborne")):
		return "land the bicycle before saving"
	if not _number(facts.get("speed"), -still, still) or not _number(facts.get("planar_speed"), 0.0, still) \
		or not _number(facts.get("slip", 0.0), 0.0, still):
		return "stop the bicycle before saving"
	if facts.has("steady") and not _is_true(facts.steady):
		return "steady the bicycle before saving"
	var at = facts.get("position")
	if not at is Vector3 or not at.is_finite() or not _number(facts.get("yaw"), -100000.0, 100000.0):
		return "bicycle seat state is changing"
	return ""

static func _still(bike: Node) -> float:
	var declared = bike.get("SAVE_STILL_SPEED")
	return float(declared) if _number(declared, 0.0, 0.5) else STILL_SPEED

## Type-checked flags: a missing or non-bool fact never compares as safe.
static func _is_true(value) -> bool:
	return value is bool and value

static func _is_false(value) -> bool:
	return value is bool and not value

static func _number(value, low: float, high: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) >= low and float(value) <= high

static func _integer(value, low: int, high: int) -> bool:
	return _number(value, low, high) and float(value) == floorf(float(value))

static func _vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
