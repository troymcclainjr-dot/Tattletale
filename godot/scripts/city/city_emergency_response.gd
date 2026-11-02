extends Node3D
## Emergency medical response for neighborhood incidents: one real ambulance
## from Cator–Elkader Hospital, two paramedics and a bounded list of medical
## calls. Created, ticked, reset and freed by city_incidents.gd; every status
## goes back through incidents.on_medical_progress() to the durable record and,
## for the player's own reports, to the phone. Contract:
## artifacts/next-five-20261101/aftermath-contract.md.
##
## A call exists only for a real injured person an incident record names (combat
## itself reported them knocked down or hurt) and only once someone called it in
## or officers found them. One call per incident or person: a repeat returns the
## same call and never dispatches again. The one ambulance serves calls in order;
## the rest wait, honestly marked as waiting, and close after bounded waits.
##
## The ambulance starts in its bay under the hospital's emergency canopy and
## leaves along the canopy's painted approach onto the street; after a call it
## returns to a curbside standby in front of the hospital that leaves the travel
## lane free (without one, it backs into the bay along that same approach). While
## it is out on the road traffic treats it as an obstacle (traffic's emergency
## vehicle registry); parked at home it is let go. Between them it follows
## the traffic network's lanes and validated junction connectors, pulling over to
## the curb at a scene when the curb there is free. Its driver
## (city_ambulance_driver.gd) ground-snaps and hull-sweeps every step: nothing is
## passed through and nothing is teleported while anyone could see it. "En route"
## needs real movement, "on scene" a real stop at the end of the route, and
## "treating" a paramedic physically beside the person; the treatment time runs
## only during that contact. Nothing is predicted: there is no ETA anywhere.
##
## The injured person waits where they are (a crowd neighbor is held, hunched
## over, by one stand-in body; named people are only tracked). Treated, they go
## on with their day through the same release path every system uses. A person
## who died is never treated, released or revived; custody and armed threats are
## never overridden (an armed scene stages the ambulance short of it). The crew
## walk back and board, the ambulance leaves the scene (the road clears) and
## returns. Every wait, walk and route is bounded and closes honestly.

const Status := preload("res://scripts/city/city_emergency_status.gd")
const People := preload("res://scripts/city/city_emergency_people.gd")
const AmbulanceDriver := preload("res://scripts/city/city_ambulance_driver.gd")
const Lanes := preload("res://scripts/city/city_police_lanes.gd")
const Driver := preload("res://scripts/city/city_police_driver.gd")
const Tactics := preload("res://scripts/city/city_police_tactics.gd")
const Facilities := preload("res://scripts/city/city_law_facilities.gd")
const Actor := preload("res://scripts/city/city_npc_actor.gd")
const Models := preload("res://scripts/city/city_car_models.gd")
const Collision := preload("res://scripts/city/city_car_collision.gd")
const CivicFleet := preload("res://scripts/city/city_civic_parking_fleet.gd")

const CREW_IDS := ["ems_paramedic_1", "ems_paramedic_2"]
const CREW_CASTS := ["mailman", "liner_4"]
const CREW_LABEL := "Paramedic"
## On paramedic identities always; DUTY_META only while one is out on a call
## (combat: never a fight target, never stolen into gunfire panic, a bicycle
## bump only stumbles).
const CREW_META := "ems_crew"
const DUTY_META := "ems_responder"
const MAX_CALLS := 3
const MAX_HISTORY := 6
const MAX_CALL_REFS := 8
const THINK_INTERVAL := 0.25
const DISPATCH_RETRIES := 2
const RETRY_SECONDS := 6.0
## A waiting call that no ambulance could take in this long closes honestly.
const QUEUE_LIMIT := 240.0
## A dispatched ambulance that has not arrived in this long closes honestly.
const ARRIVAL_LIMIT := 240.0
const EN_ROUTE_EVIDENCE := 2.0
const RESPOND_SPEED := 11.0
const RETURN_SPEED := 8.0
const APRON_SPEED := 3.0
const CURB_SPEED := 5.0
const REVERSE_SPEED := 2.0
const ROUTE_LIMIT := 1600.0
const STUCK_SECONDS := 9.0
const PERSON_WAIT := 14.0
## Traffic ahead may be queued at a red light the ambulance itself could pass.
const VEHICLE_WAIT := 30.0
## Stuck this close to the end of its route, the ambulance stops where it is and
## the paramedics go on foot.
const FOOT_ARRIVAL := 45.0
const MAX_REPLANS := 2
const HOME_RETRIES := 6
const HOME_RETRY_SECONDS := 10.0
const SAFETY_RADIUS := 28.0
const SAFETY_LIMIT := 90.0
const STAGE_DISTANCE := 60.0
const SCENE_LIMIT := 150.0
const TREAT_RANGE := 1.6
const TREAT_HEIGHT := 0.65
const TREAT_SECONDS := 9.0
const WALK_SPEED := 1.9
const FOOT_ROUTE_LIMIT := 140.0
const DIRECT_WALK := 30.0
const CREW_STUCK_SECONDS := 2.5
const MAX_CREW_UNSTICK := 3
const MAX_REROUTES := 4
const CREW_RETURN_LIMIT := 75.0
const MAX_EXIT_TRIES := 8
const BOARD_RANGE := 1.6
const CLEAR_DISTANCE := 25.0
const HIDE_DISTANCE := 45.0
const MIN_TURN_RADIUS := 4.5
const SHIFT_LENGTH := 12.0
const MIN_CURB_SHIFT := 0.8
## The standby at the hospital leaves the whole travel lane free (traffic's car
## corridor is about 2.1 m to either side of a lane centre with the ambulance's width).
const STANDBY_SHIFT := 2.15
const EXIT_STRAIGHTS := [10.0, 8.0, 12.0, 14.0]
const JOIN_AHEAD := [11.0, 14.0, 8.0, 17.0, 6.0]
## Hospital-local bay centres under the emergency canopy (city_civic_hospital
## _ambulance_entry: berths between x 11.3 and 16.9 and between 16.9 and 22.5;
## the transport ambulance stands centred at x 17), facing the hospital front
## (local +Z, toward Elkader Road).
const BAY_LOCALS := [Vector3(12.6, 0.0, 10.0), Vector3(12.2, 0.0, 9.6), Vector3(21.6, 0.0, 10.0), Vector3(13.0, 0.0, 10.4)]
const SEAT_LOCAL := Vector3(0.45, 0.9, 0.3)
## The hospital's colliders normally exist when incidents set up; when its home
## cannot be validated then, it is tried again this often (bounded) before the
## service reports itself unavailable for the session.
const CONFIGURE_TRIES := 3
const CONFIGURE_RETRY := 2.0
## Physics-checked way-out candidates per configuration (setup cost bound).
const MAX_EXIT_CHECKS := 24
const PARKED_CLEARANCE := 0.20
## How far ahead a route is joined when the ambulance stands off its start.
const JOIN_HERE := [8.0, 11.0, 14.0, 18.0]

var level: Node
var incidents: Node
var available := false
var reason := "not set up"
## Bumps on every medical change (diagnostics; the phone refreshes from the
## incident service's own revision, which every relayed change bumps).
var revision := 0
var calls: Array[Dictionary] = []
var history: Array[Dictionary] = []
## {id, actor, state: seated | to_patient | with_patient | to_ambulance | lost | dead, door, path, index, ...}
var crew: Array[Dictionary] = []
var people := People.new()
var driver := AmbulanceDriver.new()
var lanes
var ambulance: AnimatableBody3D
## {name, home: {kind, pose, exit | curb}, curb}; empty while unavailable.
var base: Dictionary = {}
## Why each home candidate was refused (setup diagnostics).
var base_report: Array[String] = []
## The ambulance. mode: none | parked | responding | on_scene | returning | stranded.
## spot: where it stands still ({kind: bay|curb|lane, ...}).
var unit := {"mode": "none", "call": "", "spot": {}, "route_parked": {}, "from_kind": "", "from_spot": {}, "lead_length": 0.0,
	"replans": 0, "home_replans": 0, "home_tries": 0, "next_home": 0.0, "clear_ref": "", "clear_from": Vector3.INF,
	"leave_wait": 0.0}
var counters := {"requests": 0, "duplicates": 0, "refused": 0, "dispatches": 0, "routes": 0, "route_failures": 0,
	"arrivals": 0, "treated": 0, "failed": 0, "cancelled": 0, "holds": 0, "replans": 0, "recoveries": 0,
	"crew_lost": 0, "transitions": 0, "relays": 0, "resets": 0, "thinks": 0, "pull_overs": 0, "foot_arrivals": 0}
var _clock := 0.0
var _think_left := 0.0
var _sequence := 0
var _tactics := Tactics.new()
var _parked_cache: Array = []
var _lights: Array[MeshInstance3D] = []
var _model: Node3D
var _wheel_spin := 0.0
var _spec: Dictionary = {}
var _configure_tries := 0
var _configure_next := 0.0
var _exit_checks := 0
## Registered with traffic as an emergency obstacle (traffic.register_emergency_vehicle).
var _on_traffic := false
var _slot_query: PhysicsShapeQueryParameters3D
var _sweep_query: PhysicsShapeQueryParameters3D
var _kit_material: StandardMaterial3D

# --------------------------------------------------------------- setup

func setup(owner_level: Node, owner_incidents: Node) -> void:
	level = owner_level
	incidents = owner_incidents
	name = "EmergencyResponse"
	people.setup(level, self)
	lanes = Lanes.new()
	var traffic = _traffic()
	var network = traffic.get("network") if traffic != null else null
	if network != null:
		lanes.setup(network)
	# Paramedic identities exist before any checkpoint loads (death registry).
	_build_crew()
	_ensure_ambulance()
	if lanes.lane_count() == 0:
		_unavailable("no lane network")
		return
	var spec := _hospital_spec()
	if spec.is_empty():
		_unavailable("no hospital")
		return
	configure_base(spec)

## The ambulance's home, chosen once: a bay whose hull is clear on real paving
## with a drivable way out (the straight canopy approach and one smooth turn
## onto the nearest traffic lane, every metre grounded and clear of buildings,
## props and parked cars), and a curbside standby in front of the hospital it
## returns to after calls. Either alone is enough. spec: {bays: [Transform3D] or
## bay: Transform3D, name}. Fixtures call this with their own hospital.
func configure_base(spec: Dictionary) -> bool:
	_build_crew()
	_ensure_ambulance()
	if not calls.is_empty():
		reset_state("the hospital base changed")
	_spec = spec.duplicate(true)
	_configure_tries += 1
	_configure_next = _clock + CONFIGURE_RETRY
	_exit_checks = 0
	base = {}
	base_report.clear()
	var bays: Array = []
	if spec.get("bay") is Transform3D:
		bays.append(spec.bay)
	for value in spec.get("bays", []):
		if value is Transform3D:
			bays.append(value)
	if bays.is_empty():
		_unavailable("no ambulance bay")
		return false
	var anchor: Vector3 = (bays[0] as Transform3D).origin
	_parked_cache = _parked_around(anchor, 100.0)
	var home: Dictionary = {}
	# Reserve a share for every bay: a blocked first berth must not spend every
	# physics check before the alternative berths are considered.
	var checks_per_bay := maxi(1, floori(float(MAX_EXIT_CHECKS) / float(bays.size())))
	for value in bays:
		var pose: Transform3D = value
		var bay := _ground_bay(pose)
		if bay.is_empty():
			base_report.append("bay %s: no clear paved footing" % _xz(pose.origin))
			continue
		var exit := _plan_exit(bay.transform, checks_per_bay)
		if exit.is_empty():
			base_report.append("bay %s: no drivable way out to a street" % _xz(pose.origin))
			continue
		home = {"kind": "bay", "pose": bay.transform, "exit": exit}
		break
	var curb := _plan_curb(anchor)
	if curb.is_empty():
		base_report.append("no clear curbside standby near the hospital")
	if home.is_empty() and not curb.is_empty():
		home = {"kind": "curb", "pose": curb.pose, "curb": curb}
	if home.is_empty():
		_unavailable("no drivable way from the hospital to a street")
		return false
	base = {"name": str(spec.get("name", "the hospital")).left(64), "home": home, "curb": curb}
	_place_home()
	available = _living_crew() > 0
	reason = "" if available else "no paramedic crew"
	revision += 1
	return available

func _unavailable(why: String) -> void:
	available = false
	reason = why
	revision += 1

## The built hospital's canopy bays, in world space, facing its front.
func _hospital_spec() -> Dictionary:
	var built: Node3D = Facilities.model(level, "hospital")
	if built == null:
		return {}
	var site: Dictionary = Facilities.site(level, "hospital")
	var front := built.global_basis * Vector3.BACK
	front = Vector3(front.x, 0.0, front.z)
	if front.length_squared() < 0.0001:
		return {}
	front = front.normalized()
	var yaw := atan2(front.x, front.z)
	var bays: Array = []
	for local in BAY_LOCALS:
		bays.append(Transform3D(Basis(Vector3.UP, yaw), built.to_global(local)))
	return {"name": str(site.get("name", "the hospital")), "bays": bays}

## Paramedic identities live in level.npcs.actors (like cruiser crews) so that a
## recorded death validates on load; a dead paramedic is never re-seated.
func _build_crew() -> void:
	if not crew.is_empty():
		return
	var npcs = level.get("npcs") if level != null else null
	if npcs == null or not npcs.get("actors") is Dictionary:
		return
	var actors: Dictionary = npcs.actors
	for i in CREW_IDS.size():
		var id: String = CREW_IDS[i]
		var actor = actors.get(id)
		if not is_instance_valid(actor):
			actor = Actor.new()
			npcs.add_child(actor)
			actor.build(level, id, str(CREW_CASTS[i]), CREW_LABEL)
			actors[id] = actor
		actor.set_meta(CREW_META, true)
		var dead: bool = actor.dead == true or _dead_id(id)
		if not dead:
			actor.set_enabled(false)
		crew.append({"id": id, "actor": actor, "state": "dead" if dead else "seated", "door": Vector3.INF, "path": [],
			"index": 0, "goal": Vector3.INF, "stuck": 0.0, "unstick": 0, "reroutes": 0, "exit_tries": 0, "gave_up": false,
			"recalled": -INF, "kit": null})

func _ensure_ambulance() -> void:
	if is_instance_valid(ambulance):
		return
	ambulance = AnimatableBody3D.new()
	ambulance.name = "HospitalAmbulanceUnit"
	ambulance.sync_to_physics = false
	ambulance.collision_layer = 0
	ambulance.collision_mask = 0
	ambulance.visible = false
	add_child(ambulance)
	Collision.attach(ambulance, AmbulanceDriver.KIND)
	var model := Models.make(AmbulanceDriver.KIND, 1)
	ambulance.add_child(model)
	# The hospital fleet's own ambulance livery: white body, red belt, markings, light bar.
	CivicFleet._ambulance_livery(model, ambulance)
	_model = model
	_build_beacons(model)
	_visibility(model)
	ambulance.set_meta("emergency_vehicle", true)
	ambulance.set_meta("vehicle_kind", "ambulance")
	driver.setup(level, _traffic(), lanes, ambulance)

func _build_beacons(model: Node3D) -> void:
	for side in [-1.0, 1.0]:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var color := Color("ff2a2a") if float(side) < 0.0 else Color("f2f4ff")
		material.albedo_color = color
		material.emission_enabled = true
		material.emission = color
		var box := BoxMesh.new()
		box.size = Vector3(0.26, 0.07, 0.26)
		var mesh := MeshInstance3D.new()
		mesh.name = "Beacon"
		mesh.mesh = box
		mesh.material_override = material
		mesh.position = Vector3(float(side) * 0.45, 1.945, -0.3)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.visible = false
		model.add_child(mesh)
		_lights.append(mesh)

static func _visibility(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).visibility_range_end = 210.0
	for child in node.get_children():
		_visibility(child)

func _ground_bay(pose: Transform3D) -> Dictionary:
	var heading := atan2(pose.basis.z.x, pose.basis.z.z)
	driver.reset_ground()
	var ground := driver.ground_pose(pose.origin, heading, pose.origin.y + 1.2, false)
	if ground.is_empty():
		return {}
	var placed: Transform3D = ground.transform
	if not driver.pose_clear(placed):
		return {}
	return {"transform": placed}

## The bay's way out: straight along the canopy approach, then one smooth turn
## onto a traffic lane (never back toward the hospital). {lead, lead_length, lane,
## along, join, join_dir} or {} when no candidate is drivable.
func _plan_exit(bay: Transform3D, check_budget := MAX_EXIT_CHECKS) -> Dictionary:
	var front := Vector3(bay.basis.z.x, 0.0, bay.basis.z.z).normalized()
	var groups: Array = []
	var check_limit := mini(MAX_EXIT_CHECKS, _exit_checks + check_budget)
	for straight in EXIT_STRAIGHTS:
		var exit_point := bay.origin + front * float(straight)
		var options: Array[Dictionary] = []
		for candidate in lanes.nearest(exit_point, Vector3.ZERO, 30.0, -2.0, 6):
			var lane := int(candidate.lane)
			if lanes.graph.is_point_disabled(lane):
				continue
			var points := PackedVector3Array(lanes.lane_points(lane))
			var sums := Lanes.cumulative(points)
			var total := sums[sums.size() - 1]
			for ahead in JOIN_AHEAD:
				var along := float(candidate.along) + float(ahead)
				if along < 3.0 or along > total - 3.0:
					continue
				var join := Driver.point_at(points, sums, along)
				var join_dir := Driver.direction_at(points, sums, along)
				if join_dir == Vector3.ZERO or join_dir.dot(front) < -0.35:
					continue
				var lead := _exit_curve(bay.origin, exit_point, front, join, join_dir)
				var lead_sums := Lanes.cumulative(lead)
				if not _smooth(lead):
					continue # Geometry alone rules it out: no physics query spent.
				options.append({"lane": lane, "along": along, "join": join, "join_dir": join_dir, "lead": lead, "straight": float(straight),
					"length": lead_sums[lead_sums.size() - 1]})
		options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.length) < float(b.length))
		groups.append(options)
	# Try the shortest smooth option of each straight length before its longer
	# alternatives, within the same fixed physics budget.
	var round_index := 0
	var pending := true
	while pending:
		pending = false
		for options in groups:
			if round_index >= options.size():
				continue
			pending = true
			var option: Dictionary = options[round_index]
			var lead: PackedVector3Array = option.lead
			if _exit_checks >= check_limit:
				return {}
			_exit_checks += 1
			var why: Array = []
			if _path_valid(lead, false, why):
				return {"lead": lead, "lead_length": float(option.length), "lane": int(option.lane), "along": float(option.along),
					"join": option.join, "join_dir": option.join_dir, "straight": float(option.straight)}
		round_index += 1
	return {}

func _exit_curve(start: Vector3, exit_point: Vector3, front: Vector3, join: Vector3, join_dir: Vector3) -> PackedVector3Array:
	var raw := PackedVector3Array([start, exit_point])
	var reach := clampf(Lanes.flat(exit_point, join) * 0.45, 3.0, 10.0)
	var p1 := exit_point + front * reach
	var p2 := join - join_dir * reach
	for i in range(1, 25):
		var t := float(i) / 24.0
		var q := 1.0 - t
		raw.append(exit_point * q * q * q + p1 * 3.0 * q * q * t + p2 * 3.0 * q * t * t + join * t * t * t)
	return Lanes.resample(raw, Lanes.SPACING)

## A curbside standby near `anchor`: a lane spot shifted to its curb with the
## whole hull still on the carriageway, a smooth pull-in and pull-out, and no
## parked car, prop or building in the way.
func _plan_curb(anchor: Vector3) -> Dictionary:
	if not anchor.is_finite():
		return {}
	for candidate in lanes.nearest(anchor, Vector3.ZERO, 45.0, -2.0, 6):
		var lane := int(candidate.lane)
		if lanes.graph.is_point_disabled(lane):
			continue
		var total: float = lanes.lane_length(lane)
		for offset in [0.0, 6.0, -6.0, 12.0, -12.0, 18.0, -18.0]:
			var along := float(candidate.along) + float(offset)
			if along < SHIFT_LENGTH + 4.0 or along > total - SHIFT_LENGTH - 4.0:
				continue
			var spot := _curb_spot(lane, along, STANDBY_SHIFT)
			if not spot.is_empty():
				return spot
	return {}

func _curb_spot(lane: int, along: float, min_shift: float) -> Dictionary:
	var shift := _lane_shift(lane)
	if shift < min_shift:
		return {}
	var pull_in := _shift_path(lane, along - SHIFT_LENGTH, along, 0.0, shift)
	var pull_out := _shift_path(lane, along, along + SHIFT_LENGTH, shift, 0.0)
	var why: Array = []
	if not _path_valid(pull_in, true, why) or not _path_valid(pull_out, true, why):
		return {}
	var points := PackedVector3Array(lanes.lane_points(lane))
	var sums := Lanes.cumulative(points)
	var direction := Driver.direction_at(points, sums, along)
	driver.reset_ground()
	var ground := driver.ground_pose(pull_in[pull_in.size() - 1], atan2(direction.x, direction.z), pull_in[pull_in.size() - 1].y + 1.0, false)
	if ground.is_empty():
		return {}
	return {"kind": "curb", "lane": lane, "along": along, "shift": shift, "pose": ground.transform, "pull_in": pull_in, "home": true}

## How far a lane's curbside stands from its centre, with the whole hull still
## on the carriageway (the traffic network's own road width and lane offset).
func _lane_shift(lane: int) -> float:
	var network = lanes.network
	if network == null or lane < 0 or lane >= (network.lanes as Array).size():
		return 0.0
	var info: Dictionary = network.lanes[lane]
	var half := float(info.get("width", 9.5)) * 0.5
	var offset := float(info.get("offset", 1.0))
	return clampf(half - 0.12 - 1.06 - 0.2 - offset, 0.0, 2.6)

## Points along `lane` from from_along to to_along, eased from one curbward
## shift to another (shift 0 is the lane centre).
func _shift_path(lane: int, from_along: float, to_along: float, from_shift: float, to_shift: float) -> PackedVector3Array:
	var points := PackedVector3Array(lanes.lane_points(lane))
	var sums := Lanes.cumulative(points)
	var result := PackedVector3Array()
	var steps := maxi(2, ceili(absf(to_along - from_along)))
	for i in steps + 1:
		var t := float(i) / float(steps)
		var along := lerpf(from_along, to_along, t)
		var center := Driver.point_at(points, sums, along)
		var direction := Driver.direction_at(points, sums, along)
		var outward := direction.cross(Vector3.UP).normalized()
		result.append(center + outward * lerpf(from_shift, to_shift, smoothstep(0.0, 1.0, t)))
	return result

## Every metre of a planned stretch: a sane turning radius, the whole hull on
## the carriageway (when require_road), drivable ground in step with the previous
## metre, no building or prop in the hull and no parked car there (distant parked
## cars have no collider yet, so their records are read instead).
func _path_valid(points: PackedVector3Array, require_road: bool, why: Array) -> bool:
	if points.size() < 2:
		why.append("too short")
		return false
	if not _smooth(points):
		why.append("tight turn")
		return false
	var sums := Lanes.cumulative(points)
	var previous := PackedFloat32Array()
	var reference_y := points[0].y + 1.2
	var traffic = _traffic()
	for i in points.size():
		var direction := Driver.direction_at(points, sums, sums[i])
		if direction == Vector3.ZERO:
			continue
		var heading := atan2(direction.x, direction.z)
		if require_road and not _hull_on_road(traffic, points[i], heading):
			why.append("off the carriageway")
			return false
		var ground := driver.ground_pose(points[i], heading, reference_y, false)
		if ground.is_empty():
			why.append("no footing")
			return false
		var heights: PackedFloat32Array = ground.heights
		if previous.size() == heights.size():
			for k in heights.size():
				if absf(heights[k] - previous[k]) > AmbulanceDriver.STEP_UP:
					why.append("step")
					return false
		previous = heights
		var pose: Transform3D = ground.transform
		reference_y = pose.origin.y
		if i % 2 == 0 or i == points.size() - 1:
			if not driver.pose_clear(pose, 2):
				why.append("structure")
				return false
			if _parked_conflict(pose):
				why.append("parked car")
				return false
	return true

## Geometry only: no turn tighter than MIN_TURN_RADIUS anywhere along `points`.
static func _smooth(points: PackedVector3Array) -> bool:
	var sums := Lanes.cumulative(points)
	for i in range(2, points.size() - 2):
		var a := points[i - 2]
		var b := points[i]
		var c := points[i + 2]
		if Lanes.flat(a, b) < 0.2 or Lanes.flat(b, c) < 0.2:
			continue
		var turn := absf(angle_difference(atan2(b.x - a.x, b.z - a.z), atan2(c.x - b.x, c.z - b.z)))
		var arc := (sums[i + 2] - sums[i - 2]) * 0.5
		if turn > 0.0001 and arc / turn < MIN_TURN_RADIUS:
			return false
	return true

func _hull_on_road(traffic, at: Vector3, heading: float) -> bool:
	if traffic == null or not traffic.has_method("on_road"):
		return false
	var forward := Vector3(sin(heading), 0.0, cos(heading))
	var side := Vector3(forward.z, 0.0, -forward.x)
	for corner in [Vector2(-1.06, -2.35), Vector2(-1.06, 2.35), Vector2(1.06, -2.35), Vector2(1.06, 2.35)]:
		if not bool(traffic.on_road(at + side * corner.x + forward * corner.y)):
			return false
	return true

func _parked_around(anchor: Vector3, radius: float) -> Array:
	var found: Array = []
	var traffic = _traffic()
	var parked = traffic.get("parked") if traffic != null else null
	var records = parked.get("records") if parked != null else null
	if not records is Array or not anchor.is_finite():
		return found
	for record in records:
		if record is Dictionary and record.get("pose") is Transform3D:
			var origin: Vector3 = (record.pose as Transform3D).origin
			if Lanes.flat(origin, anchor) <= radius:
				var footprint := _parking_footprint(record.pose, str(record.get("kind", "compact")))
				var reach := 0.0
				for point in footprint:
					reach = maxf(reach, point.distance_to(Vector2(origin.x, origin.z)))
				found.append({"origin": origin, "footprint": footprint, "radius": reach})
	return found

func _parked_conflict(pose: Transform3D) -> bool:
	if _parked_cache.is_empty():
		return false
	var own := _parking_footprint(pose, AmbulanceDriver.KIND)
	var center := Vector2(pose.origin.x, pose.origin.z)
	var reach := 0.0
	for point in own:
		reach = maxf(reach, point.distance_to(center))
	for record in _parked_cache:
		if Lanes.flat(record.origin, pose.origin) <= reach + float(record.radius) + PARKED_CLEARANCE \
				and _footprints_overlap(own, record.footprint):
			return true
	return false

## Shared full-envelope geometry also checks waiting cars before junction entry.
static func _parking_footprint(pose: Transform3D, kind: String) -> PackedVector2Array:
	return Collision.footprint(pose, kind)

static func _footprints_overlap(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	return Collision.footprints_overlap(a, b, PARKED_CLEARANCE)

# --------------------------------------------------------------- public API

## A medical call for one injured person linked to incident `ref`. event: {ref,
## patient, injury, at, by, street, phone}. A repeat for the same incident or
## person returns the existing call (duplicate) and never dispatches again.
## Refused (no call is created) for a person who died or is in custody, while no
## ambulance can respond, or when the bounded call list is full. Returns {ok,
## call_id, duplicate, stage, outcome, message, reason}.
func request(event: Dictionary) -> Dictionary:
	counters.requests = int(counters.requests) + 1
	var result := {"ok": false, "call_id": "", "duplicate": false, "stage": "", "outcome": "", "message": "", "reason": ""}
	var ref := str(event.get("ref", "")).left(64)
	var patient := str(event.get("patient", "")).left(64)
	if ref.is_empty() or patient.is_empty() or patient == "player":
		return _refuse(result, "invalid", "unavailable", "No ambulance was requested: nobody hurt was named.")
	for call in calls:
		if ref in _call_refs(call) or str(call.patient) == patient:
			if str(call.patient) != patient:
				return _refuse(result, "identity", "unavailable", "This incident already names a different injured person.")
			var refs: Array = _call_refs(call)
			if not ref in refs:
				if refs.size() >= MAX_CALL_REFS:
					return _refuse(result, "capacity", "unavailable", "This response already has too many linked reports.")
				refs.append(ref)
				call.refs = refs
				revision += 1
				_relay(call, false)
			counters.duplicates = int(counters.duplicates) + 1
			call.phone = bool(call.phone) or bool(event.get("phone", false))
			result.ok = true
			result.duplicate = true
			result.call_id = str(call.id)
			result.stage = str(call.stage)
			result.message = "An ambulance is already handling this. " + str(call.text)
			return result
	var person := _patient_state(patient)
	if str(person.state) == "dead":
		return _refuse(result, "deceased", "patient_died", "No ambulance was sent: the injured person had already died.")
	if str(person.state) == "custody":
		return _refuse(result, "custody", "in_custody", "Officers have the injured person in custody and handle their care.")
	if str(person.state) == "absent":
		return _refuse(result, "absent", "patient_left", "No ambulance was sent: the injured person is no longer there.")
	if not available:
		return _refuse(result, "unavailable", "unavailable", "No ambulance can respond right now.")
	if calls.size() >= MAX_CALLS:
		return _refuse(result, "capacity", "unavailable", "The hospital already has too many medical calls, so no ambulance could be sent.")
	_sequence += 1
	var at: Vector3 = person.position if Vector3(person.position).is_finite() else (event.get("at") if event.get("at") is Vector3 else Vector3.INF)
	var now := _minutes()
	var injury := str(event.get("injury", "hurt"))
	var call := {"id": "ems_%d" % _sequence, "ref": ref, "refs": [ref], "patient": patient,
		"injury": injury if injury in Status.INJURIES else "hurt", "at": at, "by": str(event.get("by", "")).left(64),
		"street": str(event.get("street", "")).left(64), "phone": bool(event.get("phone", false)), "stage": "", "stage_key": "",
		"outcome": "", "text": "", "clearance": "", "opened": _clock, "opened_minutes": now, "updated_minutes": now,
		"timeline": [], "retries": 0, "next_retry": 0.0, "dispatch_odometer": 0.0, "arrived": -INF, "scene_since": -INF,
		"treat_time": 0.0, "safety_wait": 0.0, "unsafe": false, "closing": false, "relay": true}
	calls.append(call)
	_transition(call, "requested", "Dispatch asked the hospital for an ambulance.", false)
	_try_hold(call)
	_assign()
	result.ok = true
	result.call_id = str(call.id)
	result.stage = str(call.stage)
	result.message = str(call.text)
	return result

func _refuse(result: Dictionary, why: String, outcome: String, text: String) -> Dictionary:
	counters.refused = int(counters.refused) + 1
	result.ok = false
	result.reason = why
	result.outcome = outcome
	result.message = text
	return result

func has_live(ref: String) -> bool:
	for call in calls:
		if ref in _call_refs(call) and not bool(call.closing):
			return true
	return false

## One medical call by incident ref or call id: live first, then the newest closed.
func call_for(key: String) -> Dictionary:
	if key.is_empty():
		return {}
	for call in calls:
		if key in _call_refs(call) or str(call.id) == key:
			return _summary(call)
	for i in range(history.size() - 1, -1, -1):
		if key in _call_refs(history[i]) or str(history[i].get("id", "")) == key:
			return history[i].duplicate(true)
	return {}

func view() -> Dictionary:
	var live: Array = []
	for call in calls:
		live.append(_summary(call))
	return {"available": available, "reason": reason, "revision": revision, "live": live,
		"history": history.duplicate(true), "minutes": _minutes()}

## Live medical responses are never saved and never block a checkpoint: a load
## stands them down (reset_state) and the durable record says the result is unknown.
func blocks_checkpoint() -> bool:
	return false

func tick(delta: float) -> void:
	if level == null or delta <= 0.0 or _world_paused():
		return
	delta = minf(delta, 0.1)
	_clock += delta
	_tactics.space = _space()
	if base.is_empty() and not _spec.is_empty() and _configure_tries < CONFIGURE_TRIES and _clock >= _configure_next:
		configure_base(_spec)
	_drive(delta)
	_tick_crew(delta)
	_tick_patients(delta)
	_animate()
	_think_left -= delta
	if _think_left <= 0.0:
		_think_left = THINK_INTERVAL
		_think()

## Stops everything now (a checkpoint load or rollback, fixtures): live calls close
## as interrupted (relayed to their records only when `relay`), held people are
## released where they are, paramedics on foot are re-seated and the ambulance is
## put back at its home. A load (relay false) also forgets this session's
## closed calls: the restored records replace that timeline.
func reset_state(why := "reset", relay := true) -> void:
	counters.resets = int(counters.resets) + 1
	for call in calls.duplicate():
		call.relay = relay
		call.closing = true
		call.outcome = "interrupted"
		_transition(call, "cancelled", "The medical response stopped (%s), so its result is unknown." % why.left(32))
		history.append(_summary(call))
	calls.clear()
	while history.size() > MAX_HISTORY:
		history.pop_front()
	people.release_all()
	for entry in crew:
		if str(entry.state) != "dead" and (_crew_ours(entry) or _crew_free(entry)):
			_seat(entry)
	unit.call = ""
	unit.clear_ref = ""
	unit.leave_wait = 0.0
	if not base.is_empty():
		_place_home()
	if not relay:
		history.clear()
	revision += 1

func get_status() -> Dictionary:
	var crew_list: Array = []
	for entry in crew:
		var actor = entry.actor
		crew_list.append({"id": str(entry.id), "state": str(entry.state),
			"position": (actor as Node3D).global_position if is_instance_valid(actor) else Vector3.INF,
			"enabled": is_instance_valid(actor) and actor.enabled == true, "gave_up": bool(entry.get("gave_up", false))})
	var home: Dictionary = base.get("home", {})
	return {"available": available, "reason": reason, "revision": revision, "max_calls": MAX_CALLS,
		"calls": calls.size(), "history": history.size(), "live": view().live,
		"base": {"name": str(base.get("name", "")), "home": str(home.get("kind", "")),
			"curb": not (base.get("curb", {}) as Dictionary).is_empty(), "report": base_report.duplicate()},
		"unit": {"mode": str(unit.mode), "call": str(unit.call), "spot": str((unit.spot as Dictionary).get("kind", "")),
			"position": ambulance.global_position if is_instance_valid(ambulance) else Vector3.INF,
			"lights": driver.emergency, "clear_ref": str(unit.clear_ref)},
		"driver": driver.get_status(), "crew": crew_list, "people": people.get_status(), "counters": counters.duplicate()}

# --------------------------------------------------------------- dispatch

func _assign() -> void:
	if available and _ambulance_free():
		for call in calls:
			if bool(call.closing) or not str(call.stage) in ["requested", "queued"]:
				continue
			if _clock < float(call.get("next_retry", 0.0)):
				continue
			if _dispatch(call):
				break
	for call in calls:
		if not bool(call.closing) and str(call.stage) == "requested":
			_transition(call, "queued", _waiting_text())

func _waiting_text() -> String:
	if not str(unit.call).is_empty():
		return "The hospital's ambulance is on another call. The injured person is waiting for it."
	if str(unit.mode) == "on_scene":
		return "The ambulance crew are finishing at another scene. The injured person is waiting."
	return "Dispatch is waiting for the ambulance to be ready. The injured person is waiting."

func _ambulance_free() -> bool:
	if not is_instance_valid(ambulance) or not str(unit.call).is_empty():
		return false
	if not str(unit.mode) in ["parked", "returning", "stranded"]:
		return false
	if str(unit.mode) == "returning" and driver.kind() == "back_in":
		return false
	for entry in crew:
		if str(entry.state) in ["to_patient", "with_patient", "to_ambulance"]:
			return false
	return _seated_crew() > 0

func _dispatch(call: Dictionary) -> bool:
	var goal: Vector3 = call.at
	if not goal.is_finite():
		return false
	var plan := _plan_route(goal)
	if bool(plan.get("ok", false)):
		plan = _from_here(_with_pull_over(plan))
	if not bool(plan.get("ok", false)):
		call.retries = int(call.get("retries", 0)) + 1
		call.next_retry = _clock + RETRY_SECONDS
		call.route_reason = str(plan.get("reason", ""))
		if int(call.retries) > DISPATCH_RETRIES:
			_close(call, "unreachable", "No road route lets the ambulance reach the injured person%s, so dispatch closed the medical call." % _near_text(goal))
		else:
			_transition(call, "queued", "Dispatch has no road route for the ambulance yet and will try again.")
		return false
	var from_kind := str((unit.spot as Dictionary).get("kind", "lane"))
	unit.from_spot = (unit.spot as Dictionary).duplicate()
	unit.call = str(call.id)
	unit.mode = "responding"
	unit.replans = 0
	unit.from_kind = from_kind
	unit.lead_length = float(plan.get("slow_until", 0.0))
	unit.spot = {"kind": "lane"}
	call.dispatch_odometer = driver.odometer
	driver.emergency = true
	driver.hold = false
	_apply_route(plan, "respond", RESPOND_SPEED)
	counters.dispatches = int(counters.dispatches) + 1
	var source := "from " + str(base.name) if from_kind in ["bay", "curb"] else "from its last call"
	_transition(call, "dispatched", "Dispatch sent the ambulance %s for the injured person." % source)
	return true

## Where a new route starts: the bay's canopy approach, a pull-out from the curb,
## or (empty) the lane the ambulance is already on.
func _departure() -> Dictionary:
	var spot: Dictionary = unit.spot
	match str(spot.get("kind", "")):
		"bay":
			var exit: Dictionary = spot.exit
			return {"lead": exit.lead, "lane": int(exit.lane), "along": float(exit.along), "join": exit.join,
				"join_dir": exit.join_dir, "slow_until": float(exit.lead_length), "slow_cap": APRON_SPEED}
		"curb":
			var lane := int(spot.lane)
			var along := float(spot.along)
			if not lanes.has_lane(lane):
				return {}
			var finish := minf(along + SHIFT_LENGTH, lanes.lane_length(lane) - 1.0)
			if finish <= along + 2.0:
				return {}
			var lead := _shift_path(lane, along, finish, float(spot.shift), 0.0)
			var points := PackedVector3Array(lanes.lane_points(lane))
			var sums := Lanes.cumulative(points)
			return {"lead": lead, "lane": lane, "along": finish, "join": lead[lead.size() - 1],
				"join_dir": Driver.direction_at(points, sums, finish), "slow_until": SHIFT_LENGTH, "slow_cap": CURB_SPEED}
	return {}

func _plan_route(goal: Vector3) -> Dictionary:
	counters.routes = int(counters.routes) + 1
	var start := _departure()
	var plan: Dictionary
	if start.is_empty():
		plan = lanes.plan(ambulance.global_position, _forward(), goal, -1, -1.0, PackedVector3Array(), ROUTE_LIMIT, _clock)
	else:
		plan = lanes.plan(start.join, start.join_dir, goal, int(start.lane), float(start.along), start.lead, ROUTE_LIMIT, _clock)
		plan["slow_until"] = float(start.slow_until)
		plan["slow_cap"] = float(start.slow_cap)
	if not bool(plan.get("ok", false)):
		counters.route_failures = int(counters.route_failures) + 1
	return plan

## The last stretch of a route moved to the curb when the curb there is free,
## so the ambulance stops out of the travel lane. Unchanged when it is not.
func _with_pull_over(plan: Dictionary) -> Dictionary:
	var lane := int(plan.get("goal_lane", -1))
	var points: PackedVector3Array = plan.points
	if lane < 0 or points.size() < 2 or not lanes.has_lane(lane):
		return plan
	var sums: PackedFloat64Array = plan.get("sums", PackedFloat64Array())
	if sums.size() != points.size():
		sums = Lanes.cumulative(points)
	var length := sums[sums.size() - 1]
	var segments: Array = plan.get("segments", [])
	if length < SHIFT_LENGTH + 6.0 or segments.is_empty():
		return plan
	var last: Dictionary = segments[segments.size() - 1]
	if str(last.get("kind", "")) != "lane" or int(last.get("lane", -1)) != lane or float(last.get("s", 0.0)) > length - SHIFT_LENGTH - 0.5:
		return plan
	var end_along := float(lanes.project(lane, points[points.size() - 1]).along)
	var start_along := end_along - SHIFT_LENGTH
	var shift := _lane_shift(lane)
	# The way back out (the same eased shift) must fit and be clear too.
	if start_along < 1.0 or end_along + SHIFT_LENGTH > lanes.lane_length(lane) - 1.0 or shift < MIN_CURB_SHIFT:
		return plan
	var tail := _shift_path(lane, start_along, end_along, 0.0, shift)
	var pull_out := _shift_path(lane, end_along, end_along + SHIFT_LENGTH, shift, 0.0)
	_parked_cache = _parked_around(tail[tail.size() - 1], 30.0)
	var why: Array = []
	if not _path_valid(tail, true, why) or not _path_valid(pull_out, true, why):
		return plan
	var kept := PackedVector3Array()
	var cut := length - SHIFT_LENGTH
	for i in points.size():
		if sums[i] < cut - 0.01:
			kept.append(points[i])
	kept.append_array(tail)
	var resampled := Lanes.resample(kept, Lanes.SPACING)
	var shifted := plan.duplicate()
	shifted.points = resampled
	shifted.sums = Lanes.cumulative(resampled)
	shifted.length = (shifted.sums as PackedFloat64Array)[resampled.size() - 1]
	shifted.parked = {"kind": "curb", "lane": lane, "along": end_along, "shift": shift}
	counters.pull_overs = int(counters.pull_overs) + 1
	return shifted

## A plan joined from where the ambulance really stands. Unchanged when the body
## is on its start (a bay or curb departure always is); otherwise one smooth
## curve from the body's heading onto the route a little further on, its marks
## re-based to match. Never a sideways jump: with no smooth join the plan fails.
func _from_here(plan: Dictionary) -> Dictionary:
	if not bool(plan.get("ok", false)) or not is_instance_valid(ambulance):
		return plan
	var points: PackedVector3Array = plan.points
	var sums: PackedFloat64Array = plan.get("sums", PackedFloat64Array())
	if sums.size() != points.size():
		sums = Lanes.cumulative(points)
	if points.size() < 2:
		return {"ok": false, "reason": "empty route", "points": PackedVector3Array()}
	var at := ambulance.global_position
	var tracked := Driver.track(points, sums, 0, at, 16)
	if float(tracked.lateral) <= 0.005:
		return plan # Already on the path, apart from floating-point tolerance.
	if float(tracked.lateral) > 6.0:
		return {"ok": false, "reason": "the route does not start where the ambulance is", "points": PackedVector3Array()}
	var forward := _forward()
	var length := sums[sums.size() - 1]
	for ahead in JOIN_HERE:
		var cut := float(tracked.s) + float(ahead)
		if cut > length - 2.0:
			break
		var join := Driver.point_at(points, sums, cut)
		var join_dir := Driver.direction_at(points, sums, cut)
		if join_dir == Vector3.ZERO or join_dir.dot(forward) < 0.3:
			continue
		var curve := _exit_curve(at, at + forward * 0.8, forward, join, join_dir)
		if not _smooth(curve):
			continue
		var curve_sums := Lanes.cumulative(curve)
		var offset := curve_sums[curve_sums.size() - 1]
		var joined := PackedVector3Array(curve)
		for i in points.size():
			if sums[i] > cut + 0.05:
				joined.append(points[i])
		var resampled := Lanes.resample(joined, Lanes.SPACING)
		var result := plan.duplicate()
		result.points = resampled
		result.sums = Lanes.cumulative(resampled)
		result.length = (result.sums as PackedFloat64Array)[resampled.size() - 1]
		result.segments = _rebase(plan.get("segments", []), cut, offset, true)
		result.junctions = _rebase(plan.get("junctions", []), cut, offset, false)
		result.slow_until = -1.0
		return result
	return {"ok": false, "reason": "no smooth way onto the route from here", "points": PackedVector3Array()}

## Route marks (lane segments, junctions) after the path before `cut` became
## `offset` metres of join curve. The lane segment in force at the cut starts
## the list; junctions already entered are dropped.
static func _rebase(marks: Array, cut: float, offset: float, keep_current: bool) -> Array:
	var result: Array = []
	var current: Dictionary = {}
	for value in marks:
		if not value is Dictionary:
			continue
		var mark: Dictionary = (value as Dictionary).duplicate(true)
		if float(mark.get("s", 0.0)) <= cut:
			current = mark
			continue
		mark.s = float(mark.s) - cut + offset
		if mark.has("exit_s"):
			mark.exit_s = float(mark.exit_s) - cut + offset
		result.append(mark)
	if keep_current and not current.is_empty():
		current.s = 0.0
		result.push_front(current)
	return result

## A new leg: the ambulance is leaving wherever it stood (any departure lead is
## already part of `plan`), so its spot is the road until the leg ends.
func _apply_route(plan: Dictionary, kind: String, cap: float) -> void:
	var points: PackedVector3Array = plan.points
	driver.emergency = kind == "respond"
	driver.set_leg(points, kind, cap, false, {"sums": plan.get("sums", PackedFloat64Array()),
		"junctions": plan.get("junctions", []), "segments": plan.get("segments", []),
		"slow_until": float(plan.get("slow_until", -1.0)), "slow_cap": float(plan.get("slow_cap", APRON_SPEED))})
	unit.route_parked = plan.get("parked", {})
	unit.spot = {"kind": "lane"}
	_traffic_presence(true)

## The way back to the hospital: lanes to the start of the curbside standby's
## pull-in and the pull-in itself; with no standby, lanes to the point where the
## bay's approach meets the street (the ambulance then backs in along it).
## Fixed targets: the planner's graph and validated connectors.
func _plan_home() -> Dictionary:
	var curb: Dictionary = base.get("curb", {})
	var home: Dictionary = base.get("home", {})
	var start := _departure()
	var plan: Dictionary
	if not curb.is_empty():
		var lane := int(curb.lane)
		plan = _plan_to_lane(start, lane, float(curb.along) - SHIFT_LENGTH)
		if not bool(plan.get("ok", false)):
			return plan
		var joined := PackedVector3Array(plan.points)
		joined.append_array(curb.pull_in)
		var resampled := Lanes.resample(joined, Lanes.SPACING)
		plan.points = resampled
		plan.sums = Lanes.cumulative(resampled)
		plan.length = (plan.sums as PackedFloat64Array)[resampled.size() - 1]
		plan.parked = curb.duplicate()
	elif str(home.get("kind", "")) == "bay":
		var exit: Dictionary = home.exit
		plan = _plan_to_lane(start, int(exit.lane), float(exit.along))
		if not bool(plan.get("ok", false)):
			return plan
		plan.parked = {"kind": "lane", "back_in": true}
	else:
		return {"ok": false, "reason": "no way back to the hospital"}
	if not start.is_empty():
		plan["slow_until"] = float(start.slow_until)
		plan["slow_cap"] = float(start.slow_cap)
	return _from_here(plan)

## Backs into the bay along its own approach: from where the approach meets the
## street, or (`upto`) from the stretch of it the ambulance had driven so far.
func _back_in(upto: float) -> bool:
	var home: Dictionary = base.get("home", {})
	if str(home.get("kind", "")) != "bay" or not is_instance_valid(ambulance):
		return false
	var lead: PackedVector3Array = (home.exit as Dictionary).lead
	var sums := Lanes.cumulative(lead)
	var back := PackedVector3Array([ambulance.global_position])
	for i in range(lead.size() - 1, -1, -1):
		if sums[i] <= upto + 0.01:
			back.append(lead[i])
	var path := Lanes.resample(back, Lanes.SPACING)
	if path.size() < 2:
		return false
	unit.mode = "returning"
	unit.spot = {"kind": "lane"}
	unit.route_parked = {}
	driver.set_leg(path, "back_in", REVERSE_SPEED, true)
	_traffic_presence(true)
	return true

## Lanes from where the ambulance is to one exact lane position, never a U-turn
## on the same street: {ok, reason, points, sums, length, segments, junctions}.
func _plan_to_lane(start: Dictionary, target_lane: int, target_along: float) -> Dictionary:
	counters.routes = int(counters.routes) + 1
	lanes._expire(_clock) # Streets blocked earlier open again (the planner's own rule).
	var fail := {"ok": false, "reason": "", "points": PackedVector3Array()}
	if not lanes.has_lane(target_lane) or target_along < 0.0:
		fail.reason = "no standby lane"
		return fail
	var start_lane := -1
	var start_along := -1.0
	var lead := PackedVector3Array()
	if not start.is_empty():
		start_lane = int(start.lane)
		start_along = float(start.along)
		lead = start.lead
	else:
		for candidate in lanes.nearest(ambulance.global_position, _forward(), Lanes.START_RADIUS, 0.45, 4):
			if not lanes.graph.is_point_disabled(int(candidate.lane)):
				start_lane = int(candidate.lane)
				start_along = float(candidate.along)
				break
	if start_lane < 0:
		counters.route_failures = int(counters.route_failures) + 1
		fail.reason = "the ambulance is off the lane network"
		return fail
	for attempt in 4:
		var sequence: Array = []
		if start_lane == target_lane and target_along >= start_along + 0.5:
			sequence = [start_lane]
		else:
			var best := INF
			var options := 0
			for next in _successors(start_lane):
				if options >= 3:
					break
				options += 1
				var ids: PackedInt64Array = PackedInt64Array([next]) if next == target_lane else lanes.graph.get_id_path(next, target_lane)
				if ids.is_empty():
					continue
				var cost: float = lanes.lane_length(start_lane) - start_along + _path_cost(ids) + target_along
				if cost < best:
					best = cost
					sequence = [start_lane]
					for value in ids:
						sequence.append(int(value))
		if sequence.is_empty():
			break
		var built: Dictionary = lanes.assemble(sequence, start_along, target_along, lead)
		if bool(built.get("ok", false)):
			if float(built.length) > ROUTE_LIMIT:
				fail.reason = "route too long"
				break
			return built
		var a := int(built.get("bad_from", -1))
		var b := int(built.get("bad_to", -1))
		if a >= 0 and b >= 0 and lanes.graph.are_points_connected(a, b, false):
			lanes.graph.disconnect_points(a, b, false)
			continue
		fail.reason = str(built.get("reason", "route assembly failed"))
		break
	if str(fail.reason).is_empty():
		fail.reason = "no lane route"
	counters.route_failures = int(counters.route_failures) + 1
	return fail

func _successors(id: int) -> Array[int]:
	var result: Array[int] = []
	var network = lanes.network
	if network == null:
		return result
	var junction = network.nodes.get(network.lanes[id].to)
	if not junction is Dictionary:
		return result
	for value in junction.get("out", []):
		var next := int(value)
		if next != id and lanes.graph.has_point(next) and not lanes.graph.is_point_disabled(next) \
				and lanes.graph.are_points_connected(id, next, false):
			result.append(next)
	return result

func _path_cost(ids: PackedInt64Array) -> float:
	var cost := 0.0
	for i in range(1, ids.size()):
		cost += lanes.graph.get_point_position(ids[i - 1]).distance_to(lanes.graph.get_point_position(ids[i]))
	return cost

# --------------------------------------------------------------- driving (every physics step)

func _drive(delta: float) -> void:
	if not is_instance_valid(ambulance) or driver.leg.is_empty():
		return
	var result := driver.tick(delta)
	var moved := float(result.get("moved", 0.0))
	if moved > 0.0:
		_wheel_spin += (-moved if bool(driver.leg.get("reverse", false)) else moved) / Models.wheel_radius(AmbulanceDriver.KIND)
		_spin_wheels()
		_update_clearance()
	match str(unit.mode):
		"responding":
			_drive_response()
		"returning":
			_drive_return()

func _drive_response() -> void:
	var call := _call(str(unit.call))
	if call.is_empty():
		_head_home()
		return
	if str(call.stage) == "dispatched" and driver.odometer - float(call.dispatch_odometer) >= EN_ROUTE_EVIDENCE:
		_transition(call, "en_route", "The ambulance is on its way.", false)
	var unsafe := bool(call.get("unsafe", false)) and driver.remaining() <= STAGE_DISTANCE and driver.s > float(unit.lead_length)
	if unsafe != driver.hold:
		driver.hold = unsafe
		if unsafe:
			_transition(call, "staging", "The ambulance is waiting nearby until the scene is safe.")
		elif str(call.stage) == "staging":
			_transition(call, "en_route", "The scene is safe now; the ambulance is going in.", false)
	if driver.hold:
		return
	if driver.finished():
		_arrive(call, true)
		return
	if driver.wait_time >= _wait_limit(driver.wait_reason):
		_response_blocked(call)

## How long the ambulance waits on one reason before acting on it. The driver
## yields for as long as cross traffic is really there; a junction that stays
## busy is this service's bounded replan or honest closure, never a forced entry.
## Staging ("hold") is bounded by the call's own safety and arrival limits.
static func _wait_limit(why: String) -> float:
	match why:
		"", "hold":
			return INF
		"person":
			return PERSON_WAIT
		"vehicle", "yield":
			return VEHICLE_WAIT
	return STUCK_SECONDS

## The lane where the ambulance is held up, when that is not the lane it is on
## (blocking its own lane would leave a new route nowhere to start).
func _jam_lane() -> int:
	var probe := driver.s + (clampf(driver.obstacle, 2.0, 25.0) + 2.0 if is_finite(driver.obstacle) else 6.0)
	var jam := driver.lane_at(probe)
	return jam if jam != driver.lane_at(driver.s) else -1

## Held up too long: close enough to walk, another way round, or (after a
## bounded number of tries) an honest closure. A failed replan keeps the
## current route; the next wait decides again.
func _response_blocked(call: Dictionary) -> void:
	driver.wait_time = 0.0
	if driver.remaining() <= FOOT_ARRIVAL and driver.s > float(unit.lead_length) and _on_road(ambulance.global_position):
		counters.foot_arrivals = int(counters.foot_arrivals) + 1
		_arrive(call, false) # Close enough: stop here and go on foot.
		return
	if int(unit.replans) >= MAX_REPLANS:
		_close(call, "blocked", "The ambulance could not get through%s, so dispatch closed the medical call." % _near_text(ambulance.global_position))
		return
	unit.replans = int(unit.replans) + 1
	counters.replans = int(counters.replans) + 1
	var jam := _jam_lane()
	if jam >= 0:
		lanes.block(jam, _clock)
	var plan := _plan_route(Vector3(call.at))
	if bool(plan.get("ok", false)):
		plan = _from_here(_with_pull_over(plan))
	if bool(plan.get("ok", false)):
		unit.lead_length = -1.0
		_apply_route(plan, "respond", RESPOND_SPEED)

func _arrive(call: Dictionary, at_end: bool) -> void:
	var parked: Dictionary = unit.route_parked
	driver.clear_leg()
	driver.hold = false
	unit.mode = "on_scene"
	unit.spot = parked.duplicate() if at_end and not parked.is_empty() else {"kind": "lane"}
	unit.leave_wait = 0.0
	unit.clear_ref = str(call.ref)
	unit.clear_from = ambulance.global_position
	call.arrived = _clock
	call.scene_since = _clock
	call.clearance = "at_scene"
	counters.arrivals = int(counters.arrivals) + 1
	for entry in crew:
		entry.exit_tries = 0
	_transition(call, "on_scene", "The ambulance has arrived. Paramedics are going to the injured person.")

func _drive_return() -> void:
	if driver.finished():
		var parked: Dictionary = unit.route_parked
		var backed := driver.kind() == "back_in"
		driver.clear_leg()
		driver.emergency = false
		unit.home_replans = 0
		if not backed and bool(parked.get("back_in", false)):
			# At the street end of the bay's approach: back in along it.
			if not _back_in(INF):
				_strand()
			return
		unit.mode = "parked"
		if backed:
			unit.spot = (base.home as Dictionary).duplicate() if str((base.home as Dictionary).kind) == "bay" else {"kind": "lane"}
		else:
			unit.spot = parked.duplicate() if not parked.is_empty() else {"kind": "lane"}
		# Home (the bay, or the standby that leaves the travel lane free): traffic
		# no longer needs to treat it as an obstacle.
		_traffic_presence(not (str(unit.spot.get("kind", "")) == "bay" or bool(unit.spot.get("home", false))))
		revision += 1
		_assign()
		return
	if driver.wait_time >= _wait_limit(driver.wait_reason) * 2.0:
		driver.wait_time = 0.0
		unit.home_replans = int(unit.home_replans) + 1
		if driver.kind() == "back_in" or int(unit.home_replans) > MAX_REPLANS:
			_strand()
			return
		var jam := _jam_lane()
		if jam >= 0:
			lanes.block(jam, _clock)
		var plan := _plan_home()
		if bool(plan.get("ok", false)):
			_apply_route(plan, "return", RETURN_SPEED)
		# A failed replan keeps the current route; the next wait decides again.

## Back to the hospital: straight to the next waiting call if there is one, else
## the curb standby. A call that ended before the ambulance moved leaves it
## where it was; one that ended while it was still on the canopy approach backs
## it into the bay along that same approach.
func _head_home() -> void:
	unit.call = ""
	driver.emergency = false
	driver.hold = false
	var from_spot: Dictionary = unit.get("from_spot", {})
	if driver.kind() == "respond" and driver.s <= 0.5 and not from_spot.is_empty():
		driver.clear_leg()
		unit.mode = "parked"
		unit.spot = from_spot.duplicate()
		_traffic_presence(not (str(from_spot.get("kind", "")) == "bay" or bool(from_spot.get("home", false))))
		revision += 1
		if _next_waiting():
			_assign()
		return
	if str(unit.from_kind) == "bay" and driver.kind() == "respond" and driver.s <= float(unit.lead_length) + 0.5 \
			and _back_in(driver.s):
		return
	if _next_waiting() and _ambulance_free_after_call():
		return
	var plan := _plan_home()
	if not bool(plan.get("ok", false)):
		_strand()
		return
	unit.mode = "returning"
	unit.home_replans = 0
	_apply_route(plan, "return", RETURN_SPEED)

func _next_waiting() -> bool:
	for call in calls:
		if not bool(call.closing) and str(call.stage) in ["requested", "queued"]:
			return true
	return false

## Leaving a scene (or turning back) with a call waiting: dispatch it from here.
func _ambulance_free_after_call() -> bool:
	var previous := str(unit.mode)
	unit.mode = "returning"
	if not _ambulance_free():
		unit.mode = previous
		return false
	for call in calls:
		if bool(call.closing) or not str(call.stage) in ["requested", "queued"] or _clock < float(call.get("next_retry", 0.0)):
			continue
		if _dispatch(call):
			return true
	unit.mode = previous
	return false

func _strand() -> void:
	driver.clear_leg()
	unit.mode = "stranded"
	unit.home_tries = 0
	unit.next_home = _clock + HOME_RETRY_SECONDS

## The road at a scene is clear once the ambulance has really driven away.
func _update_clearance() -> void:
	var ref := str(unit.get("clear_ref", ""))
	if ref.is_empty() or str(unit.mode) == "on_scene" or not is_instance_valid(ambulance):
		return
	var from: Vector3 = unit.get("clear_from", Vector3.INF)
	if from.is_finite() and Lanes.flat(ambulance.global_position, from) < CLEAR_DISTANCE:
		return
	unit.clear_ref = ""
	for i in range(history.size() - 1, -1, -1):
		var call: Dictionary = history[i]
		if str(call.get("ref", "")) == ref:
			call.clearance = "cleared"
			_step(call, "cleared", "The ambulance has left the scene; the street is clear.")
			_relay(call, false)
			break

# --------------------------------------------------------------- the scene (4 Hz)

func _think() -> void:
	counters.thinks = int(counters.thinks) + 1
	_check_crew()
	for call in calls.duplicate():
		_think_call(call)
	_think_unit()
	_assign()

func _think_call(call: Dictionary) -> void:
	if bool(call.closing):
		return
	var person := _patient_state(str(call.patient))
	var before := str(call.stage) in Status.PRE_ARRIVAL
	match str(person.state):
		"dead":
			_close(call, "patient_died", "The injured person died before the ambulance arrived." if before \
				else "The injured person died before paramedics could help.")
			return
		"custody":
			_close(call, "in_custody", "Officers took the injured person into custody, so the ambulance stood down.")
			return
		"absent":
			_close(call, "patient_left", "The injured person had gone before paramedics reached them.")
			return
	if Vector3(person.position).is_finite():
		call.at = person.position
	call.patient_state = str(person.state)
	call.unsafe = _scene_unsafe(call)
	_try_hold(call)
	var stage := str(call.stage)
	if stage == "queued" and _clock - float(call.opened) >= QUEUE_LIMIT:
		_close(call, "unavailable", "No ambulance became free in time, so dispatch closed the medical call.")
		return
	if stage in Status.PRE_ARRIVAL and _clock - float(call.opened) >= ARRIVAL_LIMIT:
		_close(call, "timeout", "The ambulance could not reach the injured person in time.")
		return
	if str(unit.call) == str(call.id) and str(unit.mode) == "on_scene":
		_tick_scene(call)

func _tick_scene(call: Dictionary) -> void:
	# This deadline covers busy patients and every early attendance/safety return.
	if _clock - float(call.scene_since) >= SCENE_LIMIT:
		_close(call, "no_access", "Paramedics could not complete care at the scene in time, so the ambulance left.")
		return
	var at: Vector3 = call.at
	if bool(call.unsafe):
		_recall_crew("Back to the ambulance! We wait for the police.")
		if str(call.stage) != "staging":
			_transition(call, "staging", "Paramedics are waiting in the ambulance until the scene is safe.")
		call.safety_wait = float(call.safety_wait) + THINK_INTERVAL
		if float(call.safety_wait) >= SAFETY_LIMIT:
			_close(call, "unsafe", "The scene never became safe for paramedics, so the ambulance left.")
		return
	if str(call.stage) == "staging":
		_transition(call, "on_scene", "The scene is safe now. Paramedics are going to the injured person.")
	var out := 0
	var can_exit := 0
	for i in crew.size():
		var entry: Dictionary = crew[i]
		if str(entry.state) == "seated" and _crew_free(entry) and int(entry.exit_tries) < MAX_EXIT_TRIES:
			entry.exit_tries = int(entry.exit_tries) + 1
			_dismount(i, call)
		if str(entry.state) == "seated" and _crew_free(entry) and int(entry.exit_tries) < MAX_EXIT_TRIES:
			can_exit += 1
		if str(entry.state) in ["to_patient", "with_patient"]:
			out += 1
	if out == 0 and can_exit == 0 and str(call.stage) != "treating":
		_close(call, "no_access", "Paramedics could not get out of the ambulance to reach the injured person.")
		return
	var attending := 0
	var trying := 0
	for entry in crew:
		if not str(entry.state) in ["to_patient", "with_patient"]:
			continue
		var actor = entry.actor
		if not _crew_ours(entry):
			continue
		if _treatment_contact(actor, call):
			if str(entry.state) != "with_patient":
				entry.state = "with_patient"
				actor.speak("You're going to be okay. Let's take a look.", 2.2)
			attending += 1
			continue
		if str(entry.state) == "with_patient":
			entry.state = "to_patient"
		if bool(entry.gave_up):
			continue
		trying += 1
		if Tactics.flat(Vector3(entry.goal), at) > 2.0 or int(entry.index) >= (entry.path as Array).size():
			if int(entry.reroutes) < MAX_REROUTES:
				_walk_to(entry, at)
			else:
				entry.gave_up = true
		elif float(entry.stuck) >= CREW_STUCK_SECONDS:
			_unstick_crew(entry, at)
	if attending > 0:
		if str(call.stage) != "treating":
			_transition(call, "treating", "A paramedic is with the injured person.")
		# Care only counts while the person is calm and still (not fighting or
		# fleeing); the paramedic stays with them meanwhile.
		if str(call.get("patient_state", "")) == "ok":
			call.treat_time = float(call.treat_time) + THINK_INTERVAL
			if float(call.treat_time) >= TREAT_SECONDS:
				_treated(call)
		return
	if out > 0 and trying == 0:
		_close(call, "no_access", "Paramedics could not reach the injured person on foot, so the ambulance left.")
		return

## Shared by walking and treatment: reach must be on the same level with a
## clear physical link to the exact patient. At most two short rays per tick.
func _treatment_contact(actor: Node3D, call: Dictionary, reach := TREAT_RANGE) -> bool:
	if not is_instance_valid(actor) or call.is_empty():
		return false
	var patient = _patient_body(str(call.get("patient", "")))
	if not is_instance_valid(patient) or not patient is Node3D:
		return false
	var at: Vector3 = (patient as Node3D).global_position
	var from: Vector3 = actor.global_position
	if Tactics.flat(from, at) > reach or absf(from.y - at.y) > TREAT_HEIGHT:
		return false
	var space := _space()
	if space == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(from + Vector3.UP, at + Vector3.UP, 1 | 2 | 4 | 8 | 16)
	var exclude: Array[RID] = []
	if actor is CollisionObject3D:
		exclude.append((actor as CollisionObject3D).get_rid())
	if patient is CollisionObject3D:
		exclude.append((patient as CollisionObject3D).get_rid())
	query.exclude = exclude
	return space.intersect_ray(query).is_empty()

func _patient_body(id: String):
	var held = people.body_of(id)
	if is_instance_valid(held):
		return held
	var named = _named(id)
	if is_instance_valid(named):
		return named
	var combat = _combat()
	if combat != null and combat.has_method("npc_fight_status"):
		var fighting = combat.npc_fight_status(id).get("actor")
		if is_instance_valid(fighting):
			return fighting
	if id.begins_with("crowd_") and id.substr(6).is_valid_int():
		var crowd = _crowd()
		var index := int(id.substr(6))
		if crowd != null and index >= 0 and index < crowd.residents.size():
			return crowd.residents[index].get("body")
	return null

func _treated(call: Dictionary) -> void:
	var body = people.body_of(str(call.patient))
	if body != null:
		body.speak("Thank you. I'm okay now.", 2.2)
	for entry in crew:
		if str(entry.state) == "with_patient" and is_instance_valid(entry.actor):
			entry.actor.speak("You're all set. Take it easy today.", 2.0)
			break
	counters.treated = int(counters.treated) + 1
	_close(call, "treated", "Paramedics treated the injured person, who is back on their feet.")

func _think_unit() -> void:
	match str(unit.mode):
		"on_scene":
			if not str(unit.call).is_empty():
				return
			unit.leave_wait = float(unit.leave_wait) + THINK_INTERVAL
			if _crew_settled() or float(unit.leave_wait) >= CREW_RETURN_LIMIT:
				_leave_scene()
		"stranded":
			if _clock < float(unit.next_home):
				return
			unit.next_home = _clock + HOME_RETRY_SECONDS
			var plan := _plan_home()
			if bool(plan.get("ok", false)):
				unit.mode = "returning"
				unit.home_replans = 0
				_apply_route(plan, "return", RETURN_SPEED)
			elif int(unit.home_tries) >= HOME_RETRIES and _unseen(ambulance):
				_recover_home()
			else:
				unit.home_tries = int(unit.home_tries) + 1

func _leave_scene() -> void:
	unit.leave_wait = 0.0
	if _next_waiting() and _ambulance_free_after_call():
		return
	var plan := _plan_home()
	if not bool(plan.get("ok", false)):
		_strand()
		return
	unit.mode = "returning"
	unit.home_replans = 0
	_apply_route(plan, "return", RETURN_SPEED)

## Last resort for an ambulance that cannot drive home: put back at the hospital
## only while nobody can see it (like traffic's out-of-view recycling).
func _recover_home() -> void:
	counters.recoveries = int(counters.recoveries) + 1
	for entry in crew:
		if str(entry.state) in ["to_patient", "with_patient", "to_ambulance"] and _crew_ours(entry):
			if _unseen(entry.actor):
				_seat(entry)
			else:
				# Keep visible people in the world. Their existing return path and
				# _check_crew's per-person unseen gate finish recovery later.
				entry.state = "to_ambulance"
				entry.recalled = _clock
	_place_home()

func _place_home() -> void:
	var home: Dictionary = base.get("home", {})
	if home.is_empty() or not is_instance_valid(ambulance):
		return
	ambulance.global_transform = home.pose
	ambulance.collision_layer = 16
	ambulance.visible = true
	if ambulance.has_method("reset_physics_interpolation"):
		ambulance.reset_physics_interpolation()
	driver.clear_leg()
	driver.reset_ground()
	driver.emergency = false
	driver.hold = false
	unit.mode = "parked"
	unit.spot = (home.curb as Dictionary).duplicate() if str(home.kind) == "curb" else home.duplicate()
	unit.route_parked = {}
	unit.home_tries = 0
	unit.home_replans = 0
	_traffic_presence(false)
	for entry in crew:
		if str(entry.state) == "seated":
			_seat(entry)

## Traffic treats the ambulance as a real obstacle (cars queue behind it, its
## surroundings stay physical far from the explorer) while it is out on the
## road; parked at its home it leaves every travel lane free and is let go.
func _traffic_presence(on_road: bool) -> void:
	if not on_road:
		driver.release_junctions()
	var traffic = _traffic()
	if traffic == null or not is_instance_valid(traffic) or not is_instance_valid(ambulance) or not ambulance.is_inside_tree():
		_on_traffic = false
		return
	if on_road and not _on_traffic and traffic.has_method("register_emergency_vehicle"):
		_on_traffic = bool(traffic.register_emergency_vehicle(ambulance))
	elif not on_road and _on_traffic and traffic.has_method("unregister_emergency_vehicle"):
		traffic.unregister_emergency_vehicle(ambulance)
		_on_traffic = false

# --------------------------------------------------------------- calls

func _call(id: String) -> Dictionary:
	for call in calls:
		if str(call.id) == id:
			return call
	return {}

func _transition(call: Dictionary, stage: String, text: String, notify := true) -> void:
	var key := "%s:%s" % [stage, str(call.get("outcome", ""))]
	if str(call.get("stage_key", "")) == key:
		return
	call.stage_key = key
	call.stage = stage
	call.text = text.left(160)
	call.updated_minutes = _minutes()
	_step(call, stage, text)
	counters.transitions = int(counters.transitions) + 1
	revision += 1
	_relay(call, notify)

func _step(call: Dictionary, stage: String, text: String) -> void:
	var timeline: Array = call.timeline
	timeline.append({"stage": stage, "outcome": str(call.get("outcome", "")), "text": text.left(120), "minutes": _minutes()})
	while timeline.size() > Status.MAX_TIMELINE:
		timeline.remove_at(1) # Keep the request itself.

## Bound all linked identities, including legacy in-memory fixtures without refs.
func _call_refs(call: Dictionary) -> Array:
	var refs: Array = call.get("refs", [str(call.get("ref", ""))])
	return refs.slice(0, MAX_CALL_REFS)

func _relay(call: Dictionary, notify: bool) -> void:
	if not bool(call.get("relay", true)) or incidents == null or not is_instance_valid(incidents) \
			or not incidents.has_method("on_medical_progress"):
		return
	var first := true
	for ref in _call_refs(call):
		counters.relays = int(counters.relays) + 1
		incidents.on_medical_progress(str(ref), {"call_id": str(call.id), "patient": str(call.patient),
			"injury": str(call.injury), "stage": str(call.stage), "outcome": str(call.get("outcome", "")),
			"text": str(call.text), "clearance": str(call.get("clearance", "")), "notify": notify and first,
			"timeline": (call.timeline as Array).duplicate(true)})
		first = false

func _close(call: Dictionary, outcome: String, text: String) -> void:
	if bool(call.get("closing", false)):
		return
	call.closing = true
	call.outcome = outcome
	var patient := str(call.patient)
	if outcome == "patient_died":
		people.forget(patient) # Never released, never revived: combat keeps the body.
	elif people.owns(patient):
		people.release(patient)
	var stage := Status.terminal_stage(outcome)
	if stage == "failed":
		counters.failed = int(counters.failed) + 1
	elif stage == "cancelled":
		counters.cancelled = int(counters.cancelled) + 1
	_transition(call, stage, text)
	calls.erase(call)
	history.append(_summary(call))
	while history.size() > MAX_HISTORY:
		history.pop_front()
	if str(unit.call) != str(call.id):
		return
	if str(unit.mode) == "on_scene":
		unit.call = ""
		unit.leave_wait = 0.0
		_recall_crew("Okay, we're done here." if outcome == "treated" else "")
	else:
		_head_home()

func _summary(call: Dictionary) -> Dictionary:
	return {"id": str(call.id), "ref": str(call.ref), "refs": _call_refs(call).duplicate(), "patient": str(call.patient), "injury": str(call.injury),
		"at": call.at, "street": str(call.street), "phone": bool(call.phone), "stage": str(call.stage),
		"outcome": str(call.get("outcome", "")), "text": str(call.text), "clearance": str(call.get("clearance", "")),
		"opened_minutes": float(call.opened_minutes), "updated_minutes": float(call.updated_minutes),
		"held": people.owns(str(call.patient)), "treat_time": float(call.get("treat_time", 0.0)),
		"timeline": (call.timeline as Array).duplicate(true)}

# --------------------------------------------------------------- the injured person

## {state: ok | busy | dead | custody | absent, position}. Missing people are
## absent, never inferred dead: combat's registry and the person's own flags decide.
func _patient_state(id: String) -> Dictionary:
	var result := {"state": "absent", "position": Vector3.INF}
	if id.is_empty() or id == "player":
		return result
	if _dead_id(id):
		result.state = "dead"
		return result
	if people.owns(id):
		if people.still_ours(id):
			result.state = "ok"
			result.position = (people.body_of(id) as Node3D).global_position
			return result
		var body = people.body_of(id)
		people.forget(id) # Combat, custody or police took the body.
		if is_instance_valid(body) and (body.get("dead") == true or bool(body.get_meta("city_dead", false))):
			result.state = "dead"
			return result
	if id.begins_with("crowd_") and id.substr(6).is_valid_int():
		var crowd = _crowd()
		var index := int(id.substr(6))
		if crowd == null or index < 0 or index >= crowd.residents.size():
			return result
		var resident: Dictionary = crowd.residents[index]
		if bool(resident.get("dead", false)):
			result.state = "dead"
		elif bool(resident.get("police_custody", false)) or bool(resident.get("police_custody_completed", false)):
			result.state = "custody"
		elif bool(resident.get("identity_unplaced", false)):
			result.state = "absent"
		else:
			var busy := bool(resident.get("combat_controlled", false)) or bool(resident.get("panic", false))
			result.state = "busy" if busy else "ok"
			result.position = resident.position
			var combat = _combat()
			if busy and combat != null and combat.has_method("npc_fight_status"):
				var body = combat.npc_fight_status(id).get("actor")
				if is_instance_valid(body) and body is Node3D:
					result.position = (body as Node3D).global_position
		return result
	var actor = _named(id)
	if not is_instance_valid(actor):
		return result
	if actor.get("dead") == true or bool(actor.get_meta("city_dead", false)):
		result.state = "dead"
	elif bool(actor.get_meta("police_custody", false)) or bool(actor.get_meta("police_custody_completed", false)):
		result.state = "custody"
	elif actor.get("enabled") != true:
		result.state = "absent"
	else:
		result.state = "busy" if actor.get("combat_override") == true else "ok"
		result.position = (actor as Node3D).global_position
	return result

func _try_hold(call: Dictionary) -> void:
	var patient := str(call.patient)
	if bool(call.closing) or people.owns(patient) or not Status.is_live(str(call.stage)):
		return
	if not people.hold_blocker(patient).is_empty():
		return
	var body := people.hold(patient, str(call.id))
	if body != null:
		counters.holds = int(counters.holds) + 1
		body.speak("Ow… I need a minute.", 2.0)

func _tick_patients(delta: float) -> void:
	for call in calls:
		var patient := str(call.patient)
		if not people.owns(patient):
			continue
		if not people.still_ours(patient):
			continue # The next think decides what happened (combat, custody, death).
		var face := Vector3.INF
		var attended := false
		for entry in crew:
			if str(entry.state) == "with_patient" and is_instance_valid(entry.actor):
				face = (entry.actor as Node3D).global_position
				attended = true
				break
		people.pose(patient, delta, face, attended)

# --------------------------------------------------------------- paramedics

func _dismount(index: int, call: Dictionary) -> bool:
	var entry: Dictionary = crew[index]
	var actor = entry.actor
	if not is_instance_valid(actor) or not is_instance_valid(ambulance):
		return false
	for door in _door_order(Vector3(call.at)):
		var spot := _exit_spot(actor, float(door[0]), float(door[1]))
		if not spot.is_finite():
			continue
		var heading := Tactics.heading_to(spot, Vector3(call.at), float(actor.yaw))
		actor.global_position = spot
		actor.yaw = heading
		actor.velocity = Vector3.ZERO
		if actor.puppet != null:
			actor.puppet.g.rotation.y = heading
		actor.set_enabled(true)
		if actor.enabled != true:
			return false
		if actor.has_method("reset_physics_interpolation"):
			actor.reset_physics_interpolation()
		actor.combat_override = true
		actor.has_target = false
		actor.set_meta(DUTY_META, str(call.id))
		_give_kit(entry)
		entry.door = spot
		entry.state = "to_patient"
		entry.reroutes = 0
		entry.unstick = 0
		entry.gave_up = false
		_walk_to(entry, Vector3(call.at))
		actor.speak("Paramedics! We're here to help." if index == 0 else "Coming through.", 2.0)
		return true
	return false

## The side facing the injured person first (so the ambulance is never between
## the crew and them), then the back doors, then the far side.
func _door_order(toward: Vector3) -> Array:
	var half := Models.dimensions(AmbulanceDriver.KIND).x * 0.5 + 0.55
	var back := -(Models.dimensions(AmbulanceDriver.KIND).z * 0.5 + 0.7)
	var near_side := 1.0
	if toward.is_finite() and is_instance_valid(ambulance):
		var forward := _forward()
		var side := Vector3(forward.z, 0.0, -forward.x)
		near_side = 1.0 if (toward - ambulance.global_position).dot(side) >= 0.0 else -1.0
	return [[near_side * half, 0.3], [near_side * half, -1.0], [0.0, back], [-near_side * half, 0.3], [-near_side * half, -1.0]]

## A capsule-checked standing spot beside a door, at the car's height, with a
## clear step out from the seat (the police crews' door check).
func _exit_spot(actor, lateral: float, along: float) -> Vector3:
	var space := _space()
	if space == null:
		return Vector3.INF
	var forward := _forward()
	var side := Vector3(forward.z, 0.0, -forward.x)
	var base_at := ambulance.global_position
	var at := base_at + side * lateral + forward * along
	var none: Array[RID] = []
	var ground := _tactics.first_hit(at + Vector3.UP * 1.0, at - Vector3.UP * 1.5, none, 1)
	if ground.is_empty() or Vector3(ground.normal).y < 0.67:
		return Vector3.INF
	var foot: Vector3 = ground.position
	if absf(foot.y - base_at.y) > 0.6:
		return Vector3.INF
	var shape: Shape3D = null
	var center := 0.9
	var collider = actor.get("capsule")
	if collider is CollisionShape3D:
		shape = (collider as CollisionShape3D).shape
		center = (collider as CollisionShape3D).position.y
	if shape == null:
		return Vector3.INF
	# A second dismount can happen in this same think, before the physics
	# broadphase sees the first body's new pose/layer. Reserve that live capsule
	# explicitly as well as retaining all of the world collision queries below.
	if shape is CapsuleShape3D:
		var own_capsule := shape as CapsuleShape3D
		var low := foot.y + 0.012 + center - own_capsule.height * 0.5
		var high := low + own_capsule.height
		for member in crew:
			var other = member.actor
			if not is_instance_valid(other) or other == actor or not other.enabled:
				continue
			var other_collider = other.get("capsule")
			if not other_collider is CollisionShape3D or not other_collider.shape is CapsuleShape3D:
				continue
			var other_capsule := other_collider.shape as CapsuleShape3D
			var other_low: float = other.global_position.y + other_collider.position.y - other_capsule.height * 0.5
			var other_high := other_low + other_capsule.height
			if low <= other_high + 0.03 and high >= other_low - 0.03 \
					and Tactics.flat(foot, other.global_position) < own_capsule.radius + other_capsule.radius + 0.06:
				return Vector3.INF
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
		return Vector3.INF
	# No bank or wall of terrain above curb height beside the door.
	_slot_query.transform.origin += Vector3.UP * 0.30
	_slot_query.collision_mask = 1
	if not space.intersect_shape(_slot_query, 1).is_empty():
		return Vector3.INF
	if _sweep_query == null:
		_sweep_query = PhysicsShapeQueryParameters3D.new()
		var ball := SphereShape3D.new()
		ball.radius = 0.22
		_sweep_query.shape = ball
		_sweep_query.collision_mask = 2 | 4 | 8 | 16
	var seat := base_at + forward * clampf(along, -1.2, 1.2) + Vector3.UP * 1.0
	_sweep_query.transform = Transform3D(Basis.IDENTITY, seat)
	_sweep_query.motion = foot + Vector3.UP * 1.0 - seat
	var ignore: Array[RID] = [ambulance.get_rid(), actor.get_rid()]
	_sweep_query.exclude = ignore
	var fractions := space.cast_motion(_sweep_query)
	if fractions.size() < 2 or fractions[0] < 1.0:
		return Vector3.INF
	return foot + Vector3.UP * 0.012

func _walk_to(entry: Dictionary, target: Vector3) -> void:
	var actor = entry.actor
	entry.path = _foot_route((actor as Node3D).global_position, target)
	entry.index = 0
	entry.goal = target
	entry.stuck = 0.0
	entry.reroutes = int(entry.get("reroutes", 0)) + 1

## A short clear link when there is one, else officers' street routes.
func _foot_route(from: Vector3, to: Vector3) -> Array:
	var path: Array = []
	if not from.is_finite() or not to.is_finite():
		return path
	if Tactics.flat(from, to) <= 1.0 or (Tactics.flat(from, to) <= DIRECT_WALK and _tactics.link_clear(from, to)):
		path.append(to)
		return path
	var law = level.get("law") if level != null else null
	var routes = law.get("routes") if law != null else null
	if routes != null and routes.has_method("route"):
		var plan: Dictionary = routes.route(from, to, FOOT_ROUTE_LIMIT)
		for point in plan.get("points", PackedVector3Array()):
			path.append(point)
	return path

func _tick_crew(delta: float) -> void:
	var call := _call(str(unit.call))
	var patient_at: Vector3 = call.get("at", Vector3.INF) if not call.is_empty() else Vector3.INF
	for entry in crew:
		var state := str(entry.state)
		if not state in ["to_patient", "with_patient", "to_ambulance"]:
			continue
		var actor = entry.actor
		if not _crew_ours(entry):
			_crew_lost(entry)
			continue
		Tactics.tick_body(actor, delta)
		if state == "with_patient" and not _treatment_contact(actor, call):
			entry.state = "to_patient"
			state = "to_patient"
		if state == "with_patient":
			if patient_at.is_finite():
				Tactics.face(actor, Tactics.heading_to(actor.global_position, patient_at, float(actor.yaw)), delta, 0.05)
			if actor.puppet != null:
				actor.puppet.pose({"walk": 0.0, "lean": 0.55, "bob": -0.2, "armR": [-1.25, 0.12], "armL": [-1.05, 0.2], "nod": 0.45})
				for leg in actor.puppet.legs:
					leg.rotation.x = -0.45
			continue
		if state == "to_patient" and _treatment_contact(actor, call, TREAT_RANGE - 0.25):
			Tactics.face(actor, Tactics.heading_to(actor.global_position, patient_at, float(actor.yaw)), delta, 0.05)
			_pose_walk(actor, false)
			continue # Within reach: the next think marks them with the patient.
		_step_path(entry, delta)
		if state == "to_ambulance" and _at_door(entry):
			_seat(entry)

func _step_path(entry: Dictionary, delta: float) -> void:
	var actor = entry.actor
	var path: Array = entry.path
	var index := int(entry.index)
	if index >= path.size():
		_pose_walk(actor, false)
		return
	var point: Vector3 = path[index]
	if Tactics.flat(actor.global_position, point) <= (0.25 if index == path.size() - 1 else 0.9):
		entry.index = index + 1
		entry.stuck = 0.0
		return
	var result := Tactics.walk(actor, point, delta, WALK_SPEED)
	if result == Tactics.MOVE_BLOCKED:
		entry.stuck = float(entry.stuck) + delta
	elif result == Tactics.MOVE_MOVED:
		entry.stuck = maxf(0.0, float(entry.stuck) - delta)
	_pose_walk(actor, bool(actor.moving))

func _pose_walk(actor, moving: bool) -> void:
	if actor.puppet != null:
		actor.puppet.pose({"walk": 0.55 if moving else 0.0, "armR": [-0.3, 0.1]})

## Beside the ambulance itself (by the door they used, while it still stands there).
func _at_door(entry: Dictionary) -> bool:
	if not is_instance_valid(ambulance):
		return false
	var at: Vector3 = (entry.actor as Node3D).global_position
	var door: Vector3 = entry.door
	var here := ambulance.global_position
	if Tactics.flat(at, here) <= 3.2:
		return true
	return door.is_finite() and Tactics.flat(at, door) <= BOARD_RANGE and Tactics.flat(door, here) <= 3.5

## Bounded recovery from a blocked step: sidestep, replan once, then stop pushing.
func _unstick_crew(entry: Dictionary, goal: Vector3) -> void:
	entry.stuck = 0.0
	entry.unstick = int(entry.get("unstick", 0)) + 1
	var actor = entry.actor
	if int(entry.unstick) > MAX_CREW_UNSTICK:
		entry.path = []
		entry.index = 0
		entry.gave_up = true
		return
	if int(entry.unstick) == 2:
		entry.path = _foot_route(actor.global_position, goal)
		entry.index = 0
		return
	var path: Array = entry.path
	var index := int(entry.index)
	if index >= path.size():
		return
	var at: Vector3 = actor.global_position
	var point: Vector3 = path[index]
	var forward := Vector3(point.x - at.x, 0.0, point.z - at.z).normalized()
	var side := Vector3(-forward.z, 0.0, forward.x) * (1.0 if int(entry.unstick) % 2 == 1 else -1.0)
	for offset in [side, -side]:
		var spot := _tactics.walkable(at + offset * 1.2 + forward * 0.4)
		if not spot.is_empty() and _tactics.link_clear(at, spot.position):
			path.insert(index, spot.position)
			return

## Everyone out on this call walks back to the door they used.
func _recall_crew(line := "") -> void:
	var spoke := line.is_empty()
	for entry in crew:
		if not str(entry.state) in ["to_patient", "with_patient"]:
			continue
		var actor = entry.actor
		entry.state = "to_ambulance"
		entry.recalled = _clock
		entry.gave_up = false
		entry.unstick = 0
		var door: Vector3 = entry.door if Vector3(entry.door).is_finite() else ambulance.global_position
		entry.path = _foot_route((actor as Node3D).global_position, door)
		entry.index = 0
		entry.goal = door
		entry.stuck = 0.0
		if not spoke:
			spoke = true
			actor.speak(line, 1.8)

func _seat(entry: Dictionary) -> void:
	var actor = entry.actor
	if not is_instance_valid(actor) or actor.dead == true:
		entry.state = "dead"
		return
	_take_kit(entry)
	if actor.has_meta(DUTY_META):
		actor.remove_meta(DUTY_META)
	actor.combat_override = false
	actor.set_enabled(false)
	actor.velocity = Vector3.ZERO
	if actor.puppet != null:
		actor.puppet.pose({"walk": 0.0})
	if is_instance_valid(ambulance) and ambulance.is_inside_tree() and actor.is_inside_tree():
		actor.global_position = ambulance.global_transform * SEAT_LOCAL
	entry.state = "seated"
	entry.path = []
	entry.index = 0
	entry.gave_up = false

func _crew_lost(entry: Dictionary) -> void:
	var actor = entry.actor
	_take_kit(entry)
	if is_instance_valid(actor) and actor.has_meta(DUTY_META):
		actor.remove_meta(DUTY_META)
	entry.state = "dead" if not is_instance_valid(actor) or actor.dead == true or _dead_id(str(entry.id)) else "lost"
	counters.crew_lost = int(counters.crew_lost) + 1

func _check_crew() -> void:
	for entry in crew:
		var actor = entry.actor
		if not is_instance_valid(actor) or actor.dead == true or _dead_id(str(entry.id)):
			if str(entry.state) != "dead":
				_take_kit(entry)
				entry.state = "dead"
				counters.crew_lost = int(counters.crew_lost) + 1
			continue
		match str(entry.state):
			"lost":
				# Combat (or another owner) let go: walk back to a waiting ambulance,
				# or step out of the world once nobody can see.
				if _crew_free(entry):
					if str(unit.mode) == "on_scene" and is_instance_valid(ambulance):
						actor.combat_override = true
						actor.set_meta(DUTY_META, "return")
						entry.state = "to_ambulance"
						entry.recalled = _clock
						var door: Vector3 = entry.door if Vector3(entry.door).is_finite() else ambulance.global_position
						entry.path = _foot_route(actor.global_position, door)
						entry.index = 0
						entry.goal = door
					elif _unseen(actor):
						_seat(entry)
			"to_ambulance":
				if float(entry.stuck) >= CREW_STUCK_SECONDS:
					_unstick_crew(entry, Vector3(entry.goal))
				if (_clock - float(entry.recalled) >= CREW_RETURN_LIMIT or str(unit.mode) != "on_scene") and _unseen(actor):
					_seat(entry) # Walked off toward the hospital out of everyone's sight.
	var had := available
	available = not base.is_empty() and _living_crew() > 0
	if had and not available:
		reason = "no paramedic crew"
		revision += 1

func _crew_settled() -> bool:
	for entry in crew:
		if str(entry.state) in ["to_patient", "with_patient", "to_ambulance"]:
			return false
	return true

func _living_crew() -> int:
	var count := 0
	for entry in crew:
		count += int(str(entry.state) != "dead")
	return count

func _seated_crew() -> int:
	var count := 0
	for entry in crew:
		count += int(str(entry.state) == "seated")
	return count

## Ours to move: alive, enabled, on duty for us and nobody else's (combat, custody).
func _crew_ours(entry: Dictionary) -> bool:
	var actor = entry.actor
	if not is_instance_valid(actor) or actor.dead == true or actor.enabled != true or actor.combat_override != true:
		return false
	if not actor.has_meta(DUTY_META) or actor.has_meta("police_custody"):
		return false
	return _combat_mode(actor) == "unknown"

## Nobody else holds this paramedic (seated, or released by combat).
func _crew_free(entry: Dictionary) -> bool:
	var actor = entry.actor
	if not is_instance_valid(actor) or actor.dead == true or actor.has_meta("police_custody"):
		return false
	return _combat_mode(actor) == "" or (actor.combat_override == true and actor.has_meta(DUTY_META) and _combat_mode(actor) == "unknown")

func _give_kit(entry: Dictionary) -> void:
	var actor = entry.actor
	if is_instance_valid(entry.get("kit")) or not is_instance_valid(actor) or actor.puppet == null or actor.puppet.hands.is_empty():
		return
	if _kit_material == null:
		_kit_material = StandardMaterial3D.new()
		_kit_material.albedo_color = Color("d9d6cc")
		_kit_material.roughness = 0.7
	var kit := MeshInstance3D.new()
	kit.name = "MedicalKit"
	var box := BoxMesh.new()
	box.size = Vector3(0.14, 0.24, 0.32)
	kit.mesh = box
	kit.material_override = _kit_material
	kit.position = Vector3(0.0, -0.12, 0.0)
	kit.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	actor.puppet.hands[0].add_child(kit)
	entry.kit = kit

func _take_kit(entry: Dictionary) -> void:
	var kit = entry.get("kit")
	if is_instance_valid(kit):
		kit.queue_free()
	entry.kit = null

# --------------------------------------------------------------- safety, looks, lookups

## Armed people near the patient: an armed fighter (combat's bounded list) or a
## police call for this incident still dealing with an armed suspect.
func _scene_unsafe(call: Dictionary) -> bool:
	var at: Vector3 = call.at
	if not at.is_finite():
		return false
	var combat = _combat()
	if combat != null and combat.has_method("fighter_snapshot"):
		for entry in combat.fighter_snapshot():
			var actor = entry.get("actor")
			if str(entry.get("mode", "")) == "gun" and is_instance_valid(actor) and actor is Node3D \
					and Tactics.flat((actor as Node3D).global_position, at) <= SAFETY_RADIUS:
				return true
	var police = level.get("police_assistance") if level != null else null
	if police != null and police.has_method("call_status"):
		var police_call: Dictionary = police.call_status(str(call.ref))
		if not police_call.is_empty() and not bool(police_call.get("closing", false)) and str(police_call.get("threat", "")) == "armed" \
				and str(police_call.get("stage", "")) in ["received", "queued", "dispatched", "en_route", "on_scene", "handling"]:
			return true
	return false

func _animate() -> void:
	var lit := driver.emergency and is_instance_valid(ambulance) and ambulance.visible
	var flash := fmod(_clock, 0.7) < 0.35
	for i in _lights.size():
		if is_instance_valid(_lights[i]):
			_lights[i].visible = lit and (flash if i == 0 else not flash)

## Traffic's own wheel animation (the prototype's spinners).
func _spin_wheels() -> void:
	if is_instance_valid(_model):
		Models.animate_spinners(_model, _wheel_spin)

func _forward() -> Vector3:
	if not is_instance_valid(ambulance):
		return Vector3.FORWARD
	var forward := Vector3(ambulance.global_basis.z.x, 0.0, ambulance.global_basis.z.z)
	return forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD

func _on_road(at: Vector3) -> bool:
	var traffic = _traffic()
	return traffic != null and traffic.has_method("on_road") and bool(traffic.on_road(at))

func _near_text(at: Vector3) -> String:
	if level != null and at.is_finite() and level.has_method("_nearest_street"):
		var street := str(level.call("_nearest_street", at))
		if not street.is_empty():
			return " near " + street.left(48)
	return ""

## Far from the explorer and outside their camera (police crews' rule).
func _unseen(body: Node3D) -> bool:
	var player = level.get("player") if level != null else null
	if not player is Node3D or not is_instance_valid(body):
		return true
	var at := body.global_position + Vector3.UP * 1.0
	var distance := Tactics.flat(at, (player as Node3D).global_position)
	if distance < HIDE_DISTANCE:
		return false
	var camera = player.get("camera")
	if camera is Camera3D and (camera as Camera3D).is_inside_tree() and distance < 160.0 and (camera as Camera3D).is_position_in_frustum(at):
		return false
	return true

func _named(id: String):
	for provider_name in ["npcs", "residents"]:
		var provider = level.get(provider_name) if level != null else null
		var actors = provider.get("actors") if provider != null else null
		if actors is Dictionary and (actors as Dictionary).has(id) and is_instance_valid(actors[id]):
			return actors[id]
	return null

func _combat_mode(actor) -> String:
	if not is_instance_valid(actor):
		return "gone"
	if actor.get("dead") == true:
		return "dead"
	var combat = _combat()
	if combat != null and combat.has_method("actor_mode"):
		return str(combat.actor_mode(actor))
	return "unknown" if actor.get("combat_override") == true else ""

func _dead_id(id: String) -> bool:
	var combat = _combat()
	return combat != null and combat.has_method("is_actor_dead") and bool(combat.is_actor_dead(id))

func _combat():
	return level.get("combat") if level != null else null

func _traffic():
	return level.get("traffic") if level != null else null

func _crowd():
	var npcs = level.get("npcs") if level != null else null
	return npcs.get("crowd") if npcs != null else null

func _minutes() -> float:
	var clock = level.get("world_time") if level != null else null
	if clock != null and clock.get("total_minutes") != null:
		return float(clock.get("total_minutes"))
	return 540.0 + _clock * 0.5

static func _xz(at: Vector3) -> String:
	return "(%.1f, %.1f)" % [at.x, at.z]

func _space() -> PhysicsDirectSpaceState3D:
	if is_inside_tree():
		var world := get_world_3d()
		if world != null:
			return world.direct_space_state
	return null

func _world_paused() -> bool:
	if level == null or level.get("paused") == true:
		return true
	var inspector = level.get("inspector")
	if inspector != null and inspector.get("active") == true:
		return true
	return is_inside_tree() and get_tree().paused

## Leaving the tree (teardown, fixtures): nobody is left on duty. Held people go
## back to ordinary life only while the crowd itself is still in the world (a
## whole-level teardown just lets them go with it).
func _exit_tree() -> void:
	driver.release_junctions()
	if _on_traffic:
		var traffic = _traffic()
		if traffic != null and is_instance_valid(traffic) and traffic.has_method("unregister_emergency_vehicle"):
			traffic.unregister_emergency_vehicle(ambulance)
		_on_traffic = false
	var crowd = _crowd()
	var crowd_alive: bool = crowd != null and is_instance_valid(crowd) and crowd.is_inside_tree() and not crowd.is_queued_for_deletion()
	for id in people.holds.keys().duplicate():
		if crowd_alive:
			people.release(str(id))
		else:
			people.forget(str(id))
	for entry in crew:
		var actor = entry.actor
		if is_instance_valid(actor) and actor.is_inside_tree() and not actor.is_queued_for_deletion() and str(entry.state) != "dead" \
				and (_crew_ours(entry) or _crew_free(entry)):
			_seat(entry) # Disabled and hidden where they stand; the ambulance is leaving with us.

