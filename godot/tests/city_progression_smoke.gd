extends SceneTree
## Deterministic progression tests; does not instantiate the neighborhood. Fakes
## mirror the combat/law/driving/shops/missions contracts, and the last section
## drives the real combat equipment API (without setup) for contract drift.
const Progression := preload("res://scripts/city/city_progression.gd")
const DialogueState := preload("res://scripts/city/city_dialogue_state.gd")

class FakeCombat extends Node:
	signal player_offense(kind: String, at: Vector3, victim_id: String)
	const MAGAZINES := {"pistol": 12, "uzi": 30, "ak47": 30}
	var health := 100.0
	var downed := 0.0
	var aggro := 0
	var weapon := "fists"
	var short_ammo := false
	var fail_grant := false
	var restores := 0
	var equipment := {"fists": {"owned": true, "ammo": 0, "reserve": 0}, "pistol": {"owned": true, "ammo": 12, "reserve": 72},
		"uzi": {"owned": false, "ammo": 0, "reserve": 0}, "ak47": {"owned": false, "ammo": 0, "reserve": 0}}

	func grant_weapon(id: String) -> bool:
		if fail_grant or not equipment.has(id) or bool(equipment[id].owned):
			return false
		equipment[id].owned = true
		if id != "fists":
			equipment[id].ammo = int(MAGAZINES[id])
		return true

	func add_ammo(id: String, count: int) -> int:
		if id == "fists" or not equipment.has(id) or count <= 0:
			return 0
		var added := mini(count, 9999 - int(equipment[id].reserve))
		if short_ammo:
			added = mini(added, int(float(count) * 0.5))
		equipment[id].reserve = int(equipment[id].reserve) + added
		return added

	func equipment_snapshot() -> Dictionary:
		return {"version": 1, "equipped": weapon, "weapons": equipment.duplicate(true)}

	func validate_equipment(data: Dictionary) -> bool:
		return int(data.get("version", 0)) == 1 and data.get("weapons") is Dictionary and data.weapons.has("fists")

	func restore_equipment(data: Dictionary) -> bool:
		if not validate_equipment(data):
			return false
		equipment = data.weapons.duplicate(true)
		weapon = str(data.get("equipped", "fists"))
		restores += 1
		return true

	func get_status() -> Dictionary:
		return {"aggro_count": aggro, "active_count": aggro, "downed": downed, "health": health}

class FakeLaw extends Node:
	var wanted := 0
	var recovering := false
	func get_status() -> Dictionary:
		return {"wanted": wanted, "phase": "calm", "message": "", "recovering": recovering}

class FakeDriving extends Node:
	var active := false

class FakeShops extends Node:
	var open := true
	func is_open() -> bool:
		return open

class FakeMissions extends Node:
	func save_schema() -> Dictionary:
		return {"lost_satchel": {"reward": 100, "stages": 3}, "parcel_report": {"reward": 150, "stages": 4}, "dumping": {"reward": 175, "stages": 4},
			"missing_tools": {"reward": 125, "stages": 4}, "torn_notice": {"reward": 140, "stages": 4}, "porch_light": {"reward": 160, "stages": 4}}

class FakeClock extends Node:
	var total_minutes := 540.0

class FakeLevel extends Node:
	var paused := false
	var combat: Node
	var driving: Node
	var law: Node
	var shops: Node
	var missions: Node
	var world_time: Node

var failures := 0
var _finished := false

func _initialize() -> void:
	call_deferred("_watchdog")
	call_deferred("_run")

func _watchdog() -> void:
	await create_timer(60.0, true, false, true).timeout
	if not _finished:
		print("[city_progression] FAIL watchdog: tests did not finish within 60 seconds")
		quit(1)

func check(value: bool, label: String) -> void:
	print("[city_progression] %s %s" % ["PASS" if value else "FAIL", label])
	if not value:
		failures += 1

func _run() -> void:
	_test_config()
	_test_purchases()
	_test_gates()
	_test_thresholds()
	_test_requirements()
	_test_rewards()
	_test_migration()
	_test_validation()
	_test_offenses()
	_test_dialogue()
	_test_perception()
	_test_history()
	_test_real_combat()
	_finished = true
	print("[city_progression] failures=%d" % failures)
	quit(1 if failures else 0)

func _world(config: Dictionary = {}) -> Dictionary:
	var world := FakeLevel.new()
	root.add_child(world)
	world.combat = FakeCombat.new()
	world.law = FakeLaw.new()
	world.driving = FakeDriving.new()
	world.shops = FakeShops.new()
	world.missions = FakeMissions.new()
	world.world_time = FakeClock.new()
	for child in [world.combat, world.law, world.driving, world.shops, world.missions, world.world_time]:
		world.add_child(child)
	var progression := Progression.new()
	world.add_child(progression)
	progression.setup(world, config)
	return {"world": world, "combat": world.combat, "law": world.law, "driving": world.driving, "shops": world.shops, "progression": progression}

func _test_config() -> void:
	var fixture := _world()
	var p = fixture.progression
	check(p.enabled and p.config_errors.is_empty(), "shipped progression config validates %s" % str(p.config_errors))
	check(_ids(p.catalog("gun")) == ["pistol", "uzi", "ak47", "ammo_pistol", "ammo_uzi", "ammo_ak47"], "gun counter publishes pistol/uzi/ak47 and distinct ammo ids")
	check(_ids(p.catalog("weed")) == ["cannabis"] and p.item_ids("weed") == ["cannabis"], "weed counter publishes the cannabis item")
	check(p.catalog("bakery").is_empty() and not p.purchase("bazooka").ok, "unknown shop kinds and items are empty or refused")
	check(p.money == 500 and p.reputation_value("snitch") == 0 and p.reputation_value("gangsta") == 0, "new player starts with $500 and both reputations at zero")
	var fields_ok := true
	for entry in p.catalog("gun"):
		for field in ["id", "label", "description", "price", "owned", "repeatable", "available", "reason", "modifiers"]:
			fields_ok = fields_ok and entry.has(field)
	check(fields_ok, "catalog entries carry every field the shop panel reads")
	var broken := Progression.new()
	broken.setup(null, {"version": 1, "money": {"starting": 10, "max": 5}})
	check(not broken.enabled and not broken.config_errors.is_empty() and broken.snapshot_state().is_empty() and not broken.purchase("pistol").ok and broken.validate_state({}) != "", "an invalid config disables transactions instead of guessing")
	broken.free()

func _test_purchases() -> void:
	var fixture := _world()
	var p = fixture.progression
	var combat = fixture.combat
	var started: Dictionary = p.begin_new_game()
	check(started.ok and started.equipment and not combat.equipment.pistol.owned and combat.equipment.fists.owned and combat.weapon == "fists" and combat.restores == 1, "new game applies the stricter starting inventory through restore_equipment")
	check(not p.begin_new_game().ok and p.money == 500, "a second new game cannot silently wipe progress")
	var early: Dictionary = p.purchase("ammo_pistol")
	check(not early.ok and p.money == 500 and int(combat.equipment.pistol.reserve) == 0, "ammo for an unowned weapon is refused without charge")
	var pistol: Dictionary = p.purchase("pistol")
	check(pistol.ok and p.money == 250 and combat.equipment.pistol.owned and int(combat.equipment.pistol.ammo) == 12, "pistol purchase charges once and grants ownership through combat")
	check(p.reputation_value("gangsta") == 3 and p.reputation_value("snitch") == 0, "buying a weapon moves only the configured gangsta axis")
	var again: Dictionary = p.purchase("pistol")
	check(not again.ok and p.money == 250 and "already own" in str(again.message), "an owned weapon is never charged twice")
	var ammo: Dictionary = p.purchase("ammo_pistol")
	check(ammo.ok and p.money == 220 and int(combat.equipment.pistol.reserve) == 24, "pistol ammunition adds reserve rounds via add_ammo")
	combat.short_ammo = true
	var partial: Dictionary = p.purchase("ammo_pistol")
	check(not partial.ok and p.money == 220 and int(combat.equipment.pistol.reserve) == 24 and combat.restores == 2, "a short ammo grant rolls combat back and charges nothing")
	combat.short_ammo = false
	var locked: Dictionary = p.purchase("uzi")
	var listing: Dictionary = _find(p.catalog("gun"), "uzi")
	check(not locked.ok and p.money == 220 and not combat.equipment.uzi.owned, "the uzi stays behind the counter below the gangsta unlock")
	check(not listing.available and listing.locked and "under the counter" in str(listing.description), "the catalog shows the authored lock reason")
	for _i in 6:
		p.apply_action("dialogue_vouch_street")
	check(p.reputation_value("gangsta") == 15 and p.is_unlocked("counter_uzi") and _find(p.catalog("gun"), "uzi").available, "reaching the gangsta threshold unlocks the uzi")
	var poor: Dictionary = p.purchase("uzi")
	check(not poor.ok and p.money == 220 and "more" in str(poor.message), "an unaffordable weapon is refused with the shortfall")
	p.credit(1000, "fixture")
	combat.fail_grant = true
	var refused: Dictionary = p.purchase("uzi")
	check(not refused.ok and p.money == 1220 and not combat.equipment.uzi.owned and not p.weapons_purchased.has("uzi"), "a refused combat grant charges nothing and records nothing")
	combat.fail_grant = false
	var uzi: Dictionary = p.purchase("uzi")
	check(uzi.ok and p.money == 570 and combat.equipment.uzi.owned and int(combat.equipment.uzi.ammo) == 30, "the uzi is issued with a loaded magazine")
	p.credit(1000, "fixture")
	var stocked := 0
	for _i in 13:
		if p.purchase("cannabis").ok:
			stocked += 1
	check(stocked == 12 and p.item_count("cannabis") == 12 and p.money == 1150, "cannabis is a bounded fictional stash item")
	combat.equipment.uzi.owned = false
	var reissue: Dictionary = p.purchase("uzi")
	check(reissue.ok and reissue.reissued and p.money == 1150 and combat.equipment.uzi.owned, "a weapon already paid for is re-issued free")
	var taken: int = p.debit(5000, "hospital")
	check(taken == 1150 and p.money == 0, "debit takes only what the player has")
	check(not p.purchase("ammo_uzi").ok and p.money == 0 and p.debit(10, "fee") == 0, "nothing can be bought or taken at $0")
	check(p.debit(-5, "fee") == 0 and p.debit(NAN, "fee") == 0 and p.credit(INF, "gift") == 0 and p.money == 0, "nonfinite and negative amounts are refused")

func _test_gates() -> void:
	var fixture := _world()
	var p = fixture.progression
	var combat = fixture.combat
	combat.downed = 2.0
	_refused(p, combat, "a downed player cannot shop")
	combat.downed = 0.0
	combat.health = 0.0
	_refused(p, combat, "a defeated player cannot shop")
	combat.health = 100.0
	combat.aggro = 1
	_refused(p, combat, "a player in a fight cannot shop")
	combat.aggro = 0
	fixture.driving.active = true
	_refused(p, combat, "a driving player cannot shop")
	fixture.driving.active = false
	fixture.law.wanted = 2
	_refused(p, combat, "a wanted player is refused service")
	fixture.law.wanted = 0
	fixture.law.recovering = true
	_refused(p, combat, "a recovering player cannot shop")
	fixture.law.recovering = false
	fixture.shops.open = false
	_refused(p, combat, "purchases need an open walk-in counter")
	fixture.shops.open = true
	fixture.world.paused = true
	var modal: Dictionary = p.purchase("ammo_pistol")
	check(modal.ok and p.money == 470 and int(combat.equipment.pistol.reserve) == 96, "the shop modal's own pause does not block buying")
	fixture.world.paused = false
	fixture.world.combat = null
	check(not p.purchase("pistol").ok and p.money == 470 and p.purchase("cannabis").ok and p.money == 435, "weapons need combat to own them; stash goods do not")
	fixture.world.combat = combat

func _refused(p, combat, label: String) -> void:
	var money: int = p.money
	var reserve := int(combat.equipment.pistol.reserve)
	var result: Dictionary = p.purchase("ammo_pistol")
	var listing: Dictionary = _find(p.catalog("gun"), "ammo_pistol")
	check(not result.ok and p.money == money and int(combat.equipment.pistol.reserve) == reserve and not listing.available and not str(listing.reason).is_empty(), label)

func _test_thresholds() -> void:
	var fixture := _world()
	var p = fixture.progression
	var notices: Array = []
	p.connect("notice", func(text: String): notices.append(text))
	check(int(p.price_quote("uzi").price) == 650 and p.price_quote("uzi").modifiers.is_empty(), "base prices apply without reputation")
	_raise(p, "gangsta", 35)
	check(p.tier_id("gangsta") == "respected" and p.tier_id("snitch") == "unknown" and p.reputation_value("snitch") == 0, "the gangsta axis rises independently of snitch")
	check(int(p.price_quote("uzi").price) == 585 and int(p.price_quote("cannabis").price) == 32, "street respect discounts both counters by 10%")
	check("Gangsta reputation: Respected" in notices, "crossing a tier announces the new standing")
	_raise(p, "snitch", 35)
	check(int(p.price_quote("uzi").price) == 683 and p.is_unlocked("two_faced") and p.tier_id("gangsta") == "respected", "both axes high stack discount and snitch tax instead of cancelling on one slider")
	var tuned: Dictionary = Progression.read_config_file().duplicate(true)
	tuned.tracks.gangsta.tiers[1].at = 5
	var quick := _world(tuned)
	var q = quick.progression
	var plain := _world()
	var d = plain.progression
	for _i in 3:
		q.apply_action("dialogue_vouch_street")
		d.apply_action("dialogue_vouch_street")
	q.credit(1000, "fixture")
	check(q.tier_id("gangsta") == "noticed" and q.is_unlocked("counter_uzi") and q.purchase("uzi").ok and not d.is_unlocked("counter_uzi"), "a configured threshold moves the unlock and purchase gate without code changes")
	var bad: Dictionary = Progression.read_config_file().duplicate(true)
	bad.tracks.snitch.tiers[2].at = 10
	var rejected := Progression.new()
	rejected.setup(null, bad)
	check(not rejected.enabled and str(rejected.config_errors).contains("increase"), "thresholds must start at the minimum and increase")
	rejected.free()

func _test_requirements() -> void:
	var fixture := _world()
	var p = fixture.progression
	check(p.meets("") and p.meets("snitch>=0") and not p.meets("snitch>=1"), "empty and numeric requirements")
	check(p.meets("snitch >= unknown and gangsta < noticed"), "spaced operators and tier names resolve")
	check(p.meets("not (snitch>=known or gangsta>=respected)") and p.meets("money>=500 and not money>500") and p.meets("(true)"), "not, and, or and parentheses")
	check(p.meets("owns:fists") and p.meets("owns:pistol") and not p.meets("owns:uzi"), "owns reads combat ownership")
	check(not p.meets("has:cannabis") and p.meets("cannabis==0") and p.meets("tier:snitch:unknown") and not p.meets("case:lost_satchel"), "inventory, tier and case atoms")
	for bad in ["snitch>=", "karma>=3", "snitch>=legendary", "(snitch>=1", "snitch>=1)", "and", "flag:", "owns:bazooka", "money>=lots", "met_resident", "snitch=>3"]:
		check(not p.handles_condition(bad) and not p.meets(bad) and not p.requirement_error(bad).is_empty(), "invalid requirement is rejected: " + bad)
	check(p.handles_condition("flag:met_dj") and not p.meets("flag:met_dj") and not p.handles_condition(12), "authored flags are progression conditions; plain keys are not")
	check(p.meets(["snitch>=0", "gangsta>=0"]) and not p.meets(["snitch>=0", "gangsta>=1"]), "a list requires every entry")

func _test_rewards() -> void:
	var fixture := _world()
	var p = fixture.progression
	var notices: Array = []
	p.connect("notice", func(text: String): notices.append(text))
	check(p.case_money("lost_satchel", 100) == 100 and p.case_money("dumping", 175) == 175 and p.case_money("dumping", NAN) == 0, "case money defaults to one dollar per community point")
	check(p.reward_case("lost_satchel", 100) and p.money == 600 and p.reputation_value("snitch") == 6, "the first case reward pays money and snitch reputation")
	check("+$100" in str(notices) and str(p.history[-1].action) == "case:lost_satchel", "the reward is announced and audited")
	check(not p.reward_case("lost_satchel", 100) and p.money == 600 and p.reputation_value("snitch") == 6, "a replayed case reward pays nothing")
	check(p.reward_case("dumping", 175) and p.money == 775 and p.reputation_value("snitch") == 16 and p.reputation_value("gangsta") == 0, "a reported case uses its configured action and leaves gangsta alone")
	check(not p.reward_case("made_up_case", 50) and not p.reward_case("parcel_report", -5) and not p.reward_case("parcel_report", NAN) and not p.reward_case("parcel_report", 1.5) and p.money == 775, "unknown cases and invalid amounts are refused")
	var copy := _world()
	var q = copy.progression
	check(q.restore_state(_round_trip(p.snapshot_state())), "the reward ledger restores from JSON")
	check(not q.reward_case("dumping", 175) and not q.reward_case("lost_satchel", 100) and q.money == 775, "a restored checkpoint never pays a case twice")
	check(q.reward_case("parcel_report", 150) and q.money == 925, "an unrewarded case still pays after restore")

func _test_migration() -> void:
	var fixture := _world()
	var p = fixture.progression
	var migrated: Dictionary = p.migrate_legacy(["lost_satchel", "dumping"])
	check(migrated.ok and p.money == 500 and p.reputation_value("snitch") == 16 and p.origin == "legacy" and migrated.marked == ["lost_satchel", "dumping"], "legacy completed cases credit reputation once and no money")
	check(not p.reward_case("dumping", 175) and not p.reward_case("lost_satchel", 100) and p.money == 500, "migrated cases can never be paid")
	check(not p.migrate_legacy(["lost_satchel"]).ok and p.reputation_value("snitch") == 16, "migration cannot run twice")
	check(p.reward_case("porch_light", 160) and p.money == 660 and p.reputation_value("snitch") == 26, "cases completed after migration pay normally")
	var later := _world()
	check(later.progression.restore_state(_round_trip(p.snapshot_state())) and not later.progression.migrate_legacy(["torn_notice"]).ok and later.progression.money == 660, "a restored checkpoint is never migrated again")
	var paying: Dictionary = Progression.read_config_file().duplicate(true)
	paying.migration.credit_money = true
	var alt := _world(paying)
	var r = alt.progression
	r.migrate_legacy(["lost_satchel", "dumping", "lost_satchel"])
	check(r.money == 775 and not r.reward_case("dumping", 175) and r.money == 775, "optional money credit pays exactly once per legacy case")
	var reconcile := _world()
	var s = reconcile.progression
	s.restore_state(_round_trip(s.snapshot_state()))
	var marked: Array = s.reconcile_cases(["torn_notice", "not_a_case"])
	check(marked == ["torn_notice"] and s.money == 500 and not s.reward_case("torn_notice", 140) and s.money == 500, "reconcile marks unrewarded completed cases without paying")
	var invalid := _world()
	check(not invalid.progression.migrate_legacy(["Lost Satchel"]).ok and invalid.progression.money == 500 and invalid.progression.origin == "new", "malformed legacy case ids are refused without changes")

func _test_validation() -> void:
	var fixture := _world()
	var p = fixture.progression
	p.reward_case("lost_satchel", 100)
	p.purchase("cannabis")
	p.apply_action("dialogue_vouch_street")
	var good: Dictionary = _round_trip(p.snapshot_state())
	check(p.validate_state(good).is_empty() and good.history.size() == 3, "a JSON round-tripped snapshot validates")
	var other := _world()
	var q = other.progression
	check(q.restore_state(good) and JSON.stringify(q.snapshot_state()) == JSON.stringify(p.snapshot_state()), "restore reproduces a byte-identical stable snapshot")
	var baseline := JSON.stringify(q.snapshot_state())
	var mutations := [
		["non-finite money", ["money"], NAN], ["infinite money", ["money"], INF], ["negative money", ["money"], -1],
		["money above the cap", ["money"], 10000000], ["fractional money", ["money"], 12.5], ["boolean money", ["money"], true],
		["text money", ["money"], "500"], ["reputation above max", ["reputation", "snitch"], 101], ["reputation below min", ["reputation", "gangsta"], -1],
		["non-finite reputation", ["reputation", "snitch"], NAN], ["unknown track", ["reputation", "karma"], 5], ["unknown item", ["items", "bazooka"], 1],
		["stash above max", ["items", "cannabis"], 13], ["unknown purchase", ["purchases", "tank"], 1], ["negative purchase count", ["purchases", "cannabis"], -1],
		["future version", ["version"], 3], ["version zero", ["version"], 0], ["unknown origin", ["origin"], "cheat"], ["unknown field", ["bonus"], 1],
		["malformed rewarded list", ["rewarded_cases"], "lost_satchel"], ["duplicate rewarded case", ["rewarded_cases"], ["lost_satchel", "lost_satchel"]],
		["unknown rewarded case", ["rewarded_cases"], ["moon_landing"]], ["unknown weapon ledger", ["weapons"], ["bazooka"]],
		["malformed once key", ["once"], ["Bad Key!"]], ["unknown action count", ["actions", "teleport"], 1], ["negative sequence", ["seq"], -1],
		["sequence behind history", ["seq"], 1], ["history not a list", ["history"], {}],
	]
	for mutation in mutations:
		var broken: Dictionary = good.duplicate(true)
		_set_path(broken, mutation[1], mutation[2])
		var reason: String = q.validate_state(broken)
		check(not reason.is_empty() and not q.restore_state(broken) and JSON.stringify(q.snapshot_state()) == baseline, "rejects %s (%s) without changing state" % [mutation[0], reason])
	var missing: Dictionary = good.duplicate(true)
	missing.erase("flags")
	var disordered: Dictionary = good.duplicate(true)
	var first = disordered.history[0]
	disordered.history[0] = disordered.history[1]
	disordered.history[1] = first
	var tampered: Dictionary = good.duplicate(true)
	tampered.history[0]["money"] = INF
	var extra: Dictionary = good.duplicate(true)
	extra.history[0]["cheat"] = true
	var crowded: Dictionary = good.duplicate(true)
	var keys: Array = []
	for index in 300:
		keys.append("hook:k%d" % index)
	crowded.once = keys
	var long_history: Dictionary = good.duplicate(true)
	var template: Dictionary = long_history.history[-1]
	for index in 60:
		var entry: Dictionary = template.duplicate(true)
		entry.seq = int(template.seq) + index + 1
		long_history.history.append(entry)
	long_history.seq = int(template.seq) + 61
	for named in [["a missing field", missing], ["out-of-order history", disordered], ["non-finite history money", tampered],
			["an unknown history field", extra], ["an oversized once ledger", crowded], ["history beyond its bound", long_history]]:
		check(not q.validate_state(named[1]).is_empty() and not q.restore_state(named[1]) and JSON.stringify(q.snapshot_state()) == baseline, "rejects " + str(named[0]))
	check(not q.validate_state("not a dictionary").is_empty() and not q.validate_state(null).is_empty() and not q.validate_state([]).is_empty(), "rejects non-object state")

func _test_offenses() -> void:
	var fixture := _world()
	var p = fixture.progression
	var first: Dictionary = p.on_offense("assault", Vector3.ZERO, "crowd_4")
	var repeat: Dictionary = p.on_offense("assault", Vector3.ZERO, "crowd_4")
	check(first.ok and not repeat.ok and p.reputation_value("gangsta") == 1, "punches on one victim count once per cooldown")
	_advance(p, 9.0)
	check(p.on_offense("assault", Vector3.ZERO, "crowd_4").ok and p.reputation_value("gangsta") == 2, "the cooldown expires with ticked play time")
	fixture.world.paused = true
	_advance(p, 30.0)
	fixture.world.paused = false
	check(not p.on_offense("assault", Vector3.ZERO, "crowd_4").ok, "paused time does not advance cooldowns")
	var accepted := 0
	for index in range(5, 10):
		if p.on_offense("assault", Vector3.ZERO, "crowd_%d" % index).ok:
			accepted += 1
	check(accepted == 3 and p.reputation_value("gangsta") == 5, "a rolling window caps reputation from a brawl")
	_advance(p, 61.0)
	var shots := 0
	for _i in 30:
		if p.on_offense("shooting", Vector3.ZERO, "").ok:
			shots += 1
	check(shots == 1 and p.reputation_value("gangsta") == 7, "automatic fire counts as one shooting incident per cooldown")
	check(not p.on_offense("stomp", Vector3.ZERO, "crowd_9", {"witnessed": false}).ok and p.reputation_value("gangsta") == 7, "unwitnessed offenses build no street reputation")
	check(p.on_offense("stomp", Vector3.ZERO, "crowd_9", {"witnessed": true}).ok and p.reputation_value("gangsta") == 11 and p.reputation_value("snitch") == 0, "a witnessed stomp raises gangsta only")
	check(not p.on_offense("jaywalk", Vector3.ZERO, "").ok, "unmapped offense kinds are ignored")
	fixture.combat.connect("player_offense", Callable(p, "on_offense"))
	_advance(p, 61.0)
	fixture.combat.emit_signal("player_offense", "assault", Vector3(1, 0, 2), "crowd_40")
	check(p.reputation_value("gangsta") == 12, "combat.player_offense connects directly to on_offense")

func _test_dialogue() -> void:
	var fixture := _world()
	var p = fixture.progression
	var hook := {"kind": "progression", "action": "dialogue_vouch_street", "once": "lookout_side"}
	check(not p.meets("used:lookout_side") and p.commit_dialogue_action(hook) and p.reputation_value("gangsta") == 2, "an authored hook applies its action")
	check(p.meets("used:lookout_side") and not p.commit_dialogue_action(hook) and p.reputation_value("gangsta") == 2, "a stale or duplicate hook is refused and pays nothing")
	var passing := hook.duplicate()
	passing.replay = "pass"
	check(p.commit_dialogue_action(passing) and p.reputation_value("gangsta") == 2, "replay pass branches without re-applying")
	check(not p.commit_dialogue_action({"kind": "progression", "action": "dialogue_deny_snitching"}) and p.reputation_value("snitch") == 0, "a rule requirement blocks the hook")
	check(not p.commit_dialogue_action({"kind": "progression", "action": "teleport"}) and not p.commit_dialogue_action({"kind": "case_step", "id": "dumping", "stage": 0}), "unknown actions and foreign hook kinds are refused")
	check(not p.commit_dialogue_action({"kind": "progression", "action": "dialogue_own_it", "requires": "gangsta>=respected"}) and p.reputation_value("snitch") == 0, "a hook requirement is rechecked at commit")
	var round_hook := {"kind": "progression", "action": "buy_round"}
	check(p.commit_dialogue_action(round_hook) and p.money == 485 and p.reputation_value("gangsta") == 3, "a money-costing hook debits atomically")
	check(not p.commit_dialogue_action(round_hook) and p.money == 485, "a cooldown blocks an immediate repeat")
	p.debit(485, "fixture")
	_advance(p, 301.0)
	check(not p.commit_dialogue_action(round_hook) and p.money == 0 and p.reputation_value("gangsta") == 3, "insufficient funds refuse the hook without partial effects")
	for _i in 8:
		p.commit_dialogue_action({"kind": "progression", "action": "dialogue_own_it"})
	check(p.reputation_value("snitch") == 16 and p.reputation_value("gangsta") == 3, "owning the snitch label moves only the snitch axis")
	check(p.commit_dialogue_action({"kind": "progression", "action": "dialogue_deny_snitching"}) and p.reputation_value("snitch") == 13 and p.meets("flag:swore_off"), "denying snitching lowers snitch and sets an authored flag")
	check(not p.commit_dialogue_action({"kind": "progression", "action": "dialogue_deny_snitching"}) and p.reputation_value("snitch") == 13, "a once rule cannot be farmed")
	var fresh := _world()
	var f = fresh.progression
	var state = DialogueState.new()
	var example: Dictionary = f.dialogue_example("lookout_reputation")
	check(state.open(example, Callable(f, "meets"), Callable(f, "commit_dialogue_action")) and state.choices().size() == 4, "the shipped example opens in the real dialogue state with conditions applied")
	state.choose(1)
	check(f.reputation_value("gangsta") == 2 and str(state.current().text) == "Good to hear. I'll pass it along.", "choosing an authored reply commits its progression hook")
	state.open(example, Callable(f, "meets"), Callable(f, "commit_dialogue_action"))
	check(state.choices().size() == 2, "a used once key hides both side-picking replies")
	state.close()

func _test_perception() -> void:
	var fixture := _world()
	var p = fixture.progression
	check(p.perceive("street").attitude == "neutral" and p.perception_line("street").is_empty(), "an unknown player gets neutral perception and no extra line")
	_raise(p, "snitch", 35)
	var view: Dictionary = p.perceive("street")
	check(view.attitude == "guarded" and view.label == "Known snitch" and p.perceive("police").attitude == "cooperative" and p.perceive("neighbor").attitude == "grateful", "snitch reputation is perceived per observer role")
	_raise(p, "gangsta", 35)
	check(p.perceive("street").attitude == "conflicted" and p.perceive("clerk").label == "Two-faced regular" and "snitch:known" in p.perceive("street").tags, "both axes high read as two-faced, not as a midpoint")
	check(p.perceive("street", {"appearance": "any", "group": "any"}) == p.perceive("street"), "perception ignores observer details beyond the authored role")
	check(p.role_for_actor("officer") == "police" and p.role_for_actor("patrol_officer_3") == "police" and p.role_for_actor("lookout") == "street" and p.role_for_actor("crowd_17") == "neighbor", "actor roles come from authored ids and prefixes with a neighbor default")
	var authored := {"start": "start", "nodes": {"start": {"speaker": "Dumbarton witness", "lines": ["There's always something happening along Old York. Keep your eyes open."], "choices": [{"text": "See you around."}]}}}
	var original := authored.duplicate(true)
	var decorated: Dictionary = p.decorate_conversation(authored, "street")
	var spoken: Array = decorated.nodes.start.lines
	check(authored == original and spoken.size() == 2 and spoken[1] == original.nodes.start.lines[0] and spoken[0] == p.perception_line("street"), "the perception line is prepended and authored wording is untouched")

func _test_history() -> void:
	var fixture := _world()
	var p = fixture.progression
	for _i in 100:
		p.apply_action("dialogue_own_it")
	var saved: Dictionary = p.snapshot_state()
	check(p.history.size() == 48 and int(saved.seq) == 100 and int(saved.history[0].seq) == 53 and p.validate_state(_round_trip(saved)).is_empty(), "audit history is bounded, ordered and saveable")
	check(p.reputation_value("snitch") == 100 and int(p.history[-1].deltas.get("snitch", 0)) == 0, "reputation clamps at the track maximum")
	check(int(p.history[-1].minute) == 540 and p.history_lines(3).size() == 3, "audit entries carry the world minute and render as ledger lines")

func _test_real_combat() -> void:
	var combat_script = load("res://scripts/city/city_combat.gd")
	check(combat_script != null and combat_script.can_instantiate(), "real combat script loads for the contract check")
	if combat_script == null or not combat_script.can_instantiate():
		return
	var world := FakeLevel.new()
	root.add_child(world)
	var shops := FakeShops.new()
	world.add_child(shops)
	world.shops = shops
	var combat = combat_script.new()
	world.combat = combat
	var p := Progression.new()
	world.add_child(p)
	p.setup(world)
	var legacy: Dictionary = p.purchase("pistol")
	check(not legacy.ok and str(legacy.message).contains("already own") and p.money == 500, "the legacy pistol owned by combat is not sold again")
	var started: Dictionary = p.begin_new_game()
	check(started.equipment and not bool(combat.equipment.pistol.owned) and str(combat.weapon) == "fists", "real combat accepts the stricter starting inventory")
	check(p.purchase("pistol").ok and bool(combat.equipment.pistol.owned) and int(combat.equipment.pistol.ammo) == 12 and p.money == 250, "real combat grant_weapon issues a loaded pistol")
	check(p.purchase("ammo_pistol").ok and int(combat.equipment_snapshot().weapons.pistol.reserve) == 24 and p.money == 220, "real combat add_ammo stores the purchased rounds")
	world.combat = null
	combat.free()

func _raise(p, track: String, target: int) -> void:
	var action := "dialogue_own_it" if track == "snitch" else "dialogue_vouch_street"
	for _i in 60:
		if int(p.reputation_value(track)) >= target:
			return
		p.apply_action(action)

func _advance(p, seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		p.tick(minf(0.5, left))
		left -= 0.5

func _find(entries: Array, id: String) -> Dictionary:
	for entry in entries:
		if str(entry.get("id", "")) == id:
			return entry
	return {}

func _ids(entries: Array) -> Array:
	var ids: Array = []
	for entry in entries:
		ids.append(str(entry.get("id", "")))
	return ids

func _round_trip(value: Dictionary) -> Dictionary:
	var parsed = JSON.parse_string(JSON.stringify(value))
	return parsed if parsed is Dictionary else {}

func _set_path(target: Dictionary, path: Array, value) -> void:
	var node: Dictionary = target
	for index in path.size() - 1:
		node = node[path[index]]
	node[path[path.size() - 1]] = value
