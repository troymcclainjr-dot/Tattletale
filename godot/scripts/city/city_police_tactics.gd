extends RefCounted
## Physics helpers for police incident response (city_police_assistance.gd):
## forward-only swept walking, sight rays and the fire-safety gates checked
## before every police round. Holds only reused query objects and counters;
## every call is a bounded number of rays or shape queries.

const EYE_HEIGHT := 1.3
const CHEST_HEIGHT := 1.2
## Buildings (2), terrain (1) and cars/solid props (16) block sight; people do not.
const SIGHT_MASK := 1 | 2 | 16
## A round meets everything solid, the player (4) and people (8).
const BULLET_MASK := 1 | 2 | 4 | 8 | 16
const PEOPLE_MASK := 4 | 8
const MOVE_ARRIVED := 0
const MOVE_TURNING := 1
const MOVE_MOVED := 2
const MOVE_BLOCKED := 3
const TURN_RATE := 4.5
const ALIGNED := 0.035
## Nobody but the suspect may stand this close to the aim point.
const BYSTANDER_RADIUS := 1.1
## A miss or a round passing through travels this far beyond the suspect.
const BACKSTOP := 6.0
## The caller and other officers stay this far from the whole line of fire.
const PROTECTED_CLEARANCE := 1.6

var space: PhysicsDirectSpaceState3D
var rays := 0
var shape_queries := 0
var _ray := PhysicsRayQueryParameters3D.new()
var _people_query := PhysicsShapeQueryParameters3D.new()
var _link_query := PhysicsShapeQueryParameters3D.new()
var _probe_query: PhysicsShapeQueryParameters3D

func _init() -> void:
	_ray.hit_from_inside = false
	var ball := SphereShape3D.new()
	ball.radius = BYSTANDER_RADIUS
	_people_query.shape = ball
	_people_query.collision_mask = PEOPLE_MASK
	var link := SphereShape3D.new()
	link.radius = 0.26
	_link_query.shape = link
	_link_query.collision_mask = 2 | 16
	_link_query.margin = 0.02

static func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

static func eye_of(body: Node3D) -> Vector3:
	return body.global_position + Vector3.UP * EYE_HEIGHT

static func chest_of(body: Node3D) -> Vector3:
	return body.global_position + Vector3.UP * CHEST_HEIGHT

static func forward_of(actor) -> Vector3:
	var yaw := float(actor.get("yaw"))
	return Vector3(sin(yaw), 0.0, cos(yaw))

# --------------------------------------------------------------- body upkeep

## Combat's convention while a system other than CityNpcs owns the body: keep the
## speech timer running and report no stale velocity.
static func tick_body(actor, delta: float) -> void:
	actor._clock += delta
	actor._speech_remaining = maxf(0.0, float(actor._speech_remaining) - delta)
	if actor._speech_label != null:
		actor._speech_label.visible = float(actor._speech_remaining) > 0.0
	actor.moving = false
	actor.velocity = Vector3.ZERO

## Turn in place toward a heading. True once facing it.
static func face(actor, wanted: float, delta: float, tolerance := ALIGNED) -> bool:
	actor.yaw = rotate_toward(float(actor.yaw), wanted, delta * TURN_RATE)
	if actor.puppet != null:
		actor.puppet.g.rotation.y = actor.yaw
	return absf(angle_difference(float(actor.yaw), wanted)) <= tolerance

static func heading_to(from: Vector3, to: Vector3, fallback: float) -> float:
	var offset := Vector3(to.x - from.x, 0.0, to.z - from.z)
	return atan2(offset.x, offset.z) if offset.length() > 0.05 else fallback

## Turn first, then one forward step on walkable ground (22 cm rise at most),
## swept by the body's own collider: walls, cars and people stop it.
static func walk(actor, destination: Vector3, delta: float, speed: float) -> int:
	var offset: Vector3 = destination - actor.global_position
	offset.y = 0.0
	if offset.length() < 0.12:
		return MOVE_ARRIVED
	if not face(actor, atan2(offset.x, offset.z), delta):
		return MOVE_TURNING
	var motion := Vector3(sin(actor.yaw), 0.0, cos(actor.yaw)) * minf(speed * delta, offset.length())
	var ground: Dictionary = actor.walking_ground_at(actor.global_position + motion)
	if ground.is_empty() or Vector3(ground.normal).y < 0.7:
		return MOVE_BLOCKED
	var rise: float = Vector3(ground.position).y + 0.012 - actor.global_position.y
	if absf(rise) > 0.23:
		return MOVE_BLOCKED
	var before: Vector3 = actor.global_position
	actor.move_and_collide(motion + Vector3.UP * rise)
	var travelled: float = actor.global_position.distance_to(before)
	actor.distance_walked += travelled
	actor.moving = travelled > 0.001
	actor.velocity = (actor.global_position - before) / maxf(delta, 0.0001)
	if actor.puppet != null:
		actor.puppet.phase += travelled * 3.5
	return MOVE_MOVED if actor.moving else MOVE_BLOCKED

# --------------------------------------------------------------- queries

func first_hit(from: Vector3, to: Vector3, skip: Array[RID], mask: int) -> Dictionary:
	if space == null or not from.is_finite() or not to.is_finite() or from.distance_squared_to(to) < 0.000001:
		return {}
	rays += 1
	_ray.from = from
	_ray.to = to
	_ray.collision_mask = mask
	_ray.exclude = skip
	return space.intersect_ray(_ray)

## One sight ray; only buildings, terrain and cars occlude.
func sees(from: Vector3, to: Vector3, skip: Array[RID]) -> bool:
	if space == null or not from.is_finite() or not to.is_finite():
		return false
	return first_hit(from, to, skip, SIGHT_MASK).is_empty()

## Swept walking link (ankle-to-hip sphere) against buildings, props and cars.
func link_clear(a: Vector3, b: Vector3) -> bool:
	if space == null or not a.is_finite() or not b.is_finite():
		return false
	if a.distance_squared_to(b) < 0.04:
		return true
	shape_queries += 1
	var from := a + Vector3.UP * 0.65
	_link_query.transform = Transform3D(Basis.IDENTITY, from)
	_link_query.motion = b + Vector3.UP * 0.65 - from
	var fraction := space.cast_motion(_link_query)
	return fraction.size() < 2 or fraction[0] >= 0.999

## Standing room: walkable terrain under `point` and a capsule clear of
## buildings, props and cars. {} when not.
func walkable(point: Vector3) -> Dictionary:
	if space == null or not point.is_finite():
		return {}
	var none: Array[RID] = []
	var ground := first_hit(point + Vector3.UP * 1.6, point - Vector3.UP * 2.0, none, 1)
	if ground.is_empty() or Vector3(ground.normal).y < 0.75:
		return {}
	var foot: Vector3 = Vector3(ground.position) + Vector3.UP * 0.012
	if _probe_query == null:
		_probe_query = PhysicsShapeQueryParameters3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.3
		capsule.height = 1.6
		_probe_query.shape = capsule
		_probe_query.collision_mask = 2 | 16
		_probe_query.margin = 0.02
	shape_queries += 1
	_probe_query.transform = Transform3D(Basis.IDENTITY, foot + Vector3.UP * 0.9)
	if not space.intersect_shape(_probe_query, 1).is_empty():
		return {}
	return {"position": foot}

static func is_person(collider) -> bool:
	return collider is CollisionObject3D and ((collider as CollisionObject3D).collision_layer & PEOPLE_MASK) != 0

## "" when a round may be fired at `suspect`, otherwise why the officer holds.
## The aimed line must meet the suspect first; nobody else may stand near the
## aim point, in the deliberate miss line or behind the suspect; the caller and
## other officers must be clear of the whole line. Five bounded queries.
func fire_clearance(muzzle: Vector3, aim: Vector3, miss: Vector3, suspect: CollisionObject3D,
		officer: CollisionObject3D, protected: Array) -> String:
	if space == null or not is_instance_valid(suspect) or not is_instance_valid(officer):
		return "no_space"
	var direction := (aim - muzzle).normalized()
	var own: Array[RID] = [officer.get_rid()]
	var line := first_hit(muzzle, aim + direction * 0.6, own, BULLET_MASK)
	if line.is_empty():
		return "no_clear_line"
	if line.collider != suspect:
		return "person_in_line" if is_person(line.collider) else "no_clear_line"
	var both: Array[RID] = [officer.get_rid(), suspect.get_rid()]
	shape_queries += 1
	_people_query.transform = Transform3D(Basis.IDENTITY, aim)
	_people_query.exclude = both
	if not space.intersect_shape(_people_query, 1).is_empty():
		return "bystander_near_target"
	var wide := first_hit(muzzle, miss, both, BULLET_MASK)
	if not wide.is_empty() and is_person(wide.collider):
		return "person_in_miss_line"
	if not first_hit(aim + direction * 0.4, aim + direction * BACKSTOP, both, PEOPLE_MASK).is_empty():
		return "person_beyond_target"
	var end := aim + direction * BACKSTOP
	for point in protected:
		if point is Vector3 and (point as Vector3).is_finite():
			if Geometry3D.get_closest_point_to_segment(point, muzzle, end).distance_to(point) < PROTECTED_CLEARANCE:
				return "protected_near_line"
	return ""

## The physical path of one round (rays already proved the shot safe).
func trace(from: Vector3, to: Vector3, skip: Array[RID]) -> Dictionary:
	var hit := first_hit(from, to, skip, BULLET_MASK)
	return {"hit": hit, "endpoint": Vector3(hit.position) if not hit.is_empty() else to}
