extends Node3D
## Five walk-in shells plus a civic pantry service window share one purchase
## panel. Progression alone owns money, ownership, effects and saved selections.
## Shops whose kind city_play_mode.gd closes (gun stores while PLAYER_COMBAT is
## off) are still built in full but shuttered: no counter, prompt, interior
## checkpoint floor, purchase or map advertisement. Their map footprint stays.
const PlayMode := preload("res://scripts/city/city_play_mode.gd")
const Building := preload("res://scripts/city/city_shop_building.gd")
const Catalog := preload("res://scripts/city/city_shop_catalog.gd")
const Bindings := preload("res://scripts/city/city_input_bindings.gd")
const C := preload("res://scripts/city/city_theme.gd")
const T := C.T
const DATA := "res://assets/data/pen_lucy_shops.json"
signal modal_changed(open: bool)
var level: Node3D
var definitions: Array = []
var models: Dictionary = {}
var applied := false
var nearby_id := ""
var active_id := ""
var last_message := ""
var ui: Control
var hint: Label
var card: PanelContainer
var title: Label
var wallet: Label
var clerk: Label
var message: Label
var stock_rows: VBoxContainer
var _refresh_time := 0.0
var _previous_mouse_mode := Input.MOUSE_MODE_CAPTURED
var _removed: Array[String] = []
var _interaction_label := ""

func _load_definitions() -> void:
	if definitions.is_empty():
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA))
		definitions = data.shops

## Call once AFTER civic.setup and BEFORE vegetation/collision/optimizer setup.
## The district remains the single reservation source used by all providers.
func apply_before_collision(city: Node3D, district: Node3D) -> Dictionary:
	if applied:
		return {"ok": true, "removed": _removed.duplicate(), "shops": models.size()}
	_load_definitions()
	# Validate all removals before changing any source mesh.
	for entry in definitions:
		if city.find_child(str(entry.source_mesh), true, false) == null:
			return {"ok": false, "message": "Shop source mesh missing: " + str(entry.source_mesh)}
	for entry in definitions:
		var source := city.find_child(str(entry.source_mesh), true, false)
		source.get_parent().remove_child(source)
		source.free()
		_removed.append(str(entry.source_mesh))
		if not str(entry.source_mesh) in district.removed_meshes:
			district.removed_meshes.append(str(entry.source_mesh))
		for identity in entry.building_ids:
			if not str(identity) in district.removed_building_ids:
				district.removed_building_ids.append(str(identity))
		district._region(entry.clearance_polygon)
		var kept: Array[Dictionary] = []
		for footprint in district.map_buildings:
			if not str(footprint.id) in entry.building_ids:
				kept.append(footprint)
		district.map_buildings = kept
		district.map_buildings.append({"id": entry.id, "polygon": entry.polygon})
		if is_entry_open(entry):
			district.map_pois.append(_poi(entry))
		var model := Building.build(entry)
		add_child(model)
		models[str(entry.id)] = model
		add_child(Building.approach(entry))
	district._filter_level_metadata()
	register_corner_store(district)
	applied = true
	return {"ok": true, "removed": _removed.duplicate(), "shops": models.size()}

## Reuse the civic pantry and its map identity, without replacing another
## building or publishing duplicate POIs. Called before collision setup.
func register_corner_store(district: Node3D) -> bool:
	if models.has(Catalog.SHOP_ID):
		return true
	var businesses: Variant = district.get("businesses")
	if not businesses is Array:
		return false
	for source in businesses:
		if str(source.get("id", "")) != Catalog.SHOP_ID or str(source.get("service", "")) != Catalog.SHOP_KIND:
			continue
		# Only advertise a counter when the actual civic storefront was built.
		if district.get_node_or_null(NodePath(Catalog.SHOP_ID)) == null:
			return false
		var entry: Dictionary = source.duplicate(true)
		entry.kind = Catalog.SHOP_KIND
		entry.service_window = true
		var model := Building.service_window(entry)
		# Keep the exact supporting civic body, not a layer-wide exemption.
		model.set_meta("foundation_body", district.get_node(NodePath(Catalog.SHOP_ID)).get_node_or_null("SolidArchitecture"))
		add_child(model)
		models[Catalog.SHOP_ID] = model
		var target := model.to_global(model.get_meta("counter_local"))
		entry.entry_world = [target.x, target.y, target.z]
		definitions.append(entry)
		for poi in district.map_pois:
			if str(poi.get("id", "")) == Catalog.SHOP_ID:
				poi.position = target
				poi.label = str(entry.label) + " · Shop"
		return true
	return false

func setup(owner_level: Node3D) -> void:
	level = owner_level
	_load_definitions()
	name = "WalkInShops"
	if ui == null:
		_build_ui()

func tick(delta: float) -> void:
	_refresh_time -= delta
	if _refresh_time > 0.0 or level == null:
		return
	_refresh_time = 0.15
	_refresh_interaction_labels()
	var player: Node3D = level.get("player")
	nearby_id = counter_at(player.global_position) if is_instance_valid(player) and _blocked_reason(is_open()).is_empty() else ""
	if is_open() and nearby_id != active_id:
		close()
	if hint != null:
		hint.visible = not nearby_id.is_empty() and not is_open()
		if hint.visible:
			hint.text = Bindings.label("city_interact") + " · " + str(_entry(nearby_id).label)

func _refresh_interaction_labels() -> void:
	var current := Bindings.label("city_interact")
	if current == _interaction_label:
		return
	_interaction_label = current
	for model in models.values():
		var prompt: Label3D = model.get_node_or_null("ShopInteractionLabel")
		if prompt != null:
			prompt.text = str(prompt.get_meta("shop_prompt_format", "%s · Shop")) % current

func _process(_delta: float) -> void:
	# Gameplay tick stops during map/settings/inspector. Hide an already-visible
	# prompt immediately without running proximity or stock work while paused.
	if hint != null and hint.visible and level != null:
		var inspector: Node = level.get("inspector")
		if level.get("paused") == true or (inspector != null and inspector.get("active") == true):
			hint.hide()

func _blocked_reason(own_modal := false) -> String:
	if level == null:
		return "Shop unavailable."
	if not own_modal and level.get("paused") == true:
		return "Close the current menu first."
	var inspector: Node = level.get("inspector")
	if inspector != null and inspector.get("active") == true:
		return "Leave the inspector first."
	var driving: Node = level.get("driving")
	if driving != null and driving.get("active") == true:
		return "Leave the vehicle first."
	var bicycle: Node = level.get("bicycle")
	if bicycle != null and bicycle.get("active") == true:
		return "Step off your bicycle first."
	var law: Node = level.get("law")
	if law != null and law.get("recovering") == true:
		return "Recovery is in progress."
	var player: Node = level.get("player")
	if player != null:
		var phone: Node = player.get("phone")
		if phone != null and phone.get("active") == true:
			return "Put away the phone first."
	var combat: Node = level.get("combat")
	if combat != null:
		var health: Variant = combat.get("health")
		var downed: Variant = combat.get("downed")
		var fighters: Variant = combat.get("_active")
		if (health != null and float(health) <= 0.0) or (downed != null and float(downed) > 0.0):
			return "Recover before shopping."
		if fighters is Dictionary and not fighters.is_empty():
			return "Finish the confrontation before shopping."
	return ""

func counter_at(world_position: Vector3) -> String:
	for identity in models:
		var model: Node3D = models[identity]
		var local := model.to_local(world_position)
		var entry := _entry(str(identity))
		if not is_entry_open(entry):
			continue
		if bool(entry.get("service_window", false)):
			var target: Vector3 = model.get_meta("counter_local")
			var front := float(entry.depth) * 0.5
			# Customer must stand outside the facade, near this window, at ground
			# height. No activation from inside the solid hull or on its roof.
			if local.z > front + 0.5 and local.z < front + 2.5 and absf(local.x - target.x) < 1.4 and absf(local.y - target.y) < 1.2:
				return str(identity)
			continue
		if absf(local.x) >= float(entry.width) * 0.5 - 0.25 or absf(local.z) >= float(entry.depth) * 0.5 - 0.25 or local.y < -0.15 or local.y > 2.2:
			continue
		var counter: Vector3 = model.get_meta("counter_local")
		if Vector2(local.x - counter.x, local.z - counter.z).length() <= 1.65:
			return str(identity)
	return ""

## Narrow checkpoint support for the built interior floor, not a general
## layer-2 exemption. Root still validates the player's entire capsule.
func walkable_floor_at(point: Vector3) -> Dictionary:
	if not point.is_finite() or not is_inside_tree():
		return {}
	for identity in models:
		var model: Node3D = models[identity]
		var local := model.to_local(point)
		var entry := _entry(str(identity))
		if bool(entry.get("service_window", false)):
			continue
		# A shuttered interior is never a checkpoint: an old save made inside
		# falls back to a checked spot outside instead of a sealed room.
		if not is_entry_open(entry):
			continue
		# Building.build's floor box is centred at -.07 with height .14: top=0.
		# Require a foot point already at that floor, never a roof/counter/fall.
		if local.y < -0.03 or local.y > 0.18:
			continue
		if absf(local.x) >= float(entry.width) * 0.5 - 0.25 or absf(local.z) >= float(entry.depth) * 0.5 - 0.25:
			continue
		var floor_point := model.to_global(Vector3(local.x, 0.0, local.z))
		var up := model.global_basis.y.normalized()
		# Starting above the counter/base shelves rejects occupied floor beneath
		# them as well as their tops. Confirm an actual built collision surface.
		var query := PhysicsRayQueryParameters3D.create(floor_point + up * 1.35, floor_point - up * 0.08, 2)
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or hit.collider != model.get_node_or_null("SolidArchitecture"):
			continue
		if hit.position.distance_to(floor_point) > 0.025 or hit.normal.dot(up) < 0.99:
			continue
		return {"position": hit.position, "normal": hit.normal}
	return {}

## Customer apron only. The terrain export has a hole under this existing
## foundation, so checkpoints need its actual exterior support. Exact model,
## exterior bounds, near-floor height and a real top-surface hit are required;
## root still verifies slope and the entire standing capsule independently.
func exterior_floor_at(point: Vector3) -> Dictionary:
	if not point.is_finite() or not is_inside_tree():
		return {}
	for identity in models:
		var entry := _entry(str(identity))
		if not bool(entry.get("service_window", false)) or not is_entry_open(entry):
			continue
		var model: Node3D = models[identity]
		var local := model.to_local(point)
		var counter: Vector3 = model.get_meta("counter_local")
		var front := float(entry.depth) * 0.5
		if local.z <= front + 0.5 or local.z >= front + 2.5 or absf(local.x - counter.x) >= 1.4:
			continue
		# Foundation top is authored at -0.025. Neither the shelf nor a roof
		# nor a falling point can be snapped down into this approved region.
		if local.y < -0.08 or local.y > 0.155:
			continue
		var foundation: Node = model.get_meta("foundation_body", null)
		if not is_instance_valid(foundation):
			continue
		var floor_point := model.to_global(Vector3(local.x, -0.025, local.z))
		var up := model.global_basis.y.normalized()
		var ray := PhysicsRayQueryParameters3D.create(floor_point + up * 1.35, floor_point - up * 0.08, 2)
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty() or hit.collider != foundation:
			continue
		if hit.position.distance_to(floor_point) <= 0.025 and hit.normal.dot(up) >= 0.99:
			return hit
	return {}

## A player can rest against the pantry shelf within the physics contact
## tolerance while checkpoint clearance requires another few millimetres.
## Offer only centimetre-scale outward poses on this same verified apron.
## The save owner must re-run its complete validation for every candidate.
## This does not change the live player, the shelf, any margin, or collision.
func exterior_checkpoint_candidates(point: Vector3) -> Array[Vector3]:
	var result: Array[Vector3] = []
	if not models.has(Catalog.SHOP_ID):
		return result
	var support := exterior_floor_at(point)
	if support.is_empty():
		return result
	var model: Node3D = models[Catalog.SHOP_ID]
	if support.collider != model.get_meta("foundation_body", null):
		return result
	var outward := model.global_basis.z
	outward.y = 0.0
	outward = outward.normalized()
	for distance in [0.01, 0.02, 0.04]:
		var candidate := point + outward * float(distance)
		var floor_hit := exterior_floor_at(candidate)
		if floor_hit.is_empty() or floor_hit.collider != support.collider:
			continue
		# Same side of the frontage and any other intervening obstacle. A
		# full standing-capsule check still follows in the save owner.
		var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP, candidate + Vector3.UP, 2 | 8 | 16)
		if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			continue
		result.append(candidate)
	return result

func handle_input(event: InputEvent) -> bool:
	if is_open():
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			close()
		# Mouse buttons reach GUI. Root must return from its world-input handler
		# whenever is_open() was true, just as for the dialogue modal.
		return event is InputEventKey or event is InputEventMouseMotion
	if Bindings.matches(event, "city_interact"):
		var player: Node3D = level.get("player") if level != null else null
		var identity := counter_at(player.global_position) if is_instance_valid(player) else ""
		if not identity.is_empty():
			return open_shop(identity)
	return false

func is_open() -> bool:
	return not active_id.is_empty()

func open_shop(identity: String) -> bool:
	if is_open():
		return active_id == identity
	var blocked := _blocked_reason()
	if not blocked.is_empty():
		last_message = blocked
		return false
	var entry := _entry(identity)
	if not entry.is_empty() and not is_entry_open(entry):
		last_message = "%s is closed." % str(entry.label)
		return false
	var progression: Node = level.get("progression") if level != null else null
	var player: Node3D = level.get("player") if level != null else null
	if entry.is_empty() or progression == null or not progression.has_method("catalog") or not is_instance_valid(player) or counter_at(player.global_position) != identity:
		return false
	active_id = identity
	last_message = "Colors and clothing apply now. Food and drinks are used at the counter." if str(entry.kind) == Catalog.SHOP_KIND else "Choose an item. Purchases are added to your inventory."
	_previous_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ui.show()
	hint.hide()
	_refresh_catalog()
	modal_changed.emit(true)
	return true

func close() -> void:
	if not is_open():
		return
	active_id = ""
	ui.hide()
	Input.mouse_mode = _previous_mouse_mode
	modal_changed.emit(false)

func purchase(item_id: String) -> Dictionary:
	if not is_open():
		return {"ok": false, "message": "Visit a shop counter first."}
	if not is_entry_open(_entry(active_id)):
		close()
		return {"ok": false, "message": "This shop is closed."}
	var blocked := _blocked_reason(true)
	if not blocked.is_empty():
		close()
		return {"ok": false, "message": blocked}
	var player: Node3D = level.get("player")
	if not is_instance_valid(player) or counter_at(player.global_position) != active_id:
		close()
		return {"ok": false, "message": "Return to the counter."}
	var progression: Node = level.get("progression")
	var stocked := false
	for item in progression.catalog(str(_entry(active_id).kind)):
		stocked = stocked or str(item.get("id", "")) == item_id
	if not stocked:
		return {"ok": false, "message": "This shop does not stock that item."}
	var result: Dictionary = progression.purchase(item_id)
	last_message = str(result.get("message", "Purchase complete." if result.get("ok", false) else "Purchase unavailable."))
	_refresh_catalog()
	return result

func _refresh_catalog() -> void:
	var progression: Node = level.get("progression")
	var entry := _entry(active_id)
	title.text = str(entry.label)
	var money := int(progression.get("money"))
	wallet.text = "Cash · $%d" % money
	clerk.text = str(progression.perception_line("clerk")) if progression.has_method("perception_line") else ""
	clerk.visible = not clerk.text.is_empty()
	message.text = last_message
	for child in stock_rows.get_children():
		stock_rows.remove_child(child)
		child.queue_free()
	var previous_category := ""
	for item in progression.catalog(str(entry.kind)):
		var category := str(item.get("category", ""))
		if not category.is_empty() and category != previous_category:
			var heading := Label.new()
			heading.text = Catalog.category_label(category)
			heading.add_theme_font_size_override("font_size", 19)
			stock_rows.add_child(heading)
			previous_category = category
		var button := Button.new()
		# This catalog uses paper cards; the shared dark-menu disabled colour
		# would otherwise make lock reasons almost white on white.
		button.add_theme_color_override("font_disabled_color", Color("626976"))
		var price := int(item.get("price", 0))
		var owned: bool = bool(item.get("owned", false)) and not bool(item.get("repeatable", false))
		var can_equip := bool(item.get("can_equip", false))
		var equipped := bool(item.get("equipped", false))
		var locked := bool(item.get("locked", false))
		var available: bool = bool(item.get("available", true)) and (not owned or can_equip) and not equipped and not locked
		var label := str(item.get("label", item.get("name", item.id)))
		var status := "Buy"
		if equipped:
			status = "Equipped"
		elif owned and can_equip:
			status = "Equip · free"
		elif owned:
			status = "Owned"
		elif not available:
			status = str(item.get("reason", "")).strip_edges()
			if status.is_empty():
				status = "Locked · requirements not met" if locked else "Unavailable"
		elif price > money:
			status = "Need $%d more" % (price - money)
		elif bool(item.get("reissue", false)):
			status = "Collect free"
		elif category == "food":
			status = "Buy & use"
		button.text = "%s  ·  $%d  ·  %s" % [label, price, status]
		var description := str(item.get("description", ""))
		# Progression appends availability reasons to its descriptive text too.
		# Keep pricing modifiers/details, but show the status reason only once.
		var reason := str(item.get("reason", "")).strip_edges()
		if not owned and not available and not reason.is_empty():
			if description == reason:
				description = ""
			elif description.ends_with(" · " + reason):
				description = description.trim_suffix(" · " + reason)
		if not description.is_empty():
			button.text += "\n" + description
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size.y = 64
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = price > money or not available
		button.name = "Buy_" + str(item.id)
		button.pressed.connect(purchase.bind(str(item.id)))
		stock_rows.add_child(button)
	for child in stock_rows.get_children():
		if child is Button and not child.disabled:
			child.grab_focus()
			break

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ShopUI"
	layer.layer = 55
	add_child(layer)
	ui = Control.new()
	ui.name = "ShopPurchasePanel"
	ui.theme = C.theme()
	layer.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = T.a(T.INK, 0.55)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card = PanelContainer.new()
	card.add_theme_stylebox_override("panel", C.case_file())
	ui.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	card.add_child(column)
	title = Label.new()
	C.text(title, "display", 27)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(title)
	wallet = Label.new()
	column.add_child(wallet)
	clerk = Label.new()
	clerk.name = "ClerkPerception"
	clerk.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	clerk.add_theme_font_size_override("font_size", 17)
	column.add_child(clerk)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	stock_rows = VBoxContainer.new()
	stock_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stock_rows.add_theme_constant_override("separation", 8)
	scroll.add_child(stock_rows)
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(message)
	var leave := Button.new()
	leave.name = "LeaveShop"
	leave.text = "Close · Esc"
	leave.pressed.connect(close)
	column.add_child(leave)
	ui.resized.connect(_layout)
	_layout()
	ui.hide()
	hint = Label.new()
	hint.name = "ShopCounterPrompt"
	hint.theme = C.theme()
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", T.PAPER)
	hint.add_theme_color_override("font_outline_color", T.INK)
	hint.add_theme_constant_override("outline_size", 5)
	layer.add_child(hint)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -90
	hint.offset_bottom = -54
	hint.hide()

func _layout() -> void:
	var width := minf(760, maxf(280, ui.size.x - 40))
	var height := minf(640, maxf(260, ui.size.y - 70))
	card.position = Vector2((ui.size.x - width) * 0.5, (ui.size.y - height) * 0.5)
	card.size = Vector2(width, height)

func _entry(identity: String) -> Dictionary:
	for entry in definitions:
		if str(entry.id) == identity:
			return entry
	return {}

## Open for business in this build (city_play_mode.gd); closed shops stay built.
func is_entry_open(entry: Dictionary) -> bool:
	return not entry.is_empty() and PlayMode.shop_kind_open(str(entry.get("kind", "")))

func closed_ids() -> Array[String]:
	_load_definitions()
	var result: Array[String] = []
	for entry in definitions:
		if not is_entry_open(entry):
			result.append(str(entry.id))
	return result

func _poi(entry: Dictionary) -> Dictionary:
	return {"id": entry.id, "label": entry.label, "position": Building.point(entry.entry_world), "service": entry.service}

## Only shops that are open are advertised.
func get_map_pois() -> Array[Dictionary]:
	_load_definitions()
	var result: Array[Dictionary] = []
	for entry in definitions:
		if is_entry_open(entry):
			result.append(_poi(entry))
	return result

func get_status() -> Dictionary:
	return {"shops": definitions.size(), "built": models.size(), "applied": applied, "open": is_open(), "active_id": active_id,
		"nearby_id": nearby_id, "message": last_message, "removed_meshes": _removed.duplicate(), "map_pois": get_map_pois(),
		"closed_ids": closed_ids()}
