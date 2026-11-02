extends SceneTree
## Run headless with --path godot --script res://tests/city_commerce_smoke.gd.
## Tests actual progression transactions, save validation, shop UI and service
## window coordinates without loading the full district.
const Progression := preload("res://scripts/city/city_progression.gd")
const Catalog := preload("res://scripts/city/city_shop_catalog.gd")
const Shops := preload("res://scripts/city/city_shops.gd")
const CivicBuilding := preload("res://scripts/city/city_civic_businesses.gd")
const Bindings := preload("res://scripts/city/city_input_bindings.gd")

class CommerceHealth extends Node:
	var refuse_healing := false
	var health := 100.0:
		set(value):
			if not refuse_healing or value <= health:
				health = value
	var downed := 0.0
	var aggro := 0
	var _active := {}
	func get_status() -> Dictionary:
		return {"aggro_count": aggro}

class CommerceGate extends Node:
	var active := false
	var recovering := false
	var wanted := 0
	var open := true
	func is_open() -> bool:
		return open

class CommercePlayer extends Node3D:
	var phone: Node

class CommerceWorld extends Node3D:
	var progression: Node
	var combat: Node
	var shops: Node
	var law: Node
	var driving: Node
	var bicycle: Node
	var world_time: Node
	var missions: Node
	var inspector: Node
	var player: Node3D
	var paused := false

class CommerceDistrict extends Node3D:
	var businesses: Array = []
	var map_pois: Array = []

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("[commerce] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1

func fixture() -> CommerceWorld:
	var world := CommerceWorld.new()
	root.add_child(world)
	world.combat = CommerceHealth.new()
	world.law = CommerceGate.new()
	world.driving = CommerceGate.new()
	world.bicycle = CommerceGate.new()
	world.shops = CommerceGate.new()
	world.player = CommercePlayer.new()
	world.progression = Progression.new()
	for node in [world.combat, world.law, world.driving, world.bicycle, world.shops, world.player, world.progression]:
		world.add_child(node)
	world.progression.setup(world)
	return world

func _run() -> void:
	var world := fixture()
	var p: Node = world.progression
	check(p.enabled and p.config_errors.is_empty(), "shipped config plus reusable catalog validates")
	check(p.catalog(Catalog.SHOP_KIND).size() == 6 and p.catalog("gun").is_empty(), "six useful goods; gun store remains closed")
	var untouched: Dictionary = p.snapshot_state()
	check(not p.purchase("bike_teal", {"shop_kind": "weed"}).ok and p.snapshot_state() == untouched, "wrong shop context is atomic")
	p.money = 2
	untouched = p.snapshot_state()
	check(not p.purchase("bike_teal").ok and p.snapshot_state() == untouched, "insufficient funds changes no account state")
	p.money = 500
	var result: Dictionary = p.purchase("bike_teal")
	check(result.ok and result.price == 45 and p.money == 455 and p.item_count("bike_teal") == 1 and p.equipped_shop_color("bike_color") == "238f91", "purchase debits once and equips durable bike color")
	untouched = p.snapshot_state()
	check(not p.purchase("bike_teal").ok and p.snapshot_state() == untouched, "equipped item double-click never charges")
	check(p.purchase("bike_sunshine").ok and p.purchase("bike_teal").price == 0 and p.money == 410, "owned bike colors switch free")
	check(p.purchase("bandana_ocean").ok and p.equipped_shop_item("bandana_color") == "bandana_ocean", "clothing has an independent equipped slot")
	check(not p.remove_item("bandana_ocean"), "owned clothing cannot be consumed")
	var saved: Dictionary = p.snapshot_state()
	check(p.validate_state(saved).is_empty(), "commerce snapshot passes strict existing schema")
	var other := fixture()
	check(other.progression.restore_state(saved) and other.progression.equipped_shop_item("bike_color") == "bike_teal" and other.progression.equipped_shop_item("bandana_color") == "bandana_ocean" and other.progression.money == p.money, "save restore preserves wallet ownership and both equipped selections")
	var corrupt := saved.duplicate(true)
	corrupt.flags.append("shop_equipped_bike_sunshine")
	check(not p.validate_state(corrupt).is_empty(), "save rejects two colors in one slot")
	corrupt = saved.duplicate(true)
	corrupt.items.bandana_ocean = 0
	check(not p.validate_state(corrupt).is_empty(), "save rejects equipped unowned clothing")
	corrupt = saved.duplicate(true)
	corrupt.flags.append("shop_equipped_unknown")
	check(not p.restore_state(corrupt) and p.snapshot_state() == saved, "unknown appearance restoration fails atomically")
	# A pre-commerce snapshot has no new item keys or selected flags. It still
	# restores unchanged wallet/history, with default appearance.
	var legacy := saved.duplicate(true)
	for id in Catalog.item_ids():
		legacy.items.erase(id)
		legacy.purchases.erase(id)
	legacy.flags = []
	check(other.progression.restore_state(legacy) and other.progression.equipped_shop_color("bandana_color").is_empty(), "pre-commerce snapshot restores default appearance")
	for index in int(other.progression.config.limits.flags):
		other.progression.flags["fixture_flag_%d" % index] = true
	var full_flags: Dictionary = other.progression.snapshot_state()
	check(not other.progression.purchase("bandana_clay").ok and other.progression.snapshot_state() == full_flags, "full flag table rejects new appearance atomically")

	world.combat.health = 73.0
	var balance := int(p.money)
	result = p.purchase("snack_granola")
	check(result.ok and world.combat.health == 93.0 and p.money == balance - 6 and p.item_count("snack_granola") == 0, "snack is used immediately for useful recovery")
	result = p.purchase("drink_water")
	check(result.ok and world.combat.health == 100.0 and result.recovered == 7.0, "drink recovery clamps to existing health maximum")
	untouched = p.snapshot_state()
	check(not p.purchase("drink_water").ok and p.snapshot_state() == untouched, "full health blocks wasteful purchase")
	world.combat.health = 40.0
	world.combat.downed = 1.0
	check(not p.purchase("snack_granola").ok and world.combat.health == 40.0 and p.snapshot_state() == untouched, "food cannot bypass knockdown")
	world.combat.downed = 0.0
	world.law.recovering = true
	check(not p.purchase("snack_granola").ok and p.snapshot_state() == untouched, "food cannot bypass law recovery")
	world.law.recovering = false
	world.combat.aggro = 1
	check(not p.purchase("snack_granola").ok and p.snapshot_state() == untouched, "active confrontation blocks food")
	world.combat.aggro = 0
	world.combat.refuse_healing = true
	check(not p.purchase("snack_granola").ok and world.combat.health == 40.0 and p.snapshot_state() == untouched, "failed health effect never charges or records purchase")
	world.combat.refuse_healing = false
	world.combat.health = 0.0
	check(not p.purchase("snack_granola").ok and p.snapshot_state() == untouched, "food cannot revive a player")
	world.combat.health = NAN
	check(not p.purchase("snack_granola").ok and p.snapshot_state() == untouched, "invalid health is never charged")
	world.combat.health = 100.0
	world.shops.open = false
	check(not p.purchase("bandana_clay").ok and p.snapshot_state() == untouched, "closed shop gates cosmetics too")
	_test_window(world)
	world.free()
	other.free()
	print("[commerce] failures=%d" % failures)
	quit(1 if failures else 0)

func _test_window(world: CommerceWorld) -> void:
	world.shops.free()
	var shops := Shops.new()
	world.shops = shops
	world.add_child(shops)
	var district := CommerceDistrict.new()
	world.add_child(district)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/pen_lucy_new_businesses.json"))
	for entry in data.businesses:
		if str(entry.id) == Catalog.SHOP_ID:
			district.businesses.append(entry)
			district.map_pois.append({"id": entry.id, "label": entry.label, "position": Vector3.ZERO, "service": entry.service})
	check(not shops.register_corner_store(district), "missing physical storefront cannot advertise a service window")
	var civic := CivicBuilding.build(district.businesses[0])
	district.add_child(civic)
	check(shops.register_corner_store(district) and shops.register_corner_store(district) and shops.models.size() == 1 and district.map_pois.size() == 1, "existing storefront gets one counter and keeps one map identity")
	shops.setup(world)
	var model: Node3D = shops.models[Catalog.SHOP_ID]
	var target: Vector3 = model.get_meta("counter_local")
	world.player.global_position = model.to_global(target)
	check(shops.counter_at(world.player.global_position) == Catalog.SHOP_ID, "front-of-window position reaches pantry counter")
	check(shops.counter_at(model.to_global(Vector3(target.x, target.y, 0))).is_empty(), "no counter activation through solid storefront")
	check(shops.counter_at(model.to_global(target + Vector3.UP * 5)).is_empty(), "no counter activation from roof")
	check(shops.walkable_floor_at(world.player.global_position).is_empty(), "service window does not create an interior checkpoint exemption")
	world.bicycle.active = true
	check(not shops.open_shop(Catalog.SHOP_ID), "dismount before using the pantry counter")
	world.bicycle.active = false
	check(shops.open_shop(Catalog.SHOP_ID), "real shop UI opens from pantry frontage")
	check(shops.stock_rows.get_node("Buy_bike_sunshine").text.contains("Equip") and not shops.stock_rows.get_node("Buy_bike_sunshine").disabled, "owned alternate color offers free equip")
	check(shops.stock_rows.get_node("Buy_drink_water").disabled and shops.stock_rows.get_node("Buy_drink_water").text.contains("full health"), "food UI explains full-health restriction")
	var before := int(world.progression.money)
	check(shops.purchase("bike_sunshine").ok and world.progression.money == before, "counter routes free owned-color equip through progression")
	check(not shops.purchase("cannabis").ok and world.progression.money == before, "pantry rejects stock from another shop")
	shops.close()
	_test_rebinding(shops, model)

func _test_rebinding(shops: Node3D, model: Node3D) -> void:
	Bindings.ensure()
	var previous: Dictionary = Bindings.bindings.duplicate()
	Bindings.bindings = Bindings.DEFAULTS.duplicate()
	Bindings.apply()
	var path := "res://../.work/next-five-20261101/commerce-controls.cfg"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	check(Bindings.rebind("city_interact", KEY_G, path).is_empty(), "interaction rebind uses isolated project controls fixture")
	var old_key := InputEventKey.new()
	old_key.keycode = KEY_E
	old_key.physical_keycode = KEY_E
	old_key.pressed = true
	check(not shops.handle_input(old_key) and not shops.is_open(), "old E no longer opens shop after interaction remap")
	shops.tick(1.0)
	var prompt: Label3D = model.get_node("ShopInteractionLabel")
	check(shops.hint.text.begins_with("G · ") and prompt.text == "PANTRY COUNTER · G", "proximity hint and physical counter instructions update to remapped key")
	var rebound := InputEventKey.new()
	# Physical binding must win over an unrelated logical keyboard layout key.
	rebound.keycode = KEY_E
	rebound.physical_keycode = KEY_G
	rebound.pressed = true
	rebound.echo = true
	check(not shops.handle_input(rebound) and not shops.is_open(), "repeat events cannot open remapped shop")
	rebound.echo = false
	var modal_events: Array = []
	var observer := func(open: bool): modal_events.append(open)
	shops.modal_changed.connect(observer)
	check(shops.handle_input(rebound) and shops.is_open(), "new physical interaction key opens actual shop panel")
	shops.handle_input(rebound)
	check(modal_events == [true], "one opening emits one modal transition; modal absorbs repeated interaction")
	shops.close()
	shops.modal_changed.disconnect(observer)
	Bindings.bindings = previous
	Bindings.apply()
	shops.tick(1.0)
