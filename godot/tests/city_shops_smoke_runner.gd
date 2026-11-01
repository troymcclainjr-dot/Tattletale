extends Node
const Shops := preload("res://scripts/city/city_shops.gd")
const District := preload("res://scripts/city/city_civic_district.gd")
class ShopWorld extends Node3D:
	var player: Node3D
	var progression: Node
	var combat: Node
	var driving: Node
	var law: Node
	var inspector: Node
	var paused := false
	var level_data := {"businesses": [], "rear_doors": [], "porch_stairs": [], "facade_details": [], "dressing": []}
class ShopPlayer extends Node3D:
	var phone: Node
class BusyState extends Node:
	var active := false
	var recovering := false
	var health := 100.0
	var downed := 0.0
	var _active: Dictionary = {}
class ShopEconomy extends Node:
	var money := 2000
	var transactions: Array[String] = []
	var owned: Array[String] = []
	var catalog_override: Array = []
	func catalog(kind: String) -> Array:
		if not catalog_override.is_empty():
			return catalog_override
		if kind == "weed":
			return [{"id": "cannabis", "label": "Sealed cannabis", "price": 40, "repeatable": true}]
		var items: Array = []
		for weapon in ["pistol", "uzi", "ak47"]:
			items.append({"id": weapon, "label": weapon.to_upper(), "price": 500, "owned": weapon in owned})
			items.append({"id": "ammo_" + weapon, "label": weapon.to_upper() + " ammunition", "price": 50, "repeatable": true})
		return items
	func purchase(identity: String) -> Dictionary:
		var price := 40 if identity == "cannabis" else (50 if identity.begins_with("ammo_") else 500)
		if price > money or identity in owned:
			return {"ok": false, "message": "Unavailable"}
		money -= price
		transactions.append(identity)
		if not identity.begins_with("ammo_") and identity != "cannabis":
			owned.append(identity)
		return {"ok": true, "message": "Purchased " + identity}
class ClerkEconomy extends ShopEconomy:
	func perception_line(role: String) -> String:
		return "Known around here. Your reputation affects the quoted prices." if role == "clerk" else ""
var shops: Node3D
var world: ShopWorld
var failures := 0
var finished := false

func _ready() -> void:
	_run.call_deferred()
	_watchdog()
func _watchdog() -> void:
	await get_tree().create_timer(75.0, true, false, true).timeout
	if not finished:
		check(false, "watchdog")
		_finish()
func check(ok: bool, label: String) -> void:
	print("[shops] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1
func _input(event: InputEvent) -> void:
	if shops != null and shops.ui != null:
		shops.handle_input(event)
func key(code: int) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame
func click(button: Button) -> void:
	var viewport := button.get_viewport()
	var at: Vector2 = button.get_global_transform_with_canvas() * (button.size * 0.5)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = at
		event.global_position = at
		event.pressed = pressed
		viewport.push_input(event, true)
		await get_tree().process_frame

func _run() -> void:
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	world = ShopWorld.new()
	add_child(world)
	world.player = ShopPlayer.new()
	world.add_child(world.player)
	world.progression = ShopEconomy.new()
	world.add_child(world.progression)
	shops = Shops.new()
	world.add_child(shops)
	shops._load_definitions()
	var source := Node3D.new()
	world.add_child(source)
	var district := District.new()
	world.add_child(district)
	district.level = world
	for entry in shops.definitions:
		var old := Node3D.new()
		old.name = str(entry.source_mesh)
		source.add_child(old)
		district.map_buildings.append({"id": entry.building_ids[0], "polygon": entry.foundation_polygon})
		world.level_data.businesses.append({"building_id": entry.building_ids[0]})
	world.level_data.businesses.append({"building_id": "retain_neighbor"})
	var applied: Dictionary = shops.apply_before_collision(source, district)
	check(applied.ok and applied.shops == 5 and source.get_child_count() == 0, "five original footprints atomically replaced before collision")
	check(shops.apply_before_collision(source, district).ok and shops.models.size() == 5, "pre-collision application is idempotent")
	check(district.removed_building_ids.size() == 5 and world.level_data.businesses == [{"building_id": "retain_neighbor"}], "removed source metadata filtered while neighboring data retained")
	check(district.map_buildings.size() == 5 and district.map_pois.size() == 5, "authoritative map footprints and service POIs registered")
	var counts := {"west": 0, "east": 0, "weed": 0}
	for entry in shops.definitions:
		if entry.kind == "gun":
			counts[str(entry.side)] += 1
		else:
			counts.weed += 1
	check(counts == {"west": 2, "east": 2, "weed": 1}, "two gun stores on each map side and one cannabis shop")
	shops.setup(world)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := world.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.75
	for entry in shops.definitions:
		var model: Node3D = shops.models[str(entry.id)]
		var open_door := ray(space, model.to_global(Vector3(0, 1.0, float(entry.depth) * 0.5 + 0.5)), model.to_global(Vector3(0, 1.0, float(entry.depth) * 0.5 - 1.0))).is_empty()
		var solid_wall := not ray(space, model.to_global(Vector3(float(entry.width) * 0.5 - 0.6, 1, 0)), model.to_global(Vector3(float(entry.width) * 0.5 + 0.6, 1, 0))).is_empty()
		check(open_door and solid_wall, str(entry.id) + " actual doorway is open and wall is collidable")
		var counter: Vector3 = model.get_meta("counter_local")
		var floor_hit := ray(space, model.to_global(counter + Vector3.UP), model.to_global(counter - Vector3.UP))
		check(not floor_hit.is_empty() and absf(floor_hit.position.y - model.position.y) < 0.03, str(entry.id) + " counter frontage has physical interior floor")
		var start: Vector3 = Shops.Building.point(entry.approach_start)
		var door: Vector3 = Shops.Building.point(entry.entry_world)
		var end := model.to_global(counter)
		var support: Dictionary = shops.walkable_floor_at(end + Vector3.UP * 0.05)
		check(not support.is_empty() and support.position.distance_to(end) < 0.025 and support.normal.dot(Vector3.UP) > 0.99,
			str(entry.id) + " checkpoint query accepts exact physical interior floor")
		check(shops.walkable_floor_at(end + Vector3.UP * 3.5).is_empty(), str(entry.id) + " checkpoint query rejects roof height")
		var counter_center := Vector3(0, 0.05, -float(entry.depth) * 0.22)
		check(shops.walkable_floor_at(model.to_global(counter_center)).is_empty() and shops.walkable_floor_at(model.to_global(counter_center + Vector3.UP)).is_empty(),
			str(entry.id) + " checkpoint query rejects counter volume and counter top")
		var shelf_base := Vector3(float(entry.width) * 0.5 - 0.52, 0.05, -float(entry.depth) * 0.04)
		check(shops.walkable_floor_at(model.to_global(shelf_base)).is_empty(), str(entry.id) + " checkpoint query rejects shelf footprint")
		check(shops.walkable_floor_at(model.to_global(Vector3(float(entry.width), 0.05, 0))).is_empty(), str(entry.id) + " checkpoint query rejects outside footprint")
		check(shops.walkable_floor_at(end - Vector3.UP * 0.5).is_empty() and shops.walkable_floor_at(end + Vector3.UP * 0.5).is_empty(),
			str(entry.id) + " checkpoint query rejects mismatched height above/below floor")
		var walkable := true
		for route in [[start, door], [door, end]]:
			for step in range(1, 30):
				var at: Vector3 = route[0].lerp(route[1], float(step) / 30.0)
				var query := PhysicsShapeQueryParameters3D.new()
				query.shape = capsule
				query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * 0.94)
				query.collision_mask = 2
				query.margin = 0.0
				var contacts := space.intersect_shape(query, 1)
				if not contacts.is_empty() and walkable:
					print("[shops] corridor collision ", entry.id, " at ", at, " body=", contacts[0].collider.name, " shape=", contacts[0].shape)
				walkable = walkable and contacts.is_empty()
		check(walkable, str(entry.id) + " full-height player capsule fits surveyed ramp, doorway and counter route")
		world.player.global_position = end + Vector3.UP * 0.03
		check(shops.counter_at(world.player.global_position) == str(entry.id), str(entry.id) + " interior counter interaction resolves")
		world.player.global_position = model.to_global(Vector3(float(entry.width), 0, counter.z))
		check(shops.counter_at(world.player.global_position).is_empty(), str(entry.id) + " counter cannot be used through side wall")
	var first: Dictionary = shops.definitions[0]
	var first_model: Node3D = shops.models[str(first.id)]
	world.player.global_position = first_model.to_global(first_model.get_meta("counter_local")) + Vector3.UP * 0.03
	var busy := BusyState.new()
	world.add_child(busy)
	world.paused = true
	check(not shops.open_shop(str(first.id)), "direct opening rejects paused menus")
	world.paused = false
	busy.active = true
	world.driving = busy
	check(not shops.open_shop(str(first.id)), "direct opening rejects driving")
	world.driving = null
	world.player.phone = busy
	check(not shops.open_shop(str(first.id)), "direct opening rejects active phone")
	world.player.phone = null
	world.inspector = busy
	check(not shops.open_shop(str(first.id)), "direct opening rejects inspector")
	world.inspector = null
	busy.recovering = true
	world.law = busy
	check(not shops.open_shop(str(first.id)), "direct opening rejects law recovery")
	world.law = null
	world.combat = busy
	busy.downed = 1.0
	check(not shops.open_shop(str(first.id)), "direct opening rejects downed player")
	busy.downed = 0.0
	busy._active = {"fighter": {}}
	check(not shops.open_shop(str(first.id)), "direct opening rejects ongoing confrontation")
	world.combat = null
	shops.tick(0.2)
	world.paused = true
	shops._process(0.01)
	check(not shops.hint.visible, "prompt hides while map/menu pauses gameplay ticks")
	world.paused = false
	await key(KEY_E)
	check(shops.is_open() and shops.active_id == first.id, "actual E input opens shop inside at counter")
	check(not shops.clerk.visible, "fixture economy without perception API keeps clerk line hidden")
	# Root freezes the world for this modal; its own pause must not block buying.
	world.paused = true
	await get_tree().process_frame
	await click(shops.stock_rows.get_node("Buy_pistol"))
	check(world.progression.money == 1500 and world.progression.transactions == ["pistol"], "actual purchase button delegates one paid weapon transaction")
	await click(shops.stock_rows.get_node("Buy_ammo_pistol"))
	await click(shops.stock_rows.get_node("Buy_ammo_pistol"))
	check(world.progression.money == 1400 and world.progression.transactions.count("ammo_pistol") == 2, "ammunition remains repeatably purchasable through UI")
	check(not shops.purchase("cannabis").ok and world.progression.money == 1400, "gun shop rejects unstocked item without spending")
	world.progression.catalog_override = [
		{"id": "uzi", "label": "Uzi", "price": 500, "available": false, "locked": true, "reason": "Requires Gangsta 10."},
		{"id": "ammo_ak47", "label": "AK47 ammunition", "price": 50, "repeatable": true, "available": false, "reason": "Buy the AK47 first."},
		{"id": "pistol", "label": "Pistol", "price": 500, "owned": true},
		{"id": "ammo_pistol", "label": "Pistol ammunition", "price": 2000, "repeatable": true, "available": true}]
	shops._refresh_catalog()
	check(shops.stock_rows.get_node("Buy_uzi").disabled and shops.stock_rows.get_node("Buy_uzi").text.contains("Requires Gangsta 10."), "locked stock shows the catalog's actual requirement")
	check(shops.stock_rows.get_node("Buy_ammo_ak47").disabled and shops.stock_rows.get_node("Buy_ammo_ak47").text.contains("Buy the AK47 first."), "unavailable ammunition shows actual prerequisite instead of Buy action")
	check(shops.stock_rows.get_node("Buy_pistol").text.ends_with("Owned"), "owned weapon retains Owned status")
	check(shops.stock_rows.get_node("Buy_ammo_pistol").text.contains("Need $600 more"), "available stock shows meaningful money deficit")
	world.progression.catalog_override.clear()
	var original_economy: Node = world.progression
	var clerk_economy := ClerkEconomy.new()
	world.add_child(clerk_economy)
	clerk_economy.money = world.progression.money
	world.progression = clerk_economy
	shops._refresh_catalog()
	check(shops.clerk.visible and shops.clerk.text == clerk_economy.perception_line("clerk"), "production clerk-perception API is shown verbatim")
	world.progression = original_economy
	clerk_economy.queue_free()
	world.progression.money = 0
	shops._refresh_catalog()
	check(shops.stock_rows.get_node("Buy_uzi").disabled and shops.wallet.text.contains("$0"), "UI shows current funds and disables unaffordable stock")
	var close_button: Button = shops.card.find_child("LeaveShop", true, false)
	check(close_button.get_global_rect().end.y <= shops.ui.size.y, "close action remains inside viewport beneath scrollable catalog")
	await key(KEY_ESCAPE)
	check(not shops.is_open(), "actual Escape input closes shop")
	world.paused = false
	world.progression.money = 100
	var weed: Dictionary = shops.definitions[4]
	var weed_model: Node3D = shops.models[str(weed.id)]
	world.player.global_position = weed_model.to_global(weed_model.get_meta("counter_local")) + Vector3.UP * 0.03
	await key(KEY_E)
	await click(shops.stock_rows.get_node("Buy_cannabis"))
	check(world.progression.money == 60 and world.progression.transactions[-1] == "cannabis", "weed shop delegates sealed fictional inventory purchase")
	world.player.global_position += Vector3(100, 0, 0)
	check(not shops.purchase("cannabis").ok and not shops.is_open(), "leaving counter cancels modal and blocks remote purchases")
	world.queue_free()
	_finish()

func ray(space: PhysicsDirectSpaceState3D, start: Vector3, end: Vector3) -> Dictionary:
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(start, end, 2))
func _finish() -> void:
	if finished:
		return
	finished = true
	print("[shops] failures=", failures)
	get_tree().quit(1 if failures else 0)
