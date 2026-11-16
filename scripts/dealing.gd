extends Node
## Selling on the street: the first rung, hand to hand. main.gd makes one (`_dealing`); it runs each frame after
## main.gd's own work, as combat.gd and melee.gd do. What he carries, where he has put a pack down, what he owes
## and who he has sold to are in the player state's `street` (street.gd), so they are in the save.
##
## A pack on the front: in the back lot someone hands him a pack on credit (a use point beside that person):
## sell it, bring the money back by tomorrow, keep the rest. Pay late and it costs respect. Paid, the next
## product is offered. His own tapes are dubbed at the studio once he has recorded a song, and sell the same way.
##
## G: he posts up where he stands. People near who are doing nothing else walk over one at a time (they find
## their own way, as people going back to their places do: combat_people.gd) and wait beside him; E serves
## one. Someone who has bought before may ask to pay tomorrow. A shot, a fight, or stepping away ends it.
## What he carries is what he is caught with: B puts everything down where he stands (a pack on the ground,
## picked up again with E); an arrest takes what is on him and the amount sets the charge.
##
## The street counts every sale (street.gd: heat, and an officer who sees one takes him in), and every buyer is
## a neighbour who remembers: sold enough ready or dope, he looks it.
##
## Every number, name and word on screen is a placeholder (assets/data/dealing.json).

const Street := preload("res://scripts/street.gd")
const DATA := "res://assets/data/dealing.json"

## A spot E can be used at that dealing.gd puts out itself (main.gd's _usables): a pack on the ground, the man
## with the front, a customer waiting.
class Point:
	extends Node3D
	var label := ""
	var use_reach := 1.5
	var label_height := 1.7
	var act: Callable

	func use_name() -> String:
		return label

	func use_spot() -> Vector3:
		return global_position

	func label_spot() -> Vector3:
		return global_position + Vector3(0, label_height, 0)

	func use(_by: Node3D = null) -> void:
		if act.is_valid():
			act.call()


var main: Node
var data := {}
var posted := false               # he is posted up
var last := {}                    # what the last sale was (for the steps)
var _post_at := Vector3.ZERO
var _next := 2.0                  # seconds till the next customer sets out
var _buyer := {}                  # the one on his way, waiting or leaving: {"p", "home", "stage", "t", "product", "credit"}
var _serve: Point
var _front: Point
var _tapes: Point
var _pack: Point                  # the pack on the ground here
var _bag: MeshInstance3D
var _place := ""
var _building: Node3D
var _day := -1
var _rng := RandomNumberGenerator.new()
var _skip := {}                   # people here who could not get to him (till he is somewhere else)
var _served := {}                 # who: when he was last served (this session), so the same face is not back at once


func _ready() -> void:
	main = get_parent()
	_rng.seed = 59
	var read: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	data = read if typeof(read) == TYPE_DICTIONARY else {}
	_serve = _point(func() -> void: serve())
	_front = _point(func() -> void: front())
	_tapes = _point(func() -> void: dub())
	_pack = _point(func() -> void: pick_up())
	_pack.use_reach = 1.2
	_pack.label_height = 0.9
	_bag = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.3, 0.2, 0.22)
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color(0.55, 0.4, 0.24)
	paper.roughness = 1.0
	box.material = paper
	_bag.mesh = box
	_bag.position.y = 0.1
	_pack.add_child(_bag)


func _point(act: Callable) -> Point:
	var p := Point.new()
	p.act = act
	p.visible = false
	add_child(p)
	return p


func _exit_tree() -> void:
	_buyer = {}


# ------------------------------------------------------------ what he has

func book() -> Dictionary:
	var s := Street.book(main._state)
	for key: String in ["carry", "sold"]:
		if typeof(s.get(key)) != TYPE_DICTIONARY:
			s[key] = {}
	if typeof(s.get("stash")) != TYPE_DICTIONARY:
		s["stash"] = {}               # place: {"x", "y", "z", "carry": {product: units}}
	if typeof(s.get("debt")) != TYPE_DICTIONARY:
		s["debt"] = {}                # {"amount", "due" (a day), "product", "late" (days counted)} or empty
	if typeof(s.get("charges")) != TYPE_ARRAY:
		s["charges"] = []
	return s


func carried(product := "") -> int:
	var carry: Dictionary = book()["carry"]
	if product != "":
		return int(carry.get(product, 0))
	var n := 0
	for k: String in carry:
		n += int(carry[k])
	return n


func give(product: String, units: int) -> void:
	var carry: Dictionary = book()["carry"]
	carry[product] = maxi(int(carry.get(product, 0)) + units, 0)
	if int(carry[product]) == 0:
		carry.erase(product)
	main._state.touch()


func _product(id: String) -> Dictionary:
	return (data.get("products", {}) as Dictionary).get(id, {})


## Units of product (not tapes) on him.
func holding() -> int:
	var n := 0
	for k: String in book()["carry"]:
		if not bool(_product(k).get("legal", false)):
			n += int(book()["carry"][k])
	return n


func _say(text: String) -> void:
	print("[shot] deal: " if main._scripted else "[deal] ", text)
	if main._combat and main._combat.hud:
		main._combat.hud.caption(text, 3.0)


# ------------------------------------------------------------ the front, the tapes

## The pack he would be handed next ("" if there is none left to offer).
func next_pack() -> String:
	var order: Array = (data.get("front", {}) as Dictionary).get("order", [])
	var paid := int(book().get("fronts_paid", 0))
	return String(order[mini(paid, order.size() - 1)]) if not order.is_empty() else ""


## E at the man with the front: pay what he owes if he can; with nothing owed, take the next pack.
func front() -> bool:
	var s := book()
	var debt: Dictionary = s["debt"]
	if not debt.is_empty():
		return pay()
	var product := next_pack()
	var pack: Dictionary = ((data.get("front", {}) as Dictionary).get("packs", {}) as Dictionary).get(product, {})
	if pack.is_empty():
		return false
	give(product, int(pack.get("units", 0)))
	s["debt"] = {"amount": int(pack.get("owe", 0)), "due": int(main._day) + int((data["front"] as Dictionary).get("days", 1)), "product": product, "late": 0}
	main._state.deed("pack_fronted")       # dealing: a deed (deeds.json)
	main._state.touch()
	_say("%d %sS ON THE FRONT. BRING BACK $%d BY TOMORROW." % [int(pack["units"]), String(_product(product).get("unit", "UNIT")), int(pack["owe"])])
	return true


func pay() -> bool:
	var s := book()
	var debt: Dictionary = s["debt"]
	if debt.is_empty():
		return false
	var owe := int(debt.get("amount", 0))
	if not main._state.spend(owe):
		_say("YOU OWE $%d. YOU HAVE $%d." % [owe, int(main._state.cash)])
		return false
	var late := int(debt.get("late", 0)) > 0
	s["debt"] = {}
	s["fronts_paid"] = int(s.get("fronts_paid", 0)) + 1
	main._state.deed("front_paid")         # dealing: a deed (deeds.json)
	if not late:
		Street.note(main, "pack_paid")
	_say("PAID $%d. %s" % [owe, "LATE." if late else "ON TIME."])
	return true


## E at the studio once he has a song: ten of his own tapes.
func dub() -> bool:
	var t: Dictionary = data.get("tapes", {})
	if int(main._state.songs) <= 0:
		_say("RECORD A SONG FIRST")
		return false
	if not main._state.spend(int(t.get("cost", 10))):
		_say("$%d FOR %d TAPES. YOU HAVE $%d." % [int(t.get("cost", 10)), int(t.get("units", 10)), int(main._state.cash)])
		return false
	give("tapes", int(t.get("units", 10)))
	_say("%d TAPES OF YOUR OWN SONG" % int(t.get("units", 10)))
	return true


# ------------------------------------------------------------ the pack on the ground

## B: everything he carries goes down where he stands (one pack to a place; more is added to it).
func put_down() -> bool:
	var s := book()
	var carry: Dictionary = s["carry"]
	if carry.is_empty() or posted:
		return false
	var lead: Node3D = main._actor
	var stash: Dictionary = s["stash"]
	var here: Dictionary = stash.get(main._place, {"carry": {}})
	if not here.has("x"):
		here["x"] = lead.position.x
		here["y"] = lead.position.y
		here["z"] = lead.position.z
	for k: String in carry:
		(here["carry"] as Dictionary)[k] = int((here["carry"] as Dictionary).get(k, 0)) + int(carry[k])
	stash[main._place] = here
	s["carry"] = {}
	main._state.touch()
	_say("PACK DOWN. NOTHING ON YOU.")
	return true


func pick_up() -> bool:
	var s := book()
	var stash: Dictionary = s["stash"]
	if not stash.has(main._place):
		return false
	var here: Dictionary = stash[main._place]
	for k: String in here.get("carry", {}):
		give(k, int(here["carry"][k]))
	stash.erase(main._place)
	main._state.touch()
	_say("PACK UP")
	return true


# ------------------------------------------------------------ posted up

func post(on: bool) -> bool:
	_sync()
	if on == posted:
		return false
	if on and (carried() <= 0 or main._actor.weapon != "" or (main._melee and main._melee.fighting())):
		_say("NOTHING TO SELL" if carried() <= 0 else "NOT WITH THAT IN YOUR HANDS")
		return false
	posted = on
	_post_at = main._actor.position
	_next = 1.5
	if not on:
		_send_away(false)
	_say("POSTED UP" if on else "STEPPED OFF")
	return true


## Someone here who would buy now, or null: calm, doing nothing else, near, not an officer.
func _someone() -> RefCounted:
	var c: Dictionary = data.get("customers", {})
	var lead: Node3D = main._actor
	var drugs := holding() > 0
	var never: Array = data.get("never", [])
	var pool: Array = []
	for p: RefCounted in main._combat.people.living_here():
		var a: Node3D = p.actor
		var who := Street.who_of(a)
		if p.taken or p.foe or p.state != "calm" or a.fallen > 0.0 or who == "cop" or _skip.has(a):
			continue
		if main._building.room_at_pos(a.position, -1) != main._room:
			continue                      # in another room: he does not come through doors to buy
		if who in never and (drugs or carried("tapes") <= 0):
			continue
		if a.position.distance_to(lead.position) > float(c.get("reach", 16.0)) or absf(a.position.y - lead.position.y) > 0.6:
			continue
		if int(_served.get(who, -100000)) > Time.get_ticks_msec() - 20000 and not main._scripted:
			continue                      # he was just here
		pool.append(p)
	return pool[_rng.randi() % pool.size()] if not pool.is_empty() else null


## What this person asks for, of what he carries.
func _wants(who: String) -> String:
	var carry: Dictionary = book()["carry"]
	var never: Array = data.get("never", [])
	var best := ""
	var most := -1.0
	for k: String in carry:
		if int(carry[k]) <= 0 or (who in never and not bool(_product(k).get("legal", false))):
			continue
		var w := float(_product(k).get("want", 0.5)) * _rng.randf_range(0.5, 1.5)
		if w > most:
			most = w
			best = k
	return best


func _set_out(p: RefCounted) -> void:
	var lead: Node3D = main._actor
	var a: Node3D = p.actor
	var c: Dictionary = data.get("customers", {})
	var who := Street.who_of(a)
	var product := _wants(who)
	if product == "":
		return
	var across: float = main._screen_dir(Vector2(a.position.x - lead.position.x, a.position.z - lead.position.z)).x
	var beside: Vector2 = main._floor_dir(Vector2((1.0 if across >= 0.0 else -1.0) * float(c.get("beside", 1.1)), 0.0))
	var people: RefCounted = main._combat.people
	var memory := Street.person(main._state, who)
	_buyer = {"p": p, "home": p.home, "stage": "coming", "t": 0.0, "product": product,
		"credit": int(memory.get("bought", 0)) > 0 and int(memory.get("owes", 0)) == 0 and _rng.randf() < float(c.get("credit", 0.2))}
	p.home = Vector3(lead.position.x + beside.x, a.position.y, lead.position.z + beside.y)
	people._take_over(p)
	people._go_home(p)                    # he finds his way to the spot beside the lead as he would to his own


## The one coming, waiting or leaving goes back to his place (`now`: put there at once: the place was left).
func _send_away(now: bool) -> void:
	_serve.visible = false
	main._usables.erase(_serve)
	if _buyer.is_empty():
		return
	var p: RefCounted = _buyer["p"]
	var home: Vector3 = _buyer["home"]
	_buyer = {}
	if p == null or not is_instance_valid(p.actor):
		return
	p.home = home
	var people: RefCounted = main._combat.people
	if now:
		if p.taken:
			people._let_go(p)
		if p.state != "dead":
			p.actor.position = home
		return
	if p.state == "dead":
		return
	main._set_frozen(p.actor, false)
	if p.state == "calm" or p.state == "returning":
		if not p.taken:
			people._take_over(p)
		people._go_home(p)


## E on the one waiting: one unit, for its price, or on credit if that is what he asked.
func serve() -> bool:
	if _buyer.is_empty() or String(_buyer["stage"]) != "waiting":
		return false
	var p: RefCounted = _buyer["p"]
	var a: Node3D = p.actor
	var who := Street.who_of(a)
	var product := String(_buyer["product"])
	if carried(product) <= 0:
		_send_away(false)
		return false
	var info := _product(product)
	var price := int(info.get("price", 10))
	var credit := bool(_buyer["credit"])
	var memory := Street.person(main._state, who)
	give(product, -1)
	var sold: Dictionary = book()["sold"]
	sold[product] = int(sold.get(product, 0)) + 1
	memory["bought"] = int(memory.get("bought", 0)) + 1
	_served[who] = Time.get_ticks_msec()
	if not bool(info.get("legal", false)):
		memory["used"] = int(memory.get("used", 0)) + (1 if product in ["ready", "dope"] else 0)
	if credit:
		memory["owes"] = int(memory.get("owes", 0)) + price
		main._state.deed("credit_given")   # dealing: a deed (deeds.json)
		Street.note(main, "credit_given", null, [a])
	else:
		main._state.earn(price)
	main._state.deed("tape_sold" if product == "tapes" else "pack_sold")      # dealing: a deed (deeds.json)
	var seen := Street.note(main, String(info.get("event", "sale")), null, [a])
	last = {"who": String(a.display_name), "product": product, "price": 0 if credit else price, "credit": credit, "police": int(seen.get("police", 0))}
	_say("%s: 1 %s, %s" % [String(a.display_name), String(info.get("unit", "UNIT")), "PAYS TOMORROW" if credit else "$%d" % price])
	_look(p)
	_send_away(false)
	_next = _rng.randf_range(float((data["customers"] as Dictionary)["every"][0]), float((data["customers"] as Dictionary)["every"][1]))
	if int(seen.get("police", 0)) > 0 and not bool(info.get("legal", false)):
		_say("POLICE SAW THE SALE")
		main._arrest("SOLD TO IN FRONT OF AN OFFICER")
	elif carried() <= 0:
		post(false)
	return true


## A neighbour who has bought enough ready or dope looks it.
func _look(p: RefCounted) -> void:
	var a: Node3D = p.actor
	if a.face == null or p.state == "dead":
		return
	var used := int(Street.person(main._state, Street.who_of(a)).get("used", 0))
	var d: Dictionary = data.get("decline", {})
	if used >= int(d.get("strung_out", 8)):
		a.face.set_expression("sleepy")
		p.face_was = "sleepy"
	elif used >= int(d.get("using", 3)):
		a.face.set_expression("nervous")
		p.face_was = "nervous"


## He is arrested (main.gd's _arrest): what is on him is taken, and how much it was sets the charge.
func on_arrest(why: String) -> void:
	posted = false
	_send_away(true)
	var units := holding()
	if units <= 0:
		return
	var s := book()
	var charge := "INTENT TO DISTRIBUTE" if units > int((data.get("charges", {}) as Dictionary).get("intent", 5)) else "POSSESSION"
	(s["charges"] as Array).append({"day": int(main._day), "charge": charge, "units": units, "why": why})
	var carry: Dictionary = s["carry"]
	for k: String in carry.keys():
		if not bool(_product(k).get("legal", false)):
			carry.erase(k)
	Street.add(main._state, "heat", 10 if charge == "POSSESSION" else 25)
	main._state.deed("caught_holding")     # dealing: a deed (deeds.json)
	print("%scaught holding %d: %s" % ["[shot] deal: " if main._scripted else "[deal] ", units, charge])


# ------------------------------------------------------------ each frame

func _process(delta: float) -> void:
	if main._actor == null or main._building == null or main._combat == null:
		return
	if main._scripted and not main.is_processing():
		return
	var dt := 1.0 / 60.0 if main._scripted else delta
	_sync()
	if int(main._day) != _day:
		if _day >= 0:
			_new_day()
		_day = int(main._day)
	_points()
	_sell(dt)
	_lines()


## He is somewhere else than he was: nobody is on his way to him any more, and he is not posted up.
func _sync() -> void:
	if main._building == _building:
		return
	_send_away(true)
	posted = false
	_skip.clear()
	_building = main._building
	_place = main._place
	_arrive()


## A place opened: the pack he left here, the people who look what they have bought.
func _arrive() -> void:
	for p: RefCounted in main._combat.people.living_here():
		if p.state == "calm":
			_look(p)


func _new_day() -> void:
	var debt: Dictionary = book()["debt"]
	if not debt.is_empty() and int(main._day) > int(debt.get("due", 0)):
		debt["late"] = int(debt.get("late", 0)) + 1
		Street.note(main, "pack_late")
		_say("THE FRONT IS LATE")
	if holding() <= 0 and (book()["debt"] as Dictionary).is_empty():
		Street.note(main, "quiet_day")


## Put out, or take in, the spots E can be used at.
func _points() -> void:
	var s := book()
	var f: Dictionary = data.get("front", {})
	var debt: Dictionary = s["debt"]
	var man := _talker(String(f.get("place", "")), String(f.get("talk", "")))
	if man != null:
		var product := next_pack()
		var pack: Dictionary = (f.get("packs", {}) as Dictionary).get(product, {})
		if not debt.is_empty():
			_front.label = "PAY THE FRONT  $%d" % int(debt.get("amount", 0))
		else:
			_front.label = "TAKE %d %sS ON THE FRONT  (OWE $%d)" % [int(pack.get("units", 0)), String(_product(product).get("unit", "UNIT")), int(pack.get("owe", 0))]
		_show(_front, man.global_position + _aside(0.9), true)
	else:
		_show(_front, Vector3.ZERO, false)
	var t: Dictionary = data.get("tapes", {})
	var dubber := _talker(String(t.get("place", "")), String(t.get("talk", "")))
	if dubber != null and int(main._state.songs) > 0:
		_tapes.label = "DUB %d TAPES  $%d" % [int(t.get("units", 10)), int(t.get("cost", 10))]
		_show(_tapes, dubber.global_position + _aside(-0.9), true)
	else:
		_show(_tapes, Vector3.ZERO, false)
	var stash: Dictionary = s["stash"]
	if stash.has(main._place):
		var here: Dictionary = stash[main._place]
		_pack.label = "PICK UP THE PACK"
		_show(_pack, Vector3(float(here.get("x", 0.0)), float(here.get("y", 0.0)), float(here.get("z", 0.0))), true)
	else:
		_show(_pack, Vector3.ZERO, false)


func _aside(x: float) -> Vector3:
	var d: Vector2 = main._floor_dir(Vector2(x, 0.0))
	return Vector3(d.x, 0.0, d.y)


func _show(point: Point, at: Vector3, on: bool) -> void:
	point.visible = on
	if on:
		point.global_position = at
		if not point in main._usables:
			main._usables.append(point)
	else:
		main._usables.erase(point)


## The person at this place who speaks from `talk`, if this is that place and he is up and about.
func _talker(place: String, talk: String) -> Node3D:
	if place != main._place or talk == "":
		return null
	for member: Dictionary in main._cast.get(place, []):
		var a: Node3D = member["actor"]
		if String(member.get("talk", "")) == talk and a.is_visible_in_tree() and a.fallen <= 0.0 and a.use_reach > 0.0:
			return a
	return null


func _sell(dt: float) -> void:
	var lead: Node3D = main._actor
	var c: Dictionary = data.get("customers", {})
	if posted:
		var trouble := false
		for p: RefCounted in main._combat.people.here():
			if p.state in ["alarmed", "fleeing", "hiding", "cowering", "held", "fighting"]:
				trouble = true
		var why := "trouble" if trouble else "something in his hands" if lead.weapon != "" else "he walked off" if lead.position.distance_to(_post_at) > float(c.get("step_off", 3.0)) else "nothing left" if carried() <= 0 else "a fight" if (main._melee and main._melee.fighting()) else ""
		if why != "":
			print("%soff the post: %s" % ["[shot] deal: " if main._scripted else "[deal] ", why])
			last["off"] = why
			post(false)
	if _buyer.is_empty():
		if posted:
			_next -= dt
			if _next <= 0.0:
				_next = _rng.randf_range(float(c["every"][0]), float(c["every"][1]))
				var p := _someone()
				if p != null:
					_set_out(p)
		return
	var p: RefCounted = _buyer["p"]
	var a: Node3D = p.actor
	_buyer["t"] = float(_buyer["t"]) + dt
	match String(_buyer["stage"]):
		"coming":
			if p.state == "calm":             # he has got as near as he can
				var gap := a.position.distance_to(lead.position)
				if gap <= float(c.get("beside", 1.1)) + 1.0:
					_buyer["stage"] = "waiting"
					_buyer["t"] = 0.0
					main._set_frozen(a, true)
				else:
					_skip[a] = true
					_send_away(false)
			elif p.state != "returning" or float(_buyer["t"]) > 25.0:
				_skip[a] = true
				_send_away(p.state != "returning" and p.state != "calm")
		"waiting":
			if p.state != "calm" or float(_buyer["t"]) > float(c.get("patience", 9.0)) or a.position.distance_to(lead.position) > 3.5:
				_send_away(false)
				return
			a.face_side(main._screen_dir(Vector2(lead.position.x - a.position.x, lead.position.z - a.position.z)).x)
			var info := _product(String(_buyer["product"]))
			_serve.label = "SERVE %s  1 %s  %s" % [String(a.display_name), String(info.get("unit", "UNIT")), "ON CREDIT" if bool(_buyer["credit"]) else "$%d" % int(info.get("price", 10))]
			_serve.use_reach = 2.4
			_show(_serve, lead.global_position.lerp(a.global_position, 0.35), true)     # nearer him than the man is, so E serves, not talks


## The lines under his standing, top right.
func _lines() -> void:
	if main._melee == null:
		return
	var out: Array = []
	var carry: Dictionary = book()["carry"]
	for k: String in carry:
		out.append("%d %s%s" % [int(carry[k]), String(_product(k).get("unit", "UNIT")), "" if int(carry[k]) == 1 else "S"])
	var debt: Dictionary = book()["debt"]
	if not debt.is_empty():
		out.append("OWES $%d  DAY %d" % [int(debt.get("amount", 0)), int(debt.get("due", 0)) + 1])
	if posted:
		out.append("POSTED UP   G")
	elif not carry.is_empty():
		out.append("G  POST UP    B  PUT IT DOWN")
	main._melee.hud.lines = out


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if main._talk.is_open() or main._travel.is_open() or main._mode != "play" or main._performing:
		return
	match (event as InputEventKey).physical_keycode:
		KEY_G:
			post(not posted)
		KEY_B:
			put_down()


# ------------------------------------------------------------ --do steps

## deal:give:product:n, deal:front, deal:pay, deal:dub, deal:post:1|0, deal:until:waiting|sold|nobody[:seconds],
## deal:serve, deal:down (B), deal:up, deal:day (the next day), deal:used:WHO:n, deal:state.
func step(bits: PackedStringArray) -> void:
	var what := bits[1] if bits.size() > 1 else "state"
	match what:
		"give":
			give(bits[2], int(bits[3]) if bits.size() > 3 else 1)
		"front":
			print("[shot] deal: front: %s" % front())
		"pay":
			print("[shot] deal: pay: %s" % pay())
		"dub":
			print("[shot] deal: dub: %s" % dub())
		"post":
			print("[shot] deal: post: %s" % post(bits.size() < 3 or bits[2] == "1"))
		"serve":
			var ok := serve()
			print("[shot] deal: serve: %s %s" % [ok, last if ok else ""])
		"down":
			print("[shot] deal: put down: %s" % put_down())
		"up":
			print("[shot] deal: pick up: %s" % pick_up())
		"day":
			main._day += 1
			await get_tree().process_frame
		"used":
			Street.person(main._state, bits[2].to_lower())["used"] = int(bits[3]) if bits.size() > 3 else 3
			_arrive()
		"until":
			var want := bits[2] if bits.size() > 2 else "waiting"
			var most := int(float(bits[3]) * 60.0) if bits.size() > 3 else 1800
			var sold_was := _sold()
			var n := 0
			while n < most and not _is(want, sold_was):
				await get_tree().process_frame
				n += 1
			var who := String((_buyer["p"] as RefCounted).actor.display_name) if not _buyer.is_empty() else "-"
			print("[shot] deal: until %s: %s after %.1f s (%s, %s)" % [want, "yes" if _is(want, sold_was) else "NO", n / 60.0, who, String(_buyer.get("stage", "-"))])
		_:
			print("[shot] deal: %s" % _state_line())


func _sold() -> int:
	var n := 0
	for k: String in book()["sold"]:
		n += int(book()["sold"][k])
	return n


func _is(want: String, sold_was: int) -> bool:
	match want:
		"waiting":
			return not _buyer.is_empty() and String(_buyer["stage"]) == "waiting"
		"sold":
			return _sold() > sold_was
		_:
			return _buyer.is_empty()


func _state_line() -> String:
	var s := book()
	if _front.visible:
		print("[shot] deal: the front is at %.2f, %.2f: %s" % [_front.global_position.x, _front.global_position.z, _front.label])
	if _tapes.visible:
		print("[shot] deal: tapes are at %.2f, %.2f: %s" % [_tapes.global_position.x, _tapes.global_position.z, _tapes.label])
	return "carrying %s; pack down here %s; owes %s; sold %s; fronts paid %d; posted %s; buyer %s; charges %s; cash %d; respect %d, heat %d, trust %d" % [s["carry"],
		(s["stash"] as Dictionary).get(main._place, "none"), s["debt"] if not (s["debt"] as Dictionary).is_empty() else "nothing", s["sold"], int(s.get("fronts_paid", 0)), posted,
		"%s (%s)" % [(_buyer["p"] as RefCounted).actor.display_name, _buyer["stage"]] if not _buyer.is_empty() else "nobody", s["charges"],
		int(main._state.cash), Street.value(main._state, "respect"), Street.value(main._state, "heat"), Street.value(main._state, "trust")]
