extends Node
## Small real-physics fixtures isolate yielding, blocked activation, and resync.
const Residents := preload("res://scripts/city/city_residents.gd")
const Resident := preload("res://scripts/city/city_resident_actor.gd")
const Clock := preload("res://scripts/city/city_world_time.gd")

class People:
	extends Node3D
	func stair_approach_clear(_at: Vector3, _radius: float) -> bool:
		return true
	func _street_info(at: Vector3) -> Dictionary:
		return {"width": 0.0, "sidewalk": 12.0, "distance": absf(at.x + 6.0)}

class Arena:
	extends Node3D
	var player: CharacterBody3D
	var npcs: Node3D
	var residents: Node3D
	var vegetation: Node3D
	var world_time: Node
	var traffic: Node3D
	func ground_at(at: Vector3) -> Dictionary:
		var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP, at - Vector3.UP * 2.0, 1)
		return get_world_3d().direct_space_state.intersect_ray(ray)

var arena: Node3D
var provider: Node3D
var failures := 0
var passes := 0

func check(ok: bool, label: String) -> void:
	print("[resident_recovery] %s %s" % ["PASS" if ok else "FAIL", label])
	if ok:
		passes += 1
	else:
		failures += 1

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func advance(seconds: float) -> void:
	for i in ceili(seconds * 60.0):
		provider.tick(1.0 / 60.0)
		await frames(1)

func capsule(at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 8
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.28
	shape.height = 1.8
	collision.shape = shape
	collision.position.y = 0.98
	body.add_child(collision)
	arena.add_child(body)
	body.position = at
	return body

func make_actor(id: String, at: Vector3, goal: Vector3):
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Residents.DATA_PATH))
	var definition: Dictionary = data.residents[0].duplicate(true)
	definition.id = id
	definition.speed = 1.2
	var actor := Resident.new()
	provider.add_child(actor)
	actor.build_resident(arena, definition)
	actor.position = at
	actor.yaw = atan2(goal.x - at.x, goal.z - at.z)
	var points: Array[Vector3] = []
	var count := maxi(1, ceili(at.distance_to(goal)))
	for i in range(1, count + 1):
		points.append(at.lerp(goal, float(i) / count))
	actor.assign_route(points, "work", "Fixture destination")
	provider.actors[id] = actor
	return actor

func clear_actors() -> void:
	for actor in provider.actors.values():
		actor.free()
	provider.actors.clear()
	provider.routes.clear()
	provider._last_slots.clear()

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	arena = Arena.new()
	add_child(arena)
	arena.npcs = People.new()
	arena.add_child(arena.npcs)
	arena.player = CharacterBody3D.new()
	arena.add_child(arena.player)
	arena.player.position = Vector3(8, 0, 8)
	arena.world_time = Clock.new()
	arena.add_child(arena.world_time)
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	floor_shape.shape = box
	ground.add_child(floor_shape)
	arena.add_child(ground)
	ground.position.y = -0.5
	provider = Residents.new()
	arena.add_child(provider)
	arena.residents = provider
	provider.level = arena
	provider._shape = CapsuleShape3D.new()
	provider._shape.radius = 0.30
	provider._shape.height = 1.90
	await frames(3)
	var a = make_actor("daily_a", Vector3(0, 0.012, -3), Vector3(0, 0.012, 3))
	var b = make_actor("daily_b", Vector3(0, 0.012, 3), Vector3(0, 0.012, -3))
	await advance(16.0)
	check(a.global_position.z > 2.7 and b.global_position.z < -2.7, "two head-on residents pass and reach opposite destinations")
	check(a.recovery_count > 0, "lower stable identity yields deterministically")
	check(a.global_position.distance_to(b.global_position) > 0.60, "passing residents retain separate physical positions")
	clear_actors()
	var walker = make_actor("daily_walker", Vector3(0, 0.012, -3), Vector3(0, 0.012, 3))
	var crowd_body := capsule(Vector3(0, 0.012, 0))
	await advance(12.0)
	check(walker.global_position.z > 2.7 and walker.recovery_count > 0, "resident bypasses a stationary collidable crowd body")
	crowd_body.free()
	clear_actors()
	var far = make_actor("daily_far", Vector3(0, 0.012, 0), Vector3(0, 0.012, 5))
	far.physical = false
	far.set_enabled(false)
	var blocker := capsule(far.global_position)
	await frames(2)
	provider.tick(0.5)
	check(not far.physical and far.global_position.z > 0.4, "failed activation keeps advancing cheap logical progress")
	await advance(2.0)
	check(far.physical and far.enabled, "resident activates after logical progress clears the occupied spot")
	blocker.free()
	clear_actors()
	var far_a = make_actor("daily_a", Vector3(0, 0.012, -1), Vector3(0, 0.012, 2))
	var far_b = make_actor("daily_b", Vector3(0, 0.012, 1), Vector3(0, 0.012, -2))
	arena.player.position = Vector3(150, 0, 0)
	far_a.physical = false
	far_b.physical = false
	far_a.set_enabled(false)
	far_b.set_enabled(false)
	var separated := true
	for i in 20:
		provider.tick(0.5)
		separated = separated and far_a.position.distance_to(far_b.position) >= 0.65
	check(separated, "far residents reserve logical space before either activates")
	clear_actors()
	arena.player.position = Vector3(8, 0, 8)
	var returned = make_actor("daily_return", Vector3(2, 0.012, -2), Vector3(4, 0.012, -2))
	var corridor: Array[Vector3] = [Vector3(0, 0.012, -2), Vector3(0, 0.012, -1), Vector3(0, 0.012, 0), Vector3(0, 0.012, 1), Vector3(0, 0.012, 2)]
	provider.routes[returned.actor_id] = {"points": corridor, "anchors": {"home": 0, "sleep": 0, "work": 4, "leisure": 2}}
	arena.world_time.set_time(540.0)
	var before: Vector3 = returned.position
	check(provider.resume_after_combat(returned), "combat release finds a validated connector to the current daily destination")
	check(returned.position == before and returned.activity == "work" and returned.route_points[-1] == corridor[-1], "combat resync neither teleports nor restores the stale fight target")
	await advance(10.0)
	check(returned.position.distance_to(corridor[-1]) < 0.20, "returned resident physically rejoins its daily route")
	returned.set_distance_fade(89.2)
	returned.set_distance_fade(105.0)
	var hidden := true
	for mesh in returned._visual_meshes:
		hidden = hidden and not mesh.visible
	check(hidden, "fully faded puppet parts are hidden from rendering")
	print("[resident_recovery] %d passed; %d failed" % [passes, failures])
	get_tree().quit(0 if failures == 0 else 1)
