extends Node
## Actual physics-space strikes, cover, retaliation and permanent death in a small arena.
const Combat := preload("res://scripts/city/city_combat.gd")
const Player := preload("res://scripts/city/city_player.gd")
const Actor := preload("res://scripts/city/city_npc_actor.gd")
const Crowd := preload("res://scripts/city/city_crowd.gd")

class PeopleFixture:
	extends Node3D
	var actors: Dictionary = {}
	var crowd: Node3D
	func _route_distance(_at: Vector3) -> float:
		return 0.0

class Arena:
	extends Node3D
	var player: CharacterBody3D
	var npcs: Node3D
	var residents: Node3D
	func ground_at(at: Vector3) -> Dictionary:
		var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP, at - Vector3.UP, 1)
		return get_world_3d().direct_space_state.intersect_ray(ray)

var arena: Node3D
var player: CharacterBody3D
var actor: CharacterBody3D
var combat: Node3D
var failures := 0

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	failures += int(not ok)
	print("[city_combat] %s %s" % ["PASS" if ok else "FAIL", label])

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func advance(seconds: float) -> void:
	for i in ceili(seconds * 60.0):
		combat.tick(1.0 / 60.0)
		combat.apply_player_pose(1.0 / 60.0)
		await frames(1)

func box(at: Vector3, size_: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var mesh := BoxShape3D.new()
	mesh.size = size_
	shape.shape = mesh
	body.add_child(shape)
	arena.add_child(body)
	body.global_position = at
	return body

func id_with(armed: bool, prefix: String) -> String:
	for i in 200:
		var id := "%s_%d" % [prefix, i]
		if Combat.is_armed_id(id) == armed:
			return id
	return prefix

## Death is permanent, so later sections use a fresh, deliberately unarmed identity.
func replace_actor(id: String) -> void:
	actor = Actor.new()
	arena.npcs.add_child(actor)
	actor.build(arena, id, "mama", "Mission contact")
	arena.npcs.actors[id] = actor
	await frames(1)

func clear_fight() -> void:
	for state in combat._active.values().duplicate():
		combat._release(state)
	for state in combat._panic.values().duplicate():
		combat._release(state)
	actor.position = Vector3(0, 0.012, 1.35)
	actor.yaw = PI
	actor.puppet.g.rotation.y = PI
	player.position = Vector3(0, 0.012, 0)
	player.yaw = 0.0
	player.camera_yaw = 0.0
	player.enabled = true
	combat.downed = 0.0
	combat.health = 100.0
	combat._invulnerable = 0.0
	combat._shot_cooldown = 0.0
	combat.equip("fists")
	await frames(2)

func _run() -> void:
	arena = Arena.new()
	add_child(arena)
	box(Vector3(0, -0.5, 0), Vector3(120, 1, 120))
	player = Player.new()
	arena.add_child(player)
	player.set_physics_process(false)
	arena.player = player
	arena.npcs = PeopleFixture.new()
	arena.add_child(arena.npcs)
	arena.residents = PeopleFixture.new()
	arena.add_child(arena.residents)
	actor = Actor.new()
	arena.npcs.add_child(actor)
	actor.build(arena, "resident", "mama", "Mission contact")
	arena.npcs.actors.resident = actor
	combat = Combat.new()
	arena.add_child(combat)
	combat.setup(arena)
	await clear_fight()
	check(combat._gun.get_parent() == player.puppet.hands[0], "equipped pistol is attached to actual hand")
	var before: int = combat.hits_landed
	var health_after_punch: Array[float] = []
	for beat in 3:
		check(combat.request_attack(), "deliberate combo click %d accepted" % (beat + 1))
		await advance([0.40, 0.44, 0.58][beat])
		health_after_punch.append(float(combat._knocked[actor.actor_id].state.health) if combat._knocked.has(actor.actor_id) else float(combat._active[actor.get_instance_id()].health))
	check(combat.hits_landed == before + 3, "three-hit combo has exactly one damage event per punch")
	check(combat.combo == 3 and health_after_punch == [72.0, 50.0, 1.0] and not actor.dead, "jab/cross apply distinct damage and third strike produces a living knockdown")
	var state: Dictionary = combat._knocked[actor.actor_id]
	check(actor.combat_override and actor.has_meta("combat_controlled"), "provoked actor takes physical control from schedule")
	var frozen_time: float = state.time
	var frozen_attack: float = combat._attack_elapsed
	player.enabled = false
	combat.tick(0.1)
	check(state.time == frozen_time and combat._attack_elapsed == frozen_attack and not combat.request_attack(), "menu/dialogue freeze combat and reject attacks")
	player.enabled = true
	await advance(0.6)
	check(combat.request_attack(), "later deliberate input starts the lethal stomp")
	await advance(0.4)
	var victim_key: int = actor.get_instance_id()
	check(actor.dead and combat.is_actor_dead("resident") and not actor.enabled and actor.collision_layer == 0, "explicit stomp kills the mission contact and removes its collider")
	check(not combat._active.has(victim_key) and combat.get_status().deaths == 1, "the dead actor leaves the fight budget immediately")
	await advance(4.2)
	actor.set_enabled(true)
	check(actor.dead and not actor.enabled and arena.npcs.actors.resident == actor, "dead contact never recovers and stays addressable for mission filtering")
	var snapshot: Dictionary = combat.death_snapshot()
	check(snapshot.version == 1 and snapshot.dead.size() == 1 and snapshot.dead[0] == "resident", "death registry snapshot lists the stable identity")
	await replace_actor(id_with(false, "contact"))

	await clear_fight()
	var wall := box(Vector3(0, 1.1, 0.67), Vector3(3, 2.2, 0.12))
	await frames(2)
	before = combat.hits_landed
	combat.request_attack()
	await advance(0.4)
	check(combat.hits_landed == before, "melee line of sight cannot hit through a wall")
	wall.queue_free()
	await frames(2)

	await clear_fight()
	combat._damage_target(actor, 1.0, "test")
	state = combat._active[actor.get_instance_id()]
	state.hurt = 0.0
	state.cooldown = 0.0
	var health_before: float = combat.health
	var hits_before: int = combat.player_hits
	await advance(0.3)
	check(combat.health == health_before, "retaliation has readable wind-up before first hit")
	await advance(1.65)
	check(combat.player_hits - hits_before == 3 and combat.health == health_before - 29.0, "NPC return combo produces exactly three timed hits (hits=%d damage=%.1f)" % [combat.player_hits - hits_before, health_before - combat.health])
	player.position.z = -22.0
	await advance(0.05)
	check(not actor.combat_override, "walking away deaggros and restores actor ownership")

	await clear_fight()
	actor.position.z = 6.0
	combat.equip("pistol")
	combat.aiming = true
	combat.apply_player_pose(0.1)
	player.camera.global_position = Vector3(0, 1.3, -2)
	player.camera.look_at(Vector3(0, 1.2, 10), Vector3.UP)
	await frames(2)
	before = combat.hits_landed
	check(combat.request_attack(), "pistol accepts deliberate shot")
	check(combat.ammo == 11 and combat.hits_landed == before + 1, "camera-directed hitscan damages physical target and spends one round")
	check(not combat.request_attack() and combat.ammo == 11, "fire cooldown prevents duplicate shots")
	check(combat.request_reload(), "partial magazine reload starts")
	check(not combat.request_attack(), "reload blocks firing")
	player.enabled = false
	var reload_time: float = combat.reloading
	combat.tick(0.1)
	check(combat.reloading == reload_time, "reload timer freezes with menu")
	player.enabled = true
	await advance(1.5)
	check(combat.ammo == 12 and combat.reserve == 71, "reload transfers bounded reserve into magazine")
	combat.ammo = 0
	combat.reserve = 0
	check(not combat.request_reload() and not combat.request_attack(), "empty reserve cannot synthesize ammunition")

	await clear_fight()
	actor.position = Vector3(0, 0.012, -1.0)
	combat.equip("pistol")
	combat.ammo = 12
	combat.aiming = true
	combat.apply_player_pose(0.1)
	player.camera.global_position = Vector3(0, 1.3, -3.0)
	player.camera.look_at(Vector3(0, 1.3, 20), Vector3.UP)
	await frames(2)
	before = combat.hits_landed
	combat.request_attack()
	# The bystander may flinch away from the noise, but is never the bullet's target.
	check(combat.hits_landed == before and not combat._active.has(actor.get_instance_id()) and not actor.dead, "NPC between chase camera and player is never shot backwards")
	check((combat.last_shot.to - combat.last_shot.from).dot(Vector3.BACK) >= 0.0, "muzzle endpoint remains in forward aim hemisphere")
	await clear_fight()
	combat._damage_target(actor, 1.0, "test")
	var changed_destination := Vector3(5, 0.012, 5)
	actor.set_target(changed_destination, true)
	combat._release(combat._active[actor.get_instance_id()])
	check(actor.target == changed_destination and actor.has_target and actor.manual_target, "mission retarget during combat survives release")

	await clear_fight()
	actor.position = Vector3(0, 0.012, 8)
	combat.equip("pistol")
	combat.ammo = 12
	combat.aiming = true
	combat.apply_player_pose(0.1)
	# Camera peeks above a low wall while the hand/chest are behind it.
	player.camera.global_position = Vector3(0, 3.0, -2)
	player.camera.look_at(Vector3(0, 1.2, 8), Vector3.UP)
	wall = box(Vector3(0, 0.9, 1), Vector3(4, 1.8, 0.18))
	await frames(2)
	before = combat.hits_landed
	combat.request_attack()
	check(combat.hits_landed == before and combat.last_shot.collider == wall, "muzzle ray blocks shot when camera can see over cover")
	wall.queue_free()
	await frames(2)
	# Thin wall intersects the chest-to-barrel segment, even if barrel protrudes.
	var muzzle: Vector3 = combat.muzzle_position()
	var chest: Vector3 = player.global_position + Vector3.UP * 1.2
	wall = box(chest.lerp(muzzle, 0.5), Vector3(0.04, 0.6, 0.6))
	await frames(2)
	combat._shot_cooldown = 0.0
	combat.request_attack()
	check(combat.last_shot.barrel_blocked, "chest-to-barrel guard blocks a protruding muzzle")
	wall.queue_free()
	await frames(2)

	await clear_fight()
	player.camera_pitch = 0.0
	combat.equip("pistol")
	combat.aiming = true
	player.update_camera()
	var camera_offset: Vector3 = player.camera.global_position - player.global_position
	check(camera_offset.x < -0.70 and camera_offset.z > -3.2 and camera_offset.z < -3.0, "pistol aim uses shorter right-shoulder camera outside the head")
	var aim_ray: Vector3 = -player.camera.global_basis.z
	check(aim_ray.dot(Vector3.BACK) > 0.999, "full aim center ray preserves chosen view yaw and pitch")
	wall = box(Vector3(-0.60, 1.7, -1.5), Vector3(0.10, 3.4, 5.0))
	await frames(2)
	player.update_camera()
	var clearance := PhysicsShapeQueryParameters3D.new()
	clearance.shape = player._camera_collision_shape
	clearance.transform.origin = player.camera.global_position
	clearance.collision_mask = 1 | 2 | 16
	check(player.camera.global_position.x > -0.39 and arena.get_world_3d().direct_space_state.intersect_shape(clearance, 1).is_empty(), "full shoulder boom sweep prevents camera clipping through side cover")
	wall.queue_free()
	await frames(2)
	combat.equip("fists")
	player.update_camera()
	camera_offset = player.camera.global_position - player.global_position
	check(absf(camera_offset.x) < 0.001 and absf(camera_offset.z + 5.2) < 0.001, "unarmed camera restores original centered 5.2m boom")

	await clear_fight()
	combat._hurt_player(100.0)
	check(combat.downed > 0.0 and combat.blocks_movement(), "player zero health starts recoverable knockdown")
	await advance(3.6)
	check(combat.health == 100.0 and not combat.blocks_movement(), "player returns without reload or lost case state")
	player.enabled = false
	player._jump_active = false
	player.position = Vector3(0, 4, 0)
	player.velocity = Vector3(0, -3, 0)
	var paused_position: Vector3 = player.position
	player._physics_process(1.0 / 60.0)
	check(player.position == paused_position and player.velocity.y == -3.0, "menu freezes passive airborne falls while retaining resume velocity")
	await _crowd_checks()
	# Flush the last proxy/barrier frees before the SceneTree shuts down.
	await frames(2)
	arena.queue_free()
	await frames(2)
	# Uncapped headless simulation can end before the audio thread consumes its
	# stop commands. Give that thread a bounded real-time shutdown grace period.
	var audio_deadline := Time.get_ticks_msec() + 150
	while Time.get_ticks_msec() < audio_deadline:
		await get_tree().process_frame
	print("[city_combat] failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)

func _crowd_checks() -> void:
	await clear_fight()
	var crowd := Crowd.new()
	arena.npcs.add_child(crowd)
	arena.npcs.crowd = crowd
	crowd.level = arena
	crowd.npcs = arena.npcs
	crowd._shape = CapsuleShape3D.new()
	crowd._shape.radius = 0.24
	crowd._shape.height = 1.65
	crowd._meshes = [crowd._person_mesh(false), crowd._person_mesh(true)]
	for i in 9:
		crowd._add_resident(Vector3(4 + i * 1.4, 0.012, 4), PI, "social", false)
	crowd._build_batches()
	await frames(2)
	for i in 9:
		combat._damage_target(crowd.residents[i].body, 18.0, "punch")
	check(combat._active.size() == Combat.MAX_ACTIVE, "primitive crowd promotion obeys strict active actor budget")
	check(crowd.residents[0].combat_controlled and crowd.residents[0].body.collision_layer == 0, "promotion hides original collider instead of duplicating person")
	var promoted: Dictionary = combat._active.values()[0]
	var index: int = promoted.crowd_index
	combat._release(promoted)
	check(not crowd.residents[index].combat_controlled and crowd.residents[index].body.collision_layer == 8, "crowd demotion restores shared render/collider ownership")
	var returning: Dictionary = combat._active.values()[0]
	for other in combat._active.values().duplicate():
		if other != returning:
			combat._release(other)
	var proxy: CharacterBody3D = returning.actor
	var original: Vector3 = returning.home
	proxy.global_position = original + Vector3(0, 0, 2.5)
	proxy.yaw = PI
	var barrier := box(original + Vector3(0, 1.2, 1.1), Vector3(2.0, 2.4, 0.2))
	await frames(2)
	combat.health = 40.0
	combat._since_hurt = 9.0
	combat._start_return(returning)
	await advance(6.2)
	var restored: Dictionary = crowd.residents[returning.crowd_index]
	check(combat._active.is_empty() and combat.health > 40.0, "blocked crowd return releases its slot and permits health recovery")
	check(restored.position.distance_to(original) > 0.4 and restored.body.global_position.is_equal_approx(restored.position), "timed-out crowd demotes at its current safe spot without teleporting home")
	barrier.queue_free()
