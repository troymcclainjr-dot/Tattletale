extends Node

const Cruisers := preload("res://scripts/city/city_police_cruisers.gd")
const Traffic := preload("res://scripts/city/city_traffic.gd")
const Network := preload("res://scripts/city/city_traffic_network.gd")
const Lanes := preload("res://scripts/city/city_police_lanes.gd")

var passes := 0
var failures := 0

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	passes += int(ok)
	failures += int(not ok)
	print("[police_emergency_junction] %s %s" % ["PASS" if ok else "FAIL", label])

func _run() -> void:
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	var traffic := Traffic.new()
	traffic.process_mode = Node.PROCESS_MODE_DISABLED
	traffic.network = Network.new()
	traffic.network.nodes = {"crossing": {"signal": false, "out": []}}
	add_child(traffic)
	var police := Node3D.new()
	add_child(police)
	police.position = Vector3(0, 0, -8)
	var ambulance := Node3D.new()
	ambulance.set_meta("traffic_obstacle_half_extents", Vector2(1.2, 2.4))
	add_child(ambulance)
	var cruisers := Cruisers.new()
	cruisers.traffic = traffic
	var path := PackedVector3Array([Vector3(0, 0, -20), Vector3.ZERO, Vector3(0, 0, 20)])
	var crossing := {"node": "crossing", "s": 20.0, "exit_s": 30.0, "center": Vector3.ZERO,
		"radius": 8.0, "signal": false, "axis": "test"}
	var unit := {"car": police, "path": path, "sums": Lanes.cumulative(path), "cursor": 0,
		"s": 12.0, "junctions": [crossing], "cleared": {}, "yield_time": 0.0,
		"yielding": false, "emergency": true}
	check(traffic.register_emergency_vehicle(ambulance) and traffic.claim_emergency_junction(ambulance, "crossing"),
		"generic ambulance obtains real shared traffic ownership")
	check(cruisers._crossing_traffic(unit, crossing), "aligned ambulance ownership blocks police crossing detection")
	check(bool(cruisers._junction_state(unit).get("yield", false)) and bool(unit.yielding),
		"aligned ambulance owner denies emergency police admission")
	unit.yield_time = Cruisers.YIELD_LIMIT + 2.0
	check(bool(cruisers._junction_state(unit).get("yield", false)), "aligned ambulance ownership never expires after the police yield limit")
	ambulance.rotation.y = PI * 0.5
	check(bool(cruisers._junction_state(unit).get("yield", false)), "perpendicular ambulance ownership also survives the yield limit")
	unit.cleared["0"] = true
	unit.s = 19.75
	check(bool(cruisers._junction_state(unit).get("yield", false)) and not unit.cleared.has("0"),
		"lease overrides cached approach clearance and near-entry shortcut")
	unit.s = 12.0
	unit.emergency = false
	check(bool(cruisers._junction_state(unit).get("yield", false)), "non-emergency police also respect the ambulance lease")
	unit.emergency = true
	ambulance.position = Vector3(100, 0, 100)
	check(bool(cruisers._junction_state(unit).get("yield", false)), "driver ownership rather than a second distance heuristic controls release")
	check(traffic.release_emergency_junction(ambulance, "crossing"), "ambulance releases its shared lease")
	check(not bool(cruisers._junction_state(unit).get("yield", true)) and not unit.yielding,
		"police admission resumes when the lease is released")
	traffic.claim_emergency_junction(ambulance, "crossing")
	traffic.unregister_emergency_vehicle(ambulance)
	check(not bool(cruisers._junction_state(unit).get("yield", true)), "unregister cleanup leaves no police yield behind")
	# Ordinary reservation rules retain their existing directional and timeout behavior.
	var ordinary := Node3D.new()
	add_child(ordinary)
	traffic.reservations["crossing"] = ordinary
	check(not bool(cruisers._junction_state(unit).get("yield", true)), "aligned ordinary holder retains existing police admission behavior")
	ordinary.rotation.y = PI * 0.5
	unit.yield_time = 0.0
	check(bool(cruisers._junction_state(unit).get("yield", false)), "ordinary crossing holder still causes initial yield")
	unit.yield_time = Cruisers.YIELD_LIMIT + 2.0
	check(not bool(cruisers._junction_state(unit).get("yield", true)), "ordinary holder retains existing bounded yield behavior")
	traffic.reservations.erase("crossing")
	traffic.register_emergency_vehicle(ambulance)
	traffic.claim_emergency_junction(ambulance, "crossing")
	unit.car = ambulance
	check(not bool(cruisers._junction_state(unit).get("yield", true)), "own emergency identity cannot yield to itself")
	unit.car = police
	ambulance.free()
	check(not bool(cruisers._junction_state(unit).get("yield", true)), "freed emergency identity is not a phantom blocking lease")
	traffic._prune_emergency_vehicles()
	ordinary.free()
	police.free()
	traffic.free()
	print("[police_emergency_junction] COMPLETE %d passed; %d failed" % [passes, failures])
	get_tree().quit(1 if failures else 0)
