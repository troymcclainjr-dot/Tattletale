extends Node3D
## Local, non-gory combat. Only tick during gameplay; no original-block input actions.
## Real collision bodies arbitrate every strike and bullet. People at zero health
## die permanently for this world slot (registry: death_snapshot/restore_deaths).
## Gunfire is an event: each shot scans nearby people once; only the bounded
## fighter, panic and corpse sets tick afterwards.
## PlayMode.PLAYER_COMBAT gates only the explorer's own offense (input, equip,
## reload, attack, stomp). NPC/police fights, incoming damage, knockdown,
## healing and the saved inventory are unaffected; see city_play_mode.gd.
## A bicycle crash knocks a pedestrian down without harm, then they go after the
## rider with fists (knockdown_from_bicycle). Incidents may start a nonlethal
## neighbor-versus-neighbor fistfight (start_npc_fight). Contract:
## .work/pacifist-foundation/incidents-contract.md sections 1-2.
signal actor_died(id: String)
signal player_offense(kind: String, at: Vector3, victim_id: String)
signal player_defeated()
signal bicycle_knockdown(result: Dictionary)
signal bicycle_recovered(id: String)
const PlayMode := preload("res://scripts/city/city_play_mode.gd")
const Weapons := preload("res://scripts/city/city_combat_weapons.gd")
const Actor := preload("res://scripts/city/city_npc_actor.gd")
const WorldAudio := preload("res://scripts/city/city_world_audio.gd")
const PopulationAppearance := preload("res://scripts/city/city_population_appearance.gd")
const ModularPeople := preload("res://scripts/city/city_modular_people.gd")
const OccupantBallistics := preload("res://scripts/city/city_occupant_ballistics.gd")
## Fighters (melee, armed return fire, returning). Panic and corpses have their
## own budgets; a full fight budget never drops damage (cheap flee/death path).
const MAX_ACTIVE := 8
const MAX_DOWNED := 8
const KNOCKDOWN_TIME := 12.0
const STOMP_RANGE := 1.8
const GROUP_RADIUS := 18.0
const MAX_GROUP_REACTIONS := 8
const MAX_PANIC := 16
const MAX_CORPSES := 24
const MAX_DEATHS := 4096
const DEATH_VERSION := 1
const ACTOR_HEALTH := 90.0
const MAGAZINE := 12
const MELEE_RANGE := 1.85
const SHOT_RANGE := 90.0
const WORLD_MASK := 1 | 2 | 4 | 8 | 16
const PLAN_MASK := 2 | 16
const COMBO_LENGTHS := [0.38, 0.42, 0.56]
const COMBO_HITS := [0.16, 0.18, 0.24]
const HEAR_RADIUS := 30.0
const IMPACT_RADIUS := 10.0
const NEAR_MISS := 1.4
const SAFE_COOLDOWN := 10.0
const PANIC_MIN := 5.0
const FLEE_DISTANCE := 9.0
const FLEE_SPEED := 3.1
const NPC_GUN_RANGE := 26.0
const NPC_AIM_TIME := 0.65
const NPC_SHOT_DAMAGE := 8.0
const STRAY_DAMAGE := 22.0
const CORPSE_TIME := 90.0
const CORPSE_FAR := 55.0
const MELEE_WITNESS_RADIUS := 16.0
const MAX_MELEE_WITNESS_CHECKS := 24
const CORPSE_FADE := 1.5
const MOVE_ARRIVED := 0
const MOVE_TURNING := 1
const MOVE_MOVED := 2
const MOVE_BLOCKED := 3
const BICYCLE_LINES := ["Hey! Watch it!", "Bell, please!", "Careful on that bike!", "Eyes up, 2-Pack!"]
## Bicycle contact: below MIN nothing happens; below KNOCKDOWN the person only
## stumbles (a second stumble within REPEAT_WINDOW starts a grudge); above it
## they go down. One contact per identity per DEDUPE seconds.
const BIKE_CONTACT_MIN := 0.6
const BIKE_KNOCKDOWN_SPEED := 2.2
const BIKE_REPEAT_WINDOW := 10.0
const BIKE_DEDUPE := 1.0
const BIKE_FALL_CLEARANCE := 1.7
const BIKE_FALL_MASK := 1 | 2 | 16
const RISE_TIME := 0.6
## Neighbor-versus-neighbor fists (incidents): the loser goes down, never dies.
const MAX_NPC_FIGHTS := 2
const NPC_FIGHT_SECONDS := 20.0
const NPC_KNOCKOUT_HEALTH := 30.0
const NPC_KNOCKDOWN_TIME := 8.0
var level: Node3D
var player: CharacterBody3D
var health := 100.0
var weapon := "fists"
var ammo := 0
var reserve := 0
var aiming := false
var reloading := 0.0
var downed := 0.0
var combo := 0
# No weapon-key tutorial for controls this build does not have.
var message := "1 Fists · 2 Pistol · 3 Uzi · 4 AK47 · R reload" if PlayMode.PLAYER_COMBAT else ""
var equipment: Dictionary = {"fists": {"owned": true, "ammo": 0, "reserve": 0}, "pistol": {"owned": true, "ammo": 12, "reserve": 72}, "uzi": {"owned": false, "ammo": 0, "reserve": 0}, "ak47": {"owned": false, "ammo": 0, "reserve": 0}}
var _weapon_models: Dictionary = {}
var _trigger_held := false
var _knocked: Dictionary = {}
var _stomp_elapsed := -1.0
var _stomp_id := ""
var _stomp_cue := ""
var _stomp_unlock := 0.0
var _stomp_check := 0.0
var group_events := 0
var last_group_reaction: Dictionary = {}
var hit_flash := 0.0
var damage_flash := 0.0
var _message_time := 5.0 if PlayMode.PLAYER_COMBAT else 0.0
var _attack_elapsed := -1.0
var _attack_hit := false
var _queued_punch := false
var _combo_window := 0.0
var _shot_cooldown := 0.0
var _invulnerable := 0.0
var _since_hurt := 20.0
var _recoil := 0.0
var _active: Dictionary = {}
var _effects: Array[Dictionary] = []
var _gun: Node3D
var _muzzle: Marker3D
var _flash: MeshInstance3D
var _sounds: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _voice_index := 0
var punches_thrown := 0
var shots_fired := 0
var hits_landed := 0
var player_hits := 0
var last_shot: Dictionary = {}
var last_threat: Dictionary = {}
var _panic: Dictionary = {}
var _wounds: Dictionary = {}
var _dead: Dictionary = {}
var _corpses: Array[Dictionary] = []
var _clock := 0.0
var _housekeeping := 0.0
var _flee_query: PhysicsShapeQueryParameters3D
var threat_events := 0
var threat_scanned := 0
var threat_usec := 0
var max_threat_usec := 0
var npc_shots := 0
var npc_hits := 0
var telegraphs := 0
var overflow_hits := 0
var cheap_hits := 0
var deaths := 0
var corpses_cleared := 0
var vehicle_hits := 0
var traffic_notifies := 0
var _occupant_ballistics := OccupantBallistics.new()
var _vehicle_contact_times: Dictionary = {}
var panic_started := 0
var panic_ticks := 0
var flee_casts := 0
var world_audio: Node3D
var assault_events := 0
var assault_witnesses := 0
var last_assault: Dictionary = {}
var bicycle_contacts := 0
var last_bicycle_contact: Dictionary = {}
var bike_knockdowns := 0
var bike_stumbles := 0
var bike_grudges := 0
var last_bicycle_knockdown: Dictionary = {}
var _bike_contacts: Dictionary = {}
var npc_fights_started := 0
var npc_strikes := 0
var npc_knockdowns := 0

func setup(owner_level: Node3D) -> void:
	level = owner_level
	player = level.player
	player.combat = self
	name = "NeighborhoodCombat"
	_build_pistol()
	_build_sounds()
	world_audio = WorldAudio.ensure(level)

func is_available() -> bool:
	return is_instance_valid(player) and player.enabled and not get_tree().paused and (level == null or level.get("paused") != true)

## Whether the explorer may attack at all in this build (city_play_mode.gd).
func player_offense_enabled() -> bool:
	return PlayMode.player_combat_enabled()

func accepts_player_input() -> bool:
	if not player_offense_enabled():
		return false
	# Photography blocks the player's attacks, not incoming damage or NPC AI.
	var driving = level.get("driving") if level != null else null
	var shops = level.get("shops") if level != null else null
	var shopping: bool = shops != null and shops.has_method("is_open") and shops.is_open()
	return is_available() and (player.phone == null or not player.phone.active) and (driving == null or driving.get("active") != true) and not shopping

func cancel_player_actions() -> void:
	_trigger_held = false
	_queued_punch = false
	_attack_elapsed = -1.0
	_stomp_elapsed = -1.0
	_stomp_cue = ""
	aiming = false

## Back to fists without touching ownership or stored rounds.
func _holster_player() -> void:
	_store_equipped()
	weapon = "fists"
	ammo = 0
	reserve = 0
	reloading = 0.0
	cancel_player_actions()
	_update_weapon_model()

func blocks_movement() -> bool:
	return downed > 0.0

func handle_input(event: InputEvent) -> bool:
	if not accepts_player_input():
		return false
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				equip("fists")
				return true
			KEY_2:
				equip("pistol")
				return true
			KEY_3:
				equip("uzi")
				return true
			KEY_4:
				equip("ak47")
				return true
			KEY_R:
				if weapon != "fists":
					request_reload()
					return true
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and weapon != "fists":
			aiming = event.pressed and downed <= 0.0
			player.set_orbiting(false)
			return true
		if event.button_index == MOUSE_BUTTON_LEFT:
			# Match the level's explicit offscreen input route without capturing
			# the desktop cursor. Normal gameplay still requires mouse capture.
			var pointer_ready: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or (level != null and level.get("offscreen_validation") == true)
			_trigger_held = event.pressed and weapon != "fists" and pointer_ready
			if event.pressed and pointer_ready:
				request_attack()
			return true
	return false

func equip(selection: String) -> void:
	if downed > 0.0 or not equipment.has(selection):
		return
	if selection != "fists" and not player_offense_enabled():
		return
	if not bool(equipment[selection].owned):
		_notice("%s not owned" % str(Weapons.profile(selection).label), 1.5)
		return
	_store_equipped()
	weapon = selection
	ammo = int(equipment[weapon].ammo)
	reserve = int(equipment[weapon].reserve)
	aiming = false
	_trigger_held = false
	_stomp_elapsed = -1.0
	_stomp_cue = ""
	reloading = 0.0
	_attack_elapsed = -1.0
	_queued_punch = false
	combo = 0
	player.set_orbiting(false)
	_update_weapon_model()
	if player_offense_enabled():
		_notice("Fists ready · punches knock down; a later stomp is lethal" if weapon == "fists" else "%s ready · RMB aim · R reload" % str(Weapons.profile(weapon).label), 3.0)

func request_reload() -> bool:
	if not accepts_player_input() or downed > 0.0 or weapon == "fists" or reloading > 0.0 or ammo >= int(Weapons.profile(weapon).magazine) or reserve <= 0:
		return false
	reloading = float(Weapons.profile(weapon).reload)
	_trigger_held = false
	_sound("click")
	_notice("Reloading…", reloading)
	return true

func request_attack() -> bool:
	if not accepts_player_input() or downed > 0.0 or player.impact_recovery > 0.0 or reloading > 0.0 or _stomp_elapsed >= 0.0:
		return false
	if weapon != "fists":
		return _fire()
	if _attack_elapsed >= 0.0:
		# One deliberate click can buffer the next beat; holding LMB never repeats.
		if _attack_elapsed >= 0.10 and combo < 3:
			_queued_punch = true
		return false
	var fallen := _nearest_knocked()
	if not fallen.is_empty():
		if _clock < _stomp_unlock:
			return false
		_stomp_id = fallen
		_stomp_elapsed = 0.0
		_stomp_cue = ""
		_queued_punch = false
		_notice("Stomp · lethal finisher", 0.8)
		_sound("swing")
		return true
	_start_punch()
	return true

func _start_punch() -> void:
	if not player_offense_enabled():
		return
	combo = combo + 1 if _combo_window > 0.0 and combo < 3 else 1
	_attack_elapsed = 0.0
	_attack_hit = false
	_queued_punch = false
	_combo_window = 0.0
	punches_thrown += 1
	_sound("swing")
	_notice(["Jab", "Cross", "Knockdown strike"][combo - 1], 0.6)

func _store_equipped() -> void:
	if weapon != "fists" and equipment.has(weapon):
		equipment[weapon].ammo = ammo
		equipment[weapon].reserve = reserve

func grant_weapon(id: String) -> bool:
	if not equipment.has(id):
		return false
	if bool(equipment[id].owned):
		return false
	equipment[id].owned = true
	if id != "fists":
		equipment[id].ammo = int(Weapons.profile(id).magazine)
	return true

func add_ammo(id: String, count: int) -> int:
	if id == "fists" or not equipment.has(id) or count <= 0:
		return 0
	_store_equipped()
	var before := int(equipment[id].reserve)
	var added := mini(count, Weapons.MAX_RESERVE - before)
	equipment[id].reserve = before + added
	if id == weapon:
		reserve = int(equipment[id].reserve)
	return added

func equipment_snapshot() -> Dictionary:
	_store_equipped()
	return {"version": 1, "equipped": weapon, "weapons": equipment.duplicate(true)}

func restore_equipment(data: Dictionary) -> bool:
	if not validate_equipment(data):
		return false
	var restored: Dictionary = {}
	for id in equipment:
		var value: Variant = data.weapons.get(id, {})
		if not value is Dictionary:
			return false
		var capacity := 0 if id == "fists" else int(Weapons.profile(id).magazine)
		restored[id] = {"owned": id == "fists" or value.get("owned", false) == true,
			"ammo": clampi(int(value.get("ammo", 0)), 0, capacity),
			"reserve": clampi(int(value.get("reserve", 0)), 0, Weapons.MAX_RESERVE)}
	var selected := str(data.get("equipped", "fists"))
	if not restored.has(selected) or not bool(restored[selected].owned):
		selected = "fists"
	# Ownership and rounds are kept verbatim; only the drawn weapon is holstered.
	if not player_offense_enabled():
		selected = "fists"
	equipment = restored
	weapon = selected
	ammo = int(equipment[selected].ammo)
	reserve = int(equipment[selected].reserve)
	aiming = false
	reloading = 0.0
	_trigger_held = false
	_attack_elapsed = -1.0
	_queued_punch = false
	_stomp_elapsed = -1.0
	_stomp_cue = ""
	_update_weapon_model()
	return true

func validate_equipment(data: Dictionary) -> bool:
	var version: Variant = data.get("version")
	if not (version is int or version is float) or version != 1 or not data.get("weapons") is Dictionary:
		return false
	var selected := str(data.get("equipped", ""))
	if not equipment.has(selected):
		return false
	for id in equipment:
		var value: Variant = data.weapons.get(id)
		if not value is Dictionary or not value.get("owned") is bool:
			return false
		for field in ["ammo", "reserve"]:
			if not (value.get(field) is int or value.get(field) is float):
				return false
			var count := float(value[field])
			var cap := 0 if id == "fists" else (Weapons.MAX_RESERVE if field == "reserve" else int(Weapons.profile(id).magazine))
			if not is_finite(count) or count != floor(count) or count < 0 or count > cap:
				return false
	return data.weapons.fists.owned == true and data.weapons[selected].owned == true

func _update_weapon_model() -> void:
	if not is_instance_valid(_gun):
		return
	_gun.visible = weapon != "fists"
	for id in _weapon_models:
		_weapon_models[id].visible = id == weapon
	_muzzle.position = Vector3(0, 0.035, {"pistol": 0.22, "uzi": 0.31, "ak47": 0.67}.get(weapon, 0.22))

func _identity_of(body: Object) -> String:
	if not is_instance_valid(body):
		return ""
	if body is Actor:
		return str(body.actor_id)
	if _is_crowd_body(body):
		return "crowd_%d" % int(body.get_meta("city_crowd_index"))
	return ""

func _knock_down(id: String, actor, crowd_index: int, state: Dictionary) -> void:
	# The bounded downed set also covers an overflow victim without silently
	# killing them or growing the normal fighter set. Oldest gets up if full.
	if _knocked.size() >= MAX_DOWNED:
		_recover_knocked(str(_knocked.keys()[0]))
	if actor == null:
		actor = _promote_crowd(crowd_index, true)
		if actor == null:
			_wounds[id] = {"hp": 1.0, "time": _clock}
			return
	if state.is_empty():
		state = _new_state(actor, crowd_index)
	_active.erase(actor.get_instance_id())
	_panic.erase(actor.get_instance_id())
	_holster(state)
	state.health = 1.0
	state.mode = "downed"
	state.attack = -1.0
	state.aim = -1.0
	actor.combat_override = true
	actor.velocity = Vector3.ZERO
	actor.moving = false
	actor._speech_remaining = 0.0
	actor._speech_label.hide()
	var original_capsule: Transform3D = actor.capsule.transform
	var base_y: float = actor.puppet.g.position.y
	# A horizontal capsule keeps bullets/footsteps aligned with the downed body.
	actor.capsule.rotation = Vector3(-PI * 0.5, actor.yaw, 0)
	actor.capsule.position = Basis(Vector3.UP, actor.yaw) * Vector3(0, 0.28, -float(actor.capsule.shape.height) * 0.45)
	_knocked[id] = {"actor": actor, "state": state, "time": 0.0, "fall": 0.0,
		"capsule": original_capsule, "base_y": base_y, "id": id}
	_queued_punch = false
	_combo_window = 0.0
	_stomp_unlock = _clock + 0.75
	_notice("Knocked down · spare them or approach and click again to stomp", 2.5)

func _nearest_knocked() -> String:
	if not is_instance_valid(player) or downed > 0.0:
		return ""
	var best := ""
	var distance := STOMP_RANGE
	var forward := Vector3(sin(player.yaw), 0, cos(player.yaw))
	for id in _knocked:
		var actor = _knocked[id].actor
		if not is_instance_valid(actor) or actor.dead or bool(_knocked[id].get("nonlethal", false)):
			continue
		var offset: Vector3 = actor.global_position - player.global_position
		if absf(offset.y) > 0.8:
			continue
		offset.y = 0.0
		if offset.length() > distance or (offset.length() > 0.25 and forward.dot(offset.normalized()) < 0.15):
			continue
		if _sight(player.global_position + Vector3.UP, actor.global_position + Vector3.UP * 0.3, player, actor):
			best = str(id)
			distance = offset.length()
	return best

func _finish_stomp() -> void:
	if not _knocked.has(_stomp_id) or _nearest_knocked() != _stomp_id or not accepts_player_input() or downed > 0.0:
		return
	var entry: Dictionary = _knocked[_stomp_id]
	var actor = entry.actor
	var at: Vector3 = actor.global_position
	player_offense.emit("stomp", at, _stomp_id)
	_melee_assault_event(player.global_position + Vector3.UP, at + Vector3.UP * 0.3, actor)
	_group_assault(_stomp_id, actor, at, player.global_position)
	_world_sound("hit", at)
	hits_landed += 1
	hit_flash = 0.18
	_kill(_stomp_id, actor, int(entry.state.crowd_index), entry.state, player.global_position)

func _tick_knockdowns(delta: float) -> void:
	for id in _knocked.keys():
		var entry: Dictionary = _knocked[id]
		var actor = entry.actor
		if not is_instance_valid(actor):
			_knocked.erase(id)
			continue
		entry.time += delta
		entry.fall = minf(1.0, float(entry.fall) + delta * 3.5)
		var fall := smoothstep(0.0, 1.0, float(entry.fall))
		var limit := float(entry.get("limit", KNOCKDOWN_TIME))
		if entry.has("fall_yaw"):
			# Nonlethal knockdowns fall along the push and get up over RISE_TIME.
			fall *= 1.0 - smoothstep(0.0, 1.0, clampf((float(entry.time) - limit + RISE_TIME) / RISE_TIME, 0.0, 1.0))
			var yaw := lerp_angle(float(entry.from_yaw), float(entry.fall_yaw), smoothstep(0.0, 1.0, float(entry.fall)))
			if bool(entry.flat):
				actor.puppet.g.rotation = Vector3(-PI * 0.5 * fall, yaw, 0)
				actor.puppet.g.position.y = float(entry.base_y) + 0.16 * fall
			else:
				# No clear ground to lie on: sit down where they stand.
				actor.puppet.g.rotation = Vector3(-0.5 * fall, yaw, 0)
				actor.puppet.g.position.y = float(entry.base_y) - 0.38 * fall
			_tick_body_clock(actor, delta)
		else:
			actor.puppet.g.rotation = Vector3(-PI * 0.5 * fall, actor.yaw, 0)
			actor.puppet.g.position.y = float(entry.base_y) + 0.16 * fall
		actor.puppet.pose({"armR": [-0.3, 0.3], "armL": [-0.3, 0.3]})
		if float(entry.time) >= limit:
			_recover_knocked(str(id))

func _recover_knocked(id: String) -> void:
	if not _knocked.has(id):
		return
	var entry: Dictionary = _knocked[id]
	_knocked.erase(id)
	var actor = entry.actor
	if not is_instance_valid(actor) or actor.dead:
		return
	if entry.has("fall_yaw"):
		actor.yaw = float(entry.fall_yaw)
	actor.capsule.transform = entry.capsule
	actor.puppet.g.rotation = Vector3(0, actor.yaw, 0)
	actor.puppet.g.position.y = float(entry.base_y)
	if str(entry.get("kind", "")) == "bicycle":
		bicycle_recovered.emit(id)
		if _bike_grudge(actor, int(entry.state.get("crowd_index", -1)), entry.state):
			return
	_release(entry.state)

func recover_player() -> void:
	health = 100.0
	downed = 0.0
	_invulnerable = 3.0
	_since_hurt = 20.0
	_trigger_held = false
	_queued_punch = false
	_attack_elapsed = -1.0
	_stomp_elapsed = -1.0
	reloading = 0.0
	aiming = false
	for state in _active.values().duplicate():
		if str(state.get("foe_id", "")).is_empty():
			_release(state)
	for state in _panic.values().duplicate():
		_release(state)
	var crowd = _crowd()
	if crowd != null:
		for index in crowd._panic.keys():
			crowd._finish_panic(int(index), false)

## Read-only ownership API for law; never changes an actor's current state.
func actor_mode(actor) -> String:
	if not is_instance_valid(actor):
		return "gone"
	if actor.get("dead") == true:
		return "dead"
	if _knocked.has(str(actor.get("actor_id"))):
		return "downed"
	var key: int = actor.get_instance_id()
	if _active.has(key):
		return str(_active[key].get("mode", "aggro"))
	if _panic.has(key):
		return "panic:" + str(_panic[key].get("mode", ""))
	return "unknown" if actor.get("combat_override") == true else ""

func disengage_actor(actor) -> void:
	if not is_instance_valid(actor):
		return
	var key: int = actor.get_instance_id()
	var state: Dictionary = _active.get(key, _panic.get(key, {}))
	if not state.is_empty():
		_release(state)

## Read-only, bounded source for police incident discovery. "provoked" marks a
## grudge the player caused (a bicycle crash): police never treat it as a crime.
## "foe" names the neighbor an incident fighter is hitting.
func fighter_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for state in _active.values():
		result.append({"actor": state.actor, "id": state.id, "mode": state.mode,
			"aim": state.aim, "shots": state.shots, "provoked": str(state.get("provoked", "")),
			"foe": str(state.get("foe_id", "")), "incident_id": str(state.get("incident_id", ""))})
	return result

## Police retain NPC damage and permanent death without attributing an attack
## to the nonviolent player or rewarding/penalizing their wallet or alignment.
func receive_police_round(body, damage: float, origin: Vector3, _officer_id: String) -> bool:
	return _damage_target(body, damage, "police", origin, false)

func receive_police_gunfire(muzzle: Vector3, endpoint: Vector3, struck) -> void:
	_gunshot_event(muzzle, muzzle, endpoint, false, struck)
	_world_sound("shot", muzzle)

func engage_actor(actor, armed := true) -> bool:
	if not is_instance_valid(actor) or actor.dead or not actor.enabled:
		return false
	return _engage(actor, "gun" if armed else "aggro")

## Incident fistfight: `aggressor` chases and hits `victim` (actor, crowd body or
## identity). Nonlethal: below NPC_KNOCKOUT_HEALTH the victim is knocked down.
## The victim flees through the bounded panic path unless options.mutual. Never
## a player offense, law event or group reaction; budgeted by MAX_ACTIVE and
## MAX_NPC_FIGHTS. options: {seconds, incident_id, mutual}.
func start_npc_fight(aggressor, victim, options := {}) -> Dictionary:
	var result := {"ok": false, "aggressor_id": "", "victim_id": "", "reason": ""}
	var a := _person_of(aggressor)
	var v := _person_of(victim)
	result.aggressor_id = str(a.id)
	result.victim_id = str(v.id)
	if str(a.id).is_empty() or str(v.id).is_empty() or str(a.id) == str(v.id):
		result.reason = "invalid_people"
	elif _npc_fight_count() >= MAX_NPC_FIGHTS:
		result.reason = "fight_budget"
	elif not _fightable(a) or not _fightable(v):
		result.reason = "unavailable"
	if not str(result.reason).is_empty():
		return result
	var state := _fighter_for(a.actor, int(a.crowd_index), "aggro")
	if state.is_empty():
		result.reason = "fight_budget"
		return result
	_aim_fight(state, v, options, true)
	if bool(options.get("mutual", false)) and v.actor != null:
		var other := _fighter_for(v.actor, int(v.crowd_index), "aggro")
		if not other.is_empty():
			_aim_fight(other, {"id": str(a.id), "actor": state.actor, "crowd_index": -1}, options, false)
	npc_fights_started += 1
	result.ok = true
	return result

func stop_npc_fight(target) -> bool:
	var id := str(_person_of(target).id)
	var stopped := false
	for state in _active.values().duplicate():
		if not str(state.get("foe_id", "")).is_empty() and (str(state.id) == id or str(state.foe_id) == id):
			_end_npc_fight(state)
			stopped = true
	return stopped

func npc_fight_status(id: String) -> Dictionary:
	for state in _active.values():
		if str(state.id) == id:
			return {"fighting": not str(state.get("foe_id", "")).is_empty(), "foe": str(state.get("foe_id", "")),
				"mode": str(state.mode), "health": float(state.health), "knocked": false,
				"incident_id": str(state.get("incident_id", "")), "actor": state.actor}
	if _knocked.has(id):
		var entry: Dictionary = _knocked[id]
		return {"fighting": false, "foe": "", "mode": "downed", "health": float(entry.state.health), "knocked": true,
			"incident_id": "", "actor": entry.actor}
	return {"fighting": false, "foe": "", "mode": "", "health": _wound_hp(id), "knocked": false, "incident_id": "", "actor": null}

func _aim_fight(state: Dictionary, foe: Dictionary, options: Dictionary, primary: bool) -> void:
	_holster(state)
	state.mode = "aggro"
	state.foe_id = str(foe.id)
	state.foe = foe.actor
	state.foe_index = int(foe.crowd_index) if foe.actor == null else -1
	state.fight_primary = primary
	state.incident_id = str(options.get("incident_id", ""))
	state.fight_limit = clampf(float(options.get("seconds", NPC_FIGHT_SECONDS)), 4.0, 40.0)
	state.time = 0.0
	state.unseen = 0.0
	state.attack = -1.0
	state.cooldown = 0.4
	state.sight_left = 0.0
	state.sees_foe = true

func _npc_fight_count() -> int:
	var count := 0
	for state in _active.values():
		count += int(not str(state.get("foe_id", "")).is_empty() and bool(state.get("fight_primary", false)))
	return count

func _fightable(person: Dictionary) -> bool:
	var id := str(person.id)
	if _dead.has(id) or _knocked.has(id):
		return false
	var actor = person.actor
	if actor != null:
		return is_instance_valid(actor) and not actor.dead and actor.enabled and not _is_police(actor) \
			and not actor.has_meta("police_custody") and not actor.has_meta("law_responder") and not actor.has_meta("police_assist")
	return _crowd_available(int(person.crowd_index))

## {id, actor, crowd_index}: a full body (crowd_index set when it stands in for
## a crowd slot) or a bare crowd slot (actor null). {"id": ""} when unknown.
func _person_of(target) -> Dictionary:
	if target is String:
		var id: String = target
		for state in _active.values() + _panic.values():
			if str(state.get("id", "")) == id and is_instance_valid(state.actor):
				return {"id": id, "actor": state.actor, "crowd_index": int(state.crowd_index)}
		if _knocked.has(id) and is_instance_valid(_knocked[id].actor):
			return {"id": id, "actor": _knocked[id].actor, "crowd_index": int(_knocked[id].state.get("crowd_index", -1))}
		if id.begins_with("crowd_") and id.substr(6).is_valid_int():
			return {"id": id, "actor": null, "crowd_index": int(id.substr(6))}
		var found = null
		if level != null and level.npcs != null:
			found = level.npcs.actors.get(id)
		var residents = level.get("residents") if level != null else null
		if found == null and residents != null and residents.get("actors") is Dictionary:
			found = residents.actors.get(id)
		if is_instance_valid(found) and found is Actor:
			return {"id": id, "actor": found, "crowd_index": _proxy_index(found)}
		return {"id": "", "actor": null, "crowd_index": -1}
	if _is_crowd_body(target):
		var index := int(target.get_meta("city_crowd_index"))
		return {"id": "crowd_%d" % index, "actor": null, "crowd_index": index}
	if is_instance_valid(target) and target is Actor:
		return {"id": str(target.actor_id), "actor": target, "crowd_index": _proxy_index(target)}
	return {"id": "", "actor": null, "crowd_index": -1}

## A body another system promoted for a crowd slot (incidents) names the slot,
## so combat's own release returns it to the crowd instead of orphaning it.
func _proxy_index(actor) -> int:
	if is_instance_valid(actor) and actor.has_meta("crowd_proxy_index"):
		return int(actor.get_meta("crowd_proxy_index"))
	return -1

func _crowd_available(index: int) -> bool:
	var crowd = _crowd()
	if crowd == null or index < 0 or index >= crowd.residents.size():
		return false
	var record: Dictionary = crowd.residents[index]
	return not record.get("dead", false) and not record.get("combat_controlled", false) \
		and not record.get("police_custody", false) and is_instance_valid(record.get("body"))

## Group lookup is a startup index, never a global proximity grouping on attack.
## Only nearby visible members react; each uses their own stable disposition.
func _group_assault(victim_id: String, victim, at: Vector3, origin: Vector3) -> void:
	var members: Array = []
	var group := ""
	var crowd = _crowd()
	if victim_id.begins_with("crowd_") and crowd != null:
		var index := int(victim_id.substr(6))
		group = crowd.social_group_id(index)
		for other in crowd.social_group_members(index, MAX_GROUP_REACTIONS + 1):
			if int(other) == index:
				continue
			var record: Dictionary = crowd.residents[int(other)]
			members.append({"id": "crowd_%d" % int(other), "index": int(other), "actor": null,
				"body": record.get("body"), "at": record.position})
	elif is_instance_valid(victim):
		group = str(victim.get_meta("social_group_id", ""))
		if not group.is_empty():
			for actor in _people():
				if actor != victim and str(actor.get_meta("social_group_id", "")) == group:
					members.append({"id": str(actor.actor_id), "index": -1, "actor": actor, "body": actor, "at": actor.global_position})
	if group.is_empty():
		return
	group_events += 1
	var reacted: Array[String] = []
	var checked := 0
	for member in members:
		if checked >= MAX_GROUP_REACTIONS:
			break
		var id := str(member.id)
		var body: CollisionObject3D = member.body
		if id == victim_id or _dead.has(id) or _knocked.has(id) or not is_instance_valid(body) or body.collision_layer == 0:
			continue
		if _flat_distance(member.at, at) > GROUP_RADIUS or _flat_distance(member.at, origin) > GROUP_RADIUS:
			continue
		checked += 1
		if not _sight(member.at + Vector3.UP * 1.2, player.global_position + Vector3.UP * 1.1, body, player):
			continue
		var mode := default_reaction(id, member.actor != null and _is_police(member.actor))
		var accepted := false
		if mode != "flee":
			accepted = not _fighter_for(member.actor, int(member.index), mode).is_empty()
		if not accepted:
			if int(member.index) >= 0:
				accepted = crowd.panic_resident(int(member.index), origin)
			else:
				accepted = _panic_actor(member.actor, origin, "flee")
		if accepted:
			reacted.append(id)
	last_group_reaction = {"group": group, "victim": victim_id, "checked": checked, "reacted": reacted}

static func default_reaction(id: String, police := false) -> String:
	if is_armed_id(id, police):
		return "gun"
	return "aggro" if stable_hash(id) % 2 == 0 else "flee"

func tick(delta: float) -> void:
	if not is_available():
		aiming = false
		_queued_punch = false
		_trigger_held = false
		return
	delta = minf(delta, 0.1)
	_shot_cooldown = maxf(0.0, _shot_cooldown - delta)
	_invulnerable = maxf(0.0, _invulnerable - delta)
	_recoil = maxf(0.0, _recoil - delta)
	hit_flash = maxf(0.0, hit_flash - delta)
	damage_flash = maxf(0.0, damage_flash - delta)
	_message_time = maxf(0.0, _message_time - delta)
	_since_hurt += delta
	_flash.visible = _recoil > 0.075 and weapon != "fists"
	for effect in _effects.duplicate():
		effect.time -= delta
		if effect.time <= 0.0:
			effect.node.queue_free()
			_effects.erase(effect)
	_clock += delta
	if not _knocked.is_empty():
		_tick_knockdowns(delta)
	if not accepts_player_input():
		_trigger_held = false
	if weapon != "fists" and not player_offense_enabled():
		_holster_player()
	if _trigger_held and weapon != "fists" and bool(Weapons.profile(weapon).automatic) and reloading <= 0.0:
		request_attack()
	if _stomp_elapsed >= 0.0:
		var before_stomp := _stomp_elapsed
		_stomp_elapsed += delta
		if before_stomp < 0.28 and _stomp_elapsed >= 0.28:
			_finish_stomp()
		if _stomp_elapsed >= 0.65:
			_stomp_elapsed = -1.0
			_stomp_id = ""
	_stomp_check -= delta
	if _stomp_check <= 0.0:
		_stomp_check = 0.1
		var cue := _nearest_knocked() if player_offense_enabled() and weapon == "fists" and _attack_elapsed < 0.0 and _stomp_elapsed < 0.0 and _clock >= _stomp_unlock else ""
		if cue != _stomp_cue:
			_stomp_cue = cue
			if not cue.is_empty():
				_notice("LMB · Stomp (lethal) · walk away to spare them", 1.0)
	# Bystanders keep fleeing and corpses keep their budget during a knockdown.
	panic_ticks = 0
	for id in _panic.keys():
		if _panic.has(id):
			_tick_panic_actor(id, _panic[id], delta)
	if not _corpses.is_empty():
		_tick_corpses(delta)
	_housekeeping += delta
	if _housekeeping >= 2.0:
		_housekeeping = 0.0
		# Survivors heal once nobody has hurt them for a while; deaths are permanent.
		for id in _wounds.keys():
			if _clock - float(_wounds[id].time) > 30.0:
				_wounds.erase(id)
	if downed > 0.0:
		if level.get("law") != null:
			return # Recovery is owned by law; no automatic full-health escape.
		downed = maxf(0.0, downed - delta)
		if downed <= 0.0:
			recover_player()
			_notice("Back on your feet · walk away to cool things down", 4.0)
		return
	if reloading > 0.0:
		reloading = maxf(0.0, reloading - delta)
		if reloading <= 0.0:
			var amount := mini(int(Weapons.profile(weapon).magazine) - ammo, reserve)
			ammo += amount
			reserve -= amount
			_store_equipped()
			_notice("Reloaded", 1.0)
	if _attack_elapsed >= 0.0:
		_attack_elapsed += delta
		if not _attack_hit and _attack_elapsed >= COMBO_HITS[combo - 1]:
			_attack_hit = true
			_punch_hit()
		if _attack_elapsed >= COMBO_LENGTHS[combo - 1]:
			_attack_elapsed = -1.0
			_combo_window = 0.55
			if _queued_punch and combo < 3:
				_start_punch()
	else:
		_combo_window = maxf(0.0, _combo_window - delta)
		if _combo_window <= 0.0:
			combo = 0
	for id in _active.keys():
		if _active.has(id):
			_tick_actor(_active[id], delta)
	if _since_hurt > 8.0 and not _has_aggressors():
		health = minf(100.0, health + delta * 8.0)

func _has_aggressors() -> bool:
	for state in _active.values():
		if (state.mode == "aggro" or state.mode == "gun") and str(state.get("foe_id", "")).is_empty():
			return true
	return false

func _ray(from: Vector3, to: Vector3, exclude: Array[RID], hit_inside := true) -> Dictionary:
	if from.distance_squared_to(to) < 0.000001:
		return {}
	var query := PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK, exclude)
	query.hit_from_inside = hit_inside
	return get_world_3d().direct_space_state.intersect_ray(query)

func _sight(from: Vector3, to: Vector3, source: CollisionObject3D, target_body: CollisionObject3D) -> bool:
	if target_body == player and _occupied_car() != null:
		return not _driver_hit(from, _player_aim_point(), [source.get_rid()]).is_empty()
	var hit := _ray(from, to, [source.get_rid()])
	if hit.is_empty() or hit.collider == target_body:
		return true
	# Riding disables the player's capsule; the chest point then lies inside
	# the bicycle hull. Accept only that occupied hull as the first hit, never
	# a parked bicycle, unrelated vehicle or intervening scenery. Car occupants
	# keep their separate ballistic test above.
	var bicycle = level.get("bicycle") if target_body == player and level != null else null
	return is_instance_valid(bicycle) and bicycle is CollisionObject3D and bicycle.get("active") == true \
		and player.get("seated_vehicle") == bicycle and hit.collider == bicycle

func _occupied_car() -> CollisionObject3D:
	var driving = level.get("driving") if level != null else null
	if driving == null or driving.get("active") != true:
		return null
	return driving.get("vehicle") as CollisionObject3D

func _player_aim_point() -> Vector3:
	var car := _occupied_car()
	var presentation = level.get("vehicle_presentation") if level != null else null
	if car != null and presentation != null:
		var zones: Array = presentation.get_occupant_hit_zones(car)
		if not zones.is_empty():
			return zones[0].center
	return player.global_position + Vector3.UP * 1.1

## Virtual targets are needed because the walking capsule is disabled in a car.
## Actual glass AND the opened body mesh arbitrate cabin penetration. Excluding
## only this vehicle from the final world ray still leaves every wall/car solid.
func _driver_hit(from: Vector3, to: Vector3, exclude: Array[RID]) -> Dictionary:
	var car := _occupied_car()
	var presentation = level.get("vehicle_presentation") if level != null else null
	if car == null or presentation == null:
		return {}
	var model = car.get("model")
	var body: MeshInstance3D = model.get_node_or_null("Body") if is_instance_valid(model) else null
	if body == null:
		return {}
	var best := Vector3.INF
	for zone in presentation.get_occupant_hit_zones(car):
		var point := OccupantBallistics.sphere_hit(from, to, zone.center, float(zone.radius))
		if point.is_finite() and (not best.is_finite() or from.distance_squared_to(point) < from.distance_squared_to(best)):
			best = point
	if not best.is_finite() or not _occupant_ballistics.window_path(body, from, best):
		return {}
	var exclusions: Array[RID] = exclude.duplicate()
	exclusions.append(car.get_rid())
	var obstruction := _ray(from, best, exclusions)
	if not obstruction.is_empty() and obstruction.get("collider") != player:
		return {}
	return {"collider": player, "position": best, "occupied_driver": true}

## Driving reports consequential contact once, but dedupe again at this boundary
## so a resting bumper cannot repeatedly hurt a person or manufacture crimes.
func receive_vehicle_collision(contact: Dictionary) -> bool:
	var speed := float(contact.get("relative_speed", contact.get("speed", 0.0)))
	var body = contact.get("collider")
	if not is_available() or not is_finite(speed) or speed < 2.5 or not is_instance_valid(body):
		return false
	var key: int = body.get_instance_id()
	if _clock - float(_vehicle_contact_times.get(key, -10.0)) < 1.0:
		return false
	_vehicle_contact_times[key] = _clock
	if _vehicle_contact_times.size() > 32:
		for previous in _vehicle_contact_times.keys():
			if _clock - float(_vehicle_contact_times[previous]) > 2.0:
				_vehicle_contact_times.erase(previous)
	var at: Vector3 = contact.get("point", contact.get("position", player.global_position))
	var person := body is Actor or _is_crowd_body(body)
	if person and _damage_target(body, clampf((speed - 2.0) * 7.0, 4.0, 120.0), "vehicle", player.global_position):
		player_offense.emit("vehicle_assault", at, _identity_of(body))
		return true
	# Severe impacts hurt the driver too. Small parking scrapes have no criminal
	# consequence; hitting another car at speed is reported through witness law.
	if speed >= 8.0:
		_hurt_player(clampf((speed - 7.0) * 1.8, 1.0, 35.0))
	var vehicle_contact: bool = str(contact.get("kind", "")) == "vehicle" or (body is CollisionObject3D and body.has_method("apply_body_damage"))
	if vehicle_contact and speed >= 5.0:
		var victim := str(contact.get("other_vehicle_id", ""))
		if victim.is_empty() and body.has_method("apply_body_damage"):
			victim = str(body.get("vehicle_id"))
		player_offense.emit("vehicle_collision", at, victim)
		return true
	return false

## Player movement already verifies the swept impact and enforces a stumble
## cooldown. Traffic damage shares health/recovery with bullets and punches.
func receive_traffic_impact(hit_speed: float, _source: String) -> void:
	if is_finite(hit_speed) and hit_speed >= 2.5 and _occupied_car() == null:
		_hurt_player(clampf((hit_speed - 2.0) * 4.0, 2.0, 75.0))

## Social-only response to a city_bicycle.pedestrian_contact payload
## ({"collider", "position", "speed", "harmless", ...}). Contract: never deals
## damage, never moves, turns, knocks down, panics or engages anyone, never
## emits player_offense and never reaches law or progression, so a bump can be
## neither a crime nor rewarded. A full actor who is free (alive, enabled, not
## combat- or law-controlled) says one short line; crowd residents are only
## counted. Returns true when someone spoke. Repeat contacts are already rate
## limited by the bicycle (2 s per collider). Safe in every PlayMode.
func receive_bicycle_contact(contact: Dictionary) -> bool:
	var body = contact.get("collider")
	if not is_available() or not is_instance_valid(body):
		return false
	bicycle_contacts += 1
	var id := _identity_of(body)
	last_bicycle_contact = {"id": id, "speed": float(contact.get("speed", 0.0)), "reacted": false}
	if not body is Actor or body.dead or not body.enabled or body.combat_override or body.has_meta("law_responder"):
		return false
	body.speak(BICYCLE_LINES[posmod(stable_hash("%s:%d" % [id, bicycle_contacts]), BICYCLE_LINES.size())], 1.6)
	last_bicycle_contact.reacted = true
	return true

## A bicycle crash into a pedestrian (the bike's contact payload via the root
## bridge). Nonlethal by construction: no damage or health change, no death, no
## stomp, never player_offense, law, progression or an incident. A hard contact
## lays the person down with the knockdown rig (no ragdoll); once up they go
## after the rider with fists whatever their usual armed disposition. Police,
## on-duty responders and people in custody only stumble. `target`: actor, crowd
## body or identity; `impulse`: world push (fall direction and strength).
func knockdown_from_bicycle(target, contact_speed: float, impulse := Vector3.ZERO, context := {}) -> Dictionary:
	var result := {"ok": false, "id": "", "outcome": "ignored", "reason": "", "down_seconds": 0.0, "aggro": false, "deduped": false}
	var person := _person_of(target)
	var id := str(person.id)
	var actor = person.actor
	var crowd_index := int(person.crowd_index)
	result.id = id
	if id.is_empty():
		result.reason = "unknown_target"
	elif not is_finite(contact_speed) or contact_speed < BIKE_CONTACT_MIN:
		result.reason = "too_slow"
	elif _dead.has(id) or (actor != null and (actor.dead or not actor.enabled)) or (actor == null and not _crowd_available(crowd_index)):
		result.reason = "unavailable"
	elif _knocked.has(id):
		result.reason = "already_down"
	if not str(result.reason).is_empty():
		return _bike_result(result)
	var memory: Dictionary = _bike_contacts.get(id, {})
	var since := _clock - float(memory.get("time", -INF))
	if since < BIKE_DEDUPE:
		result.deduped = true
		result.reason = "repeat_contact"
		return _bike_result(result)
	var repeats: int = int(memory.get("count", 0)) + 1 if since <= BIKE_REPEAT_WINDOW else 1
	_bike_contacts[id] = {"time": _clock, "count": repeats}
	if _bike_contacts.size() > 32:
		for key in _bike_contacts.keys():
			if _clock - float(_bike_contacts[key].time) > BIKE_REPEAT_WINDOW:
				_bike_contacts.erase(key)
	result.ok = true
	result.outcome = "stumbled"
	var exempt := _bike_exempt(actor, crowd_index)
	if not exempt.is_empty():
		result.reason = exempt
		if actor != null and exempt == "police" and not actor.combat_override:
			actor.speak(BICYCLE_LINES[posmod(stable_hash("%s:%d" % [id, repeats]), BICYCLE_LINES.size())], 1.6)
		return _bike_result(result)
	if contact_speed < BIKE_KNOCKDOWN_SPEED:
		if repeats >= 2:
			result.reason = "repeated"
			result.aggro = _bike_grudge(actor, crowd_index, {})
		elif actor != null and not actor.combat_override:
			actor.speak(BICYCLE_LINES[posmod(stable_hash("%s:%d" % [id, repeats]), BICYCLE_LINES.size())], 1.6)
		return _bike_result(result)
	var push := Vector3(impulse.x, 0.0, impulse.z)
	if push.length_squared() < 0.0001 and context.get("direction") is Vector3:
		push = Vector3(context.direction.x, 0.0, context.direction.z)
	var at: Vector3 = actor.global_position if actor != null else _crowd().resident_position(crowd_index)
	if push.length_squared() < 0.0001 and is_instance_valid(player):
		push = Vector3(at.x - player.global_position.x, 0.0, at.z - player.global_position.z)
	var seconds := clampf(1.6 + 0.35 * contact_speed + minf(push.length(), 40.0) * 0.01, 2.0, 4.5)
	var yaw := _fall_yaw_along(push) if push.length_squared() > 0.0001 else INF
	if not _lay_down(id, actor, crowd_index, yaw, seconds, "bicycle"):
		result.reason = "no_body"
		return _bike_result(result)
	result.outcome = "knocked_down"
	result.down_seconds = seconds
	result.aggro = true
	return _bike_result(result)

## Stands a bicycle-knocked person up now (root reset, checkpoint, fixtures).
## Their grudge follows as usual; dead or unknown identities return false.
func recover_from_bicycle(id: String) -> bool:
	if not _knocked.has(id) or str(_knocked[id].get("kind", "")) != "bicycle":
		return false
	_recover_knocked(id)
	return true

func is_bicycle_knockdown(id: String) -> bool:
	return _knocked.has(id) and str(_knocked[id].get("kind", "")) == "bicycle"

func bicycle_knockdown_status(id: String) -> Dictionary:
	var grudge := false
	for state in _active.values():
		if str(state.id) == id and str(state.get("provoked", "")) == "bicycle":
			grudge = true
	if not is_bicycle_knockdown(id):
		return {"down": false, "remaining": 0.0, "grudge": grudge}
	var entry: Dictionary = _knocked[id]
	return {"down": true, "remaining": maxf(0.0, float(entry.limit) - float(entry.time)), "grudge": grudge}

func _bike_result(result: Dictionary) -> Dictionary:
	if str(result.outcome) == "knocked_down":
		bike_knockdowns += 1
	elif str(result.outcome) == "stumbled":
		bike_stumbles += 1
	last_bicycle_knockdown = result.duplicate()
	if str(result.outcome) != "ignored":
		bicycle_knockdown.emit(result.duplicate())
	return result

func _bike_exempt(actor, crowd_index: int) -> String:
	if actor != null:
		if _is_police(actor):
			return "police"
		if actor.has_meta("police_custody"):
			return "in_custody"
		if actor.has_meta("law_responder") or actor.has_meta("police_assist") or actor.has_meta("police_crew"):
			return "on_duty"
		return ""
	var crowd = _crowd()
	if crowd != null and crowd_index >= 0 and crowd_index < crowd.residents.size() and crowd.residents[crowd_index].get("police_custody", false):
		return "in_custody"
	return ""

## Fists at the rider after a bicycle crash, whatever the person's armed
## disposition; ordinary melee cool-down rules end it. False when the fight
## budget is full (the caller then returns them to their routine).
func _bike_grudge(actor, crowd_index: int, state: Dictionary) -> bool:
	if not is_instance_valid(player) or (actor != null and (not is_instance_valid(actor) or actor.dead or not actor.enabled)):
		return false
	if state.is_empty():
		state = _fighter_for(actor, crowd_index, "aggro")
		if state.is_empty():
			return false
	else:
		var key: int = state.actor.get_instance_id()
		if not _active.has(key):
			if _active.size() >= MAX_ACTIVE:
				return false
			_panic.erase(key)
			_active[key] = state
	for field in ["foe", "foe_id", "foe_index", "fight_primary", "incident_id"]:
		state.erase(field)
	_holster(state)
	state.mode = "aggro"
	state.provoked = "bicycle"
	state.time = 0.0
	state.unseen = 0.0
	state.attack = -1.0
	state.cooldown = 0.8
	bike_grudges += 1
	state.actor.speak(BICYCLE_LINES[posmod(stable_hash("%s:%d" % [state.id, bike_grudges]), BICYCLE_LINES.size())], 1.6)
	return true

## The knockdown rig rotates the body's top toward its local -Z; this yaw sends
## the head along `push`, i.e. away from whatever hit them.
static func _fall_yaw_along(push: Vector3) -> float:
	return atan2(-push.x, -push.z)

## Model-controlled downed pose shared by bicycle and neighbor-fight knockdowns:
## the rig falls along `fall_yaw` onto clear ground (else sits down in place),
## the capsule lies flat with it, health is kept. Never lethal or stompable.
func _lay_down(id: String, actor, crowd_index: int, fall_yaw: float, limit: float, kind: String) -> bool:
	if _knocked.size() >= MAX_DOWNED:
		_recover_knocked(str(_knocked.keys()[0]))
	if actor == null:
		actor = _promote_crowd(crowd_index, true)
		if actor == null:
			return false
	var key: int = actor.get_instance_id()
	var state: Dictionary = _active.get(key, _panic.get(key, {}))
	if state.is_empty():
		state = _new_state(actor, crowd_index if crowd_index >= 0 else _proxy_index(actor))
	_active.erase(key)
	_panic.erase(key)
	_holster(state)
	for field in ["foe", "foe_id", "foe_index", "fight_primary", "incident_id", "provoked"]:
		state.erase(field)
	state.mode = "downed"
	state.attack = -1.0
	state.aim = -1.0
	actor.combat_override = true
	actor.velocity = Vector3.ZERO
	actor.moving = false
	var yaw := _clear_fall_yaw(actor, fall_yaw if is_finite(fall_yaw) else actor.yaw)
	var flat := is_finite(yaw)
	var original_capsule: Transform3D = actor.capsule.transform
	var base_y: float = actor.puppet.g.position.y
	if flat:
		actor.capsule.rotation = Vector3(-PI * 0.5, yaw, 0)
		actor.capsule.position = Basis(Vector3.UP, yaw) * Vector3(0, 0.28, -float(actor.capsule.shape.height) * 0.45)
	_knocked[id] = {"actor": actor, "state": state, "time": 0.0, "fall": 0.0, "capsule": original_capsule,
		"base_y": base_y, "id": id, "limit": limit, "kind": kind, "nonlethal": true,
		"from_yaw": float(actor.yaw), "fall_yaw": yaw if flat else float(actor.yaw), "flat": flat}
	return true

## The first of a few headings near `yaw` whose fall line is clear of walls,
## props and cars; INF when none is (the person then sits down in place).
func _clear_fall_yaw(actor, yaw: float) -> float:
	if not is_inside_tree():
		return INF
	var space := get_world_3d().direct_space_state
	var from: Vector3 = actor.global_position + Vector3.UP * 0.35
	var skip: Array[RID] = [actor.get_rid()]
	for turn in [0.0, 0.9, -0.9, 1.8, -1.8, PI]:
		var heading := yaw + float(turn)
		var reach := Vector3(-sin(heading), 0.0, -cos(heading)) * BIKE_FALL_CLEARANCE
		var query := PhysicsRayQueryParameters3D.create(from, from + reach, BIKE_FALL_MASK, skip)
		if space.intersect_ray(query).is_empty():
			return heading
	return INF

func _candidates() -> Array:
	var result: Array = []
	if level.npcs != null:
		result.append_array(level.npcs.actors.values())
	var residents = level.get("residents")
	if residents != null:
		result.append_array(residents.actors.values())
	for state in _active.values():
		if state.crowd_index >= 0 and is_instance_valid(state.actor):
			result.append(state.actor)
	return result.filter(func(actor): return is_instance_valid(actor) and not actor.dead)

func _punch_hit() -> void:
	if not player_offense_enabled():
		return
	var origin: Vector3 = player.global_position + Vector3.UP * 1.15
	var forward := Vector3(sin(player.yaw), 0, cos(player.yaw))
	var best: CollisionObject3D
	var distance := MELEE_RANGE
	for actor in _candidates():
		if not is_instance_valid(actor) or not actor.enabled or _knocked.has(str(actor.actor_id)):
			continue
		var offset: Vector3 = actor.global_position - player.global_position
		if absf(offset.y) > 1.2:
			continue
		offset.y = 0.0
		if offset.length() <= distance and forward.dot(offset.normalized()) > 0.30 and _sight(origin, actor.global_position + Vector3.UP, player, actor):
			best = actor
			distance = offset.length()
	# Primitive residents have real colliders: a short fan finds the closest one.
	for angle in [-0.32, 0.0, 0.32]:
		var direction := forward.rotated(Vector3.UP, angle)
		var hit := _ray(origin, origin + direction * distance, [player.get_rid()])
		if not hit.is_empty() and _is_crowd_body(hit.collider):
			best = hit.collider
			distance = origin.distance_to(hit.position)
	if best != null:
		_damage_target(best, [18.0, 22.0, 32.0][combo - 1], "punch")

func _fire() -> bool:
	if not player_offense_enabled():
		return false
	if _shot_cooldown > 0.0:
		return false
	if ammo <= 0:
		_notice("Magazine empty · press R to reload" if reserve > 0 else "Out of ammo · press 1 for fists", 2.0)
		return false
	ammo -= 1
	_store_equipped()
	shots_fired += 1
	var profile: Dictionary = Weapons.profile(weapon)
	_shot_cooldown = float(profile.interval)
	_recoil = 0.13
	var camera: Camera3D = player.camera
	var center := camera.get_viewport().get_visible_rect().size * 0.5
	var origin := camera.project_ray_origin(center)
	var direction := camera.project_ray_normal(center)
	var chest: Vector3 = player.global_position + Vector3.UP * 1.2
	# People can stand inside the camera boom. Start target selection at player
	# depth, so a rear bystander never becomes a backwards muzzle destination.
	var depth := maxf(0.0, (chest - origin).dot(direction))
	var aim_start := origin + direction * depth
	var view_hit := _ray(aim_start, aim_start + direction * float(profile.range), [player.get_rid()], false)
	var endpoint: Vector3 = view_hit.get("position", aim_start + direction * float(profile.range))
	var muzzle := muzzle_position()
	_world_sound("shot", muzzle)
	if (endpoint - muzzle).dot(direction) <= 0.0:
		last_shot = {"from": muzzle, "to": muzzle, "barrel_blocked": true, "backwards_rejected": true, "collider": null}
		_notice("Aim blocked · make some space", 0.8)
		# The round still went off: the noise alone frightens nearby people.
		_gunshot_event(muzzle, muzzle, muzzle, true, null)
		return true
	# A barrel can overlap a thin wall. Check from the body to the barrel first,
	# then from the barrel to the camera's point. Never trust the camera ray alone.
	var trace := _trace_bullet(chest, muzzle, endpoint, [player.get_rid()])
	var hit: Dictionary = trace.hit
	var blocked_at_barrel: bool = trace.barrel_blocked
	endpoint = trace.endpoint
	if hit.is_empty() and not view_hit.is_empty():
		# The endpoint itself may lie exactly on a shape boundary.
		hit = view_hit
	last_shot = {"from": muzzle, "to": endpoint, "barrel_blocked": blocked_at_barrel, "collider": hit.get("collider"), "tire": trace.tire, "vehicle": false}
	_tracer(chest if blocked_at_barrel else muzzle, endpoint)
	var struck: Object = null
	if not hit.is_empty():
		_spark(endpoint, Color("ffd68a"))
		# The chest-to-barrel guard is an obstruction check, never a damaging ray
		# (the body may face away from the camera while turning through movement).
		if blocked_at_barrel or (endpoint - muzzle).dot(direction) <= 0.0:
			_notice("Shot blocked · make some space", 0.7)
		elif _vehicle_shot(hit, muzzle):
			last_shot.vehicle = true
			_notice("Tire hit" if trace.tire else "Shot struck a vehicle", 0.7)
		elif _damage_target(hit.collider, float(profile.damage), "shot", muzzle):
			struck = hit.collider
		else:
			_notice("Shot blocked" if blocked_at_barrel else "Shot struck cover", 0.7)
	else:
		_notice("Shot", 0.4)
	_gunshot_event(muzzle, chest if blocked_at_barrel else muzzle, endpoint, true, struck)
	return true

## One bullet for player and NPC alike: body-to-barrel guard, barrel-to-target
## world ray (vehicles are layer 16), then analytic tires on the segment truncated
## at that hit. A tire is chosen only when strictly nearer, so walls always win.
func _trace_bullet(guard_from: Vector3, from: Vector3, to: Vector3, exclude: Array[RID]) -> Dictionary:
	var hit := _ray(guard_from, from, exclude)
	var blocked := not hit.is_empty()
	if not blocked:
		hit = _ray(from, to, exclude)
		var occupied := _driver_hit(from, to, exclude)
		if not occupied.is_empty():
			hit = occupied
	var endpoint: Vector3 = to if hit.is_empty() else hit.position
	var tire := false
	var traffic = level.get("traffic") if level != null else null
	if not blocked and traffic != null and traffic.has_method("raycast_tires"):
		var wheel: Dictionary = traffic.raycast_tires(from, endpoint)
		if not wheel.is_empty() and float(wheel.get("distance", INF)) < from.distance_to(endpoint) - 0.001:
			hit = wheel
			endpoint = wheel.get("position", endpoint)
			tire = wheel.has("tire_index")
	return {"hit": hit, "endpoint": endpoint, "barrel_blocked": blocked, "tire": tire}

func _vehicle_shot(hit: Dictionary, origin: Vector3) -> bool:
	var body = hit.get("collider")
	if not is_instance_valid(body) or _is_crowd_body(body) or body is Actor:
		return false
	var tire := bool(hit.get("vehicle_hit", false))
	if not tire and not (body is CollisionObject3D and (body.collision_layer & 16) != 0):
		return false
	var traffic = level.get("traffic")
	if traffic == null or not traffic.has_method("receive_gunshot"):
		return tire
	var result: Dictionary = traffic.receive_gunshot(hit, origin)
	# Layer 16 also holds solid street props; those are ordinary cover.
	if result.is_empty() and not tire:
		return false
	vehicle_hits += 1
	return true

func _notify_traffic(from: Vector3, to: Vector3) -> void:
	var traffic = level.get("traffic") if level != null else null
	if traffic != null and traffic.has_method("notify_gunshot"):
		traffic.notify_gunshot(from, to)
		traffic_notifies += 1

## Called exactly once per discharged round with the occluded endpoint. Only
## people near the shooter, the bullet path or the impact react this frame.
func _gunshot_event(origin: Vector3, from: Vector3, endpoint: Vector3, by_player: bool, struck: Object) -> void:
	if by_player:
		player_offense.emit("shooting", origin, _identity_of(struck))
	var began := Time.get_ticks_usec()
	threat_events += 1
	_notify_traffic(from, endpoint)
	var reactions: Array[Dictionary] = []
	for actor in _people():
		if not is_instance_valid(actor) or actor == struck or actor.dead or not actor.enabled:
			continue
		if _active.has(actor.get_instance_id()):
			continue
		var chest: Vector3 = actor.global_position + Vector3.UP * 1.2
		var heard := _flat_distance(actor.global_position, origin)
		var direct := Geometry3D.get_closest_point_to_segment(chest, from, endpoint).distance_to(chest) < NEAR_MISS
		if heard > HEAR_RADIUS and not direct and chest.distance_to(endpoint) > IMPACT_RADIUS:
			continue
		reactions.append({"actor": actor, "distance": heard, "direct": direct})
	reactions.sort_custom(func(a, b): return a.distance < b.distance)
	var scanned := reactions.size()
	for reaction in reactions:
		_react(reaction.actor, origin, reaction.direct, by_player)
	var crowd = _crowd()
	if crowd != null and crowd.has_method("react_to_threat"):
		var before: int = crowd._threat_scanned
		var direct_crowd: Array[int] = crowd.react_to_threat(origin, HEAR_RADIUS, from, endpoint)
		if _flat_distance(origin, endpoint) > HEAR_RADIUS * 0.5:
			direct_crowd.append_array(crowd.react_to_threat(endpoint, IMPACT_RADIUS, from, endpoint))
		scanned += crowd._threat_scanned - before
		# Hearing a shot makes people run. Only a near miss by the player makes
		# an armed neighbor turn and return fire, while fight slots remain.
		if by_player:
			for index in direct_crowd:
				if is_armed_id("crowd_%d" % index) and _active.size() < MAX_ACTIVE:
					_fighter_for(null, index, "gun")
	threat_scanned = scanned
	threat_usec = Time.get_ticks_usec() - began
	max_threat_usec = maxi(max_threat_usec, threat_usec)
	last_threat = {"origin": origin, "from": from, "to": endpoint, "by_player": by_player, "scanned": scanned}

func _react(actor, origin: Vector3, direct: bool, by_player: bool) -> void:
	# Law already owns this officer's route/search. Its queued offense scan
	# handles new gunfire; ambient hearing must not repeatedly steal the body
	# into panic/alert between law's perception ticks. Direct damage still
	# follows _damage_target and can wound, knock down or kill the officer.
	if actor.has_meta("law_responder"):
		return
	var police := _is_police(actor)
	if by_player and is_armed_id(actor.actor_id, police):
		# Police who can see the shooter respond; armed civilians only when targeted.
		var engage := direct
		if not engage and police:
			engage = _sight(actor.global_position + Vector3.UP * 1.3, player.global_position + Vector3.UP * 1.1, actor, player)
		if engage and _engage(actor, "gun"):
			return
	_panic_actor(actor, origin, "alert" if police else "flee")

func _melee_assault_event(origin: Vector3, impact: Vector3, victim: CollisionObject3D) -> void:
	# A landed player punch is visible violence, not a gunshot/hearing event.
	# Existing fighter/panic budgets and police melee response remain unchanged.
	assault_events += 1
	var candidates: Array[Dictionary] = []
	var seen: Dictionary = {}
	for actor in _people():
		if not is_instance_valid(actor) or actor == victim or actor.dead or not actor.enabled:
			continue
		var identity: int = actor.get_instance_id()
		if seen.has(identity) or _active.has(identity):
			continue
		seen[identity] = true
		var distance := maxf(_flat_distance(actor.global_position, impact), _flat_distance(actor.global_position, origin))
		if distance <= MELEE_WITNESS_RADIUS:
			candidates.append({"actor": actor, "body": actor, "position": actor.global_position,
				"yaw": float(actor.yaw), "id": str(actor.actor_id), "index": -1,
				"police": _is_police(actor), "distance": distance})
	var crowd = _crowd()
	if crowd != null:
		var indices: Dictionary = {}
		var cell_size: float = crowd.CELL
		var radius := MELEE_WITNESS_RADIUS + 4.0
		var low := Vector2i(floori((impact.x-radius)/cell_size),floori((impact.z-radius)/cell_size))
		var high := Vector2i(floori((impact.x+radius)/cell_size),floori((impact.z+radius)/cell_size))
		for x in range(low.x,high.x+1):
			for z in range(low.y,high.y+1):
				var cell: Dictionary = crowd._cells.get(Vector2i(x,z),{})
				if cell.is_empty() or cell.nodes.is_empty():
					continue
				for index in cell.resident_indices:
					indices[index] = true
		for displaced in [crowd._displaced,crowd._panic]:
			for index in displaced:
				indices[index] = true
		for index in indices:
			var record: Dictionary = crowd.residents[index]
			var body: CollisionObject3D = record.get("body")
			if not is_instance_valid(body) or body == victim or record.get("dead",false) or record.get("combat_controlled",false):
				continue
			var position: Vector3 = record.position
			var distance := maxf(_flat_distance(position,impact), _flat_distance(position,origin))
			if distance <= MELEE_WITNESS_RADIUS:
				candidates.append({"actor": null,"body":body,"position":position,"yaw":float(record.yaw),
					"id":"crowd_%d" % int(index),"index":int(index),"police":false,"distance":distance})
	candidates.sort_custom(func(a: Dictionary,b: Dictionary):
		return bool(a.police) if a.police!=b.police else float(a.distance)<float(b.distance))
	var checked := 0
	var rays := 0
	var reacted: Array[String] = []
	var observed: Array[String] = []
	var midpoint := origin.lerp(impact,.5)
	for candidate in candidates:
		if checked >= MAX_MELEE_WITNESS_CHECKS:
			break
		var at: Vector3 = candidate.position
		var toward := Vector3(midpoint.x-at.x,0,midpoint.z-at.z).normalized()
		var forward := Vector3(sin(float(candidate.yaw)),0,cos(float(candidate.yaw)))
		if forward.dot(toward) < -.25:
			continue
		checked += 1
		var eye := at + Vector3.UP * 1.3
		rays += 1
		if not _sight(eye,origin,candidate.body,player):
			continue
		rays += 1
		if not _sight(eye,impact,candidate.body,victim):
			continue
		observed.append(str(candidate.id))
		var accepted := false
		if int(candidate.index) >= 0:
			accepted = crowd.panic_resident(int(candidate.index),origin)
		elif bool(candidate.police):
			accepted = _engage(candidate.actor,"aggro")
			if accepted:
				candidate.actor.speak("Stop! Back away!",1.6)
			else:
				accepted = _panic_actor(candidate.actor,origin,"alert")
		else:
			accepted = _panic_actor(candidate.actor,origin,"flee")
		if accepted:
			reacted.append(str(candidate.id))
	assault_witnesses += reacted.size()
	last_assault = {"origin":origin,"impact":impact,"candidates":candidates.size(),
		"checked":checked,"rays":rays,"observed":observed,"reacted":reacted}

func muzzle_position() -> Vector3:
	return _muzzle.global_position if is_instance_valid(_muzzle) else player.global_position + Vector3.UP * 1.3

func _is_crowd_body(body: Object) -> bool:
	return is_instance_valid(body) and body.has_meta("city_crowd_index")

func _crowd():
	if level == null or level.npcs == null:
		return null
	return level.npcs.get("crowd")

func _people() -> Array:
	var result: Array = []
	if level.npcs != null:
		result.append_array(level.npcs.actors.values())
	var residents = level.get("residents")
	if residents != null and residents.get("actors") != null:
		result.append_array(residents.actors.values())
	return result

func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _is_police(actor) -> bool:
	var id := str(actor.actor_id)
	return str(actor.cast_id).begins_with("cop_") or id == "officer" or id.begins_with("patrol_officer_")

## FNV-1a over the UTF-8 identity: identical on every launch and platform.
static func stable_hash(text: String) -> int:
	var value := 2166136261
	for byte in text.to_utf8_buffer():
		value = ((value ^ byte) * 16777619) & 0xFFFFFFFF
	return value

## Police are always armed; about one civilian identity in three carries a pistol.
static func is_armed_id(id: String, police := false) -> bool:
	return police or stable_hash(id) % 3 == 0

func is_actor_armed(actor) -> bool:
	return is_instance_valid(actor) and is_armed_id(str(actor.actor_id), _is_police(actor))

func is_actor_dead(id: String) -> bool:
	return _dead.has(id)

func dead_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in _dead:
		ids.append(str(id))
	ids.sort()
	return ids

## Persist with the current world slot. Bounded, sorted and versioned.
func death_snapshot() -> Dictionary:
	return {"version": DEATH_VERSION, "dead": dead_ids()}

## Unions a saved registry into this world. Malformed, oversized or unknown-version
## data is rejected without changing anything. Never resurrects anyone.
func restore_deaths(data: Dictionary) -> bool:
	var version = data.get("version")
	if not (version is int or version is float) or version != DEATH_VERSION:
		return false
	var list = data.get("dead")
	if not list is Array or list.size() > MAX_DEATHS:
		return false
	var fresh: Array[String] = []
	var seen: Dictionary = {}
	for entry in list:
		if not entry is String or not _valid_identity(entry):
			return false
		if not _dead.has(entry) and not seen.has(entry):
			seen[entry] = true
			fresh.append(entry)
	if _dead.size() + fresh.size() > MAX_DEATHS:
		return false
	for id in fresh:
		_dead[id] = true
	for id in fresh:
		_apply_death(id)
	return true

## Re-applies the registry, e.g. after the root spawns or reloads an identity.
func refresh_deaths() -> void:
	for id in _dead:
		_apply_death(str(id))

func _valid_identity(id: String) -> bool:
	if id.is_empty() or id.length() > 64:
		return false
	for i in id.length():
		var code := id.unicode_at(i)
		var ok := (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code == 95 or code == 45 or code == 46
		if not ok:
			return false
	return true

## Restored deaths are silent: no corpse, no notice, no resurrection path.
func _apply_death(id: String) -> void:
	if _knocked.has(id):
		var fallen: Dictionary = _knocked[id]
		_knocked.erase(id)
		if is_instance_valid(fallen.actor):
			fallen.actor.mark_dead()
			fallen.actor.visible = false
			if int(fallen.state.crowd_index) >= 0:
				fallen.actor.queue_free()
	for container in [_active, _panic]:
		for key in container.keys():
			var state: Dictionary = container[key]
			if str(state.get("id", "")) != id:
				continue
			container.erase(key)
			_holster(state)
			if int(state.crowd_index) >= 0 and is_instance_valid(state.actor):
				state.actor.mark_dead()
				state.actor.queue_free()
	_wounds.erase(id)
	var actor = null
	if level.npcs != null:
		actor = level.npcs.actors.get(id)
	var residents = level.get("residents")
	if actor == null and residents != null and residents.get("actors") != null:
		actor = residents.actors.get(id)
	if is_instance_valid(actor) and actor is Actor:
		if not actor.dead:
			actor.mark_dead()
		actor.visible = false
	if id.begins_with("crowd_") and id.substr(6).is_valid_int():
		var crowd = _crowd()
		if crowd != null:
			crowd.kill_resident(int(id.substr(6)), Vector3.INF, false)

## Every accepted strike or bullet applies its damage. A full fight budget only
## changes the reaction (flee instead of fight), never whether damage counts.
func _damage_target(body: Object, damage: float, source: String, origin := Vector3.INF, by_player := true) -> bool:
	if by_player and not player_offense_enabled():
		return false
	if not is_instance_valid(body):
		return false
	var actor = null
	var crowd_index := -1
	var crowd = _crowd()
	if _is_crowd_body(body):
		crowd_index = int(body.get_meta("city_crowd_index"))
		if crowd == null or crowd.is_dead(crowd_index):
			return false
	elif body is Actor:
		actor = body
		if actor.dead or not actor.enabled:
			return false
	else:
		return false
	var from: Vector3 = origin if origin.is_finite() else player.global_position + Vector3.UP * 1.2
	var id: String = actor.actor_id if actor != null else "crowd_%d" % crowd_index
	if source == "punch" and _knocked.has(id):
		return false # Neither a queued combo nor repeated punches can execute them.
	var at: Vector3 = actor.global_position if actor != null else crowd.resident_position(crowd_index)
	var key: int = actor.get_instance_id() if actor != null else 0
	var state: Dictionary = {}
	if actor != null:
		state = _active.get(key, _panic.get(key, {}))
		if _knocked.has(id):
			state = _knocked[id].state
	var health_left: float = (float(state.health) if not state.is_empty() else _wound_hp(id)) - damage
	if by_player:
		hits_landed += 1
		hit_flash = 0.18
	_world_sound("hit", at + Vector3.UP * 1.2)
	_spark(at + Vector3.UP * 1.2, Color("fff3cf"))
	if by_player and source == "punch":
		_melee_assault_event(from, at + Vector3.UP * 1.1, body as CollisionObject3D)
		player_offense.emit("assault", at, id)
	if by_player and source in ["punch", "shot", "stomp", "vehicle"]:
		_group_assault(id, actor, at, from)
	if source == "punch" and (health_left <= 18.0 or combo == 3):
		_knock_down(id, actor, crowd_index, state)
		return true
	if health_left <= 0.0:
		_kill(id, actor, crowd_index, state, from)
		return true
	var shot := source == "shot" or source == "stray" or source == "vehicle"
	var police: bool = actor != null and _is_police(actor)
	# Melee provokes a fistfight; a bullet only makes armed people shoot back.
	var wants_fight: bool = by_player and (not shot or is_armed_id(id, police))
	var mode := "gun" if shot else "aggro"
	if not state.is_empty() and _active.has(key):
		state.health = health_left
		_flinch(state)
		if wants_fight:
			state.mode = mode
			state.time = 0.0
			state.unseen = 0.0
			if mode == "gun":
				_arm(state)
			else:
				_holster(state)
		actor.speak("Back off!", 1.4)
		_notice("%s hit · %s · move away to disengage" % [actor.display_name, source], 1.6)
		return true
	if wants_fight:
		var fighter := _fighter_for(actor, crowd_index, mode)
		if not fighter.is_empty():
			fighter.health = health_left
			_flinch(fighter)
			fighter.actor.speak("Back off!", 1.4)
			_notice("%s hit · %s · move away to disengage" % [fighter.actor.display_name, source], 1.6)
			return true
		overflow_hits += 1
	# An assisting officer keeps responding when wounded. Health still falls,
	# and the lethal branch above still kills; ambient panic must not steal the
	# body from the response controller after the first stray round.
	if actor != null and actor.has_meta("police_assist") and not by_player:
		_wounds[id] = {"hp": health_left, "time": _clock}
		actor.speak("Officer hit! Stay back!", 1.4)
		return true
	# Cheap path: wounded and fleeing, no full combat actor or extra physics.
	cheap_hits += 1
	if actor != null and _panic_actor(actor, from, "flee"):
		_panic[key].health = health_left
		actor.speak("Don't shoot!" if shot else "Leave me alone!", 1.4)
	else:
		_wounds[id] = {"hp": health_left, "time": _clock}
		if crowd_index >= 0:
			crowd.panic_resident(crowd_index, from)
	_notice("%s hit · fleeing" % (actor.display_name if actor != null else "Neighbor"), 1.4)
	return true

func _flinch(state: Dictionary) -> void:
	state.hurt = 0.24
	state.attack = -1.0
	state.aim = -1.0
	state.cooldown = 0.55
	state.gun_cooldown = maxf(float(state.gun_cooldown), 0.5)

func _wound_hp(id: String) -> float:
	return float(_wounds[id].hp) if _wounds.has(id) else ACTOR_HEALTH

## Move an identity into the fight set. Returns {} when the budget is full.
func _fighter_for(actor, crowd_index: int, mode: String) -> Dictionary:
	if actor == null:
		var proxy := _promote_crowd(crowd_index)
		if proxy == null:
			return {}
		var state := _new_state(proxy, crowd_index)
		_active[proxy.get_instance_id()] = state
		state.mode = mode
		if mode == "gun":
			_arm(state)
		return state
	if _engage(actor, mode):
		return _active[actor.get_instance_id()]
	return {}

func _engage(actor, mode: String) -> bool:
	if _knocked.has(str(actor.actor_id)):
		return false
	var key: int = actor.get_instance_id()
	var state: Dictionary
	if _active.has(key):
		state = _active[key]
	else:
		if _active.size() >= MAX_ACTIVE:
			return false
		if _panic.has(key):
			# Keep the flee trail: the eventual return retraces checked ground.
			state = _panic[key]
			_panic.erase(key)
		else:
			state = _new_state(actor, _proxy_index(actor))
		_active[key] = state
	state.mode = mode
	state.time = 0.0
	state.unseen = 0.0
	state.attack = -1.0
	state.aim = -1.0
	if mode == "gun":
		_arm(state)
		state.gun_cooldown = maxf(float(state.gun_cooldown), 0.35)
	return true

func _new_state(actor, crowd_index: int) -> Dictionary:
	actor.combat_override = true
	actor.set_meta("combat_controlled", true)
	var id: String = actor.actor_id
	var health_left := _wound_hp(id)
	_wounds.erase(id)
	return {"actor": actor, "id": id, "health": health_left, "mode": "aggro", "time": 0.0, "unseen": 0.0,
		"hurt": 0.0, "cooldown": 0.65, "attack": -1.0, "beat": 0, "down": 0.0,
		"home": actor.global_position, "target": actor.target, "has_target": actor.has_target,
		"manual": actor.manual_target, "revision": actor.target_revision,
		"trail": [actor.global_position], "return_time": 0.0, "return_limit": 6.0, "stalled": 0.0,
		"crowd_index": crowd_index, "blocked": 0.0, "threat": actor.global_position, "quiet": 0.0,
		"dest": actor.global_position, "replans": 0, "legs": 0, "bias": 0.0, "aim": -1.0,
		"gun_cooldown": 0.0, "shots": 0, "gun": null, "muzzle": null}

func _kill(id: String, actor, crowd_index: int, state: Dictionary, from: Vector3) -> void:
	var fallen: Dictionary = _knocked.get(id, {})
	_knocked.erase(id)
	if not state.is_empty():
		_holster(state)
		_active.erase(state.actor.get_instance_id())
		_panic.erase(state.actor.get_instance_id())
	_wounds.erase(id)
	_dead[id] = true
	deaths += 1
	var crowd = _crowd()
	var label := "Neighbor"
	if actor != null:
		label = actor.display_name
		var proxy_index: int = int(state.get("crowd_index", _proxy_index(actor)))
		if proxy_index >= 0 and crowd != null:
			# The promoted proxy is the corpse; its shared slot stays hidden.
			crowd.kill_resident(proxy_index, from, false)
		var toward: Vector3 = from - actor.global_position
		var facing: float = actor.yaw if Vector2(toward.x, toward.z).length() < 0.05 else atan2(toward.x, toward.z)
		actor.mark_dead()
		actor.yaw = facing
		_add_corpse({"kind": "actor", "actor": actor, "id": id, "proxy": proxy_index >= 0, "facing": facing,
			"fall": float(fallen.get("fall", 0.0)), "base_y": float(fallen.get("base_y", actor.puppet.g.position.y)), "meshes": []})
	elif crowd != null:
		crowd.kill_resident(crowd_index, from, true)
		_add_corpse({"kind": "crowd", "index": crowd_index, "id": id})
	_notice("%s was killed" % label, 2.5)
	actor_died.emit(id)

func _add_corpse(entry: Dictionary) -> void:
	entry.time = 0.0
	entry.fade = -1.0
	_corpses.append(entry)
	var showing := 0
	for corpse in _corpses:
		showing += int(corpse.fade < 0.0)
	# Over budget: the oldest visible corpse starts fading now.
	if showing > MAX_CORPSES:
		for corpse in _corpses:
			if corpse.fade < 0.0:
				corpse.fade = 0.0
				break

func _corpse_position(entry: Dictionary) -> Vector3:
	if entry.kind == "actor":
		return entry.actor.global_position if is_instance_valid(entry.actor) else Vector3.INF
	var crowd = _crowd()
	return crowd.resident_position(int(entry.index)) if crowd != null else Vector3.INF

func _tick_corpses(delta: float) -> void:
	for entry in _corpses.duplicate():
		entry.time += delta
		var actor = entry.get("actor")
		if entry.kind == "actor" and not is_instance_valid(actor):
			_corpses.erase(entry)
			continue
		if entry.kind == "actor" and entry.fall < 1.0:
			# A short non-gory collapse onto the back, away from the shot.
			entry.fall = minf(1.0, entry.fall + delta * 2.2)
			var t := smoothstep(0.0, 1.0, entry.fall)
			actor.puppet.g.rotation = Vector3(-1.45 * t, entry.facing, 0.0)
			actor.puppet.g.position.y = float(entry.base_y) + 0.15 * t
			actor.puppet.pose({"walk": 0.0, "armR": [-0.5 * t, 0.45 * t], "armL": [-0.5 * t, 0.45 * t], "nod": -0.2 * t})
		var at := _corpse_position(entry)
		var far: bool = not at.is_finite() or (is_instance_valid(player) and _flat_distance(at, player.global_position) > CORPSE_FAR)
		if entry.fade < 0.0 and (entry.time > CORPSE_TIME or far):
			entry.fade = 0.0
		if entry.fade < 0.0:
			continue
		if entry.kind == "crowd":
			var crowd = _crowd()
			if crowd != null:
				crowd.clear_corpse(int(entry.index))
			_corpses.erase(entry)
			corpses_cleared += 1
			continue
		if entry.meshes.is_empty():
			_collect_geometry(actor.puppet.g, entry.meshes)
		entry.fade = minf(1.0, entry.fade + delta / CORPSE_FADE)
		for mesh in entry.meshes:
			if is_instance_valid(mesh):
				mesh.transparency = entry.fade
		if entry.fade >= 1.0:
			# The identity and its registry entry remain; only the body is removed.
			actor.visible = false
			if entry.proxy:
				actor.queue_free()
			_corpses.erase(entry)
			corpses_cleared += 1

func _collect_geometry(node: Node, out: Array) -> void:
	if node is GeometryInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect_geometry(child, out)

func _promote_crowd(index: int, for_knockdown := false) -> CharacterBody3D:
	if (not for_knockdown and _active.size() >= MAX_ACTIVE) or level.npcs == null or level.npcs.crowd == null:
		return null
	var crowd = level.npcs.crowd
	var info: Dictionary = crowd.begin_combat(index)
	if info.is_empty():
		return null
	var actor := Actor.new()
	add_child(actor)
	actor.build(level, "crowd_%d" % index, ["liner_2", "ricky", "mailman", "granny"][index % 4], "Neighbor")
	# Promotion changes representation, not the person's appearance. Retain the
	# existing actor/collision setup, then bind the same birth-ID roster to its
	# animated rig. Death keeps this puppet; demotion restores its original slot.
	var appearance := PopulationAppearance.profile("crowd_%d" % index)
	var look: Dictionary = ModularPeople.roster()[int(appearance.roster_index)]
	actor.puppet.g.free()
	actor.puppet = Puppet.new()
	actor.puppet.id = actor.actor_id
	actor.puppet.H = float(look.height)
	actor.capsule.shape.height = maxf(.8,actor.puppet.H-.10)
	actor.capsule.position.y = actor.capsule.shape.height*.5+.08
	actor.puppet.g = ModularPeople.rig(actor.actor_id, int(appearance.roster_index), actor.puppet.H)
	actor.add_child(actor.puppet.g)
	actor.puppet.bind()
	actor._speech_label.position.y = actor.puppet.H + .78
	actor.set_meta("population_appearance", appearance)
	actor.global_position = info.position
	actor.yaw = info.yaw
	actor.puppet.g.rotation.y = actor.yaw
	return actor

func _tick_actor(state: Dictionary, delta: float) -> void:
	var actor = state.actor
	if not is_instance_valid(actor):
		return
	if not actor.enabled:
		_release(state)
		return
	state.time += delta
	_tick_body_clock(actor, delta)
	state.hurt = maxf(0.0, state.hurt - delta)
	state.cooldown = maxf(0.0, state.cooldown - delta)
	if state.mode == "return":
		_tick_return(state, delta)
		return
	if not str(state.get("foe_id", "")).is_empty():
		_tick_foe(state, delta)
		return
	if state.mode == "gun":
		_tick_gun(state, delta)
		return
	var offset: Vector3 = player.global_position - actor.global_position
	var distance := offset.length()
	var sees := _sight(actor.global_position + Vector3.UP * 1.3, player.global_position + Vector3.UP * 1.1, actor, player)
	state.unseen = 0.0 if sees else state.unseen + delta
	if distance > 18.0 or state.unseen > 5.0 or state.time > 28.0:
		_start_return(state)
		state.attack = -1.0
		actor.speak("Just leave me alone.", 2.0)
		_notice("Fight cooled down · neighbors return to their day", 2.0)
		return
	if actor.has_meta("law_responder") and not sees:
		# Law will route this officer to the last witnessed position after its
		# sight-loss grace period. Do not track the hidden live player meanwhile.
		state.attack = -1.0
		_pose_actor(actor, state)
		return
	var wanted := atan2(offset.x, offset.z)
	actor.yaw = rotate_toward(actor.yaw, wanted, delta * 5.0)
	actor.puppet.g.rotation.y = actor.yaw
	var aligned: bool = absf(angle_difference(actor.yaw, wanted)) < 0.12
	if state.attack < 0.0 and distance > 1.35 and state.hurt <= 0.0:
		_move_actor(actor, player.global_position, delta, 2.0)
		if actor.global_position.distance_to(state.trail[-1]) >= 0.45:
			state.trail.append(actor.global_position)
			if state.trail.size() > 128:
				state.trail.remove_at(1)
	elif state.attack < 0.0 and state.cooldown <= 0.0 and distance <= 1.65 and sees and aligned and state.hurt <= 0.0:
		state.attack = 0.0
		state.beat = 0
		actor.speak("Watch it!", 1.2)
	if state.attack >= 0.0:
		state.attack += delta
		# A telegraphed jab/cross/finisher: each threshold fires exactly once.
		var thresholds := [0.44, 0.96, 1.52]
		if state.beat < 3 and state.attack >= thresholds[state.beat]:
			if distance <= 1.75 and sees and absf(angle_difference(actor.yaw, wanted)) < 0.45:
				_hurt_player([7.0, 9.0, 13.0][state.beat])
			state.beat += 1
		if state.attack >= 1.86:
			state.attack = -1.0
			state.cooldown = 1.35
	_pose_actor(actor, state)

## Incident fistfight: chase the foe, then the same telegraphed jab/cross/finisher
## as a player fight; each landed beat is a nonlethal strike. Ends when the foe is
## down, gone, out of reach or out of sight, or when the fight runs out of time.
func _tick_foe(state: Dictionary, delta: float) -> void:
	var actor = state.actor
	var at := _foe_position(state)
	if not at.is_finite() or _knocked.has(str(state.foe_id)) or _dead.has(str(state.foe_id)) or state.time > float(state.get("fight_limit", NPC_FIGHT_SECONDS)):
		_end_npc_fight(state)
		return
	var offset: Vector3 = at - actor.global_position
	offset.y = 0.0
	var distance := offset.length()
	state.sight_left = float(state.get("sight_left", 0.0)) - delta
	if state.sight_left <= 0.0:
		state.sight_left = 0.2
		state.sees_foe = _foe_visible(state, at)
	state.unseen = 0.0 if bool(state.get("sees_foe", true)) else state.unseen + delta
	if distance > 14.0 or state.unseen > 4.0:
		_end_npc_fight(state)
		return
	var wanted := atan2(offset.x, offset.z)
	actor.yaw = rotate_toward(actor.yaw, wanted, delta * 5.0)
	actor.puppet.g.rotation.y = actor.yaw
	var aligned: bool = absf(angle_difference(actor.yaw, wanted)) < 0.12
	if state.attack < 0.0 and distance > 1.35 and state.hurt <= 0.0:
		_move_actor(actor, at, delta, 2.3)
		_record_trail(state, actor)
	elif state.attack < 0.0 and state.cooldown <= 0.0 and distance <= 1.65 and aligned and state.hurt <= 0.0:
		state.attack = 0.0
		state.beat = 0
	if state.attack >= 0.0:
		state.attack += delta
		var thresholds := [0.44, 0.96, 1.52]
		if state.beat < 3 and state.attack >= thresholds[state.beat]:
			if distance <= 1.75 and absf(angle_difference(actor.yaw, wanted)) < 0.45:
				_strike_foe(state, [7.0, 9.0, 13.0][state.beat], at)
			state.beat += 1
		if state.attack >= 1.86:
			state.attack = -1.0
			state.cooldown = 1.35
	_pose_actor(actor, state)

func _foe_position(state: Dictionary) -> Vector3:
	var foe = state.get("foe")
	if foe != null:
		return foe.global_position if is_instance_valid(foe) and not foe.dead and foe.enabled else Vector3.INF
	var index := int(state.get("foe_index", -1))
	var crowd = _crowd()
	if crowd == null or index < 0 or crowd.is_dead(index) or crowd.residents[index].get("combat_controlled", false):
		return Vector3.INF # Someone else took the person over (custody, another fight).
	return crowd.resident_position(index)

func _foe_visible(state: Dictionary, at: Vector3) -> bool:
	var actor = state.actor
	var skip: Array[RID] = [actor.get_rid()]
	var foe = state.get("foe")
	if is_instance_valid(foe):
		skip.append(foe.get_rid())
	else:
		var crowd = _crowd()
		var index := int(state.get("foe_index", -1))
		if crowd != null and index >= 0 and is_instance_valid(crowd.residents[index].get("body")):
			skip.append(crowd.residents[index].body.get_rid())
	var hit := _ray(actor.global_position + Vector3.UP * 1.3, at + Vector3.UP * 1.1, skip)
	return hit.is_empty() or not (hit.collider is CollisionObject3D and (hit.collider.collision_layer & (1 | 2 | 16)) != 0)

## One landed incident punch. The victim keeps fleeing (or fighting back in a
## mutual fight); at NPC_KNOCKOUT_HEALTH they are knocked down, never killed.
func _strike_foe(state: Dictionary, damage: float, at: Vector3) -> void:
	var actor = state.actor
	var id := str(state.foe_id)
	var foe = state.get("foe")
	npc_strikes += 1
	_world_sound("hit", at + Vector3.UP * 1.2)
	_spark(at + Vector3.UP * 1.2, Color("fff3cf"))
	var victim: Dictionary = {}
	if is_instance_valid(foe):
		victim = _active.get(foe.get_instance_id(), _panic.get(foe.get_instance_id(), {}))
	var health_left := (float(victim.health) if not victim.is_empty() else _wound_hp(id)) - damage
	if health_left <= NPC_KNOCKOUT_HEALTH:
		var push := Vector3(at.x - actor.global_position.x, 0.0, at.z - actor.global_position.z)
		var index := int(state.get("foe_index", -1)) if foe == null else _proxy_index(foe)
		if _lay_down(id, foe if is_instance_valid(foe) else null, index, _fall_yaw_along(push), NPC_KNOCKDOWN_TIME, "npc_fight"):
			var entry: Dictionary = _knocked[id]
			entry.state.health = maxf(health_left, 1.0)
			state.foe = entry.actor
			state.foe_index = -1
			npc_knockdowns += 1
			return
	if not victim.is_empty():
		victim.health = health_left
		if _active.has(foe.get_instance_id()):
			_flinch(victim)
		else:
			_panic_actor(foe, actor.global_position, "flee")
		return
	if is_instance_valid(foe):
		if _panic_actor(foe, actor.global_position, "flee"):
			_panic[foe.get_instance_id()].health = health_left
			return
	_wounds[id] = {"hp": health_left, "time": _clock}
	var crowd = _crowd()
	if foe == null and crowd != null:
		crowd.panic_resident(int(state.get("foe_index", -1)), actor.global_position)

## The fight is over: the attacker walks back along their swept trail. Whoever
## owns the incident decides what happens next (police, or a calm return).
func _end_npc_fight(state: Dictionary) -> void:
	for field in ["foe", "foe_id", "foe_index", "fight_primary"]:
		state.erase(field)
	state.attack = -1.0
	_start_return(state)

func _tick_body_clock(actor, delta: float) -> void:
	actor._clock += delta
	actor._speech_remaining = maxf(0.0, actor._speech_remaining - delta)
	actor._speech_label.visible = actor._speech_remaining > 0.0
	actor.moving = false
	actor.velocity = Vector3.ZERO

## Armed return fire: face, telegraph (raised pistol + callout), recheck sight
## at the trigger, then one real bullet. Never moves while aiming.
func _tick_gun(state: Dictionary, delta: float) -> void:
	var actor = state.actor
	state.gun_cooldown = maxf(0.0, float(state.gun_cooldown) - delta)
	var offset: Vector3 = player.global_position - actor.global_position
	var distance := Vector2(offset.x, offset.z).length()
	var sees := _sight(actor.global_position + Vector3.UP * 1.3, player.global_position + Vector3.UP * 1.1, actor, player)
	state.unseen = 0.0 if sees else state.unseen + delta
	if distance > NPC_GUN_RANGE * 1.5 or state.unseen > 6.0 or state.time > 40.0:
		_start_return(state)
		actor.speak("Stay away from here!", 2.0)
		_notice("Shooter lost sight of you · neighbors return to their day", 2.0)
		return
	if actor.has_meta("law_responder") and not sees:
		state.aim = -1.0
		_pose_gun(actor, state)
		return
	var wanted := atan2(offset.x, offset.z)
	if state.aim < 0.0 and distance > NPC_GUN_RANGE and sees and state.hurt <= 0.0:
		# Close to range along a swept path (recorded for the return walk).
		_move_actor(actor, player.global_position, delta, 2.0)
		_record_trail(state, actor)
	else:
		actor.yaw = rotate_toward(actor.yaw, wanted, delta * 5.0)
		actor.puppet.g.rotation.y = actor.yaw
	var error := absf(angle_difference(actor.yaw, wanted))
	if state.aim < 0.0:
		if sees and error < 0.10 and state.gun_cooldown <= 0.0 and distance <= NPC_GUN_RANGE and state.hurt <= 0.0:
			state.aim = 0.0
			telegraphs += 1
			if int(state.shots) == 0:
				actor.speak("Drop it!", 1.2)
	else:
		state.aim += delta
		if state.aim >= NPC_AIM_TIME:
			state.aim = -1.0
			state.gun_cooldown = 1.25 + float(posmod(stable_hash(str(state.id)) + int(state.shots), 5)) * 0.12
			# The telegraph is no promise: new cover or a dodge cancels the shot.
			if sees and error < 0.25 and distance <= NPC_GUN_RANGE:
				_npc_fire(state, distance)
	_pose_gun(actor, state)

func _npc_fire(state: Dictionary, distance: float) -> void:
	var actor = state.actor
	state.shots = int(state.shots) + 1
	npc_shots += 1
	var chest: Vector3 = actor.global_position + Vector3.UP * 1.25
	var muzzle: Vector3 = state.muzzle.global_position if is_instance_valid(state.muzzle) else chest + Vector3(sin(actor.yaw), 0, cos(actor.yaw)) * 0.45
	var target: Vector3 = _player_aim_point()
	var accuracy := clampf(0.9 - distance * 0.022, 0.3, 0.85)
	if player.current_speed > 3.0:
		accuracy -= 0.15
	# Deterministic per identity and shot number: reproducible fixtures, no RNG state.
	var roll := float(posmod(stable_hash("%s:%d" % [state.id, state.shots]), 1000)) / 1000.0
	if roll >= accuracy:
		var across := Vector3(-(target - muzzle).z, 0.0, (target - muzzle).x).normalized()
		target += across * (0.55 + roll * 0.6) * (1.0 if int(state.shots) % 2 == 0 else -1.0) + Vector3.UP * (roll - 0.5) * 0.4
	var direction := (target - muzzle).normalized()
	var trace := _trace_bullet(chest, muzzle, muzzle + direction * (muzzle.distance_to(target) + 6.0), [actor.get_rid()])
	var hit: Dictionary = trace.hit
	var endpoint: Vector3 = trace.endpoint
	_world_sound("shot", muzzle)
	_spark(muzzle, Color("ffcf67"))
	_tracer(chest if trace.barrel_blocked else muzzle, endpoint)
	var struck: Object = null
	if not hit.is_empty():
		_spark(endpoint, Color("ffd68a"))
		if not trace.barrel_blocked:
			if hit.collider == player:
				if _hurt_player(NPC_SHOT_DAMAGE):
					npc_hits += 1
					_notice("Shot by %s · health %d · break line of sight" % [actor.display_name, int(health)], 1.4)
			elif _vehicle_shot(hit, muzzle):
				pass
			elif _damage_target(hit.collider, STRAY_DAMAGE, "stray", muzzle, false):
				struck = hit.collider
	_gunshot_event(muzzle, chest if trace.barrel_blocked else muzzle, endpoint, false, struck)

func _arm(state: Dictionary) -> void:
	var actor = state.actor
	if is_instance_valid(state.get("gun")):
		state.gun.visible = true
		return
	var gun := Node3D.new()
	gun.name = "NpcPistol"
	actor.puppet.hands[0].add_child(gun)
	gun.rotation.x = PI * 0.5
	_box(gun, Vector3(0.085, 0.10, 0.28), Vector3(0, 0.035, 0.065), Color("343d48"))
	_box(gun, Vector3(0.065, 0.16, 0.08), Vector3(0, -0.075, -0.025), Color("151d29"))
	var muzzle := Marker3D.new()
	muzzle.position = Vector3(0, 0.035, 0.22)
	gun.add_child(muzzle)
	state.gun = gun
	state.muzzle = muzzle

func _holster(state: Dictionary) -> void:
	if is_instance_valid(state.get("gun")):
		state.gun.queue_free()
	state.gun = null
	state.muzzle = null

func _pose_gun(actor, state: Dictionary) -> void:
	# Ready position, raised through the telegraph, held briefly after the shot.
	var raise := 0.0
	if state.aim >= 0.0:
		raise = clampf(state.aim / NPC_AIM_TIME, 0.0, 1.0)
	elif float(state.gun_cooldown) > 0.9:
		raise = 1.0
	actor.puppet.pose({"walk": 0.45 if actor.moving else 0.0, "armR": [-0.9 - 0.55 * raise, 0.04],
		"armL": [-0.9 - 0.3 * raise, 0.22], "lean": -0.2 if state.hurt > 0.0 else 0.0})

func _panic_actor(actor, origin: Vector3, mode: String) -> bool:
	if _knocked.has(str(actor.actor_id)):
		return false
	var key: int = actor.get_instance_id()
	if _active.has(key) or actor.dead or not actor.enabled:
		return false
	var fresh := not _panic.has(key)
	if fresh and _panic.size() >= MAX_PANIC:
		return false
	var state: Dictionary = _new_state(actor, _proxy_index(actor)) if fresh else _panic[key]
	if fresh:
		_panic[key] = state
		state.mode = ""
		panic_started += 1
		actor.speak(["Get down!", "Run!", "Somebody's shooting!"][posmod(stable_hash(str(state.id)), 3)], 1.6)
	state.threat = origin
	state.quiet = 0.0
	if mode == "alert":
		if fresh or state.mode == "return":
			state.mode = "alert"
	elif fresh or state.mode == "return" or state.mode == "alert" or (state.mode == "cower" and int(state.replans) < 3 and _flat_distance(actor.global_position, origin) < 10.0):
		_plan_actor_flee(state)
	return true

func _plan_actor_flee(state: Dictionary) -> void:
	var actor = state.actor
	var away: Vector3 = actor.global_position - state.threat
	away.y = 0.0
	if away.length_squared() < 0.04:
		away = -Vector3(sin(actor.yaw), 0.0, cos(actor.yaw))
	away = away.normalized().rotated(Vector3.UP, float(state.bias))
	# Directly away from the shooter first; only widen when scenery blocks it.
	for angle in [0.0, 0.55, -0.55, 1.1, -1.1, 1.6, -1.6]:
		var dest := _flee_destination(actor, away.rotated(Vector3.UP, angle))
		if dest.is_finite():
			state.dest = dest
			state.mode = "flee"
			state.stalled = 0.0
			return
	state.mode = "cower"

func _flee_destination(actor, direction: Vector3) -> Vector3:
	if _flee_query == null:
		_flee_query = PhysicsShapeQueryParameters3D.new()
		_flee_query.collision_mask = PLAN_MASK
		_flee_query.margin = 0.02
	_flee_query.shape = actor.capsule.shape
	_flee_query.exclude = [actor.get_rid()]
	_flee_query.transform = Transform3D(Basis.IDENTITY, actor.global_position + actor.capsule.position)
	_flee_query.motion = direction * FLEE_DISTANCE
	flee_casts += 1
	var sweep := get_world_3d().direct_space_state.cast_motion(_flee_query)
	var travel := (1.0 if sweep.size() < 2 else float(sweep[0])) * FLEE_DISTANCE - 0.4
	for attempt in 2:
		if travel < 2.5:
			return Vector3.INF
		var dest: Vector3 = actor.global_position + direction * travel
		var ground: Dictionary = actor.walking_ground_at(dest)
		if not ground.is_empty() and ground.normal.y >= 0.75 and absf(ground.position.y - actor.global_position.y) < 1.0:
			return Vector3(dest.x, ground.position.y + 0.012, dest.z)
		travel *= 0.5
	return Vector3.INF

## Bounded (MAX_PANIC) full actors: flee along swept steps, re-plan or cower
## when blocked, then retrace the trail and resume schedules once it is quiet.
func _tick_panic_actor(key: int, state: Dictionary, delta: float) -> void:
	var actor = state.actor
	if not is_instance_valid(actor) or actor.dead:
		_panic.erase(key)
		return
	if not actor.enabled:
		_release(state)
		return
	panic_ticks += 1
	state.time += delta
	state.quiet += delta
	_tick_body_clock(actor, delta)
	if state.mode == "return":
		_tick_return(state, delta)
		return
	if state.mode == "flee":
		var status := _move_actor(actor, state.dest, delta, FLEE_SPEED)
		_record_trail(state, actor)
		if status == MOVE_ARRIVED:
			if state.quiet < 3.0 and int(state.legs) < 2:
				state.legs = int(state.legs) + 1
				_plan_actor_flee(state)
			else:
				state.mode = "cower"
		elif status == MOVE_BLOCKED:
			state.stalled += delta
			if state.stalled > 0.5:
				# Don't grind into a wall: try the other side, then take cover.
				state.stalled = 0.0
				state.replans = int(state.replans) + 1
				state.bias = 0.8 if int(state.replans) % 2 == 1 else -0.8
				if int(state.replans) <= 3:
					_plan_actor_flee(state)
				else:
					state.mode = "cower"
		else:
			state.stalled = 0.0
	if state.mode == "cower":
		actor.puppet.pose({"walk": 0.0, "lean": 0.7, "bob": -0.32, "armR": [-2.6, 0.3], "armL": [-2.6, 0.3], "nod": 0.35})
		actor.puppet.legs[0].rotation.x = -0.6
		actor.puppet.legs[1].rotation.x = -0.6
	elif state.mode == "alert":
		var toward: Vector3 = state.threat - actor.global_position
		if Vector2(toward.x, toward.z).length() > 0.1:
			actor.yaw = rotate_toward(actor.yaw, atan2(toward.x, toward.z), delta * 3.0)
			actor.puppet.g.rotation.y = actor.yaw
		actor.puppet.pose({"walk": 0.0, "look": 0.0})
	if state.mode != "flee" and state.quiet >= SAFE_COOLDOWN and state.time >= PANIC_MIN:
		_start_return(state)
		actor.speak("Is it over?", 2.0)

func _start_return(state: Dictionary) -> void:
	_holster(state)
	state.mode = "return"
	state.attack = -1.0
	state.aim = -1.0
	state.return_time = 0.0
	state.stalled = 0.0
	# Long flee trails get proportionally longer to retrace; short fights keep 6 s.
	var actor = state.actor
	var length := 0.0
	var previous: Vector3 = actor.global_position
	for i in range(state.trail.size() - 1, -1, -1):
		length += previous.distance_to(state.trail[i])
		previous = state.trail[i]
	state.return_limit = maxf(6.0, length / 1.8 + 3.0)

func _tick_return(state: Dictionary, delta: float) -> void:
	var actor: CharacterBody3D = state.actor
	state.return_time += delta
	# Reverse the short, physically swept chase path rather than drawing a new
	# straight line through a corner. Recheck every segment against current bodies.
	while not state.trail.is_empty() and actor.global_position.distance_to(state.trail[-1]) < 0.20:
		state.trail.pop_back()
	if state.trail.is_empty():
		_release(state)
		return
	var before := actor.global_position
	_move_actor(actor, state.trail[-1], delta, 1.8)
	state.stalled = state.stalled + delta if actor.global_position.distance_to(before) < 0.002 else 0.0
	if state.return_time >= float(state.get("return_limit", 6.0)) or state.stalled >= 3.0:
		# A new obstacle may occupy the old route. Release at the current safe
		# physical spot; no teleport, leaked fight slot or blocked regeneration.
		_release(state)

func _record_trail(state: Dictionary, actor: CharacterBody3D) -> void:
	if actor.global_position.distance_to(state.trail[-1]) >= 0.45:
		state.trail.append(actor.global_position)
		if state.trail.size() > 128:
			state.trail.remove_at(1)

func _move_actor(actor: CharacterBody3D, destination: Vector3, delta: float, speed: float) -> int:
	var offset := destination - actor.global_position
	offset.y = 0.0
	if offset.length() < 0.12:
		return MOVE_ARRIVED
	var wanted := atan2(offset.x, offset.z)
	actor.yaw = rotate_toward(actor.yaw, wanted, delta * 4.5)
	actor.puppet.g.rotation.y = actor.yaw
	if absf(angle_difference(actor.yaw, wanted)) > 0.035:
		actor.puppet.pose({"walk": 0.0})
		return MOVE_TURNING
	var motion := Vector3(sin(actor.yaw), 0, cos(actor.yaw)) * minf(speed * delta, offset.length())
	var ground: Dictionary = actor.walking_ground_at(actor.global_position + motion)
	if ground.is_empty() or ground.normal.y < 0.7:
		return MOVE_BLOCKED
	var rise: float = ground.position.y + 0.012 - actor.global_position.y
	if absf(rise) > 0.23:
		return MOVE_BLOCKED
	var before := actor.global_position
	# Kinematic sweep stops at walls, people and cars; no sidestepping through them.
	actor.move_and_collide(motion + Vector3.UP * rise)
	var travelled := actor.global_position.distance_to(before)
	actor.distance_walked += travelled
	actor.moving = travelled > 0.001
	actor.velocity = (actor.global_position - before) / maxf(delta, 0.0001)
	actor.puppet.phase += travelled * 3.5
	actor.puppet.pose({"walk": (0.7 if speed > 2.5 else 0.45) if actor.moving else 0.0})
	return MOVE_MOVED if actor.moving else MOVE_BLOCKED

func _pose_actor(actor: CharacterBody3D, state: Dictionary) -> void:
	var punch := 0.0
	var left := false
	if state.attack >= 0.0:
		var beat: float = fposmod(state.attack, 0.52) / 0.52
		punch = sin(PI * clampf((beat - 0.40) / 0.60, 0, 1))
		left = state.beat == 1
	actor.puppet.pose({"walk": 0.45 if actor.moving else 0.0,
		"armR": [-0.65 - (0.9 * punch if not left else 0.0), 0.12],
		"armL": [-0.65 - (0.9 * punch if left else 0.0), 0.12],
		"lean": -0.2 if state.hurt > 0.0 else 0.06 * punch})

func _hurt_player(damage: float) -> bool:
	if _invulnerable > 0.0 or downed > 0.0 or not is_available():
		return false
	health = maxf(0.0, health - damage)
	_since_hurt = 0.0
	_invulnerable = 0.35
	damage_flash = 0.25
	player_hits += 1
	_sound("hit")
	_notice("Hit! Move out of reach · health %d" % int(health), 1.0)
	if health <= 0.0:
		downed = 3.5
		aiming = false
		_attack_elapsed = -1.0
		_queued_punch = false
		_trigger_held = false
		_stomp_elapsed = -1.0
		reloading = 0.0
		for state in _active.values():
			if str(state.get("foe_id", "")).is_empty():
				_start_return(state)
		_notice("Knocked down · catching your breath…", 3.5)
		player_defeated.emit()
	return true

func _release(state: Dictionary) -> void:
	var actor = state.actor
	_active.erase(actor.get_instance_id())
	_panic.erase(actor.get_instance_id())
	_holster(state)
	# A survivor's wounds heal once the danger has passed; deaths never reach here.
	_wounds.erase(str(state.get("id", "")))
	actor.combat_override = false
	actor.remove_meta("combat_controlled")
	actor.velocity = Vector3.ZERO
	actor.puppet.pose({"walk": 0.0})
	if state.crowd_index >= 0:
		actor.collision_layer = 0
		level.npcs.crowd.end_combat(state.crowd_index, actor.global_position, actor.yaw, actor.capsule)
		actor.queue_free()
	else:
		actor.blocked_seconds = 0.0
		actor.blocked = false
		actor._wait = 0.0
		# Mission retargeting during combat wins over the snapshot. Do not silently
		# overwrite a newly assigned case destination when the fight cools down.
		if actor.target_revision != state.revision:
			return
		var residents = level.get("residents")
		if residents != null and residents.actors.get(actor.actor_id) == actor:
			if residents.has_method("resume_after_combat"):
				residents.resume_after_combat(actor)
			else:
				residents._update_schedule(actor, true)
		elif not actor.patrol_points.is_empty():
			var nearest := 0
			var distance := INF
			for i in actor.patrol_points.size():
				var candidate: float = actor.global_position.distance_squared_to(actor.patrol_points[i])
				if candidate < distance:
					distance = candidate
					nearest = i
			actor.patrol_index = nearest
			actor.has_target = false
			actor.manual_target = false
		else:
			actor.target = state.target
			actor.has_target = state.has_target
			actor.manual_target = state.manual

func apply_player_pose(delta: float) -> void:
	if not is_instance_valid(player) or player.puppet == null:
		return
	var puppet: Puppet = player.puppet
	if downed > 0.0:
		puppet.body.rotation.x = 0.8
		puppet.body.position.y = puppet.body_y - 0.42
		puppet.legs[0].rotation.x = -0.55
		puppet.legs[1].rotation.x = -0.55
		return
	if (aiming or _attack_elapsed >= 0.0) and player.current_speed < 0.2:
		player.yaw = rotate_toward(player.yaw, player.camera_yaw, delta * 16.0)
		puppet.g.rotation.y = player.yaw
	if weapon != "fists":
		var raise := -1.45 if aiming else -0.55
		if reloading > 0.0:
			raise = -0.85
		puppet.arms[0].rotation = Vector3(raise - _recoil * 1.3, 0.0, -0.06)
		if aiming or reloading > 0.0:
			puppet.arms[1].rotation = Vector3(-1.24, 0.0, -0.20)
	if _attack_elapsed >= 0.0:
		var length: float = COMBO_LENGTHS[combo - 1]
		var progress := clampf(_attack_elapsed / length, 0.0, 1.0)
		var extension := sin(PI * progress)
		var side := 1 if combo == 2 else 0
		puppet.arms[side].rotation.x = -0.45 - 1.25 * extension
		puppet.arms[1 - side].rotation.x = -0.60
		puppet.body.rotation.y = (0.20 if side == 0 else -0.20) * extension
		puppet.body.rotation.x = 0.12 * extension
	if damage_flash > 0.0:
		puppet.body.rotation.x = -0.22 * damage_flash / 0.25
	if _stomp_elapsed >= 0.0:
		var stomp := sin(PI * clampf(_stomp_elapsed / 0.65, 0.0, 1.0))
		puppet.legs[0].rotation.x = -0.95 * stomp
		puppet.body.rotation.x = 0.28 * stomp

func _build_pistol() -> void:
	_gun = Node3D.new()
	_gun.name = "EquippedWeapon"
	player.puppet.hands[0].add_child(_gun)
	# Arm local -Y is the hand's forward direction when raised to shoulder height.
	_gun.rotation.x = PI * 0.5
	for id in Weapons.PROFILES:
		var model := Node3D.new()
		model.name = str(Weapons.PROFILES[id].label)
		_gun.add_child(model)
		_weapon_models[id] = model
		model.visible = id == "pistol"
	var pistol: Node3D = _weapon_models.pistol
	_box(pistol, Vector3(0.085, 0.10, 0.28), Vector3(0, 0.035, 0.065), Color("343d48"))
	_box(pistol, Vector3(0.065, 0.16, 0.08), Vector3(0, -0.075, -0.025), Color("151d29"))
	_box(pistol, Vector3(0.055, 0.018, 0.20), Vector3(0, 0.09, 0.065), Color("74818d"))
	var uzi: Node3D = _weapon_models.uzi
	_box(uzi, Vector3(.115, .13, .32), Vector3(0, .035, .04), Color("343d39"))
	_box(uzi, Vector3(.055, .055, .14), Vector3(0, .035, .25), Color("171e22"))
	_box(uzi, Vector3(.07, .25, .08), Vector3(0, -.14, -.015), Color("151a1c"))
	_box(uzi, Vector3(.10, .035, .22), Vector3(0, -.02, -.22), Color("55605c"))
	_box(uzi, Vector3(.10, .13, .035), Vector3(0, -.065, -.33), Color("55605c"))
	var ak: Node3D = _weapon_models.ak47
	_box(ak, Vector3(.08, .11, .34), Vector3(0, .035, .10), Color("292d30"))
	_box(ak, Vector3(.055, .055, .28), Vector3(0, .035, .53), Color("171b20"))
	_box(ak, Vector3(.095, .10, .20), Vector3(0, .015, .32), Color("855331"))
	_box(ak, Vector3(.07, .17, .07), Vector3(0, -.08, -.025), Color("63402a"))
	_box(ak, Vector3(.09, .13, .27), Vector3(0, .005, -.22), Color("855331"))
	_box(ak, Vector3(.065, .15, .10), Vector3(0, -.12, .15), Color("363c40"))
	_box(ak, Vector3(.065, .11, .09), Vector3(0, -.23, .19), Color("363c40"))
	_muzzle = Marker3D.new()
	_muzzle.position = Vector3(0, 0.035, 0.22)
	_gun.add_child(_muzzle)
	_flash = MeshInstance3D.new()
	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = 0.06
	flash_mesh.height = 0.16
	_flash.mesh = flash_mesh
	_flash.material_override = _material(Color("ffcf67"), true)
	_muzzle.add_child(_flash)
	_flash.hide()
	_gun.hide()

func _material(color: Color, glowing := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.76
	if glowing:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material

func _build_sounds() -> void:
	# Small original synthesized transients, cached once; no missing asset/import
	# dependency and no new audio bus that could bypass the player's SFX setting.
	var random := RandomNumberGenerator.new()
	random.seed = 2048
	for kind in ["shot", "hit", "swing", "click"]:
		var rate := 22050
		var duration := 0.18 if kind == "shot" else 0.12
		var count := int(rate * duration)
		var data := PackedByteArray()
		data.resize(count * 2)
		var smooth := 0.0
		for i in count:
			var time := float(i) / rate
			var noise := random.randf_range(-1.0, 1.0)
			smooth = lerpf(smooth, noise, 0.24)
			var sample := 0.0
			match kind:
				"shot": sample = (noise * exp(-time * 100.0) * 0.42 + smooth * exp(-time * 24.0) * 0.6)
				"hit": sample = sin(TAU * (130.0 - time * 300.0) * time) * exp(-time * 40.0) * 0.5 + smooth * exp(-time * 60.0) * 0.2
				"swing": sample = smooth * sin(PI * time / duration) * 0.20
				"click": sample = noise * exp(-time * 150.0) * 0.18
			data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 24000))
		var stream := AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.mix_rate = rate
		stream.data = data
		_sounds[kind] = stream
	for i in 4:
		var voice := AudioStreamPlayer.new()
		voice.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
		voice.volume_db = -7.0
		add_child(voice)
		_voices.append(voice)

func _sound(kind: String) -> void:
	if _voices.is_empty():
		return
	var voice: AudioStreamPlayer = _voices[_voice_index]
	_voice_index = (_voice_index + 1) % _voices.size()
	voice.stream = _sounds[kind]
	voice.play()

func _world_sound(kind: String, at: Vector3) -> void:
	if is_instance_valid(world_audio) and _sounds.has(kind):
		world_audio.play_world(_sounds[kind], at, 90.0 if kind == "shot" else 24.0,
			-7.0, 5.0 if kind == "shot" else 2.5, kind)

func _exit_tree() -> void:
	for voice in _voices:
		if is_instance_valid(voice):
			voice.stop()
			voice.stream = null
	_voices.clear()
	_sounds.clear()

func _box(parent: Node3D, size_: Vector3, at: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size_
	mesh.mesh = box
	mesh.material_override = _material(color)
	mesh.position = at
	parent.add_child(mesh)

func _spark(at: Vector3, color: Color) -> void:
	if _effects.size() >= 16:
		return
	var mesh := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.07
	ball.height = 0.14
	mesh.mesh = ball
	mesh.material_override = _material(color, true)
	add_child(mesh)
	mesh.global_position = at
	_effects.append({"node": mesh, "time": 0.12})

func _tracer(from: Vector3, to: Vector3) -> void:
	if _effects.size() >= 16 or from.distance_to(to) < 0.03:
		return
	var mesh := MeshInstance3D.new()
	var line := BoxMesh.new()
	line.size = Vector3(0.012, 0.012, from.distance_to(to))
	mesh.mesh = line
	mesh.material_override = _material(Color("ffe4ac"), true)
	add_child(mesh)
	mesh.global_position = from.lerp(to, 0.5)
	mesh.look_at(to, Vector3.RIGHT if absf((to - from).normalized().y) > 0.98 else Vector3.UP)
	_effects.append({"node": mesh, "time": 0.065})

func _notice(text_: String, duration: float) -> void:
	message = text_
	_message_time = duration

func get_status() -> Dictionary:
	var actors: Dictionary = {}
	var aggro := 0
	var npc_fighting := 0
	for state in _active.values():
		var neighbor_fight := not str(state.get("foe_id", "")).is_empty()
		npc_fighting += int(neighbor_fight)
		# Hostile toward the explorer only; neighbor-versus-neighbor fights are not.
		aggro += int((state.mode == "aggro" or state.mode == "gun") and not neighbor_fight)
		actors[state.actor.actor_id] = {"health": state.health, "mode": state.mode, "attack": state.attack, "beat": state.beat, "down": state.down, "aim": state.aim, "shots": state.shots,
			"foe": str(state.get("foe_id", "")), "provoked": str(state.get("provoked", ""))}
	var panic_actors: Dictionary = {}
	for state in _panic.values():
		panic_actors[state.id] = {"health": state.health, "mode": state.mode, "quiet": state.quiet}
	var crowd = _crowd()
	var crowd_panic: Dictionary = crowd.get_panic_status() if crowd != null and crowd.has_method("get_panic_status") else {}
	# active_count stays fighters only: the checkpoint busy guard is unchanged.
	return {"health": health, "max_health": 100.0, "weapon": weapon, "ammo": ammo, "reserve": reserve,
		"equipment": equipment_snapshot(), "magazine_size": 0 if weapon == "fists" else int(Weapons.profile(weapon).magazine),
		"automatic": weapon != "fists" and bool(Weapons.profile(weapon).automatic),
		"stomp_available": not _stomp_cue.is_empty(), "stomp_target": _stomp_cue,
		"knocked_count": _knocked.size(), "max_knocked": MAX_DOWNED, "group_events": group_events, "last_group_reaction": last_group_reaction,
		"assault_events": assault_events, "assault_witnesses": assault_witnesses, "last_assault": last_assault.duplicate(),
		"world_audio": world_audio.get_status() if is_instance_valid(world_audio) else {},
		"reloading": reloading, "aiming": aiming, "combo": combo, "downed": downed,
		"message": message if _message_time > 0.0 else "", "hit_flash": hit_flash, "damage_flash": damage_flash,
		"aggro_count": aggro, "active_count": _active.size(), "max_active": MAX_ACTIVE,
		"punches": punches_thrown, "shots": shots_fired, "hits": hits_landed, "player_hits": player_hits, "actors": actors,
		"panic_count": _panic.size(), "max_panic": MAX_PANIC, "panic_actors": panic_actors, "panic_started": panic_started,
		"panic_ticks": panic_ticks, "flee_casts": flee_casts, "crowd_panic": crowd_panic,
		"deaths": deaths, "dead_count": _dead.size(), "corpses": _corpses.size(), "max_corpses": MAX_CORPSES,
		"corpses_cleared": corpses_cleared, "wounded": _wounds.size(),
		"threat_events": threat_events, "threat_scanned": threat_scanned, "threat_usec": threat_usec,
		"max_threat_usec": max_threat_usec, "npc_shots": npc_shots, "npc_hits": npc_hits, "telegraphs": telegraphs,
		"overflow_hits": overflow_hits, "cheap_hits": cheap_hits, "vehicle_hits": vehicle_hits,
		"traffic_notifies": traffic_notifies, "player_offense_enabled": player_offense_enabled(),
		"bicycle_contacts": bicycle_contacts, "last_bicycle_contact": last_bicycle_contact.duplicate(),
		"bike_knockdowns": bike_knockdowns, "bike_stumbles": bike_stumbles, "bike_grudges": bike_grudges,
		"last_bicycle_knockdown": last_bicycle_knockdown.duplicate(), "npc_fighting": npc_fighting,
		"npc_fights_started": npc_fights_started, "npc_strikes": npc_strikes, "npc_knockdowns": npc_knockdowns,
		"max_npc_fights": MAX_NPC_FIGHTS}
