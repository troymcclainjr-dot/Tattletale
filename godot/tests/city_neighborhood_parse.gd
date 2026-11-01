extends SceneTree
func _initialize() -> void:
	var failures := 0
	for filename in DirAccess.get_files_at("res://scripts/city"):
		if not filename.ends_with(".gd"):
			continue
		var script = load("res://scripts/city/" + filename)
		if script == null or not script.can_instantiate():
			push_error("Cannot load city script: " + filename)
			failures += 1
	print("[city_neighborhood_parse] failures=", failures)
	quit(0 if failures == 0 else 1)
