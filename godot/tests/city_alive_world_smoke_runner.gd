extends Node
var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	get_tree().change_scene_to_file("res://scenes/city/pen_lucy.tscn")
	var level: Node
	for frame in 1800:
		await get_tree().physics_frame
		await get_tree().process_frame
		level = get_tree().current_scene
		if level != null and level.get("level_ready") == true:
			break
	if level == null or level.get("level_ready") != true:
		failures.append("Level initialization failed")
		_finish({})
		return
	level.pause_exploring()
	var details := level.find_child("CityAliveWorld", true, false)
	if details == null:
		failures.append("World repair provider not integrated")
		_finish({})
		return
	var status: Dictionary = details.get_status()
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/pen_lucy_alive_world.json"))
	if int(status.get("fences", 0)) < 1 or not bool(source.audit.frisby_fence):
		failures.append("Requested Frisby side fence missing")
	if int(status.get("dumpsters", 0)) < 1 or not status.get("dumpster_rejected", []).is_empty():
		failures.append("Authored Dumbarton rear dumpster failed terrain/occupancy validation")
	if float(source.audit.fire_grass_area_m2.west) < 5 or float(source.audit.fire_grass_area_m2.east) < 5:
		failures.append("One firehouse side lawn is missing")
	var shrubs := 0
	var conifers := 0
	for cell in level.vegetation._cells.values():
		for plant in cell:
			if str(plant.kind) in ["tree4", "tree5"]:
				conifers += 1
			if str(plant.get("source_mesh", "")) != "Row_050" or not bool(plant.get("authored_size", false)):
				continue
			shrubs += 1
			var hit: Dictionary = level.ground_at(plant.position)
			if hit.is_empty() or absf(float(hit.position.y) - float(plant.position.y)) > .05:
				failures.append("Row050 authored shrub does not match final terrain")
	if shrubs != source.plants.size() or shrubs == 0:
		failures.append("Row050 authored lawn shrubs missing")
	if conifers == 0:
		failures.append("New pine templates were not used")
	for fence in source.fences:
		for p in fence.posts:
			var at: Vector3 = level.vector(p)
			var hit: Dictionary = level.ground_at(at)
			if hit.is_empty() or absf(float(hit.position.y) - at.y) > .05:
				failures.append("Private fence post unsupported: " + str(fence.id))
				break
	# Source-authored rear entry metadata survives the narrow-front repair.
	var rear_count := 0
	for door in level.level_data.rear_doors:
		rear_count += int(str(door.source_mesh) == "Row_170")
	if rear_count != 8:
		failures.append("Dumbarton rear doors changed: %d" % rear_count)
	status["verified_lawn_shrubs"] = shrubs
	status["conifers"] = conifers
	status["row170_rear_doors"] = rear_count
	_finish(status)

func _finish(status: Dictionary) -> void:
	print("ALIVE_WORLD_SMOKE " + JSON.stringify({"failures": failures, "status": status}))
	get_tree().quit(0 if failures.is_empty() else 1)
