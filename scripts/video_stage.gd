extends Node3D
## The set of a music video, put out at its location (video.json's "location"
## row): his mark, the entourage behind him in matching clothes, the cars that
## were paid for, Large Fry with the camcorder (the camera crew of one), a
## light on a stand, the smoke machine, the bling on the lead; and what happens
## on it: bills thrown, smoke, the police car going by, a car alarm, Miss Bea's
## slipper, the chain coming off, words said over people's heads.
## video_take.gd runs it; nothing here keeps score.
##
## A location gives "place" (an id of main.gd's PLACES) and "mark" (x, z on the
## floor); optionally "camera" (from the mark: x, height, z), "crew" (where the
## entourage stands, from the mark: x, z each), "cars" (from the mark: x, z, yaw
## each), "car_areas" (more floor the cars may stand on besides where people
## walk, such as the road: x0, z0, x1, z1 each), "police" (the z of the line
## the police car drives along, left to right), "police_stop" (how far right of
## him it pulls up) and "setup" (where the camera starts, behind Large Fry: how
## far back, how far to his left, how high). What is left out is taken from
## DEFAULT (and video.json's "take").
##
## Hard (`style`, set before build): the entourage is not the "crew" row in
## matching clothes with happy faces: video_crew.gd places them in depth bands
## from the location's floor, dresses each in their own dark clothes (video.json
## "hard"'s "wear") and gives each a watchful face and a way of standing.

const PaperActor := preload("res://scripts/paper_actor.gd")
const Crew := preload("res://scripts/video_crew.gd")
const Props := preload("res://scripts/video_props.gd")
const Street := preload("res://scripts/props_street.gd")
const PROP_SHADER := preload("res://shaders/paper_prop.gdshader")
const FONT := preload("res://assets/fonts/Bungee-Regular.ttf")
const BLING := "res://assets/video/"

const DEFAULT := {
	"camera": [0.7, 1.5, 6.2],
	"crew": [[-1.1, -0.8], [1.1, -0.8], [-2.2, -1.2], [2.2, -1.2], [0.0, -1.5], [-3.3, -0.8]],
	"cars": [[-3.9, 2.0, 70], [3.9, 2.0, 290], [-6.4, 0.4, 90]],
}
const GRAVITY := 9.8
const BILL_FALL := 2.2           # bills fall this fast at most, fluttering
const BUBBLE_LIFT := 0.35        # words said float this far over a head

var main: Node3D
var lead: Node3D
var mark := Vector3.ZERO         # where he stands
var lens := Vector3.ZERO         # the camcorder on Large Fry's shoulder
var police_z := INF
var police_stop := 3.4           # how far to his right the police car pulls up (its middle), so it does not hide him
var crew: Array = []           # the entourage, paper actors
var spots: Array = []            # where each of them stands
var op: Node3D                   # Large Fry
var cars: Array = []             # each {"node", "rect", "lamps" (materials), "wobble", "alarm"}
var obstacles: Array = []        # the place's props, the cars and the smoke machine
var low: Array = []              # those of them too low to hide him from the camera (the smoke machine)
var smoke := false
var smoke_level := 0.0           # 0 the low smoke round his feet .. 1 it has got out of hand
var smoke_want := 0.0
var chain_on := true             # the chain is round his neck
var style := "clean"             # "clean" or "hard" (set before build)
var seed_value := 0              # the take's seed (set before build): where the hard crew stand
var hard_crew: RefCounted        # hard: video_crew.gd, how each of the entourage stands
var hard_wear := {}              # hard: video.json "hard"'s "wear" (set before build)
var drift := 2.4                 # how far Large Fry pans each way (video.json "take"'s "drift"): nobody stands on that line

var _police: Node3D
var _police_bar: Array = []
var _police_glow: OmniLight3D    # its lights on everything round it, red then blue
var _police_back: Node3D         # over its boot, the end nearest him: where what it says goes
var _siren := {}                 # its siren's bubble (one of _bubbles) while it is here
var _police_x := 0.0
var _police_speed := 0.0
var _police_stop := INF          # where it pulls up (x); INF: it drives on
var _police_time := 0.0
var _puffs: Array = []           # {"node", "at", "phase"}
var _bills: Array = []           # {"node", "vel", "spin", "rest"}
var _bill_look: Material
var _bubbles: Array = []         # {"label", "until", "on" (a node to follow, or null), "at"}
var _bling: Node3D
var _pieces := {}                # bling piece: {"front": [cards], "side": [cards]}
var _chain_y := {}               # each chain card: where it sits on him
var _chain_t := -1.0             # the chain coming off: 0 .. 1 it has slid to his feet
var _chain_lost: Node3D          # the chain left lying on the ground
var _slipper: Node3D
var _slipper_t := -1.0
var _slipper_from := Vector3.ZERO
var _slipper_to := Vector3.ZERO
var _light: OmniLight3D
var _camcorder: Node3D           # on Large Fry's shoulder (it stays put as his card turns to the camera)
var _clock := 0.0


## Put the set out. `got` is the choice picked in each row (video_score.gd's chosen).
func build(main_node: Node3D, got: Dictionary) -> void:
	main = main_node
	lead = main._actor
	var loc: Dictionary = got["location"]
	mark = Vector3(float(loc["mark"][0]), 0.0, float(loc["mark"][1]))
	var cam: Array = loc.get("camera", DEFAULT["camera"])
	lens = Vector3(mark.x + float(cam[0]), float(cam[1]), mark.z + float(cam[2]))
	police_z = float(loc.get("police", mark.z + float(cam[2]) * 0.5))
	police_stop = float(loc.get("police_stop", police_stop))
	obstacles = (main._building.obstacles as Array).duplicate()
	var areas: Array = main._building.walk_areas()

	# The cars that were paid for, where the location parks them.
	var parks: Array = loc.get("cars", DEFAULT["cars"])
	var bought: Array = got["cars"].get("cars", [])
	var floor_for_cars := areas.duplicate()          # where people walk, and the road if the location gives it
	for r: Array in loc.get("car_areas", []):
		floor_for_cars.append(Rect2(float(r[0]), float(r[1]), float(r[2]) - float(r[0]), float(r[3]) - float(r[1])))
	for i in mini(bought.size(), parks.size()):
		var spec: Dictionary = bought[i]
		var at := mark + Vector3(float(parks[i][0]), 0.0, float(parks[i][1]))
		_park(at, float(parks[i][2]), String(spec.get("kind", "box_sedan")), Color(String(spec.get("paint", "#888888"))), floor_for_cars)
	_check_police_way()

	# The smoke machine, at his feet off to one side (in front of the line he
	# walks along to keep in the picture), and the low smoke.
	smoke = got["smoke"].get("smoke", false)
	if smoke:
		var at := mark + Vector3(1.0, 0.0, 0.85)
		Props.smoke_machine(self, at, -125.0)
		obstacles.append(Rect2(at.x - 0.25, at.z - 0.25, 0.5, 0.5))
		low.append(obstacles[-1])
		var soft := Props.soft_texture()
		for k in 12:
			var a := TAU * k / 12.0
			var spot := mark + Vector3(cos(a) * (0.7 + 0.5 * (k % 3)), 0.0, sin(a) * (0.45 + 0.3 * (k % 2)))
			_puffs.append({"node": Props.puff(self, soft), "at": spot, "phase": k * 0.7})

	# Large Fry, where the camera is, facing the lead; the camcorder on his shoulder.
	op = PaperActor.new()
	op.name = "LargeFry"
	add_child(op)
	op.set_rig(main._rig_dir("fry"))
	op.display_name = "LARGE FRY"
	op.reach = 0.5
	op.position = Vector3(lens.x, 0.0, lens.z)
	op.areas = [Rect2(-999, -999, 1998, 1998)]
	op.face_way("back")
	for i in 90:                     # he turns his back to us (a turn takes a moment)
		op.walk(Vector2.ZERO, Vector2.ZERO, 1.0 / 60.0)
	var toward := Vector2(mark.x - lens.x, mark.z - lens.z).normalized()
	var side := Vector2(-toward.y, toward.x)
	var shoulder := op.position + Vector3(toward.x * 0.1 - side.x * 0.24, 1.47, toward.y * 0.1 - side.y * 0.24)
	_camcorder = Props.camcorder(self, shoulder, rad_to_deg(atan2(toward.x, toward.y)))

	# The entourage, in what the plan dressed them in, standing behind him.
	var who: Array = got["entourage"].get("who", [])
	var places: Array = loc.get("crew", DEFAULT["crew"])
	var outfit: Dictionary = got["entourage"].get("outfit", {})
	for i in mini(who.size(), places.size()):
		var npc: Node3D = PaperActor.new()
		npc.name = String(who[i]).capitalize()
		add_child(npc)
		npc.set_rig(main._rig_dir(String(who[i])))
		if style == "hard":
			Crew.dress(main, npc, String(who[i]), hard_wear)
		elif npc.has_wardrobe() and not outfit.is_empty():
			npc.wear(main._outfit_of(outfit))
		npc.speed = 1.5
		npc.areas = floor_for_cars       # the road is closed for the shoot: they may walk out into it
		npc.obstacles = obstacles
		npc.position = _clear_spot(npc, mark + Vector3(float(places[i][0]), 0.0, float(places[i][1])))
		npc.performing = style != "hard"
		if npc.face and style != "hard":
			npc.face.set_expression("happy", true)
		crew.append(npc)
		spots.append(npc.position)
	for npc: Node3D in crew:
		npc.others = [lead, op] + crew.filter(func(o: Node3D) -> bool: return o != npc)
	op.others = [lead] + crew

	# The lead on his mark, round whatever is in the way.
	lead.obstacles = obstacles
	lead.areas = areas
	lead.others = crew + [op]
	lead.position = _clear_spot(lead, mark)
	mark = lead.position

	# Hard: the entourage in depth bands round him, each standing their own way.
	if style == "hard" and not crew.is_empty():
		hard_crew = Crew.new()
		hard_crew.place(self, crew, seed_value, drift)
		spots = crew.map(func(npc: Node3D) -> Vector3: return npc.position)

	# A light on the set, by the camera, so the cars and props are seen at night.
	_light = Kit.omni(self, Vector3(lens.x - 0.6, 2.6, lens.z - 0.4), Color(1.0, 0.94, 0.86), 1.4, 14.0)

	_dress_lead(got["bling"].get("wear", []))
	_bill_look = Props.bill_look()


## The floor a car takes (x, z), turned to `yaw`.
static func car_rect(at: Vector3, yaw: float, kind: String) -> Rect2:
	var c: Array = Street.CAR_KINDS[kind]
	var l: float = c[0]
	var w: float = c[1]
	var a := deg_to_rad(yaw)
	var half := Vector2(absf(sin(a)) * l + absf(cos(a)) * w, absf(cos(a)) * l + absf(sin(a)) * w) * 0.5
	return Rect2(at.x - half.x, at.z - half.y, half.x * 2.0, half.y * 2.0)


## Can a car stand on `rect`: on the place's floor, clear of its props and the
## other cars, not on top of him or the camera, not between them?
func _car_fits(rect: Rect2, areas: Array) -> bool:
	for corner: Vector2 in [rect.position, rect.end, Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y)]:
		var inside := false
		for area: Rect2 in areas:
			if area.grow(0.05).has_point(corner):
				inside = true
		if not inside:
			return false
	for other: Rect2 in obstacles:
		if other.intersects(rect.grow(0.08)):
			return false
	var him := Vector2(mark.x, mark.z)
	var cam := Vector2(lens.x, lens.z)
	if rect.grow(1.1).has_point(him) or rect.grow(1.3).has_point(cam):
		return false
	var wide := rect.grow(0.45)
	for k in 21:                     # the line from the camera to him
		if wide.has_point(cam.lerp(him, k / 20.0)):
			return false
	return true


## A car where the location parks it, or the nearest place to that it fits:
## solid, and kept to hand for its alarm. Left out (and said) if it fits nowhere near.
func _park(want: Vector3, yaw: float, kind: String, paint: Color, areas: Array) -> void:
	var at := want
	var rect := car_rect(at, yaw, kind)
	var found := _car_fits(rect, areas)
	for ring in range(1, 15):
		if found:
			break
		for k in 16:
			var p := want + Vector3(cos(TAU * k / 16.0), 0.0, sin(TAU * k / 16.0)) * ring * 0.3
			rect = car_rect(p, yaw, kind)
			if _car_fits(rect, areas):
				at = p
				found = true
				break
	if not found:
		print("[shot] video: no room for a car near %.1f, %.1f: left out" % [want.x, want.z])
		return
	if at != want:
		print("[shot] video: a car moved from %.1f, %.1f to %.1f, %.1f to clear the props" % [want.x, want.z, at.x, at.z])
	var node := Street.car_model(self, at, yaw, kind, paint)
	var c: Array = Street.CAR_KINDS[kind]
	var l: float = c[0]
	var w: float = c[1]
	obstacles.append(rect)
	# Its alarm: an orange lamp over each head lamp and tail lamp, off until it goes.
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color(1.0, 0.6, 0.15)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.55, 0.1)
	lamp.emission_energy_multiplier = 2.5
	var flash := Kit.group(node, Vector3.ZERO, Vector3.ZERO, "Alarm")
	var top := 0.3 + float(c[2])
	var nose := l * 0.5 + 0.006
	for x: float in [-w * 0.5 + 0.3, w * 0.5 - 0.3]:
		Kit.box(flash, Vector3(0.31, 0.15, 0.008), Vector3(x, top - float(c[2]) * 0.42, nose + 0.016), lamp)
		Kit.box(flash, Vector3(0.33, 0.15, 0.008), Vector3(x, top - float(c[2]) * 0.35, -nose - 0.016), lamp)
	flash.visible = false
	cars.append({"node": node, "rect": rect, "flash": flash, "wobble": 0.0, "alarm": false, "yaw": yaw})


## Say if the police car's way (left to right along "police") runs into a prop
## of the place or a car of the video (it does not stop for them).
func _check_police_way() -> void:
	var x := mark.x - 14.0
	while x <= mark.x + 22.0:
		var rect := car_rect(Vector3(x, 0.0, police_z), 90.0, "box_sedan")
		for other: Rect2 in obstacles:
			if other.intersects(rect):
				print("[shot] video: the police car's way at z %.1f runs into something at %s (x %.1f)" % [police_z, other, x])
				return
		x += 0.5


## The nearest spot to `want` where `who` can stand, clear of the props and of the people already placed.
func _clear_spot(who: Node3D, want: Vector3) -> Vector3:
	var placed: Array = crew.duplicate()
	if op and who != op:
		placed.append(op)
	var ok := func(p: Vector2) -> bool:
		if not who.can_stand(p):
			return false
		for other: Node3D in placed:
			if other != who and Vector2(other.position.x, other.position.z).distance_to(p) < 0.62:
				return false
		return true
	var at := Vector2(want.x, want.z)
	if ok.call(at):
		return want
	for ring in range(1, 16):
		for k in 16:
			var p := at + Vector2.from_angle(TAU * k / 16.0) * ring * 0.1
			if ok.call(p):
				return Vector3(p.x, 0.0, p.y)
	print("[shot] video: no clear spot near %.1f, %.1f for %s" % [want.x, want.z, who.name])
	return want


# ------------------------------------------------------------------ the bling

## Put the bling on him: "chain", "shades", "studs" (assets/video/bling.json says
## where each goes on each drawing, in pixels of that drawing).
func _dress_lead(wear: Array) -> void:
	_bling = Node3D.new()
	_bling.name = "Bling"
	lead._card.add_child(_bling)
	var info = JSON.parse_string(FileAccess.get_file_as_string(BLING + "bling.json")) if FileAccess.file_exists(BLING + "bling.json") else null
	if typeof(info) != TYPE_DICTIONARY:
		return
	var px := Vector2(1010, 1488)
	var body: Texture2D = lead._views.get("front", {}).get("art", null)
	if body:
		px = Vector2(body.get_size())
	var metre: float = lead.height / px.y
	for piece: String in wear:
		if not info.has(piece):
			continue
		_pieces[piece] = {}
		for way: String in ["front", "side"]:
			var cards: Array = []
			for part: Dictionary in info[piece].get(way, []):
				var r: Array = part["rect"]
				var card := MeshInstance3D.new()
				var quad := QuadMesh.new()
				quad.size = Vector2(float(r[2]), float(r[3])) * metre
				card.mesh = quad
				var mat := ShaderMaterial.new()
				mat.shader = PROP_SHADER
				mat.set_shader_parameter("art", load(BLING + String(part["file"])))
				mat.set_shader_parameter("toward", 0.026)
				card.material_override = mat
				card.position = Vector3((float(r[0]) + float(r[2]) * 0.5 - px.x * 0.5) * metre, (px.y - float(r[1]) - float(r[3]) * 0.5) * metre, 0.0)
				_bling.add_child(card)
				cards.append(card)
				if piece == "chain":
					_chain_y[card] = card.position.y
			_pieces[piece][way] = cards


func has_bling(piece: String) -> bool:
	return _pieces.has(piece)


## Show the bling that goes with the drawing he has on show.
func _show_bling() -> void:
	for piece: String in _pieces:
		for way: String in _pieces[piece]:
			for card: MeshInstance3D in _pieces[piece][way]:
				card.visible = lead.view == way and (piece != "chain" or chain_on or _chain_t >= 0.0)


## The chain slides off him (the chain mishap).
func chain_fall() -> void:
	if not _pieces.has("chain") or not chain_on:
		return
	chain_on = false
	_chain_t = 0.0


## Caught before it is gone: it goes back on.
func chain_catch() -> void:
	if _chain_t < 0.0:
		return
	_chain_t = -1.0
	chain_on = true
	for card: MeshInstance3D in _chain_y:
		card.position.y = _chain_y[card]


## Left on the ground: a copy of it lies at his feet; he goes on without it.
func chain_drop() -> void:
	if _chain_t < 0.0:
		return
	_chain_t = -1.0
	var art: Texture2D = null
	for card: MeshInstance3D in _chain_y:
		card.position.y = _chain_y[card]
		art = (card.material_override as ShaderMaterial).get_shader_parameter("art")
	if art == null:
		return
	_chain_lost = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.24, 0.36)
	_chain_lost.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = art
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_chain_lost.material_override = mat
	add_child(_chain_lost)
	_chain_lost.position = lead.position + Vector3(0.12, 0.012, 0.2)
	_chain_lost.rotation = Vector3(-PI * 0.5, 0.6, 0.0)


# -------------------------------------------------------------- what happens

## Throw `n` bills at the camera from his raised hand.
func throw_cash(n: int, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var right: Vector3 = main._camera.global_transform.basis.x
	right.y = 0.0
	var hand := lead.position + right.normalized() * 0.35 + Vector3(0.0, 1.55, 0.0)
	var to_cam := (lens - hand).normalized()
	for i in n:
		var node := Props.bill(self, _bill_look)
		node.position = hand + Vector3(rng.randf_range(-0.08, 0.08), rng.randf_range(-0.05, 0.08), 0.0)
		var vel := to_cam * rng.randf_range(1.6, 3.0) + Vector3(rng.randf_range(-1.2, 1.2), rng.randf_range(1.2, 2.6), rng.randf_range(-0.4, 0.4))
		_bills.append({"node": node, "vel": vel, "spin": Vector3(rng.randf_range(-9, 9), rng.randf_range(-6, 6), rng.randf_range(-9, 9)), "rest": false, "lie": 0.012 + 0.001 * i})


## How much smoke there is: 0 the low smoke, 1 the whole frame.
func set_smoke(level: float) -> void:
	smoke_want = level


## The police car comes in from the left and pulls up level with him (stop
## true) or drives straight through, `siren` over it until it goes.
func police_in(stop: bool, siren := "") -> void:
	if _police == null:
		_police_bar = []
		_police = Props.police_car(self, Vector3.ZERO, 90.0, _police_bar)
		_police_glow = Kit.omni(_police, Vector3(0.0, 1.75, -0.28), Color.RED, 6.0, 12.0)
		_police_back = Node3D.new()
		_police_back.position = Vector3(0.0, 0.0, -float(Street.CAR_KINDS["box_sedan"][0]) * 0.5 + 0.7)
		_police.add_child(_police_back)
	_police_x = mark.x - 14.0
	_police_speed = 8.0
	_police_stop = mark.x + police_stop if stop else INF
	_police.position = Vector3(_police_x, 0.0, police_z)
	_police.visible = true
	_police_time = 0.0
	if siren != "":
		say(_police_back, siren, 60.0, Color("#8fb4ff"))
		_siren = _bubbles[-1]


## It drives on and away (and the siren stops).
func police_go() -> void:
	_police_stop = INF
	if _bubbles.has(_siren):
		(_siren["label"] as Label3D).queue_free()
		_bubbles.erase(_siren)
	_siren = {}


## Where the police car's words go: over its back end, the end nearest him
## (on a street set most of it is off the side of the picture).
func police_car() -> Node3D:
	return _police_back


## Seconds until the police car has pulled up, from where it is now.
func police_eta() -> float:
	if _police == null or _police_stop == INF:
		return 0.0
	return maxf(_police_stop - _police_x, 0.0) / 6.5


## A car's alarm going (on) or stopping.
func alarm(i: int, on: bool) -> void:
	if i < 0 or i >= cars.size():
		return
	cars[i]["alarm"] = on
	if not on:
		cars[i]["flash"].visible = false


## Somebody gives the car a kick: it rocks.
func kick(i: int) -> void:
	if i >= 0 and i < cars.size():
		cars[i]["wobble"] = 1.0


## A slipper comes flying in from off the left of the picture at his head (or,
## `short`, lands at his feet).
func slipper_throw(from: Vector3, short := false) -> void:
	if _slipper == null:
		_slipper = Props.slipper(self)
	_slipper_from = from
	_slipper_to = lead.position + (Vector3(-0.5, 0.05, 0.35) if short else Vector3(0.0, lead.height * 0.86, 0.0))
	_slipper.position = from
	_slipper.visible = true
	_slipper_t = 0.0


## Words over someone's head (or over a spot, if `on` is not a node) for `seconds`.
func say(on: Variant, words: String, seconds: float, colour := Color("#f6f1e3")) -> void:
	if words == "":
		return
	if on is Node3D:                 # one bubble each: a new line replaces the last (BONK over WEE-OO)
		for old: Dictionary in _bubbles.duplicate():
			if old["on"] == on:
				(old["label"] as Label3D).queue_free()
				_bubbles.erase(old)
	var label := Label3D.new()
	label.text = words
	label.font = FONT
	label.font_size = 64
	label.fixed_size = true          # as easy to read over the police car down the street as over him
	label.pixel_size = 0.0005
	label.outline_size = 18
	label.modulate = colour
	label.outline_modulate = Color.BLACK
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	add_child(label)
	var at: Vector3 = on if on is Vector3 else Vector3.ZERO
	_bubbles.append({"label": label, "until": _clock + seconds, "on": on if on is Node3D else null, "at": at})
	_place_bubbles()


## Each bubble over whoever said it; one whose speaker is off the side of the
## picture (a car alarm, the police car on a street) is pulled in to its edge.
func _place_bubbles() -> void:
	var cam: Camera3D = main._camera
	var size: Vector2 = main.get_viewport().get_visible_rect().size
	for b: Dictionary in _bubbles:
		var on: Node3D = b["on"]
		var at: Vector3 = b["at"]
		if on and is_instance_valid(on):
			at = on.global_position + Vector3(0.0, (on.height if "height" in on else 1.6) + BUBBLE_LIFT, 0.0)
		var depth := -(cam.global_transform.affine_inverse() * at).z
		if depth > 0.5:
			var spot := cam.unproject_position(at)
			var inside := Vector2(clampf(spot.x, size.x * 0.17, size.x * 0.83), clampf(spot.y, size.y * 0.33, size.y * 0.8))
			if inside != spot:
				at = cam.project_position(inside, depth)
		(b["label"] as Label3D).position = at


# --------------------------------------------------------------------- moving

func tick(delta: float) -> void:
	_clock += delta
	op.walk(Vector2.ZERO, Vector2.ZERO, delta)
	_show_bling()
	# The chain sliding down him.
	if _chain_t >= 0.0:
		_chain_t = minf(_chain_t + delta / 0.9, 1.0)
		for card: MeshInstance3D in _chain_y:
			card.position.y = lerpf(_chain_y[card], 0.16, _chain_t * _chain_t)
	# Bills flutter down and stay where they land.
	for b: Dictionary in _bills:
		if b["rest"]:
			continue
		var node: MeshInstance3D = b["node"]
		var vel: Vector3 = b["vel"]
		vel.y -= GRAVITY * 0.55 * delta
		vel.y = maxf(vel.y, -BILL_FALL)
		vel.x *= 1.0 - 1.4 * delta
		vel.z *= 1.0 - 1.4 * delta
		b["vel"] = vel
		node.position += vel * delta
		node.rotation += (b["spin"] as Vector3) * delta
		if node.position.y <= 0.012:
			node.position.y = float(b["lie"])
			node.rotation = Vector3(-PI * 0.5, node.rotation.y, 0.0)
			b["rest"] = true
	# The smoke: low and slow round his feet, or everywhere.
	smoke_level = move_toward(smoke_level, smoke_want, delta * (1.6 if smoke_want > smoke_level else 0.7))
	for p: Dictionary in _puffs:
		var node: MeshInstance3D = p["node"]
		var at: Vector3 = p["at"]
		var ph: float = p["phase"]
		var big := smoke_level
		var drift := Vector3(sin(_clock * 0.4 + ph) * 0.3, 0.0, cos(_clock * 0.3 + ph) * 0.2)
		var toward_lens := (lens - at) * 0.45 * big
		node.position = at + drift + toward_lens + Vector3(0.0, lerpf(0.22, 1.1, big) + 0.05 * sin(_clock + ph), 0.0)
		var s := lerpf(0.9 + 0.2 * sin(_clock * 0.8 + ph), 3.2, big)
		node.scale = Vector3(s, s, s)
		(node.material_override as StandardMaterial3D).albedo_color.a = lerpf(0.32, 0.62, big)
	# The police car: in, pulled up, on and away; its lights going.
	if _police and _police.visible:
		_police_time += delta
		if _police_stop < INF:
			var left := _police_stop - _police_x
			_police_speed = minf(8.0, maxf(left * 2.5, 0.0))
		else:
			_police_speed = minf(_police_speed + delta * 3.0, 7.0)
		_police_x += _police_speed * delta
		_police.position = Vector3(_police_x, 0.0, police_z)
		var on := int(_police_time * 6.0) % 2 == 0
		(_police_bar[0] as StandardMaterial3D).emission_energy_multiplier = 3.0 if on else 0.0
		(_police_bar[1] as StandardMaterial3D).emission_energy_multiplier = 0.0 if on else 3.0
		_police_glow.light_color = Color(1.0, 0.15, 0.1) if on else Color(0.2, 0.35, 1.0)
		if _police_stop == INF and _police_x > mark.x + 22.0:
			_police.visible = false
	# Car alarms flash; a kicked car rocks.
	for c: Dictionary in cars:
		if c["alarm"]:
			(c["flash"] as Node3D).visible = int(_clock * 5.0) % 2 == 0
		var wob: float = c["wobble"]
		if wob > 0.0:
			c["wobble"] = maxf(wob - delta * 1.8, 0.0)
		var node: Node3D = c["node"]
		node.rotation = Vector3(0.0, deg_to_rad(float(c["yaw"])), 0.05 * wob * sin(_clock * 30.0) + (0.012 * sin(_clock * 40.0) if c["alarm"] else 0.0))
	# The slipper.
	if _slipper_t >= 0.0 and _slipper:
		_slipper_t += delta / 0.55
		if _slipper_t < 1.0:
			var p := _slipper_from.lerp(_slipper_to, _slipper_t)
			p.y += sin(PI * _slipper_t) * 0.9
			_slipper.position = p
			_slipper.rotation = Vector3(_slipper_t * 9.0, _slipper_t * 4.0, 0.0)
		else:
			var fall := minf((_slipper_t - 1.0) * 0.55 / 0.5, 1.0)
			_slipper.position = _slipper_to.lerp(lead.position + Vector3(0.45, 0.02, 0.3), fall)
			_slipper.position.y = lerpf(_slipper_to.y, 0.02, fall * fall)
			_slipper.rotation = Vector3(0.0, 0.7, 0.0) if fall >= 1.0 else Vector3(fall * 6.0, 1.0, 0.0)
	# Words said, and gone when their time is up.
	for b: Dictionary in _bubbles.duplicate():
		if _clock >= float(b["until"]):
			(b["label"] as Label3D).queue_free()
			_bubbles.erase(b)
	_place_bubbles()


## Large Fry and his camcorder seen, or not (the camera is on his shoulder).
func show_op(on: bool) -> void:
	op.visible = on
	_camcorder.visible = on


## Turn every card on the set to face the camera.
func face_cards(camera: Camera3D) -> void:
	var back := camera.global_transform.basis.z
	var yaw := atan2(back.x, back.z)
	for who: Node3D in crew + [op]:
		who.rotation.y = yaw


## Take the set down: the bling comes off him and everything here goes.
func teardown() -> void:
	if _bling and is_instance_valid(_bling):
		_bling.queue_free()
	_bling = null
	queue_free()
