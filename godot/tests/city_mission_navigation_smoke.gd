extends SceneTree
const Navigation := preload("res://scripts/city/city_mission_navigation.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	print("[city_navigation] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1

func _initialize() -> void:
	_run.call_deferred()

func _clear(a: Vector3, b: Vector3) -> bool:
	# An impassable courtyard occupies the inside of the L-shaped street fixture.
	for i in range(1, 20):
		var at := a.lerp(b, float(i) / 20.0)
		if at.x > 0.2 and at.x < 19.8 and at.z > 0.2 and at.z < 19.8:
			return false
	return true

func _run() -> void:
	var navigation := Navigation.new()
	navigation.setup({"roads": [{"points": [[0, 0, 0], [0, 0, 20], [20, 0, 20]]}], "route": {"points": []}}, _clear)
	var permanent := navigation.graph.get_point_count()
	var status := {"active_id": "fixture", "stage": 0, "target_position": Vector3(20, 0, 20)}
	navigation.update(status, Vector3.ZERO, 0.0)
	check(navigation.route.size() >= 3 and navigation.route[0] == Vector3.ZERO and navigation.route[-1] == status.target_position, "accepted mission routes from player to exact destination")
	var safe := true
	var distance := 0.0
	for i in range(1, navigation.route.size()):
		safe = safe and _clear(navigation.route[i - 1], navigation.route[i])
		distance += navigation.route[i - 1].distance_to(navigation.route[i])
	check(safe and distance >= 39.9, "street route follows bend around building rather than diagonal shortcut")
	check(navigation.graph.get_point_count() == permanent, "temporary endpoint links leave permanent graph unchanged")
	var builds: int = navigation.route_build_count
	for i in 100:
		navigation.update(status, Vector3(0, 0, 5), 0.1)
	check(navigation.route_build_count == builds and navigation.build_count == 1, "normal movement and redraws reuse graph and route")
	status.stage = 1
	status.target_position = Vector3(0, 0, 20)
	navigation.update(status, Vector3.ZERO, 0.0)
	check(navigation.route_build_count == builds + 1 and navigation.target == status.target_position, "next mission stage updates destination immediately")
	builds = navigation.route_build_count
	navigation.update(status, Vector3(100, 0, 100), 0.1)
	check(navigation.route_build_count == builds, "off-route checks are throttled")
	navigation.update(status, Vector3(100, 0, 100), 1.0)
	check(navigation.route_build_count == builds + 1 and navigation.route.is_empty(), "unreachable off-route position yields marker without unsafe line")
	navigation.update({"active_id": ""}, Vector3.ZERO, 0.0)
	check(navigation.route.is_empty() and navigation.active_id.is_empty(), "cancel/completion clears route and destination")
	var blocked := Navigation.new()
	blocked.setup({"roads": [{"points": [[0, 0, 0], [0, 0, 20]]}]}, func(_a, _b): return false)
	blocked.update(status, Vector3(5, 0, 5), 0.0)
	check(blocked.route.is_empty(), "blocked endpoint never falls back to a line through buildings")
	quit(0 if failures == 0 else 1)
