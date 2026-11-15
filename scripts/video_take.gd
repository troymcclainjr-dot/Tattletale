extends Node
## One take of a music video, from QUIET ON SET to CUT. It runs on the beat he
## performs to at the microphone (paper_actor.gd's BEAT) and is driven by
## `tick`, so a --do step can run it at any speed and stop it at any moment.
##
## The song is four sections (video.json's "take": "sections"); each "x" of a
## section's pattern is a beat on which a move is asked for. It comes in along
## the lane and is pressed as it reaches the ring: within "timing"'s "perfect"
## seconds is PERFECT, within "good" is GOOD, later is a MISS, and a move key
## pressed with nothing due is OFF BEAT. The moves are video.json's "moves":
## each has its key (W, A, S or D; two moves can share one), a face, how his
## arms go ([left, right, left bow, right bow], radians: see
## paper_card.gdshader's arm_*_angle) and how far he leans; one that "needs"
## something (the chain, cash to throw, a weapon) is only asked for while he
## has it. The entourage do each move he lands after him, and look lost when he
## misses.
##
## Large Fry pans the camera now and then ("drift"; never while a mishap is on,
## never further than he can walk); he has to walk along his line (the left and
## right arrows) to stay inside the brackets ("frame"), or what he does counts for
## half and polish drains away. Two or three mishaps happen ("mishaps"; each video.json
## "mishaps" row that "needs" what this video has can): each comes on, then
## asks for E for "answer_beats" beats. Answering is the "answer" outcome, not
## answering the "miss" one: what each takes off polish and adds to chaos, and
## the line said. What each mishap does on the set is its "effect", in code
## below (_begin, _end): lens_hog, car_alarm, neighbour, police, smoke, chain_drop.
##
## At the end `kept` has what the premiere needs: swagger, polish, chaos, the
## mishaps and how each went, and the moments to show (each a still and a
## caption from video.json's "captions").

signal wrapped

const PaperActor := preload("res://scripts/paper_actor.gd")
const BEAT := PaperActor.BEAT
const MOODS := ["focused", "smug", "shout", "sly"]
const BASE_MOVES := ["point", "wide", "lean", "sign"]      # always to hand: what a move he can no longer do becomes
const SLOTS := [9.0, 24.0, 40.0, 53.0]       # beats into the song where a mishap may begin
const LEAD := {"lens_hog": 2.6, "car_alarm": 0.5, "neighbour": 1.2, "police": 3.4, "smoke": 1.0, "chain_drop": 0.5}
const PERFECT := Color("#f2d24a")
const GOOD := Color("#f6f1e3")
const MISS := Color("#e8392b")

var main: Node3D
var stage: Node3D
var ui: CanvasLayer
var data := {}
var got := {}                    # the choice picked in each row
var auto := -1.0                 # the skill of whoever plays it for a --do step, 0 .. 1; below 0, nobody: the keys
var hold_dir := Vector2.ZERO     # the direction held, on screen (the keys)
var time := 0.0                  # seconds since QUIET ON SET
var prompts: Array = []          # each {"beat", "move", "key", "name", "state" ("due", "hit", "miss"), "grade"}
var mishaps: Array = []          # each {"m" (its row), "start", "open", "close", "state", "handled", ...}
var in_shot := true
var kept := {}                   # once it is over
var stills: Array = []           # moments wanted, waiting to be caught: {"key", "beat"} (the shoot catches them)
var done := false

var _take := {}
var _moves := {}                 # id: its row
var _keys := {}                  # key: the ids of the moves on it, in video.json's order
var _rng := RandomNumberGenerator.new()
var _seed := 0
var _count_in := 4.0
var _song_end := 68.0
var _end := 72.0
var _good := 0.32
var _perfect := 0.14
var _points := 0.0
var _judged := 0
var _flubs := 0
var _polish := 100.0
var _chaos := 0.0
var _pan := 0.0
var _pan_from := 0.0
var _pan_to := 0.0
var _pan_start := -99.0
var _next_drift := 0.0
var _setup_at := Vector3.ZERO    # where the camera starts, behind Large Fry
var _setup_look := Vector3.ZERO
var _pose := {}                  # the move he is doing: {"move", "start"}
var _stopped := 0.0              # until this beat he has stopped performing (Miss Bea, the police)
var _turned := false             # he has turned to Miss Bea
var _gun_out := false            # pointing it at the lens while the police go by
var _throws := 0
var _crew: Array = []            # for each of the entourage: {"move", "start", "lost", "goal", "exit", "gone", "wave", "stuck"}
var _later: Array = []           # {"beat", "do"}: things that happen a little after something else
var _wished := {}                # moment keys asked for already
var _mood := ""
var _weapon := ""
var _fov := 40.0
var _section := ""
var _quarter := -1               # the auto player looks for an off-beat press once each quarter beat


## Ready a take: `forced` is a list of mishap ids to have instead of picking (for --do steps).
func setup(main_node: Node3D, stage_node: Node3D, ui_node: CanvasLayer, video: Dictionary, chosen: Dictionary, seed_value: int, forced: Array) -> void:
	main = main_node
	stage = stage_node
	ui = ui_node
	data = video
	got = chosen
	_seed = seed_value
	_rng.seed = seed_value
	_take = data["take"]
	_count_in = float(_take.get("count_in", 4))
	_good = float(_take["timing"]["good"])
	_perfect = float(_take["timing"]["perfect"])
	_fov = float(_take.get("fov", 40.0))
	_throws = int(got["rain"].get("throws", 0))
	_weapon = String(main._actor.weapon)
	for m: Dictionary in data["moves"]:
		_moves[m["id"]] = m
		if not _keys.has(String(m["key"])):
			_keys[String(m["key"])] = []
		(_keys[String(m["key"])] as Array).append(String(m["id"]))
	var beat := _count_in
	for section: Dictionary in _take["sections"]:
		var pattern := String(section["pattern"])
		for i in pattern.length():
			if pattern[i] == "x":
				var move := _pick_move()
				prompts.append({"beat": beat + i, "move": move, "key": String(_moves[move]["key"]), "name": String(_moves[move]["name"]), "state": "due", "grade": ""})
		beat += pattern.length()
	_song_end = beat
	_end = beat + float(_take.get("outro", 4))
	_pick_mishaps(forced)
	for _i in stage.crew.size():
		_crew.append({"move": {}, "start": 0.0, "lost": -99.0, "goal": null, "exit": false, "gone": false, "wave": false, "stuck": 0.0})
	# The camera starts behind Large Fry and a little to one side, and pushes in to his camcorder at ACTION.
	var toward: Vector3 = stage.mark - stage.lens
	toward.y = 0.0
	toward = toward.normalized()
	var side := Vector3(-toward.z, 0.0, toward.x)
	var back: Array = got["location"].get("setup", _take.get("setup", [3.4, 1.2, 2.25]))     # behind him, to his left, how high
	_setup_at = Vector3(stage.lens.x, 0.0, stage.lens.z) - toward * float(back[0]) - side * float(back[1]) + Vector3(0.0, float(back[2]), 0.0)
	_setup_look = stage.mark + Vector3(0.0, 0.95, 0.0)
	_next_drift = _count_in + float(_take["drift"]["every"])
	_wish("open", _count_in + 1.6)
	_wish("close", _song_end - 0.6)
	var lead: Node3D = main._actor
	lead.performing = true
	lead.sprinting = false
	lead.aiming = false
	lead.aim_way = ""
	lead.show_face()
	if lead.face:
		lead.face.set_expression("focused")
	_camera(0.0)


## A move for a prompt: any he can do now, not the same one twice running;
## the cash only while there is some left to throw.
func _pick_move(avoid := "") -> String:
	var can: Array = []
	for id: String in _moves:
		if _can_do(id) and id != avoid:
			can.append(id)
	if can.is_empty():
		return BASE_MOVES[0]
	var last := String(prompts[-1]["move"]) if not prompts.is_empty() else ""
	var pick := String(can[_rng.randi() % can.size()])
	if pick == last and can.size() > 1:
		pick = String(can[(can.find(pick) + 1) % can.size()])
	return pick


func _can_do(id: String) -> bool:
	var need := String(_moves[id].get("needs", ""))
	match need:
		"chain":
			return stage.has_bling("chain") and stage.chain_on
		"rain":
			return _throws > 0
		"weapon":
			return String(main._actor.weapon) != ""
	return true


## Two or three of the mishaps this video can have, at beats spread through the song.
func _pick_mishaps(forced: Array) -> void:
	var can: Array = []
	for m: Dictionary in data["mishaps"]:
		if _fits(String(m.get("needs", ""))):
			can.append(m)
	var chosen_rows: Array = []
	if not forced.is_empty():
		for id: String in forced:
			for m: Dictionary in data["mishaps"]:
				if String(m["id"]) == id:
					if _fits(String(m.get("needs", ""))):
						chosen_rows.append(m)
					else:
						print("[shot] video: mishap %s needs %s, which this video has not got" % [id, m.get("needs", "")])
	else:
		var range_n: Array = _take.get("mishaps", [2, 3])
		var n := _rng.randi_range(int(range_n[0]), int(range_n[1]))
		var pool := can.duplicate()
		while chosen_rows.size() < n and not pool.is_empty():
			var m: Dictionary = pool.pop_at(_rng.randi() % pool.size())
			var clash := false
			for other: Dictionary in chosen_rows:
				if other["effect"] == m["effect"]:
					clash = true
			if not clash:
				chosen_rows.append(m)
	var slots: Array = SLOTS.duplicate()
	if forced.is_empty():
		while slots.size() > chosen_rows.size():
			slots.remove_at(_rng.randi() % slots.size())
	var answer := float(_take.get("answer_beats", 3))
	for i in mini(chosen_rows.size(), slots.size()):
		var m: Dictionary = chosen_rows[i]
		var start: float = _count_in + float(slots[i])
		var open := start + float(LEAD.get(m["effect"], 1.0))
		mishaps.append({"m": m, "start": start, "open": open, "close": open + answer, "state": "coming", "handled": false})
		for p: Dictionary in prompts:
			if float(p["beat"]) >= start - 0.5 and float(p["beat"]) <= open + answer + 1.0:
				p["state"] = "gone"
	prompts = prompts.filter(func(p: Dictionary) -> bool: return p["state"] != "gone")


func _fits(need: String) -> bool:
	match need:
		"":
			return true
		"entourage":
			return not stage.crew.is_empty()
		"cars":
			return not stage.cars.is_empty()
		"weapon":
			return String(main._actor.weapon) != ""
		"no weapon":
			return String(main._actor.weapon) == ""
		"smoke":
			return stage.smoke
		"chain":
			return stage.has_bling("chain")
	return false


func beat() -> float:
	return time / BEAT


## A beat just after this mishap starts asking for E, before anyone could have
## answered (for --do steps), or -1.
func mishap_beat(id: String) -> float:
	for m: Dictionary in mishaps:
		if String(m["m"]["id"]) == id:
			return float(m["open"]) + 0.3
	return -1.0


## The beat of the next move still to come, or -1.
func next_prompt() -> float:
	for p: Dictionary in prompts:
		if p["state"] == "due" and float(p["beat"]) > beat():
			return float(p["beat"])
	return -1.0


func end_beat() -> float:
	return _end


# --------------------------------------------------------------------- input

## A key pressed during the take: a move's key (W, A, S, D), or E for a mishap.
## A key lands whichever of its moves is due nearest now; pressed with none due
## it is OFF BEAT, and he does its plain move (the one that needs nothing).
func press(key: String) -> void:
	if done:
		return
	var b := beat()
	if key == "E":
		for m: Dictionary in mishaps:
			if m["state"] == "asking":
				_end_mishap(m, true)
				return
		return
	if not _keys.has(key) or b < _count_in - 0.5 or b > _song_end + 0.5:
		return
	var best: Dictionary = {}
	var gap := INF
	for p: Dictionary in prompts:
		if p["state"] == "due" and p["key"] == key and _can_do(String(p["move"])):
			var d := absf(float(p["beat"]) * BEAT - time)
			if d < gap:
				gap = d
				best = p
	var words: Dictionary = data["words"]
	var id := String(best["move"]) if not best.is_empty() and gap <= _good else _plain(key)
	if id == "":
		return
	if not best.is_empty() and gap <= _good:
		var perfect := gap <= _perfect
		var value := 1.0 if perfect else 0.6
		if not in_shot:
			value *= 0.5
		best["state"] = "hit"
		best["grade"] = "perfect" if perfect else "good"
		_points += value
		_judged += 1
		ui.judge(String(words.get("perfect" if perfect else "good", "")), PERFECT if perfect else GOOD)
		_start_move(id)
		for i in _crew.size():
			_crew[i]["move"] = _moves[id]
			_crew[i]["start"] = b + 0.12 * (i + 1)
		if perfect and not _wished.has("move:" + id) and _count_wished("move:") < 3:
			_wish("move:" + id, b + 0.45)
	else:
		_flubs += 1
		_chaos += float(_take.get("flub_chaos", 1.0))
		ui.judge(String(words.get("flub", "OFF BEAT")), MISS)
		_start_move(id)


## What a key does pressed off the beat: its move that needs nothing (else the first of its moves he can do now).
func _plain(key: String) -> String:
	for id: String in _keys[key]:
		if not (_moves[id] as Dictionary).has("needs"):
			return id
	for id: String in _keys[key]:
		if _can_do(id):
			return id
	return ""


func _start_move(id: String) -> void:
	var lead: Node3D = main._actor
	var move: Dictionary = _moves[id]
	_pose = {"move": move, "start": beat()}
	if lead.face:
		lead.face.set_expression(String(move.get("face", "focused")))
	if id == "cash" and _throws > 0:
		_throws -= 1
		stage.throw_cash(6, _seed + _throws * 13)
		if _throws <= 0:
			_retire("cash")
	if id == "aim":
		lead.aiming = true
		lead.aim_way = "toward"


## A move he can no longer do: the ones still to come become others.
func _retire(id: String) -> void:
	for p: Dictionary in prompts:
		if p["state"] == "due" and p["move"] == id and float(p["beat"]) > beat() + 0.5:
			var other: String = BASE_MOVES[_rng.randi() % BASE_MOVES.size()]
			p["move"] = other
			p["key"] = String(_moves[other]["key"])
			p["name"] = String(_moves[other]["name"])


# ---------------------------------------------------------------------- tick

func tick(delta: float) -> void:
	if done:
		return
	time += delta
	var b := beat()
	_camera(delta)
	if auto >= 0.0:
		_auto_play(b)
	for later: Dictionary in _later.duplicate():
		if b >= float(later["beat"]):
			_later.erase(later)
			(later["do"] as Callable).call()
	_lead(b, delta)
	for p: Dictionary in prompts:
		if p["state"] == "due" and time > float(p["beat"]) * BEAT + _good:
			p["state"] = "miss"
			_judged += 1
			_chaos += float(_take.get("miss_chaos", 0.5))
			ui.judge(String(data["words"].get("miss", "MISS")), MISS)
			for c: Dictionary in _crew:
				c["lost"] = b
	_run_mishaps(b)
	_entourage(b, delta)
	stage.tick(delta)
	var song := b >= _count_in and b < _song_end
	in_shot = _framed()
	if song and not in_shot:
		_polish -= float(_take.get("out_of_shot", 2.0)) * delta / BEAT
	_show(b)
	if b >= _end:
		_finish()


## The camera: behind Large Fry during the count-in, pushing in to his
## camcorder at ACTION; during the song on his shoulder, panning now and then;
## pulling back out after CUT.
func _camera(_delta: float) -> void:
	var b := beat()
	var drift: Dictionary = _take["drift"]
	if b >= _next_drift and b < _song_end - 3.0 and _mishap_near(b):
		_next_drift = b + 1.0            # he holds it still while something is going on
	elif b >= _next_drift and b < _song_end - 3.0:
		_next_drift += float(drift["every"])
		var most := float(drift["metres"])
		var by: float = most * (0.5 if _rng.randf() < 0.5 else 1.0)      # half the way or all of it, never further than that from the mark
		var way := 1.0 if _rng.randf() < 0.5 else -1.0
		if absf(_pan_to + way * by) > most + 0.01:
			way = -way
		_pan_from = _pan
		_pan_to = _reachable(_pan_to + way * by)
		_pan_start = b
	elif b >= _song_end - 3.0 and _pan_to != 0.0:
		_pan_from = _pan
		_pan_to = 0.0
		_pan_start = b
	_pan = lerpf(_pan_from, _pan_to, smoothstep(0.0, 1.6, b - _pan_start))
	var k := smoothstep(2.4, 3.6, b) * (1.0 - smoothstep(_song_end + 1.0, _song_end + 2.4, b))
	var sway := Vector3(sin(time * 0.7) * 0.03, sin(time * 1.13) * 0.02, 0.0) * k
	var aim := Vector3(stage.mark.x + _pan, 1.0, stage.mark.z)
	var at := _setup_at.lerp(stage.lens + sway, k)
	var look := _setup_look.lerp(aim, k)
	var cam: Camera3D = main._camera
	cam.fov = lerpf(44.0, _fov, k)
	cam.look_at_from_position(at, look)
	stage.show_op(k < 0.55)          # once the camera is on his shoulder, he and his camcorder are out of the picture
	stage.face_cards(cam)
	main._face_cards()


## As far towards `pan` (metres along x from his mark) as he can walk along
## his line and still be seen: Large Fry never pans to where a hydrant keeps
## him out or a lamp post stands between him and the lens.
func _reachable(pan: float) -> float:
	var lead: Node3D = main._actor
	var step := 0.1 * signf(pan)
	var x := 0.0
	while step != 0.0 and absf(x + step) <= absf(pan) + 0.001:
		var spot := Vector2(stage.mark.x + x + step, stage.mark.z)
		if not lead.can_stand(spot) or not _seen(spot):
			break
		x += step
	return x


## Can `who` walk this way (a list of points on the floor) with no prop, no
## lead and nobody else of the entourage in it?
func _clear_way(who: Node3D, way: Array) -> bool:
	var at := Vector2(who.position.x, who.position.z)
	var lead: Node3D = main._actor
	for point: Vector3 in way:
		var to := Vector2(point.x, point.z)
		var n := maxi(int(ceil(at.distance_to(to) / 0.15)), 1)
		for i in range(1, n + 1):
			var p := at.lerp(to, float(i) / n)
			if not who.can_stand(p):
				return false
			for other: Node3D in [lead] + stage.crew:
				if other != who and Vector2(other.position.x, other.position.z).distance_to(p) < 0.56:
					return false
		at = to
	return true


## Nothing tall between the lens and this spot on the floor.
func _seen(at: Vector2) -> bool:
	var from := Vector2(stage.lens.x, stage.lens.z)
	for k in range(1, 19):
		var p := from.lerp(at, k / 20.0)
		for prop: Rect2 in stage.obstacles:
			if not stage.low.has(prop) and prop.grow(0.12).has_point(p):
				return false
	return true


## Is a mishap about to come on, on, or only just over? Large Fry does not pan then.
func _mishap_near(b: float) -> bool:
	for m: Dictionary in mishaps:
		if b >= float(m["start"]) - 2.0 and b <= float(m["close"]) + 2.0:
			return true
	return false


## Is he inside the brackets?
func _framed() -> bool:
	var cam: Camera3D = main._camera
	var lead: Node3D = main._actor
	var chest := lead.global_position + Vector3(0.0, lead.height * 0.55, 0.0)
	if cam.is_position_behind(chest):
		return false
	var width := main.get_viewport().get_visible_rect().size.x
	var sx := cam.unproject_position(chest).x / maxf(width, 1.0)
	return absf(sx - 0.5) < float(_take.get("frame", 0.24))


func aim_x() -> float:
	return stage.mark.x + _pan


func _lead(b: float, delta: float) -> void:
	var lead: Node3D = main._actor
	var dir := Vector2(signf(hold_dir.x), 0.0) if absf(hold_dir.x) > 0.3 else Vector2.ZERO      # along his line, the way the camera pans
	var stopped := b < _stopped
	var moving := dir.length() > 0.01 and not stopped and not _gun_out and b < _song_end + 1.0
	var aiming_now := (not _pose.is_empty() and String(_pose["move"]["id"]) == "aim") or _gun_out
	lead.performing = not moving and not stopped and not aiming_now and b < _song_end + 0.5
	lead.aiming = aiming_now
	lead.aim_way = "toward" if aiming_now else ""
	if lead.performing:
		lead._beat = maxf(b - delta / BEAT, 0.0)
	if moving:
		lead.walk(dir, dir, delta)       # the camera looks along -z: right on the screen is +x
	else:
		lead.walk(Vector2.ZERO, Vector2.ZERO, delta)
	if lead.face:
		lead.face.talking = b >= _count_in and b < _song_end and not stopped
	# The move he is doing, laid over the groove.
	if not _pose.is_empty():
		var move: Dictionary = _pose["move"]
		var t := b - float(_pose["start"])
		var length := float(move.get("beats", 0.8))
		if t > length:
			_pose = {}
			_mood = ""
		elif not moving and String(move["id"]) != "aim":
			_lay_move(lead, move, t, length)
	if _pose.is_empty() and lead.face and not stopped and not _gun_out:
		var mood: String = MOODS[int(maxf(b - _count_in, 0.0) / 8.0) % MOODS.size()]
		if mood != _mood:
			_mood = mood
			lead.face.set_expression(mood)
	if _turned and not stopped:
		_turned = false
		lead.face_way("front")


## Lay a move's arms and lean over whatever pose he is in, easing in and out.
func _lay_move(who: Node3D, move: Dictionary, t: float, length: float) -> void:
	var arms: Array = move.get("arms", [])
	if arms.size() < 4:
		return
	var k := smoothstep(0.0, 0.12, t) * (1.0 - smoothstep(length - 0.22, length, t))
	var mat: ShaderMaterial = who._mat
	var names := ["arm_l_angle", "arm_r_angle", "arm_l_curl", "arm_r_curl"]
	for i in 4:
		var was := float(mat.get_shader_parameter(names[i]))
		who._put(names[i], lerpf(was, float(arms[i]), k))
	who._card.rotation.z = lerpf(who._card.rotation.z, float(move.get("lean", 0.0)), k)


func _entourage(b: float, delta: float) -> void:
	for i in stage.crew.size():
		var npc: Node3D = stage.crew[i]
		var c: Dictionary = _crew[i]
		if c["gone"]:
			continue
		if c["goal"] != null:          # walking: in front of the lens, or out of the picture
			npc.performing = false
			var goal: Vector3 = c["goal"]
			var gap := Vector2(goal.x - npc.position.x, goal.z - npc.position.z)
			var then: Array = c.get("then", [])
			if gap.length() < 0.1 and not then.is_empty():     # on to the next point of his way
				c["goal"] = then.pop_front()
			elif gap.length() < 0.1:
				c["goal"] = null
				if c["exit"]:
					c["gone"] = true
					npc.visible = false
				npc.walk(Vector2.ZERO, Vector2.ZERO, delta)
			else:
				var at := npc.position
				var way := gap.normalized()
				npc.walk(way, main._screen_dir(way), delta)
				c["stuck"] = float(c["stuck"]) + delta if npc.position.distance_to(at) < 0.3 * delta else 0.0
				if float(c["stuck"]) > 1.0 and c["exit"]:
					c["gone"] = true
					npc.visible = false
			continue
		var lost := b - float(c["lost"]) < 1.2
		npc.performing = not lost and b < _song_end + 0.5 and not c["wave"]
		if npc.performing:
			npc._beat = maxf(b - delta / BEAT, 0.0)
		npc.walk(Vector2.ZERO, Vector2.ZERO, delta)
		if npc.face:
			var want := "confused" if lost else ("grin" if not (c["move"] as Dictionary).is_empty() else "happy")
			if c["wave"]:
				want = "laugh"
			if npc.face.expression != want:
				npc.face.set_expression(want)
		if c["wave"]:                 # in front of the lens, waving at it
			npc._put("arm_r_angle", 2.5 + 0.35 * sin(time * 9.0))
			npc._put("arm_l_angle", -0.15)
		elif not (c["move"] as Dictionary).is_empty():
			var t := b - float(c["start"])
			var move: Dictionary = c["move"]
			var length := float(move.get("beats", 0.8))
			if t > length:
				c["move"] = {}
			elif t >= 0.0 and String(move["id"]) not in ["aim", "cash", "chain"]:
				_lay_move(npc, move, t, length)


# ------------------------------------------------------------------- mishaps

func _run_mishaps(b: float) -> void:
	var words: Dictionary = data["words"]
	for m: Dictionary in mishaps:
		match m["state"]:
			"coming":
				if b >= float(m["start"]):
					m["state"] = "on"
					_begin(m)
			"on":
				if b >= float(m["open"]):
					m["state"] = "asking"
					if String(m["m"]["effect"]) == "police" and String(main._actor.weapon) != "":
						_gun_out = true
			"asking":
				var row: Dictionary = m["m"]
				ui.mishap({"name": row["name"], "key": row["answer"].get("key", "E"), "say": row["answer"]["say"],
					"or": row["miss"].get("say", ""), "or_word": words.get("or", "OR"),
					"left": (float(m["close"]) - b) / maxf(float(m["close"]) - float(m["open"]), 0.01)})
				if b >= float(m["close"]):
					_end_mishap(m, false)


## A mishap comes on.
func _begin(m: Dictionary) -> void:
	var row: Dictionary = m["m"]
	var lead: Node3D = main._actor
	match String(row["effect"]):
		"lens_hog":         # one of the entourage walks right up to the lens: one with a clear way there, straight or round him
			var lens := Vector3(stage.lens.x, 0.0, stage.lens.z)
			var toward: Vector3 = stage.mark - lens
			toward.y = 0.0
			toward = toward.normalized()
			var across := Vector3(-toward.z, 0.0, toward.x)
			var order: Array = range(stage.crew.size())
			for k in order.size():           # a seeded shuffle
				var j := _rng.randi() % order.size()
				var swap: int = order[k]
				order[k] = order[j]
				order[j] = swap
			for k: int in order:
				var npc: Node3D = stage.crew[k]
				var side := signf((npc.position - lead.position).dot(across))
				if side == 0.0:
					side = 1.0
				var spot := lens + toward * 1.7 + across * 0.35 * side
				var round_him := lead.position - toward * 1.0 + across * 0.8 * side
				for way: Array in [[spot], [round_him, spot]]:
					if m.has("who"):
						break
					if _clear_way(npc, way):
						m["who"] = k
						npc.speed = 3.4              # he hurries: he has something to say to his mother
						_crew[k]["goal"] = way[0]
						_crew[k]["then"] = way.slice(1)
						_crew[k]["side"] = side
			if not m.has("who"):
				m["who"] = -1
				print("[shot] video: nobody in the entourage has a clear way to the lens")
		"car_alarm":         # the car nearest where the camera is pointing, so it is seen going off
			var i := 0
			for k in stage.cars.size():
				var node: Node3D = stage.cars[k]["node"]
				var best: Node3D = stage.cars[i]["node"]
				if absf(node.position.x - aim_x()) < absf(best.position.x - aim_x()):
					i = k
			m["car"] = i
			stage.alarm(i, true)
			if i < stage.cars.size():
				stage.say(stage.cars[i]["node"], String(data["words"].get("alarm", "")), BEAT * 1.5, Color("#f07a2a"))
		"neighbour":         # Miss Bea, from off the picture
			var lines: Array = row.get("lines", [])
			ui.voice(String(row.get("who", "")), String(lines[0]) if lines.size() > 0 else "")
		"police":
			stage.police_in(true, String(data["words"].get("siren", "")))
		"smoke":
			stage.set_smoke(1.0)
		"chain_drop":
			stage.chain_fall()
			if lead.face:
				lead.face.set_expression("shocked")


## Answered (E in time) or not.
func _end_mishap(m: Dictionary, handled: bool) -> void:
	var row: Dictionary = m["m"]
	var outcome: Dictionary = row["answer"] if handled else row["miss"]
	m["state"] = "done"
	m["handled"] = handled
	_polish += float(outcome.get("polish", 0))
	_chaos += float(outcome.get("chaos", 0))
	ui.mishap({})
	var b := beat()
	var lead: Node3D = main._actor
	var line := String(outcome.get("line", ""))
	var id := String(row["id"])
	_wish("%s:%s" % [id, "handled" if handled else "missed"], b + (0.5 if handled else 0.3))
	match String(row["effect"]):
		"lens_hog":
			var pick: int = m.get("who", -1)
			if pick < 0 or pick >= stage.crew.size():
				return
			var npc: Node3D = stage.crew[pick]
			var c: Dictionary = _crew[pick]
			stage.say(npc, line, BEAT * 1.6)
			var leave := func() -> void:
				c["wave"] = false
				c["exit"] = true
				c["then"] = []
				var side := float(c.get("side", 1.0))
				c["goal"] = Vector3(stage.lens.x + side * 1.9, 0.0, stage.lens.z + 0.4)
			if handled:          # he shoves him out of the way: the homie lurches and goes
				_pose = {"move": {"id": "shove", "arms": [-1.2, 0.2, 0.0, 0.0] if c.get("side", 1.0) < 0.0 else [-0.2, 1.2, 0.0, 0.0], "lean": 0.0, "beats": 0.7}, "start": b}
				npc._card.rotation.z = -0.25 * float(c.get("side", 1.0))
				_later.append({"beat": b + 0.4, "do": leave})
			else:                # he waves at the lens a while first
				c["goal"] = null
				c["then"] = []
				c["wave"] = true
				_later.append({"beat": b + 1.8, "do": leave})
		"car_alarm":
			var i: int = m.get("car", 0)
			if handled:
				stage.kick(i)
				stage.alarm(i, false)
				if i < stage.cars.size():
					stage.say(stage.cars[i]["node"], line, BEAT * 1.4)
			else:
				if i < stage.cars.size():
					stage.say(stage.cars[i]["node"], line, BEAT * 2.0, Color("#f07a2a"))
				_later.append({"beat": b + 2.0, "do": func() -> void: stage.alarm(i, false)})
		"neighbour":
			var lines: Array = row.get("lines", [])
			if handled:          # he stops, turns to her and takes it
				_stopped = b + 1.8
				_turned = true
				lead.face_side(-1.0)
				if lead.face:
					lead.face.set_expression("guilty")
				stage.say(lead, line, BEAT * 1.6)
				_later.append({"beat": b + 1.4, "do": func() -> void: ui.voice("", "")})
			else:                # she has had enough: the slipper
				ui.voice(String(row.get("who", "")), String(lines[1]) if lines.size() > 1 else "")
				var cam: Camera3D = main._camera
				var left := -cam.global_transform.basis.x
				left.y = 0.0
				stage.slipper_throw(lead.position + left.normalized() * 4.5 + Vector3(0.0, 1.6, 0.6))
				var ow := func() -> void:
					stage.say(lead, line, BEAT * 1.4, Color("#e8392b"))
					if lead.face:
						lead.face.set_expression("hurt")
				_later.append({"beat": b + 0.85, "do": ow})
				_later.append({"beat": b + 2.0, "do": func() -> void: ui.voice("", "")})
		"police":
			var car: Node3D = stage.police_car()
			if handled and String(main._actor.weapon) != "":      # PUT IT AWAY
				_gun_out = false
				main._actor.weapon = ""
				_retire("aim")
				if lead.face:
					lead.face.set_expression("innocent")
			elif handled:          # ACT NATURAL
				_stopped = b + 1.6
				if lead.face:
					lead.face.set_expression("innocent")
			else:
				if car:
					stage.say(car, line, BEAT * 1.8)
				_later.append({"beat": b + 1.2, "do": func() -> void: _gun_out = false})
			_later.append({"beat": b + 1.4, "do": func() -> void: stage.police_go()})
		"smoke":
			if handled:
				stage.set_smoke(0.0)
				_pose = {"move": {"id": "fan", "arms": [-1.3, 1.3, 0.4, -0.4], "lean": 0.0, "beats": 0.9}, "start": b}
			else:
				stage.say(lead, line, BEAT * 1.5)
				if lead.face:
					lead.face.set_expression("disgusted")
				_later.append({"beat": b + 1.6, "do": func() -> void: stage.set_smoke(0.0)})
		"chain_drop":
			if handled:
				stage.chain_catch()
				if lead.face:
					lead.face.set_expression("grin")
			else:
				stage.chain_drop()
				_retire("chain")
				stage.say(lead, line, BEAT * 1.6)
				if lead.face:
					lead.face.set_expression("crying")


# --------------------------------------------------------------- auto player

## Whoever plays it for a --do step, at `auto` skill: 1 lands every move
## dead on the beat, answers every mishap at once and stays in shot; 0 presses
## nothing and stands where he is. In between, in proportion (seeded, so the same
## skill plays the same take the same way).
func _auto_play(b: float) -> void:
	var s := clampf(auto, 0.0, 1.0)
	for p: Dictionary in prompts:
		if p["state"] != "due":
			continue
		if not p.has("auto"):
			if float(p["beat"]) - b > 2.0:
				continue
			var press_it := _rng.randf() < pow(s, 0.7)
			var err := _rng.randfn(0.0, (1.0 - s) * 0.2)
			p["auto"] = {"press": press_it, "at": float(p["beat"]) * BEAT + err}
		var plan: Dictionary = p["auto"]
		if plan["press"] and time >= float(plan["at"]):
			plan["press"] = false
			press(String(p["key"]))
	# Now and then, an off-beat press.
	if b >= _count_in and b < _song_end and int(b * 4.0) != _quarter:
		_quarter = int(b * 4.0)
		if _rng.randf() < (1.0 - s) * 0.035:
			var keys: Array = _keys.keys()
			press(String(keys[_rng.randi() % keys.size()]))
	for m: Dictionary in mishaps:
		if m["state"] != "asking":
			continue
		if not m.has("auto"):
			m["auto"] = {"answer": _rng.randf() < s, "at": float(m["open"]) + lerpf(2.2, 0.4, s)}
		if m["auto"]["answer"] and b >= float(m["auto"]["at"]):
			m["auto"]["answer"] = false
			press("E")
	# Keep in shot: walk to where the camera is pointing once he is far enough off it.
	var lead: Node3D = main._actor
	var off := aim_x() - lead.position.x
	var slack := 0.3 + (1.0 - s) * 3.0
	if absf(off) > slack or (absf(hold_dir.x) > 0.0 and absf(off) > 0.15):
		hold_dir = Vector2(signf(off), 0.0)
	else:
		hold_dir = Vector2.ZERO


# ---------------------------------------------------------------- the screen

func _show(b: float) -> void:
	var words: Dictionary = data["words"]
	ui.finder = smoothstep(3.2, 3.8, b) * (1.0 - smoothstep(_song_end + 0.8, _song_end + 1.6, b))
	ui.in_shot = in_shot
	ui.frame = float(_take.get("frame", 0.24))
	ui.swagger = swagger()
	ui.chaos = clampf(_chaos, 0.0, 100.0)
	ui.lane(prompts, b)
	ui.set_time(maxf(time - _count_in * BEAT, 0.0))
	var section := ""
	var at := _count_in
	for s: Dictionary in _take["sections"]:
		var length := float(String(s["pattern"]).length())
		if b >= at and b < at + length:
			section = String(s["name"])
		at += length
	if section != _section:
		_section = section
		ui.set_section(section)
	if b < 1.5:
		ui.big(String(words.get("set", "")))
	elif b < 3.0:
		ui.big(String(words.get("rolling", "")))
	elif b < _count_in + 0.6:
		ui.big(String(words.get("action", "")))
	elif b >= _song_end + 0.3:
		ui.big(String(words.get("cut", "")))
	else:
		ui.big("")


## How well he is doing, 0 .. 100: the moves landed so far (a miss counts
## nothing), less a little for every press off the beat.
func swagger() -> float:
	if _judged == 0:
		return 0.0 if _flubs > 0 else 50.0
	return clampf(100.0 * _points / _judged - float(_take.get("flub", 2.0)) * _flubs, 0.0, 100.0)


func _wish(key: String, at: float) -> void:
	if _wished.has(key):
		return
	_wished[key] = true
	stills.append({"key": key, "beat": at})


func _count_wished(prefix: String) -> int:
	var n := 0
	for key: String in _wished:
		if key.begins_with(prefix):
			n += 1
	return n


## The moment keys that are due now (the shoot takes the still and gives it back with `caught`).
func due_stills() -> Array:
	var out: Array = []
	for s: Dictionary in stills.duplicate():
		if beat() >= float(s["beat"]):
			stills.erase(s)
			out.append(String(s["key"]))
	return out


func _finish() -> void:
	done = true
	var outcome: Array = []
	for m: Dictionary in mishaps:
		if m["state"] == "done":
			outcome.append({"id": String(m["m"]["id"]), "handled": bool(m["handled"])})
	var hits := 0
	var perfect := 0
	var missed := 0
	for p: Dictionary in prompts:
		if p["state"] == "hit":
			hits += 1
			if p["grade"] == "perfect":
				perfect += 1
		elif p["state"] == "miss":
			missed += 1
	kept = {"swagger": roundi(swagger()), "polish": clampf(_polish, 0.0, 100.0), "chaos": clampf(_chaos, 0.0, 100.0),
		"mishaps": outcome, "hits": hits, "perfect": perfect, "missed": missed, "flubs": _flubs, "moves": prompts.size()}
	main._actor.weapon = _weapon
	wrapped.emit()
