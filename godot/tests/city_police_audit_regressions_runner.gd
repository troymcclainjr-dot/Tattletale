extends Node
## State-machine regressions for the independent audit patch. Lane projections,
## direct-path construction, speed planning, blockage timers and radio updates
## use production methods. Synthetic pavement/visibility isolate these contracts;
## this fixture does not claim to validate physical LOS or driving collisions.
const Cruisers := preload("res://scripts/city/city_police_cruisers.gd")
const Lanes := preload("res://scripts/city/city_police_lanes.gd")

class NetworkFixture:
	extends RefCounted
	var lanes: Array = [
		{"id": 0, "enabled": true, "to": "junction", "points": [Vector3(0, 0, 0), Vector3(0, 0, 20)]},
		{"id": 1, "enabled": true, "to": "end", "points": [Vector3(0, 0, 30), Vector3(0, 0, 70)]}]
	var nodes: Dictionary = {"junction": {"out": [1]}, "end": {"out": []}}
	func on_road(_at: Vector3, _margin := 0.12) -> bool:
		return true # Wide paved intersection: shortcut checks used to accept it.
class CarFixture:
	extends CharacterBody3D
	var speed := 0.0
	var yaw := 0.0
class LawFixture:
	extends Node
	var wanted := 3
	var recovering := false
	var last_known_position := Vector3(0, 0, 40)
	var player_location := Vector3(0, 0, 80)
	var lost_sight_seconds := 1.0
	var observations := 0
	func _vehicle_body() -> Object:
		return null
	func _player_feet() -> Vector3:
		return player_location
	func _observe_player(at: Vector3) -> void:
		observations += 1
		last_known_position = at
class PerceptionProbe:
	extends "res://scripts/city/city_police_cruisers.gd"
	var visible_car: Node3D
	func _crew_sees(car: Node3D) -> bool:
		return car == visible_car
	func _direct_path(_unit: Dictionary, _goal: Vector3) -> bool:
		return false
	func _needs_replan(_unit: Dictionary, _goal: Vector3) -> bool:
		return false
	func _maybe_dismount(_unit: Dictionary) -> void:
		pass

var failures := 0
var passes := 0

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	passes += int(ok)
	failures += int(not ok)
	print("[police_audit] %s %s" % ["PASS" if ok else "FAIL", label])

func unit(car: CarFixture, goal: Vector3, lane := 0) -> Dictionary:
	var path := PackedVector3Array([car.global_position, goal])
	var sums := Lanes.cumulative(path)
	return {"car": car, "owner": "law_cruiser_fixture", "goal": goal, "planned_goal": goal, "mode": "respond", "emergency": true,
		"path": path, "sums": sums, "length": sums[-1], "limits": PackedFloat32Array([12.0, 12.0]),
		"segments": [{"kind": "lane", "lane": lane, "s": 0.0, "along": 0.0}], "junctions": [],
		"s": 0.0, "cursor": 0, "remaining": sums[-1], "odometer": 0.0, "unstick_odometer": 0.0,
		"unstick": 0, "stuck": 0.0, "contacts": 0, "last_contact": {}, "yielding": false,
		"obstacle": INF, "obstacle_kind": "", "obstacle_speed": 0.0, "blocked_time": 0.0,
		"pass_tried": false, "junction": {}, "release_pending": false, "plan_clock": 0.0,
		"path_kind": "lanes", "seen": false, "had_sight": false, "seen_clock": -INF,
		"frozen": false, "want_plan": false, "crew": 0}

func _run() -> void:
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	var world := Node3D.new()
	add_child(world)
	var car := CarFixture.new()
	world.add_child(car)
	car.position = Vector3(0, 0, 12)
	var manager := Cruisers.new()
	manager.lanes = Lanes.new()
	manager.lanes.setup(NetworkFixture.new())
	var crossing := unit(car, Vector3(0, 0, 40))
	crossing.junctions = [{"s": 8.0, "exit_s": 18.0, "node": "junction"}]
	var old_path: PackedVector3Array = crossing.path.duplicate()
	var accepted: bool = manager._direct_path(crossing, crossing.goal)
	check(not accepted and crossing.path == old_path and crossing.junctions.size() == 1, "close pursuit across intersection retains lane route and crossing metadata")
	car.position = Vector3(0, 0, 35)
	var straight := unit(car, Vector3(0, 0, 55), 1)
	check(manager._direct_path(straight, straight.goal), "safe shortcut wholly inside one lane still works")
	check(not straight.segments.is_empty() and int(straight.segments[0].lane) == 1, "same-lane shortcut retains lane identity for subsequent decisions")
	car.position = Vector3(0, 0, 40)
	var too_near_end := unit(car, Vector3(0, 0, 69), 1)
	check(not manager._direct_path(too_near_end, too_near_end.goal), "shortcut cannot discard bumper clearance at lane endpoint")
	car.position = Vector3.ZERO
	var blocked := unit(car, Vector3(0, 0, 35))
	blocked.obstacle = 3.4
	blocked.obstacle_kind = "person"
	var target: float = manager._target_speed(blocked, 0.0)
	check(target == 0.0, "person in stopping gap remains protected by zero target speed")
	for i in 130:
		manager._clock += 0.1
		manager._after_step(blocked, {"moved": 0.0, "contact": {}}, target, 0.1)
		if blocked.mode == "hold":
			break
	check(blocked.mode == "hold" and blocked.get("hold_reason", "") == "search", "persistent pedestrian blockage reaches bounded on-foot fallback")
	check(int(manager.counters.passes) == 0 and int(manager.counters.unsticks) == 0, "pedestrian fallback never overtakes or reverses toward the person")
	var released_wait := unit(car, Vector3(0, 0, 35))
	released_wait.blocked_time = 5.0
	manager._after_step(released_wait, {"moved": 0.1, "contact": {}}, 5.0, 0.1)
	check(float(released_wait.blocked_time) == 0.0, "cleared obstruction resets waiting budget")
	_check_radio(world, car)
	world.free()
	print("[police_audit] %d passed; %d failed" % [passes, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _check_radio(world: Node3D, first: CarFixture) -> void:
	var second := CarFixture.new()
	world.add_child(second)
	var law := LawFixture.new()
	world.add_child(law)
	var manager := PerceptionProbe.new()
	manager.law = law
	manager._clock = 10.0
	var sighted := unit(first, law.last_known_position)
	var occluded := unit(second, law.last_known_position)
	occluded.crew = 1
	manager.units = {1: sighted, 2: occluded}
	manager.crew = [{"state": "seated"}, {"state": "seated"}]
	manager.visible_car = first
	manager._unit_perceive(sighted)
	check(law.observations == 1 and law.last_known_position == law.player_location, "real-sighting boundary updates law's last-known location")
	check(occluded.goal == law.player_location and not bool(occluded.seen), "genuine cruiser sighting radios new goal to already-responding occluded unit")
	var known := law.last_known_position
	manager.visible_car = null
	law.player_location = Vector3(999, 0, 999)
	manager._clock += 2.0
	manager._unit_perceive(sighted)
	manager._unit_perceive(occluded)
	check(law.observations == 1 and law.last_known_position == known and sighted.goal == known and occluded.goal == known, "hidden player motion never changes either cruiser's remembered goal")
	# Existing own-sight precedence survives the extra radio publication.
	occluded.seen = true
	occluded.mode = "pursue"
	occluded.goal = Vector3(8, 0, 8)
	manager.radio(Vector3(50, 0, 50))
	check(occluded.goal == Vector3(8, 0, 8), "radio cannot replace another unit's own current sighting")
