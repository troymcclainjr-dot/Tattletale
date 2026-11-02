extends RefCounted
## The ambulance's own driver (city_emergency_response.gd). It follows a planned
## path the way traffic cars follow theirs: the traffic network's lanes and
## validated junction connectors (planned by city_police_lanes.gd) and, at the
## hospital, the canopy's painted ambulance approach. Every step is ground-snapped
## to real terrain and paving and swept with the ambulance's own compound hull
## against buildings, props, people, the explorer and cars: a step that would
## touch anything is not taken at all, so nothing is passed through and nothing
## is teleported. Speed comes from path curvature, the stop at the end of the
## leg, traffic read by position (cars far from the explorer have no collider),
## one box sweep for people and structures ahead, and yielding at junctions.
## Bounded per physics step while moving: six hull queries and five ground rays;
## sensing at 10 Hz.

const Lanes := preload("res://scripts/city/city_police_lanes.gd")
const Driver := preload("res://scripts/city/city_police_driver.gd")
const Collision := preload("res://scripts/city/city_car_collision.gd")
const Models := preload("res://scripts/city/city_car_models.gd")

const KIND := "minivan"
## Buildings/props, the explorer, people and cars. Terrain is handled by rays.
const HULL_MASK := 2 | 4 | 8 | 16
const SENSE_MASK := 2 | 4 | 8
## Terrain and paving (the hospital canopy apron is building paving, layer 2).
const GROUND_MASK := 1 | 2
const ACCEL := 2.6
const BRAKE := 5.0
const LATERAL := 4.0
const STEP_UP := 0.3
const MAX_SLOPE := 0.7
const SENSE_INTERVAL := 0.1
const CAR_CORRIDOR := 2.4
const CAR_LENGTH := 4.7
const STOP_GAP := 2.5
const PERSON_GAP := 3.5
const STRUCTURE_GAP := 1.5
const JUNCTION_SPEED := 4.5

var level: Node
var traffic: Node
var lanes
var body: Node3D
var half_length := 2.29
var parts: Array[Dictionary] = []
## {points, sums, limits, length, kind, cap, reverse, junctions}; {} = parked.
var leg: Dictionary = {}
var s := 0.0
var cursor := 0
var speed := 0.0
var odometer := 0.0
## Lights on: a red signal is a yield, not a stop (crossing traffic still is).
var emergency := false
## The service asks the car to stop where it is (staging short of a scene).
var hold := false
## Seconds the car wanted to move but could not, and why (vehicle, person,
## structure, yield, hull, terrain, hold). Reset by real movement.
var wait_time := 0.0
var wait_reason := ""
var obstacle := INF
var obstacle_kind := ""
var obstacle_speed := 0.0
var junction: Dictionary = {}
var counters := {"steps": 0, "blocked_steps": 0, "hull_queries": 0, "rays": 0, "senses": 0, "yields": 0}
var _sense_left := 0.0
var _yield_time := 0.0
var _cleared: Dictionary = {}
var _connector_hulls: Dictionary = {}
## Shared traffic ownership survives route replacement while the body still
## occupies a junction. Geometry is stored independently of the route cursor.
var _junction_leases: Dictionary = {}
var _heights := PackedFloat32Array()
var _pending_reason := ""
var _ray := PhysicsRayQueryParameters3D.new()
var _hull := PhysicsShapeQueryParameters3D.new()
var _box := PhysicsShapeQueryParameters3D.new()

func setup(owner_level: Node, owner_traffic: Node, owner_lanes, owner_body: Node3D) -> void:
	level = owner_level
	traffic = owner_traffic
	lanes = owner_lanes
	body = owner_body
	parts = Collision.parts(KIND)
	var size := Models.dimensions(KIND)
	half_length = size.z * 0.5
	_ray.collision_mask = GROUND_MASK
	_ray.hit_back_faces = false
	_hull.margin = 0.02
	_hull.collision_mask = HULL_MASK
	var box := BoxShape3D.new()
	box.size = Vector3(size.x + 0.1, 1.4, 0.6)
	_box.shape = box
	_box.margin = 0.02
	_box.collision_mask = SENSE_MASK

## A leg is driven in path order. `reverse`: the body faces against the travel
## direction (backing into the bay). extra: {sums, junctions, slow_until,
## slow_cap} — the off-road hospital approach is driven at slow_cap.
func set_leg(points: PackedVector3Array, kind: String, cap: float, reverse := false, extra := {}) -> void:
	_update_junction_leases()
	if points.size() < 2:
		clear_leg()
		return
	var sums: PackedFloat64Array = extra.get("sums", PackedFloat64Array())
	if sums.size() != points.size():
		sums = Lanes.cumulative(points)
	var limits := Driver.curve_limits(points, LATERAL, cap)
	var slow_until := float(extra.get("slow_until", -1.0))
	var slow_cap := float(extra.get("slow_cap", cap))
	if slow_until > 0.0:
		for i in points.size():
			if sums[i] <= slow_until:
				limits[i] = minf(limits[i], slow_cap)
	leg = {"points": points, "sums": sums, "limits": limits, "length": sums[sums.size() - 1], "kind": kind, "cap": cap,
		"reverse": reverse, "junctions": extra.get("junctions", []), "segments": extra.get("segments", [])}
	_release_unused_approaches()
	s = 0.0
	cursor = 0
	if is_instance_valid(body):
		# Resume from where the car actually is along the new path, never from
		# a point behind it (a stop a little short of the previous leg's end).
		var tracked := Driver.track(points, sums, 0, body.global_position, 16)
		if float(tracked.lateral) <= 1.0:
			s = clampf(float(tracked.s), 0.0, float(leg.length))
			cursor = int(tracked.cursor)
	_cleared = {}
	_connector_hulls = {}
	_yield_time = 0.0
	_sense_left = 0.0
	obstacle = INF
	obstacle_kind = ""
	obstacle_speed = 0.0
	junction = {}
	wait_time = 0.0
	wait_reason = ""

func clear_leg() -> void:
	_update_junction_leases()
	leg = {}
	_release_unused_approaches()
	s = 0.0
	cursor = 0
	speed = 0.0
	wait_time = 0.0
	wait_reason = ""
	junction = {}
	obstacle = INF
	obstacle_kind = ""

func kind() -> String:
	return str(leg.get("kind", ""))

## The lane the car is on at path distance `at` (a connector reports the lane
## it leads into); -1 off the lanes (the hospital approach, a curb pull-in).
func lane_at(at: float) -> int:
	var lane := -1
	for segment in leg.get("segments", []):
		if segment is Dictionary and float(segment.get("s", 0.0)) <= at + 0.01:
			lane = int(segment.get("lane", -1))
	return lane

func remaining() -> float:
	return maxf(0.0, float(leg.get("length", 0.0)) - s) if not leg.is_empty() else 0.0

## The leg is driven to its end and the car has stopped there.
func finished() -> bool:
	return not leg.is_empty() and remaining() <= 0.6 and speed < 0.3

## The flat direction the car is travelling (backwards along its body when reversing).
func travel_direction() -> Vector3:
	if not is_instance_valid(body):
		return Vector3.FORWARD
	var forward := Vector3(body.global_basis.z.x, 0.0, body.global_basis.z.z)
	forward = forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD
	return -forward if bool(leg.get("reverse", false)) else forward

## Forget the previous step's ground heights (after a placement, not a drive).
func reset_ground() -> void:
	_heights = PackedFloat32Array()

## One physics step. Returns {moved, blocked}; blocked names why a wanted step
## was not taken ("terrain" or "hull"). Holding or yielding is not a block.
func tick(delta: float) -> Dictionary:
	var result := {"moved": 0.0, "blocked": ""}
	_update_junction_leases()
	if leg.is_empty() or not is_instance_valid(body) or not body.is_inside_tree():
		speed = 0.0
		return result
	_sense(delta)
	var target := _target_speed()
	speed = move_toward(speed, target, (ACCEL if target > speed else BRAKE) * delta)
	if speed < 0.02:
		speed = 0.0
		if target < 0.05 and remaining() > 0.6:
			wait_time += delta
			wait_reason = _pending_reason if not _pending_reason.is_empty() else "stopped"
		return result
	var points: PackedVector3Array = leg.points
	var sums: PackedFloat64Array = leg.sums
	var next_s := minf(float(leg.length), s + speed * delta)
	if next_s <= s + 0.0001:
		speed = 0.0
		return result
	var point := Driver.point_at(points, sums, next_s, cursor)
	# A projected route cursor is not permission to absorb a lateral offset.
	# Service routes must join from the actual pose; reject an unjoined leg so
	# bounded route recovery can handle it without moving the body sideways.
	if Lanes.flat(body.global_position, point) > speed * delta + 0.005:
		return _blocked(result, "route", delta)
	var direction := Driver.direction_at(points, sums, next_s, cursor)
	if direction == Vector3.ZERO:
		direction = travel_direction()
	var heading := atan2(direction.x, direction.z) + (PI if bool(leg.reverse) else 0.0)
	var ground := ground_pose(point, heading)
	if ground.is_empty():
		return _blocked(result, "terrain", delta)
	var pose: Transform3D = ground.transform
	if not _sweep_clear(body.global_transform, pose):
		return _blocked(result, "hull", delta)
	body.global_transform = pose
	_heights = ground.heights
	result.moved = next_s - s
	odometer += next_s - s
	s = next_s
	while cursor < points.size() - 2 and sums[cursor + 1] < s:
		cursor += 1
	wait_time = 0.0
	wait_reason = ""
	counters.steps = int(counters.steps) + 1
	return result

func stop() -> void:
	speed = 0.0

func _blocked(result: Dictionary, why: String, delta: float) -> Dictionary:
	speed = 0.0
	counters.blocked_steps = int(counters.blocked_steps) + 1
	wait_time += delta
	wait_reason = why
	result.blocked = why
	return result

## Five rays (centre, front, back and both sides) onto terrain and paving.
## {transform, heights} or {} when there is no drivable support: a riser taller
## than a curb since the previous step, a steep slope, or a hit on something's side.
## `reference_y`: height to start from (default: the higher of the car and point).
func ground_pose(at: Vector3, heading: float, reference_y := INF, continuous := true) -> Dictionary:
	var space := _space()
	if space == null:
		return {}
	var forward := Vector3(sin(heading), 0.0, cos(heading))
	var right := Vector3(forward.z, 0.0, -forward.x)
	var base := reference_y
	if not is_finite(base):
		base = maxf(body.global_position.y, at.y) if is_instance_valid(body) else at.y
	var top := base + STEP_UP + 0.6
	var exclude: Array[RID] = []
	if is_instance_valid(body) and body is CollisionObject3D:
		exclude.append((body as CollisionObject3D).get_rid())
	_ray.exclude = exclude
	var heights := PackedFloat32Array()
	for offset in [Vector3.ZERO, forward * 1.35, -forward * 1.35, right * 0.8, -right * 0.8]:
		var point: Vector3 = at + offset
		_ray.from = Vector3(point.x, top, point.z)
		_ray.to = Vector3(point.x, top - 6.0, point.z)
		counters.rays = int(counters.rays) + 1
		var hit := space.intersect_ray(_ray)
		if hit.is_empty() or Vector3(hit.normal).y < 0.82:
			return {}
		heights.append(float(Vector3(hit.position).y))
	if continuous and _heights.size() == heights.size():
		for i in heights.size():
			if heights[i] - _heights[i] > STEP_UP:
				return {}
	var pitch := (heights[1] - heights[2]) / 2.7
	var roll := (heights[3] - heights[4]) / 1.6
	if absf(pitch) > MAX_SLOPE or absf(roll) > MAX_SLOPE:
		return {}
	forward.y = pitch
	right.y = roll
	forward = forward.normalized()
	var up := forward.cross(right).normalized()
	right = up.cross(forward).normalized()
	var origin := Vector3(at.x, (heights[1] + heights[2] + heights[3] + heights[4]) * 0.25 + 0.025, at.z)
	return {"transform": Transform3D(Basis(right, up, forward), origin), "heights": heights}

## The ambulance's convex hull parts at `pose`, touching anything in `mask`.
func pose_clear(pose: Transform3D, mask := HULL_MASK) -> bool:
	var space := _space()
	if space == null:
		return false
	var exclude: Array[RID] = []
	if is_instance_valid(body) and body is CollisionObject3D:
		exclude.append((body as CollisionObject3D).get_rid())
	_hull.exclude = exclude
	_hull.collision_mask = mask
	_hull.motion = Vector3.ZERO
	var clear := true
	for part in parts:
		_hull.shape = part.shape
		_hull.transform = pose
		counters.hull_queries = int(counters.hull_queries) + 1
		if not space.intersect_shape(_hull, 1).is_empty():
			clear = false
			break
	_hull.collision_mask = HULL_MASK
	return clear

## Each hull part swept along the translation, then tested at the final
## (possibly turned) pose. Anything touched blocks the whole step.
func _sweep_clear(from: Transform3D, to: Transform3D) -> bool:
	var space := _space()
	if space == null:
		return false
	var exclude: Array[RID] = []
	if body is CollisionObject3D:
		exclude.append((body as CollisionObject3D).get_rid())
	_hull.exclude = exclude
	_hull.collision_mask = HULL_MASK
	var motion := to.origin - from.origin
	for part in parts:
		_hull.shape = part.shape
		_hull.transform = from
		_hull.motion = motion
		counters.hull_queries = int(counters.hull_queries) + 1
		var fractions := space.cast_motion(_hull)
		if fractions.size() < 2 or fractions[0] < 1.0:
			_hull.motion = Vector3.ZERO
			return false
		_hull.transform = to
		_hull.motion = Vector3.ZERO
		counters.hull_queries = int(counters.hull_queries) + 1
		if not space.intersect_shape(_hull, 1).is_empty():
			return false
	return true

# --------------------------------------------------------------- speed and sensing

func _target_speed() -> float:
	_pending_reason = ""
	if hold:
		_pending_reason = "hold"
		return 0.0
	var cap := float(leg.cap)
	var horizon := clampf(speed * speed / (2.0 * BRAKE) + 12.0, 12.0, 60.0)
	var target := minf(cap, Driver.allowed_speed(leg.limits, leg.sums, cursor, s, horizon, BRAKE))
	target = minf(target, Driver.stop_speed(remaining() - 0.3, BRAKE))
	if is_finite(obstacle):
		var margin := STRUCTURE_GAP
		if obstacle_kind == "vehicle":
			margin = STOP_GAP
		elif obstacle_kind == "person":
			margin = PERSON_GAP
		var gap := obstacle - margin
		var follow := maxf(0.0, obstacle_speed)
		var limit := sqrt(follow * follow + 2.0 * BRAKE * gap) if gap > 0.0 else 0.0
		if limit < target:
			target = limit
			_pending_reason = obstacle_kind
	if not junction.is_empty():
		var distance := float(junction.entry_s) - s
		if bool(junction.get("yield", false)):
			var stop_at := Driver.stop_speed(distance - 1.0, BRAKE)
			if stop_at < target:
				target = stop_at
				_pending_reason = "yield"
		else:
			target = minf(target, sqrt(JUNCTION_SPEED * JUNCTION_SPEED + 2.0 * BRAKE * maxf(0.0, distance)))
	return maxf(0.0, target)

## 10 Hz: the nearest car on the path ahead (by position: distant cars have no
## collider), one box sweep for people and structures, and the junction state.
func _sense(delta: float) -> void:
	_sense_left -= delta
	if _sense_left > 0.0:
		return
	_sense_left = SENSE_INTERVAL
	counters.senses = int(counters.senses) + 1
	var horizon := clampf(speed * speed / (2.0 * BRAKE) + 16.0, 16.0, 48.0)
	var at := body.global_position
	var best := INF
	var found := ""
	var along_speed := 0.0
	var points: PackedVector3Array = leg.points
	var sums: PackedFloat64Array = leg.sums
	if traffic != null:
		for pool in [traffic.get("vehicles"), traffic.get("player_fleet")]:
			if not pool is Array:
				continue
			for other in pool:
				if not is_instance_valid(other) or not other is Node3D or other == body:
					continue
				var point: Vector3 = (other as Node3D).global_position
				if absf(point.x - at.x) > horizon + 6.0 or absf(point.z - at.z) > horizon + 6.0:
					continue
				var hit := _path_hit(point, s + horizon)
				if hit < 0.0:
					continue
				var gap := hit - s - CAR_LENGTH
				if gap < best:
					best = gap
					found = "vehicle"
					var direction := Driver.direction_at(points, sums, hit, cursor)
					var yaw := float(other.get("yaw")) if other.get("yaw") != null else 0.0
					var other_speed := float(other.get("speed")) if other.get("speed") != null else 0.0
					along_speed = other_speed * Vector3(sin(yaw), 0.0, cos(yaw)).dot(direction)
	var ahead := _sweep_ahead(minf(horizon, 22.0))
	if float(ahead.distance) < best:
		best = float(ahead.distance)
		found = str(ahead.kind)
		along_speed = 0.0
	obstacle = best
	obstacle_kind = found
	obstacle_speed = along_speed
	junction = _junction_state()

## Path distance where `point` comes within the car corridor of the path ahead, or -1.
func _path_hit(point: Vector3, s_end: float) -> float:
	var points: PackedVector3Array = leg.points
	var sums: PackedFloat64Array = leg.sums
	var i := cursor
	var best := -1.0
	var best_distance := CAR_CORRIDOR
	while i < points.size() - 1 and sums[i] <= s_end:
		var j := mini(i + 2, points.size() - 1)
		var a := points[i]
		var b := points[j]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var length_squared := ab.length_squared()
		var t := 0.0 if length_squared < 0.000001 else clampf(Vector2(point.x - a.x, point.z - a.z).dot(ab) / length_squared, 0.0, 1.0)
		var distance := (Vector2(a.x, a.z) + ab * t).distance_to(Vector2(point.x, point.z))
		if distance < best_distance:
			best_distance = distance
			best = sums[i] + (sums[j] - sums[i]) * t
		i = j
	return best if best >= s - 0.5 else -1.0

## People, the explorer and props or walls ahead: one box sweep from the
## leading bumper, no longer than the path stays straight or than the leg lasts.
func _sweep_ahead(reach: float) -> Dictionary:
	var none := {"distance": INF, "kind": ""}
	var space := _space()
	if space == null:
		return none
	var lead := travel_direction()
	var direction := Driver.direction_at(leg.points, leg.sums, s + 3.0, cursor)
	if direction == Vector3.ZERO:
		direction = lead
	var start := body.global_position + lead * (half_length + 0.4) + Vector3.UP * 0.95
	reach = minf(reach, _straight_reach(start, direction, reach))
	reach = minf(reach, remaining() + 0.5)
	if reach < 0.5:
		return none
	_box.transform = Transform3D(Basis.looking_at(direction, Vector3.UP), start)
	_box.motion = direction * reach
	var exclude: Array[RID] = []
	if body is CollisionObject3D:
		exclude.append((body as CollisionObject3D).get_rid())
	_box.exclude = exclude
	counters.hull_queries = int(counters.hull_queries) + 1
	var fractions := space.cast_motion(_box)
	if fractions.size() < 2 or fractions[0] >= 1.0:
		return none
	var what := "person"
	_box.transform = Transform3D(_box.transform.basis, start + direction * reach * minf(1.0, fractions[1] + 0.02))
	_box.motion = Vector3.ZERO
	counters.hull_queries = int(counters.hull_queries) + 1
	var info := space.get_rest_info(_box)
	if not info.is_empty():
		var other := instance_from_id(int(info.collider_id))
		if other is CollisionObject3D and ((other as CollisionObject3D).collision_layer & (4 | 8)) == 0:
			what = "structure"
	return {"distance": fractions[0] * reach + 0.4, "kind": what}

func _straight_reach(start: Vector3, direction: Vector3, reach: float) -> float:
	var points: PackedVector3Array = leg.points
	var sums: PackedFloat64Array = leg.sums
	var side := Vector3(direction.z, 0.0, -direction.x)
	var i := cursor
	while i < points.size() and sums[i] <= s + reach + CAR_LENGTH:
		var offset := Vector3(points[i].x - start.x, 0.0, points[i].z - start.z)
		var along := offset.dot(direction)
		if along > 0.0 and absf(offset.dot(side)) > 1.3:
			return maxf(0.0, along - 1.0)
		i += 2
	return reach

func _junction_state() -> Dictionary:
	_update_junction_leases()
	var junctions: Array = leg.get("junctions", [])
	for index in junctions.size():
		var entry: Dictionary = junctions[index]
		var entry_s := float(entry.get("s", 0.0))
		var leave := float(entry.get("exit_s", entry_s + 12.0))
		if leave < s:
			continue
		var distance := entry_s - s
		if distance > 30.0:
			_yield_time = 0.0
			return {}
		var key := str(index)
		var node := str(entry.get("node", ""))
		var owns := _owns_junction(node)
		if owns and (_cleared.has(key) or distance <= 0.5):
			_cleared[key] = true
			_yield_time = 0.0
			return {"entry_s": entry_s, "yield": false}
		var red := not emergency and bool(entry.get("signal", false)) and _signal_red(str(entry.get("axis", "")))
		var conflict := red or _crossing_traffic(entry)
		# Claim at the approach, before the nose/yaw enters the crossing. The
		# ordinary traffic controller consults this same ownership dictionary.
		if not conflict and distance <= 7.0 and not owns:
			conflict = not _claim_junction(entry)
		if conflict:
			_yield_time += SENSE_INTERVAL
			if _yield_time <= SENSE_INTERVAL + 0.001:
				counters.yields = int(counters.yields) + 1
			# Only a cleared conflict permits entry. The service owns bounded
			# replan/failure; elapsed waiting never makes cross traffic safe.
			return {"entry_s": entry_s, "yield": true}
		_yield_time = 0.0
		return {"entry_s": entry_s, "yield": false}
	return {}

func _owns_junction(node: String) -> bool:
	if not is_instance_valid(traffic):
		return true # A fixture without a traffic controller has no competing cars.
	var reservations = traffic.get("reservations")
	return reservations is Dictionary and reservations.get(node) == body

func _claim_junction(entry: Dictionary) -> bool:
	if not is_instance_valid(traffic):
		return true
	var node := str(entry.get("node", ""))
	if node.is_empty() or not traffic.has_method("claim_emergency_junction"):
		return false
	if not bool(traffic.claim_emergency_junction(body, node)):
		return false
	if not _junction_leases.has(node):
		var start := float(entry.get("s", s))
		var finish := float(entry.get("exit_s", start + 12.0))
		_junction_leases[node] = {"entry": Driver.point_at(leg.points, leg.sums, start),
			"inward": Driver.direction_at(leg.points, leg.sums, start),
			"exit": Driver.point_at(leg.points, leg.sums, finish),
			"outward": Driver.direction_at(leg.points, leg.sums, finish),
			"center": entry.get("center", body.global_position), "radius": float(entry.get("radius", 8.0)), "entered": false, "inside": false, "exit_armed": false}
	_update_junction_leases()
	return true

func _update_junction_leases() -> void:
	if not is_instance_valid(body) or not body.is_inside_tree():
		return
	for node in _junction_leases.keys():
		var lease: Dictionary = _junction_leases[node]
		var position := body.global_position
		# Include the front overhang: cancelling a route with its nose already
		# inside cannot open the intersection to somebody else.
		if (position - (lease.entry as Vector3)).dot(lease.inward) >= -half_length - 0.2:
			lease.entered = true
		var center_distance := Lanes.flat(position, lease.center)
		if center_distance <= float(lease.radius) + half_length + 0.5:
			lease.inside = true
		if not bool(lease.entered):
			continue
		var outgoing: Vector3 = lease.outward
		var side := Vector3(outgoing.z, 0.0, -outgoing.x)
		var offset: Vector3 = position - (lease.exit as Vector3)
		if Vector2(offset.x, offset.z).length() <= half_length + 2.0 and body.global_basis.z.dot(outgoing) > 0.5:
			lease.exit_armed = true
		var rear := (half_length + 0.12) * absf(body.global_basis.z.dot(outgoing)) + (Models.dimensions(KIND).x * 0.5 + 0.10) * absf(body.global_basis.x.dot(outgoing))
		var cleared_exit := bool(lease.exit_armed) and offset.dot(outgoing) > rear + 0.5 and absf(offset.dot(side)) < 3.0
		# A replan may use another exit. Only a body wholly outside the junction
		# can release that old ownership; stopped bodies have no timeout.
		var cleared_other_exit := bool(lease.inside) and center_distance > float(lease.radius) + half_length + 1.0
		if cleared_exit or cleared_other_exit:
			_release_junction(str(node))

func _release_unused_approaches() -> void:
	var needed: Dictionary = {}
	for entry in leg.get("junctions", []):
		needed[str(entry.get("node", ""))] = true
	for node in _junction_leases.keys():
		if not needed.has(node) and not bool(_junction_leases[node].entered):
			_release_junction(str(node))

func _release_junction(node: String) -> void:
	if is_instance_valid(traffic) and traffic.has_method("release_emergency_junction"):
		traffic.release_emergency_junction(body, node)
	_junction_leases.erase(node)

## Only reset/relocation/teardown may force release an occupied junction.
func release_junctions() -> void:
	for node in _junction_leases.keys():
		_release_junction(str(node))

func _signal_red(axis: String) -> bool:
	var signals = traffic.get("signals") if traffic != null else null
	return signals != null and signals.has_method("phase") and str(signals.phase(axis)) != "Green"

## A car moving through the junction, approaching it across our way, or
## holding traffic's own reservation of it.
func _crossing_traffic(entry: Dictionary) -> bool:
	if traffic == null:
		return false
	var center: Vector3 = entry.get("center", body.global_position)
	var radius := float(entry.get("radius", 8.0))
	var ours := Driver.direction_at(leg.points, leg.sums, float(entry.get("s", s)) + 2.0, cursor)
	var reservations = traffic.get("reservations")
	if reservations is Dictionary:
		var holder = (reservations as Dictionary).get(str(entry.get("node", "")))
		if is_instance_valid(holder) and holder != body:
			return true # Every holder owns the junction, including aligned cars.
	for pool in [traffic.get("vehicles"), traffic.get("player_fleet")]:
		if not pool is Array:
			continue
		for other in pool:
			if not is_instance_valid(other) or not other is Node3D or other == body:
				continue
			var point: Vector3 = (other as Node3D).global_position
			var distance := Lanes.flat(point, center)
			if distance > radius + 8.0:
				continue
			var yaw := float(other.get("yaw")) if other.get("yaw") != null else 0.0
			var heading := Vector3(sin(yaw), 0.0, cos(yaw))
			var other_speed := float(other.get("speed")) if other.get("speed") != null else 0.0
			# A waiting car is still solid. Its nose may occupy the swept turn
			# even when its centre lies outside the moving-car corridor. Yield
			# before entry so it can clear, rather than meet it midway through.
			if absf(other_speed) <= 1.0 and _stationary_connector_conflict(entry, other):
				return true
			if heading.dot(ours) > 0.8:
				continue # Same way as us: following is the obstacle scan's job.
			var toward := Vector3(center.x - point.x, 0.0, center.z - point.z)
			if distance <= radius and absf(other_speed) > 0.5:
				return true
			if absf(other_speed) > 1.0 and toward.length() > 0.1 and heading.dot(toward.normalized()) * signf(other_speed) > 0.3:
				return true
	return false

func _stationary_connector_conflict(entry: Dictionary, other: Node3D) -> bool:
	var key := "%s:%s" % [str(entry.get("node", "")), str(entry.get("s", 0.0))]
	if not _connector_hulls.has(key):
		var start := float(entry.get("s", 0.0))
		var finish := float(entry.get("exit_s", start + 12.0))
		var steps := ceili(maxf(0.0, finish - start))
		if steps < 1 or steps > 48:
			return true # Invalid/unbounded connector never grants permission.
		var footprints: Array = []
		for i in steps + 1:
			var along := lerpf(start, finish, float(i) / float(steps))
			var point := Driver.point_at(leg.points, leg.sums, along)
			var direction := Driver.direction_at(leg.points, leg.sums, along)
			var grounded := ground_pose(point, atan2(direction.x, direction.z), point.y + 1.2, false)
			if grounded.is_empty():
				return true
			footprints.append(Collision.footprint(grounded.transform, KIND))
		_connector_hulls[key] = footprints
	var kind := str(other.get("prototype_kind")) if other.get("prototype_kind") != null else "minivan"
	if kind.is_empty():
		kind = "minivan"
	var parked := Collision.footprint(other.global_transform, kind)
	for footprint in _connector_hulls[key]:
		if Collision.footprints_overlap(footprint, parked, 0.20):
			return true
	return false

func _space() -> PhysicsDirectSpaceState3D:
	if is_instance_valid(body) and body.is_inside_tree():
		var world := body.get_world_3d()
		if world != null:
			return world.direct_space_state
	return null

func get_status() -> Dictionary:
	return {"kind": kind(), "s": s, "length": float(leg.get("length", 0.0)), "remaining": remaining(), "speed": speed,
		"reverse": bool(leg.get("reverse", false)), "emergency": emergency, "hold": hold, "wait_time": wait_time,
		"wait_reason": wait_reason, "obstacle": obstacle, "obstacle_kind": obstacle_kind, "odometer": odometer,
		"junction_leases": _junction_leases.keys(), "counters": counters.duplicate()}
