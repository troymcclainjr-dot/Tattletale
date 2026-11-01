extends SceneTree
var failures := 0
func check(ok: bool, text: String) -> void:
	failures += int(not ok)
	print("[civic_models] %s %s" % ["PASS" if ok else "FAIL", text])
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var district = load("res://scripts/city/city_civic_district.gd")
	check(district != null and district.can_instantiate(), "district integration script loads")
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")
	for id in ["police", "fire", "courthouse", "hospital"]:
		if not only.is_empty() and id != only:
			continue
		var path := "res://scripts/city/city_civic_%s.gd" % id
		if not FileAccess.file_exists(path):
			check(false, "missing required civic model " + id)
			continue
		var script = load(path)
		check(script != null and script.can_instantiate(), id + " script loads")
		if script == null or not script.can_instantiate():
			continue
		var model: Node3D = script.build()
		root.add_child(model)
		var surfaces := 0
		var triangles := 0
		var bounds := AABB()
		var first := true
		for visual in model.find_children("*", "MeshInstance3D", true, false):
			var box: AABB = visual.global_transform * visual.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
			surfaces += visual.mesh.get_surface_count()
			for index in visual.mesh.get_surface_count():
				var arrays: Array = visual.mesh.surface_get_arrays(index)
				triangles += (arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX] != null and arrays[Mesh.ARRAY_INDEX].size() > 0 else arrays[Mesh.ARRAY_VERTEX].size()) / 3
		var footprint: Vector2 = script.footprint()
		check(surfaces > 0 and surfaces <= 12, id + " batched finish budget")
		check(triangles < 18000, id + " geometry budget")
		check(bounds.position.x >= -footprint.x / 2 - 0.1 and bounds.end.x <= footprint.x / 2 + 0.1 and bounds.position.z >= -footprint.y / 2 - 0.1 and bounds.end.z <= footprint.y / 2 + 0.1, id + " contained in declared site")
		var colliders := model.find_children("*", "CollisionShape3D", true, false).size()
		check(colliders > 0 and colliders <= 32, id + " solid architecture within collider budget")
		print("[civic_models] %s triangles=%d surfaces=%d colliders=%d bounds=%s" % [id, triangles, surfaces, colliders, bounds])
		model.free()
	var shop_script = load("res://scripts/city/city_civic_businesses.gd")
	for grounds_id in ["hospital", "fire"]:
		var grounds = load("res://scripts/city/city_civic_%s_grounds.gd" % grounds_id)
		check(grounds != null and grounds.can_instantiate(), grounds_id + " grounds script loads")
		if grounds != null and grounds.can_instantiate():
			var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/pen_lucy_civic_build.json"))
			var site: Dictionary = plan.sites.filter(func(s): return s.id == grounds_id)[0]
			var campus: Node3D = grounds.build(site)
			root.add_child(campus)
			check(not campus.find_children("*", "CollisionShape3D", true, false).is_empty(), grounds_id + " grounds have solid support")
			campus.free()
	check(shop_script != null and shop_script.can_instantiate(), "business module loads")
	if shop_script != null and shop_script.can_instantiate():
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/pen_lucy_new_businesses.json"))
		check(data.businesses.size() == 8, "eight distributed businesses")
		for entry in data.businesses:
			var shop: Node3D = shop_script.build(entry)
			root.add_child(shop)
			check(not shop.find_children("*", "MeshInstance3D", true, false).is_empty(), "built " + str(entry.id))
			shop.free()
	quit(0 if failures == 0 else 1)
