extends CharacterBody3D
## Ejected bicycle rider: one bounded kinematic tumble rig, built once by the
## bicycle and reused (no ragdoll, no per-NPC physics). While a crash runs this
## body stands in for the explorer's seated "vehicle": the existing chase camera
## follows it, and every guard that respects a seated explorer (checkpoints,
## loads, phone, walking input) stays engaged. Its own origin is the ground under
## the rider, so position-based systems never see an airborne explorer.
## The rider is a swept sphere: every frame of flight, bounce and slide is a
## move_and_collide sweep, so walls, cars and roofs are hit, never crossed.
## While active the sphere sits on the explorer layer (4) so traffic stops for
## a rider lying in the road. Health, law, progression and NPCs are untouched.
## Contract: .work/pacifist-foundation/bike-contract.md section 4.

const RADIUS := 0.28
const GRAVITY := 22.0
const SWEEP_MASK := 1 | 2 | 8 | 16
const GROUND_MASK := 1 | 2
const WALKABLE := 0.55
const WALL_RESTITUTION := 0.28
const WALL_FRICTION := 0.35
const GROUND_RESTITUTION := 0.22
const GROUND_FRICTION := 7.5
const SPIN_DAMPING := 6.0
const SETTLE_SPEED := 0.3
const MAX_FLIGHT := 2.4
const MAX_SLIDE := 2.6
const DOWN_TIME := 0.85
const DOWN_MIN := 0.45
const GETUP_TIME := 0.7
## Farthest standing spot the rider visibly gets up toward (the nearby rings
## reach 1.35 m). Farther fallbacks (recent trail, mount point) are not walked
## to through whatever ruled the near ones out: the rider rises in place.
const GETUP_REACH := 1.5
## Where the chase camera looks above this rig's anchor (city_player's
## CHASE_TARGET_HEIGHT); the anchor only glides if that point can follow it.
const VIEW_HEIGHT := 1.45
const PIVOT_HEIGHT := 0.95
const HEAD_REACH := 0.85
const LYING_HEIGHT := 0.17
const MAX_TRACE := 600

var bike: CharacterBody3D
var player: Node3D
## Chase-camera API shared with seated vehicles (city_player._update_vehicle_camera).
var yaw := 0.0
var speed := 0.0
var phase := ""
var center := Vector3.ZERO
var body_velocity := Vector3.ZERO
var spin := Vector3.ZERO
var orientation := Basis.IDENTITY
var elapsed := 0.0
var phase_time := 0.0
var ground_point := Vector3.ZERO
var standing_spot := Vector3.INF
var standing_heading := 0.0
var get_up_requested := false
var sweeps := 0
var hits := 0
var ground_hits := 0
var wall_hits := 0
var max_height := 0.0
var launch_height := 0.0
## Bounded trace of sphere centres (tests audit every swept position).
var trace := PackedVector3Array()
var _body: CharacterBody3D
var _shape: CollisionShape3D
var _pivot: Node3D
var _puppet: Puppet
var _lying := Basis.IDENTITY
var _getup_from := Transform3D.IDENTITY
## Ground under the lying rider and the spot the get-up blends toward.
var _getup_ground := Vector3.ZERO
var _getup_target := Vector3.ZERO
var _getup_glide := false
var _grounded := false

func setup(owner_bike: CharacterBody3D, explorer: Node3D) -> void:
	bike = owner_bike
	player = explorer
	name = "BicycleCrashRig"
	top_level = true
	collision_layer = 0
	collision_mask = 0
	_body = CharacterBody3D.new()
	_body.name = "EjectedRider"
	_body.top_level = true
	_body.collision_layer = 0
	_body.collision_mask = SWEEP_MASK
	_shape = CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = RADIUS
	_shape.shape = sphere
	_body.add_child(_shape)
	add_child(_body)
	_body.add_collision_exception_with(bike)
	if player is PhysicsBody3D:
		_body.add_collision_exception_with(player as PhysicsBody3D)
	_pivot = Node3D.new()
	_pivot.name = "TumblePivot"
	_pivot.top_level = true
	add_child(_pivot)
	_puppet = Cast.person("two_pack", _pivot)
	_puppet.g.name = "EjectedRiderPuppet"
	_puppet.g.position = Vector3(0.0, -PIVOT_HEIGHT, 0.0)
	_pivot.visible = false

func is_active() -> bool:
	return not phase.is_empty()

func is_down() -> bool:
	return phase == "down"

## True once the rider has rested long enough (or asked early) to stand up.
func ready_to_stand() -> bool:
	return phase == "down" and (phase_time >= DOWN_TIME or (get_up_requested and phase_time >= DOWN_MIN))

## A rider sphere centred here overlaps nothing solid (people and cars count).
func is_clear(at: Vector3) -> bool:
	if not at.is_finite() or not is_inside_tree():
		return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _shape.shape
	query.transform = Transform3D(Basis.IDENTITY, at)
	query.collision_mask = SWEEP_MASK
	query.exclude = _excluded()
	query.margin = 0.002
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func begin(start: Vector3, launch: Vector3, angular: Vector3, heading: float) -> bool:
	if not is_inside_tree() or not start.is_finite() or not launch.is_finite() or not angular.is_finite() or not is_finite(heading):
		return false
	phase = "flight"
	elapsed = 0.0
	phase_time = 0.0
	yaw = heading
	center = start
	body_velocity = launch
	spin = angular
	orientation = Basis(Vector3.UP, heading)
	standing_spot = Vector3.INF
	standing_heading = heading
	get_up_requested = false
	sweeps = 0
	hits = 0
	ground_hits = 0
	wall_hits = 0
	trace = PackedVector3Array()
	_grounded = false
	_body.global_position = start
	_body.collision_layer = 4
	_shape.disabled = false
	launch_height = start.y
	max_height = start.y
	ground_point = _ground_below(start, bike.global_position.y)
	global_position = ground_point
	velocity = launch
	speed = Vector2(launch.x, launch.z).length()
	_pivot.visible = true
	_place_rig()
	_pose(0.0)
	return true

## One physics step of the presentation. Returns the phase ("done" when standing).
func step(delta: float) -> String:
	if phase.is_empty() or phase == "done" or delta <= 0.0:
		return phase
	elapsed += delta
	phase_time += delta
	match phase:
		"flight":
			_integrate(delta, false)
			if spin.length() > 0.001:
				orientation = (Basis(spin.normalized(), spin.length() * delta) * orientation).orthonormalized()
			if (_grounded and absf(body_velocity.y) < 1.2) or phase_time >= MAX_FLIGHT:
				_lying = _lying_basis()
				_enter("slide")
		"slide":
			_integrate(delta, true)
			spin *= exp(-SPIN_DAMPING * delta)
			orientation = orientation.slerp(_lying, 1.0 - exp(-7.0 * delta)).orthonormalized()
			var flat := Vector2(body_velocity.x, body_velocity.z).length()
			if (_grounded and flat < SETTLE_SPEED) or phase_time >= MAX_SLIDE:
				body_velocity = Vector3(0.0, minf(0.0, body_velocity.y), 0.0)
				# Re-check where the slide actually stopped (a wall may be close now).
				_lying = _lying_basis()
				_enter("down")
		"down":
			_integrate(delta, true)
			body_velocity.x = 0.0
			body_velocity.z = 0.0
			orientation = orientation.slerp(_lying, 1.0 - exp(-10.0 * delta)).orthonormalized()
		"getup":
			var t := clampf(phase_time / GETUP_TIME, 0.0, 1.0)
			var eased := t * t * (3.0 - 2.0 * t)
			var target := Transform3D(Basis(Vector3.UP, standing_heading), _getup_target + Vector3.UP * PIVOT_HEIGHT)
			_pivot.global_transform = _getup_from.interpolate_with(target, eased)
			# The visual rig rises from its lowered lying pivot; collision and
			# recovery traces must continue to describe the swept torso sphere.
			center = _body.global_position
			if t >= 1.0:
				_enter("done")
	_update_anchor()
	if phase != "getup" and phase != "done":
		_place_rig()
	_pose(delta)
	if trace.size() < MAX_TRACE:
		trace.append(center)
	return phase

## The bicycle picked a verified standing spot: blend from lying to standing.
## The explorer's anchor (this node's origin, which the chase camera and the
## seated explorer follow) moves with the blend, so standing up never ends in
## a jump of the camera's subject.
func begin_getup(spot: Vector3, heading: float) -> void:
	if phase != "down" or not spot.is_finite():
		return
	standing_spot = spot
	standing_heading = heading
	_getup_from = _pivot.global_transform
	_getup_ground = ground_point
	var reach := Vector2(spot.x - ground_point.x, spot.z - ground_point.z).length()
	# Standing spots are ground + 0.05 m, as the bicycle's recovery reports them.
	_getup_target = spot if reach <= GETUP_REACH else ground_point + Vector3.UP * 0.05
	# The recovery rays clear the body's path, not necessarily the camera's view
	# point above it (a rail at head height). If that is blocked the anchor stays
	# put, and the explorer's own camera glide (clamped by a sweep) takes over.
	_getup_glide = _view_path_clear(ground_point + Vector3.UP * VIEW_HEIGHT, _getup_target + Vector3.UP * (VIEW_HEIGHT - 0.05))
	_enter("getup")

## Hides the rig and releases the explorer layer (recovery, abort or teardown).
func finish() -> void:
	phase = ""
	phase_time = 0.0
	get_up_requested = false
	body_velocity = Vector3.ZERO
	spin = Vector3.ZERO
	velocity = Vector3.ZERO
	speed = 0.0
	if _body != null:
		_body.collision_layer = 0
	if _pivot != null:
		_pivot.visible = false

func get_status() -> Dictionary:
	return {"phase": phase, "elapsed": elapsed, "phase_time": phase_time, "center": center,
		"ground": ground_point, "velocity": body_velocity, "sweeps": sweeps, "hits": hits,
		"ground_hits": ground_hits, "wall_hits": wall_hits, "max_height": max_height,
		"launch_height": launch_height, "standing_spot": standing_spot, "visible": _pivot != null and _pivot.visible}

func rider_rid() -> RID:
	return _body.get_rid()

func _enter(next: String) -> void:
	phase = next
	phase_time = 0.0

func _excluded() -> Array[RID]:
	var rids: Array[RID] = [get_rid(), _body.get_rid()]
	if is_instance_valid(bike):
		rids.append(bike.get_rid())
	if player is CollisionObject3D:
		rids.append((player as CollisionObject3D).get_rid())
	return rids

func _is_actor_or_vehicle(collider: Object) -> bool:
	return collider is CollisionObject3D and ((collider as CollisionObject3D).collision_layer & (8 | 16)) != 0

## Gravity, swept motion, bounces and (on the ground) sliding friction.
func _integrate(delta: float, friction: bool) -> void:
	body_velocity.y = maxf(-30.0, body_velocity.y - GRAVITY * delta)
	if friction and _grounded:
		var flat := Vector3(body_velocity.x, 0.0, body_velocity.z).move_toward(Vector3.ZERO, GROUND_FRICTION * delta)
		body_velocity.x = flat.x
		body_velocity.z = flat.z
	var remaining := body_velocity * delta
	var touched_ground := false
	for iteration in 3:
		if remaining.length_squared() < 0.00000025:
			break
		sweeps += 1
		var hit := _body.move_and_collide(remaining, false, 0.002, false, 4)
		if hit == null:
			break
		hits += 1
		var normal := hit.get_normal()
		var collider := hit.get_collider()
		var actor := _is_actor_or_vehicle(collider)
		var into := body_velocity.dot(normal)
		if normal.y >= WALKABLE and not actor:
			touched_ground = true
			ground_hits += 1
			if into < 0.0:
				# One small bounce for hard landings, then the body follows the ground.
				var bounce := -into * GROUND_RESTITUTION if -into > 3.5 else 0.0
				body_velocity -= normal * into
				body_velocity += normal * bounce
				body_velocity.x *= 0.86
				body_velocity.z *= 0.86
		else:
			wall_hits += 1
			if into < 0.0:
				var tangent := body_velocity - normal * into
				body_velocity = tangent * (1.0 - WALL_FRICTION) - normal * into * WALL_RESTITUTION
			if actor and normal.y > 0.3 and collider is Node3D:
				# Never come to rest on a car roof or a person: slide off their side.
				var away := center - (collider as Node3D).global_position
				away.y = 0.0
				if away.length() < 0.05:
					away = Vector3(sin(yaw), 0.0, cos(yaw))
				body_velocity += away.normalized() * 1.6
		remaining = hit.get_remainder().slide(normal)
	center = _body.global_position
	_grounded = touched_ground or _resting_on_ground()
	max_height = maxf(max_height, center.y)

func _resting_on_ground() -> bool:
	var contact := KinematicCollision3D.new()
	if not _body.test_move(_body.global_transform, Vector3.DOWN * 0.05, contact, 0.002):
		return false
	return contact.get_normal().y >= WALKABLE and not _is_actor_or_vehicle(contact.get_collider())

## Ground below `at` for the camera/explorer anchor; vehicles and people skipped.
func _ground_below(at: Vector3, fallback_y: float) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.1, at + Vector3.DOWN * 6.0, GROUND_MASK)
	var excluded := _excluded()
	query.exclude = excluded
	query.hit_back_faces = false
	var space := get_world_3d().direct_space_state
	for attempt in 3:
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break
		if _is_actor_or_vehicle(hit.get("collider")):
			excluded.append(hit.rid)
			query.exclude = excluded
			continue
		return hit.position
	return Vector3(at.x, fallback_y, at.z)

func _update_anchor() -> void:
	ground_point = _ground_below(center, ground_point.y)
	global_position = _getup_anchor() if phase == "getup" or phase == "done" else ground_point
	velocity = body_velocity if phase != "getup" else Vector3.ZERO
	speed = Vector2(velocity.x, velocity.z).length()

## On the ground between where the rider lay and where they stand, in step
## with the get-up blend; at the standing spot once it completes.
func _getup_anchor() -> Vector3:
	var t := clampf(phase_time / GETUP_TIME, 0.0, 1.0) if phase == "getup" else 1.0
	var eased := t * t * (3.0 - 2.0 * t) if _getup_glide else 0.0
	var at := _getup_ground.lerp(_getup_target, eased)
	var floor_y := lerpf(_getup_ground.y, _getup_target.y - 0.05, eased)
	at.y = maxf(_getup_ground.y, _getup_target.y) + 0.25
	return _ground_below(at, floor_y)

## A camera-sized sphere can travel from `from` to `to` (walls, roofs, cars),
## ignoring what the chase camera ignores here (the bicycle, the explorer).
func _view_path_clear(from: Vector3, to: Vector3) -> bool:
	var sphere := SphereShape3D.new()
	sphere.radius = 0.2
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, from)
	query.motion = to - from
	query.collision_mask = 1 | 2 | 16
	query.exclude = _excluded()
	var fractions := get_world_3d().direct_space_state.cast_motion(query)
	return fractions.size() >= 2 and fractions[0] >= 1.0

func _lying_basis() -> Basis:
	var head := orientation.y
	var along := Vector3(head.x, 0.0, head.z)
	if along.length() < 0.3:
		along = Vector3(sin(yaw), 0.0, cos(yaw))
	along = _clear_lying_direction(along.normalized())
	var front := Vector3.UP if orientation.z.y >= 0.0 else Vector3.DOWN
	return Basis(along.cross(front), along, front).orthonormalized()

## Turns the lying body until neither head nor legs reach into a wall, car or
## person; the tumble's own direction is kept whenever it is already clear.
func _clear_lying_direction(along: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var from := center + Vector3.DOWN * (RADIUS - LYING_HEIGHT)
	var excluded := _excluded()
	for k in 8:
		# 0, -45, +45, -90, +90, -135, +135, 180 degrees from the tumble direction.
		var angle := ceilf(float(k) * 0.5) * PI * 0.25 * (-1.0 if k % 2 == 1 else 1.0)
		var candidate := along.rotated(Vector3.UP, angle)
		var clear := true
		for reach in [HEAD_REACH, -PIVOT_HEIGHT]:
			var query := PhysicsRayQueryParameters3D.create(from, from + candidate * float(reach), SWEEP_MASK)
			query.exclude = excluded
			query.hit_back_faces = false
			if not space.intersect_ray(query).is_empty():
				clear = false
				break
		if clear:
			return candidate
	return along

func _place_rig() -> void:
	var lying := 0.0
	if phase == "slide":
		lying = clampf(phase_time / 0.35, 0.0, 1.0)
	elif phase == "down":
		lying = 1.0
	# The sweep sphere rests RADIUS above the ground; a lying body is flatter.
	var offset := Vector3.DOWN * (RADIUS - LYING_HEIGHT) * lying
	_pivot.global_transform = Transform3D(orientation, center + offset)

func _pose(delta: float) -> void:
	if _puppet == null:
		return
	var t := elapsed
	match phase:
		"flight":
			_puppet.pose({"walk": 0.0, "armR": [-2.3 + 0.55 * sin(t * 9.0), 0.55 + 0.25 * sin(t * 7.0)],
				"armL": [-2.0 + 0.55 * sin(t * 8.0 + 1.3), 0.5 + 0.25 * sin(t * 6.0 + 0.4)],
				"lean": 0.35, "nod": -0.25, "mouth": 0.7})
			_puppet.legs[0].rotation.x = 0.75 * sin(t * 8.5)
			_puppet.legs[1].rotation.x = -0.65 * sin(t * 8.5 + 0.6)
		"slide", "down":
			var settle := clampf(phase_time / 0.3, 0.0, 1.0) if phase == "slide" else 1.0
			_puppet.pose({"walk": 0.0, "armR": [lerpf(-2.0, -1.25, settle), lerpf(0.5, 1.05, settle)],
				"armL": [lerpf(-1.8, -0.55, settle), lerpf(0.5, 0.85, settle)], "lean": 0.0, "nod": 0.25, "mouth": 0.2})
			_puppet.legs[0].rotation.x = 0.30
			_puppet.legs[1].rotation.x = -0.18
		"getup", "done":
			var p := clampf(phase_time / GETUP_TIME, 0.0, 1.0) if phase == "getup" else 1.0
			var crouch := sin(PI * p)
			_puppet.pose({"walk": 0.0, "armR": [-1.25 * (1.0 - p) - 0.5 * crouch, 1.05 * (1.0 - p) + 0.1],
				"armL": [-0.55 * (1.0 - p) - 0.5 * crouch, 0.85 * (1.0 - p) + 0.1], "lean": 0.45 * crouch, "nod": 0.0})
			_puppet.legs[0].rotation.x = 0.30 * (1.0 - p) - 0.9 * crouch
			_puppet.legs[1].rotation.x = -0.18 * (1.0 - p) - 0.7 * crouch
	if delta > 0.0:
		_puppet.phase += delta
