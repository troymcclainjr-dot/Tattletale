extends Node
var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	get_tree().change_scene_to_file("res://scenes/city/pen_lucy.tscn")
	var level: Node
	for frame in 1200:
		await get_tree().physics_frame
		await get_tree().process_frame
		level = get_tree().current_scene
		if level != null and level.get("level_ready") == true:
			break
	if level == null or level.get("level_ready") != true:
		failures.append("Level did not initialize")
		_finish({})
		return
	level.pause_exploring()
	var crowd = level.npcs.crowd
	var path := "res://assets/data/pen_lucy_crowd_recipe.json"
	if not FileAccess.file_exists(path):
		failures.append("Canonical crowd recipe missing")
		_finish({})
		return
	var recipe: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var exporting := "--export-crowd-recipe" in OS.get_cmdline_user_args()
	if recipe.residents.size() != crowd.residents.size():
		failures.append("Crowd count changed canonical ordinal range")
	if not exporting:
		if crowd._identity_source != "canonical_legacy_recipe":
			failures.append("Runtime did not use canonical legacy identities")
		var identities: Array = crowd.identity_snapshot()
		for index in mini(identities.size(), recipe.residents.size()):
			var expected: Dictionary = recipe.residents[index]
			var actual: Dictionary = identities[index]
			if actual.id != expected.id or level.vector(actual.birth_position).distance_to(level.vector(expected.birth_position)) > 0.001 or actual.birth_activity != expected.activity:
				failures.append("Legacy identity changed at index %d" % index)
				break
		if not crowd._identity_failures.is_empty():
			failures.append("Some legacy identities could not be safely relocated")
		if level.civic_district == null and level.get("park_furniture") == null and crowd._identity_relocated != 0:
			failures.append("Unchanged city unexpectedly relocates canonical legacy neighbors")
		if level.civic_district != null:
			for resident in crowd.residents:
				if level.civic_district.is_cleared(resident.position):
					failures.append("Canonical resident remains in cleared construction area")
		# Saved death IDs stay attached to their original birth anchors, including
		# a relocated identity. This never writes/reset the player's save registry.
		var affected := -1
		for index in crowd.residents.size():
			if crowd.residents[index].get("civic_relocated", false):
				affected = index
				break
		var dead_index := affected if affected >= 0 else 0
		var before: Array = crowd.identity_snapshot()
		if not level.combat.restore_deaths({"version": 1, "dead": ["crowd_%d" % dead_index]}):
			failures.append("Legacy death registry rejected canonical ID")
		if not crowd.is_dead(dead_index) or crowd.identity_snapshot()[dead_index].birth_position != before[dead_index].birth_position:
			failures.append("Restored death moved to a different identity")
	_finish({"count": crowd.residents.size(), "identity_source": crowd._identity_source, "relocated": crowd._identity_relocated, "failures_to_relocate": crowd._identity_failures, "civic_enabled": level.civic_district != null})

func _finish(status: Dictionary) -> void:
	print(JSON.stringify({"suite": "crowd_identity", "status": status, "failures": failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
