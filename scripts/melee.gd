extends Node
## Hands. main.gd makes one (`_melee`); it runs each frame after main.gd's own work, as combat.gd does.
##
## With nothing in his hands (Q), the right mouse button puts them up. Hands up: a left click is a jab; held and
## let go, a hook (slower, heavier); Ctrl is a slip (a lean out of the way: a punch that arrives during it
## misses, and his next one lands harder). Each punch costs wind and takes wind off the man it lands on; nobody
## dies of it. A man out of wind goes down and gets up a little later. He himself, out of wind, goes down and
## is up again in a moment, having lost.
##
## Who is hit decides what happens (assets/data/melee.json's `people`): someone with heart squares up and
## fights back (MeleeBrain below walks him to arm's length beside the lead, at the lead's depth, so the two
## are side-on to the camera, and throws at him: each punch is drawn back first, which is the time to slip);
## someone without it is frightened like anyone near a shot (combat_people.gd). A heavy punch on a man who is
## not fighting puts him straight down ("stole on him"). An officer hit, or an officer who sees a punch land,
## arrests him. Pulling a gun on a man who has squared up ends the fight and costs respect.
##
## What a fight is worth depends on who saw it (street.gd's note()); what the man thinks of him afterwards
## is kept in the save (street.gd's person(): "feels" fear, grudge or respect).
##
## Nobody moves except the way he faces: the two turn to each other standing still; there is no backing off.
## Every number is a placeholder (melee.json); every word on screen is a placeholder.

const Street := preload("res://scripts/street.gd")
const Hud := preload("res://scripts/street_hud.gd")
const DATA := "res://assets/data/melee.json"
const FALL := 0.4                 # seconds to go down, or get up
const WATCH := 9.0                # metres: people this near a fight turn to watch it

## A man he is fighting.
class Fighter:
	var p: RefCounted             # combat_people.gd's Person
	var name := ""
	var who := ""
	var wind := 100.0
	var full := 100.0
	var hands := 0.4
	var act := ""                 # "", "jab", "hook" (drawing back, then thrown), "down", "up"
	var t := 0.0
	var landed := false
	var next := 1.0               # seconds till his next punch
	var hurt_t := 0.0
	var swung := false            # he has thrown at the lead (it was a fight, not a beating)
	var fair := true              # the lead has not hit him while he was not fighting


## Walks a Fighter: to arm's length beside the lead, at his depth, facing the way he goes; standing there he
## turns to the lead. (main.gd ticks it as it ticks any brain.)
class MeleeBrain:
	var frozen := false
	var melee: Node
	var f: Fighter
	var close := false            # he is where he wants to be

	func tick(delta: float) -> void:
		var a: Node3D = f.p.actor
		var main: Node = melee.main
		if f.act in ["down", "up"] or f.act in ["jab", "hook"]:
			a.walk(Vector2.ZERO, Vector2.ZERO, delta)
			return
		var lead: Node3D = main._actor
		var gap := Vector2(lead.position.x - a.position.x, lead.position.z - a.position.z)
		var across: float = main._screen_dir(gap).x
		var side := -1.0 if across > 0.0 else 1.0                 # the side of the lead he is on, on screen
		var spot: Vector2 = Vector2(lead.position.x, lead.position.z) + main._floor_dir(Vector2(side * melee.num("stand", 0.95), 0.0))
		var to := spot - Vector2(a.position.x, a.position.z)
		close = to.length() <= 0.14
		if close:
			a.walk(Vector2.ZERO, Vector2.ZERO, delta)
			a.face_side(across)
		else:
			var dir := to.normalized()
			a.walk(dir, main._screen_dir(dir), delta)


var main: Node
var hud: CanvasLayer
var data := {}
var guard := false                # his hands are up
var act := ""                     # "", "jab", "hook", "slip", "down", "up"
var act_t := 0.0
var landed := false
var wind := 100.0
var wind_wait := 0.0
var counter_t := 0.0              # seconds left of a slip's reward
var hold_t := -1.0                # the left button has been down this long (below 0: it is up)
var foes: Array = []              # Fighters: everyone squared up to him, or down
var last := {}                    # what the last punch did (for the steps)
var said := ""                    # the note on the HUD
var said_t := 0.0
var _slip_was := false
var _down_at := Vector3.ZERO
var _drawn := false               # a gun came out during this fight
var _watchers := {}               # actor: performing as it was
var _rng := RandomNumberGenerator.new()
var _script_guard := false        # a --do step put his hands up
var _face_was := ""               # the lead's face before the fight
var _hurt_t := 0.0                # seconds of his hurt face left
var _guard_was := false


func _ready() -> void:
	main = get_parent()
	_rng.seed = 41
	var read: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	data = read if typeof(read) == TYPE_DICTIONARY else {}
	hud = Hud.new()
	add_child(hud)
	hud.state = main._state


## Nothing is left holding anything else (a Fighter, his brain and his Person point at each other).
func _exit_tree() -> void:
	for f: Fighter in foes:
		if f.p != null and f.p.member.get("brain") is MeleeBrain:
			(f.p.member["brain"] as MeleeBrain).f = null
			(f.p.member["brain"] as MeleeBrain).melee = null
			f.p.member["brain"] = null
		f.p = null
	foes.clear()
	_watchers.clear()


func num(key: String, fallback: float) -> float:
	return float(data.get(key, fallback))


func _of(kind: String, key: String, fallback: float) -> float:
	return float((data.get(kind, {}) as Dictionary).get(key, fallback))


## What melee.json says of this character.
func _traits(who: String) -> Dictionary:
	var people: Dictionary = data.get("people", {})
	var out: Dictionary = (people.get("default", {}) as Dictionary).duplicate()
	out.merge(people.get(who, {}), true)
	return out


## Is he in a fight (someone squared up to him and on his feet)?
func fighting() -> bool:
	for f: Fighter in foes:
		if f.act != "down" and f.act != "up":
			return true
	return false


## The nearest man fighting him, or null.
func foe() -> Fighter:
	var best: Fighter = null
	var near := INF
	for f: Fighter in foes:
		var d: float = f.p.actor.global_position.distance_to(main._actor.global_position)
		if f.act != "down" and f.act != "up" and d < near:
			near = d
			best = f
	return best


func _process(delta: float) -> void:
	if main._actor == null or main._building == null or main._combat == null:
		return
	var free: bool = main._mode == "play" and not main._talk.is_open() and not main._travel.is_open() and not main._performing
	hud.visible = main._combat.hud.visible
	if main._scripted and not main.is_processing():
		return
	var dt := 1.0 / 60.0 if main._scripted else delta
	var lead: Node3D = main._actor
	var empty: bool = lead.weapon == ""
	if not main._scripted:
		guard = free and empty and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and act != "down" and act != "up"
		var down := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		if guard and act == "":
			if down:
				hold_t = maxf(hold_t, 0.0) + dt
			elif hold_t >= 0.0:
				throw("hook" if hold_t >= _of("hook", "hold", 0.25) else "jab")
				hold_t = -1.0
			var slip := Input.is_physical_key_pressed(KEY_CTRL)
			if slip and not _slip_was:
				slip_now()
			_slip_was = slip
		elif not down:
			hold_t = -1.0
	else:
		guard = _script_guard and empty and act != "down" and act != "up"
	if guard and not _guard_was and not main._scripted and said_t <= 0.0:
		said = "CLICK  JAB      HOLD  HOOK      CTRL  SLIP"
		said_t = 3.0
	_guard_was = guard
	_gun_out(lead)
	_tick_lead(dt, lead)
	lead.flinch = move_toward(lead.flinch, 0.0, dt * 1.4)
	if _hurt_t > 0.0:
		_hurt_t -= dt
		if _hurt_t <= 0.0 and lead.face:
			lead.face.set_expression("dizzy" if act == "down" else "angry" if fighting() else (_face_was if _face_was != "" else "neutral"), true)
	elif _face_was != "" and not fighting() and act == "" and lead.face:
		lead.face.set_expression(_face_was)
		_face_was = ""
	for f: Fighter in foes.duplicate():
		_tick_foe(f, dt)
	_watch(lead)
	counter_t = maxf(counter_t - dt, 0.0)
	said_t = maxf(said_t - dt, 0.0)
	wind_wait = maxf(wind_wait - dt, 0.0)
	if wind_wait <= 0.0 and act in ["", "slip"]:
		wind = minf(wind + num("wind_back", 14.0) * dt, 100.0)
	_pose_all(lead)
	var f := foe()
	if guard or f != null or act in ["down", "up"]:
		hud.fight = {"mine": wind / 100.0, "note": said if said_t > 0.0 else ""}
		if f != null:
			hud.fight["his"] = f.wind / f.full
			hud.fight["name"] = f.name
	else:
		hud.fight = {}
	hud.tick(dt)


# ------------------------------------------------------------ the lead

## Throw a punch ("jab" or "hook"). False if he cannot (busy, no wind, something in his hands).
func throw(kind: String) -> bool:
	var lead: Node3D = main._actor
	if act != "" or lead.weapon != "" or wind < _of(kind, "wind", 6.0):
		return false
	act = kind
	act_t = 0.0
	landed = false
	wind -= _of(kind, "wind", 6.0)
	wind_wait = num("wind_wait", 0.7)
	last = {"kind": kind, "hit": ""}
	var target: RefCounted = _in_reach(lead)
	if target != null:                       # he turns to the man first, then throws
		var gap := Vector2(target.actor.position.x - lead.position.x, target.actor.position.z - lead.position.z)
		lead.face_side(main._screen_dir(gap).x)
	return true


func slip_now() -> bool:
	if act != "" or wind < _of("slip", "wind", 3.0):
		return false
	act = "slip"
	act_t = 0.0
	wind -= _of("slip", "wind", 3.0)
	return true


func _tick_lead(dt: float, lead: Node3D) -> void:
	if act == "":
		return
	act_t += dt
	match act:
		"jab", "hook":
			if not landed and act_t >= _of(act, "lands", 0.1):
				landed = true
				_land(lead, act)
			if act_t >= _of(act, "time", 0.3):
				act = ""
		"slip":
			if act_t >= _of("slip", "time", 0.45):
				act = ""
		"down":
			lead.fallen = clampf(act_t / FALL, 0.0, 1.0)
			lead.position = _down_at
			if act_t >= num("down_mine", 2.5):
				act = "up"
				act_t = 0.0
		"up":
			lead.fallen = 1.0 - clampf(act_t / FALL, 0.0, 1.0)
			lead.position = _down_at
			if act_t >= FALL:
				lead.fallen = 0.0
				act = ""
				wind = 50.0


## Someone alive and on his feet within a punch of the lead (nearest first), or null.
func _in_reach(lead: Node3D) -> RefCounted:
	var best: RefCounted = null
	var near := INF
	for p: RefCounted in main._combat.people.living_here():
		var a: Node3D = p.actor
		if a.fallen > 0.2:
			continue
		var gap := Vector2(a.position.x - lead.position.x, a.position.z - lead.position.z)
		var s: Vector2 = main._screen_dir(gap)
		if absf(s.x) <= num("reach", 1.2) and absf(s.y) <= num("depth", 0.6) and absf(a.position.y - lead.position.y) < 0.6 and gap.length() < near:
			near = gap.length()
			best = p
	return best


func _fighter(p: RefCounted) -> Fighter:
	for f: Fighter in foes:
		if f.p == p:
			return f
	return null


## His punch arrives.
func _land(lead: Node3D, kind: String) -> void:
	var p: RefCounted = _in_reach(lead)
	if p == null:
		last["hit"] = "air"
		return
	var a: Node3D = p.actor
	var gap := Vector2(a.position.x - lead.position.x, a.position.z - lead.position.z)
	var across: float = main._screen_dir(gap).x
	var who := Street.who_of(a)
	last["hit"] = String(a.display_name)
	last["who"] = who
	if who == "cop":
		_say("YOU HIT A COP")
		_arrest("ASSAULT ON AN OFFICER")
		return
	var hurts := _of(kind, "hurts", 12.0) * (num_slip("gain") if counter_t > 0.0 else 1.0)
	last["counter"] = counter_t > 0.0
	counter_t = 0.0
	var f := _fighter(p)
	var open: bool = f == null or f.act in ["jab", "hook"] or last["counter"] or kind == "hook"
	if not open:
		hurts *= num("guarded", 0.5)          # his hands are up: a jab mostly lands on them
	last["guarded"] = not open
	if f == null:
		f = _meet(p, kind)
		if f == null:
			return                            # he ran, or went straight down
	a.flinch = -0.22 * signf(across)
	if a.face:
		a.face.set_expression("hurt", true)
	f.wind -= hurts
	f.hurt_t = 0.5
	last["his_wind"] = f.wind
	if f.wind <= 0.0:
		_drop(f)
	if Street.witnesses(main, lead.global_position, [a])["police"] > 0:
		_say("POLICE")
		_arrest("FIGHTING")


func num_slip(key: String) -> float:
	return _of("slip", key, 1.6)


## A man hit who was not fighting him. Returns his Fighter if he squares up; null if he does not (he runs, or
## a heavy punch he never saw puts him down).
func _meet(p: RefCounted, kind: String) -> Fighter:
	var a: Node3D = p.actor
	var who := Street.who_of(a)
	var traits := _traits(who)
	var memory := Street.person(main._state, who)
	var people: RefCounted = main._combat.people
	var busy: bool = p.taken or p.foe or p.state != "calm"         # frightened, hiding, held up, or shooting at him
	var will: bool = float(traits.get("heart", 0.5)) >= 0.5 and String(memory.get("feels", "")) != "fear" and not busy
	if kind == "hook" or not will:
		if kind == "hook":
			var f := _take(p, traits)
			f.fair = false
			f.wind = 0.0
			last["stole"] = true
			_drop(f)
			return null
		if not p.foe:
			people._frighten(p, main._actor.global_position)
			if p.state == "alarmed":
				p.wait = 0.05
		memory["hit"] = int(memory.get("hit", 0)) + 1
		last["ran"] = true
		_say("%s WANTS NO PART OF IT" % String(a.display_name))
		return null
	var f := _take(p, traits)
	_say("%s SQUARES UP" % f.name)
	return f


## From now on melee.gd moves this man (combat_people.gd's _take_over keeps what he was doing, for _let_go).
func _take(p: RefCounted, traits: Dictionary) -> Fighter:
	var people: RefCounted = main._combat.people
	var f := Fighter.new()
	f.p = p
	f.name = String(p.actor.display_name)
	f.who = Street.who_of(p.actor)
	f.full = float(traits.get("wind", 70.0))
	f.wind = f.full
	f.hands = float(traits.get("hands", 0.4))
	f.next = 0.6
	if not p.taken:
		people._take_over(p)
	p.state = "fighting"
	p.foe = true                              # a shot does not frighten him; nobody else moves him
	p.search = null
	var brain := MeleeBrain.new()
	brain.melee = self
	brain.f = f
	p.member["brain"] = brain
	p.actor.sprinting = false
	p.actor.cower = 0.0
	if p.actor.face:
		p.actor.face.set_expression("angry", true)
	if foes.is_empty() and main._actor.face:
		_face_was = main._actor.face.expression
	foes.append(f)
	_drawn = false
	return f


## He goes down: out of wind.
func _drop(f: Fighter) -> void:
	var a: Node3D = f.p.actor
	var lead: Node3D = main._actor
	f.act = "down"
	f.t = 0.0
	f.wind = 0.0
	var away := a.global_position - lead.global_position
	away.y = 0.0
	_lay(a, away)
	if a.face:
		a.face.set_expression("dizzy", true)
		a.face.talking = false
	var memory := Street.person(main._state, f.who)
	memory["beaten"] = int(memory.get("beaten", 0)) + 1
	memory["day"] = int(main._day)
	var fair: bool = f.fair and f.swung
	if fair:
		memory["feels"] = "respect" if float(_traits(f.who).get("heart", 0.5)) >= 0.8 else "fear"
		main._state.deed("fight_won")        # melee: a deed (deeds.json)
		Street.note(main, "fair_one_won", lead.global_position, [a])
		_say("%s IS DOWN" % f.name)
	else:
		memory["feels"] = "grudge"
		main._state.deed("stole_on_him")     # melee: a deed (deeds.json)
		Street.note(main, "stole_on_him", lead.global_position, [a])
		_say("STOLE ON %s" % f.name)
	last["down"] = f.name
	last["fair"] = fair


## Someone is about to go down, his head away from the punch: square to the camera and still (as the shot fall:
## combat_people.gd's _still), across the screen, on top of the floor he stands on (a court, a rug).
func _lay(a: Node3D, away: Vector3) -> void:
	main._combat.people._still(a)
	var across: float = main._screen_dir(Vector2(away.x, away.z)).x
	var way: Vector2 = main._floor_dir(Vector2(1.0 if across >= 0.0 else -1.0, 0.0))
	a.fall_to = Vector3(way.x, 0.0, way.y).normalized()
	var feet: Vector3 = a.global_position
	var top := feet.y
	var w: RefCounted = main._combat.world_for(main._building)
	if w != null:
		for k: float in [0.0, 0.45, 0.85]:
			var at: Vector3 = feet + a.fall_to * a.height * k
			top = maxf(top, w.floor_at(Vector3(at.x, feet.y - 0.38, at.z), feet.y))
	a.fall_lift = top - feet.y


func _tick_foe(f: Fighter, dt: float) -> void:
	var p: RefCounted = f.p
	var a: Node3D = p.actor
	var lead: Node3D = main._actor
	if p.state == "dead" or not is_instance_valid(a) or p.place != main._place:
		_forget(f, false)
		return
	if f.hurt_t > 0.0:
		f.hurt_t -= dt
		if f.hurt_t <= 0.0 and a.face and f.act != "down":
			a.face.set_expression("angry", true)
	a.flinch = move_toward(a.flinch, 0.0, dt * 1.4)
	f.t += dt
	match f.act:
		"down":
			a.fallen = clampf(f.t / FALL, 0.0, 1.0)
			if f.t >= num("down_his", 8.0):
				f.act = "up"
				f.t = 0.0
		"up":
			a.fallen = 1.0 - clampf(f.t / FALL, 0.0, 1.0)
			if f.t >= FALL:
				a.fallen = 0.0
				_forget(f, true)
		"jab", "hook":
			var tell := _of("his", f.act + "_tell", 0.32)
			if not f.landed and f.t >= tell:
				f.landed = true
				f.swung = true
				_his_lands(f, lead)
			if f.t >= tell + _of("his", "after", 0.25):
				f.act = ""
				var wait: Array = (data.get("his", {}) as Dictionary).get("wait", [1.5, 0.7])
				f.next = lerpf(float(wait[0]), float(wait[1]), f.hands) * _rng.randf_range(0.75, 1.25)
		"":
			if act == "down" or act == "up":
				return                        # the lead is on the floor: he stands over him
			var brain: MeleeBrain = p.member["brain"] if p.member["brain"] is MeleeBrain else null
			if brain == null or not brain.close:
				return
			if f.wind < f.full:
				f.wind = minf(f.wind + num("wind_back", 14.0) * 0.4 * dt, f.full)
			f.next -= dt
			if f.next <= 0.0:
				f.act = "hook" if _rng.randf() < _of("his", "hook_chance", 0.3) else "jab"
				f.t = 0.0
				f.landed = false


## His punch arrives at the lead.
func _his_lands(f: Fighter, lead: Node3D) -> void:
	var a: Node3D = f.p.actor
	var gap := Vector2(lead.position.x - a.position.x, lead.position.z - a.position.z)
	var s: Vector2 = main._screen_dir(gap)
	if absf(s.x) > num("reach", 1.2) + 0.15 or absf(s.y) > num("depth", 0.6) or act in ["down", "up"]:
		last["his"] = "air"
		return
	if act == "slip":
		counter_t = _of("slip", "counter", 0.8)
		last["his"] = "slipped"
		_say("SLIPPED IT")
		return
	last["his"] = f.act
	wind -= _of(f.act, "hurts", 12.0)
	wind_wait = num("wind_wait", 0.7)
	lead.flinch = -0.22 * signf(s.x)
	if lead.face:
		lead.face.set_expression("hurt", true)
	_hurt_t = 0.5
	if act in ["jab", "hook"] and not landed:
		act = ""                              # caught mid-punch: his own does not land
	if wind <= 0.0:
		wind = 0.0
		act = "down"
		act_t = 0.0
		hold_t = -1.0
		_down_at = lead.position
		if lead.face:
			lead.face.set_expression("dizzy", true)
		var away := lead.global_position - a.global_position
		away.y = 0.0
		_lay(lead, away)
		main._state.deed("fight_lost")       # melee: a deed (deeds.json)
		Street.note(main, "fight_lost", lead.global_position, [a])
		var memory := Street.person(main._state, f.who)
		memory["beat_him"] = int(memory.get("beat_him", 0)) + 1
		memory["feels"] = "nothing"
		_say("%s PUT YOU DOWN" % f.name)
		last["lost_to"] = f.name
		for other: Fighter in foes.duplicate():
			if other.act != "down" and other.act != "up":
				_forget(other, false)


## The fight with this man is over: he goes back to what he was doing (`ran`: after getting up he does what
## he feels: a man afraid of him now runs for cover).
func _forget(f: Fighter, got_up: bool) -> void:
	foes.erase(f)
	var p: RefCounted = f.p
	if p.state == "dead" or not is_instance_valid(p.actor):
		p.foe = false
		return
	var people: RefCounted = main._combat.people
	p.foe = false
	p.actor.fallen = 0.0
	p.actor.flinch = 0.0
	people._let_go(p)
	if got_up and String(Street.person(main._state, f.who).get("feels", "")) in ["fear", "grudge"]:
		people._frighten(p, main._actor.global_position)
		if p.state == "alarmed":
			p.wait = 0.05


## A gun in his hands while a man is squared up to him: the fight is over, and it costs him.
func _gun_out(lead: Node3D) -> void:
	if lead.weapon == "" or not fighting():
		return
	if not _drawn:
		_drawn = true
		Street.note(main, "gun_on_hands", lead.global_position)
		_say("PULLED A GUN ON A FAIR ONE")
	for f: Fighter in foes.duplicate():
		if f.act != "down" and f.act != "up":
			Street.person(main._state, f.who)["feels"] = "grudge"
			_forget(f, true)


func _arrest(why: String) -> void:
	for f: Fighter in foes.duplicate():
		_forget(f, false)
	act = ""
	main._actor.fallen = 0.0
	_script_guard = false
	main._arrest(why)


func _say(text: String) -> void:
	said = text
	said_t = 2.2
	print("[fight] ", text)


# ------------------------------------------------------------ everyone else

## People near a fight stop what they are doing and turn to watch it; when it is over they go on.
func _watch(lead: Node3D) -> void:
	var on := fighting()
	var people: RefCounted = main._combat.people
	if not on:
		for a: Node3D in _watchers:
			if is_instance_valid(a):
				a.performing = _watchers[a]
		_watchers.clear()
		return
	for p: RefCounted in people.living_here():
		var a: Node3D = p.actor
		if p.taken or p.foe or p.state != "calm" or a.fallen > 0.0 or a.global_position.distance_to(lead.global_position) > WATCH:
			continue
		if not _watchers.has(a):
			_watchers[a] = a.performing
			a.performing = false
		if p.member["brain"] == null or ("frozen" in p.member["brain"] and p.member["brain"].frozen):
			var gap := Vector2(lead.position.x - a.position.x, lead.position.z - a.position.z)
			a.face_side(main._screen_dir(gap).x)


# ------------------------------------------------------------ how it looks

const GUARD := [1.9, 1.1]            # hands up: the near arm turned this far from hanging, and bowed this much
const DRAWN := [-0.5, 1.6]            # a punch drawn back
const OUT := [1.55, 0.0]             # a punch at full reach: the arm straight out in front
const LEAN_IN := 0.16                # radians he leans into a punch
const LEAN_OUT := 0.3                # ...and away in a slip
const DUCK := 0.1                    # metres he drops in a slip
var pose_test := []                  # a --do step's [angle, curl, lean] for the lead, or empty


func _pose_all(lead: Node3D) -> void:
	var f0 := foe()
	var to := 0.0
	if f0 != null:
		to = main._screen_dir(Vector2(f0.p.actor.position.x - lead.position.x, f0.p.actor.position.z - lead.position.z)).x
	if not pose_test.is_empty():
		_arm(lead, [float(pose_test[0]), float(pose_test[1]), float(pose_test[2]), 0.0], 0.0, to)
	elif act in ["jab", "hook"]:
		_arm(lead, _punch(act, act_t, 0.0, _of(act, "lands", 0.1), _of(act, "time", 0.3)), 0.0, to)
	elif act == "slip":
		var k := sin(clampf(act_t / _of("slip", "time", 0.45), 0.0, 1.0) * PI)
		_arm(lead, [GUARD[0], GUARD[1], -LEAN_OUT * k, 0.0], DUCK * k, to)
	elif hold_t >= _of("hook", "hold", 0.25):
		_arm(lead, [DRAWN[0], DRAWN[1], -0.1, 0.0], 0.0, to)
	elif guard:
		_arm(lead, [GUARD[0], GUARD[1], 0.03, 0.0], 0.0, to)
	for f: Fighter in foes:
		var a: Node3D = f.p.actor
		var his: float = main._screen_dir(Vector2(lead.position.x - a.position.x, lead.position.z - a.position.z)).x
		if f.act in ["jab", "hook"]:
			var tell := _of("his", f.act + "_tell", 0.32)
			_arm(a, _punch(f.act, f.t, tell * 0.75, tell, tell + _of("his", "after", 0.25)), 0.0, his)
		elif f.act == "":
			_arm(a, [GUARD[0], GUARD[1], 0.03, 0.0], 0.0, his)


## A punch at `t` seconds in: drawn back until `back`, out by `lands`, home by `over`.
## [angle, curl, lean, how far out it is 0 .. 1 (below zero: drawn back)].
func _punch(kind: String, t: float, back: float, lands: float, over: float) -> Array:
	var heavy := 1.0 if kind == "hook" else 0.5
	if t < back:
		var k := t / maxf(back, 0.001)
		return [lerpf(GUARD[0], DRAWN[0], k * heavy), lerpf(GUARD[1], DRAWN[1], k), -0.12 * k * heavy, -k * heavy]
	if t < lands:
		var k := (t - back) / maxf(lands - back, 0.001)
		var from: Array = [lerpf(GUARD[0], DRAWN[0], heavy), DRAWN[1]] if back > 0.0 else GUARD
		return [lerpf(float(from[0]), OUT[0], k), lerpf(float(from[1]), OUT[1], k), lerpf(-0.12 * heavy if back > 0.0 else 0.0, LEAN_IN * (0.6 + heavy), k), k]
	var k := clampf((t - lands) / maxf(over - lands, 0.001), 0.0, 1.0)
	return [lerpf(OUT[0], GUARD[0], k), lerpf(OUT[1], GUARD[1], k), LEAN_IN * (0.6 + heavy) * (1.0 - k), 1.0 - k]


## Put someone's arms where a fighter's are. `pose` is _punch()'s: how far the punching arm is turned up from
## hanging (forward, the way he faces), how much it bows, how far he tips forward (below zero: back), and how
## far out the punch is. Side-on it is his near arm. Square to the camera (someone with no side drawing) both
## fists come up a little and the arm on the other man's side (`toward`, across the screen) goes out to him.
func _arm(a: Node3D, pose: Array, duck: float, toward: float) -> void:
	if a.fallen > 0.0 or a.weapon != "":
		return
	if a.view == "side":
		a._put("arm_l_angle", a._arm_rest + float(pose[0]) * ARM_SIGN)
		a._put("arm_l_curl", float(pose[1]) * CURL_SIGN)
		a._card.rotation.z = -float(pose[2])
	elif a._arms.has("l") and a._arms.has("r"):
		var out := clampf(float(pose[3]), 0.0, 1.0)
		var back := clampf(-float(pose[3]), 0.0, 1.0)
		var throwing := FRONT_UP + (FRONT_OUT - FRONT_UP) * out - 0.25 * back
		a._put("arm_l_angle", -(throwing if toward < 0.0 else FRONT_UP))
		a._put("arm_r_angle", throwing if toward >= 0.0 else FRONT_UP)
		a._put("arm_l_curl", FRONT_CURL * ((1.0 - out) if toward < 0.0 else 1.0))
		a._put("arm_r_curl", -FRONT_CURL * ((1.0 - out) if toward >= 0.0 else 1.0))
		a._card.rotation.z = -signf(toward) * float(pose[2]) * 0.6
	a._card.position.y -= duck

const ARM_SIGN := 1.0                # which way "forward and up" turns the near arm in a side drawing
const CURL_SIGN := 1.0
const FRONT_UP := 0.45               # square to the camera: each arm turned this far out from hanging, fists up
const FRONT_OUT := 1.45              # ...and the punching arm this far, straight out to the side
const FRONT_CURL := 1.1


# ------------------------------------------------------------ --do steps

## fight:guard:1|0, fight:at:WHO (stand him at arm's length beside WHO), fight:jab[:n], fight:hook, fight:slip,
## fight:wait:seconds, fight:until:down|lost|calm[:seconds], fight:auto:skill:seconds (he fights by himself:
## slips that share of the punches thrown at him, jabs when he can), fight:state, fight:pose:angle:curl:lean
## (hold the lead's arm there, to look at; fight:pose alone lets go), fight:wind:n, fight:feels:WHO[:fear].
func step(bits: PackedStringArray) -> void:
	var what := bits[1] if bits.size() > 1 else "state"
	var lead: Node3D = main._actor
	match what:
		"guard":
			_script_guard = bits.size() < 3 or bits[2] == "1"
			lead.weapon = ""
			await _frames(2)
		"at":
			var p: RefCounted = _named(bits[2] if bits.size() > 2 else "")
			if p == null:
				print("[shot] fight: nobody here called %s" % (bits[2] if bits.size() > 2 else "?"))
				return
			var a: Node3D = p.actor
			var side := -1.0 if bits.size() > 3 and bits[3] == "left" else 1.0
			for way: float in [side, -side]:
				var spot: Vector2 = Vector2(a.position.x, a.position.z) - main._floor_dir(Vector2(way * num("stand", 0.95), 0.0))
				if lead.can_stand(spot):
					lead.position = Vector3(spot.x, a.position.y, spot.y)
					lead.face_side(way)
					break
			await _frames(3)
			print("[shot] fight: beside %s at %.2f, %.2f" % [a.display_name, lead.position.x, lead.position.z])
		"jab", "hook":
			var n := int(bits[2]) if bits.size() > 2 else 1
			for i in n:
				_script_guard = true
				await _frames(1)
				var ok := throw(what)
				while act == what:
					await _frames(1)
				print("[shot] fight: %s: %s" % [what, _last_said() if ok else "could not (wind %d)" % int(wind)])
		"slip":
			slip_now()
			await _frames(1)
		"wait":
			await _frames(int(float(bits[2]) * 60.0) if bits.size() > 2 else 30)
		"until":
			var want := bits[2] if bits.size() > 2 else "down"
			var most := int(float(bits[3]) * 60.0) if bits.size() > 3 else 1200
			var n := 0
			while n < most and not _is(want):
				await _frames(1)
				n += 1
			print("[shot] fight: until %s: %s after %.1f s" % [want, "yes" if _is(want) else "NO", n / 60.0])
		"auto":
			var skill := float(bits[2]) if bits.size() > 2 else 0.5
			var most := int(float(bits[3]) * 60.0) if bits.size() > 3 else 1800
			_script_guard = true
			var rng := RandomNumberGenerator.new()
			rng.seed = 5
			var slip_this := false
			var was := ""
			var n := 0
			while n < most and (fighting() or n < 30) and act != "down":
				var f := foe()
				var his := f.act if f != null else ""
				if his in ["jab", "hook"] and not was in ["jab", "hook"]:
					slip_this = rng.randf() < skill      # one throw of the dice for each punch thrown at him
				was = his
				if f != null and his in ["jab", "hook"] and not f.landed:
					if slip_this and f.t >= _of("his", his + "_tell", 0.32) - 0.2 and act == "":
						slip_now()
				elif act == "" and _in_reach(lead) != null:
					if counter_t > 0.0 and wind >= 30.0:
						throw("hook")                  # after a slip: the heavy one
					elif wind >= 60.0:
						throw("jab")                   # otherwise only with wind to spare (mashing loses)
				await _frames(1)
				n += 1
			print("[shot] fight: auto %.2f for %.1f s: %s" % [skill, n / 60.0, _state_line()])
		"pose":
			pose_test = [float(bits[2]), float(bits[3]) if bits.size() > 3 else 0.0, float(bits[4]) if bits.size() > 4 else 0.0] if bits.size() > 2 else []
			await _frames(2)
		"wind":
			wind = float(bits[2]) if bits.size() > 2 else 100.0
		"feels":
			var who := (bits[2] if bits.size() > 2 else "").to_lower()
			if bits.size() > 3:
				Street.person(main._state, who)["feels"] = bits[3]
			print("[shot] fight: %s remembers %s" % [who, Street.person(main._state, who)])
		_:
			print("[shot] fight: %s" % _state_line())


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _named(name: String) -> RefCounted:
	for p: RefCounted in main._combat.people.living_here():
		if String(p.actor.display_name).to_lower() == name.to_lower() or Street.who_of(p.actor) == name.to_lower():
			return p
	return null


func _is(want: String) -> bool:
	match want:
		"down":
			for f: Fighter in foes:
				if f.act == "down" and f.t >= FALL:
					return true
			return false
		"lost":
			return act == "down" and act_t >= FALL
		"histhrow":
			var f := foe()
			return f != null and f.act in ["jab", "hook"] and f.landed
		"up":
			return act == "" and main._actor.fallen <= 0.0
		_:
			return foes.is_empty() and act == ""


func _last_said() -> String:
	var parts: Array = []
	for k: String in last:
		parts.append("%s %s" % [k, last[k]])
	return ", ".join(parts)


func _state_line() -> String:
	var who: Array = []
	for f: Fighter in foes:
		who.append("%s (%s, wind %d of %d)" % [f.name, f.act if f.act != "" else "up", int(f.wind), int(f.full)])
	return "his wind %d, %s, hands %s; against %s; respect %d, heat %d, trust %d; deeds won %d, lost %d, stole %d" % [int(wind), act if act != "" else "ready", "up" if guard else "down",
		"nobody" if who.is_empty() else ", ".join(who), Street.value(main._state, "respect"), Street.value(main._state, "heat"), Street.value(main._state, "trust"),
		main._state.done("fight_won"), main._state.done("fight_lost"), main._state.done("stole_on_him")]
