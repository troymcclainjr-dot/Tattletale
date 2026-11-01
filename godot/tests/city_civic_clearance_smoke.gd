extends SceneTree

class TestDistrict extends Node3D:
	var removed_building_ids := ["removed_home"]
	var removed_meshes := ["RemovedRow"]
	func is_cleared(at: Vector3) -> bool:
		return Rect2(380, -200, 80, 120).has_point(Vector2(at.x, at.z))

class TestLevel extends Node3D:
	var civic_district: Node3D

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var failures: Array[String] = []
	for file in ["city_civic_clearance", "city_vegetation", "city_yard_details", "city_park_courts", "city_power_grid", "city_parked_cars", "city_crowd", "city_residents", "city_npcs", "city_neighborhood_details"]:
		var script = load("res://scripts/city/" + file + ".gd")
		if script == null or not script.can_instantiate():
			failures.append(file + " failed to compile")
	if not failures.is_empty():
		print(JSON.stringify({"suite": "civic_clearance", "failures": failures}))
		quit(1)
		return
	var clearance = load("res://scripts/city/city_civic_clearance.gd")
	var level := TestLevel.new()
	level.civic_district = TestDistrict.new()
	level.add_child(level.civic_district)
	root.add_child(level)
	if not clearance.segment_blocked(level, Vector3(370, 0, -150), Vector3(470, 0, -150)):
		failures.append("Cross-site span was accepted when both endpoints were outside")
	if not clearance.record_removed(level, {"building_id": "removed_home", "position": [0, 0, 0]}):
		failures.append("Detached yard record of demolished home survived")
	if clearance.blocked(level, Vector3.ZERO, 0.4):
		failures.append("Unrelated neighborhood was cleared")
	var grid_script = load("res://scripts/city/city_power_grid.gd")
	var grid: Node3D = grid_script.new()
	level.add_child(grid)
	var status: Dictionary = grid.setup(level)
	if int(status.audit.civic_removed_poles) == 0:
		failures.append("Expected utility poles inside reserved construction area to be removed")
	for record in grid.records:
		if clearance.record_removed(level, record, 0.35):
			failures.append("Power pole survived inside construction area")
	for span in grid.spans:
		if int(span.a) < 0 or int(span.b) >= grid.records.size():
			failures.append("Pole removal broke span indices")
	print(JSON.stringify({"suite": "civic_clearance", "power": status, "failures": failures}))
	level.free()
	quit(0 if failures.is_empty() else 1)
