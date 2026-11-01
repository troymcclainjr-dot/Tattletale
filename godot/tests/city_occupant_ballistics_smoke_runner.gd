extends Node
## Real authored/opened car mesh + visible posed driver + real world physics.
## The subclass only suppresses unrelated audiovisual/neighbor reactions; rays,
## NPC bullet resolution, health, wounds and contact consequences stay production.
const Presentation := preload("res://scripts/city/city_vehicle_presentation.gd")
const Models := preload("res://scripts/city/city_car_models.gd")
const Collision := preload("res://scripts/city/city_car_collision.gd")
const Actor := preload("res://scripts/city/city_npc_actor.gd")

class LevelFixture:
	extends Node3D
	var paused := false
	var driving: Node3D
	var vehicle_presentation: Node3D
	var traffic: Node3D
	var npcs: Node3D
class DrivingFixture:
	extends Node3D
	var active := true
	var vehicle: CharacterBody3D
	var _controls := {"throttle": 0.0, "handbrake": false}
class PlayerFixture:
	extends CharacterBody3D
	var enabled := true
	var current_speed := 0.0
class CarFixture:
	extends CharacterBody3D
	var prototype_kind := "hatchback"
	var model: Node3D
	var speed := 0.0
	var drive_velocity := Vector3.ZERO
	var drive_steer := 0.0
	var drive_airborne := false
	var body_disabled := false
	var vehicle_id := "other_car_fixture"
	func apply_body_damage(_damage: float, _origin := Vector3.INF) -> bool:
		return true
class CombatProbe:
	extends "res://scripts/city/city_combat.gd"
	func _sound(_kind: String) -> void:
		pass
	func _world_sound(_kind: String, _at: Vector3) -> void:
		pass
	func _spark(_at: Vector3, _color: Color) -> void:
		pass
	func _tracer(_from: Vector3, _to: Vector3) -> void:
		pass
	func _gunshot_event(_origin: Vector3, _from: Vector3, _endpoint: Vector3, _by_player: bool, _struck: Object) -> void:
		pass
	func _group_assault(_id: String, _victim, _at: Vector3, _origin: Vector3) -> void:
		pass
	func _panic_actor(_actor, _origin: Vector3, _mode: String) -> bool:
		return false

var failures := 0
var passes := 0
var world: LevelFixture
var driving: DrivingFixture
var player: PlayerFixture
var combat: CombatProbe
var view: Node3D
var offenses: Array[Dictionary] = []

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	passes += int(ok)
	failures += int(not ok)
	print("[occupant_ballistics] %s %s" % ["PASS" if ok else "FAIL", label])

func frames(count := 2) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func _box(parent: CollisionObject3D, size: Vector3, center: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = center
	parent.add_child(shape)

func _run() -> void:
	G.built = false
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	world = LevelFixture.new()
	add_child(world)
	driving = DrivingFixture.new()
	world.add_child(driving)
	world.driving = driving
	player = PlayerFixture.new()
	world.add_child(player)
	player.collision_layer = 0
	player.collision_mask = 0
	combat = CombatProbe.new()
	world.add_child(combat)
	combat.level = world
	combat.player = player
	combat.player_offense.connect(func(kind: String, at: Vector3, victim_id: String): offenses.append({"kind": kind, "at": at, "id": victim_id}))
	view = Presentation.new()
	world.add_child(view)
	world.vehicle_presentation = view
	view.setup(world)
	for kind in ["hatchback", "box_sedan", "compact"]:
		await _check_car(kind)
	await _check_contacts()
	view.detach()
	world.free()
	print("[occupant_ballistics] %d passed; %d failed" % [passes, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _check_car(kind: String) -> void:
	var car := CarFixture.new()
	world.add_child(car)
	car.prototype_kind = kind
	car.collision_layer = 16
	car.collision_mask = 0
	car.position = Vector3(7, 0, -11)
	car.rotation.y = 0.7
	car.model = Models.make(kind, 3)
	car.add_child(car.model)
	Collision.attach(car, kind)
	driving.vehicle = car
	driving.active = true
	player.global_position = car.global_position
	view.tick(1.0 / 60.0)
	await frames()
	var zones: Array = view.get_occupant_hit_zones(car)
	check(zones.size() == 2 and view.driver.g.visible, "%s uses production posed visible occupant" % kind)
	check(car.model.get_node("Body").mesh != Models.prototype(kind).body, "%s tests genuinely opened occupied mesh, not untouched prototype" % kind)
	if zones.is_empty():
		view.detach()
		car.free()
		return
	var head: Vector3 = zones[0].center
	var local_head := car.to_local(head)
	var from := car.to_global(local_head + Vector3(3, 0, 0))
	var end := head + (head - from).normalized() * 0.5
	var raw: Dictionary = combat._ray(from, end, [])
	check(not raw.is_empty() and raw.collider == car, "%s real collision shell blocks ordinary ray at window" % kind)
	var exposed: Dictionary = combat._trace_bullet(from, from, end, [])
	check(not exposed.hit.is_empty() and exposed.hit.collider == player and exposed.hit.get("occupied_driver", false), "%s opened authored window reaches seated head through actual mesh" % kind)
	var ceiling := head + Vector3.UP * 4.0
	var roof: Dictionary = combat._trace_bullet(ceiling, ceiling, head, [])
	check(not roof.hit.is_empty() and roof.hit.collider == car and not roof.hit.get("occupied_driver", false), "%s closed roof shields seated driver" % kind)
	var low_from := car.to_global(Vector3(3, 0.35, local_head.z))
	var low_to := car.to_global(Vector3(0, 0.35, local_head.z))
	var low: Dictionary = combat._trace_bullet(low_from, low_from, low_to, [])
	check(not low.hit.is_empty() and low.hit.collider == car and not low.hit.get("occupied_driver", false), "%s low chassis remains solid cover" % kind)
	var wall := StaticBody3D.new()
	wall.collision_layer = 2
	wall.collision_mask = 0
	_box(wall, Vector3(0.25, 3, 3), Vector3.ZERO)
	world.add_child(wall)
	wall.global_position = from.lerp(head, 0.40)
	wall.rotation.y = car.rotation.y
	await frames()
	var blocked: Dictionary = combat._trace_bullet(from, from, end, [])
	check(not blocked.hit.is_empty() and blocked.hit.collider == wall, "%s intervening wall wins over virtual occupant" % kind)
	wall.free()
	var other := CarFixture.new()
	other.collision_layer = 16
	other.collision_mask = 0
	_box(other, Vector3(0.25, 3, 3), Vector3.ZERO)
	world.add_child(other)
	other.global_position = from.lerp(head, 0.40)
	other.rotation.y = car.rotation.y
	await frames()
	blocked = combat._trace_bullet(from, from, end, [])
	check(not blocked.hit.is_empty() and blocked.hit.collider == other, "%s other vehicle is never excluded with occupied car" % kind)
	other.free()
	await frames()
	# A real NPC firing call must connect the virtual hit to ordinary player health.
	var shooter := Actor.new()
	world.add_child(shooter)
	shooter.global_position = from - Vector3.UP * 1.25
	shooter.collision_layer = 8
	shooter.collision_mask = 0
	var muzzle := Marker3D.new()
	shooter.add_child(muzzle)
	muzzle.global_position = from
	var accurate_id := ""
	for index in 100:
		var candidate := "occupant_shooter_%d" % index
		if posmod(combat.stable_hash(candidate + ":1"), 1000) < 500:
			accurate_id = candidate
			break
	check(not accurate_id.is_empty(), "deterministic NPC shot fixture has an accurate first shot")
	shooter.actor_id = accurate_id
	combat.health = 100.0
	combat._invulnerable = 0.0
	combat.downed = 0.0
	var before_hits: int = combat.npc_hits
	combat._npc_fire({"actor": shooter, "shots": 0, "muzzle": muzzle, "id": accurate_id}, 3.0)
	check(combat.health < 100.0 and combat.npc_hits == before_hits + 1, "%s production NPC fire injures exposed seated player" % kind)
	var shield := StaticBody3D.new()
	shield.collision_layer = 2
	shield.collision_mask = 0
	_box(shield, Vector3(0.25, 3, 3), Vector3.ZERO)
	world.add_child(shield)
	shield.global_position = from.lerp(head, 0.40)
	shield.rotation.y = car.rotation.y
	await frames()
	combat.health = 100.0
	combat._invulnerable = 0.0
	before_hits = combat.npc_hits
	combat._npc_fire({"actor": shooter, "shots": 0, "muzzle": muzzle, "id": accurate_id}, 3.0)
	check(combat.health == 100.0 and combat.npc_hits == before_hits, "%s same NPC shot cannot injure seated player through wall" % kind)
	shield.free()
	await frames()
	# Barrel guard is still authoritative even if the muzzle can see a window.
	var barrel: Dictionary = combat._trace_bullet(car.to_global(Vector3(0, 0.3, 0)), from, end, [])
	check(barrel.barrel_blocked and barrel.hit.collider == car, "%s blocked barrel cannot skip own collision guard" % kind)
	shooter.free()
	view.detach()
	check(combat._driver_hit(from, end, []).is_empty(), "%s removed presentation removes virtual target" % kind)
	driving.vehicle = null
	driving.active = false
	car.free()
	await frames()

func _check_contacts() -> void:
	var wall := StaticBody3D.new()
	world.add_child(wall)
	wall.collision_layer = 2
	_box(wall, Vector3.ONE, Vector3.ZERO)
	wall.position = Vector3(30, 0, 0)
	combat.health = 100.0
	combat._invulnerable = 0.0
	combat._clock = 20.0
	offenses.clear()
	for speed in [0.0, 2.49, NAN, INF]:
		check(not combat.receive_vehicle_collision({"collider": wall, "relative_speed": speed}) and combat.health == 100.0 and offenses.is_empty(), "nonconsequential/nonfinite speed %s causes no injury or crime" % speed)
	combat.receive_vehicle_collision({"collider": wall, "relative_speed": 12.0})
	var injured := combat.health
	check(injured < 100.0 and offenses.is_empty(), "severe wall crash hurts driver without inventing person/car crime")
	combat._invulnerable = 0.0
	combat.receive_vehicle_collision({"collider": wall, "relative_speed": 12.0})
	check(combat.health == injured and offenses.is_empty(), "same resting contact is deduped independently of player invulnerability")
	combat._clock += 1.1
	combat.receive_vehicle_collision({"collider": wall, "relative_speed": 12.0})
	check(combat.health < injured, "new impact after cooldown can hurt again")
	var victim := Actor.new()
	world.add_child(victim)
	victim.actor_id = "unarmed_contact_neighbor"
	while combat.is_armed_id(victim.actor_id):
		victim.actor_id += "_a"
	victim.position = Vector3(40, 0, 0)
	var impact_at := victim.global_position
	var before_hp: float = combat._wound_hp(victim.actor_id)
	combat._clock += 2.0
	check(combat.receive_vehicle_collision({"collider": victim, "relative_speed": 4.0, "point": impact_at}), "real NPC contact accepted by production damage route")
	var wounded: float = combat._wound_hp(victim.actor_id)
	check(wounded < before_hp and offenses.size() == 1 and offenses[0].kind == "vehicle_assault" and offenses[0].id == victim.actor_id and offenses[0].at == impact_at, "person contact persists health loss and emits exactly one identity/location offense")
	check(not combat.receive_vehicle_collision({"collider": victim, "relative_speed": 4.0, "position": impact_at}) and combat._wound_hp(victim.actor_id) == wounded and offenses.size() == 1, "duplicate person contact cannot duplicate wounds or crimes")
	var other := CarFixture.new()
	world.add_child(other)
	other.collision_layer = 16
	combat._clock += 2.0
	offenses.clear()
	check(not combat.receive_vehicle_collision({"collider": other, "relative_speed": 4.0}) and offenses.is_empty(), "moderate parking contact has no vehicle crime")
	combat._clock += 1.1
	check(combat.receive_vehicle_collision({"collider": other, "relative_speed": 6.0}) and offenses.size() == 1 and offenses[0].kind == "vehicle_collision" and offenses[0].id == other.vehicle_id, "consequential car contact identifies the struck vehicle for witness law")
	combat._clock += 2.0
	offenses.clear()
	check(combat.receive_vehicle_collision({"collider": wall, "kind": "vehicle", "other_vehicle_id": "parked_009", "relative_speed": 6.0}) and offenses.size() == 1 and offenses[0].id == "parked_009", "batch parked collider contact uses event vehicle identity")
	combat.health = 100.0
	combat._invulnerable = 0.0
	combat.receive_traffic_impact(10.0, "patrol")
	check(combat.health < 100.0, "accepted traffic impact damages on-foot player health")
	var traffic_health: float = combat.health
	combat.receive_traffic_impact(10.0, "patrol")
	check(combat.health == traffic_health, "traffic injury shares combat invulnerability window")
	wall.free()
	victim.free()
	other.free()
