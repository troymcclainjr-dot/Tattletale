extends SceneTree
## Load integration scripts after autoload symbols are registered, without
## constructing the world. Runtime acceptance remains a separate gate.
func _initialize() -> void:
	var targets := OS.get_cmdline_user_args()
	if targets.is_empty():
		targets = PackedStringArray([
			"res://scripts/city/pen_lucy_level.gd",
			"res://scripts/city/city_police_cruisers.gd",
			"res://scripts/city/city_law.gd",
			"res://scripts/city/city_missions.gd",
			"res://scripts/city/city_progression.gd",
			"res://scripts/city/city_narrative.gd",
			"res://tests/city_narrative_smoke_runner.gd",
			"res://tests/city_story_input_smoke_runner.gd",
			"res://scripts/city/city_world_save.gd",
			"res://tests/city_priorities_session_runner.gd",
			"res://tests/city_priorities_soak_runner.gd",
		])
	for path in targets:
		var script := load(path) as Script
		if script == null or not script.can_instantiate():
			push_error("[priorities_compile] FAIL " + path)
			quit(1)
			return
		print("[priorities_compile] PASS " + path)
	quit(0)
