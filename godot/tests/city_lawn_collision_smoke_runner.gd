extends Node
var failures := 0

func check(ok: bool, label: String) -> void:
	print("[lawn_collision] %s %s" % ["PASS" if ok else "FAIL", label])
	failures += int(not ok)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var lawns = load("res://scripts/city/city_alive_world.gd").new()
	add_child(lawns)
	var report: Dictionary = lawns._build_lawn_collision([[[0,.125,0],[2,.125,0],[0,.125,2]]])
	check(report.cells == 1 and report.triangles == 1, "bounded cell collider built")
	var body := lawns.get_child(0) as StaticBody3D
	check(body.collision_layer == 1 and body.collision_mask == 0, "support belongs to terrain layer only")
	check((body.get_child(0) as CollisionShape3D).shape is ConcavePolygonShape3D, "offline surface triangles supply collision")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var query := PhysicsRayQueryParameters3D.create(Vector3(.5,1,.5), Vector3(.5,-1,.5), 1)
	var hit: Dictionary = lawns.get_world_3d().direct_space_state.intersect_ray(query)
	check(not hit.is_empty() and absf(hit.position.y-.125) < .001, "footing ray matches repaired lawn height")
	lawns.hide()
	await get_tree().physics_frame
	hit = lawns.get_world_3d().direct_space_state.intersect_ray(query)
	check(not hit.is_empty() and absf(hit.position.y-.125) < .001, "support survives decorative visibility culling")
	check(lawns._build_lawn_collision([]).cells == 0, "legacy manifests add no unnecessary colliders")
	lawns.queue_free()
	get_tree().quit(0 if failures == 0 else 1)
