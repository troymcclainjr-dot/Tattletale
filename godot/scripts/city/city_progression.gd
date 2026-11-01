extends Node
## Money, two independent reputation tracks (Snitch, Gangsta), fictional shop
## inventory, authored unlocks and role-based perception. Every number and rule
## is data in pen_lucy_progression.json; this script only interprets it.
## Heat stays in law. Weapons and ammunition stay in combat: purchases call
## grant_weapon/add_ammo and roll back through restore_equipment on mismatch.
## Observers are story roles (neighbor/street/police/clerk), never appearance.
## Relationships are per authored contact, decisions keep one durable option
## each, and errands pay through one shared cooldown measured in saved
## world_time.elapsed_seconds so repeatable income stays bounded.
## city_play_mode.gd: with ALIGNMENT off the tracks never move, are not shown
## and every requirement reads them at their start value (stored values are
## kept for saves); offenses earn nothing. With PLAYER_COMBAT off weapon/ammo
## items are unsellable, closed shop kinds publish no catalog and retired
## story options cannot be chosen. Money, goods, relationships, choices and
## errands are unchanged.

signal changed
signal notice(text: String)
signal money_changed(balance: int, delta: int, reason: String)
signal reputation_changed(track: String, value: int, tier: String)
signal relationship_changed(contact: String, value: int, tier: String)
signal choice_made(decision: String, option: String)

## 2 adds relationships, choices and errands; version 1 snapshots still restore.
const VERSION := 2
const PlayMode := preload("res://scripts/city/city_play_mode.gd")
const CONFIG_PATH := "res://assets/data/pen_lucy_progression.json"
const WEAPONS_PATH := "res://scripts/city/city_combat_weapons.gd"
const MAX_CONFIG_BYTES := 262144
const MAX_REQUIREMENT := 240
const MAX_DEPTH := 32
const MAX_SEQ := 9007199254740991
const MAX_CASES := 256
const KEY_LIMIT := 96
const ONCE_LIMIT := 192
const ORIGINS := ["new", "legacy"]
const ITEM_KINDS := ["weapon", "ammo", "goods"]
const OPERATORS := [">=", "<=", "==", "!=", ">", "<"]
const RESERVED := ["money", "true", "false", "and", "or", "not"]
const STATE_KEYS := ["version", "origin", "money", "reputation", "items", "purchases", "weapons", "rewarded_cases", "once", "flags", "actions", "history", "seq"]
const STATE_KEYS_V2 := ["version", "origin", "money", "reputation", "items", "purchases", "weapons", "rewarded_cases", "once", "flags", "actions", "history", "seq",
	"relationships", "choices", "errands"]
const ERRAND_KEYS := ["runs", "ready_at", "earned"]
const MAX_READY_AT := 1000000000
const HISTORY_KEYS := ["seq", "action", "key", "deltas", "money", "minute", "note"]
const CONFIG_KEYS := ["version", "about", "money", "new_game", "limits", "gates", "tracks", "items", "shops", "pricing", "unlocks", "actions", "offenses", "cases", "migration", "perception", "actor_roles", "dialogue_examples",
	"relationships", "decisions", "errands", "reactions"]
const LIMITS := {"history": [1, 512, 48], "once_keys": [8, 4096, 256], "flags": [1, 1024, 128], "stack": [1, 100000, 999],
	"purchase_count": [1, 10000000, 100000], "action_count": [1, 100000000, 1000000], "cooldown_entries": [8, 4096, 256]}
const GATES := ["block_downed", "block_combat", "block_driving", "block_recovering", "block_wanted", "require_open_shop"]

var level: Node
var enabled := false
var config: Dictionary = {}
var config_errors: Array = []
var last_message := ""
var last_validation_error := ""
var money_cap := 0
## Read freely (the shop UI does). Change it through debit/credit/purchase so
## the audit history stays truthful; the setter only guarantees 0..money.max.
var money := 0:
	set(value):
		money = clampi(value, 0, money_cap)
var reputation: Dictionary = {}
var items: Dictionary = {}
var purchases: Dictionary = {}
var weapons_purchased: Dictionary = {}
var rewarded_cases: Dictionary = {}
var flags: Dictionary = {}
var action_counts: Dictionary = {}
var history: Array = []
var origin := "new"
var seq := 0
var relationships: Dictionary = {}
## decision id -> option id; never rewritten once chosen.
var choices: Dictionary = {}
var errand_runs := 0
## world_time.elapsed_seconds at which the next errand may pay.
var errand_ready_at := 0
var errand_earned := 0
var _once: Dictionary = {}
var _clock := 0.0
var _cooldowns: Dictionary = {}
var _windows: Dictionary = {}
var _session_loaded := false
var _compiled: Dictionary = {}
var _parse_cfg: Dictionary = {}
var _parse_tokens: Array = []
var _parse_index := 0
var _parse_error := ""
var _operator_spacing := RegEx.new()
var _id_pattern := RegEx.new()

func _init() -> void:
	_operator_spacing.compile("\\s*(>=|<=|==|!=|>|<)\\s*")
	_id_pattern.compile("^[a-z][a-z0-9_]{0,63}$")

## Manager contract. A fixture may pass its own config; otherwise the shipped
## JSON is read. Starts as a new game without touching combat: root then calls
## begin_new_game (no checkpoint), restore_state or migrate_legacy.
func setup(owner_level: Node, config_data: Dictionary = {}) -> void:
	level = owner_level
	name = "Progression"
	load_config(config_data if not config_data.is_empty() else read_config_file())
	_reset_state()
	_session_loaded = false

static func read_config_file(path: String = CONFIG_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_CONFIG_BYTES:
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return {}
	return parser.data

## An invalid config disables every transaction (snapshot_state returns {} and
## validate_state rejects) instead of guessing; config_errors explains why.
func load_config(data: Dictionary) -> bool:
	var errors: Array = []
	var normalized := _normalize_config(data, errors)
	config = normalized
	config_errors = errors
	enabled = errors.is_empty()
	money_cap = int(normalized.money.max) if enabled else 0
	_compiled.clear()
	return enabled

## Cooldowns and rate windows run on unpaused play time only.
func tick(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	if level != null and _is_true(level.get("paused")):
		return
	_clock += minf(delta, 1.0)
	_repair_errand_clock()

func get_status() -> Dictionary:
	var tracks := {}
	if enabled:
		for track in config.track_order:
			tracks[track] = reputation_status(str(track))
	var last: Dictionary = history.back() if not history.is_empty() else {}
	return {"enabled": enabled, "config_errors": config_errors.duplicate(), "money": money, "reputation": tracks,
		"items": items.duplicate(), "weapons_purchased": _sorted_keys(weapons_purchased), "rewarded_cases": _sorted_keys(rewarded_cases),
		"flags": _sorted_keys(flags), "unlocks": unlock_status(), "history_size": history.size(), "last_entry": last.duplicate(true),
		"origin": origin, "message": last_message, "summary": hud_text(), "relationships": relationship_status(),
		"choices": choices.duplicate(), "errands": errand_status(), "alignment_enabled": PlayMode.alignment_enabled()}

# --- Relationships, durable choices and errands -----------------------------------

func relationship_value(contact: String) -> int:
	if not enabled or not config.relationships.contacts.has(contact):
		return 0
	return int(relationships.get(contact, config.relationships.start))

func relationship_tier(contact: String) -> String:
	if not enabled or not config.relationships.contacts.has(contact):
		return ""
	return str(_tier_for(config.relationships, relationship_value(contact)).get("id", ""))

## Authored contact id for an actor id ("" when the actor has no relationship).
func contact_for_actor(actor_id: String) -> String:
	return str(config.relationships.actors.get(actor_id, "")) if enabled else ""

func relationship_status() -> Array:
	var rows: Array = []
	if not enabled:
		return rows
	for contact in config.relationships.contact_order:
		var value := relationship_value(str(contact))
		var tier := _tier_for(config.relationships, value)
		rows.append({"id": contact, "label": config.relationships.contacts[contact].label, "value": value,
			"tier": str(tier.get("id", "")), "tier_label": str(tier.get("label", ""))})
	return rows

func choice_of(decision: String) -> String:
	return str(choices.get(decision, ""))

## Dry run of commit_choice: {ok, reason}. Changes nothing.
func choice_available(decision: String, option: String) -> Dictionary:
	if not enabled:
		return {"ok": false, "reason": "progression unavailable"}
	if not config.decisions.has(decision):
		return {"ok": false, "reason": "unknown decision"}
	var spec: Dictionary = config.decisions[decision]
	if not spec.options.has(option):
		return {"ok": false, "reason": "unknown option"}
	if not PlayMode.story_option_allowed(decision, option):
		return {"ok": false, "reason": "option retired"}
	if choices.has(decision):
		return {"ok": false, "reason": "already chosen"}
	var entry: Dictionary = spec.options[option]
	for earlier in entry.after:
		if choice_of(str(earlier)) != str(entry.after[earlier]):
			return {"ok": false, "reason": "earlier choice missing"}
	if not meets(entry.requires):
		return {"ok": false, "reason": "requirement not met"}
	return {"ok": true, "reason": ""}

## Records one durable option for a decision and applies its configured
## action atomically (all checks first; a refused action records nothing).
## A decision can never be chosen twice, so stale dialogue pays nothing.
func commit_choice(decision: String, option: String, context: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "decision": decision, "option": option, "reason": "", "deltas": {}, "relations": {}, "money": 0}
	var check := choice_available(decision, option)
	if not bool(check.ok):
		result.reason = str(check.reason)
		return result
	var entry: Dictionary = config.decisions[decision].options[option]
	var details := context.duplicate()
	details["source"] = "choice"
	var outcome := _apply_rule(str(entry.action), _slug(decision + "." + option, KEY_LIMIT), details, false)
	if not bool(outcome.ok):
		result.reason = str(outcome.reason)
		return result
	choices[decision] = option
	_record("choice:" + decision, option, outcome.deltas, int(outcome.money), str(entry.label))
	result.ok = true
	result.deltas = outcome.deltas
	result.relations = outcome.relations
	result.money = int(outcome.money)
	choice_made.emit(decision, option)
	changed.emit()
	return result

## Shared errand clock. "" asks only for readiness; a variant adds its payout,
## lock state and availability. Reading never changes state.
func errand_status(variant: String = "") -> Dictionary:
	var result := {"variant": variant, "label": "", "payout": 0, "ready": false, "unlocked": false, "available": false,
		"seconds_left": 0, "runs": errand_runs, "earned": errand_earned, "reason": ""}
	if not enabled:
		result.reason = "progression unavailable"
		return result
	var wait := _errand_wait()
	result.ready = wait <= 0.0
	result.seconds_left = ceili(wait)
	if variant.is_empty():
		return result
	if not config.errands.variants.has(variant):
		result.reason = "unknown errand"
		return result
	var spec: Dictionary = config.errands.variants[variant]
	result.label = str(spec.label)
	result.payout = int(spec.payout)
	result.unlocked = meets(spec.requires)
	result.available = bool(result.unlocked) and bool(result.ready)
	if not bool(result.unlocked):
		result.reason = "locked"
	elif not bool(result.ready):
		result.reason = "cooling down"
	return result

## Pays one finished errand. `run` must equal errand_runs (captured when the
## errand started) and the shared cooldown must have elapsed, so a replayed
## or duplicated completion can never pay twice. Returns {ok, paid, reason}.
func pay_errand(variant: String, run) -> Dictionary:
	var result := {"ok": false, "variant": variant, "paid": 0, "reason": "", "money": money}
	if not enabled:
		result.reason = "progression unavailable"
	elif not config.errands.variants.has(variant):
		result.reason = "unknown errand"
	elif not _is_integer(run, 0, MAX_SEQ) or int(run) != errand_runs:
		result.reason = "stale errand"
	elif _errand_wait() > 0.0:
		result.reason = "cooling down"
	if not str(result.reason).is_empty():
		return result
	var spec: Dictionary = config.errands.variants[variant]
	var before := money
	money += int(spec.payout)
	var paid := money - before
	errand_runs = mini(errand_runs + 1, int(config.limits.action_count))
	errand_earned = mini(errand_earned + paid, int(config.money.max))
	errand_ready_at = mini(ceili(_errand_now() + float(config.errands.cooldown)), MAX_READY_AT)
	_record("errand:" + variant, variant, {}, paid, str(spec.label))
	if paid > 0:
		money_changed.emit(money, paid, "errand")
	changed.emit()
	result.ok = true
	result.paid = paid
	result.money = money
	return result

## First matching authored contact line for an actor, or "".
func reaction_line(actor_id: String) -> String:
	if not enabled or actor_id.is_empty():
		return ""
	for rule in config.reactions:
		if not PlayMode.alignment_enabled() and _uses_alignment(str(rule.requires)):
			continue
		if actor_id in rule.actors and meets(rule.requires):
			return str(rule.line)
	return ""

## Saved play seconds when available, so the cooldown survives save/load.
func _errand_now() -> float:
	var clock = _manager("world_time")
	if clock != null:
		var seconds = clock.get("elapsed_seconds")
		if _is_number(seconds) and float(seconds) >= 0.0:
			return float(seconds)
	return _clock

## Never longer than one cooldown, even with an inconsistent saved clock.
func _errand_wait() -> float:
	if not enabled:
		return 0.0
	return clampf(float(errand_ready_at) - _errand_now(), 0.0, float(config.errands.cooldown))

## A clock that moved backwards (older slot, missing world_time) would otherwise
## hold the ready time out of reach; pull it to at most one cooldown away.
func _repair_errand_clock() -> void:
	if not enabled:
		return
	var limit := _errand_now() + float(config.errands.cooldown)
	if float(errand_ready_at) > limit + 1.0:
		errand_ready_at = mini(ceili(limit), MAX_READY_AT)

func _default_relationships() -> Dictionary:
	var result := {}
	var section = config.get("relationships", {})
	if not section is Dictionary:
		return result
	for contact in section.get("contact_order", []):
		result[str(contact)] = int(section.get("start", 0))
	return result

## Compact HUD line, e.g. "$500 · Snitch 12 Unknown · Gangsta 0 Unknown"
## ("$500" alone while alignment is disabled).
func hud_text() -> String:
	if not enabled:
		return "Progression unavailable"
	var parts := PackedStringArray(["$%d" % money])
	if not PlayMode.alignment_enabled():
		return parts[0]
	for track in config.track_order:
		var status := reputation_status(str(track))
		parts.append("%s %d %s" % [str(status.label), int(status.value), str(status.tier_label)])
	return " · ".join(parts)

func reputation_value(track: String) -> int:
	if not enabled or not config.tracks.has(track):
		return 0
	return int(reputation.get(track, config.tracks[track].start))

func tier_id(track: String) -> String:
	if not enabled or not config.tracks.has(track):
		return ""
	return str(_tier_for(config.tracks[track], reputation_value(track)).get("id", ""))

func reputation_status(track: String) -> Dictionary:
	if not enabled or not config.tracks.has(track):
		return {}
	var cfg: Dictionary = config.tracks[track]
	var value := reputation_value(track)
	var current := _tier_for(cfg, value)
	return {"track": track, "label": cfg.label, "value": value, "min": cfg.min, "max": cfg.max, "tier": str(current.get("id", "")),
		"tier_label": str(current.get("label", "")), "next_at": _next_threshold(cfg, value)}

# --- New game, persistence and migration -------------------------------------

## Fresh game only (no checkpoint): starter money and, when configured, the
## stricter starting inventory through combat.restore_equipment.
func begin_new_game(force := false) -> Dictionary:
	var result := {"ok": false, "equipment": false, "reason": ""}
	if not enabled:
		result.reason = "progression unavailable"
		return result
	if _session_loaded and not force:
		result.reason = "progress already loaded"
		return result
	_reset_state()
	_session_loaded = true
	var combat = _combat()
	if bool(config.new_game.strict) and combat != null and combat.has_method("equipment_snapshot") and combat.has_method("restore_equipment"):
		result.equipment = bool(combat.restore_equipment(starting_equipment(combat.equipment_snapshot())))
	_record("new_game", "", {}, 0, "Arrived in Pen Lucy with $%d" % money)
	result.ok = true
	changed.emit()
	return result

## Pure: a combat equipment snapshot in which only starter weapons stay owned.
func starting_equipment(snapshot: Dictionary) -> Dictionary:
	var weapons := {}
	var source = snapshot.get("weapons", {})
	if source is Dictionary:
		for id in source:
			var entry = source[id]
			var keep: bool = str(id) == "fists" or str(id) in config.new_game.weapons
			var ammo := int(entry.get("ammo", 0)) if keep and entry is Dictionary else 0
			var reserve := int(entry.get("reserve", 0)) if keep and entry is Dictionary else 0
			weapons[id] = {"owned": keep, "ammo": ammo, "reserve": reserve}
	var equipped := str(snapshot.get("equipped", "fists"))
	if not weapons.has(equipped) or not _is_true(weapons[equipped].owned):
		equipped = "fists"
	return {"version": int(snapshot.get("version", 1)), "equipped": equipped, "weapons": weapons}

## Stable, versioned and bounded; JSON-safe (ints, strings, sorted lists).
func snapshot_state() -> Dictionary:
	if not enabled:
		return {}
	var tracks := {}
	for track in config.track_order:
		tracks[track] = reputation_value(str(track))
	var goods := {}
	var bought := {}
	for id in config.items:
		if str(config.items[id].kind) == "goods":
			goods[id] = int(items.get(id, 0))
		if int(purchases.get(id, 0)) > 0:
			bought[id] = int(purchases[id])
	var counts := {}
	for id in config.actions:
		if int(action_counts.get(id, 0)) > 0:
			counts[id] = int(action_counts[id])
	var bonds := {}
	for contact in config.relationships.contact_order:
		bonds[contact] = relationship_value(str(contact))
	var picked := {}
	for decision in config.decision_order:
		if choices.has(decision):
			picked[decision] = str(choices[decision])
	return {"version": VERSION, "origin": origin, "money": money, "reputation": tracks, "items": goods, "purchases": bought,
		"weapons": _sorted_keys(weapons_purchased), "rewarded_cases": _sorted_keys(rewarded_cases), "once": _sorted_keys(_once),
		"flags": _sorted_keys(flags), "actions": counts, "history": history.duplicate(true), "seq": seq,
		"relationships": bonds, "choices": picked, "errands": {"runs": errand_runs, "ready_at": errand_ready_at, "earned": errand_earned}}

## "" when valid, otherwise a short reason. Strict: unknown or missing fields,
## wrong types, non-integers, nonfinite or out-of-range numbers, duplicates,
## unknown IDs and oversized lists are all rejected. Changes no game state.
func validate_state(data) -> String:
	last_validation_error = _validate_state(data)
	return last_validation_error

## All-or-nothing; replays no actions, rewards, signals other than changed.
func restore_state(data) -> bool:
	if not validate_state(data).is_empty():
		return false
	var state: Dictionary = data
	money = int(state.money)
	reputation = {}
	for track in config.track_order:
		reputation[track] = int(state.reputation.get(track, config.tracks[track].start))
	items = {}
	for id in config.items:
		if str(config.items[id].kind) == "goods":
			items[id] = int(state.items.get(id, 0))
	purchases = _int_map(state.purchases)
	action_counts = _int_map(state.actions)
	weapons_purchased = _set_of(state.weapons)
	rewarded_cases = _set_of(state.rewarded_cases)
	_once = _set_of(state.once)
	flags = _set_of(state.flags)
	history = []
	for entry in state.history:
		history.append(_normalized_entry(entry))
	seq = int(state.seq)
	origin = str(state.origin)
	# Version 1 predates relationships/choices/errands: neutral, none, ready.
	relationships = _default_relationships()
	choices = {}
	errand_runs = 0
	errand_ready_at = 0
	errand_earned = 0
	if int(state.version) >= 2:
		for contact in state.relationships:
			relationships[str(contact)] = int(state.relationships[contact])
		for decision in config.decision_order:
			if state.choices.has(decision):
				choices[decision] = str(state.choices[decision])
		errand_runs = int(state.errands.runs)
		errand_ready_at = int(state.errands.ready_at)
		errand_earned = int(state.errands.earned)
	_repair_errand_clock()
	_cooldowns.clear()
	_windows.clear()
	_session_loaded = true
	last_message = ""
	changed.emit()
	return true

## A checkpoint written before progression existed: starter wallet, and every
## completed case is marked rewarded so reward_case can never pay for it.
## config.migration may credit each case's reputation and/or money exactly once.
## Never touches combat (a legacy pistol stays owned).
func migrate_legacy(completed_ids: Array) -> Dictionary:
	var result := {"ok": false, "marked": [], "money": 0, "deltas": {}, "reason": ""}
	if not enabled:
		result.reason = "progression unavailable"
		return result
	if _session_loaded:
		result.reason = "progress already loaded"
		return result
	if completed_ids.size() > MAX_CASES:
		result.reason = "too many cases"
		return result
	for value in completed_ids:
		if not _is_id(value):
			result.reason = "invalid case id"
			return result
	_reset_state()
	origin = "legacy"
	_session_loaded = true
	var schema := _known_case_ids()
	var marked: Array = []
	var totals := {}
	var credited := 0
	for value in completed_ids:
		var id := str(value)
		if rewarded_cases.has(id) or (not schema.is_empty() and not schema.has(id)):
			continue
		rewarded_cases[id] = true
		marked.append(id)
		if bool(config.migration.credit_reputation):
			var outcome := _apply_rule(_case_action(id), id, {"source": "migration"}, false, true)
			for track in outcome.deltas:
				totals[track] = int(totals.get(track, 0)) + int(outcome.deltas[track])
		if bool(config.migration.credit_money):
			var definition = schema.get(id)
			credited += case_money(id, definition.get("reward", 0) if definition is Dictionary else 0)
	var before := money
	money += credited
	result.money = money - before
	_record("migration", "", totals, int(result.money), "Migrated %d completed cases" % marked.size())
	result.ok = true
	result.marked = marked
	result.deltas = totals
	changed.emit()
	return result

## After both missions and progression are restored: completed cases without a
## reward record (e.g. finished by an older build) are marked, never paid.
func reconcile_cases(completed_ids: Array) -> Array:
	var marked: Array = []
	if not enabled:
		return marked
	var schema := _known_case_ids()
	for value in completed_ids:
		if not _is_id(value) or rewarded_cases.has(value) or rewarded_cases.size() >= MAX_CASES:
			continue
		if not schema.is_empty() and not schema.has(value):
			continue
		rewarded_cases[str(value)] = true
		marked.append(str(value))
	if not marked.is_empty():
		_record("reconcile", "", {}, 0, "Marked %d completed cases as already rewarded" % marked.size())
		changed.emit()
	return marked

# --- Money and case rewards -----------------------------------------------------

## Fees (hospital, arrest...): takes what the player has and never goes below
## zero. Returns the dollars actually taken.
func debit(amount, reason: String = "fee") -> int:
	if not enabled or not _is_integer(amount, 1, int(config.money.max)):
		return 0
	var taken := mini(int(amount), money)
	if taken <= 0:
		return 0
	money -= taken
	_record("debit:" + _slug(reason, 48), "", {}, -taken, reason.left(160))
	money_changed.emit(money, -taken, reason)
	changed.emit()
	return taken

## Non-idempotent income for root-owned events; use reward_case or once-actions
## for anything that can replay. Returns dollars credited (capped at money.max).
func credit(amount, reason: String = "income") -> int:
	if not enabled or not _is_integer(amount, 1, int(config.money.max)):
		return 0
	var before := money
	money += int(amount)
	var added := money - before
	if added <= 0:
		return 0
	_record("credit:" + _slug(reason, 48), "", {}, added, reason.left(160))
	money_changed.emit(money, added, reason)
	changed.emit()
	return added

func can_afford(amount) -> bool:
	return enabled and _is_integer(amount, 0, MAX_SEQ) and int(amount) <= money

## Idempotent per case id: the first call pays `amount` dollars plus the case's
## configured reputation action. Every later call (also after save/load or a
## legacy migration) returns false and changes nothing.
func reward_case(id: String, amount) -> bool:
	if not enabled or not _is_id(id) or rewarded_cases.has(id) or rewarded_cases.size() >= MAX_CASES:
		return false
	if not _is_integer(amount, 0, int(config.cases.max_reward)):
		return false
	var schema := _known_case_ids()
	if not schema.is_empty() and not schema.has(id):
		return false
	rewarded_cases[id] = true
	var before := money
	money += int(amount)
	var paid := money - before
	var outcome := _apply_rule(_case_action(id), id, {"source": "case"}, false)
	var deltas: Dictionary = outcome.deltas
	_record("case:" + id, id, deltas, paid, "Case reward")
	if paid > 0:
		money_changed.emit(money, paid, "case")
	var text := "Case reward +$%d" % paid
	for track in deltas:
		text += " · %s %s" % [_track_label(str(track)), _signed(int(deltas[track]))]
	# Story parts whose effects come from the choice itself have nothing to add.
	if paid > 0 or not deltas.is_empty():
		notice.emit(text)
	changed.emit()
	return true

## Dollars for a case worth `points` community points (override, else the
## configured money_per_point).
func case_money(id: String, points = 0) -> int:
	if not enabled:
		return 0
	var overrides: Dictionary = config.cases.money_overrides
	if overrides.has(id):
		return int(overrides[id])
	if not _is_number(points) or float(points) < 0.0:
		return 0
	return clampi(roundi(float(points) * float(config.cases.money_per_point)), 0, int(config.cases.max_reward))

# --- Actions, offenses and dialogue hooks ----------------------------------------

## Applies one configured rule. context: key (scope for once/cooldown), witnessed
## (bool; omitted counts as witnessed), source. Returns {ok, action, reason,
## deltas, money}; check result.ok.
func apply_action(action_id: String, context: Dictionary = {}) -> Dictionary:
	return _apply_rule(action_id, _slug(str(context.get("key", "")), KEY_LIMIT), context, true)

## Signature-compatible with combat.player_offense(kind, at, victim_id).
## Offenses only ever feed street reputation, so with alignment disabled they
## are refused outright: no count, cooldown, history entry or reward.
func on_offense(kind: String, _at: Vector3 = Vector3.ZERO, victim_id: String = "", context: Dictionary = {}) -> Dictionary:
	if not PlayMode.alignment_enabled():
		return {"ok": false, "action": "", "reason": "alignment disabled", "deltas": {}, "money": 0}
	if not enabled or not config.offenses.has(kind):
		return {"ok": false, "action": "", "reason": "unmapped offense", "deltas": {}, "money": 0}
	var mapping: Dictionary = config.offenses[kind]
	var details := context.duplicate()
	details["offense"] = kind
	var key := _slug(victim_id, KEY_LIMIT) if str(mapping.key) == "victim" else ""
	return _apply_rule(str(mapping.action), key, details, true)

## Dialogue choice hook {"kind": "progression", "action": id, "once": key,
## "requires": expression, "replay": "block"|"pass"}. False keeps the
## conversation on its node, so stale or duplicate choices award nothing.
func commit_dialogue_action(hook: Dictionary) -> bool:
	if not enabled or str(hook.get("kind", "")) != "progression":
		return false
	var action_id := str(hook.get("action", ""))
	if not config.actions.has(action_id):
		return false
	var once_key := ""
	if hook.has("once"):
		once_key = _slug(str(hook.once), 80)
		if once_key.is_empty():
			return false
		if _once.has("hook:" + once_key):
			return str(hook.get("replay", "block")) == "pass"
		if _once.size() + 2 > int(config.limits.once_keys):
			return false
	var requires := str(hook.get("requires", ""))
	if not requires.is_empty() and not meets(requires):
		return false
	var outcome := _apply_rule(action_id, once_key, {"source": "dialogue"}, true)
	if not bool(outcome.ok):
		return false
	if not once_key.is_empty():
		_once["hook:" + once_key] = true
		changed.emit()
	return true

# --- Requirements, unlocks and perception -----------------------------------------

## Authored requirement: an expression (grammar in the progression report) or a
## list of expressions that must all hold. "" is always met; invalid never is.
func meets(requirement) -> bool:
	if not enabled:
		return false
	if requirement is Array:
		for part in requirement:
			if part is Array or not meets(part):
				return false
		return true
	var text := str(requirement).strip_edges()
	if text.is_empty():
		return true
	var node := _requirement(text)
	if node.is_empty():
		return false
	if not PlayMode.alignment_enabled():
		node = _without_alignment(node, 0)
		if node.is_empty():
			return true
	return _evaluate(node, 0)

## Empty means only alignment was required, including under NOT. Mixed
## expressions keep their remaining money/flag/relationship conditions.
func _without_alignment(node: Array, depth: int) -> Array:
	if node.is_empty() or depth > MAX_DEPTH:
		return ["bool", false]
	match str(node[0]):
		"track", "tier":
			return []
		"not":
			var child := _without_alignment(node[1], depth + 1)
			return [] if child.is_empty() else ["not", child]
		"and", "or":
			var left := _without_alignment(node[1], depth + 1)
			var right := _without_alignment(node[2], depth + 1)
			if left.is_empty():
				return right
			if right.is_empty():
				return left
			return [node[0], left, right]
		"unlock":
			var spec: Dictionary = config.unlocks.get(str(node[1]), {})
			if spec.is_empty():
				return ["bool", false]
			var required := str(spec.requires).strip_edges()
			return ["bool", true] if required.is_empty() else _without_alignment(_requirement(required), depth + 1)
	return node

## Alignment-derived prices and social labels disappear instead of becoming
## unconditional when requirements no longer restrict access to content.
func _uses_alignment(requirement: String) -> bool:
	return _node_uses_alignment(_requirement(requirement), 0)

func _node_uses_alignment(node: Array, depth: int) -> bool:
	if node.is_empty():
		return false
	if depth > MAX_DEPTH:
		return true
	match str(node[0]):
		"track", "tier":
			return true
		"not":
			return _node_uses_alignment(node[1], depth + 1)
		"and", "or":
			return _node_uses_alignment(node[1], depth + 1) or _node_uses_alignment(node[2], depth + 1)
		"unlock":
			var spec: Dictionary = config.unlocks.get(str(node[1]), {})
			return not spec.is_empty() and _node_uses_alignment(_requirement(str(spec.requires)), depth + 1)
	return false

## True when `key` parses as a progression expression, so a dialogue host can
## route it here and keep plain authored flags in its own table.
func handles_condition(key) -> bool:
	if not enabled or not key is String:
		return false
	var text: String = key
	text = text.strip_edges()
	return not text.is_empty() and not _requirement(text).is_empty()

## "" for a valid expression, otherwise why it does not parse (authoring aid).
func requirement_error(text: String) -> String:
	if not enabled:
		return "progression unavailable"
	return "" if not _compile(text, config).is_empty() else _parse_error

func is_unlocked(id: String) -> bool:
	return enabled and config.unlocks.has(id) and meets(config.unlocks[id].requires)

func unlock_status() -> Array:
	var result: Array = []
	if not enabled:
		return result
	for id in config.unlocks:
		result.append({"id": id, "label": config.unlocks[id].label, "requires": config.unlocks[id].requires, "unlocked": is_unlocked(str(id))})
	return result

## World perception for an observer ROLE. The context is accepted for authored
## callers, but nothing about anyone's appearance or identity is consulted.
func perceive(role: String, _context: Dictionary = {}) -> Dictionary:
	var result := {"role": role, "attitude": "neutral", "label": "", "line": "", "rule": "", "tags": _tags()}
	if not enabled:
		return result
	for rule in config.perception:
		if not PlayMode.alignment_enabled() and _uses_alignment(str(rule.requires)):
			continue
		if not role in rule.roles and not "*" in rule.roles:
			continue
		if not meets(rule.requires):
			continue
		result.attitude = str(rule.attitude)
		result.label = str(rule.label)
		result.line = str(rule.line)
		result.rule = str(rule.id)
		break
	return result

func perceive_actor(actor_id: String) -> Dictionary:
	return perceive(role_for_actor(actor_id))

func perception_line(role: String) -> String:
	return str(perceive(role).line)

func role_for_actor(actor_id: String) -> String:
	if not enabled:
		return "neighbor"
	var roles: Dictionary = config.actor_roles
	if roles.actors.has(actor_id):
		return str(roles.actors[actor_id])
	for entry in roles.prefixes:
		if actor_id.begins_with(str(entry[0])):
			return str(entry[1])
	return str(roles.default)

## Pure copy of an authored conversation with the role's perception line spoken
## first, then the contact's authored reaction line when graph.actor_id has one
## (graphs marked "reactions": false skip it). Authored lines stay verbatim and
## in order; nothing is replaced.
func decorate_conversation(graph: Dictionary, role: String) -> Dictionary:
	var result := graph.duplicate(true)
	var spoken: Array = []
	var line := perception_line(role)
	if not line.is_empty():
		spoken.append(line)
	if not _is_false(result.get("reactions", true)):
		var reaction := reaction_line(str(result.get("actor_id", "")))
		if not reaction.is_empty() and reaction != line:
			spoken.append(reaction)
	var nodes = result.get("nodes")
	var start := str(result.get("start", "start"))
	if spoken.is_empty() or not nodes is Dictionary or not nodes.get(start) is Dictionary:
		return result
	var entry: Dictionary = nodes[start]
	var lines = entry.get("lines", [])
	if not lines is Array:
		return result
	spoken.append_array(lines)
	entry["lines"] = spoken
	return result

func dialogue_example(id: String) -> Dictionary:
	if not enabled or not config.dialogue_examples.has(id) or not PlayMode.dialogue_example_allowed(id):
		return {}
	return config.dialogue_examples[id].duplicate(true)

# --- Shops ---------------------------------------------------------------------

func item_ids(shop_kind: String) -> Array:
	if not enabled or not config.shops.has(shop_kind):
		return []
	return config.shops[shop_kind].items.duplicate()

## Stock for a walk-in shop kind ("gun" or "weed") in authored order. Entries:
## id, label, description, price (after reputation modifiers), base_price,
## percent, modifiers, owned, repeatable, available, reason, locked, count.
func catalog(shop_kind: String) -> Array:
	var result: Array = []
	if not enabled or not config.shops.has(shop_kind) or not PlayMode.shop_kind_open(shop_kind):
		return result
	var gate := purchase_gate()
	var weapons := _equipment_weapons()
	for item_id in config.shops[shop_kind].items:
		result.append(_catalog_entry(str(item_id), gate, weapons))
	return result

## Effective price after reputation modifiers (sum clamped to pricing limits).
func price_quote(item_id: String) -> Dictionary:
	var quote := {"price": 0, "base": 0, "percent": 0, "modifiers": []}
	if not enabled or not config.items.has(item_id):
		return quote
	var item: Dictionary = config.items[item_id]
	var percent := 0
	var applied: Array = []
	for modifier in config.pricing.modifiers:
		if not PlayMode.alignment_enabled() and _uses_alignment(str(modifier.requires)):
			continue
		if str(item.shop) in modifier.shops and meets(modifier.requires):
			percent += int(modifier.percent)
			applied.append({"id": str(modifier.id), "label": str(modifier.label), "percent": int(modifier.percent)})
	percent = clampi(percent, int(config.pricing.min_percent), int(config.pricing.max_percent))
	quote.base = int(item.price)
	quote.percent = percent
	quote.modifiers = applied
	quote.price = maxi(0, roundi(float(item.price) * float(100 + percent) / 100.0))
	return quote

## Why the player cannot shop right now. Reads world state only. A modal pause
## from the shop UI itself is deliberately not a gate.
func purchase_gate() -> Dictionary:
	if not enabled:
		return {"ok": false, "reason": "The register is closed right now."}
	var gates: Dictionary = config.gates
	var combat = _combat()
	if combat != null:
		var health = combat.get("health")
		if bool(gates.block_downed) and (_positive(combat.get("downed")) or (_is_number(health) and float(health) <= 0.0)):
			return {"ok": false, "reason": "You're in no shape to shop right now."}
		if bool(gates.block_combat) and combat.has_method("get_status"):
			var fight = combat.get_status()
			if fight is Dictionary and _positive(fight.get("aggro_count", 0)):
				return {"ok": false, "reason": "Not while someone is squaring up to you."}
	if bool(gates.block_driving) and _positive_flag(_manager("driving"), "active"):
		return {"ok": false, "reason": "Park and step inside first."}
	var law = _manager("law")
	if bool(gates.block_recovering) and _positive_flag(law, "recovering"):
		return {"ok": false, "reason": "Get yourself sorted out first."}
	if bool(gates.block_wanted) and _positive_flag(law, "wanted"):
		return {"ok": false, "reason": "The clerk won't serve you while the police are looking for you."}
	var shops = _manager("shops")
	if bool(gates.require_open_shop) and shops != null and shops.has_method("is_open") and not bool(shops.is_open()):
		return {"ok": false, "reason": "Visit a shop counter first."}
	return {"ok": true, "reason": ""}

## Atomic: every check runs before anything changes, combat effects are verified
## and rolled back on mismatch, money never goes negative and an owned or
## already-paid weapon is never charged again. Returns {ok, message, price, money}.
func purchase(item_id: String, context: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "message": "", "item": item_id, "price": 0, "money": money, "reissued": false}
	if not enabled:
		result.message = "The register is closed right now."
	elif not config.items.has(item_id):
		result.message = "That isn't for sale here."
	elif context.has("shop_kind") and str(context.shop_kind) != str(config.items[item_id].shop):
		result.message = "This shop doesn't stock that."
	elif not PlayMode.item_kind_sellable(str(config.items[item_id].kind)) or not PlayMode.shop_kind_open(str(config.items[item_id].shop)):
		result.message = "That counter is closed."
	else:
		var gate := purchase_gate()
		var item: Dictionary = config.items[item_id]
		var quote := price_quote(item_id)
		if not bool(gate.ok):
			result.message = str(gate.reason)
		else:
			match str(item.kind):
				"weapon":
					_buy_weapon(item, quote, result)
				"ammo":
					_buy_ammo(item, quote, result)
				_:
					_buy_goods(item, quote, result)
	result.money = money
	last_message = str(result.message)
	return result

func item_count(id: String) -> int:
	return int(items.get(id, 0))

## Authored hand-over/consumption hook (no use mechanics). Atomic.
func remove_item(id: String, count = 1, reason: String = "handed over") -> bool:
	if not enabled or not items.has(id) or not _is_integer(count, 1, int(config.limits.stack)) or int(items[id]) < int(count):
		return false
	items[id] = int(items[id]) - int(count)
	_record("remove:" + id, id, {}, 0, reason.left(160))
	changed.emit()
	return true

## Readable recent history, newest first, for a ledger panel.
func history_lines(limit := 8) -> Array:
	var lines: Array = []
	for index in range(history.size() - 1, -1, -1):
		if lines.size() >= limit:
			break
		var entry: Dictionary = history[index]
		var parts := PackedStringArray([str(entry.note)])
		if PlayMode.alignment_enabled():
			for track in entry.deltas:
				parts.append("%s %s" % [_track_label(str(track)), _signed(int(entry.deltas[track]))])
		var dollars := int(entry.money)
		if dollars != 0:
			parts.append(("+$%d" % dollars) if dollars > 0 else ("-$%d" % -dollars))
		lines.append(" · ".join(parts))
	return lines

# --- Purchase internals ---------------------------------------------------------

func _buy_weapon(item: Dictionary, quote: Dictionary, result: Dictionary) -> void:
	var combat = _combat()
	var weapon := str(item.weapon)
	var label := str(item.label)
	var price := int(quote.price)
	if combat == null or not combat.has_method("grant_weapon") or not combat.has_method("equipment_snapshot"):
		result.message = "The clerk can't hand over weapons right now."
		return
	if _combat_owns(weapon):
		result.message = "You already own the %s." % label
		return
	var reissue := weapons_purchased.has(str(item.id))
	if not reissue and not meets(item.requires):
		result.message = _locked_text(item)
		return
	if not reissue and money < price:
		result.message = "You need $%d more for the %s." % [price - money, label]
		return
	var before: Dictionary = combat.equipment_snapshot()
	if not bool(combat.grant_weapon(weapon)):
		result.message = "The clerk can't hand over the %s right now." % label
		return
	var rounds := int(item.rounds)
	if not reissue and rounds > 0 and int(combat.add_ammo(weapon, rounds)) != rounds:
		_rollback(combat, before)
		result.message = "The clerk can't load the %s right now." % label
		return
	if not _combat_owns(weapon):
		_rollback(combat, before)
		result.message = "The clerk can't hand over the %s right now." % label
		return
	result.ok = true
	if reissue:
		result.reissued = true
		result.message = "Already paid for. The clerk hands back your %s." % label
		_record("reissue:" + str(item.id), str(item.id), {}, 0, "Collected a weapon already paid for")
		changed.emit()
		return
	money -= price
	purchases[str(item.id)] = mini(int(purchases.get(str(item.id), 0)) + 1, int(config.limits.purchase_count))
	weapons_purchased[str(item.id)] = true
	var deltas := {}
	if not str(item.action).is_empty():
		deltas = _apply_rule(str(item.action), str(item.id), {"source": "purchase"}, false).deltas
	result.price = price
	result.message = "Bought the %s for $%d%s." % [label, price, _modifier_suffix(quote)]
	if not str(item.hint).is_empty():
		result.message += " " + str(item.hint)
	_record("purchase:" + str(item.id), str(item.id), deltas, -price, "Bought the " + label)
	money_changed.emit(money, -price, "purchase")
	changed.emit()

func _buy_ammo(item: Dictionary, quote: Dictionary, result: Dictionary) -> void:
	var combat = _combat()
	var weapon := str(item.weapon)
	var rounds := int(item.rounds)
	var price := int(quote.price)
	if combat == null or not combat.has_method("add_ammo") or not combat.has_method("equipment_snapshot"):
		result.message = "Ammunition can't be supplied right now."
		return
	var before: Dictionary = combat.equipment_snapshot()
	var weapons = before.get("weapons")
	var state = weapons.get(weapon) if weapons is Dictionary else null
	if not state is Dictionary:
		result.message = "Ammunition can't be supplied right now."
		return
	if bool(item.requires_owned) and not _is_true(state.get("owned")):
		result.message = "Buy the %s first." % _weapon_label(weapon)
		return
	if not meets(item.requires):
		result.message = _locked_text(item)
		return
	var reserve := int(state.get("reserve", 0))
	if reserve + rounds > _max_reserve():
		result.message = "You can't carry any more %s ammunition." % _weapon_label(weapon)
		return
	if money < price:
		result.message = "You need $%d more." % (price - money)
		return
	var added := int(combat.add_ammo(weapon, rounds))
	if added != rounds:
		if added > 0:
			_rollback(combat, before)
		result.message = "Ammunition can't be supplied right now."
		return
	money -= price
	purchases[str(item.id)] = mini(int(purchases.get(str(item.id), 0)) + 1, int(config.limits.purchase_count))
	result.ok = true
	result.price = price
	result.message = "Bought %d %s rounds for $%d%s. Reserve %d." % [rounds, _weapon_label(weapon), price, _modifier_suffix(quote), reserve + rounds]
	_record("purchase:" + str(item.id), str(item.id), {}, -price, "Bought " + str(item.label).to_lower())
	money_changed.emit(money, -price, "purchase")
	changed.emit()

func _buy_goods(item: Dictionary, quote: Dictionary, result: Dictionary) -> void:
	var id := str(item.id)
	var quantity := int(item.quantity)
	var price := int(quote.price)
	var count := int(items.get(id, 0))
	if not meets(item.requires):
		result.message = _locked_text(item)
		return
	if count + quantity > int(item.max):
		result.message = "Your stash is full."
		return
	if money < price:
		result.message = "You need $%d more." % (price - money)
		return
	money -= price
	items[id] = count + quantity
	purchases[id] = mini(int(purchases.get(id, 0)) + 1, int(config.limits.purchase_count))
	result.ok = true
	result.price = price
	result.message = "Bought %s for $%d%s. %d in your stash." % [str(item.label).to_lower(), price, _modifier_suffix(quote), count + quantity]
	_record("purchase:" + id, id, {}, -price, "Bought " + str(item.label).to_lower())
	money_changed.emit(money, -price, "purchase")
	changed.emit()

func _catalog_entry(item_id: String, gate: Dictionary, weapons: Dictionary) -> Dictionary:
	var item: Dictionary = config.items[item_id]
	var quote := price_quote(item_id)
	var kind := str(item.kind)
	var entry := {"id": item_id, "shop": item.shop, "kind": kind, "label": item.label, "price": int(quote.price),
		"base_price": int(quote.base), "percent": int(quote.percent), "modifiers": quote.modifiers, "owned": false,
		"repeatable": kind != "weapon", "available": true, "reason": "", "locked": false, "reissue": false, "count": 0,
		"weapon": item.weapon, "rounds": int(item.rounds), "quantity": int(item.quantity), "requires": item.requires}
	var reason := ""
	var state = weapons.get(str(item.weapon))
	if kind == "weapon":
		entry.owned = state is Dictionary and _is_true(state.get("owned"))
		if weapons.is_empty():
			reason = "Weapons can't be issued right now."
		elif not entry.owned and weapons_purchased.has(item_id):
			entry.price = 0
			entry.reissue = true
	elif kind == "ammo":
		entry.count = int(state.get("reserve", 0)) if state is Dictionary else 0
		if not state is Dictionary:
			reason = "Ammunition can't be supplied right now."
		elif bool(item.requires_owned) and not _is_true(state.get("owned")):
			reason = "Buy the %s first." % _weapon_label(str(item.weapon))
		elif int(entry.count) + int(item.rounds) > _max_reserve():
			reason = "Reserve full."
	else:
		entry.count = int(items.get(item_id, 0))
		if int(entry.count) + int(item.quantity) > int(item.max):
			reason = "Stash full."
	if reason.is_empty() and not entry.owned and not entry.reissue and not meets(item.requires):
		reason = _locked_text(item)
		entry.locked = true
	if reason.is_empty() and not entry.owned and not bool(gate.ok):
		reason = str(gate.reason)
	var parts := PackedStringArray()
	if not str(item.description).is_empty():
		parts.append(str(item.description))
	if entry.reissue:
		parts.append("Already paid for: collect it free.")
	elif not quote.modifiers.is_empty():
		parts.append(_modifier_text(quote.modifiers))
	if not reason.is_empty():
		entry.available = false
		entry.reason = reason
		parts.append(reason)
	entry.description = " · ".join(parts)
	return entry

func _rollback(combat, before: Dictionary) -> void:
	if combat.has_method("restore_equipment"):
		combat.restore_equipment(before)

func _combat_owns(weapon: String) -> bool:
	var state = _equipment_weapons().get(weapon)
	return state is Dictionary and _is_true(state.get("owned"))

func _equipment_weapons() -> Dictionary:
	var combat = _combat()
	if combat == null or not combat.has_method("equipment_snapshot"):
		return {}
	var snapshot = combat.equipment_snapshot()
	if not snapshot is Dictionary or not snapshot.get("weapons") is Dictionary:
		return {}
	return snapshot.weapons

## Combat's shared weapon table (read-only); falls back if it moves.
func _weapon_constant(constant: String):
	if not ResourceLoader.exists(WEAPONS_PATH):
		return null
	var weapons_script = load(WEAPONS_PATH)
	return weapons_script.get_script_constant_map().get(constant) if weapons_script is Script else null

func _max_reserve() -> int:
	var value = _weapon_constant("MAX_RESERVE")
	return int(value) if _is_integer(value, 0, MAX_SEQ) else 9999

func _weapon_profiles() -> Dictionary:
	var profiles = _weapon_constant("PROFILES")
	return profiles if profiles is Dictionary else {}

func _locked_text(item: Dictionary) -> String:
	return str(item.locked) if not str(item.locked).is_empty() else "Not available to you yet."

func _modifier_text(modifiers: Array) -> String:
	var parts := PackedStringArray()
	for modifier in modifiers:
		parts.append("%s %s%%" % [str(modifier.label), _signed(int(modifier.percent))])
	return ", ".join(parts)

func _modifier_suffix(quote: Dictionary) -> String:
	return "" if quote.modifiers.is_empty() else " (%s)" % _modifier_text(quote.modifiers)

func _weapon_label(weapon: String) -> String:
	for id in config.items:
		var item: Dictionary = config.items[id]
		if str(item.kind) == "weapon" and str(item.weapon) == weapon:
			return str(item.label)
	return weapon.capitalize()

func _track_label(track: String) -> String:
	return str(config.tracks[track].label) if config.tracks.has(track) else track.capitalize()

# --- Rule engine ------------------------------------------------------------------

## Checks everything first, then commits. `silent` (migration) emits nothing.
func _apply_rule(action_id: String, key: String, context: Dictionary, record: bool, silent := false) -> Dictionary:
	var result := {"ok": false, "action": action_id, "reason": "", "deltas": {}, "relations": {}, "money": 0}
	if not enabled or not config.actions.has(action_id):
		result.reason = "unknown action"
		return result
	var rule: Dictionary = config.actions[action_id]
	var once_id := action_id if key.is_empty() else action_id + ":" + key
	var scope := action_id + "|" + key
	var window: Array = []
	var new_flags := 0
	for flag in rule.set_flags:
		if not flags.has(flag):
			new_flags += 1
	if bool(rule.requires_witness) and context.has("witnessed") and not _is_true(context.witnessed):
		result.reason = "unwitnessed"
	elif not meets(rule.requires):
		result.reason = "requirement not met"
	elif bool(rule.once) and _once.has(once_id):
		result.reason = "already applied"
	elif bool(rule.once) and (_once.size() >= int(config.limits.once_keys) or once_id.length() > ONCE_LIMIT):
		result.reason = "once ledger full"
	elif int(rule.limit) > 0 and int(action_counts.get(action_id, 0)) >= int(rule.limit):
		result.reason = "limit reached"
	elif float(rule.cooldown) > 0.0 and _cooldowns.has(scope) and _clock - float(_cooldowns[scope]) < float(rule.cooldown):
		result.reason = "cooling down"
	elif int(rule.money) < 0 and money + int(rule.money) < 0:
		result.reason = "insufficient funds"
	elif flags.size() + new_flags > int(config.limits.flags):
		result.reason = "flag ledger full"
	if str(result.reason).is_empty() and int(rule.window_max) > 0:
		for stamp in _windows.get(action_id, []):
			if _clock - float(stamp) < float(rule.window_seconds):
				window.append(stamp)
		_windows[action_id] = window
		if window.size() >= int(rule.window_max):
			result.reason = "rate limited"
	if str(result.reason).is_empty():
		for item_id in rule.items:
			var after_count := int(items.get(item_id, 0)) + int(rule.items[item_id])
			if after_count < 0 or after_count > int(config.items[item_id].max):
				result.reason = "inventory unavailable"
				break
	if not str(result.reason).is_empty():
		return result
	var applied := {}
	var tier_notices := PackedStringArray()
	# Alignment disabled: the rest of the rule (money, relationships, flags,
	# items, once/limit bookkeeping) still applies; the tracks stay put.
	var track_deltas: Dictionary = rule.deltas if PlayMode.alignment_enabled() else {}
	for track in track_deltas:
		var cfg: Dictionary = config.tracks[track]
		var before := int(reputation.get(track, cfg.start))
		var after := clampi(before + int(track_deltas[track]), int(cfg.min), int(cfg.max))
		reputation[track] = after
		if after == before:
			continue
		applied[track] = after - before
		var new_tier := _tier_for(cfg, after)
		if str(_tier_for(cfg, before).get("id", "")) != str(new_tier.get("id", "")):
			tier_notices.append("%s reputation: %s" % [str(cfg.label), str(new_tier.get("label", ""))])
	var bonds := {}
	var bond_cfg: Dictionary = config.relationships
	for contact in rule.relations:
		var was := relationship_value(str(contact))
		var now := clampi(was + int(rule.relations[contact]), int(bond_cfg.min), int(bond_cfg.max))
		relationships[contact] = now
		if now == was:
			continue
		bonds[contact] = now - was
		var bond_tier := _tier_for(bond_cfg, now)
		if str(_tier_for(bond_cfg, was).get("id", "")) != str(bond_tier.get("id", "")):
			tier_notices.append("%s: %s" % [str(bond_cfg.contacts[contact].label), str(bond_tier.get("label", ""))])
	var before_money := money
	money += int(rule.money)
	var paid := money - before_money
	for item_id in rule.items:
		items[item_id] = int(items.get(item_id, 0)) + int(rule.items[item_id])
	for flag in rule.set_flags:
		flags[flag] = true
	for flag in rule.clear_flags:
		flags.erase(flag)
	if bool(rule.once):
		_once[once_id] = true
	if float(rule.cooldown) > 0.0:
		_cooldowns[scope] = _clock
		_prune_cooldowns()
	if int(rule.window_max) > 0:
		window.append(_clock)
		_windows[action_id] = window
	action_counts[action_id] = mini(int(action_counts.get(action_id, 0)) + 1, int(config.limits.action_count))
	result.ok = true
	result.deltas = applied
	result.relations = bonds
	result.money = paid
	if record:
		_record(action_id, key, applied, paid, str(rule.label))
	if silent:
		return result
	for track in applied:
		reputation_changed.emit(str(track), int(reputation[track]), tier_id(str(track)))
	for contact in bonds:
		relationship_changed.emit(str(contact), relationship_value(str(contact)), relationship_tier(str(contact)))
	if paid != 0:
		money_changed.emit(money, paid, action_id)
	for text in tier_notices:
		notice.emit(text)
	if not str(rule.notice).is_empty():
		notice.emit(str(rule.notice))
	changed.emit()
	return result

func _prune_cooldowns() -> void:
	var limit := int(config.limits.cooldown_entries)
	if _cooldowns.size() <= limit:
		return
	var longest := 0.0
	for id in config.actions:
		longest = maxf(longest, float(config.actions[id].cooldown))
	for scope in _cooldowns.keys():
		if _clock - float(_cooldowns[scope]) >= longest:
			_cooldowns.erase(scope)
	while _cooldowns.size() > limit:
		var oldest = _cooldowns.keys()[0]
		for candidate in _cooldowns:
			if float(_cooldowns[candidate]) < float(_cooldowns[oldest]):
				oldest = candidate
		_cooldowns.erase(oldest)

func _record(action: String, key: String, deltas: Dictionary, money_delta: int, note: String) -> void:
	seq = mini(seq + 1, MAX_SEQ)
	history.append({"seq": seq, "action": _slug(action, KEY_LIMIT), "key": _slug(key, KEY_LIMIT), "deltas": deltas.duplicate(),
		"money": money_delta, "minute": _world_minute(), "note": note.left(160)})
	while history.size() > int(config.limits.history):
		history.pop_front()

func _reset_state() -> void:
	money = int(config.money.starting) if enabled else 0
	reputation = {}
	items = {}
	for track in config.get("track_order", []):
		reputation[track] = int(config.tracks[track].start)
	for id in config.get("items", {}):
		if str(config.items[id].kind) == "goods":
			items[id] = 0
	purchases = {}
	weapons_purchased = {}
	rewarded_cases = {}
	flags = {}
	action_counts = {}
	history = []
	relationships = _default_relationships()
	choices = {}
	errand_runs = 0
	errand_ready_at = 0
	errand_earned = 0
	_once = {}
	_cooldowns = {}
	_windows = {}
	origin = "new"
	seq = 0
	last_message = ""

func _case_action(id: String) -> String:
	return str(config.cases.actions.get(id, config.cases.default_action))

func _tags() -> Array:
	var tags: Array = []
	if enabled and PlayMode.alignment_enabled():
		for track in config.track_order:
			tags.append("%s:%s" % [str(track), _gate_tier(str(track))])
	return tags

## Raw backend value. Disabled-mode access checks remove alignment predicates
## before evaluation; stored values remain intact for saves and future builds.
func _gate_track_value(track: String) -> int:
	return reputation_value(track)

func _gate_tier(track: String) -> String:
	if not enabled or not config.tracks.has(track):
		return ""
	return str(_tier_for(config.tracks[track], _gate_track_value(track)).get("id", ""))

func _tier_for(track_cfg: Dictionary, value: int) -> Dictionary:
	var found: Dictionary = {}
	for tier in track_cfg.get("tiers", []):
		if value >= int(tier.at):
			found = tier
	return found

func _next_threshold(track_cfg: Dictionary, value: int) -> int:
	for tier in track_cfg.get("tiers", []):
		if int(tier.at) > value:
			return int(tier.at)
	return -1

func _tier_index(track_cfg: Dictionary, wanted: String) -> int:
	var tiers: Array = track_cfg.get("tiers", [])
	for index in tiers.size():
		if str(tiers[index].id) == wanted:
			return index
	return -1

func _world_minute() -> int:
	var clock = _manager("world_time")
	if clock == null:
		return -1
	var minutes = clock.get("total_minutes")
	if not _is_number(minutes) or float(minutes) < 0.0:
		return -1
	return mini(floori(float(minutes)), 1000000000)

func _manager(property: String):
	if level == null:
		return null
	var value = level.get(property)
	return value if is_instance_valid(value) else null

func _combat():
	return _manager("combat")

func _known_case_ids() -> Dictionary:
	var missions = _manager("missions")
	if missions == null or not missions.has_method("save_schema"):
		return {}
	var schema = missions.save_schema()
	return schema if schema is Dictionary else {}

func _positive_flag(node, property: String) -> bool:
	if node == null:
		return false
	if _positive(node.get(property)):
		return true
	if node.has_method("get_status"):
		var status = node.get_status()
		return status is Dictionary and _positive(status.get(property))
	return false

# --- Requirement expressions ------------------------------------------------------

func _requirement(text: String) -> Array:
	if _compiled.has(text):
		return _compiled[text]
	var node := _compile(text, config)
	if _compiled.size() >= 512:
		_compiled.clear()
	_compiled[text] = node
	return node

func _compile(text: String, cfg: Dictionary) -> Array:
	_parse_cfg = cfg
	_parse_index = 0
	_parse_error = ""
	var source := text.strip_edges().to_lower()
	if source.is_empty() or source.length() > MAX_REQUIREMENT:
		_parse_error = "requirement is empty or longer than %d characters" % MAX_REQUIREMENT
		return []
	_parse_tokens = _tokenize(source)
	var node := _parse_or(0)
	if _parse_error.is_empty() and _parse_index < _parse_tokens.size():
		_parse_error = "unexpected '%s'" % str(_parse_tokens[_parse_index])
	return node if _parse_error.is_empty() else []

func _tokenize(source: String) -> Array:
	var spaced := _operator_spacing.sub(source.replace("\t", " ").replace("\n", " "), "$1", true)
	spaced = spaced.replace("(", " ( ").replace(")", " ) ")
	var tokens: Array = []
	for part in spaced.split(" ", false):
		tokens.append(part)
	return tokens

func _peek() -> String:
	return str(_parse_tokens[_parse_index]) if _parse_index < _parse_tokens.size() else ""

func _parse_or(depth: int) -> Array:
	var left := _parse_and(depth)
	while _parse_error.is_empty() and _peek() == "or":
		_parse_index += 1
		left = ["or", left, _parse_and(depth)]
	return left

func _parse_and(depth: int) -> Array:
	var left := _parse_not(depth)
	while _parse_error.is_empty() and _peek() == "and":
		_parse_index += 1
		left = ["and", left, _parse_not(depth)]
	return left

func _parse_not(depth: int) -> Array:
	if depth > MAX_DEPTH:
		_parse_error = "requirement nests too deeply"
		return []
	if _peek() == "not":
		_parse_index += 1
		return ["not", _parse_not(depth + 1)]
	return _parse_primary(depth)

func _parse_primary(depth: int) -> Array:
	if not _parse_error.is_empty():
		return []
	if _parse_index >= _parse_tokens.size():
		_parse_error = "requirement ends early"
		return []
	var token := str(_parse_tokens[_parse_index])
	_parse_index += 1
	if token == "(":
		var inner := _parse_or(depth + 1)
		if _parse_error.is_empty() and _peek() != ")":
			_parse_error = "missing ')'"
		_parse_index += 1
		return inner
	if token in [")", "and", "or", "not"]:
		_parse_error = "unexpected '%s'" % token
		return []
	return _parse_atom(token)

## subject OP value, where subject is a track, money, a goods item or
## rel:<contact> and value is a whole number or (for tracks and relationships)
## a tier id: "gangsta>=respected", "rel:ines>=friendly".
func _parse_atom(token: String) -> Array:
	if token == "true" or token == "false":
		return ["bool", token == "true"]
	var op := ""
	var at := -1
	for candidate in OPERATORS:
		at = token.find(candidate)
		if at >= 0:
			op = candidate
			break
	if op.is_empty():
		return _parse_prefixed(token)
	var subject := token.substr(0, at)
	var value_text := token.substr(at + op.length())
	var contact := subject.trim_prefix("rel:") if subject.begins_with("rel:") else ""
	var bonds: Dictionary = _parse_cfg.get("relationships", {})
	var value := 0
	if value_text.is_valid_int() and absi(value_text.to_int()) <= 1000000000:
		value = value_text.to_int()
	elif _parse_cfg.tracks.has(subject) and _tier_index(_parse_cfg.tracks[subject], value_text) >= 0:
		value = int(_parse_cfg.tracks[subject].tiers[_tier_index(_parse_cfg.tracks[subject], value_text)].at)
	elif not contact.is_empty() and _tier_index(bonds, value_text) >= 0:
		value = int(bonds.tiers[_tier_index(bonds, value_text)].at)
	else:
		_parse_error = "'%s' needs a whole number or a tier id after the operator" % token
		return []
	if _parse_cfg.tracks.has(subject):
		return ["track", subject, op, value]
	if not contact.is_empty():
		if bonds.get("contacts", {}).has(contact):
			return ["rel", contact, op, value]
		_parse_error = "unknown relationship contact '%s'" % contact
		return []
	if subject == "money":
		return ["money", "", op, value]
	if _parse_cfg.items.has(subject) and str(_parse_cfg.items[subject].kind) == "goods":
		return ["count", subject, op, value]
	_parse_error = "unknown requirement subject '%s'" % subject
	return []

## owns:<weapon> has:<goods> bought:<item> case:<id> flag:<id> used:<hook once
## key> unlock:<id> tier:<track>:<tier> choice:<decision>[:<option>]
func _parse_prefixed(token: String) -> Array:
	var colon := token.find(":")
	var prefix := token.substr(0, colon) if colon > 0 else ""
	var rest := token.substr(colon + 1) if colon > 0 else ""
	match prefix:
		"owns":
			if rest == "fists" or _weapon_known(rest):
				return ["owns", rest]
		"has":
			if _parse_cfg.items.has(rest) and str(_parse_cfg.items[rest].kind) == "goods":
				return ["count", rest, ">=", 1]
		"bought":
			if _parse_cfg.items.has(rest):
				return ["bought", rest]
		"case", "flag":
			if _is_id(rest):
				return [prefix, rest]
		"used":
			if _is_key(rest, KEY_LIMIT):
				return ["used", rest]
		"unlock":
			if _parse_cfg.unlocks.has(rest):
				return ["unlock", rest]
		"tier":
			var parts := rest.split(":")
			if parts.size() == 2 and _parse_cfg.tracks.has(parts[0]) and _tier_index(_parse_cfg.tracks[parts[0]], parts[1]) >= 0:
				return ["tier", parts[0], parts[1]]
		"choice":
			var picked := rest.split(":")
			var decisions: Dictionary = _parse_cfg.get("decisions", {})
			if picked.size() == 1 and decisions.has(picked[0]):
				return ["choice", picked[0], ""]
			if picked.size() == 2 and decisions.has(picked[0]) and decisions[picked[0]].options.has(picked[1]):
				return ["choice", picked[0], picked[1]]
	_parse_error = "unknown requirement '%s'" % token
	return []

func _weapon_known(id: String) -> bool:
	for item_id in _parse_cfg.items:
		if str(_parse_cfg.items[item_id].weapon) == id:
			return true
	return _weapon_profiles().has(id)

func _evaluate(node: Array, depth: int) -> bool:
	if node.is_empty() or depth > MAX_DEPTH:
		return false
	match str(node[0]):
		"bool":
			return bool(node[1])
		"not":
			return not _evaluate(node[1], depth + 1)
		"and":
			return _evaluate(node[1], depth + 1) and _evaluate(node[2], depth + 1)
		"or":
			return _evaluate(node[1], depth + 1) or _evaluate(node[2], depth + 1)
		"track":
			return _compare(_gate_track_value(str(node[1])), str(node[2]), int(node[3]))
		"money":
			return _compare(money, str(node[2]), int(node[3]))
		"count":
			return _compare(int(items.get(str(node[1]), 0)), str(node[2]), int(node[3]))
		"owns":
			return str(node[1]) == "fists" or _combat_owns(str(node[1]))
		"bought":
			return int(purchases.get(str(node[1]), 0)) > 0
		"case":
			return rewarded_cases.has(str(node[1]))
		"flag":
			return flags.has(str(node[1]))
		"used":
			return _once.has("hook:" + str(node[1]))
		"unlock":
			var unlock: Dictionary = config.unlocks.get(str(node[1]), {})
			if unlock.is_empty():
				return false
			var requires := str(unlock.requires).strip_edges()
			return requires.is_empty() or _evaluate(_requirement(requires), depth + 1)
		"tier":
			return _gate_tier(str(node[1])) == str(node[2])
		"rel":
			return _compare(relationship_value(str(node[1])), str(node[2]), int(node[3]))
		"choice":
			var picked := choice_of(str(node[1]))
			return not picked.is_empty() if str(node[2]).is_empty() else picked == str(node[2])
	return false

static func _compare(left: int, op: String, right: int) -> bool:
	match op:
		">=":
			return left >= right
		"<=":
			return left <= right
		"==":
			return left == right
		"!=":
			return left != right
		">":
			return left > right
		"<":
			return left < right
	return false

# --- State validation -------------------------------------------------------------

func _validate_state(data) -> String:
	if not enabled:
		return "progression unavailable"
	if not data is Dictionary:
		return "malformed progression"
	var state: Dictionary = data
	# Older (1) snapshots restore with defaults; anything newer is refused.
	if not _is_integer(state.get("version"), 1, VERSION):
		return "unsupported progression version"
	var keys: Array = STATE_KEYS_V2 if int(state.version) >= 2 else STATE_KEYS
	for key in state:
		if not key is String or not key in keys:
			return "unknown progression field"
	for key in keys:
		if not state.has(key):
			return "missing progression " + str(key)
	if not state.origin is String or not state.origin in ORIGINS:
		return "invalid progression origin"
	if not _is_integer(state.money, 0, int(config.money.max)):
		return "invalid money"
	if not state.reputation is Dictionary:
		return "invalid reputation"
	for track in state.reputation:
		if not track is String or not config.tracks.has(track):
			return "unknown reputation track"
		if not _is_integer(state.reputation[track], int(config.tracks[track].min), int(config.tracks[track].max)):
			return "reputation out of range"
	var goods := {}
	var every_item := {}
	var weapon_items := {}
	for id in config.items:
		every_item[id] = true
		if str(config.items[id].kind) == "goods":
			goods[id] = int(config.items[id].max)
		elif str(config.items[id].kind) == "weapon":
			weapon_items[id] = true
	var error := _validate_counts(state.items, goods, -1)
	if not error.is_empty():
		return "invalid items: " + error
	error = _validate_counts(state.purchases, every_item, int(config.limits.purchase_count))
	if not error.is_empty():
		return "invalid purchases: " + error
	var known_actions := {}
	for id in config.actions:
		known_actions[id] = true
	error = _validate_counts(state.actions, known_actions, int(config.limits.action_count))
	if not error.is_empty():
		return "invalid action counts: " + error
	error = _validate_set(state.weapons, weapon_items, weapon_items.size(), 0)
	if not error.is_empty():
		return "invalid weapon ledger: " + error
	error = _validate_set(state.rewarded_cases, _known_case_ids(), MAX_CASES, 0)
	if not error.is_empty():
		return "invalid rewarded cases: " + error
	error = _validate_set(state.once, {}, int(config.limits.once_keys), ONCE_LIMIT)
	if not error.is_empty():
		return "invalid once ledger: " + error
	error = _validate_set(state.flags, {}, int(config.limits.flags), 0)
	if not error.is_empty():
		return "invalid flags: " + error
	if not _is_integer(state.seq, 0, MAX_SEQ):
		return "invalid sequence"
	if not state.history is Array or state.history.size() > int(config.limits.history):
		return "invalid history"
	var previous := 0
	for entry in state.history:
		error = _validate_history_entry(entry, previous)
		if not error.is_empty():
			return error
		previous = int(entry.seq)
	if previous > int(state.seq):
		return "history sequence mismatch"
	if int(state.version) >= 2:
		error = _validate_relationships(state.relationships)
		if not error.is_empty():
			return "invalid relationships: " + error
		error = _validate_choices(state.choices)
		if not error.is_empty():
			return "invalid choices: " + error
		error = _validate_errands(state.errands)
		if not error.is_empty():
			return "invalid errands: " + error
	return ""

func _validate_relationships(value) -> String:
	if not value is Dictionary:
		return "not an object"
	var bonds: Dictionary = config.relationships
	for contact in value:
		if not contact is String or not bonds.contacts.has(contact):
			return "unknown contact"
		if not _is_integer(value[contact], int(bonds.min), int(bonds.max)):
			return "value out of range"
	return ""

## One known option per known decision, and every option's "after" ordering
## must hold inside the same snapshot (no ending without its earlier choice).
func _validate_choices(value) -> String:
	if not value is Dictionary or value.size() > config.decisions.size():
		return "not an object"
	for decision in value:
		if not decision is String or not config.decisions.has(decision):
			return "unknown decision"
		var option = value[decision]
		if not option is String or not config.decisions[decision].options.has(option):
			return "unknown option"
	for decision in value:
		var after: Dictionary = config.decisions[decision].options[value[decision]].after
		for earlier in after:
			if str(value.get(earlier, "")) != str(after[earlier]):
				return "choice out of order"
	return ""

func _validate_errands(value) -> String:
	if not value is Dictionary or value.size() != ERRAND_KEYS.size():
		return "not an errand record"
	for key in ERRAND_KEYS:
		if not value.has(key):
			return "not an errand record"
	if not _is_integer(value.runs, 0, int(config.limits.action_count)):
		return "invalid run count"
	if not _is_integer(value.ready_at, 0, MAX_READY_AT):
		return "invalid ready time"
	if not _is_integer(value.earned, 0, int(config.money.max)):
		return "invalid earnings"
	return ""

func _validate_counts(value, allowed: Dictionary, cap: int) -> String:
	if not value is Dictionary:
		return "not an object"
	for key in value:
		if not key is String or not allowed.has(key):
			return "unknown id"
		if not _is_integer(value[key], 0, cap if cap >= 0 else int(allowed[key])):
			return "count out of range"
	return ""

## key_limit 0 means plain ids; otherwise canonical keys up to that length.
func _validate_set(value, known: Dictionary, limit: int, key_limit: int) -> String:
	if not value is Array or value.size() > limit:
		return "not a bounded list"
	var seen := {}
	for entry in value:
		if not entry is String or seen.has(entry):
			return "duplicate or malformed entry"
		if not (_is_key(entry, key_limit) if key_limit > 0 else _is_id(entry)):
			return "malformed entry"
		if not known.is_empty() and not known.has(entry):
			return "unknown entry"
		seen[entry] = true
	return ""

func _validate_history_entry(entry, previous: int) -> String:
	if not entry is Dictionary or entry.size() != HISTORY_KEYS.size():
		return "malformed history entry"
	for key in HISTORY_KEYS:
		if not entry.has(key):
			return "malformed history entry"
	if not _is_integer(entry.seq, previous + 1, MAX_SEQ):
		return "history out of order"
	if not _is_key(entry.action, KEY_LIMIT):
		return "invalid history action"
	if not entry.key is String or (not entry.key.is_empty() and not _is_key(entry.key, KEY_LIMIT)):
		return "invalid history key"
	if not entry.note is String or entry.note.length() > 160:
		return "invalid history note"
	if not _is_integer(entry.money, -int(config.money.max), int(config.money.max)):
		return "invalid history money"
	if not _is_integer(entry.minute, -1, 1000000000):
		return "invalid history time"
	if not entry.deltas is Dictionary:
		return "invalid history change"
	for track in entry.deltas:
		if not track is String or not config.tracks.has(track):
			return "invalid history change"
		var span := int(config.tracks[track].max) - int(config.tracks[track].min)
		if not _is_integer(entry.deltas[track], -span, span):
			return "invalid history change"
	return ""

func _normalized_entry(entry: Dictionary) -> Dictionary:
	return {"seq": int(entry.seq), "action": str(entry.action), "key": str(entry.key), "deltas": _int_map(entry.deltas),
		"money": int(entry.money), "minute": int(entry.minute), "note": str(entry.note)}

static func _int_map(source: Dictionary) -> Dictionary:
	var result := {}
	for key in source:
		result[str(key)] = int(source[key])
	return result

static func _set_of(source: Array) -> Dictionary:
	var result := {}
	for entry in source:
		result[str(entry)] = true
	return result

static func _sorted_keys(source: Dictionary) -> Array:
	var keys := source.keys()
	keys.sort()
	return keys

static func _is_number(value) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _is_integer(value, low: int, high: int) -> bool:
	return _is_number(value) and float(value) == floorf(float(value)) and float(value) >= float(low) and float(value) <= float(high)

static func _is_true(value) -> bool:
	return value is bool and value

static func _is_false(value) -> bool:
	return value is bool and not value

static func _positive(value) -> bool:
	return (value is bool and value) or (_is_number(value) and float(value) > 0.0)

static func _signed(value: int) -> String:
	return ("+%d" % value) if value >= 0 else ("%d" % value)

func _is_id(text) -> bool:
	return text is String and _id_pattern.search(text) != null

func _is_key(text, limit: int) -> bool:
	return text is String and not text.is_empty() and text.length() <= limit and _slug(text, limit) == text

## Lowercase [a-z0-9_:.-] only, so recorded keys always pass validation.
func _slug(text: String, limit: int) -> String:
	var lowered := text.strip_edges().to_lower()
	var out := ""
	for index in lowered.length():
		if out.length() >= limit:
			break
		var code := lowered.unicode_at(index)
		var allowed := (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95 or code == 58 or code == 46 or code == 45
		out += lowered[index] if allowed else "_"
	return out

# --- Config normalization -----------------------------------------------------------

func _normalize_config(data: Dictionary, errors: Array) -> Dictionary:
	var out := {"money": {"starting": 0, "max": 0}, "new_game": {"strict": false, "weapons": ["fists"]}, "limits": {}, "gates": {},
		"tracks": {}, "track_order": [], "items": {}, "shops": {}, "actions": {}, "offenses": {},
		"cases": {"money_per_point": 0.0, "money_overrides": {}, "max_reward": 0, "default_action": "", "actions": {}},
		"migration": {"credit_reputation": false, "credit_money": false}, "pricing": {"min_percent": 0, "max_percent": 0, "modifiers": []},
		"unlocks": {}, "roles": [], "perception": [], "actor_roles": {"default": "neighbor", "actors": {}, "prefixes": []}, "dialogue_examples": {},
		"relationships": {"min": -100, "max": 100, "start": 0, "tiers": [], "contacts": {}, "contact_order": [], "actors": {}},
		"decisions": {}, "decision_order": [], "errands": {"cooldown": 120.0, "max_payout": 200, "variants": {}, "variant_order": []}, "reactions": []}
	for key in LIMITS:
		out.limits[key] = int(LIMITS[key][2])
	for key in GATES:
		out.gates[key] = true
	if data.is_empty():
		errors.append("progression config missing or unreadable: " + CONFIG_PATH)
		return out
	_check_keys(data, CONFIG_KEYS, errors, "config")
	if not _is_integer(data.get("version"), 1, 1):
		errors.append("config.version must be 1")
	var section := _section(data, "money", true, errors)
	_check_keys(section, ["starting", "max"], errors, "money")
	out.money.max = _int_field(section, "max", 1, 1000000000, 9999999, true, errors, "money")
	out.money.starting = _int_field(section, "starting", 0, int(out.money.max), 0, true, errors, "money")
	section = _section(data, "new_game", false, errors)
	_check_keys(section, ["strict_starting_inventory", "starter_weapons"], errors, "new_game")
	out.new_game.strict = _bool_field(section, "strict_starting_inventory", false, errors, "new_game")
	var starters := _id_list(section, "starter_weapons", errors, "new_game")
	if not "fists" in starters:
		starters.append("fists")
	out.new_game.weapons = starters
	section = _section(data, "limits", true, errors)
	_check_keys(section, LIMITS.keys(), errors, "limits")
	for key in LIMITS:
		var spec: Array = LIMITS[key]
		out.limits[key] = _int_field(section, key, int(spec[0]), int(spec[1]), int(spec[2]), true, errors, "limits")
	section = _section(data, "gates", true, errors)
	_check_keys(section, GATES, errors, "gates")
	for key in GATES:
		out.gates[key] = _bool_field(section, key, true, errors, "gates")
	_normalize_tracks(_section(data, "tracks", true, errors), out, errors)
	_normalize_items(_section(data, "items", true, errors), out, errors)
	_normalize_shops(_section(data, "shops", true, errors), out, errors)
	_normalize_relationships(_section(data, "relationships", false, errors), out, errors)
	_normalize_actions(_section(data, "actions", true, errors), out, errors)
	_normalize_decisions(_section(data, "decisions", false, errors), out, errors)
	_normalize_errands(_section(data, "errands", false, errors), out, errors)
	_normalize_reactions(data.get("reactions"), out, errors)
	_normalize_rest(data, out, errors)
	_compile_all(out, errors)
	return out

func _normalize_relationships(source: Dictionary, out: Dictionary, errors: Array) -> void:
	var bonds: Dictionary = out.relationships
	if source.is_empty():
		return
	_check_keys(source, ["min", "max", "start", "tiers", "contacts"], errors, "relationships")
	var low := _int_field(source, "min", -100000, 100000, -100, true, errors, "relationships")
	var high := _int_field(source, "max", -100000, 100000, 100, true, errors, "relationships")
	if high <= low:
		errors.append("relationships.max must be greater than min")
		high = low + 1
	bonds.min = low
	bonds.max = high
	bonds.start = _int_field(source, "start", low, high, clampi(0, low, high), false, errors, "relationships")
	bonds.tiers = _tier_list(source.get("tiers"), low, high, "relationships", errors)
	var contacts = source.get("contacts", {})
	if not contacts is Dictionary:
		errors.append("relationships.contacts must be an object")
		return
	for raw_id in contacts:
		var id := str(raw_id)
		var where := "relationships.contacts." + id
		if not _is_id(raw_id) or id in RESERVED or not contacts[raw_id] is Dictionary:
			errors.append(where + " is not a valid contact")
			continue
		var contact: Dictionary = contacts[raw_id]
		_check_keys(contact, ["label", "actors"], errors, where)
		var actors := _id_list(contact, "actors", errors, where)
		if actors.is_empty():
			errors.append(where + ".actors must name at least one actor id")
		for actor_id in actors:
			if bonds.actors.has(actor_id):
				errors.append("%s.actors repeats %s" % [where, str(actor_id)])
			bonds.actors[actor_id] = id
		bonds.contacts[id] = {"label": _text_field(contact, "label", 48, id.capitalize(), true, errors, where), "actors": actors}
		bonds.contact_order.append(id)

func _tier_list(raw_tiers, low: int, high: int, where: String, errors: Array) -> Array:
	var tiers: Array = []
	if not raw_tiers is Array or raw_tiers.is_empty():
		errors.append(where + ".tiers must be a non-empty list")
		return tiers
	var previous := low - 1
	var seen := {}
	for index in raw_tiers.size():
		var tier_where := "%s.tiers[%d]" % [where, index]
		var raw_tier = raw_tiers[index]
		if not raw_tier is Dictionary or not _is_id(raw_tier.get("id")) or seen.has(raw_tier.get("id")):
			errors.append(tier_where + " needs a unique id")
			continue
		_check_keys(raw_tier, ["id", "at", "label"], errors, tier_where)
		var at := _int_field(raw_tier, "at", low, high, low, true, errors, tier_where)
		if (index == 0 and at != low) or at <= previous:
			errors.append(tier_where + ".at must start at the minimum and increase")
		previous = at
		seen[raw_tier.id] = true
		tiers.append({"id": str(raw_tier.id), "at": at, "label": _text_field(raw_tier, "label", 48, str(raw_tier.id), true, errors, tier_where)})
	return tiers

## Each option names a known action; "after" may only point at a decision
## declared earlier, so a recorded ending always has its earlier choice.
func _normalize_decisions(source: Dictionary, out: Dictionary, errors: Array) -> void:
	for raw_id in source:
		var id := str(raw_id)
		var where := "decisions." + id
		if not _is_id(raw_id) or not source[raw_id] is Dictionary:
			errors.append(where + " is invalid")
			continue
		var spec: Dictionary = source[raw_id]
		_check_keys(spec, ["label", "options"], errors, where)
		var decision := {"label": _text_field(spec, "label", 96, id, true, errors, where), "options": {}}
		var options = spec.get("options")
		if not options is Dictionary or options.is_empty():
			errors.append(where + ".options must be a non-empty object")
		else:
			for raw_option in options:
				var option_id := str(raw_option)
				var option_where := where + ".options." + option_id
				if not _is_id(raw_option) or not options[raw_option] is Dictionary:
					errors.append(option_where + " is invalid")
					continue
				var option: Dictionary = options[raw_option]
				_check_keys(option, ["label", "action", "after", "requires"], errors, option_where)
				var action := _text_field(option, "action", 64, "", true, errors, option_where)
				if not out.actions.has(action):
					errors.append(option_where + ".action is not a known action")
				var after := {}
				var raw_after = option.get("after", {})
				if not raw_after is Dictionary:
					errors.append(option_where + ".after must be an object")
				else:
					for earlier in raw_after:
						var earlier_id := str(earlier)
						if not out.decisions.has(earlier_id) or not raw_after[earlier] is String or not out.decisions[earlier_id].options.has(raw_after[earlier]):
							errors.append("%s.after must name an earlier decision and one of its options" % option_where)
						else:
							after[earlier_id] = str(raw_after[earlier])
				decision.options[option_id] = {"label": _text_field(option, "label", 96, option_id, true, errors, option_where), "action": action,
					"after": after, "requires": _text_field(option, "requires", MAX_REQUIREMENT, "", false, errors, option_where)}
		out.decisions[id] = decision
		out.decision_order.append(id)

## Repeatable income is bounded by one shared cooldown and a payout cap.
func _normalize_errands(source: Dictionary, out: Dictionary, errors: Array) -> void:
	var spec: Dictionary = out.errands
	if source.is_empty():
		return
	_check_keys(source, ["cooldown_seconds", "max_payout", "variants"], errors, "errands")
	spec.cooldown = _float_field(source, "cooldown_seconds", 30.0, 3600.0, 120.0, errors, "errands")
	spec.max_payout = _int_field(source, "max_payout", 1, 1000, 200, false, errors, "errands")
	var variants = source.get("variants", {})
	if not variants is Dictionary:
		errors.append("errands.variants must be an object")
		return
	for raw_id in variants:
		var id := str(raw_id)
		var where := "errands.variants." + id
		if not _is_id(raw_id) or not variants[raw_id] is Dictionary:
			errors.append(where + " is invalid")
			continue
		var variant: Dictionary = variants[raw_id]
		_check_keys(variant, ["label", "payout", "requires"], errors, where)
		spec.variants[id] = {"label": _text_field(variant, "label", 64, id.capitalize(), true, errors, where),
			"payout": _int_field(variant, "payout", 1, int(spec.max_payout), 1, true, errors, where),
			"requires": _text_field(variant, "requires", MAX_REQUIREMENT, "", false, errors, where)}
		spec.variant_order.append(id)

func _normalize_reactions(raw, out: Dictionary, errors: Array) -> void:
	if raw == null:
		return
	if not raw is Array:
		errors.append("config.reactions must be a list")
		return
	var seen := {}
	for index in raw.size():
		var where := "reactions[%d]" % index
		var rule = raw[index]
		if not rule is Dictionary or not _is_id(rule.get("id")) or seen.has(rule.get("id")):
			errors.append(where + " needs a unique id")
			continue
		_check_keys(rule, ["id", "actors", "requires", "line"], errors, where)
		seen[rule.id] = true
		var actors := _id_list(rule, "actors", errors, where)
		if actors.is_empty():
			errors.append(where + ".actors must name at least one actor id")
		out.reactions.append({"id": str(rule.id), "actors": actors, "requires": _text_field(rule, "requires", MAX_REQUIREMENT, "", false, errors, where),
			"line": _text_field(rule, "line", 200, "", true, errors, where)})

func _normalize_tracks(source_tracks: Dictionary, out: Dictionary, errors: Array) -> void:
	for raw_id in source_tracks:
		var id := str(raw_id)
		var where := "tracks." + id
		if not _is_id(raw_id) or id in RESERVED or not source_tracks[raw_id] is Dictionary:
			errors.append(where + " is not a valid track")
			continue
		var source: Dictionary = source_tracks[raw_id]
		_check_keys(source, ["label", "min", "max", "start", "tiers"], errors, where)
		var low := _int_field(source, "min", -100000, 100000, 0, true, errors, where)
		var high := _int_field(source, "max", -100000, 100000, low + 1, true, errors, where)
		if high <= low:
			errors.append(where + ".max must be greater than min")
			high = low + 1
		var track := {"label": _text_field(source, "label", 32, id.capitalize(), true, errors, where), "min": low, "max": high,
			"start": _int_field(source, "start", low, high, low, false, errors, where), "tiers": []}
		var raw_tiers = source.get("tiers")
		if not raw_tiers is Array or raw_tiers.is_empty():
			errors.append(where + ".tiers must be a non-empty list")
		else:
			var previous := low - 1
			var seen := {}
			for index in raw_tiers.size():
				var tier_where := "%s.tiers[%d]" % [where, index]
				var raw_tier = raw_tiers[index]
				if not raw_tier is Dictionary or not _is_id(raw_tier.get("id")) or seen.has(raw_tier.get("id")):
					errors.append(tier_where + " needs a unique id")
					continue
				_check_keys(raw_tier, ["id", "at", "label"], errors, tier_where)
				var at := _int_field(raw_tier, "at", low, high, low, true, errors, tier_where)
				if (index == 0 and at != low) or at <= previous:
					errors.append(tier_where + ".at must start at the track minimum and increase")
				previous = at
				seen[raw_tier.id] = true
				track.tiers.append({"id": str(raw_tier.id), "at": at, "label": _text_field(raw_tier, "label", 48, str(raw_tier.id), true, errors, tier_where)})
		out.tracks[id] = track
		out.track_order.append(id)
	for required in ["snitch", "gangsta"]:
		if not out.tracks.has(required):
			errors.append("tracks.%s is required (the two independent reputation axes)" % required)

func _normalize_items(source_items: Dictionary, out: Dictionary, errors: Array) -> void:
	var profiles := _weapon_profiles()
	var sold_weapons := {}
	for raw_id in source_items:
		var id := str(raw_id)
		var where := "items." + id
		if not _is_id(raw_id) or id in RESERVED or out.tracks.has(id) or not source_items[raw_id] is Dictionary:
			errors.append(where + " is not a valid item")
			continue
		var source: Dictionary = source_items[raw_id]
		_check_keys(source, ["kind", "weapon", "label", "description", "hint", "price", "rounds", "quantity", "max", "requires", "locked", "action", "requires_owned"], errors, where)
		var kind := _text_field(source, "kind", 16, "goods", true, errors, where)
		if not kind in ITEM_KINDS:
			errors.append(where + ".kind must be weapon, ammo or goods")
			kind = "goods"
		var item := {"id": id, "kind": kind, "shop": "", "label": _text_field(source, "label", 48, id.capitalize(), true, errors, where),
			"description": _text_field(source, "description", 200, "", false, errors, where), "hint": _text_field(source, "hint", 80, "", false, errors, where),
			"price": _int_field(source, "price", 0, 1000000, 0, true, errors, where), "weapon": "", "rounds": 0, "quantity": 1, "max": 0,
			"requires": _text_field(source, "requires", MAX_REQUIREMENT, "", false, errors, where), "locked": _text_field(source, "locked", 160, "", false, errors, where),
			"action": _text_field(source, "action", 64, "", false, errors, where), "requires_owned": _bool_field(source, "requires_owned", kind == "ammo", errors, where)}
		if kind == "weapon" or kind == "ammo":
			var weapon := _text_field(source, "weapon", 32, id if kind == "weapon" else "", kind == "ammo", errors, where)
			if not _is_id(weapon) or weapon == "fists" or (not profiles.is_empty() and not profiles.has(weapon)):
				errors.append(where + ".weapon must be a combat weapon id")
			if kind == "weapon":
				if sold_weapons.has(weapon):
					errors.append(where + ".weapon is already sold as " + str(sold_weapons[weapon]))
				sold_weapons[weapon] = id
			item.weapon = weapon
			item.rounds = _int_field(source, "rounds", 1 if kind == "ammo" else 0, 10000, 0, kind == "ammo", errors, where)
		else:
			item.quantity = _int_field(source, "quantity", 1, 1000, 1, false, errors, where)
			item.max = _int_field(source, "max", 1, int(out.limits.stack), 1, true, errors, where)
		out.items[id] = item

func _normalize_shops(source_shops: Dictionary, out: Dictionary, errors: Array) -> void:
	for raw_kind in source_shops:
		var kind := str(raw_kind)
		var where := "shops." + kind
		if not _is_id(raw_kind) or not source_shops[raw_kind] is Dictionary:
			errors.append(where + " is not a valid shop kind")
			continue
		var source: Dictionary = source_shops[raw_kind]
		_check_keys(source, ["label", "clerk_role", "items"], errors, where)
		var stock := _id_list(source, "items", errors, where)
		for item_id in stock:
			if not out.items.has(item_id):
				errors.append("%s lists unknown item %s" % [where, str(item_id)])
			elif not str(out.items[item_id].shop).is_empty():
				errors.append("%s: item %s is already sold by %s" % [where, str(item_id), str(out.items[item_id].shop)])
			else:
				out.items[item_id].shop = kind
		out.shops[kind] = {"label": _text_field(source, "label", 48, kind.capitalize(), false, errors, where),
			"clerk_role": _text_field(source, "clerk_role", 32, "clerk", false, errors, where), "items": stock}
	for item_id in out.items:
		if str(out.items[item_id].shop).is_empty():
			errors.append("items.%s is not stocked by any shop" % str(item_id))

func _normalize_actions(source_actions: Dictionary, out: Dictionary, errors: Array) -> void:
	for raw_id in source_actions:
		var id := str(raw_id)
		var where := "actions." + id
		if not _is_id(raw_id) or not source_actions[raw_id] is Dictionary:
			errors.append(where + " is not a valid action")
			continue
		var source: Dictionary = source_actions[raw_id]
		_check_keys(source, ["label", "deltas", "relations", "money", "items", "once", "cooldown", "window", "limit", "requires", "requires_witness", "notice", "set_flags", "clear_flags"], errors, where)
		var rule := {"label": _text_field(source, "label", 96, id, true, errors, where), "deltas": {}, "relations": {}, "items": {},
			"money": _int_field(source, "money", -100000, 100000, 0, false, errors, where), "once": _bool_field(source, "once", false, errors, where),
			"cooldown": _float_field(source, "cooldown", 0.0, 86400.0, 0.0, errors, where), "window_seconds": 0.0, "window_max": 0,
			"limit": _int_field(source, "limit", 0, 1000000, 0, false, errors, where),
			"requires": _text_field(source, "requires", MAX_REQUIREMENT, "", false, errors, where),
			"requires_witness": _bool_field(source, "requires_witness", false, errors, where),
			"notice": _text_field(source, "notice", 160, "", false, errors, where),
			"set_flags": _id_list(source, "set_flags", errors, where), "clear_flags": _id_list(source, "clear_flags", errors, where)}
		var deltas = source.get("deltas", {})
		if not deltas is Dictionary:
			errors.append(where + ".deltas must be an object")
		else:
			for track in deltas:
				if not out.tracks.has(str(track)) or not _is_integer(deltas[track], -1000, 1000):
					errors.append("%s.deltas.%s must name a track with a whole-number change" % [where, str(track)])
				else:
					rule.deltas[str(track)] = int(deltas[track])
		var relations = source.get("relations", {})
		if not relations is Dictionary:
			errors.append(where + ".relations must be an object")
		else:
			for contact in relations:
				if not out.relationships.contacts.has(str(contact)) or not _is_integer(relations[contact], -1000, 1000):
					errors.append("%s.relations.%s must name a relationship contact with a whole-number change" % [where, str(contact)])
				else:
					rule.relations[str(contact)] = int(relations[contact])
		var grants = source.get("items", {})
		var grants_items := false
		if not grants is Dictionary:
			errors.append(where + ".items must be an object")
		else:
			for item_id in grants:
				if not out.items.has(str(item_id)) or str(out.items[str(item_id)].kind) != "goods" or not _is_integer(grants[item_id], -1000, 1000):
					errors.append("%s.items.%s must name a goods item with a whole-number change" % [where, str(item_id)])
				else:
					rule.items[str(item_id)] = int(grants[item_id])
					grants_items = grants_items or int(grants[item_id]) > 0
		if source.has("window"):
			var window = source.window
			if not window is Dictionary:
				errors.append(where + ".window must be an object")
			else:
				_check_keys(window, ["seconds", "max"], errors, where + ".window")
				rule.window_seconds = _float_field(window, "seconds", 0.1, 86400.0, 60.0, errors, where + ".window")
				rule.window_max = _int_field(window, "max", 1, 1000, 1, true, errors, where + ".window")
		if (int(rule.money) > 0 or grants_items) and not bool(rule.once) and int(rule.limit) == 0:
			errors.append(where + " grants money or items, so it needs once or limit")
		out.actions[id] = rule

func _normalize_rest(data: Dictionary, out: Dictionary, errors: Array) -> void:
	var section := _section(data, "offenses", false, errors)
	for raw_kind in section:
		var offense_where := "offenses." + str(raw_kind)
		var offense = section[raw_kind]
		if not _is_id(raw_kind) or not offense is Dictionary:
			errors.append(offense_where + " is invalid")
			continue
		_check_keys(offense, ["action", "key"], errors, offense_where)
		var offense_action := _text_field(offense, "action", 64, "", true, errors, offense_where)
		var scope := _text_field(offense, "key", 16, "none", false, errors, offense_where)
		if not out.actions.has(offense_action) or not scope in ["victim", "none"]:
			errors.append(offense_where + " needs a known action and key victim or none")
		out.offenses[str(raw_kind)] = {"action": offense_action, "key": scope}
	section = _section(data, "cases", false, errors)
	_check_keys(section, ["money_per_point", "money_overrides", "max_reward", "default_action", "actions"], errors, "cases")
	out.cases.max_reward = _int_field(section, "max_reward", 0, 10000000, 100000, false, errors, "cases")
	out.cases.money_per_point = _float_field(section, "money_per_point", 0.0, 1000.0, 1.0, errors, "cases")
	out.cases.default_action = _text_field(section, "default_action", 64, "", false, errors, "cases")
	if not str(out.cases.default_action).is_empty() and not out.actions.has(out.cases.default_action):
		errors.append("cases.default_action is not a known action")
	var overrides = section.get("money_overrides", {})
	if not overrides is Dictionary:
		errors.append("cases.money_overrides must be an object")
	else:
		for case_id in overrides:
			if not _is_id(case_id) or not _is_integer(overrides[case_id], 0, int(out.cases.max_reward)):
				errors.append("cases.money_overrides.%s is invalid" % str(case_id))
			else:
				out.cases.money_overrides[str(case_id)] = int(overrides[case_id])
	var case_actions = section.get("actions", {})
	if not case_actions is Dictionary:
		errors.append("cases.actions must be an object")
	else:
		for case_id in case_actions:
			if not _is_id(case_id) or not case_actions[case_id] is String or not out.actions.has(case_actions[case_id]):
				errors.append("cases.actions.%s must name a known action" % str(case_id))
			else:
				out.cases.actions[str(case_id)] = str(case_actions[case_id])
	section = _section(data, "migration", false, errors)
	_check_keys(section, ["credit_reputation", "credit_money"], errors, "migration")
	out.migration.credit_reputation = _bool_field(section, "credit_reputation", false, errors, "migration")
	out.migration.credit_money = _bool_field(section, "credit_money", false, errors, "migration")
	section = _section(data, "pricing", false, errors)
	_check_keys(section, ["min_percent", "max_percent", "modifiers"], errors, "pricing")
	out.pricing.min_percent = _int_field(section, "min_percent", -100, 0, -50, false, errors, "pricing")
	out.pricing.max_percent = _int_field(section, "max_percent", 0, 1000, 100, false, errors, "pricing")
	var modifiers = section.get("modifiers", [])
	if not modifiers is Array:
		errors.append("pricing.modifiers must be a list")
	else:
		var seen_modifiers := {}
		for index in modifiers.size():
			var modifier_where := "pricing.modifiers[%d]" % index
			var modifier = modifiers[index]
			if not modifier is Dictionary or not _is_id(modifier.get("id")) or seen_modifiers.has(modifier.get("id")):
				errors.append(modifier_where + " needs a unique id")
				continue
			_check_keys(modifier, ["id", "label", "shops", "requires", "percent"], errors, modifier_where)
			seen_modifiers[modifier.id] = true
			var kinds := _id_list(modifier, "shops", errors, modifier_where)
			for kind in kinds:
				if not out.shops.has(kind):
					errors.append("%s names unknown shop %s" % [modifier_where, str(kind)])
			out.pricing.modifiers.append({"id": str(modifier.id), "label": _text_field(modifier, "label", 48, str(modifier.id), true, errors, modifier_where),
				"shops": kinds, "requires": _text_field(modifier, "requires", MAX_REQUIREMENT, "", false, errors, modifier_where),
				"percent": _int_field(modifier, "percent", -100, 1000, 0, true, errors, modifier_where)})
	section = _section(data, "unlocks", false, errors)
	for raw_id in section:
		var unlock_where := "unlocks." + str(raw_id)
		var unlock = section[raw_id]
		if not _is_id(raw_id) or not unlock is Dictionary:
			errors.append(unlock_where + " is invalid")
			continue
		_check_keys(unlock, ["label", "requires"], errors, unlock_where)
		out.unlocks[str(raw_id)] = {"label": _text_field(unlock, "label", 96, str(raw_id), true, errors, unlock_where),
			"requires": _text_field(unlock, "requires", MAX_REQUIREMENT, "", true, errors, unlock_where)}
	section = _section(data, "perception", false, errors)
	_check_keys(section, ["roles", "rules"], errors, "perception")
	out.roles = _id_list(section, "roles", errors, "perception")
	var rules = section.get("rules", [])
	if not rules is Array:
		errors.append("perception.rules must be a list")
	else:
		var seen_rules := {}
		for index in rules.size():
			var rule_where := "perception.rules[%d]" % index
			var rule = rules[index]
			if not rule is Dictionary or not _is_id(rule.get("id")) or seen_rules.has(rule.get("id")):
				errors.append(rule_where + " needs a unique id")
				continue
			_check_keys(rule, ["id", "roles", "requires", "attitude", "label", "line"], errors, rule_where)
			seen_rules[rule.id] = true
			var observers: Array = []
			var raw_roles = rule.get("roles", [])
			if not raw_roles is Array or raw_roles.is_empty():
				errors.append(rule_where + ".roles must be a non-empty list")
			else:
				for role in raw_roles:
					if not role is String or (role != "*" and not role in out.roles):
						errors.append("%s names unknown role %s" % [rule_where, str(role)])
					else:
						observers.append(role)
			var attitude := _text_field(rule, "attitude", 32, "neutral", true, errors, rule_where)
			if not _is_id(attitude):
				errors.append(rule_where + ".attitude must be an id")
			out.perception.append({"id": str(rule.id), "roles": observers, "attitude": attitude,
				"requires": _text_field(rule, "requires", MAX_REQUIREMENT, "", false, errors, rule_where),
				"label": _text_field(rule, "label", 48, "", false, errors, rule_where), "line": _text_field(rule, "line", 200, "", false, errors, rule_where)})
	section = _section(data, "actor_roles", false, errors)
	_check_keys(section, ["default", "actors", "prefixes"], errors, "actor_roles")
	out.actor_roles.default = _text_field(section, "default", 32, "neighbor", false, errors, "actor_roles")
	var actor_map = section.get("actors", {})
	var prefix_map = section.get("prefixes", {})
	if not actor_map is Dictionary or not prefix_map is Dictionary:
		errors.append("actor_roles.actors and actor_roles.prefixes must be objects")
	else:
		for actor_id in actor_map:
			if not actor_map[actor_id] is String or not actor_map[actor_id] in out.roles:
				errors.append("actor_roles.actors.%s names an unknown role" % str(actor_id))
			else:
				out.actor_roles.actors[str(actor_id)] = str(actor_map[actor_id])
		for prefix in prefix_map:
			if not _is_id(prefix) or not prefix_map[prefix] is String or not prefix_map[prefix] in out.roles:
				errors.append("actor_roles.prefixes.%s is invalid" % str(prefix))
			else:
				out.actor_roles.prefixes.append([str(prefix), str(prefix_map[prefix])])
	if not out.roles.is_empty():
		if not out.actor_roles.default in out.roles:
			errors.append("actor_roles.default names an unknown role")
		for kind in out.shops:
			if not out.shops[kind].clerk_role in out.roles:
				errors.append("shops.%s.clerk_role names an unknown role" % str(kind))
	for item_id in out.items:
		var item_action := str(out.items[item_id].action)
		if not item_action.is_empty() and not out.actions.has(item_action):
			errors.append("items.%s.action is not a known action" % str(item_id))
	section = _section(data, "dialogue_examples", false, errors)
	for raw_id in section:
		if not _is_id(raw_id) or not section[raw_id] is Dictionary:
			errors.append("dialogue_examples.%s is invalid" % str(raw_id))
		else:
			out.dialogue_examples[str(raw_id)] = section[raw_id].duplicate(true)

## Every authored requirement must parse; unlocks may not depend on themselves.
func _compile_all(cfg: Dictionary, errors: Array) -> void:
	var checks: Array = []
	for id in cfg.items:
		checks.append(["items.%s.requires" % str(id), cfg.items[id].requires])
	for id in cfg.actions:
		checks.append(["actions.%s.requires" % str(id), cfg.actions[id].requires])
	for modifier in cfg.pricing.modifiers:
		checks.append(["pricing.%s.requires" % str(modifier.id), modifier.requires])
	for rule in cfg.perception:
		checks.append(["perception.%s.requires" % str(rule.id), rule.requires])
	for id in cfg.decisions:
		for option_id in cfg.decisions[id].options:
			checks.append(["decisions.%s.%s.requires" % [str(id), str(option_id)], cfg.decisions[id].options[option_id].requires])
	for id in cfg.errands.variants:
		checks.append(["errands.%s.requires" % str(id), cfg.errands.variants[id].requires])
	for rule in cfg.reactions:
		checks.append(["reactions.%s.requires" % str(rule.id), rule.requires])
	var graph := {}
	for id in cfg.unlocks:
		checks.append(["unlocks.%s.requires" % str(id), cfg.unlocks[id].requires])
		var refs: Array = []
		if not str(cfg.unlocks[id].requires).strip_edges().is_empty():
			_collect_unlocks(_compile(str(cfg.unlocks[id].requires), cfg), refs)
		graph[id] = refs
	for id in cfg.dialogue_examples:
		_check_example(cfg.dialogue_examples[id], "dialogue_examples." + str(id), cfg, checks, errors)
	for check in checks:
		var text := str(check[1]).strip_edges()
		if not text.is_empty() and _compile(text, cfg).is_empty():
			errors.append("%s: %s" % [str(check[0]), _parse_error])
	for id in graph:
		if _unlock_cycle(str(id), graph, {}):
			errors.append("unlocks.%s depends on itself" % str(id))

func _collect_unlocks(node: Array, refs: Array) -> void:
	if node.is_empty():
		return
	match str(node[0]):
		"unlock":
			refs.append(str(node[1]))
		"not":
			_collect_unlocks(node[1], refs)
		"and", "or":
			_collect_unlocks(node[1], refs)
			_collect_unlocks(node[2], refs)

func _unlock_cycle(id: String, graph: Dictionary, trail: Dictionary) -> bool:
	if trail.has(id):
		return true
	trail[id] = true
	for next_id in graph.get(id, []):
		if _unlock_cycle(str(next_id), graph, trail):
			return true
	trail.erase(id)
	return false

func _check_example(graph: Dictionary, where: String, cfg: Dictionary, checks: Array, errors: Array) -> void:
	var nodes = graph.get("nodes")
	if not graph.get("start") is String or not nodes is Dictionary or not nodes.has(graph.start):
		errors.append(where + " needs a start node and nodes")
		return
	for node_id in nodes:
		var entry = nodes[node_id]
		var node_where := "%s.%s" % [where, str(node_id)]
		if not entry is Dictionary or not entry.get("lines", []) is Array or not entry.get("choices", []) is Array:
			errors.append(node_where + " is malformed")
			continue
		for choice in entry.get("choices", []):
			if not choice is Dictionary:
				errors.append(node_where + " has a malformed choice")
				continue
			var next_id := str(choice.get("next", ""))
			if not next_id.is_empty() and not nodes.has(next_id):
				errors.append("%s leads to missing node %s" % [node_where, next_id])
			if choice.has("condition"):
				checks.append([node_where + " condition", choice.condition])
			var hook = choice.get("hook", {})
			if not hook is Dictionary:
				errors.append(node_where + " has a malformed hook")
			elif not hook.is_empty() and (str(hook.get("kind", "")) != "progression" or not cfg.actions.has(str(hook.get("action", "")))):
				errors.append(node_where + " hook must name a progression action")

func _section(data: Dictionary, key: String, required: bool, errors: Array) -> Dictionary:
	if not data.has(key):
		if required:
			errors.append("config.%s is required" % key)
		return {}
	if not data[key] is Dictionary:
		errors.append("config.%s must be an object" % key)
		return {}
	return data[key]

func _check_keys(source: Dictionary, allowed: Array, errors: Array, where: String) -> void:
	for key in source:
		if not key is String or not key in allowed:
			errors.append("%s has unknown field '%s'" % [where, str(key)])

func _int_field(source: Dictionary, key: String, low: int, high: int, fallback: int, required: bool, errors: Array, where: String) -> int:
	if not source.has(key):
		if required:
			errors.append("%s.%s is required" % [where, key])
		return fallback
	if not _is_integer(source[key], low, high):
		errors.append("%s.%s must be a whole number from %d to %d" % [where, key, low, high])
		return fallback
	return int(source[key])

func _float_field(source: Dictionary, key: String, low: float, high: float, fallback: float, errors: Array, where: String) -> float:
	if not source.has(key):
		return fallback
	if not _is_number(source[key]) or float(source[key]) < low or float(source[key]) > high:
		errors.append("%s.%s must be a number from %s to %s" % [where, key, str(low), str(high)])
		return fallback
	return float(source[key])

func _bool_field(source: Dictionary, key: String, fallback: bool, errors: Array, where: String) -> bool:
	if not source.has(key):
		return fallback
	if not source[key] is bool:
		errors.append("%s.%s must be true or false" % [where, key])
		return fallback
	return bool(source[key])

func _text_field(source: Dictionary, key: String, limit: int, fallback: String, required: bool, errors: Array, where: String) -> String:
	if not source.has(key):
		if required:
			errors.append("%s.%s is required" % [where, key])
		return fallback
	if not source[key] is String or str(source[key]).length() > limit:
		errors.append("%s.%s must be text of at most %d characters" % [where, key, limit])
		return fallback
	return str(source[key])

func _id_list(source: Dictionary, key: String, errors: Array, where: String) -> Array:
	var result: Array = []
	if not source.has(key):
		return result
	if not source[key] is Array:
		errors.append("%s.%s must be a list of ids" % [where, key])
		return result
	for value in source[key]:
		if not _is_id(value) or value in result:
			errors.append("%s.%s has an invalid or repeated id" % [where, key])
			continue
		result.append(str(value))
	return result
