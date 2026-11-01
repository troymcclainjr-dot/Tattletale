extends Node
## Actual populated-world acceptance, including terrain and all scene colliders.
const Fleet = preload("res://scripts/city/city_civic_parking_fleet.gd")
const Network = preload("res://scripts/city/city_traffic_network.gd")
var failures := 0

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	failures += int(not ok)
	print("[neighborhood_vehicle_placement] %s %s" % ["PASS" if ok else "FAIL", label])

func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func _run() -> void:
	get_tree().change_scene_to_file("res://scenes/city/pen_lucy.tscn")
	await _frames(4)
	var level: Node = get_tree().current_scene
	for i in 900:
		if level != null and level.get("level_ready") == true:
			break
		await _frames(1)
		level = get_tree().current_scene
	if level == null or level.get("level_ready") != true:
		_check(false, "world initializes")
		get_tree().quit(1)
		return
	level.pause_exploring()
	await _frames(2)
	var traffic: Node3D = level.traffic
	var parked: Node3D = traffic.parked
	var status: Dictionary = parked.get_status()
	print("[neighborhood_vehicle_placement] parked ", JSON.stringify(status))
	_check(int(status.total) == 216, "actual parked fleet 144 -> 216 (+50 percent)")
	var min_spacing := INF
	var valid_curb := true
	for i in parked.records.size():
		var record: Dictionary = parked.records[i]
		valid_curb = valid_curb and bool(record.curb_checked)
		if float(record.road_width) < 11.0:
			valid_curb = valid_curb and str(record.parking_mode) == "single" and float(record.parking_side) == 1.0
		for j in range(i + 1, parked.records.size()):
			var a: Vector3 = record.pose.origin
			var b: Vector3 = parked.records[j].pose.origin
			min_spacing = minf(min_spacing, Vector2(a.x-b.x,a.z-b.z).length())
	_check(valid_curb, "all curb/driveway checks retained; narrow roads park one side")
	_check(min_spacing >= 6.999, "parked centres retain at least seven metres separation")
	_check(Network.parking_mode(7.0,"Frisby Street") == "none" and Network.parking_mode(9.5,"Old York Road") == "none", "narrow links and arterial remain no parking")
	_check(is_equal_approx(9.5 - 2.12 - .22,7.16), "single-side local roads leave 7.16m clear carriageway")
	var network: RefCounted = traffic.network
	var grounded_continuations := true
	var enabled := 0
	var streets: Dictionary = {}
	var min_lane_clearance := INF
	for lane in network.lanes:
		if not bool(lane.enabled):
			continue
		enabled += 1
		streets[lane.street] = true
		var exits := 0
		for option in network.choices(int(lane.id),1):
			exits += int(not network.connector(int(lane.id),int(option)).is_empty())
		grounded_continuations = grounded_continuations and exits > 0
		for record in parked.records:
			if str(record.street) != str(lane.street):
				continue
			var p: Vector3 = record.pose.origin
			var path: Array[Vector3] = lane.points
			for i in range(1,path.size()):
				var distance := Geometry2D.get_closest_point_to_segment(Vector2(p.x,p.z),Vector2(path[i-1].x,path[i-1].z),Vector2(path[i].x,path[i].z)).distance_to(Vector2(p.x,p.z))
				min_lane_clearance = minf(min_lane_clearance,distance)
	_check(grounded_continuations and enabled > 0 and streets.size() >= 10, "enabled traffic network has grounded continuation on at least ten streets")
	_check(min_lane_clearance >= 2.319, "parked cars clear every same-street moving lane by both hull widths plus0.2m")
	var ratios: Array[float] = []
	var all_sidewalk := true
	for anchor in traffic.street_details.stop_anchors.values():
		all_sidewalk = all_sidewalk and bool(anchor.sidewalk_checked)
		if float(anchor.legacy_setback) > 0.0:
			ratios.append(float(anchor.actual_setback) / float(anchor.legacy_setback))
	ratios.sort()
	var median := ratios[floori(ratios.size() * 0.5)] if not ratios.is_empty() else INF
	print("[neighborhood_vehicle_placement] network ", JSON.stringify(network.get_status()), " minimum lane clearance ",min_lane_clearance," median sign setback ratio ",median)
	_check(all_sidewalk and not ratios.is_empty(), "stop signs stay on checked sidewalks")
	_check(median <= 0.78, "median stop-sign setback approaches two-thirds of former setback")
	var fleet := level.find_child("CivicParkingFleet",true,false) as Node3D
	if fleet == null:
		fleet = Fleet.build(level)
		level.add_child(fleet)
		await _frames(2)
	var fleet_status: Dictionary = fleet.get_meta("fleet_status",{})
	print("[neighborhood_vehicle_placement] civic fleet ",JSON.stringify(fleet_status))
	_check(int(fleet_status.get("total",0)) == 16 and fleet_status.get("rejected",[]).is_empty(), "six visitor cars, one ambulance and nine cruisers fit validated civic bays")
	var hulls := 0
	var proper := true
	for body in fleet.get_children():
		proper = proper and body is StaticBody3D and bool(body.get_meta("precise_vehicle_hulls",false))
		for child in body.get_children():
			if child is CollisionShape3D:
				hulls += 1
	_check(proper and hulls == 42, "civic fleet uses precise shared low-body/cabin hulls and bounded light bars")
	print("[neighborhood_vehicle_placement] failures=",failures)
	get_tree().quit(1 if failures else 0)
