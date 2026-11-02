extends Node
## Incident aftermath and ambulance response in a small physics arena. The real
## incident service, emergency service (its ambulance driver, paramedics and
## patient holds), traffic lane network and NPC actors run over a two-block
## street grid with an off-road hospital bay; police dispatch, combat, crowd,
## traffic presence and the player are small recording fixtures (the narrow
## combat edits are checked on the real combat service at the end).
##
## Covers: a reported injury treated end to end with truthful stages (asked on
## the next tick, real movement before "en route", a real stop before "on
## scene", treatment only beside the person, nothing timed before arrival, no
## teleport), duplicate reports and requests that never dispatch twice, care
## independent of the police outcome, pause and inspector freezes, an
## unreachable patient (no pretend trip), a patient who dies (never treated,
## released or revived), a patient who leaves, a checkpoint restore that
## interrupts a response (faithful snapshot, honest "result unknown", retry by
## a repeat report), bounded calls and holds with truthful waiting, an armed
## scene that stages the ambulance short of it, and teardown that leaves nobody
## on duty. Run:
## python godot/tools/godot_run.py --timeout 900 -- --headless --script res://tests/city_emergency_response_smoke.gd
const Incidents := preload("res://scripts/city/city_incidents.gd")
const Emergency := preload("res://scripts/city/city_emergency_response.gd")
const People := preload("res://scripts/city/city_emergency_people.gd")
const EmergencyStatus := preload("res://scripts/city/city_emergency_status.gd")
const PoliceStatus := preload("res://scripts/city/city_police_status.gd")
const Network := preload("res://scripts/city/city_traffic_network.gd")
const Actor := preload("res://scripts/city/city_npc_actor.gd")
const Combat := preload("res://scripts/city/city_combat.gd")
const Player := preload("res://scripts/city/city_player.gd")
const DT := 1.0 / 60.0
const ROAD_WIDTH := 14.0
const BAY := Vector3(30.0, 0.03, 90.0)
const NOBODY := Vector3(-200.0, 0.012, 200.0)

class PlayerFixture:
	extends Node3D
	var yaw := 0.0
	var camera_yaw := 0.0
	var camera: Camera3D

class InspectorFixture:
	extends Node
	var active := false

class PeopleFixture:
	extends Node3D
	var actors: Dictionary = {}
	var crowd: Node3D

## The crowd's slot API as patient holds use it: one static body per resident;
## begin_combat hands the slot to a full stand-in body, end_combat takes it back.
class CrowdFixture:
	extends Node3D
	var residents: Array[Dictionary] = []
	var begun := 0
	var ended := 0
	func add(at: Vector3, yaw: float) -> int:
		var body := StaticBody3D.new()
		body.collision_layer = 8
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.28
		capsule.height = 1.6
		shape.shape = capsule
		shape.position = Vector3(0.0, 0.88, 0.0)
		body.add_child(shape)
		add_child(body)
		body.global_position = at
		residents.append({"position": at, "yaw": yaw, "body": body, "activity": "standing", "pose": 0})
		return residents.size() - 1
	func begin_combat(index: int) -> Dictionary:
		var resident: Dictionary = residents[index]
		if bool(resident.get("dead", false)) or bool(resident.get("combat_controlled", false)) or not is_instance_valid(resident.get("body")):
			return {}
		resident.combat_controlled = true
		(resident.body as StaticBody3D).collision_layer = 0
		begun += 1
		return {"position": resident.position, "yaw": resident.yaw}
	func end_combat(index: int, at := Vector3.INF, yaw := INF, _shape: CollisionShape3D = null) -> void:
		var resident: Dictionary = residents[index]
		resident.combat_controlled = false
		ended += 1
		if bool(resident.get("dead", false)):
			return
		if at.is_finite():
			resident.position = at
		if is_finite(yaw):
			resident.yaw = yaw
		(resident.body as StaticBody3D).global_position = resident.position
		(resident.body as StaticBody3D).collision_layer = 8
	func resident_position(index: int) -> Vector3:
		return residents[index].position
	func is_dead(index: int) -> bool:
		return bool(residents[index].get("dead", false))

## combat's read-only ownership/death API, scripted by the fixture.
class CombatFixture:
	extends Node
	var dead: Dictionary = {}
	var fighters: Array[Dictionary] = []
	func is_actor_dead(id: String) -> bool:
		return dead.has(id)
	func actor_mode(actor) -> String:
		if not is_instance_valid(actor):
			return "gone"
		if actor.get("dead") == true:
			return "dead"
		return "unknown" if actor.get("combat_override") == true else ""
	func npc_fight_status(_id: String) -> Dictionary:
		return {"fighting": false, "foe": "", "mode": "", "health": 90.0, "knocked": false, "incident_id": "", "actor": null}
	func fighter_snapshot() -> Array[Dictionary]:
		return fighters.duplicate()
	func is_bicycle_knockdown(_id: String) -> bool:
		return false

## Police dispatch as the incident service sees it: every report is taken and
## stays open (the medical side is what this fixture follows).
class PoliceFixture:
	extends Node
	var incident_handler
	var open: Dictionary = {}
	var reports := 0
	func report_incident(event: Dictionary) -> Dictionary:
		reports += 1
		open[str(event.get("incident_ref", ""))] = true
		return {"ok": true, "incident_id": "pol_%d" % reports, "message": "Dispatch has the report."}
	func has_open_ref(ref: String) -> bool:
		return open.has(ref)
	func cancel_ref(ref: String, _text := "") -> bool:
		return open.erase(ref)
	func call_status(_ref: String) -> Dictionary:
		return {}

## Traffic as the ambulance reads it: the real lane network, an empty fleet and
## the emergency-obstacle registry (recorded).
class TrafficFixture:
	extends Node3D
	var network
	var vehicles: Array[Node3D] = []
	var player_fleet: Array[Node3D] = []
	var reservations: Dictionary = {}
	var signals = null
	var parked = null
	var emergency_vehicles: Array[Node3D] = []
	var registrations := 0
	func on_road(point: Vector3, margin := 0.12) -> bool:
		return network != null and bool(network.on_road(point, margin))
	func register_emergency_vehicle(body: Node3D) -> bool:
		if not is_instance_valid(body) or not body.is_inside_tree():
			return false
		if not emergency_vehicles.has(body):
			emergency_vehicles.append(body)
			registrations += 1
		return true
	func unregister_emergency_vehicle(body: Node3D) -> bool:
		if not emergency_vehicles.has(body):
			return false
		emergency_vehicles.erase(body)
		for node in reservations.keys():
			if reservations[node] == body:
				reservations.erase(node)
		return true
	func claim_emergency_junction(body: Node3D, node: String) -> bool:
		if not emergency_vehicles.has(body) or (is_instance_valid(reservations.get(node)) and reservations[node] != body):
			return false
		reservations[node] = body
		return true
	func release_emergency_junction(body: Node3D, node: String) -> bool:
		if reservations.get(node) != body:
			return false
		reservations.erase(node)
		return true

class Arena:
	extends Node3D
	var player: Node3D
	var npcs: Node3D
	var combat: Node
	var police_assistance: Node
	var traffic: Node3D
	var inspector: Node
	var paused := false
	var level_data: Dictionary = {}
	func vector(value) -> Vector3:
		if value is Vector3:
			return value
		return Vector3(float(value[0]), float(value[1]), float(value[2]))

## The real combat service needs a real explorer; its probe lives here.
class CombatArena:
	extends Node3D
	var player: CharacterBody3D
	var npcs: Node3D
	var paused := false

var arena: Arena
var player: PlayerFixture
var inspector: InspectorFixture
var npcs: PeopleFixture
var crowd: CrowdFixture
var combat: CombatFixture
var police: PoliceFixture
var traffic: TrafficFixture
var incidents: Node3D
var ems: Node3D
var home_pose := Transform3D.IDENTITY
var failures := 0
var passes := 0
var finished := false
var statuses: Array[Dictionary] = []
var phone_texts: Array[String] = []
var stage_log: Dictionary = {}
var violations: Dictionary = {}
var max_step := 0.0

func _ready() -> void:
	_run.call_deferred()
	_watchdog()

func _watchdog() -> void:
	await get_tree().create_timer(900.0, true, false, true).timeout
	if not finished:
		check(false, "aftermath fixture completes within 900 s")
		_finish()

func check(ok: bool, label: String) -> bool:
	failures += int(not ok)
	passes += int(ok)
	print("[emergency] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok and is_instance_valid(ems):
		print("[emergency] DIAGNOSTIC ", JSON.stringify(ems.get_status()))
		for entry in ems.crew:
			print("[emergency] CREW ", str(entry), " position=", entry.actor.global_position if is_instance_valid(entry.actor) else Vector3.INF)
	return ok

func violation(kind: String, detail: String) -> void:
	if not violations.has(kind):
		violations[kind] = detail
		print("[emergency] VIOLATION %s: %s" % [kind, detail])

func _on_status(status: Dictionary) -> void:
	statuses.append(status)
	if bool(status.get("phone", false)):
		phone_texts.append(str(status.get("text", "")))

# --------------------------------------------------------------- stepping

func tick_once() -> void:
	var before: Vector3 = ems.ambulance.global_position if is_instance_valid(ems) and is_instance_valid(ems.ambulance) else Vector3.INF
	incidents.tick(DT)
	if before.is_finite() and is_instance_valid(ems.ambulance):
		var moved := Vector2(ems.ambulance.global_position.x - before.x, ems.ambulance.global_position.z - before.z).length()
		max_step = maxf(max_step, moved)
		if moved > Emergency.RESPOND_SPEED * DT + 0.05:
			violation("teleport", "%.2f m in one step at %s" % [moved, str(ems.ambulance.global_position)])
	_watch()
	await get_tree().physics_frame

func step(seconds: float) -> void:
	for i in ceili(seconds * 60.0):
		await tick_once()

func advance_until(condition: Callable, limit: float) -> bool:
	for i in ceili(limit * 60.0):
		if bool(condition.call()):
			return true
		await tick_once()
	return bool(condition.call())

## Invariants sampled every step; each kind is reported once.
var _crew_probe_ticks := 0
var _checked_exit_pair := false

func _watch() -> void:
	if not _checked_exit_pair and ems.crew.size() == 2 \
			and ems.crew[0].state == "to_patient" and ems.crew[1].state == "to_patient":
		_checked_exit_pair = true
		var first = ems.crew[0].actor
		var second = ems.crew[1].actor
		var clearance: float = first.capsule.shape.radius + second.capsule.shape.radius + 0.06
		check(flat(ems.crew[0].door, ems.crew[1].door) >= clearance,
			"simultaneous dismount reserves separate capsule-clear doors for both paramedics")
		check(absf(first.global_position.y - Vector3(ems.crew[0].door).y) < 0.23 \
				and absf(second.global_position.y - Vector3(ems.crew[1].door).y) < 0.23,
			"dismount leaves both crew on the ground without overlap recovery lifting them")
	if str(ems.unit.mode) == "on_scene" and _crew_probe_ticks < 600:
		_crew_probe_ticks += 1
		if _crew_probe_ticks in [1, 2, 3, 15, 60, 150, 300, 450, 600]:
			print("CREW_PROBE tick=", _crew_probe_ticks, " ambulance=", ems.ambulance.global_position, " forward=", ems._forward())
			for member in ems.crew:
				var body = member.actor
				var overlaps: Array = []
				if is_instance_valid(body) and body.enabled:
					var query := PhysicsShapeQueryParameters3D.new()
					query.shape = body.capsule.shape
					query.transform = body.capsule.global_transform
					query.collision_mask = 1 | 2 | 4 | 8 | 16
					query.exclude = [body.get_rid()]
					for hit in arena.get_world_3d().direct_space_state.intersect_shape(query, 8):
						overlaps.append(str(hit.collider.get_path()))
				print("CREW_PROBE member=", member.id, " state=", member.state, " position=", body.global_position, " door=", member.door, " path=", member.path, " index=", member.index, " stuck=", member.stuck, " reroutes=", member.reroutes, " overlaps=", overlaps)
	for call in ems.calls:
		var ref := str(call.ref)
		var log: Array = stage_log.get(ref, [])
		if log.is_empty() or str(log[log.size() - 1]) != str(call.stage):
			log.append(str(call.stage))
			stage_log[ref] = log
		var stage := str(call.stage)
		if stage in EmergencyStatus.PRE_ARRIVAL and float(call.get("treat_time", 0.0)) > 0.0:
			violation("timed_before_arrival", "%s has %.2f s of care before arrival" % [ref, float(call.treat_time)])
		if stage == "treating":
			var near := false
			for entry in ems.crew:
				if str(entry.state) == "with_patient" and is_instance_valid(entry.actor) \
						and flat((entry.actor as Node3D).global_position, Vector3(call.at)) <= Emergency.TREAT_RANGE + 0.6:
					near = true
			if not near:
				violation("treating_without_contact", "%s is treating with no paramedic beside the person" % ref)
		if stage in ["on_scene", "treating"] and str(ems.unit.call) == str(call.id) and not (ems.driver.leg as Dictionary).is_empty():
			violation("arrived_while_moving", "%s is %s while the ambulance still has a route" % [ref, stage])
	for entry in ems.history:
		var ref := str(entry.get("ref", ""))
		var log: Array = stage_log.get(ref, [])
		if not log.is_empty() and str(log[log.size() - 1]) != str(entry.get("stage", "")):
			log.append(str(entry.get("stage", "")))
			stage_log[ref] = log
	for entry in ems.crew:
		var actor = entry.actor
		if str(entry.state) == "seated" and is_instance_valid(actor) and (actor.enabled or actor.visible):
			violation("seated_crew_present", "%s is seated but enabled or visible" % str(entry.id))
	if ems.people.holds.size() > People.MAX_HOLDS:
		violation("holds_over_budget", "%d people held" % ems.people.holds.size())
	if ems.calls.size() > Emergency.MAX_CALLS:
		violation("calls_over_budget", "%d live calls" % ems.calls.size())

# --------------------------------------------------------------- helpers

static func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func box(at: Vector3, size_: Vector3, layer := 1) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	var shape := CollisionShape3D.new()
	var form := BoxShape3D.new()
	form.size = size_
	shape.shape = form
	body.add_child(shape)
	arena.add_child(body)
	body.global_position = at
	return body

func person(id: String, cast: String, at: Vector3, yaw := 0.0, owner_arena: Node3D = null, people: Node3D = null) -> CharacterBody3D:
	var where: Node3D = owner_arena if owner_arena != null else arena
	var registry: Node3D = people if people != null else npcs
	var actor := Actor.new()
	registry.add_child(actor)
	actor.build(where, id, cast, "Neighbor")
	registry.actors[id] = actor
	actor.global_position = at
	actor.yaw = yaw
	actor.puppet.g.rotation.y = yaw
	return actor

func live_call(ref: String) -> Dictionary:
	for call in ems.calls:
		if str(call.ref) == ref:
			return call
	return {}

func stage_of(ref: String) -> String:
	return str(ems.call_for(ref).get("stage", ""))

func outcome_of(ref: String) -> String:
	return str(ems.call_for(ref).get("outcome", ""))

func medical(ref: String) -> Dictionary:
	return incidents.medical_for(ref)

func card_for(id: String) -> Dictionary:
	for card in PoliceStatus.cards({"live": [], "history": [], "refusals": []}, incidents.reports_for("player", 8), 8):
		if str(card.get("key", "")) == "incident:" + id:
			return card
	return {}

func phone_index(fragment: String) -> int:
	for i in phone_texts.size():
		if phone_texts[i].contains(fragment):
			return i
	return -1

func crew_aboard() -> bool:
	for entry in ems.crew:
		var actor = entry.actor
		if str(entry.state) == "dead":
			continue
		if str(entry.state) != "seated" or not is_instance_valid(actor) or actor.enabled or actor.visible \
				or actor.combat_override or actor.has_meta(Emergency.DUTY_META):
			return false
	return true

func at_home() -> bool:
	return str(ems.unit.mode) == "parked" and (str(ems.unit.spot.get("kind", "")) == "bay" or bool(ems.unit.spot.get("home", false)))

## An incident naming `victim`, witnessed by the player, with the injury combat
## would have reported. Returns the incident id.
func injured_incident(victim: String, at: Vector3, injury := "knocked_down", offender := "fighter_a") -> String:
	var opened: Dictionary = incidents.open_incident({"template": "street_fight", "at": at, "offender_id": offender,
		"victim_id": victim, "source": "external:aftermath-fixture"})
	var id := str(opened.get("incident_id", ""))
	if not bool(opened.get("ok", false)):
		return ""
	incidents.note_observation(id, "player", {})
	incidents.note_injury(id, victim, injury)
	return id

func report(id: String) -> Dictionary:
	return incidents.report_incident(id, "player", {"channel": "phone", "phone": true})

func go_home(limit := 150.0) -> bool:
	return await advance_until(func(): return at_home() and ems.calls.is_empty() and crew_aboard(), limit)

# --------------------------------------------------------------- run

func _run() -> void:
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	arena = Arena.new()
	add_child(arena)
	box(Vector3(0, -0.5, 0), Vector3(520, 1, 520), 1)
	arena.level_data = {"spawn": {"position": [0, 0, 0], "yaw": 0.0}, "roads": [
		{"name": "North Street", "width": ROAD_WIDTH, "points": [[-90, 0, 70], [0, 0, 70], [90, 0, 70]]},
		{"name": "South Street", "width": ROAD_WIDTH, "points": [[-90, 0, -70], [0, 0, -70], [90, 0, -70]]},
		{"name": "West Avenue", "width": ROAD_WIDTH, "points": [[-90, 0, -70], [-90, 0, 70]]},
		{"name": "Middle Avenue", "width": ROAD_WIDTH, "points": [[0, 0, -70], [0, 0, 70]]},
		{"name": "East Avenue", "width": ROAD_WIDTH, "points": [[90, 0, -70], [90, 0, 70]]}]}
	await get_tree().physics_frame
	player = PlayerFixture.new()
	arena.add_child(player)
	player.global_position = Vector3(-30, 0.012, -45)
	arena.player = player
	inspector = InspectorFixture.new()
	arena.add_child(inspector)
	arena.inspector = inspector
	npcs = PeopleFixture.new()
	arena.add_child(npcs)
	arena.npcs = npcs
	crowd = CrowdFixture.new()
	npcs.add_child(crowd)
	npcs.crowd = crowd
	combat = CombatFixture.new()
	arena.add_child(combat)
	arena.combat = combat
	police = PoliceFixture.new()
	arena.add_child(police)
	arena.police_assistance = police
	traffic = TrafficFixture.new()
	arena.add_child(traffic)
	arena.traffic = traffic
	var network := Network.new()
	network.setup(arena)
	traffic.network = network
	check(network.lanes.size() >= 12, "the fixture street grid has directed lanes (%d)" % network.lanes.size())
	person("fighter_a", "ricky", NOBODY)
	person("fighter_b", "ricky", NOBODY + Vector3(4, 0, 0))
	incidents = Incidents.new()
	arena.add_child(incidents)
	incidents.setup(arena)
	incidents.set_spawning_enabled(false)
	incidents.report_status_changed.connect(_on_status)
	ems = incidents.emergency
	check(ems != null and ems.get_parent() == incidents and ems.name == "EmergencyResponse", "the incident service owns the emergency service")
	check(not ems.available and str(ems.reason) == "no hospital", "with no hospital built, it honestly reports itself unavailable (%s)" % str(ems.reason))
	await tick_once()
	_base_section()
	if not ems.available:
		_finish()
		return
	await _treated_section()
	await _unreachable_section()
	await _death_section()
	await _left_section()
	await _interruption_section()
	await _bounded_section()
	await _staging_section()
	await _teardown_section()
	await _combat_section()
	_finish()

func _base_section() -> void:
	var configured: bool = ems.configure_base({"bays": [Transform3D(Basis(Vector3.UP, PI), BAY)], "name": "Fixture General"})
	check(configured and ems.available and str(ems.base.home.kind) == "bay",
		"the fixture hospital's bay has a drivable way out to the street (%s)" % str(ems.base_report))
	var curb: Dictionary = ems.base.get("curb", {})
	check(not curb.is_empty() and float(curb.shift) >= Emergency.STANDBY_SHIFT,
		"a curbside standby in front of it leaves the travel lane free (shift %.2f)" % float(curb.get("shift", 0.0)))
	home_pose = ems.ambulance.global_transform
	check(at_home() and ems.ambulance.visible and ems.ambulance.collision_layer == 16 and flat(home_pose.origin, BAY) < 0.05,
		"the ambulance stands in its bay, solid and visible")
	check(not traffic.emergency_vehicles.has(ems.ambulance), "parked off the street, traffic need not treat it as an obstacle")
	for id in Emergency.CREW_IDS:
		var actor = npcs.actors.get(id)
		check(is_instance_valid(actor) and not actor.enabled and not actor.visible and actor.collision_layer == 0 and actor.has_meta(Emergency.CREW_META),
			"%s is a registered identity, seated (disabled and hidden)" % id)
	var refused: Dictionary = ems.request({"ref": "inc_000900", "patient": "player", "injury": "hurt"})
	check(not bool(refused.ok) and ems.calls.is_empty(), "the explorer is never a patient")

# --------------------------------------------------------------- 1. treated end to end

func _treated_section() -> void:
	var index := crowd.add(Vector3(-40, 0.012, -60), PI)
	var patient := "crowd_%d" % index
	var id := injured_incident(patient, Vector3(-40, 0.0, -60))
	check(not id.is_empty(), "an incident naming the victim opens (%s)" % id)
	check(not incidents.note_injury(id, "nobody_named", "hurt") and not incidents.note_injury(id, "player", "hurt"),
		"an injury needs someone the record names, and never the explorer")
	var injured := medical(id)
	check(str(injured.get("stage", "")) == "injured" and str(injured.get("patient", "")) == patient and str(injured.get("injury", "")) == "knocked_down",
		"combat's injury names the victim as the record's patient")
	await step(0.5)
	check(ems.calls.is_empty() and str(medical(id).stage) == "injured", "an injury nobody reported sends no ambulance")
	check(not incidents.note_injury(id, patient, "hurt") and str(medical(id).injury) == "knocked_down", "only the first injury counts")
	var reply := report(id)
	check(bool(reply.ok) and not bool(reply.duplicate) and ems.calls.is_empty(),
		"the report is accepted; the ambulance is asked on the next tick, not inside the report call")
	await tick_once()
	var call := live_call(id)
	check(not call.is_empty() and str(call.stage) == "dispatched" and str(ems.unit.mode) == "responding" and str(ems.unit.call) == str(call.id),
		"the free ambulance is dispatched at once (%s)" % str(call.get("stage", "none")))
	check(ems.people.owns(patient) and bool(crowd.residents[index].get("combat_controlled", false)),
		"the injured neighbor waits, held where they stood by one stand-in body")
	check(str(medical(id).stage) == "dispatched" and phone_index("Dispatch sent the ambulance from Fixture General") >= 0,
		"the record and the phone say the ambulance was dispatched")
	check(traffic.emergency_vehicles.has(ems.ambulance) and ems.driver.emergency, "on its way it is a lit emergency obstacle for traffic")
	# 2. Duplicates never dispatch twice.
	var dispatches := int(ems.counters.dispatches)
	var again := report(id)
	await tick_once()
	check(bool(again.ok) and bool(again.duplicate) and ems.calls.size() == 1 and int(ems.counters.dispatches) == dispatches,
		"a repeat report of the same incident never sends a second ambulance")
	var same: Dictionary = ems.request({"ref": id, "patient": patient, "injury": "hurt", "at": Vector3(-40, 0, -60)})
	var other_ref: Dictionary = ems.request({"ref": "inc_000777", "patient": patient, "injury": "hurt", "at": Vector3(-40, 0, -60)})
	check(bool(same.duplicate) and bool(other_ref.duplicate) and str(same.call_id) == str(call.id) and str(other_ref.call_id) == str(call.id)
		and ems.calls.size() == 1, "the same incident or the same person asking again gets the same call")
	var en_route := await advance_until(func(): return stage_of(id) == "en_route", 20.0)
	call = live_call(id)
	check(en_route and float(ems.driver.odometer) - float(call.get("dispatch_odometer", 0.0)) >= Emergency.EN_ROUTE_EVIDENCE,
		"\"on the way\" only after the ambulance really moved (%.1f m)" % (float(ems.driver.odometer) - float(call.get("dispatch_odometer", 0.0))))
	check(flat(ems.ambulance.global_position, home_pose.origin) > 1.0 and float(call.treat_time) == 0.0 and str(medical(id).clearance) == "",
		"it left the bay; nothing is timed and nothing is claimed at the scene yet")
	# Pause and inspection freeze everything.
	await step(1.0)
	arena.paused = true
	var frozen: Vector3 = ems.ambulance.global_position
	var frozen_clock := float(ems._clock)
	var frozen_stage := stage_of(id)
	await step(1.0)
	check(ems.ambulance.global_position.is_equal_approx(frozen) and float(ems._clock) == frozen_clock and stage_of(id) == frozen_stage,
		"a paused world freezes the ambulance, its clock and its stage")
	arena.paused = false
	inspector.active = true
	await step(1.0)
	check(ems.ambulance.global_position.is_equal_approx(frozen) and float(ems._clock) == frozen_clock, "the inspector freezes it too")
	inspector.active = false
	await step(0.5)
	check(not ems.ambulance.global_position.is_equal_approx(frozen), "it moves on once play resumes")
	# Care does not depend on how the police call ended.
	incidents.on_police_progress(id, "resolved", {"outcome": "arrested", "text": "Officers arrested the suspect."})
	police.open.erase(id)
	await tick_once()
	check(str(incidents.get_incident(id).state) == "resolved" and not live_call(id).is_empty(),
		"the police closing the incident does not call the ambulance off")
	var arrived := await advance_until(func(): return stage_of(id) in ["on_scene", "treating", "resolved"], 120.0)
	check(arrived, "the ambulance reaches the scene by road (%s)" % stage_of(id))
	var log: Array = stage_log.get(id, [])
	check(log.find("dispatched") >= 0 and log.find("dispatched") < log.find("en_route") and log.find("en_route") < log.find("on_scene"),
		"stages arrive in order: %s" % str(log))
	check((ems.driver.leg as Dictionary).is_empty() and str(ems.unit.mode) == "on_scene" and str(medical(id).clearance) == "at_scene",
		"\"at the scene\" only once it stopped at the end of its route; the street is marked occupied")
	check(flat(ems.ambulance.global_position, Vector3(-40, 0, -60)) <= Emergency.FOOT_ARRIVAL and traffic.network.on_road(ems.ambulance.global_position),
		"it stopped on the street beside the scene (%.1f m away)" % flat(ems.ambulance.global_position, Vector3(-40, 0, -60)))
	var treating := await advance_until(func(): return stage_of(id) in ["treating", "resolved"], 40.0)
	check(treating and phone_index("A paramedic is with the injured person") >= 0, "a paramedic walked over; treatment starts beside the person")
	var resolved := await advance_until(func(): return stage_of(id) == "resolved", 40.0)
	check(resolved and outcome_of(id) == "treated" and str(medical(id).outcome) == "treated",
		"paramedics treat the injured person (%s)" % outcome_of(id))
	check(not ems.people.owns(patient) and not bool(crowd.residents[index].get("combat_controlled", false)) and crowd.ended >= 1,
		"the treated neighbor goes back to ordinary life through the crowd's own release")
	var cleared := await advance_until(func(): return str(medical(id).get("clearance", "")) == "cleared", 120.0)
	var timeline: Array = medical(id).get("timeline", [])
	check(cleared and timeline.any(func(step_entry): return str(step_entry.stage) == "cleared"),
		"crew board, the ambulance drives off and the street is clear again")
	var home := await go_home()
	check(home and str(ems.unit.spot.get("kind", "")) == "curb" and not traffic.emergency_vehicles.has(ems.ambulance),
		"it returns to its standby at the hospital and stops being a traffic obstacle")
	check(crew_aboard(), "both paramedics are back aboard: disabled, hidden, off duty")
	check(phone_index("Dispatch sent") < phone_index("has arrived") and phone_index("has arrived") < phone_index("A paramedic is with")
		and phone_index("A paramedic is with") < phone_index("Paramedics treated"), "the phone hears each step once, in order")
	var card := card_for(id)
	check(not card.is_empty() and str(card.incident).contains("Treated by paramedics") and str((card.medical as Dictionary).stage) == "resolved",
		"the Police page card shows the medical result: %s" % str(card.get("incident", "")))
	var labels: Array = []
	for line in card.get("timeline", []):
		labels.append(str(line.label))
	check(labels.has("Treated by paramedics") or labels.has("Ambulance left the scene"), "medical steps join the card timeline: %s" % str(labels))
	check(max_step <= Emergency.RESPOND_SPEED * DT + 0.05, "no step moved the ambulance more than one driving step (%.3f m)" % max_step)

# --------------------------------------------------------------- 3. unreachable

func _unreachable_section() -> void:
	person("far_patient", "granny", Vector3(0, 0.012, 200), 0.0)
	var id := injured_incident("far_patient", Vector3(0, 0, 200), "hurt", "fighter_b")
	report(id)
	var before: Transform3D = ems.ambulance.global_transform
	var failures_before := int(ems.counters.route_failures)
	await tick_once()
	check(stage_of(id) == "queued" and phone_index("no road route for the ambulance yet") >= 0,
		"with no road near the person, dispatch says it is still looking (%s)" % stage_of(id))
	var closed := await advance_until(func(): return outcome_of(id) == "unreachable", 30.0)
	check(closed and str(medical(id).stage) == "failed" and str(medical(id).outcome) == "unreachable",
		"after bounded retries the call closes as unreachable")
	check(ems.ambulance.global_transform.is_equal_approx(before) and at_home() and int(ems.counters.route_failures) - failures_before >= 3,
		"the ambulance never pretended to go: it stayed home")
	check(phone_index("No road route lets the ambulance reach the injured person") >= 0
		and EmergencyStatus.summary(medical(id)) == "No road route for the ambulance", "the phone and the card say why")

# --------------------------------------------------------------- 4. death

func _death_section() -> void:
	var index := crowd.add(Vector3(-70, 0.012, -60), PI)
	var patient := "crowd_%d" % index
	var id := injured_incident(patient, Vector3(-70, 0, -60))
	report(id)
	await tick_once()
	var en_route := await advance_until(func(): return stage_of(id) == "en_route", 20.0)
	var body = ems.people.body_of(patient)
	check(en_route and is_instance_valid(body), "a second patient is held and the ambulance is on its way")
	var ended_before := crowd.ended
	var treated_before := int(ems.counters.treated)
	combat.dead[patient] = true
	crowd.residents[index].dead = true
	body.mark_dead()
	var closed := await advance_until(func(): return outcome_of(id) == "patient_died", 3.0)
	check(closed and str(medical(id).stage) == "cancelled" and str(medical(id).outcome) == "patient_died",
		"the person's death closes the medical call honestly")
	check(is_instance_valid(body) and body.dead and not body.enabled and not body.has_meta("ems_patient") and crowd.ended == ended_before
		and bool(crowd.residents[index].get("combat_controlled", false)) and not ems.people.owns(patient),
		"the body is never released, revived or handed back; combat keeps it")
	var log: Array = stage_log.get(id, [])
	check(not log.has("on_scene") and not log.has("treating") and int(ems.counters.treated) == treated_before,
		"nobody treats the dead: no arrival or treatment was ever claimed (%s)" % str(log))
	await tick_once()
	check(str(ems.unit.call).is_empty() and str(ems.unit.mode) in ["returning", "parked", "stranded"], "the ambulance turns back")
	var refused: Dictionary = ems.request({"ref": "inc_000901", "patient": patient, "injury": "hurt", "at": Vector3(-70, 0, -60)})
	check(not bool(refused.ok) and str(refused.reason) == "deceased" and str(refused.outcome) == "patient_died",
		"a new request for someone who died is refused: no ambulance for the dead")
	var home := await go_home()
	check(home, "back at the hospital afterwards")

# --------------------------------------------------------------- 5. the person leaves

func _left_section() -> void:
	var leaver := person("leaver", "liner_2", Vector3(40, 0.012, -60), 0.0)
	var reply: Dictionary = ems.request({"ref": "inc_000902", "patient": "leaver", "injury": "hurt", "at": leaver.global_position})
	check(bool(reply.ok) and not ems.people.owns("leaver"), "a named neighbor is only tracked, never held")
	await step(1.0)
	leaver.set_enabled(false)
	var gone := await advance_until(func(): return outcome_of("inc_000902") == "patient_left", 3.0)
	check(gone and stage_of("inc_000902") == "cancelled", "a person who has gone closes the call as \"left\"")
	var custody := person("held_one", "liner_2", Vector3(44, 0.012, -60), 0.0)
	custody.set_meta("police_custody", true)
	var refused: Dictionary = ems.request({"ref": "inc_000903", "patient": "held_one", "injury": "hurt", "at": custody.global_position})
	check(not bool(refused.ok) and str(refused.reason) == "custody", "custody is never overridden: officers handle that person's care")
	var home := await go_home()
	check(home, "home again")

# --------------------------------------------------------------- 6. interruption

func _interruption_section() -> void:
	var index := crowd.add(Vector3(-20, 0.012, -60), PI)
	var patient := "crowd_%d" % index
	var id := injured_incident(patient, Vector3(-20, 0, -60))
	report(id)
	await tick_once()
	var en_route := await advance_until(func(): return stage_of(id) == "en_route", 20.0)
	check(en_route and ems.people.owns(patient), "a response is under way")
	var snapshot: Dictionary = incidents.snapshot_state()
	var saved_medical: Dictionary = {}
	for entry in snapshot.incidents:
		if str(entry.id) == id:
			saved_medical = entry.get("medical", {})
	check(str(saved_medical.get("stage", "")) == "en_route" and incidents.validate_state(snapshot).is_empty(),
		"the durable record carries the medical summary and validates")
	var restored: Dictionary = incidents.restore_state(snapshot.duplicate(true))
	check(bool(restored.ok) and incidents.snapshot_state() == snapshot, "a checkpoint restore is faithful (the rollback check holds)")
	check(ems.calls.is_empty() and ems.people.holds.is_empty() and not bool(crowd.residents[index].get("combat_controlled", false)),
		"the live response stands down: the person is back in ordinary life where they stood")
	check(at_home() and ems.ambulance.global_transform.is_equal_approx(home_pose) and crew_aboard() and not traffic.emergency_vehicles.has(ems.ambulance),
		"the ambulance is back at the hospital with its crew aboard")
	var card := card_for(id)
	check(not card.is_empty() and str((card.medical as Dictionary).label) == "Medical response interrupted" and not bool((card.medical as Dictionary).live),
		"before upkeep runs, the card never shows the restored stage as under way")
	await step(1.0)
	check(str(medical(id).stage) == "cancelled" and str(medical(id).outcome) == "interrupted" and str(medical(id).text).contains("result is unknown"),
		"upkeep settles it: stopped, result unknown (%s)" % str(medical(id).get("text", "")))
	var corrupt: Dictionary = snapshot.duplicate(true)
	for entry in corrupt.incidents:
		if str(entry.id) == id:
			entry.medical.stage = "teleported"
	check(not incidents.validate_state(corrupt).is_empty(), "a corrupt medical summary is refused by validation")
	var again := report(id)
	await tick_once()
	check(bool(again.duplicate) and ems.calls.size() == 1 and stage_of(id) in ["dispatched", "en_route"],
		"a repeat report after an interrupted response asks for the ambulance again")
	await step(1.0)
	incidents.reset_state()
	check(str(medical(id).stage) == "cancelled" and str(medical(id).outcome) == "interrupted" and str(medical(id).text).contains("reset")
		and ems.calls.is_empty() and at_home() and crew_aboard() and ems.people.holds.is_empty(),
		"a reset stops it at once and says so; nobody is left held or on duty")

# --------------------------------------------------------------- 7. bounded resources

func _bounded_section() -> void:
	var ids: Array[String] = []
	var spots: Array[Vector3] = [Vector3(-60, 0.012, 60), Vector3(-40, 0.012, 60), Vector3(-20, 0.012, 60), Vector3(30, 0.012, 60)]
	for spot in spots:
		ids.append("crowd_%d" % crowd.add(spot, 0.0))
	var replies: Array = []
	for i in 4:
		replies.append(ems.request({"ref": "inc_00095%d" % i, "patient": ids[i], "injury": "hurt", "at": spots[i]}))
	check(bool(replies[0].ok) and bool(replies[1].ok) and bool(replies[2].ok) and not bool(replies[3].ok) and str(replies[3].reason) == "capacity",
		"at most three medical calls at once; a fourth is refused honestly")
	await step(0.5)
	var dispatched := 0
	var waiting := 0
	for call in ems.calls:
		dispatched += int(str(call.stage) in ["dispatched", "en_route"])
		waiting += int(str(call.stage) == "queued" and str(call.text).contains("on another call"))
	check(dispatched == 1 and waiting == 2, "one ambulance serves one call; the others wait, saying why")
	check(ems.people.holds.size() == People.MAX_HOLDS, "at most two people are held at once")
	ems.reset_state("fixture")
	check(ems.calls.is_empty() and ems.people.holds.is_empty() and at_home() and crew_aboard(), "a reset releases everyone and re-stages the ambulance")

# --------------------------------------------------------------- 8. armed scene

func _staging_section() -> void:
	var index := crowd.add(Vector3(60, 0.012, -60), PI)
	var patient := "crowd_%d" % index
	var armed := person("armed_one", "ricky", Vector3(63, 0.012, -57), 0.0)
	combat.fighters = [{"actor": armed, "id": "armed_one", "mode": "gun"}]
	var reply: Dictionary = ems.request({"ref": "inc_000960", "patient": patient, "injury": "hurt", "at": Vector3(60, 0, -60)})
	check(bool(reply.ok), "a call near an armed person is taken")
	var staged := await advance_until(func(): return stage_of("inc_000960") == "staging", 90.0)
	check(staged and ems.driver.hold and ems.driver.remaining() <= Emergency.STAGE_DISTANCE + 1.0,
		"the ambulance waits short of a scene with an armed person (%.1f m left)" % ems.driver.remaining())
	await advance_until(func(): return float(ems.driver.speed) <= 0.0, 5.0)
	var held_at: Vector3 = ems.ambulance.global_position
	await step(3.0)
	check(stage_of("inc_000960") == "staging" and flat(ems.ambulance.global_position, held_at) < 0.05 and float(live_call("inc_000960").treat_time) == 0.0,
		"it stays put and nothing is timed while the threat lasts")
	combat.fighters.clear()
	var arrived := await advance_until(func(): return stage_of("inc_000960") in ["on_scene", "treating", "resolved"], 60.0)
	check(arrived, "once the scene is safe it goes in")
	ems.reset_state("fixture")
	await step(0.2)

# --------------------------------------------------------------- 9. teardown

func _teardown_section() -> void:
	var index := crowd.add(Vector3(-10, 0.012, 60), 0.0)
	var patient := "crowd_%d" % index
	var reply: Dictionary = ems.request({"ref": "inc_000970", "patient": patient, "injury": "hurt", "at": Vector3(-10, 0, 60)})
	var on_foot := await advance_until(func(): return ems.crew.any(func(entry): return str(entry.state) in ["to_patient", "with_patient"]), 120.0)
	check(bool(reply.ok) and on_foot and ems.people.owns(patient), "paramedics are out on foot with a held patient")
	var crew_actors: Array = []
	for entry in ems.crew:
		crew_actors.append(entry.actor)
	var ambulance: Node3D = ems.ambulance
	arena.remove_child(incidents)
	var nobody_on_duty := true
	for actor in crew_actors:
		nobody_on_duty = nobody_on_duty and is_instance_valid(actor) and not actor.enabled and not actor.visible and not actor.combat_override \
			and not actor.has_meta(Emergency.DUTY_META)
	check(nobody_on_duty, "leaving the tree leaves no paramedic on duty or visible")
	check(not bool(crowd.residents[index].get("combat_controlled", false)), "the held neighbor gets their slot back")
	check(not traffic.emergency_vehicles.has(ambulance), "traffic forgets the ambulance")
	check(police.incident_handler == null, "police no longer report to the removed service")
	incidents.free()
	await get_tree().physics_frame
	var registered := true
	for id in Emergency.CREW_IDS:
		registered = registered and is_instance_valid(npcs.actors.get(id))
	check(registered, "paramedic identities stay registered for the death registry")
	check(violations.is_empty(), "no invariant was violated: %s" % str(violations))

# --------------------------------------------------------------- 10. narrow combat edits

func _combat_section() -> void:
	var probe := CombatArena.new()
	add_child(probe)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(60, 1, 60)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	probe.add_child(floor_body)
	floor_body.global_position = Vector3(1000, -0.5, 0)
	await get_tree().physics_frame
	var explorer := Player.new()
	probe.add_child(explorer)
	explorer.set_physics_process(false)
	explorer.global_position = Vector3(1000, 0.012, -20)
	explorer.enabled = true
	probe.player = explorer
	var people := PeopleFixture.new()
	probe.add_child(people)
	probe.npcs = people
	var real := Combat.new()
	probe.add_child(real)
	real.setup(probe)
	var medic := person("ems_probe_medic", "mailman", Vector3(1000, 0.012, 0), 0.0, probe, people)
	medic.combat_override = true
	medic.set_meta(Emergency.DUTY_META, "probe")
	var hurt := person("ems_probe_patient", "granny", Vector3(1004, 0.012, 0), 0.0, probe, people)
	hurt.set_meta("ems_patient", "probe")
	var bystander := person("ems_probe_bystander", "liner_2", Vector3(996, 0.012, 4), 0.0, probe, people)
	var bump: Dictionary = real.knockdown_from_bicycle(medic, 9.0)
	check(str(bump.outcome) == "stumbled" and str(bump.reason) == "on_duty" and real.actor_mode(medic) == "unknown",
		"a bicycle bump only jostles an on-duty paramedic (%s/%s)" % [str(bump.outcome), str(bump.reason)])
	var jostle: Dictionary = real.knockdown_from_bicycle(hurt, 9.0)
	check(str(jostle.outcome) == "stumbled" and str(jostle.reason) == "injured" and not real.is_bicycle_knockdown("ems_probe_patient"),
		"an injured person waiting for paramedics is never knocked down again (%s/%s)" % [str(jostle.outcome), str(jostle.reason)])
	var fight: Dictionary = real.start_npc_fight(bystander, medic)
	check(not bool(fight.ok) and str(fight.reason) == "unavailable", "an on-duty paramedic is never an incident fight target")
	real._react(medic, medic.global_position + Vector3(4, 0, 0), false, false)
	check(real.actor_mode(medic) == "unknown", "gunfire does not steal a paramedic into panic; their service handles scene safety")
	real._react(bystander, bystander.global_position + Vector3(4, 0, 0), false, false)
	var status: Dictionary = real.npc_fight_status("ems_probe_bystander")
	check(str(real.actor_mode(bystander)).begins_with("panic:") and str(status.mode).begins_with("panic:") and status.actor == bystander,
		"a fleeing person's state is readable (%s)" % str(status.get("mode", "")))
	(real._panic[bystander.get_instance_id()] as Dictionary).health = 40.0
	check(is_equal_approx(float(real.npc_fight_status("ems_probe_bystander").health), 40.0),
		"how badly a fleeing victim was hurt is reported for the aftermath")
	real.disengage_actor(bystander)
	probe.queue_free()
	await get_tree().physics_frame

func _finish() -> void:
	if finished:
		return
	finished = true
	print("[emergency] passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures > 0 else 0)
