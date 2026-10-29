extends Node3D
## HUD harness: fills G with fake state and drives every HUD state, saving a screenshot of each.
## Run windowed (it needs the renderer):
##   python godot/tools/godot_run.py --timeout 300 -- --resolution 1600x900 res://scenes/ui/hud_test.tscn -- --out C:/abs/dir [--only play,bino]
## Writes <out>/hud_<state>.png and prints the G callbacks the HUD made.

const FakeG := preload("res://scripts/ui/test/fake_g.gd")
const FakeCrime := preload("res://scripts/ui/test/fake_crime.gd")

var out_dir := ""
var only: Array = []
var g: Node
var hud: Node
var cam: Camera3D
var failures: Array = []


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == "--out" and i + 1 < a.size():
			out_dir = a[i + 1]
		elif a[i] == "--only" and i + 1 < a.size():
			only = Array(a[i + 1].split(","))
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("res://").path_join("../.work/ui_shots").simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)
	g = get_node("/root/G")
	hud = get_node("/root/Hud")
	if OS.get_cmdline_user_args().has("--stub"):
		await _stub_smoke()
		get_tree().quit()
		return
	g.set_script(FakeG)
	_build_world()
	await get_tree().process_frame
	await _run()
	print("[hud_test] G calls: ", g.calls)
	if failures.size():
		print("[hud_test] FAILURES: ", failures)
	else:
		print("[hud_test] all checks passed")
	get_tree().quit()


## Every API call against the untouched stub G (empty C, null car, no W): must not error.
func _stub_smoke() -> void:
	var calls := 0
	hud.show_title(true)
	hud.hide_screens()
	hud.show_hud(true)
	hud.say("NOBODY", "Unknown speaker line.")
	hud.say("TWOPACK", "Known speaker line.", 0.2)
	hud.toast("A toast.")
	hud.pop(Vector3(1, 1, 1), "POP")
	hud.card("STAGE 1", "Snitch Season", 0.2)
	hud.bino(true)
	hud.bino(true, "LABEL", 2.0)
	hud.bino(false)
	hud.lock_update("rhythm", {})
	hud.lock_msg("no lock open")
	for k in ["rhythm", "ruler", "record", "bogus"]:
		hud.lock_open(k, "EYE", "Title", "Msg")
		hud.lock_update(k, {})
		hud.lock_update(k, {"head": 0.5, "hit": 9, "needle": 2.0, "reading": "x", "vu": -1.0, "count": "0/3"})
		await get_tree().process_frame
	hud.lock_close()
	for k in ["wires", "keypad", "menu", "plate", "bogus"]:
		hud.puzzle_show(k, null)
		for key in ["1", "2", "3", "4", "#", "*", "Backspace", "x"]:
			hud.puzzle_key(key)
		await get_tree().create_timer(0.1).timeout
		hud.puzzle_hide()
	hud.puzzle_key("1")
	hud.penalty_flash(4)
	hud.show_over("Shift over", "line", {}, true)
	hud.show_pause(true)
	hud.show_pause(false)
	hud.play_video(Callable())
	await get_tree().create_timer(0.2).timeout
	hud.hide_screens()
	hud.play_video(func(): calls += 1)
	await get_tree().create_timer(0.1).timeout
	hud.hide_screens()
	hud.clear_subs()
	hud.show_hud(false)
	for i in 30:
		await get_tree().process_frame
	print("[hud_test] stub smoke done")


func _want(n: String) -> bool:
	return only.is_empty() or only.has(n)


func _shot(n: String, settle := 0.35) -> void:
	await get_tree().create_timer(settle).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var p := out_dir.path_join("hud_%s.png" % n)
	img.save_png(p)
	print("[hud_test] saved ", p)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)
		push_warning("[hud_test] check failed: " + what)


# ------------------------------------------------------------------------------ world
func _box(size: Vector3, pos: Vector3, col: Color) -> void:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.9
	m.material_override = mat
	m.position = pos
	add_child(m)


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#b9d0e4")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#c9d6e6")
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)
	sun.look_at_from_position(Vector3(14, 26, 12), Vector3.ZERO, Vector3.UP)
	_box(Vector3(120, 0.1, 14), Vector3(6, -0.05, 7), Color("#3a3b42"))          # street
	_box(Vector3(120, 0.12, 3.2), Vector3(6, -0.04, -1.6), Color("#d8d2c0"))     # sidewalk
	_box(Vector3(120, 0.1, 3.8), Vector3(6, -0.05, -5.1), Color("#7da34e"))      # lawns
	_box(Vector3(120, 0.12, 5), Vector3(6, -0.04, 16.5), Color("#d8d2c0"))       # far sidewalk
	var cols := [Color("#a35a4a"), Color("#6a7d9a"), Color("#c9a35a"), Color("#5a8a6a"), Color("#8a6a9a"), Color("#b07a4a")]
	for i in 11:
		var x := -30.0 + i * 7.2
		_box(Vector3(6.6, 6.0 + (i % 3), 6), Vector3(x, 3.0, -10), cols[i % cols.size()])
		_box(Vector3(1.2, 2.2, 0.2), Vector3(x, 1.1, -6.95), Color("#5a3a24"))
	for x in [-10.5, 2.8, 19.6]:
		_box(Vector3(0.5, 1.6, 0.4), Vector3(x, 0.8, -3.0), Color("#2c5bd6"))   # payphones
	_box(Vector3(1.0, 0.5, 0.6), Vector3(-3.55, 0.25, 0.73), Color("#8a6aa0"))   # "Gary"
	_box(Vector3(0.6, 1.8, 0.4), Vector3(2.8, 0.9, -2.3), Color("#7a4a2a"))      # "2-Pack"
	cam = Camera3D.new()
	cam.fov = 55
	add_child(cam)
	cam.current = true


func _third_person(px: float, pz: float, yaw: float, pitch := 0.32) -> void:
	var dist := 5.6
	var head := Vector3(px, 1.5, pz)
	var want := Vector3(px - sin(yaw) * cos(pitch) * dist, 1.5 + sin(pitch) * dist, pz - cos(yaw) * cos(pitch) * dist)
	cam.fov = 55
	cam.look_at_from_position(want, head, Vector3.UP)


# ------------------------------------------------------------------------------ fake state
func _crime(id: String, title: String, who: String, steps: Array, t: Vector3, left: float, full: float, si := 0, no := 1) -> Object:
	var c = FakeCrime.new()
	c.id = id
	c.title = title
	c.who = who
	c.steps = steps
	c.tpos = t
	c.active = true
	c.left = left
	c.full = full
	c.si = si
	c.no = no
	return c


func _stage1_state() -> void:
	g.S.mode = "play"
	g.S.stage = 1
	g.S.score = 1640
	g.S.strikes = 1
	g.S.still = 2
	g.S.busts = 4
	g.S.told = {"granny": true, "mail": true}
	g.S.lock = null
	g.S.pz = null
	g.S.bino_on = false
	g.P.x = 2.8
	g.P.z = -2.3
	g.P.yaw = PI
	g.cam_yaw = PI * 0.85
	g.car = {"x": 42.0, "z": -1.0}
	g.W = {"dan": {"escort": null, "lost": false, "x": 35.2, "z": -2.75}}
	g.W_ = {"phones": [{"x": -10.5, "z": -3.0}, {"x": 2.8, "z": -3.0}, {"x": 19.6, "z": -3.0}]}
	var gary = _crime("gary", "Smoking crack in the gutter", "Gary · since 2009",
		[{"k": "spy", "t": "Spy on him with binoculars", "m": "!"}, {"k": "call", "t": "Call it in: any payphone, or Precinct 9", "m": "CALL IT IN"}],
		Vector3(-3.55, 0.45, 0.73), INF, INF, 1, 1)
	gary.describe = "Gary. He's in the gutter. He's always in the gutter."
	var ricky = _crime("ricky", "Bank robbery", "Ricky",
		[{"k": "cash", "t": func(): return "Follow the money: pick up the bills he's dropping (%d/3)" % 0, "m": "FOLLOW THE $"},
		 {"k": "spy", "t": "ID him with binoculars", "m": "!"},
		 {"k": "getdan", "t": "Go get Officer Dan at Precinct 9 (east end). Ricky won't wait.", "m": "GET DAN"},
		 {"k": "lead", "t": "Lead Dan to Ricky. Don't lose him.", "m": "LEAD DAN"}],
		Vector3(9.0, 1.2, -1.05), 12.4, 130.0, 0, 2)
	var timmy = _crime("timmy", "Unlicensed lemonade stand", "Little Timmy",
		[{"k": "buy", "t": "Go undercover: buy a cup at his stand", "m": "BUY ONE"}, {"k": "mama", "t": "Tell his mama: knock on the door of the house behind the stand", "m": "KNOCK"}],
		Vector3(16.5, 0.9, -3.6), 80.0, 80.0, 1, 3)
	var lawn = _crime("lawn", "Lawn a quarter inch too brown", "Mrs. Johnson",
		[{"k": "measure", "t": "Measure it: stand on her lawn and get out your ruler", "m": "MEASURE"}, {"k": "mail", "t": "Mail a complaint: the blue mailbox near your house", "m": "MAIL IT"}],
		Vector3(11.5, 0.2, -5.0), 61.0, 90.0, 1, 4)
	lawn.dispatched = true
	g.C = {"gary": gary, "ricky": ricky, "timmy": timmy, "lawn": lawn}
	_third_person(g.P.x, g.P.z, g.cam_yaw)


# ------------------------------------------------------------------------------ states
func _run() -> void:
	# boot: nothing but the title should show
	g.S.mode = "title"
	cam.look_at_from_position(Vector3(18, 6.5, 14), Vector3(4, 1.2, -2), Vector3.UP)
	if _want("title"):
		hud.show_title(true)
		await _shot("title")
		hud.hide_screens()

	_stage1_state()
	hud.show_hud(true)
	if _want("play"):
		g.fake_interact = {"kind": "phone", "label": "Use payphone"}
		hud.say("TWOPACK", "Yeah... this one goes out to Precinct Nine.", 3.0)
		hud.say("GARY", "Heyyy, fellas!", 1.8)
		hud.toast("Every crime gets reported its own way. Your case file says what to do next.")
		hud.pop(Vector3(16.5, 0.4, -2.6), "RECEIPT")
		await _shot("play", 0.5)
		_check(_has_call("set_talking", "TWOPACK", 2.55), "say() calls G.set_talking(who, dur * 0.85)")
		g.fake_interact = null

	if _want("bino"):
		g.S.bino_on = true
		g.bino_yaw = -0.72
		cam.fov = 22
		cam.look_at_from_position(Vector3(2.8, 1.68, -2.3), Vector3(-3.55, 0.6, 0.73), Vector3.UP)
		hud.bino(true, "GARY · 21 FT", 0.45)
		await _shot("bino")
		hud.bino(true, "NOTHING TO REPORT. YET.", 0.0)
		await _shot("bino_none", 0.2)
		g.S.bino_on = false
		hud.bino(false)
		_third_person(g.P.x, g.P.z, g.cam_yaw)

	if _want("rhythm"):
		g.S.lock = {"kind": "rhythm"}
		hud.lock_open("rhythm", "CITIZEN'S CITATION", "Blow the whistle on the beat", "Press E as the line crosses each dot. Hit 4 of 6. Esc to back off.")
		hud.lock_update("rhythm", {"head": 0.1, "hit": -1})
		hud.lock_update("rhythm", {"head": 0.21, "hit": 0})
		hud.say("TWOPACK", "Hold it right there, ma'am!", 1.4)
		await _shot("rhythm")
	if _want("ruler"):
		g.S.lock = {"kind": "ruler"}
		hud.lock_open("ruler", "LAWN INSPECTION", "Measure the grass", "Press E when it reads exactly 1/4 inch. Esc to stop.")
		hud.lock_update("ruler", {"needle": 0.31, "reading": "5/16 in"})
		hud.lock_msg("That reads 5/16 in. Again. (-3s)")
		await _shot("ruler")
	if _want("record"):
		g.S.lock = {"kind": "record"}
		hud.lock_open("record", "FLIP PHONE · VOICE MEMO", "Record the snoring", "Hold still. It records every snore. Esc to stop.")
		hud.lock_update("record", {"vu": 0.82, "count": "1/3"})
		hud.pop(Vector3(5.0, 1.2, -5.0), "SNORE 1/3")
		await _shot("record", 0.3)
	hud.lock_close()
	g.S.lock = null

	var gary = g.C["gary"]
	for k in ["wires", "keypad", "menu"]:
		if not _want(k):
			continue
		g.S.mode = "puzzle"
		g.S.pz = {"focus": gary, "kind": k, "done": false}
		hud.puzzle_show(k, gary)
		await _shot(k, 1.25 if k == "keypad" else 0.35)
		hud.puzzle_hide()
		g.S.pz = null

	if _want("keypad"):
		# a wrong key while it plays back is ignored; a wrong key when listening costs 4 s
		g.calls.clear()
		g.S.mode = "puzzle"
		g.S.pz = {"focus": gary, "kind": "keypad", "done": false}
		hud.puzzle_show("keypad", gary)
		await get_tree().create_timer(3.9).timeout
		hud.puzzle_key("#")
		hud.puzzle_key("#")
		hud.puzzle_key("#")
		await get_tree().process_frame
		_check(g.calls.has(["penalty", 4]), "keypad: a wrong answer calls G.penalty(4)")
		await _shot("keypad_wrong", 0.12)
		hud.puzzle_hide()
		g.S.pz = null

	if _want("menu"):
		# one wrong pick (costs 4 s, back to the first question), then the right answers
		g.calls.clear()
		g.S.mode = "puzzle"
		g.S.pz = {"focus": gary, "kind": "menu", "done": false}
		hud.puzzle_show("menu", gary)
		await get_tree().process_frame
		var answers := [["To report a crime"], ["Yes. Right now. Right there.", "It's been happening since 2009"], [gary.describe]]
		hud.puzzle_key(_menu_key(answers[0], false))
		await get_tree().process_frame
		_check(g.calls.has(["penalty", 4]), "menu: a wrong pick calls G.penalty(4)")
		await _shot("menu_wrong", 0.1)
		await get_tree().create_timer(0.8).timeout
		for step in 3:
			hud.puzzle_key(_menu_key(answers[step], true))
			await get_tree().process_frame
		_check(g.calls.has(["puzzle_solved"]), "menu: the right answers call G.puzzle_solved()")
		await _shot("menu_solved", 0.1)
		hud.puzzle_hide()
		g.S.pz = null

	if _want("plate"):
		g.calls.clear()
		g.S.stage = 2
		g.S.told = {"daddy": true}
		var mama = _crime("mama", "Running a red light", "2-Pack's mama",
			[{"k": "spy", "t": "Catch her running the red light at the crosswalk. Binoculars, while it's red.", "m": "!"},
			 {"k": "call", "t": "Call it in from a payphone. Remember her plate?", "m": "CALL IT IN"}],
			Vector3(2.0, 1.1, 10.5), 9.0, 90.0, 1, 5)
		mama.plate = "4127"
		mama.hint = 0
		mama.puzzle = "plate"
		g.C = {"gary": gary, "mama": mama}
		g.S.mode = "puzzle"
		g.S.pz = {"focus": mama, "kind": "plate", "done": false}
		hud.puzzle_show("plate", mama)
		for k in ["4", "2"]:
			hud.puzzle_key(k)
		await _shot("plate", 0.3)
		for k in ["9", "9"]:
			hud.puzzle_key(k)
		await get_tree().process_frame
		_check(mama.hint == 1, "plate: a wrong plate raises focus.hint")
		_check(g.calls.has(["penalty", 4]), "plate: a wrong plate calls G.penalty(4)")
		await _shot("plate_wrong", 0.15)
		await get_tree().create_timer(0.6).timeout
		for k in ["4", "1", "2", "Backspace", "2", "7"]:
			hud.puzzle_key(k)
		await get_tree().process_frame
		_check(g.calls.has(["puzzle_solved"]), "plate: the right plate calls G.puzzle_solved()")
		await _shot("plate_solved", 0.1)
		hud.puzzle_hide()
		g.S.pz = null
		_stage1_state()

	if _want("over"):
		hud.show_hud(false)
		g.S.mode = "over"
		hud.show_over("Shift over", "I keep on callin', but nothin' gets done", {"score": 2310, "busts": 6, "still": 2, "time": 312.0}, false)
		await _shot("over")
		hud.show_over("Stage 2 clear", "Gary called it in. To be continued...", {"score": 6210, "busts": 9, "still": 3, "time": 845.0}, true)
		await _shot("clear")
		hud.hide_screens()

	if _want("pause"):
		_stage1_state()
		hud.show_hud(true)
		await get_tree().create_timer(0.2).timeout
		g.S.mode = "pause"
		hud.show_pause(true)
		await _shot("pause")
		hud.show_pause(false)
		g.S.mode = "play"

	if _want("card"):
		hud.card("STAGE 2", "Verse 3: everybody he's ever told on", 60)
		await _shot("card")
		hud.card("STAGE 1", "Snitch Season", 0.3)
		await get_tree().create_timer(0.5).timeout

	if _want("video"):
		hud.show_hud(false)
		g.S.mode = "video"
		var done := [false]
		hud.play_video(func(): done[0] = true)
		var has_video := ResourceLoader.exists("res://assets/video/still_there.ogv")
		await _shot("video", 1.6 if has_video else 0.3)
		var skip: Button = _find_button(hud, "SKIP TO STAGE 2")
		_check(skip != null, "video: has the skip button")
		if skip:
			skip.pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		_check(done[0], "video: Skip to Stage 2 calls the callback")

	if _want("wide"):
		hud.hide_screens()
		_stage1_state()
		hud.show_hud(true)
		get_window().size = Vector2i(2240, 945)
		await get_tree().process_frame
		_third_person(g.P.x, g.P.z, g.cam_yaw)
		hud.toast("Wait... is that the cop car? In the FIRE LANE?")
		await _shot("wide", 0.5)
		get_window().size = Vector2i(1200, 900)
		await _shot("narrow", 0.5)


func _has_call(fn: String, a0, a1 = null) -> bool:
	for c in g.calls:
		if c[0] == fn and c.size() > 1 and c[1] == a0 and (a1 == null or absf(float(c[2]) - float(a1)) < 0.011):
			return true
	return false


## The number key of the menu option whose text is (or, right == false, isn't) in texts.
func _menu_key(texts: Array, right: bool) -> String:
	for l in _all_labels(hud.get("_puzzle")):
		var row: Node = l.get_parent()
		if row is HBoxContainer and row.get_child_count() == 2 and row.get_child(1) == l:
			if texts.has(l.text) == right:
				var num: Label = row.get_child(0).get_child(0)
				return num.text
	return "1"


func _all_labels(n: Node) -> Array:
	var out := []
	if n is Label:
		out.append(n)
	for ch in n.get_children():
		out.append_array(_all_labels(ch))
	return out


func _find_button(n: Node, text: String) -> Button:
	if n is Button and (n as Button).text == text:
		return n
	for ch in n.get_children():
		var b := _find_button(ch, text)
		if b:
			return b
	return null
