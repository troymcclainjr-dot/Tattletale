extends Node
## Actual provider methods with two bounded cells; no full-city fixture or saves.
var failures := 0

class TestPlayer extends Node3D:
	var camera_override: Dictionary = {}

class TestLevel extends Node3D:
	var player: Node3D
	var inspector: Node = null

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	failures += int(not ok)
	print("[capture_residency] %s %s" % ["PASS" if ok else "FAIL", label])

func _run() -> void:
	var world := TestLevel.new()
	add_child(world)
	world.player = TestPlayer.new()
	world.add_child(world.player)
	var vegetation = load("res://scripts/city/city_vegetation.gd").new()
	world.add_child(vegetation)
	vegetation.setup(world, world)
	var local := Vector2i.ZERO
	var remote := Vector2i(10, 0)
	vegetation._cells = {
		local: [{"kind": "tree0", "position": Vector3(12, 0, 12), "yaw": .2, "radius": 2.0, "height": 7.0, "trunk_radius": .12}],
		remote: [{"kind": "tree0", "position": Vector3(492, 0, 12), "yaw": .2, "radius": 2.0, "height": 7.0, "trunk_radius": .12}]}
	await vegetation.prepare_presence(Vector3.ZERO, 55.0, 180.0)
	var trunk: StaticBody3D = vegetation._active[local].node.get_node("TreeTrunk_0")
	var original_rid := trunk.get_rid()
	check(not vegetation._active.has(remote), "ordinary play does not load the remote tree cell")
	var alive = load("res://scripts/city/city_alive_world.gd").new()
	world.add_child(alive)
	var repaired_lawn := Node3D.new()
	alive.add_child(repaired_lawn)
	alive._register(repaired_lawn, Vector3(492, 0, 12))
	alive.set_presence(Vector3.ZERO, 55.0, 180.0)
	check(not repaired_lawn.visible, "distant repaired lawn begins culled at player focus")
	# Real yard loading creates colliders and attaches its preloaded mesh.
	var yards = load("res://scripts/city/city_yard_details.gd").new()
	world.add_child(yards)
	yards._material = StandardMaterial3D.new()
	var box := BoxMesh.new()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.append_from(box, 0, Transform3D.IDENTITY)
	var yard_mesh := surface.commit()
	for at in [Vector3(12, 0, 12), Vector3(492, 0, 12)]:
		yards.records.append({"kind": "can", "position": at, "basis": Basis.IDENTITY, "radius": .35})
	for index in 2:
		var coordinate := local if index == 0 else remote
		yards._cells[coordinate] = {"origin": Vector3(coordinate.x * 48, 0, 0), "indices": [index], "node": null,
			"bodies": [], "mesh": yard_mesh, "instance": null, "prefetch": false, "distance": INF, "path": "", "failed": false}
	yards.set_presence(Vector3.ZERO, 55.0, 180.0)
	# A distant preloaded mesh may be evicted by normal presence; supply it as a
	# cache hit again so this focused regression tests attachment, not disk IO.
	yards._cells[remote].mesh = yard_mesh
	var bin_rid: RID = yards._cells[local].bodies[0].get_rid()
	var streaming = load("res://scripts/city/city_streaming.gd").new()
	world.add_child(streaming)
	streaming.level = world
	streaming.providers.assign([vegetation, alive, yards])
	world.player.camera_override = {"eye": Vector3(492, 3, 12), "target": Vector3(1500, 8, 12)}
	for i in 4:
		streaming.refresh_now()
		await get_tree().process_frame
	check(repaired_lawn.visible, "camera eye makes the actual lawn repair provider visible")
	check(vegetation._active.has(remote) and str(vegetation._active[remote].lod) == "near", "camera eye loads near vegetation despite distant look-at target")
	check(not bool(vegetation._active[remote].physics), "camera-only tree cell creates no remote trunk collider")
	check(is_instance_valid(trunk) and trunk.get_rid() == original_rid and trunk.collision_layer == 2, "original player trunk collider/RID stays live")
	check(yards._cells[local].bodies[0].get_rid() == bin_rid and yards._cells[local].bodies[0].collision_layer == 2, "original player yard collider/RID stays live")
	check(is_instance_valid(yards._cells[remote].instance), "camera yard detail mesh attaches")
	check(int(streaming.get_status().detail_pending) == 0 and int(streaming.get_status().detail_missing) == 0, "combined building/detail readiness reports settled")
	world.player.camera_override.clear()
	streaming.refresh_now()
	await get_tree().process_frame
	check(not vegetation._active.has(remote) and not repaired_lawn.visible, "leaving capture returns to ordinary bounded player residency")
	check(is_instance_valid(trunk) and trunk.get_rid() == original_rid, "ending capture preserves the player collider")
	check(not bool(streaming.get_status().capture_details), "ordinary mode disables capture bookkeeping")
	get_tree().quit(0 if failures == 0 else 1)
