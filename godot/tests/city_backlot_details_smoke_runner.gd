extends Node
const Details = preload("res://scripts/city/city_backlot_details.gd")
var failures := 0

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	failures += int(not ok)
	print("[backlot_details] %s %s" % ["PASS" if ok else "FAIL", label])

func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func _run() -> void:
	get_tree().change_scene_to_file("res://scenes/city/pen_lucy.tscn")
	await _frames(4)
	var level: Node3D = get_tree().current_scene
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
	var details: Node3D = level.get_node_or_null("CityBacklotDetails")
	if details == null:
		details = Details.new()
		level.add_child(details)
		details.setup(level)
	await _frames(2)
	var status: Dictionary = details.get_status()
	print("[backlot_details] status ", JSON.stringify(status))
	_check(bool(status.get("enabled", false)), "source-authored module initializes")
	_check(int(status.get("total", 0)) == int(status.get("requested", -1)), "every checked source placement survives actual physics")
	for id in ["WyanokeBldg219Dumpster", "CatorMarketDumpster", "CatorAcrossGapCar"]:
		_check(bool(status.get("mandatory", {}).get(id, false)), id + " placed")
	_check(level.find_child("Bldg_219", true, false) != null, "Bldg219 retained alongside requested dumpster")
	var bodies := 0
	var hulls := 0
	for node in details.get_children():
		if node is StaticBody3D and node.get_meta("backlot_dumpster", false):
			bodies += 1
			for child in node.get_children():
				if child is CollisionShape3D:
					hulls += 1
	_check(bodies == int(status.get("dumpsters", -1)) and hulls == bodies * 8, "dumpster body/lid/handle/foot hulls match reused mesh")
	_check(not details.is_processing(), "static details have no frame processing")
	_check(int(status.get("dumpster_batches", 100)) <= bodies, "dumpsters share material and spatial MultiMesh batches")
	get_tree().quit(0 if failures == 0 else 1)
