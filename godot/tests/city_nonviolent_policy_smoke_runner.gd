extends Node
## Nonviolent playable-feature policy (scripts/city/city_play_mode.gd). Drives
## the REAL combat, driving, progression, narrative, shop and shop-building
## scripts against small fakes; the neighborhood is never instantiated.
## Run: python godot/tools/godot_run.py -- --headless --script res://tests/city_nonviolent_policy_smoke.gd
const PlayMode := preload("res://scripts/city/city_play_mode.gd")
const Combat := preload("res://scripts/city/city_combat.gd")
const Driving := preload("res://scripts/city/city_driving.gd")
const Progression := preload("res://scripts/city/city_progression.gd")
const Narrative := preload("res://scripts/city/city_narrative.gd")
const Shops := preload("res://scripts/city/city_shops.gd")
const Building := preload("res://scripts/city/city_shop_building.gd")
const Actor := preload("res://scripts/city/city_npc_actor.gd")
const Missions := preload("res://scripts/city/city_missions.gd")
const Npcs := preload("res://scripts/city/city_npcs.gd")

class FakePlayer extends CharacterBody3D:
	var enabled := true
	var yaw := 0.0
	var left_at := Vector3.INF
	func leave_vehicle(at: Vector3, heading: float) -> void:
		left_at = at
		yaw = heading

class FakeLevel extends Node3D:
	var paused := false
	var player: Node
	var combat: Node
	var progression: Node
	var driving: Node
	var law: Node
	var shops: Node
	var missions: Node
	var world_time: Node

class FakeActor extends Node:
	var display_name := "Neighbor"
	var enabled := true

class FakeNpcs extends Node:
	var actors: Dictionary = {}
	func get_actor(id: String):
		if not actors.has(id):
			var actor := FakeActor.new()
			add_child(actor)
			actors[id] = actor
		return actors[id]
	func actor_position(_id: String) -> Vector3:
		return Vector3.ZERO

class FakeMissions extends Node:
	signal notice(text: String)
	signal changed
	var level: Node
	var npcs: Node
	var completed_ids: Dictionary = {}
	var active_id := ""
	var stage := 0
	var _steps: Array = []
	var cancels := 0
	var notices: Array[String] = []
	func _init() -> void:
		notice.connect(func(text: String): notices.append(text))
	func cancel_case() -> void:
		cancels += 1
		active_id = ""
		stage = 0
		_steps.clear()
	func start_case(_id: String) -> bool:
		return false
	func _can_interact(_at: Vector3) -> bool:
		return true
	func save_schema() -> Dictionary:
		return {}

var failures := 0
var _finished := false

func _ready() -> void:
	call_deferred("_watchdog")
	call_deferred("_run")

func _watchdog() -> void:
	await get_tree().create_timer(60.0, true, false, true).timeout
	if not _finished:
		print("[city_nonviolent] FAIL watchdog: tests did not finish within 60 seconds")
		get_tree().quit(1)

func check(value: bool, label: String) -> void:
	print("[city_nonviolent] %s %s" % ["PASS" if value else "FAIL", label])
	if not value:
		failures += 1

func _run() -> void:
	G.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.process_mode = Node.PROCESS_MODE_DISABLED
	Hud.hide()
	_test_policy()
	_test_combat()
	_test_driving()
	_test_progression()
	_test_narrative()
	_test_custody_contacts()
	await _test_shops()
	_finished = true
	print("[city_nonviolent] failures=%d" % failures)
	get_tree().quit(1 if failures else 0)

func _test_policy() -> void:
	check(not PlayMode.PLAYER_COMBAT and not PlayMode.PLAYER_DRIVING and not PlayMode.ALIGNMENT, "all three feature flags default to false")
	var script: Script = PlayMode
	check(script.get_script_property_list().filter(func(p): return (int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0).is_empty(),
		"policy has no mutable state (no runtime toggle)")
	check(not PlayMode.shop_kind_open("gun") and PlayMode.shop_kind_open("weed"), "gun stores closed, weed shop open")
	check(not PlayMode.item_kind_sellable("weapon") and not PlayMode.item_kind_sellable("ammo") and PlayMode.item_kind_sellable("goods"), "weapons and ammunition unsellable, goods sellable")
	check(not PlayMode.story_option_allowed("petals_call", "intimidate") and PlayMode.story_option_allowed("petals_call", "negotiate")
		and not PlayMode.story_option_allowed("petals_final", "intimidate_firm") and PlayMode.story_option_allowed("petals_final", "intimidate_amends"),
		"only the coercive story options are retired")
	var stranded: Array[String] = []
	for id in Narrative.PARTS:
		for step in Narrative.PARTS[id].steps:
			if not step.has("decision"):
				continue
			var kept := 0
			for option in step.options:
				kept += int(PlayMode.story_option_allowed(str(step.decision), str(option.option)))
			if kept == 0:
				stranded.append(str(id))
	check(stranded.is_empty(), "every authored decision keeps at least one allowed option %s" % str(stranded))

func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	return event

func _mouse(button: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	return event

func _test_combat() -> void:
	var combat = Combat.new()
	get_tree().root.add_child(combat)
	var player := FakePlayer.new()
	get_tree().root.add_child(player)
	combat.player = player
	var offenses: Array = []
	combat.player_offense.connect(func(kind, _at, victim): offenses.append([kind, victim]))
	check(not combat.handle_input(_mouse(MOUSE_BUTTON_LEFT)), "LMB is never consumed by combat (basketball and other services keep it)")
	check(not combat.handle_input(_mouse(MOUSE_BUTTON_RIGHT)), "RMB falls through to camera orbit")
	for code in [KEY_1, KEY_2, KEY_3, KEY_4, KEY_R]:
		check(not combat.handle_input(_key(code)), "weapon/reload key %s is not consumed" % OS.get_keycode_string(code))
	combat.equip("pistol")
	check(str(combat.weapon) == "fists" and not combat.request_attack() and not combat.request_reload() and combat.punches_thrown == 0 and combat.shots_fired == 0,
		"cannot equip, attack, punch, fire or reload")
	var legacy := {"version": 1, "equipped": "ak47", "weapons": {"fists": {"owned": true, "ammo": 0, "reserve": 0},
		"pistol": {"owned": true, "ammo": 12, "reserve": 72}, "uzi": {"owned": true, "ammo": 30, "reserve": 60},
		"ak47": {"owned": true, "ammo": 30, "reserve": 120}}}
	check(combat.validate_equipment(legacy) and combat.restore_equipment(legacy), "a legacy armed loadout still validates and restores")
	var saved: Dictionary = combat.equipment_snapshot()
	check(str(combat.weapon) == "fists" and int(combat.ammo) == 0 and str(saved.equipped) == "fists", "a restored loadout is holstered to fists")
	check(saved.weapons.ak47 == legacy.weapons.ak47 and saved.weapons.pistol == legacy.weapons.pistol and combat.validate_equipment(saved),
		"saved ownership and rounds are preserved verbatim and the snapshot stays loadable")
	combat.equip("ak47")
	check(str(combat.weapon) == "fists", "the restored rifle cannot be drawn")
	check(combat.get_status().player_offense_enabled == false and str(combat.get_status().message).is_empty(), "status reports offense disabled with no weapon tutorial")
	var crowd_body := StaticBody3D.new()
	crowd_body.set_meta("city_crowd_index", 3)
	get_tree().root.add_child(crowd_body)
	check(not combat.receive_bicycle_contact({"collider": crowd_body, "speed": 4.0, "harmless": true}) and combat.bicycle_contacts == 1
		and str(combat.last_bicycle_contact.id) == "crowd_3", "a bike bump on a crowd resident is only counted")
	var actor = Actor.new()
	actor.actor_id = "daily_test_walker"
	actor._speech_label = Label3D.new()
	actor.add_child(actor._speech_label)
	get_tree().root.add_child(actor)
	check(combat.receive_bicycle_contact({"collider": actor, "speed": 6.0, "harmless": true}) and actor._speech_remaining > 0.0
		and str(actor._speech_label.text) in Combat.BICYCLE_LINES, "a free actor answers a bike bump with one spoken line")
	check(not actor.dead and actor.enabled and not actor.combat_override and combat.hits_landed == 0 and combat._wounds.is_empty()
		and combat._active.is_empty() and combat._panic.is_empty() and offenses.is_empty(),
		"bike bumps never damage, engage, panic or report an offense")
	actor.queue_free()
	crowd_body.queue_free()
	combat.queue_free()
	player.queue_free()

func _test_driving() -> void:
	var level := FakeLevel.new()
	get_tree().root.add_child(level)
	var player := FakePlayer.new()
	level.add_child(player)
	level.player = player
	var driving = Driving.new()
	driving.level = level
	driving.player = player
	level.add_child(driving)
	check(not driving.handle_input(_key(KEY_F)), "F is never consumed by driving (the bicycle can use it)")
	var car := Node3D.new()
	level.add_child(car)
	check(not driving.enter_vehicle(car) and not driving.active and driving.entries == 0, "no car can be boarded")
	driving.starter = car
	check(driving.get_map_pois().is_empty(), "no 'Your car' map marker")
	driving._build_label(car)
	check(car.get_child_count() == 0 and driving._label == null, "the starter car gets no 'F Drive' label")
	driving.tick(0.1)
	var status: Dictionary = driving.get_status()
	check(str(status.prompt).is_empty() and status.player_driving_enabled == false, "no boarding prompt and status reports driving disabled")
	driving.active = true
	driving.vehicle = null
	driving.tick(0.1)
	check(not driving.active and driving.exits == 1 and bool(driving.last_exit.forced) and player.left_at.is_finite(), "a seat taken by any other path is vacated at once")
	level.queue_free()

func _progression_world() -> Dictionary:
	var level := FakeLevel.new()
	get_tree().root.add_child(level)
	var progression = Progression.new()
	level.add_child(progression)
	level.progression = progression
	progression.setup(level)
	return {"level": level, "progression": progression}

func _test_progression() -> void:
	var fixture := _progression_world()
	var p = fixture.progression
	check(p.enabled, "shipped progression config loads")
	check(p.hud_text() == "$500", "HUD shows money only, no alignment")
	var vouched: Dictionary = p.apply_action("dialogue_vouch_street")
	check(vouched.ok and vouched.deltas.is_empty() and p.reputation_value("gangsta") == 0, "alignment actions no longer move the tracks")
	var legacy: Dictionary = p.snapshot_state()
	legacy.reputation = {"snitch": 70, "gangsta": 80}
	check(p.restore_state(legacy), "a legacy high-alignment snapshot restores")
	check(p.reputation_value("gangsta") == 80 and int(p.snapshot_state().reputation.gangsta) == 80, "stored alignment is preserved for saves")
	check(p.meets("gangsta>=respected") and p.meets("not snitch>=known") and p.is_unlocked("counter_ak47") and p.is_unlocked("two_faced"),
		"alignment-only requirements and unlocks never block access")
	check(int(p.price_quote("cannabis").percent) == 0 and str(p.perceive("street").rule) == "default" and p.perception_line("clerk").is_empty(),
		"no alignment pricing or perception")
	_test_alignment_requirements(p)
	check(p.dialogue_example("lookout_reputation").is_empty(), "the 'whose side are you on' alignment chat is withheld")
	var history_size: int = p.history.size()
	check(not bool(p.on_offense("assault", Vector3.ZERO, "crowd_1").ok) and not bool(p.on_offense("shooting").ok) and p.history.size() == history_size,
		"offenses earn nothing and leave no record")
	check(p.catalog("gun").is_empty() and not p.catalog("weed").is_empty(), "the gun counter publishes no stock")
	var money: int = p.money
	for item in ["pistol", "uzi", "ak47", "ammo_pistol"]:
		var bought: Dictionary = p.purchase(item)
		check(not bought.ok and p.money == money and str(bought.message).contains("closed"), "%s cannot be bought" % item)
	check(p.purchase("cannabis").ok and p.money == money - 35, "the weed shop still sells")
	check(str(p.choice_available("petals_call", "intimidate").reason) == "option retired" and not bool(p.commit_choice("petals_call", "intimidate").ok)
		and p.choice_of("petals_call").is_empty(), "the intimidate choice is refused")
	for line in p.history_lines(48):
		check(not str(line).contains("Snitch") and not str(line).contains("Gangsta"), "ledger line hides alignment: " + str(line))
	fixture.level.queue_free()

func _test_alignment_requirements(p: Node) -> void:
	var saved_config: Dictionary = p.config.duplicate(true)
	var saved_reputation: Dictionary = p.reputation.duplicate()
	var saved_relationships: Dictionary = p.relationships.duplicate()
	p.relationships.ines = 25
	p.config.unlocks.smoke_mixed = {"requires": "snitch>=known and money>=600"}
	p.config.unlocks.smoke_nested = {"requires": "unlock:smoke_mixed or flag:smoke_allowed"}
	p.config.unlocks.smoke_unconditional = {"requires": ""}
	var cases := [
		["snitch>=known", true], ["not snitch>=known", true],
		["not (snitch>=known and gangsta>=respected)", true],
		["tier:gangsta:feared", true], ["not tier:gangsta:feared", true],
		["unlock:two_faced", true], ["not unlock:two_faced", true],
		["gangsta>=respected and money>=600", false],
		["gangsta>=respected or money>=600", false],
		["money>=100 and not snitch>=known", true],
		["not (money>=600 or snitch>=known)", true],
		["not (money>=100 and snitch>=known)", false],
		["gangsta>=respected and flag:smoke_allowed", false],
		["not flag:smoke_allowed and snitch>=known", true],
		["rel:ines>=20 and snitch>=known", true],
		["snitch>=known or rel:ines>=30", false],
		["unlock:smoke_mixed", false], ["not unlock:smoke_mixed", true],
		["unlock:smoke_nested", false], ["not unlock:smoke_nested", true],
		["not unlock:smoke_unconditional", false],
		["snitch>=known or false", false], ["money>=100", true],
		["unknown_track>=4 and snitch>=known", false],
	]
	for reputation in [{"snitch": 0, "gangsta": 0}, {"snitch": 100, "gangsta": 100}]:
		p.reputation = reputation.duplicate()
		for row in cases:
			check(p.meets(row[0]) == row[1], "alignment pruning preserves other requirements: %s (stored %d)" % [row[0], reputation.snitch])
	check(p.meets(["snitch>=known", "money>=100"]) and not p.meets(["snitch>=known", "money>=600"]), "requirement arrays preserve nonalignment constraints")
	check(p.perceive("street").tags.is_empty(), "perception does not publish alignment tags")
	# Alignment-dependent effects are skipped entirely; independent effects remain.
	p.config.pricing.modifiers.append({"id": "smoke_money", "label": "Ordinary discount", "shops": ["weed"], "requires": "money>=100", "percent": -5})
	p.config.pricing.modifiers.append({"id": "smoke_alignment", "label": "Retired discount", "shops": ["weed"], "requires": "not unlock:two_faced", "percent": -10})
	check(int(p.price_quote("cannabis").percent) == -5, "only nonalignment price modifiers apply, including indirect NOT unlock predicates")
	p.config.perception.insert(0, {"id": "smoke_money", "roles": ["street"], "requires": "money>=100", "attitude": "neutral", "label": "Customer", "line": "Welcome."})
	p.config.perception.insert(0, {"id": "smoke_alignment", "roles": ["street"], "requires": "not unlock:two_faced", "attitude": "neutral", "label": "Retired", "line": "Wrong line."})
	check(p.perception_line("street") == "Welcome.", "nonalignment perception remains while alignment-derived perception is skipped")
	p.config.reactions.insert(0, {"id": "smoke_contact", "actors": ["smoke_actor"], "requires": "rel:ines>=20", "line": "Still friends."})
	p.config.reactions.insert(0, {"id": "smoke_alignment", "actors": ["smoke_actor"], "requires": "tier:gangsta:feared", "line": "Wrong line."})
	check(p.reaction_line("smoke_actor") == "Still friends.", "contact relationships remain while alignment-derived reactions are skipped")
	p.config = saved_config
	p.reputation = saved_reputation
	p.relationships = saved_relationships

func _story_world() -> Dictionary:
	var fixture := _progression_world()
	var missions := FakeMissions.new()
	var npcs := FakeNpcs.new()
	missions.add_child(npcs)
	missions.npcs = npcs
	missions.level = fixture.level
	fixture.level.missions = missions
	fixture.level.add_child(missions)
	var story = Narrative.new()
	story.setup(missions)
	fixture.missions = missions
	fixture.story = story
	return fixture

func _test_custody_contacts() -> void:
	var level := FakeLevel.new()
	get_tree().root.add_child(level)
	var npcs := Npcs.new()
	level.add_child(npcs)
	var resident := Actor.new()
	resident.actor_id = "resident"
	npcs.add_child(resident)
	npcs.actors.resident = resident
	var missions := Missions.new()
	level.add_child(missions)
	level.missions = missions
	missions.setup(level, npcs)
	check(npcs.actor_position("resident").is_finite(), "living contact has an interaction position")
	resident.set_meta("police_custody", true)
	check(not npcs.actor_position("resident").is_finite() and not missions.narrative._present("resident"), "held contact is absent from interaction and story presence")
	resident.set_meta("police_custody_completed", true)
	resident.set_meta("police_custody", false)
	resident.set_enabled(false)
	resident.hide()
	check(not npcs.actor_position("resident").is_finite() and missions._available_offers().is_empty(), "completed custody removes invisible contact offers")
	check(not missions.start_case("lost_satchel"), "case requiring a detained contact cannot start")
	var ledger: Array[Dictionary] = missions.case_ledger()
	check(ledger[0].state == "unavailable" and str(ledger[0].reason).contains("custody"), "case ledger identifies custody without claiming death")
	missions.active_id = "lost_satchel"
	missions._steps = missions.case_steps("lost_satchel")
	missions.stage = 0
	missions.tick(0.01)
	check(missions.active_id.is_empty() and missions.score == 0 and missions.completed_ids.is_empty(), "detention cancels active case without rewarding or completing it")
	var snapshot := {"active_id": "lost_satchel", "stage": 0, "completed_ids": [], "score": 0}
	check(missions.preflight_restore(snapshot) and missions.restore_state(snapshot) and missions.active_id.is_empty(), "older active checkpoint restores earned state without reviving detained-contact attempt")
	var lookout := Actor.new()
	lookout.actor_id = "lookout"
	npcs.add_child(lookout)
	npcs.actors.lookout = lookout
	lookout.set_meta("police_custody_completed", true)
	var stand_in := Actor.new()
	stand_in.actor_id = "ambient_neighbor"
	npcs.add_child(stand_in)
	npcs.actors.ambient_neighbor = stand_in
	check(missions.narrative.resolve("@street") == "ambient_neighbor", "story role uses a living stand-in for a detained contact")
	check(not resident.get_meta("city_dead", false) and not lookout.get_meta("city_dead", false), "custody never writes death flags")
	level.queue_free()

func _choice_ids(conversation: Dictionary) -> Array:
	var ids: Array = []
	for reply in conversation.nodes.start.choices:
		if reply.has("hook") and reply.hook.has("choice"):
			ids.append(str(reply.hook.choice))
	return ids

func _test_narrative() -> void:
	var fixture := _story_world()
	var story = fixture.story
	var missions: FakeMissions = fixture.missions
	var p = fixture.progression
	var decide: Dictionary = Narrative.PARTS.petals_word.steps[2]
	var offered := _choice_ids(story.step_conversation("petals_word", 2, decide))
	check(offered == ["report", "protect", "negotiate"], "part 1 offers no intimidation %s" % str(offered))
	check(not bool(story.accept_step("petals_word", decide, "intimidate").ok) and p.choice_of("petals_call").is_empty(), "a stale intimidate reply commits nothing")
	check(Narrative.PARTS.petals_word.steps[2].options.size() == 4 and Narrative.PARTS.has("petals_intimidate") and Narrative.ENDINGS.has("intimidate_firm"),
		"authored intimidate branch data is preserved")
	# Legacy slot: intimidate already chosen, part 2 done, too little cash to pay Ines back.
	p.choices = {"petals_call": "intimidate"}
	missions.completed_ids = {"petals_word": true, "petals_intimidate": true}
	p.money = 50
	var held: Dictionary = story.part_state("petals_end_intimidate")
	check(not bool(held.startable) and str(held.state) == "unavailable" and str(held.reason).contains("$120"), "part 3 waits for the payback money: " + str(held.reason))
	check(story.can_start("petals_end_intimidate", 1, true), "a restored part 3 still resumes, so the checkpoint loads")
	missions.active_id = "petals_end_intimidate"
	missions.stage = 1
	story._hold_if_stranded()
	check(missions.cancels == 1 and missions.active_id.is_empty() and not missions.notices.is_empty() and missions.notices[-1].contains("$120"),
		"an unfinishable part 3 is put on hold (errands open again), never soft-locked")
	var final_step: Dictionary = Narrative.PARTS.petals_end_intimidate.steps[1]
	var finale: Dictionary = story.step_conversation("petals_end_intimidate", 1, final_step)
	check(_choice_ids(finale) == ["intimidate_amends"], "the only ending offered is making amends")
	p.money = 200
	check(bool(story.part_state("petals_end_intimidate").startable), "with the cash, part 3 is offered again")
	check(not bool(story.accept_step("petals_end_intimidate", final_step, "intimidate_firm").ok) and p.choice_of("petals_final").is_empty(), "raising the fee is refused")
	var amends: Dictionary = story.accept_step("petals_end_intimidate", final_step, "intimidate_amends")
	check(bool(amends.ok) and p.choice_of("petals_final") == "intimidate_amends" and p.money == 80 and p.reputation_value("gangsta") == 0,
		"amends resolve the legacy branch: money and relationships apply, alignment does not")
	check(story.validate(["petals_word", "petals_intimidate", "petals_end_intimidate"], "", 0, p.choices, {}).is_empty(), "the migrated story still validates for saves")
	fixture.level.queue_free()

func _shop_entry(kind: String) -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Shops.DATA))
	for entry in data.shops:
		if str(entry.kind) == kind:
			return entry
	return {}

func _labels(node: Node, out: Array) -> Array:
	if node is Label3D:
		out.append(str(node.text))
	for child in node.get_children():
		_labels(child, out)
	return out

func _test_shops() -> void:
	var gun := _shop_entry("gun")
	var weed := _shop_entry("weed")
	check(not gun.is_empty() and not weed.is_empty(), "shop data has a gun store and the weed shop")
	var shops = Shops.new()
	get_tree().root.add_child(shops)
	var advertised: Array = shops.get_map_pois().map(func(poi): return str(poi.service))
	check(not "gun_store" in advertised and "weed_store" in advertised, "map advertises the weed shop only %s" % str(advertised))
	check(shops.closed_ids().size() == 4 and str(gun.id) in shops.closed_ids(), "all four gun stores are closed")
	var closed: Node3D = Building.build(gun)
	var open: Node3D = Building.build(weed)
	get_tree().root.add_child(closed)
	get_tree().root.add_child(open)
	var closed_text := _labels(closed, [])
	check(bool(closed.get_meta("closed")) and "CLOSED" in closed_text and not "OPEN · WALK IN" in closed_text and not "COUNTER · E TO SHOP" in closed_text,
		"the gun store shows a CLOSED shutter sign and no shop prompts")
	check(str(gun.label).to_upper() in closed_text and closed.get_node_or_null("BatchedArchitecture") != null, "the building and its storefront sign are preserved")
	check(not bool(open.get_meta("closed")) and "OPEN · WALK IN" in _labels(open, []), "the weed shop stays open")
	shops.models[str(gun.id)] = closed
	shops.models[str(weed.id)] = open
	var gun_counter: Vector3 = closed.to_global(closed.get_meta("counter_local"))
	var weed_counter: Vector3 = open.to_global(open.get_meta("counter_local"))
	check(shops.counter_at(gun_counter).is_empty() and shops.counter_at(weed_counter) == str(weed.id), "a closed counter is never served")
	check(shops.walkable_floor_at(gun_counter).is_empty(), "a closed interior is never a checkpoint floor")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var front := float(gun.depth) * 0.5
	var space := closed.get_world_3d().direct_space_state
	var into_gun := PhysicsRayQueryParameters3D.create(closed.to_global(Vector3(0, 1.2, front + 1.5)), closed.to_global(Vector3(0, 1.2, 0)), 2)
	var hit := space.intersect_ray(into_gun)
	check(not hit.is_empty() and hit.collider == closed.get_node("SolidArchitecture") and closed.to_local(hit.position).z > front - 0.2,
		"the doorway is physically sealed by the shutter")
	var weed_front := float(weed.depth) * 0.5
	var into_weed := PhysicsRayQueryParameters3D.create(open.to_global(Vector3(0, 1.2, weed_front + 1.5)), open.to_global(Vector3(0, 1.2, 0)), 2)
	check(space.intersect_ray(into_weed).is_empty(), "the weed shop doorway stays open")
	closed.queue_free()
	open.queue_free()
	shops.queue_free()
