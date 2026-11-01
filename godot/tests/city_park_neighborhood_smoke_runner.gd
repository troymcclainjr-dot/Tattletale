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
	var furniture = level.get("park_furniture")
	if furniture == null:
		failures.append("Park furniture was not integrated")
		_finish({})
		return
	var crowd = level.npcs.crowd
	var requested_court_found := false
	for court in level.park_courts.records:
		if str(court.id) == "park_court_17":
			failures.append("Removed Argonne court 17 was restored")
		if str(court.id) == "park_court_13":
			requested_court_found = true
			if str(court.kind) != "full" or court.hoops.size() != 2 or float(court.length_m) <= float(court.width_m):
				failures.append("Wyanoke court 13 lacks a lengthwise two-hoop layout")
	if not requested_court_found:
		failures.append("Wyanoke court 13 missing")
	if crowd._destination_population.has("court_edge:park_court_17"):
		failures.append("Crowd still targets removed court 17")
	var recipe: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(crowd.RECIPE_PATH))
	if crowd.residents.size() != 1200 or recipe.residents.size() != 1200:
		failures.append("Canonical population changed")
	for i in mini(crowd.residents.size(), recipe.residents.size()):
		var resident: Dictionary = crowd.residents[i]
		var canonical: Dictionary = recipe.residents[i]
		if resident.stable_id != canonical.id or resident.birth_position.distance_to(level.vector(canonical.birth_position)) > 0.001 or resident.birth_activity != canonical.activity or resident.birth_pose != canonical.pose:
			failures.append("Canonical identity changed: %d" % i)
			break
		if resident.pose == 1 and resident.activity != "porch":
			failures.append("Portable chair outside a porch: %d" % i)
		if resident.pose == 2:
			if not resident.has("bench_id") or resident.bench_id >= furniture.benches.size():
				failures.append("Seated park resident lacks a bench")
		elif resident.get("neighborhood_relocated", false):
			var hit: Dictionary = level.ground_at(resident.position)
			if hit.is_empty() or absf(hit.position.y + 0.012 - resident.position.y) > 0.06:
				failures.append("Redistributed neighbor is not grounded: %d" % i)
			if level.park_courts.is_court(resident.position, 1.0):
				failures.append("Redistributed neighbor blocks a court")
	if not crowd._identity_failures.is_empty():
		failures.append("Unplaced crowd identities")
	if furniture.playgrounds.size() != 2:
		failures.append("Expected exactly two playgrounds")
	for park in ["Community green 1", "Community green 2"]:
		var matches := 0
		for playground in furniture.playgrounds:
			matches += int(playground.park == park)
			if level.park_courts.is_court(playground.position, playground.size.length() * 0.5 + 1.9):
				failures.append("Playground intrudes into a court clearance")
		if matches != 1:
			failures.append("Playground missing/duplicated in " + park)
	if furniture.benches.size() < 12:
		failures.append("Too few validated benches")
	var vegetation = level.vegetation
	var vegetation_before: Dictionary = vegetation.get_stats()
	for plants in vegetation._cells.values():
		for plant in plants:
			if not str(plant.kind).begins_with("bush"):
				continue
			var point := Vector2(plant.position.x, plant.position.z)
			for playground in furniture.playgrounds:
				var center := Vector2(playground.position.x, playground.position.z)
				var half_size: Vector2 = playground.size * 0.5
				if point.distance_to(point.clamp(center - half_size, center + half_size)) < float(plant.radius) + 0.4:
					failures.append("Shrub crown overlaps playground clearance")
	if vegetation.clear_playground_shrubs(furniture.playgrounds) != 0 or int(vegetation.get_stats().trees) != int(vegetation_before.trees):
		failures.append("Playground shrub clearance is not idempotent/preserved trees")
	# Exercise all cached LOD/bush variants after the setup filter. A stale
	# pre-clearance cache would restore the larger plant count when revisited.
	for playground in furniture.playgrounds:
		var cell := Vector2i(floori(playground.position.x / vegetation.CELL), floori(playground.position.z / vegetation.CELL))
		if not vegetation._cells.has(cell):
			continue
		var trees := 0
		for plant in vegetation._cells[cell]:
			trees += int(str(plant.kind).begins_with("tree"))
		for lod in ["near", "far", "near"]:
			for bushes in [true, false]:
				var geometry: Dictionary = vegetation._cell_mesh(cell, lod, bushes)
				if int(geometry.plants) != (vegetation._cells[cell].size() if bushes else trees):
					failures.append("Stale vegetation mesh restored cleared shrubs")
	if int(crowd._park_population.get("Community green 2", 0)) > 16:
		failures.append("Northern edge park remains overcrowded")
	if int(crowd._physical_park_population.get("Community green 2", 0)) > 20:
		failures.append("Northern edge park still crowded when all activities are counted")
	if crowd._distribution_fallbacks > 0:
		failures.append("Park redistribution exhausted valid candidates")
	var sizes: Dictionary = {}
	for group in crowd._neighborhood_groups:
		var count: int = group.indices.size()
		sizes[count] = true
		if count < 2 or count > 8:
			failures.append("Neighborhood group outside 2..8 range")
	if sizes.size() < 5 or not sizes.has(2) or not sizes.has(8):
		failures.append("Insufficient visible group-size variation")
	if int(crowd._distribution_counts.get("business", 0)) < 8 or int(crowd._distribution_counts.get("court_edge", 0)) < 16:
		failures.append("Redistribution missed business or court destinations")
	if crowd._park_plan.size() < 860:
		failures.append("Original street circles were not redistributed")
	for key in crowd._destination_population:
		if str(key).begins_with("court_edge:") and int(crowd._destination_population[key]) > 16:
			failures.append("Court edge acquired an oversized assembly")
	# Restore a saved death for a moved park identity; its ordinal/birth anchor
	# must remain the same. This fixture never writes the user's checkpoint.
	for i in crowd.residents.size():
		if not crowd.residents[i].get("neighborhood_relocated", false):
			continue
		var birth: Vector3 = crowd.residents[i].birth_position
		if not level.combat.restore_deaths({"version":1,"dead":["crowd_%d" % i]}) or not crowd.is_dead(i) or crowd.residents[i].birth_position != birth:
			failures.append("Redistributed identity lost saved death")
		break
	_finish({"furniture": furniture.get_status(), "vegetation": vegetation.get_stats(), "crowd": crowd.get_status(), "group_sizes": sizes.keys()})

func _finish(status: Dictionary) -> void:
	print(JSON.stringify({"suite":"park_neighborhood", "status":status, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
