extends Node
## People who shoot at him. combat.gd makes this node (its child) and hands it the foe steps (step()). The owners:
## "the metal detector at the courthouse should blink red if you're carrying a firearm and trigger a search. if a
## cop sees you with a firearm pulled they should open fire on you. we also need random gang members to also
## return fire."
##
## Police. An officer (the cop drawing) who can see him with a weapon in his hands (nothing solid between the
## officer's eyes and him, within "sight") shouts once, draws and fires at him until he is down, out of sight or
## has put it away. Put away while one of them is close ("arrest_range"), he is arrested (main.gd's _arrest).
## With his hands empty and nobody close, they hold their guns on him a while ("calm"), then put them away.
## Gang. At the places foes.json names, some of the people carry a gun out of sight; the dice are thrown for the
## place and the day, so a place looks the same all day. A shot fired near one of them, or at him, and he draws
## and shoots back instead of running. Shot, he flinches and dies like anyone (combat_people.gd); badly hurt, he
## may break off and run like anyone frightened. Drawn only from the front, a foe holds the gun out to the side,
## side-on (paper_actor.gd HOLDS front_aim), mirrored to point right, or at the camera when the lead is nearly
## straight towards it. Officers have arms of their own for it (artifacts tools/foes_cop.py).
## Their shots: a muzzle flash and a case out of the port, a tracer if combat_fx.gd draws them, glass on the way
## broken, a mark where they end, everyone near frightened (combat_people.gd's alarm). A hit on him takes his
## health (combat.gd's hurt: with none left he wakes in hospital); he flinches and pulls a hurt face.
## The courthouse's metal detector (foes_detector.gd) blinks red for a firearm on him at all: the officer behind
## the arch stops him, walks up to him (only ever towards the camera, the way he faces) and searches him, and he is
## arrested. Pull the weapon and the police rule applies; run and they open fire until he stands still.
## The stash in his room at the crib (a use point "stash", plans/crib.gd) keeps his weapons in the player state's
## flags ("stash"), so he can go to court without them.
##
## In a screenshot run (tools/shot.py) nobody here is armed until a foe step wakes them (foe:on), so other checks
## and pictures are not shot at. Every number and every shouted line is a placeholder, in assets/data/foes.json.

const DATA := "res://assets/data/foes.json"
const Glass := preload("res://scripts/combat_glass.gd")
const FONT := preload("res://assets/fonts/Bungee-Regular.ttf")
const Deeds := preload("res://scripts/deeds.gd")      # bars: the deeds ledger's rules (assets/data/deeds.json)
const RANGE := 60.0             # metres a shot carries (combat.gd's RANGE)
const CONE := 0.7               # radians: drawn only from the front, he walks no further than this from straight at the camera (combat_people.gd's FLEE_CONE)
const TOWARD := 0.25            # the lead within this much (across against towards) of straight at the camera from a foe: pointed at the camera (else side-on, which reads better)
const SAY_TIME := 1.5           # seconds a shout shows over his head
const SAY_UP := 0.1             # metres above his head (the words sit on that point, the same size on screen near or far)
const LOOK_EVERY := 0.1         # seconds between looks for him (a few rays each)
const FACES := {"police": "focused", "gang": "angry"}


class Foe:
	var p: RefCounted                 # combat_people.gd's Person
	var kind := ""                    # "police" or "gang"
	var weapon := ""                  # what he carries; out of sight till he draws
	var state := "idle"               # idle, search (walking up to search him), draw, up (gun on him), gone (ran), dead
	var t := 0.0                      # seconds in this state
	var cool := 0.0                   # seconds till his next shot
	var burst := 0                    # shots left in this burst
	var shouted := false
	var seen := false                 # he can see the lead
	var look := 0.0                   # seconds till he looks again
	var quiet := 0.0                  # gang: seconds since he last saw him or heard a shot
	var on_him := 0.0                 # seconds with his gun up, the lead in sight and cause to fire (for the check)
	var brain: RefCounted             # his FoeBrain while he is taken
	var brain_was: Variant = null
	var areas_was: Array = []
	var others_was: Array = []
	var reach_was := 1.6
	var face_was := ""
	var health_was := 100
	var hurt := 0.0                   # seconds of the hurt face left
	var rolled := false               # he has been badly hurt: the dice for breaking off are thrown
	var label: Label3D
	var label_t := 0.0
	var shots := 0
	var hits := 0
	var called := ""
	var home := Vector3.ZERO


## Stands in for someone's brain in main.gd's cast while he is taken: main.gd calls tick() each frame. It walks
## him straight to `goal`, facing the way he walks (paper_actor.gd), or keeps him standing.
class FoeBrain:
	var frozen := false
	var actor: Node3D
	var to_screen: Callable
	var goal := Vector2.INF
	var stuck := 0.0
	var done := false                 # got to `goal`, or could not

	func tick(delta: float) -> void:
		if goal == Vector2.INF:
			actor.walk(Vector2.ZERO, Vector2.ZERO, delta)
			return
		var here := Vector2(actor.position.x, actor.position.z)
		var to := goal - here
		if to.length() < 0.06:
			goal = Vector2.INF
			done = true
			actor.walk(Vector2.ZERO, Vector2.ZERO, delta)
			return
		var dir := to.normalized()
		actor.walk(dir, to_screen.call(dir), delta)
		var moved := Vector2(actor.position.x, actor.position.z).distance_to(here)
		stuck = stuck + delta if moved < actor.WALK_SPEED * float(actor.speed) * delta * 0.3 else 0.0
		if stuck > 0.6:               # someone in the way: he stops where he is
			goal = Vector2.INF
			done = true


var combat: Node
var main: Node
var people: RefCounted
var fx: Node3D
var data := {}
var wake := 0                   # 1: woken (foe:on), -1: asleep (foe:off), 0: awake in play, asleep in a screenshot run
var events: Array = []          # what happened, for foecheck

var _foes: Array = []           # Foe, at the place he is at
var _building: Node3D
var _place := ""
var _day := -1
var _awake_was := false
var _rng := RandomNumberGenerator.new()
var _clock := 0.0
var _last_shot: Variant = null  # combat.gd's `last` when we last looked: each shot of his makes a new one
var _lead_at := Vector3.ZERO
var _lead_speed := 0.0          # metres a second, on the floor
var _still := 0.0               # seconds he has stood still
var _hurt_t := 0.0              # seconds of his hurt face left
var _face_was := ""
var _flinching := false
var _down := false              # down or arrested: nothing more here
var _quiet := 0.0               # police: seconds his hands have been empty while they are on him
var _was_armed := false         # police: he had it out while they were on him
var _hands_said := false
var _search := {}               # after a red: "state", "t", "at" (Vector2: where he was stopped), "foe", "tries"
var _why_not := ""              # why the last _approach found no spot (for the notes)
var _last_line := ""            # the last shout picked from a list
var _detectors: Array = []
var _forced := {}               # place: {who (lower case): weapon}: the foe:arm step
var _stash: Node3D              # the stash's use point, at the crib
var _tally := {}
var _problems: Array = []


func _init() -> void:
	name = "CombatFoes"
	_rng.seed = 41
	_reset_tally()


func _ready() -> void:
	combat = get_parent()
	main = combat.main
	people = combat.people
	fx = combat.fx
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	if typeof(parsed) == TYPE_DICTIONARY:
		data = parsed
	else:
		push_warning("Could not read %s" % DATA)


func _reset_tally() -> void:
	_tally = {"police_shots": 0, "gang_shots": 0, "hits_on_him": 0, "damage": 0, "bystanders_hit": 0, "panes": 0,
		"marks": 0, "his_shots": 0, "down": 0, "broke": 0, "green": 0, "red": 0, "searches": 0, "arrests": 0, "draws": 0}


func _awake() -> bool:
	return wake > 0 or (wake == 0 and not main._scripted)


func _rule(kind: String) -> Dictionary:
	return data.get(kind, {})


func _num(rule: Dictionary, key: String, fallback: float) -> float:
	return float(rule.get(key, fallback))


func _between(range_of: Variant, fallback: float) -> float:
	if typeof(range_of) == TYPE_ARRAY and (range_of as Array).size() == 2:
		return _rng.randf_range(float(range_of[0]), float(range_of[1]))
	return fallback


# ------------------------------------------------------------ each frame

func _process(delta: float) -> void:
	if main._scripted and not main.is_processing():
		return                      # a screenshot's last frames: everything stays where it is
	if main._mode != "play" or main._building == null:
		return
	var dt := 1.0 / 60.0 if main._scripted else delta
	_watch()
	if combat._frozen:
		return
	_clock += dt
	_tick_lead(dt)
	for f: Foe in _foes:
		_tick_say(f, dt)
	if _foes.is_empty() or _down:
		return
	if main._talk.is_open() or main._travel.is_open() or main._performing:
		return
	_heard_his()
	_tick_police(dt)
	if _down:
		return
	_tick_search(dt)
	if _down:
		return
	_tick_gang(dt)


## A place left, a new day, woken or put to sleep: let go of everyone, then arm who is armed here today.
func _watch() -> void:
	var now := _awake()
	if main._building == _building and int(main._day) == _day and now == _awake_was:
		return
	_teardown()
	_building = main._building
	_place = main._place
	_day = int(main._day)
	_awake_was = now
	_down = false
	_hook_place()
	if now:
		_setup()


## The detectors and the stash here: they work whether the foes are awake or not.
func _hook_place() -> void:
	_detectors = []
	for d: Node in get_tree().get_nodes_in_group("foes_detector"):
		if not _building.is_ancestor_of(d):
			continue
		_detectors.append(d)
		d.armed = _carries
		var numbers: Dictionary = (d.numbers as Dictionary).duplicate()
		numbers.merge(_rule("detector"), true)
		d.numbers = numbers
		if not d.has_meta("foes_hooked"):
			d.set_meta("foes_hooked", true)
			d.tripped.connect(_on_tripped)
	_stash = null
	for point: Node3D in (_building.use_points if "use_points" in _building else []):
		if point.id == "stash":
			_stash = point
			if not point.has_meta("foes_hooked"):
				point.set_meta("foes_hooked", true)
				point.used.connect(_on_stash)
	_label_stash()


func _setup() -> void:
	_foes = []
	var police := _rule("police")
	var rule: Dictionary = _rule("gang").get("places", {}).get(_place, {})
	var dice := RandomNumberGenerator.new()
	dice.seed = hash("foes/%s/%d" % [_place, _day])       # the same place on the same day: the same people armed
	var forced: Dictionary = _forced.get(_place, {})
	var armed: Array = []
	for p: RefCounted in people.here():
		var a: Node3D = p.actor
		var who: String = a._who
		var kind := ""
		var weapon := ""
		if who == String(police.get("rig", "cop")):
			kind = "police"
			weapon = String(police.get("weapon", "pistol"))
		elif who in rule.get("who", []):
			var roll := dice.randf()
			var pick := _pick(dice, rule.get("weapons", {"pistol": 1}))
			if roll < float(rule.get("odds", 0.0)):
				kind = "gang"
				weapon = pick
		for key: String in [who, String(a.name).to_lower(), String(a.display_name).to_lower()]:
			if forced.has(key):
				kind = "gang"
				weapon = forced[key]
		if kind == "" or p.state == "dead" or p.taken:
			continue
		var f := Foe.new()
		f.p = p
		f.kind = kind
		f.weapon = weapon
		f.health_was = int(p.health)
		f.called = String(a.display_name) if a.display_name != "" else String(a.name)
		var n := 1
		for g: Foe in _foes:          # (names are only told apart within a room: the police station has several Cops)
			if g.called == f.called or g.called.begins_with(f.called + " #"):
				n += 1
		if n > 1:
			f.called = "%s #%d" % [f.called, n]
		f.home = a.position
		p.foe = true
		_foes.append(f)
		armed.append("%s (%s%s)" % [f.called, weapon, "" if kind == "gang" else ", police"])
	_last_shot = combat.last
	_lead_at = main._actor.global_position
	if not armed.is_empty():
		_note("%s, day %d: armed here: %s" % [_place, _day + 1, ", ".join(armed)])


func _pick(dice: RandomNumberGenerator, weights: Dictionary) -> String:
	var total := 0.0
	for w: String in weights:
		total += float(weights[w])
	var r := dice.randf() * total
	for w: String in weights:
		r -= float(weights[w])
		if r <= 0.0:
			return w
	return "pistol"


func _teardown() -> void:
	for f: Foe in _foes:
		_release(f, true)
		f.p.foe = false
	_foes = []
	_search = {}
	_quiet = 0.0
	_was_armed = false
	_hands_said = false


## He is moved by a FoeBrain from now on, may walk anywhere he could, and is nobody to talk to.
func _take(f: Foe) -> void:
	if f.brain != null:
		return
	var p := f.p
	var a: Node3D = p.actor
	var brain := FoeBrain.new()
	brain.actor = a
	brain.to_screen = Callable(main, "_screen_dir")
	f.brain = brain
	f.brain_was = p.member["brain"]
	p.member["brain"] = brain
	f.areas_was = a.areas.duplicate()
	f.others_was = a.others.duplicate()
	f.reach_was = a.use_reach
	f.face_was = a.face.expression if a.face else ""
	a.areas = main._building.walk_areas()
	a.others = [main._actor]
	for q: RefCounted in people.living_here():
		if q != p:
			a.others.append(q.actor)
	a.use_reach = -1.0


## Back to what he was doing (and, leaving the place, back where he was).
func _release(f: Foe, back_home := false) -> void:
	var p := f.p
	var a: Node3D = p.actor
	if f.brain != null:
		if p.member["brain"] == f.brain:
			p.member["brain"] = f.brain_was
		if p.brain_was == f.brain:          # combat_people.gd took him over from us (down): give it his own
			p.brain_was = f.brain_was
			p.areas_was = f.areas_was
			p.others_was = f.others_was
			p.face_was = f.face_was
		if p.state != "dead":
			a.areas = f.areas_was
			a.others = f.others_was
			a.use_reach = f.reach_was
		f.brain = null
	if p.state != "dead":
		a.weapon = ""
		a.aiming = false
		a.aim_way = ""
		a.recoil = 0.0
		if a.face and f.face_was != "":
			a.face.talking = false
			a.face.set_expression(f.face_was)
		if back_home:
			a.position = f.home
			a.face_way("front")
	if f.label:
		f.label.queue_free()
		f.label = null
	if f.state != "dead" and f.state != "gone":
		f.state = "idle"


## Someone here draws on him: a shout (once), the gun out and turned on him.
func _engage(f: Foe, why: String, shout := true) -> void:
	if f.state != "idle" and f.state != "search":
		return
	_take(f)
	var a: Node3D = f.p.actor
	f.state = "draw"
	f.t = 0.0
	f.quiet = 0.0
	a.weapon = f.weapon
	a.aiming = true
	_turn(f)
	if shout and not f.shouted:
		f.shouted = true
		_say(f, _shout_line(f))
	elif a.face:
		a.face.set_expression(FACES[f.kind])
	_tally["draws"] += 1
	Deeds.drawn_on()      # bars: walked_away is counted if he leaves without firing (deeds.gd)
	_note("%s draws a %s (%s)" % [f.called, f.weapon, why])


## What he shouts as he draws: one of his kind's lines; an officer at someone running with his hands empty, "freeze".
func _shout_line(f: Foe) -> String:
	if f.kind == "police" and main._actor.weapon == "":
		return String(_rule("police").get("freeze", "FREEZE!"))
	var lines: Array = (_rule(f.kind).get("shout", ["HEY!"]) as Array).duplicate()
	if lines.size() > 1:
		lines.erase(_last_line)       # two of them at once do not say the same thing
	_last_line = String(lines[_rng.randi() % lines.size()])
	return _last_line


## He puts it away again.
func _stand_down(f: Foe) -> void:
	_note("%s puts his gun away" % f.called)
	var a: Node3D = f.p.actor
	a.weapon = ""
	a.aiming = false
	a.aim_way = ""
	f.shouted = false
	f.on_him = 0.0
	if not _search.is_empty() and _search["foe"] == f:
		f.state = "search"            # he still has a search to finish
		return
	_release(f)


## Turn him to point it at the lead: across the screen (mirrored to point right) or at the camera.
func _turn(f: Foe) -> void:
	var a: Node3D = f.p.actor
	var lead: Node3D = main._actor
	var screen: Vector2 = main._screen_dir(Vector2(lead.position.x - a.position.x, lead.position.z - a.position.z))
	if screen.y > 0.0 and absf(screen.x) < screen.y * TOWARD:
		a.aim_way = "toward"
		a.face_way("front", false)
	else:
		a.aim_way = ""
		if absf(screen.x) > 0.05:
			a.face_way("front", screen.x > 0.0)


## Can this one see him: standing where he can be seen, in range, nothing solid between his eyes and him.
func _sees(f: Foe) -> bool:
	var a: Node3D = f.p.actor
	if f.p.state == "dead" or not a.is_visible_in_tree():
		return false
	var lead: Node3D = main._actor
	var eye := a.global_position + Vector3(0.0, a.height * 0.86, 0.0)
	if eye.distance_to(lead.global_position) > _num(_rule(f.kind), "sight", 18.0):
		return false
	var w: RefCounted = combat.world_for(main._building)
	for h: float in [0.84, 0.6, 0.72]:
		if not bool(w.trace(eye, lead.global_position + Vector3(0.0, lead.height * h, 0.0))["hit"]):
			return true
	return false


func _look(f: Foe, dt: float) -> void:
	f.look -= dt
	if f.look <= 0.0:
		f.look = LOOK_EVERY
		f.seen = _sees(f)


# ------------------------------------------------------------ him

func _tick_lead(dt: float) -> void:
	var lead: Node3D = main._actor
	var at: Vector3 = lead.global_position
	_lead_speed = Vector2(at.x - _lead_at.x, at.z - _lead_at.z).length() / dt
	_lead_at = at
	_still = _still + dt if _lead_speed < 0.15 else 0.0
	if _flinching:
		lead.flinch = move_toward(lead.flinch, 0.0, dt * 1.4)
		_flinching = lead.flinch != 0.0
	if _hurt_t > 0.0:
		_hurt_t -= dt
		if _hurt_t <= 0.0 and lead.face and not lead.face.hold:
			lead.face.set_expression(_face_was)


## A shot of his (combat.gd makes a new `last` for each): the gang near it draw, the police near it are on him.
func _heard_his() -> void:
	var last: Dictionary = combat.last
	if is_same(last, _last_shot):
		return
	_last_shot = last
	if String(last.get("what", "")) == "" or String(last.get("what", "")) == "click":
		return
	_tally["his_shots"] += 1
	var from: Vector3 = last.get("from", main._actor.global_position)
	_heard(from, last.get("at", from), null)


## A shot from `from` that ended at `to`: whoever is near it, or near its line, reacts.
func _heard(from: Vector3, to: Vector3, by: Foe) -> void:
	var gang := _rule("gang")
	for f: Foe in _foes:
		if f == by or f.p.state == "dead" or f.state == "gone":
			continue
		var at: Vector3 = f.p.actor.global_position
		if f.kind == "gang":
			if at.distance_to(from) <= _num(gang, "alert", 12.0) or _gap(from, to, at) <= _num(gang, "pass", 2.0):
				f.quiet = 0.0
				if f.state == "idle":
					_engage(f, "a shot near him")
		elif by == null and f.state == "idle" and at.distance_to(from) <= _num(_rule("police"), "hear", 18.0):
			_engage(f, "a shot", false)          # on him; the shout comes when they see him with it


## How far `at` is from the segment from `a` to `b`, on the floor.
static func _gap(a: Vector3, b: Vector3, at: Vector3) -> float:
	var p := Vector2(at.x, at.z)
	var s := Vector2(a.x, a.z)
	var d := Vector2(b.x, b.z) - s
	if d.length_squared() < 1e-6:
		return p.distance_to(s)
	return p.distance_to(s + d * clampf((p - s).dot(d) / d.length_squared(), 0.0, 1.0))


# ------------------------------------------------------------ police

func _tick_police(dt: float) -> void:
	var police := _rule("police")
	var lead: Node3D = main._actor
	var armed: bool = lead.weapon != ""
	var cause := armed or _running()
	var on := false
	for f: Foe in _foes:
		if f.kind != "police" or f.state == "dead":
			continue
		if f.p.state == "dead":
			_dead(f)
			continue
		_look(f, dt)
		if int(f.p.health) < f.health_was:      # shot: he is on him whatever
			f.health_was = int(f.p.health)
			f.hurt = _num(data, "hurt_face", 0.6)
			if f.state == "idle" or f.state == "search":
				_engage(f, "shot")
		if f.state == "idle" or f.state == "search":
			if f.seen and cause:
				_engage(f, "saw him with a %s" % lead.weapon if armed else "saw him run")
			continue
		on = true
		f.t += dt
		_fight_face(f, dt)
		if f.seen:
			_turn(f)
		if f.state == "draw":
			if f.t >= _num(police, "draw", 0.7):
				f.state = "up"
				f.cool = _between(police.get("first"), 0.3)
			continue
		if not (cause and f.seen):
			continue                  # out of sight, or his hands are empty: hold fire
		if not f.shouted:             # on him from a shot heard: the shout now, and a moment to drop it
			f.shouted = true
			_say(f, _shout_line(f))
			f.cool = _num(police, "draw", 0.7)
			continue
		f.on_him += dt
		f.cool -= dt
		if f.cool > 0.0:
			continue
		var gp: Dictionary = f.p.actor.gun_points()
		if gp.is_empty():
			continue
		f.cool = _between(police.get("every"), 0.7) if _fire(f, gp) != "" else 0.25
		if _down:
			return
	if not on:
		_quiet = 0.0
		_was_armed = false
		return
	if cause:
		_quiet = 0.0
		_was_armed = _was_armed or armed
		_hands_said = false
		return
	_quiet += dt
	var close: Foe = null
	for f: Foe in _foes:
		if f.kind == "police" and (f.state == "draw" or f.state == "up") and f.seen \
				and f.p.actor.global_position.distance_to(lead.global_position) <= _num(police, "arrest_range", 5.0):
			close = f
	if _was_armed and close != null:
		if not _hands_said:
			_hands_said = true
			_say(close, String(police.get("hands_up", "DON'T MOVE!")))
		if _quiet >= _num(police, "hands", 1.0):
			_arrest(String(police.get("why", "put his gun away in front of the police")))
		return
	if _quiet >= _num(police, "calm", 8.0):
		for f: Foe in _foes:
			if f.kind == "police" and (f.state == "draw" or f.state == "up"):
				_stand_down(f)
		_was_armed = false


## He ran from the search and is still on the move (stopped, he is not shot at: he has done as he was told).
func _running() -> bool:
	return String(_search.get("state", "")) == "run" and _lead_speed > 0.5


func _arrest(why: String) -> void:
	_note("arrest: %s" % why)
	_tally["arrests"] += 1
	_down = true
	_search = {}
	main._arrest(why)
	_building = null                  # (he is at the police station now: set up afresh at the next look, even with no frame between)


# ------------------------------------------------------------ the detector, the search

## The detector: has he a firearm on him at all (in his hands or not)?
func _carries() -> bool:
	return not (main._state.owned as Array).is_empty()


func _on_tripped(red: bool) -> void:
	var owned: Array = main._state.owned
	_tally["red" if red else "green"] += 1
	if not red: Deeds.once(main, "court_clean")      # bars: a deed (deeds.json): once a visit
	_note("detector: %s (he has %s)" % ["RED" if red else "green", ", ".join(owned) if not owned.is_empty() else "nothing on him"])
	if red and _awake() and _search.is_empty() and not _down and main._actor.weapon == "":
		_start_search()


## The officer who can walk up to him (behind him, from the camera) stops him; if none can, the nearest calls him over.
func _start_search() -> void:
	var lead: Node3D = main._actor
	var best: Foe = null
	var best_d := INF
	var can_walk := false
	for f: Foe in _foes:
		if f.kind != "police" or f.p.state == "dead" or f.state != "idle" or not f.p.actor.is_visible_in_tree():
			continue
		_take(f)
		var spot := _approach(f)
		var d: float = f.p.actor.global_position.distance_to(lead.global_position)
		var walks := spot != Vector2.INF
		if (walks and not can_walk) or (walks == can_walk and d < best_d):
			best = f
			best_d = d
			can_walk = walks
	for f: Foe in _foes:          # those not picked go back to what they were doing
		if f != best and f.kind == "police" and f.state == "idle":
			_release(f)
	if best == null:
		_note("search: no officer here to search him")
		return
	_tally["searches"] += 1
	best.state = "search"
	_search = {"state": "stop", "t": 0.0, "at": Vector2(lead.position.x, lead.position.z), "foe": best, "tries": 0, "said": false}
	_note("search: %s will stop him" % best.called)


func _tick_search(dt: float) -> void:
	if _search.is_empty():
		return
	var rule := _rule("search")
	var s := _search
	var f: Foe = s["foe"]
	if f.p.state == "dead" or f.state == "gone":
		_note("search: called off (%s is down)" % f.called)
		_search = {}
		return
	var lead: Node3D = main._actor
	var a: Node3D = f.p.actor
	var brain: FoeBrain = f.brain
	var him := Vector2(lead.position.x, lead.position.z)
	var gap: float = Vector2(a.position.x, a.position.z).distance_to(him)
	var reach := _num(rule, "reach", 0.85)
	s["t"] = float(s["t"]) + dt
	if lead.weapon != "":
		if s["state"] != "drawn":
			s["state"] = "drawn"     # he pulled it: the police rule (_tick_police) has him now
			brain.goal = Vector2.INF
			_note("search: he pulls his %s" % lead.weapon)
		return
	if s["state"] == "drawn":
		if _was_armed:
			return                    # put away with the police on him: theirs (an arrest, or in time they calm down)
		s["state"] = "stop"
		s["t"] = 0.0
		s["at"] = him
	var away: float = him.distance_to(s["at"])
	match String(s["state"]):
		"stop":
			if not s["said"] and float(s["t"]) >= _num(rule, "react", 0.35):
				s["said"] = true          # (a moment after the alarm, so it is seen first)
				_say(f, String(rule.get("stop", "HOLD IT!")))
			if away > _num(rule, "run_off", 2.0):
				_ran(f)
			elif float(s["t"]) >= _num(rule, "wait", 0.7):
				_walk_up(f)
		"walk":
			if away > _num(rule, "run_off", 2.0):
				_ran(f)
			elif gap <= reach + 0.35:
				_pat(f)
			elif brain.done:
				s["tries"] = int(s["tries"]) + 1
				if int(s["tries"]) < 3:
					_walk_up(f)
				else:
					_call_over(f)
			elif away > 0.35:          # he shuffled: walk to where he is now
				s["at"] = him
				_walk_up(f)
		"call":
			if gap <= reach + 0.45:
				_pat(f)
			elif away > _num(rule, "run_off", 2.0) and gap > float(s.get("gap", gap)) + 0.5:
				_ran(f)
		"pat":
			_face(f, lead.position)
			if gap > reach + 1.2:
				_ran(f)
			elif float(s["t"]) >= _num(rule, "pat", 1.3):
				_arrest(String(rule.get("why", "a firearm through the courthouse metal detector")))
		"run":
			if _still >= _num(rule, "still", 1.2):
				s["state"] = "stop"
				s["t"] = 0.0
				s["at"] = him
				_note("search: he stands still")


func _walk_up(f: Foe) -> void:
	var s := _search
	var spot := _approach(f)
	if spot == Vector2.INF:
		_call_over(f)
		return
	var brain: FoeBrain = f.brain
	brain.goal = spot
	brain.done = false
	brain.stuck = 0.0
	if s["state"] != "walk":
		_note("search: %s walks up to him (%.1f m)" % [f.called, Vector2(f.p.actor.position.x, f.p.actor.position.z).distance_to(spot)])
	s["state"] = "walk"


func _call_over(f: Foe) -> void:
	var s := _search
	var a: Node3D = f.p.actor
	(f.brain as FoeBrain).goal = Vector2.INF
	s["state"] = "call"
	s["gap"] = Vector2(a.position.x, a.position.z).distance_to(Vector2(main._actor.position.x, main._actor.position.z))
	_face(f, main._actor.position)
	_say(f, String(_rule("search").get("come", "OVER HERE!")))
	_note("search: %s cannot walk up to him (%s): he calls him over" % [f.called, _why_not])


func _pat(f: Foe) -> void:
	var s := _search
	(f.brain as FoeBrain).goal = Vector2.INF
	s["state"] = "pat"
	s["t"] = 0.0
	main._state.deed("searched")      # bars: a deed (deeds.json)
	_face(f, main._actor.position)
	var owned: Array = main._state.owned
	if not owned.is_empty():          # what he found, in his hand (carried, not pointed)
		f.p.actor.weapon = String(owned[0])
		f.p.actor.aiming = false
	_say(f, String(_rule("search").get("found", "WHAT'S THIS?")))
	_note("search: %s searches him" % f.called)


func _ran(f: Foe) -> void:
	var s := _search
	(f.brain as FoeBrain).goal = Vector2.INF
	s["state"] = "run"
	s["t"] = 0.0
	_say(f, String(_rule("police").get("freeze", "FREEZE!")))
	f.shouted = true
	_note("search: he runs")


func _face(f: Foe, at: Vector3) -> void:
	var a: Node3D = f.p.actor
	var across: float = main._screen_dir(Vector2(at.x - a.position.x, at.z - a.position.z)).x
	if absf(across) > 0.05:
		a.face_way("front", across > 0.0)


## Where the officer can walk to, to search him: a spot beside him he can reach in a straight line that runs
## towards the camera (he is drawn only from the front, and faces the way he walks), clear of props, not through
## him. Vector2.INF if there is none.
func _approach(f: Foe) -> Vector2:
	var a: Node3D = f.p.actor
	var lead: Node3D = main._actor
	var from := Vector2(a.position.x, a.position.z)
	var him := Vector2(lead.position.x, lead.position.z)
	var near: Vector2 = main._floor_dir(Vector2(0.0, 1.0)).normalized()
	var reach := _num(_rule("search"), "reach", 0.85)
	var best := Vector2.INF
	var best_d := INF
	var no := {"way": 0, "stand": 0, "line": 0, "him": 0}
	for r: float in [reach, reach + 0.3]:         # beside him, or a step further off
		for i in 24:
			var q := him + Vector2.from_angle(TAU * float(i) / 24.0) * r
			var go := q - from
			if go.length() < 0.1:
				return from
			if absf(go.angle_to(near)) > CONE:
				no["way"] += 1
			elif not a.can_stand(q):
				no["stand"] += 1
			elif not _clear_line(a, from, q):
				no["line"] += 1
			elif _gap(Vector3(from.x, 0.0, from.y), Vector3(q.x, 0.0, q.y), Vector3(him.x, 0.0, him.y)) < r - 0.1:
				no["him"] += 1        # it would take him through the lead
			else:                     # beside him on screen rather than behind or in front, where the two flat figures would stack into one
				var d := go.length() + (0.0 if absf(main._screen_dir(q - him).x) >= r * 0.6 else 4.0)
				if d < best_d:
					best_d = d
					best = q
		if best != Vector2.INF:
			break
	_why_not = "of 48 spots round him: %d the wrong way, %d where he cannot stand, %d not in a clear line, %d through him" % [no["way"], no["stand"], no["line"], no["him"]]
	return best


func _clear_line(a: Node3D, from: Vector2, to: Vector2) -> bool:
	var n := int(ceil(from.distance_to(to) / 0.1))
	for k in range(1, n + 1):
		if not a.can_stand(from.lerp(to, float(k) / float(n))):
			return false
	return true


# ------------------------------------------------------------ gang

func _tick_gang(dt: float) -> void:
	var gang := _rule("gang")
	for f: Foe in _foes:
		if f.kind != "gang" or f.state == "dead":
			continue
		if f.state == "gone":                     # broke off and ran: still counted if he goes down
			if f.p.state == "dead":
				f.state = "dead"
				_tally["down"] += 1
				_note("%s is down (he had broken off)" % f.called)
			continue
		var p := f.p
		if p.state == "dead":
			_dead(f)
			continue
		if int(p.health) < f.health_was:        # shot
			f.health_was = int(p.health)
			f.hurt = _num(data, "hurt_face", 0.6)
			f.quiet = 0.0
			if f.state == "idle":
				_engage(f, "shot")
			elif _breaks(f):
				continue
		if f.state == "idle":
			continue
		_look(f, dt)
		f.t += dt
		f.quiet = 0.0 if f.seen else f.quiet + dt
		_fight_face(f, dt)
		if f.seen:
			_turn(f)
		var w := f.weapon
		if f.state == "draw":
			if f.t >= _num(gang, "draw", 0.45):
				f.state = "up"
				f.cool = _between(gang.get("first"), 0.3)
				f.burst = _burst(gang, w)
			continue
		if f.quiet >= _num(gang, "calm", 12.0):
			_stand_down(f)
			continue
		if not f.seen:
			continue
		f.on_him += dt
		f.cool -= dt
		if f.cool > 0.0:
			continue
		var gp: Dictionary = p.actor.gun_points()
		if gp.is_empty():
			continue
		if _fire(f, gp) == "":
			f.cool = 0.25
			continue
		f.burst -= 1
		if f.burst > 0:
			f.cool = _between(gang.get("every", {}).get(w), 0.5)
		else:
			f.burst = _burst(gang, w)
			f.cool = _between(gang.get("rest"), 1.0)
		if _down:
			return


func _burst(gang: Dictionary, w: String) -> int:
	var b: Variant = gang.get("burst", {}).get(w, [1, 1])
	if typeof(b) == TYPE_ARRAY and (b as Array).size() == 2:
		return _rng.randi_range(int(b[0]), int(b[1]))
	return 1


## Badly hurt: maybe he breaks off and runs, like anyone frightened. True if he did.
func _breaks(f: Foe) -> bool:
	var gang := _rule("gang")
	if f.rolled or int(f.p.health) > int(_num(gang, "break_health", 40.0)):
		return false
	f.rolled = true
	if _rng.randf() >= _num(gang, "break_odds", 0.5):
		return false
	_release(f)
	f.p.foe = false
	f.state = "gone"
	_tally["broke"] += 1
	_note("%s breaks off and runs" % f.called)
	var lead: Vector3 = main._actor.global_position
	var at: Vector3 = f.p.actor.global_position
	people.alarm(lead if lead.distance_to(at) <= 17.0 else at)      # (combat_people.gd: he runs from the lead)
	return true


func _dead(f: Foe) -> void:
	_release(f)
	f.state = "dead"
	_tally["down"] += 1
	_note("%s is down (%d shots fired, %d hit him)" % [f.called, f.shots, f.hits])


## His face while he is at it: hurt a moment after a hit, then his fighting face; a shout has its own.
func _fight_face(f: Foe, dt: float) -> void:
	var a: Node3D = f.p.actor
	if f.hurt > 0.0:
		f.hurt -= dt
		if f.hurt <= 0.0 and a.face and f.label_t <= 0.0:
			a.face.set_expression(FACES[f.kind])


# ------------------------------------------------------------ a shot

## The first clear point on him from `muzzle` (chest, shoulders, head, belly), or null.
func _aim_point(muzzle: Vector3) -> Variant:
	var lead: Node3D = main._actor
	var w: RefCounted = combat.world_for(main._building)
	for h: float in [0.6, 0.72, 0.84, 0.45]:
		var at: Vector3 = lead.global_position + Vector3(0.0, lead.height * h, 0.0)
		if not bool(w.trace(muzzle, at)["hit"]):
			return at
	return null


## How likely a shot from `d` metres is to hit him.
func _chance(f: Foe, d: float) -> float:
	var rule := _rule(f.kind)
	var close := _num(rule, "close", 1.5)
	var near := _num(rule, "near", 4.0)
	var far := _num(rule, "far", 18.0)
	var c := lerpf(_num(rule, "hit_near", 0.5), _num(rule, "hit_far", 0.1), clampf((d - near) / maxf(far - near, 0.1), 0.0, 1.0))
	if d < near:                      # closer still, surer still: point blank hardly misses
		c = lerpf(_num(rule, "hit_close", 0.9), _num(rule, "hit_near", 0.5), clampf((d - close) / maxf(near - close, 0.1), 0.0, 1.0))
	if _lead_speed > 0.5:
		c *= _num(data, "sprinting", 0.5) if main._actor.sprinting else _num(data, "moving", 0.7)
	return c


## Fire one shot at him from `gp` (paper_actor.gd's gun_points). What it hit: "him", "person", "wall", "nothing",
## or "" if it did not go off (no clear line; for the police, someone else in the way). `sure`: it hits him.
func _fire(f: Foe, gp: Dictionary, sure := false) -> String:
	var a: Node3D = f.p.actor
	var lead: Node3D = main._actor
	var w: RefCounted = combat.world_for(main._building)
	var muzzle: Vector3 = gp["muzzle"]
	var chest := a.global_position + Vector3(0.0, a.height * 0.62, 0.0)
	if bool(w.trace(chest, muzzle)["hit"]):
		return ""                     # the gun is through a wall he stands against
	var aim: Variant = _aim_point(muzzle)
	if aim == null:
		return ""
	if f.kind == "police" and not _along(muzzle, aim, f.p).is_empty():
		return ""                     # someone else in the line of fire: an officer holds it
	if f.p.state == "dead" or not a.is_visible_in_tree():
		_problem("%s fired while %s" % [f.called, "dead" if f.p.state == "dead" else "out of sight"])
	if f.kind == "police" and lead.weapon == "" and not _running():
		_problem("%s fired at him with his hands empty, standing still" % f.called)
	var target: Vector3 = aim
	if not sure and _rng.randf() >= _chance(f, muzzle.distance_to(aim)):
		target = _miss(muzzle, aim)
	var dir := (target - muzzle).normalized()
	var end := muzzle + dir * RANGE
	var hit: Dictionary = w.trace(muzzle, end)
	var stop := float(hit["t"]) if hit["hit"] else 1.0
	var what := "wall" if hit["hit"] else "nothing"
	var who := _along(muzzle, end, f.p)
	if not who.is_empty() and float(who["t"]) < stop:
		stop = float(who["t"])
		what = "person"
	var t_him := _through_him(muzzle, end)
	if t_him >= 0.0 and t_him < stop:
		stop = t_him
		what = "him"
	var at := muzzle + (end - muzzle) * stop
	var node: Node3D = people._node_for(at)
	var ground: float = lead.global_position.y
	for pane: Dictionary in hit["panes"]:
		if float(pane["t"]) >= stop:
			break
		if combat._break(pane["entry"].mi, pane["pos"], dir):
			_tally["panes"] += 1
	var room: Node3D = people._node_for(a.global_position)
	var gun: Dictionary = combat.GUNS.get(f.weapon, combat.GUNS["pistol"])
	fx.flash(gp, float(gun["flash"]), room)
	_eject(gp, gun, room, a.global_position.y)
	if fx.has_method("tracer"):
		fx.tracer(muzzle, at, room)
	a.recoil = 1.0
	f.shots += 1
	if f.shots == 1: main._state.deed("shot_at_by_police" if f.kind == "police" else "shot_at_by_gang")      # bars: a deed (deeds.json)
	_tally["police_shots" if f.kind == "police" else "gang_shots"] += 1
	match what:
		"him":
			f.hits += 1
			_hit_him(f, at, dir)
		"person":
			_tally["bystanders_hit"] += 1
			var p: RefCounted = who["person"]
			var result: String = people.hit(p, who["point"], dir, int(gun["damage"]))
			_note("%s hits %s: %s" % [f.called, String(p.actor.display_name) if p.actor.display_name != "" else String(p.actor.name), result])
		"wall":
			_tally["marks"] += 1
			if hit["block"]:
				Glass.crack(hit["mi"], at, hit["normal"], _rng)
				fx.shards(at, hit["normal"], dir, 0.08, 6, w.floor_at(at, ground), node)
			else:
				fx.impact(at, hit["normal"], hit["mi"], hit["metal"], node, w.floor_at(at, ground))
	if _down:
		return what
	people.alarm(a.global_position)
	_heard(a.global_position, at, f)
	return what


## A point to send a miss through: past him, to one side and up or down.
func _miss(muzzle: Vector3, aim: Vector3) -> Vector3:
	var d := (aim - muzzle).normalized()
	var side := d.cross(Vector3.UP)
	side = side.normalized() if side.length() > 0.1 else Vector3.RIGHT
	return aim + side * _rng.randf_range(0.45, 0.9) * (1.0 if _rng.randf() < 0.5 else -1.0) + Vector3.UP * _rng.randf_range(-0.35, 0.45)


## The spent case, out of the port, as combat.gd throws his.
func _eject(gp: Dictionary, gun: Dictionary, room: Node3D, ground: float) -> void:
	var d: Vector3 = gp["dir"]
	var side := d.cross(Vector3.UP)
	if side.length() < 0.2:
		side = main._camera.global_transform.basis.x
	side = side.normalized()
	var vel := side * _rng.randf_range(1.0, 1.7) + Vector3.UP * _rng.randf_range(1.7, 2.4) - d * _rng.randf_range(0.3, 0.7)
	fx.shell(gp["eject"], vel, ground, float(gun["shell"]), room)


## He is hit at `at` by a shot going `dir`: blood, a flinch, a hurt face, his health (combat.gd's hurt).
func _hit_him(f: Foe, at: Vector3, dir: Vector3) -> void:
	var lead: Node3D = main._actor
	var damage := int(_num(_rule("police"), "damage", 14.0)) if f.kind == "police" else int(_rule("gang").get("damage", {}).get(f.weapon, 10))
	var cam: Camera3D = main._camera
	var n: Vector3 = lead.global_transform.basis.z
	var plane := at - n * (at - lead.global_position).dot(n)
	fx.blood(plane + (cam.global_position - plane).normalized() * 0.06, dir, lead.global_position.y, people._node_for(lead.global_position))
	var across := dir.dot(cam.global_transform.basis.x)
	lead.flinch = -_num(data, "flinch", 0.22) * (signf(across) if across != 0.0 else 1.0)       # he jerks away from it
	_flinching = true
	if lead.face and not lead.face.hold:
		if _hurt_t <= 0.0:
			_face_was = lead.face.expression
		lead.face.set_expression("hurt", true)
		_hurt_t = _num(data, "hurt_face", 0.6)
	_tally["hits_on_him"] += 1
	_tally["damage"] += damage
	var before := int(main._state.health)
	_note("%s hits him: health %d -> %d" % [f.called, before, maxi(before - damage, 0)])
	if before <= 0:
		return
	main._state.deed("wounded")      # bars: a deed (deeds.json)
	combat.hurt(damage)
	if int(main._state.health) <= 0 or main._building != _building:
		_note("he is down")
		_down = true


## Where a shot from `from` to `to` first goes into him (0..1 along it), or -1 (as combat_people.gd's along()).
func _through_him(from: Vector3, to: Vector3) -> float:
	var lead: Node3D = main._actor
	return _into(lead, from, to)


static func _into(a: Node3D, from: Vector3, to: Vector3) -> float:
	var d := to - from
	var flat := Vector2(d.x, d.z)
	var len2 := flat.length_squared()
	if len2 < 1e-8:
		return -1.0
	var f := Vector2(from.x, from.z)
	var c := Vector2(a.global_position.x, a.global_position.z)
	var r: float = 0.24 * a.reach / 0.4
	var t := clampf((c - f).dot(flat) / len2, 0.0, 1.0)
	var gap := (f + flat * t).distance_squared_to(c)
	if gap > r * r:
		return -1.0
	var t0 := maxf(t - sqrt(r * r - gap) / sqrt(len2), 0.0)
	var foot: float = a.global_position.y
	var y0 := from.y + d.y * t0
	var y1 := from.y + d.y * t
	if (y0 < foot or y0 > foot + a.height) and (y1 < foot or y1 > foot + a.height):
		return -1.0
	return t0


## The first living person (not `skip`) a shot from `from` to `to` goes into: {"person", "t", "point"}, or {}.
func _along(from: Vector3, to: Vector3, skip: RefCounted) -> Dictionary:
	var best := {}
	var first := INF
	for p: RefCounted in people.living_here():
		if p == skip:
			continue
		var t := _into(p.actor, from, to)
		if t >= 0.0 and t < first:
			first = t
			best = {"person": p, "t": t, "point": from + (to - from) * t}
	return best


# ------------------------------------------------------------ shouting

func _say(f: Foe, text: String) -> void:
	var a: Node3D = f.p.actor
	if f.label == null:
		var l := Label3D.new()
		l.font = FONT
		l.font_size = 56
		l.fixed_size = true             # the same size on screen near or far, so the nearest one does not shout loudest
		l.pixel_size = 0.00055
		l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		l.outline_size = 18
		l.modulate = Color(1.0, 0.96, 0.84)
		l.outline_modulate = Color(0.03, 0.02, 0.05)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true          # read over whatever stands in front of him (an arch, a counter)
		l.render_priority = 2
		l.outline_render_priority = 1
		l.position = Vector3(0.0, a.height + SAY_UP, 0.0)
		a.add_child(l)
		f.label = l
	f.label.text = text
	f.label.visible = true
	f.label_t = SAY_TIME
	if a.face:
		a.face.set_expression("shout")
		a.face.talking = true
	_note('%s shouts "%s"' % [f.called, text])


func _tick_say(f: Foe, dt: float) -> void:
	if f.label_t <= 0.0:
		return
	f.label_t -= dt
	if f.label_t > 0.0:
		return
	if f.label:
		f.label.visible = false
	var a: Node3D = f.p.actor
	if a.face and f.p.state != "dead":
		a.face.talking = false
		a.face.set_expression(FACES[f.kind] if f.state == "draw" or f.state == "up" else (f.face_was if f.face_was != "" else "neutral"))


# ------------------------------------------------------------ the stash

## E at the stash: everything he has goes in it; with nothing on him, he takes it all back.
func _on_stash(_id: String = "", _by: Node3D = null) -> void:
	var state: RefCounted = main._state
	var kept: Array = state.flags.get("stash", [])
	if not (state.owned as Array).is_empty():
		for w: String in state.owned:
			if not w in kept:
				kept.append(w)
		state.flags["stash"] = kept
		state.deed("guns_stashed")      # bars: a deed (deeds.json)
		main._actor.weapon = ""
		main._actor.aiming = false
		main._aim_off()
		state.disarm()
		_note("stash: he leaves %s in it" % ", ".join(kept))
	elif not kept.is_empty():
		state.flags.erase("stash")
		for w: String in kept:
			state.own(w)
		state.touch()
		_note("stash: he takes %s" % ", ".join(kept))
	else:
		_note("stash: nothing in it, nothing on him")
	_label_stash()
	main._save_game()


func _label_stash() -> void:
	if _stash == null:
		return
	var rule := _rule("stash")
	if not (main._state.owned as Array).is_empty():
		_stash.label = String(rule.get("put", "STASH GUNS"))
	elif not (main._state.flags.get("stash", []) as Array).is_empty():
		_stash.label = String(rule.get("take", "TAKE GUNS"))
	else:
		_stash.label = String(rule.get("empty", "STASH"))


# ------------------------------------------------------------ for the steps and the check

func _note(text: String) -> void:
	events.append("%6.2f  %s" % [_clock, text])
	if main._scripted:
		print("[shot] foe: ", text)


func _problem(text: String) -> void:
	_problems.append(text)
	print("[shot] foe: PROBLEM: ", text)


func _wake() -> void:
	wake = 1
	_watch()


## A --do step (see the top of main.gd): foe:... or foecheck.
func step(bits: PackedStringArray) -> void:
	_watch()                          # (a place: step just before has not had a frame yet)
	if bits[0] == "foecheck":
		_check()
		return
	var what := bits[1] if bits.size() > 1 else ""
	var arg := bits[2] if bits.size() > 2 else ""
	match what:
		"on":
			_wake()
			print("[shot] foe: awake at %s: %d armed here" % [_place, _foes.size()])
		"off":
			wake = -1
			_watch()
			print("[shot] foe: asleep")
		"arm":              # foe:arm:who[:weapon]
			var who := arg.to_lower()
			var weapon := bits[3] if bits.size() > 3 else "pistol"
			if not _forced.has(main._place):
				_forced[main._place] = {}
			_forced[main._place][who] = weapon
			wake = 1
			_building = null          # set up again, with him armed
			_watch()
			var found := false
			for f: Foe in _foes:
				if f.called.to_lower() == who or String(f.p.actor.name).to_lower() == who or String(f.p.actor._who) == who:
					found = true
			print("[shot] foe: %s" % ("%s carries a %s, out of sight" % [arg, weapon] if found else "nobody called %s here" % arg))
		"alert":            # foe:alert or foe:alert:who
			_wake()
			var drew: Array = []
			for f: Foe in _foes:
				if f.kind == "gang" and f.state == "idle" and (arg == "" or f.called.to_lower() == arg.to_lower() or String(f.p.actor.name).to_lower() == arg.to_lower()):
					_engage(f, "told to (foe:alert)")
					drew.append(f.called)
			print("[shot] foe: alert: %s" % (", ".join(drew) if not drew.is_empty() else "nobody armed here to draw"))
		"cops":             # foe:cops[:seconds]
			await _cops(float(arg) if arg != "" else 3.0)
		"hitme":            # foe:hitme[:n]
			await _hit_me(int(arg) if arg != "" else 1)
		"putaway":
			main._actor.weapon = ""
			main._actor.aiming = false
			main._aim_off()
			print("[shot] foe: he puts it away")
		"stash":
			_on_stash()
			print("[shot] foe: stash: he has %s; in the stash: %s" % [main._state.owned, main._state.flags.get("stash", [])])
		"through":          # foe:through[:red|green[:in]]
			await _through(arg, bits.size() > 3 and bits[3] == "in")
		"go":               # foe:go:x:z[:run][:shot]
			var how: PackedStringArray = bits.slice(4)
			await _go(Vector2(float(arg), float(bits[3]) if bits.size() > 3 else 0.0), how.has("run"), how.has("shot"))
		"search":           # foe:search[:seconds]
			await _await_search(float(arg) if arg != "" else 12.0)
		"run":              # foe:run:seconds
			for i in int((float(arg) if arg != "" else 1.0) * 60.0):
				await get_tree().process_frame
			print("[shot] foe: %.1f s on; health %d" % [float(arg) if arg != "" else 1.0, int(main._state.health)])
		"until":            # foe:until:shot|hit|draw|down[:seconds]: on until the next one (a picture can catch it)
			var secs := float(bits[3]) if bits.size() > 3 else 4.0
			var start := _count(arg)
			for i in int(secs * 60.0):
				await get_tree().process_frame
				if _count(arg) > start or _down:
					break
			print("[shot] foe: until %s: %s; health %d" % [arg, "yes" if _count(arg) > start else "NOT in %.1f s" % secs, int(main._state.health)])
		_:
			print("[shot] unknown step: %s" % ":".join(bits))


func _count(what: String) -> int:
	match what:
		"shot":
			return int(_tally["police_shots"]) + int(_tally["gang_shots"])
		"hit":
			return int(_tally["hits_on_him"])
		"down":
			return int(_tally["down"])
		"draw":
			return int(_tally["draws"])
	return 0


## foe:cops: he has his gun out where the police here can see him, for `seconds`.
func _cops(seconds: float) -> void:
	_wake()
	if main._actor.weapon == "":
		if (main._state.owned as Array).is_empty():
			main._state.own("pistol")
		main._actor.weapon = String(main._state.owned[0])
	var before := int(_tally["police_shots"])
	var health := int(main._state.health)
	var saw := {}
	for i in int(seconds * 60.0):
		await get_tree().process_frame
		if _down:
			break
		for f: Foe in _foes:
			if f.kind == "police" and f.seen:
				saw[f.called] = true
	var fired := int(_tally["police_shots"]) - before
	var officers := 0
	for f: Foe in _foes:
		officers += 1 if f.kind == "police" else 0
	var police := _rule("police")
	var first: Variant = police.get("first", [0.2, 0.45])
	var enough := _num(police, "draw", 0.7) + (float(first[1]) if typeof(first) == TYPE_ARRAY and (first as Array).size() == 2 else 0.5) + 0.5
	print("[shot] foe: cops: he holds a %s; %d officers here, %d saw him, %d shots at him in %.1f s%s; health %d -> %d%s" % [main._actor.weapon,
			officers, saw.size(), fired, seconds, " (too soon to fire: they draw first)" if seconds < enough else "", health, int(main._state.health), " (down)" if _down else ""])
	if saw.size() > 0 and fired == 0 and not _down and seconds >= enough:
		_problem("officers saw him with a gun for %.1f s and nobody fired" % seconds)


## foe:hitme: a foe here who can see him shoots him `n` times, every one a hit.
func _hit_me(n: int) -> void:
	_wake()
	var pick: Foe = null
	for f: Foe in _foes:
		if f.p.state != "dead" and f.state != "gone" and _sees(f) and (pick == null or f.state == "up"):
			pick = f
	if pick == null:
		print("[shot] foe: hitme: nobody armed here can see him")
		return
	_engage(pick, "told to (foe:hitme)")
	for i in 90:
		if pick.state == "up" and not pick.p.actor.gun_points().is_empty():
			break
		await get_tree().process_frame
	var before := int(main._state.health)
	var hits := 0
	for k in n:
		if _down or pick.p.state == "dead":
			break
		var gp: Dictionary = pick.p.actor.gun_points()
		if gp.is_empty():
			break
		if _fire(pick, gp, true) == "him":
			hits += 1
		for i in 12:
			await get_tree().process_frame
	print("[shot] foe: hitme: %s fired %d, %d hit him: health %d -> %d%s" % [pick.called, n, hits, before, int(main._state.health), " (down)" if _down else ""])
	if hits == 0:
		_problem("hitme: %s could not hit him" % pick.called)


## foe:through: he walks through the metal detector here, from the street side; red: with a firearm on him
## (the stash's, or a pistol), green: with none (all of it into the stash). `stop_in`: he stops in the arch, the
## lamps lit (a picture can catch them).
func _through(want: String, stop_in := false) -> void:
	if _detectors.is_empty():
		print("[shot] foe: through: no metal detector here")
		return
	var state: RefCounted = main._state
	if want == "green" and not (state.owned as Array).is_empty():
		_on_stash()
	elif want == "red" and (state.owned as Array).is_empty():
		if not (state.flags.get("stash", []) as Array).is_empty():
			_on_stash()
		else:
			state.own("pistol")
	main._actor.weapon = ""
	main._aim_off()
	var d: Node3D = _detectors[0]
	var mid: Vector2 = d.zone.get_center()
	var times: int = d.times
	main._teleport(Vector3(mid.x, 0.0, mid.y + 1.3), true)
	for i in 4:
		await get_tree().process_frame
	var way := Vector2(0.0, -1.0)
	var lit := -1
	for i in 240:
		if main._actor.position.z <= mid.y - 0.85 or lit == 0:
			break
		if stop_in and lit < 0 and d.times > times:
			lit = 4                       # a few frames on, the lamps are still in their first blink
		lit -= 1 if lit > 0 else 0
		main._actor.walk(way if lit < 0 else Vector2.ZERO, main._screen_dir(way) if lit < 0 else Vector2.ZERO, 1.0 / 60.0)
		await get_tree().process_frame
	var expected := "green" if (state.owned as Array).is_empty() else "red"
	print("[shot] foe: through the detector: it showed %s (he has %s): %s" % [d.shown if d.times > times else "NOTHING",
			", ".join(state.owned) if not (state.owned as Array).is_empty() else "nothing on him", "ok" if d.times > times and d.shown == expected else "WRONG"])
	if d.times == times or d.shown != expected:
		_problem("the detector showed %s with %s on him" % [d.shown if d.times > times else "nothing", "a firearm" if expected == "red" else "nothing"])


## foe:go: he walks (runs, `run`) straight to `to` on the floor a frame at a time, so everyone here sees him go
## (main.gd's go: step moves him all at once). `shot`: he stops where he is at the first shot at him (a picture
## can catch it).
func _go(to: Vector2, run: bool, shot := false) -> void:
	var lead: Node3D = main._actor
	lead.areas = main._building.walk_areas()
	var was: bool = lead.sprinting
	lead.sprinting = run
	var stuck := 0
	var shots := _count("shot")
	for i in 600:
		var gap := to - Vector2(lead.position.x, lead.position.z)
		if gap.length() < 0.06 or _down or stuck > 20 or (shot and _count("shot") > shots):
			break
		var before := Vector2(lead.position.x, lead.position.z)
		lead.walk(gap.normalized(), main._screen_dir(gap.normalized()), 1.0 / 60.0)
		stuck = stuck + 1 if Vector2(lead.position.x, lead.position.z).distance_to(before) < 0.002 else 0
		await get_tree().process_frame
	lead.sprinting = was
	print("[shot] foe: %s to %.2f, %.2f%s" % ["ran" if run else "walked", lead.position.x, lead.position.z,
			" (stopped: in the way)" if stuck > 20 else (" (stopped: shot at)" if shot and _count("shot") > shots else "")])


## foe:search: wait for the search to end (an arrest, or he ran), up to `seconds`.
func _await_search(seconds: float) -> void:
	var arrests := int(_tally["arrests"])
	if _search.is_empty() and arrests == 0:
		print("[shot] foe: search: none under way")
		return
	for i in int(seconds * 60.0):
		if _search.is_empty() or _down or String(_search.get("state", "")) == "run":
			break
		await get_tree().process_frame
	var arrested := int(_tally["arrests"]) > arrests or (_down and int(_tally["arrests"]) > 0)
	print("[shot] foe: search: %s" % ("he was arrested, now at %s" % main._place if arrested else ("he ran" if String(_search.get("state", "")) == "run" else "STILL GOING after %.0f s" % seconds)))
	if not arrested and String(_search.get("state", "")) != "run":
		_problem("the search did not end in %.0f s" % seconds)


## --do=foecheck: what happened, and anything that should not have.
func _check() -> void:
	_watch()                          # (an arrest or the hospital may have just moved him)
	var lines: Array = []
	for f: Foe in _foes:
		lines.append("%s (%s, %s): %s, %d shots, %d hit him" % [f.called, f.kind, f.weapon, f.state if f.p.state != "dead" else "down", f.shots, f.hits])
		if (f.state == "up" or f.state == "draw") and f.on_him > 2.5 and f.shots == 0:
			_problem("%s had him in sight for %.1f s with cause and never fired" % [f.called, f.on_him])
	print("[shot] foecheck: at %s (%s): %s" % [main._place, "awake" if _awake() else "asleep", "; ".join(lines) if not lines.is_empty() else "nobody armed here"])
	var t := _tally
	print("[shot] foecheck: shots at him: police %d, gang %d; %d hit him for %d; his health %d" % [t["police_shots"], t["gang_shots"], t["hits_on_him"], t["damage"], int(main._state.health)])
	print("[shot] foecheck: his shots heard %d; bystanders hit %d; panes broken %d; marks %d; foes down %d; broke off %d" % [t["his_shots"], t["bystanders_hit"], t["panes"], t["marks"], t["down"], t["broke"]])
	print("[shot] foecheck: detector green %d, red %d; searches %d; arrests %d; stash %s" % [t["green"], t["red"], t["searches"], t["arrests"], main._state.flags.get("stash", [])])
	print("[shot] foecheck: what happened:")
	for e: String in events:
		print("[shot] foecheck:   ", e)
	for p: String in _problems:
		print("[shot] foecheck: PROBLEM: ", p)
	print("[shot] foecheck: %d problems" % _problems.size())
