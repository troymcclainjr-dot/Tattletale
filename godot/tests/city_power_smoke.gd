extends SceneTree
## Lightweight fixture: no city scene/import or physics world needed.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var script = load("res://scripts/city/city_power_grid.gd")
	if script == null or not script.can_instantiate():
		quit(1)
		return
	var grid: Node3D = script.new()
	root.add_child(grid)
	var owner_level := Node3D.new()
	var status: Dictionary = grid.setup(owner_level)
	owner_level.free()
	var failures: Array[String] = []
	if int(status.get("poles", 0)) < 100 or int(status.get("spans", 0)) < 70:
		failures.append("Expected neighborhood-wide pole and span coverage")
	if float(status.audit.minimum_wire_ground_clearance_m) < 7.2:
		failures.append("Wire clearance is below design minimum")
	if status.audit.streets.size() < 15:
		failures.append("Power grid misses named neighborhood streets")
	if grid.is_processing() or int(status.collision_bodies) != 0 or int(status.shadow_casters) != 0:
		failures.append("Decorative grid acquired ticks/collisions/shadows")
	grid.set_presence(Vector3.ZERO, 55.0, 180.0)
	var nearby: Dictionary = grid.get_status()
	if int(nearby.visible_cells) == 0 or int(nearby.visible_cells) >= int(nearby.cells):
		failures.append("Nearby grid cells should be visible and distant cells culled")
	grid.set_presence(Vector3(10000, 0, 10000), 55.0, 180.0)
	if int(grid.get_status().visible_cells) != 0:
		failures.append("Far grid did not cull")
	for cell in grid.get_children():
		if cell.get_child_count() > 2:
			failures.append("A power cell exceeds two draw batches")
		for child in cell.get_children():
			if child is CollisionObject3D:
				failures.append("Power grid introduced a player snag collider")
	print(JSON.stringify({"suite": "city_power", "status": status, "failures": failures}))
	grid.free()
	quit(0 if failures.is_empty() else 1)
