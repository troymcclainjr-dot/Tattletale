extends Node
## Focused review regressions; separate from the full EMS arena/city fixtures.
const Emergency := preload("res://scripts/city/city_emergency_response.gd")
const AmbulanceDriver := preload("res://scripts/city/city_ambulance_driver.gd")
class Person extends CharacterBody3D:
	var dead := false
	var enabled := true
	var combat_override := true
	var puppet = null
	var yaw := 0.0
	var _clock := 0.0
	var _speech_remaining := 0.0
	var _speech_label = null
	var moving := false
	func speak(_text: String, _seconds: float) -> void: pass
	func set_enabled(value: bool) -> void:
		enabled = value
		visible = value
class EMSReviewWorld extends Node3D:
	var player: Node3D
	var combat = null
	var traffic = null
	var world_time = null
	var npcs = null
	var residents = null
class Relay extends Node:
	var records := {}
	func on_medical_progress(ref: String, data: Dictionary) -> void:
		records[ref] = data.duplicate(true)
class Service extends Emergency:
	var patient: Person
	var patient_state := "ok"
	var assignments := 0
	var hold_attempts := 0
	var walking_steps := 0
	func _patient_body(_id: String): return patient
	func _patient_state(_id: String) -> Dictionary:
		return {"state": patient_state, "position": patient.global_position}
	func _assign() -> void: assignments += 1
	func _try_hold(_call_: Dictionary) -> void: hold_attempts += 1
	func _foot_route(from: Vector3, to: Vector3) -> Array: return [from, to]
	func _step_path(_entry: Dictionary, _delta: float) -> void: walking_steps += 1
class ConflictDriver extends AmbulanceDriver:
	var crossing := true
	var red := false
	func _crossing_traffic(_entry: Dictionary) -> bool: return crossing
	func _signal_red(_axis: String) -> bool: return red

var failures := 0
var passes := 0
var world: EMSReviewWorld
var service: Service
var relay: Relay
var medic: Person
var patient: Person
var entry: Dictionary

func _ready() -> void: _run.call_deferred()
func check(ok: bool, text: String) -> void:
	passes += int(ok)
	failures += int(not ok)
	print("[ems_review] %s %s" % ["PASS" if ok else "FAIL", text])
func _run() -> void:
	world = EMSReviewWorld.new()
	add_child(world)
	world.player = Node3D.new()
	world.add_child(world.player)
	service = Service.new()
	world.add_child(service)
	service.level = world
	service.people.setup(world, service)
	relay = Relay.new()
	world.add_child(relay)
	service.incidents = relay
	patient = Person.new()
	world.add_child(patient)
	patient.position = Vector3(1.2, 0, 0)
	service.patient = patient
	medic = Person.new()
	world.add_child(medic)
	medic.set_meta(Emergency.DUTY_META, "fixture")
	entry = {"id": "ems_paramedic_1", "actor": medic, "state": "with_patient", "exit_tries": 0,
		"gave_up": false, "goal": patient.position, "path": [], "index": 0, "reroutes": 0,
		"stuck": 0.0, "door": Vector3(-1, 0, 0), "recalled": 0.0, "unstick": 0}
	service.crew.append(entry)
	service.ambulance = AnimatableBody3D.new()
	# Match _ensure_ambulance(): manual driver/recovery steps are authoritative.
	# The default true defers/resets transform writes until a physics frame.
	service.ambulance.sync_to_physics = false
	service.add_child(service.ambulance)
	service.ambulance.position = Vector3(100, 0, 0)
	service.base = {"home": {"kind": "bay", "pose": Transform3D(Basis.IDENTITY, Vector3(200, 0, 0))}}
	service.available = true
	await get_tree().physics_frame
	await _contact_and_deadline()
	_linked_reports()
	_visible_recovery()
	_junction_yield()
	await _query_accounting()
	await _route_continuity()
	world.queue_free()
	await get_tree().process_frame
	print("[ems_review] %d passed; %d failed" % [passes, failures])
	get_tree().quit(1 if failures else 0)

func _new_call(ref: String) -> Dictionary:
	service.request({"ref": ref, "patient": "patient", "phone": true})
	return service.calls.back()
func _scene(call: Dictionary) -> void:
	call.stage = "on_scene"
	call.scene_since = service._clock
	call.unsafe = false
	call.patient_state = "ok"
	service.unit.call = str(call.id)
	service.unit.mode = "on_scene"
	entry.state = "with_patient"
	entry.gave_up = false
func _wall(at: Vector3, extent: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.collision_layer = 2
	wall.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = extent
	collision.shape = shape
	wall.add_child(collision)
	world.add_child(wall)
	wall.position = at
	return wall

func _contact_and_deadline() -> void:
	var call := _new_call("contact")
	_scene(call)
	check(service._treatment_contact(medic, call), "same-level unobstructed patient is in real treatment reach")
	service._tick_scene(call)
	check(float(call.treat_time) > 0.0, "real contact accumulates treatment")
	call.treat_time = 0.0
	patient.position.y = 3.0
	service._tick_scene(call)
	check(not service._treatment_contact(medic, call) and float(call.treat_time) == 0.0, "patient on another level never accrues treatment")
	patient.position.y = 0.0
	var wall := _wall(Vector3(0.6, 1.0, 0), Vector3(0.12, 2.0, 3.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	service._tick_scene(call)
	check(not service._treatment_contact(medic, call) and float(call.treat_time) == 0.0, "thin wall blocks treatment despite horizontal reach")
	entry.state = "with_patient"
	var before := service.walking_steps
	service._tick_crew(1.0 / 60.0)
	check(entry.state == "to_patient" and service.walking_steps > before, "walking and attendance share obstruction predicate and keep seeking access")
	wall.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	call.patient_state = "busy"
	entry.state = "with_patient"
	service._tick_scene(call)
	check(float(call.treat_time) == 0.0 and not bool(call.closing), "nearby busy patient receives no treatment before deadline")
	service._clock = float(call.scene_since) + Emergency.SCENE_LIMIT + 1.0
	service._tick_scene(call)
	check(bool(call.closing) and call.outcome == "no_access" and service.calls.is_empty(), "busy attendance cannot bypass scene deadline")
	check(entry.state == "to_ambulance" and str(service.unit.call).is_empty(), "deadline closes physical assignment and recalls crew")

func _linked_reports() -> void:
	service.crew.clear()
	service.unit.call = ""
	service.unit.mode = "parked"
	var first := _new_call("linked_a")
	var attempts := service.hold_attempts
	var assignments := service.assignments
	var response := service.request({"ref": "linked_b", "patient": "patient"})
	check(bool(response.ok) and bool(response.duplicate) and service.calls.size() == 1, "two incident refs share one physical patient call")
	check(service.hold_attempts == attempts and service.assignments == assignments, "linked report does not create a second hold or assignment")
	check(service.has_live("linked_a") and service.has_live("linked_b") and service.call_for("linked_b").id == first.id, "both refs resolve to the live shared response")
	check(relay.records.has("linked_a") and relay.records.has("linked_b"), "new linked report immediately receives current medical progress")
	service._transition(first, "treating", "A paramedic is with the injured person.")
	check(relay.records.linked_a.stage == "treating" and relay.records.linked_b.stage == "treating", "both records receive later physical progress")
	for i in range(2, Emergency.MAX_CALL_REFS):
		service.request({"ref": "linked_%d" % i, "patient": "patient"})
	var excess := service.request({"ref": "overflow", "patient": "patient"})
	check(not bool(excess.ok) and service._call_refs(first).size() == Emergency.MAX_CALL_REFS, "same-patient refs have a hard budget and overflow is explicit")
	service._close(first, "treated", "Care completed.")
	check(not service.has_live("linked_b") and service.call_for("linked_b").outcome == "treated", "linked refs resolve to the same closed history outcome")
	check(relay.records.linked_a.outcome == "treated" and relay.records.linked_b.outcome == "treated", "both durable incident relays receive final treatment result")
	_new_call("reload_a")
	service.request({"ref": "reload_b", "patient": "patient"})
	service.reset_state("checkpoint restore")
	check(not service.has_live("reload_a") and not service.has_live("reload_b"), "checkpoint reset leaves no phantom live linked response")
	check(relay.records.reload_a.outcome == "interrupted" and relay.records.reload_b.outcome == "interrupted", "checkpoint reset relays interruption to every associated record")

func _visible_recovery() -> void:
	service.crew.append(entry)
	entry.state = "to_ambulance"
	entry.stuck = 0.0
	medic.enabled = true
	medic.visible = true
	medic.combat_override = true
	medic.set_meta(Emergency.DUTY_META, "fixture")
	medic.position = Vector3.ZERO
	world.player.position = Vector3.ZERO
	service.ambulance.position = Vector3(100, 0, 0)
	var at := medic.global_position
	check(service._unseen(service.ambulance) and not service._unseen(medic), "recovery fixture has hidden ambulance and visible walking crew")
	service._recover_home()
	check(service.ambulance.position.x == 200.0 and medic.global_position == at and medic.enabled and medic.visible, "hidden vehicle recovery preserves visible crew position and visibility (ambulance=%s crew=%s enabled=%s visible=%s)" % [service.ambulance.position, medic.global_position, medic.enabled, medic.visible])
	check(entry.state == "to_ambulance", "visible crew remains on bounded per-person return path")
	world.player.position = Vector3(1000, 0, 0)
	service._check_crew()
	check(entry.state == "seated" and not medic.enabled, "crew recovery completes only after that person is unseen")

func _junction_yield() -> void:
	for emergency in [false, true]:
		var driver := ConflictDriver.new()
		driver.emergency = emergency
		driver.leg = {"junctions": [{"s": 4.0, "exit_s": 16.0, "signal": true, "axis": "x"}]}
		var always_yielded := true
		for i in 80:
			always_yielded = bool(driver._junction_state().get("yield", false)) and always_yielded
		check(always_yielded and driver._cleared.is_empty(), "persistent cross traffic keeps yielding beyond five seconds (emergency=%s)" % emergency)
		driver.crossing = false
		check(not bool(driver._junction_state().get("yield", true)), "cleared traffic permits approach (emergency=%s)" % emergency)
		driver.crossing = true
		check(bool(driver._junction_state().get("yield", false)), "new conflict before entry is rechecked rather than pre-cleared (emergency=%s)" % emergency)

func _query_accounting() -> void:
	var body := AnimatableBody3D.new()
	world.add_child(body)
	var driver := AmbulanceDriver.new()
	driver.setup(world, null, null, body)
	driver.set_leg(PackedVector3Array([Vector3.ZERO, Vector3(0, 0, 20)]), "fixture", 4.0)
	var wall := _wall(Vector3(0, 1.0, 8), Vector3(3, 2, 0.2))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var before := int(driver.counters.hull_queries)
	var obstacle := driver._sweep_ahead(12.0)
	check(is_finite(float(obstacle.distance)) and int(driver.counters.hull_queries) - before == 2, "ahead sweep counts both collision cast and contact classification query")
	wall.queue_free()
	body.queue_free()
	await get_tree().process_frame

func _route_continuity() -> void:
	var floor_body := _wall(Vector3(0, -0.5, 15), Vector3(20, 1, 60))
	floor_body.collision_layer = 1
	service.ambulance.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.3, 0.025, 0))
	var driver := AmbulanceDriver.new()
	driver.setup(world, null, null, service.ambulance)
	var raw := PackedVector3Array([Vector3.ZERO, Vector3(0, 0, 30)])
	await get_tree().physics_frame
	await get_tree().physics_frame
	var at := service.ambulance.global_position
	driver.set_leg(raw, "unjoined", 4.0)
	driver.tick(1.0 / 60.0)
	check(service.ambulance.global_position == at and driver.wait_reason == "route", "an unjoined lateral route cannot teleport the ambulance to its projection")
	var plan: Dictionary = service._from_here({"ok": true, "points": raw, "segments": [], "junctions": []})
	check(bool(plan.get("ok", false)) and (plan.points as PackedVector3Array)[0].distance_to(at) < 0.0001, "0.3 m lateral route gets a join beginning at the exact physical pose")
	if bool(plan.get("ok", false)):
		driver.set_leg(plan.points, "joined", 4.0, false, {"sums": plan.sums})
		var bounded := true
		var max_excess := 0.0
		for i in 240:
			if i == 120:
				# Restarting the same route midway must preserve forward progress.
				driver.set_leg(plan.points, "same_route", 4.0, false, {"sums": plan.sums})
			var before := service.ambulance.global_position
			driver.tick(1.0 / 60.0)
			var distance := before.distance_to(service.ambulance.global_position)
			var excess := distance - driver.speed / 60.0
			max_excess = maxf(max_excess, excess)
			bounded = bounded and excess <= 0.0051
		check(bounded, "every joined/restarted route step stays within speed times delta (max excess %.6f m)" % max_excess)
		check(service.ambulance.global_position.z > 5.0 and driver.odometer > 5.0, "continuity guard permits real progress rather than staying stopped (at=%s odometer=%.4f wait=%s)" % [service.ambulance.global_position, driver.odometer, driver.wait_reason])
	floor_body.queue_free()
	await get_tree().process_frame
