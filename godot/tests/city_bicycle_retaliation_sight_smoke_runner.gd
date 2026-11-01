extends Node3D
## Actual physics rays against the production bicycle's hull dimensions.
## No combat ticks, damage, rider movement, profile writes or synthetic hits.
const Combat := preload("res://scripts/city/city_combat.gd")
const Bicycle := preload("res://scripts/city/city_bicycle.gd")
var failures := 0

class TestPlayer extends CharacterBody3D:
	var seated_vehicle: Node3D

class TestDriving extends Node:
	var active := false
	var vehicle: CollisionObject3D

class TestLevel extends Node3D:
	var player: CharacterBody3D
	var bicycle: CharacterBody3D
	var driving: Node
	var vehicle_presentation: Node = null

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	failures += int(not ok)
	print("[bicycle_retaliation_sight] %s %s" % ["PASS" if ok else "FAIL", label])

func settle() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame

func box_body(parent: Node, at: Vector3, size: Vector3, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	body.position = at
	return body

func _run() -> void:
	var level := TestLevel.new()
	add_child(level)
	var player := TestPlayer.new()
	level.add_child(player)
	level.player = player
	player.collision_layer = 0 # Production enter_vehicle disables the walking body.
	player.collision_mask = 0
	var bicycle := Bicycle.new()
	level.add_child(bicycle)
	level.bicycle = bicycle
	bicycle.collision_layer = 16
	bicycle.collision_mask = 0
	bicycle.active = true
	# Use the actual bicycle script and its exact three-capsule hull dimensions,
	# without building presentation, parking searches or the unrelated crash rig.
	for z in [-0.52, 0.0, 0.52]:
		var collision := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = Bicycle.HULL_RADIUS
		capsule.height = Bicycle.HULL_TOP - Bicycle.HULL_CLEARANCE
		collision.shape = capsule
		collision.position = Vector3(0, Bicycle.HULL_CLEARANCE + capsule.height * .5, z)
		bicycle.add_child(collision)
	player.seated_vehicle = bicycle
	var driving := TestDriving.new()
	level.add_child(driving)
	level.driving = driving
	var combat := Combat.new()
	level.add_child(combat)
	combat.level = level
	combat.player = player
	var attacker := box_body(level, Vector3(-2, 1.0, 0), Vector3(.4, 1.8, .4), 8)
	var eye := Vector3(-2, 1.3, 0)
	var chest := player.global_position + Vector3.UP * 1.1
	var health_before: float = combat.health
	await settle()
	var exclusions: Array[RID] = [attacker.get_rid()]
	var hit: Dictionary = combat._ray(eye, chest, exclusions)
	check(not hit.is_empty() and hit.collider == bicycle, "real rider chest ray first hits occupied bicycle hull")
	check(combat._sight(eye, chest, attacker, player), "occupied bicycle hull permits sight to its rider")
	bicycle.active = false
	check(not combat._sight(eye, chest, attacker, player), "inactive parked bicycle does not become a player sight target")
	bicycle.active = true
	player.seated_vehicle = null
	check(not combat._sight(eye, chest, attacker, player), "active bicycle is insufficient when player is not its rider")
	player.seated_vehicle = bicycle
	var cover := box_body(level, Vector3(-1, 1.1, 0), Vector3(.2, 2.0, 2.0), 2)
	await settle()
	check(not combat._sight(eye, chest, attacker, player), "wall before occupied bicycle still blocks rider sight")
	cover.collision_layer = 16
	await settle()
	check(not combat._sight(eye, chest, attacker, player), "unrelated vehicle before occupied bicycle still blocks rider sight")
	cover.collision_layer = 1
	await settle()
	check(not combat._sight(eye, chest, attacker, player), "terrain before occupied bicycle still blocks rider sight")
	cover.collision_layer = 0
	await settle()
	check(combat._sight(eye, chest, attacker, player), "rider sight returns when external cover leaves")
	var other := box_body(level, Vector3(0, 1.1, 0), Vector3(.1, .1, .1), 0)
	check(not combat._sight(eye, chest, attacker, other), "occupied bicycle exception applies only to the player target")
	# A driving manager claim retains the existing car-ballistics gate; absent
	# verified cabin hit geometry must not fall through to the bicycle exception.
	driving.vehicle = cover
	driving.active = true
	check(not combat._sight(eye, chest, attacker, player), "occupied-car ballistic branch keeps priority over bicycle sight")
	driving.active = false
	check(combat.health == health_before and combat._active.is_empty(), "sight queries alone never change health or start retaliation")
	get_tree().quit(0 if failures == 0 else 1)
