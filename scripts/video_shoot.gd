extends Node
## The music video, from the studio to the premiere (main.gd makes one and
## calls `setup`). Everything it says and every number it uses is in
## assets/data/video.json.
##
##   Record   Performing at the booth microphone for "song"'s "beats" beats is
##            a song recorded (player_state.gd's songs). A REC mark shows
##            while he is at it.
##   Start    The camcorder on its tripod in the control room's front corner.
##            E there: the plan board if there is a song with no video yet,
##            otherwise it says to record one first.
##   Plan     video_plan.gd. Esc: nothing spent.
##   Shoot    He is taken to the location, the set is put out (video_stage.gd)
##            and the take is played (video_take.gd, video_take_ui.gd). Esc
##            walks him off the set: back to the studio, nothing spent. At CUT
##            the whole plan is paid for at once.
##   Premiere Back in the studio (video_premiere.gd): the moments caught during
##            the take, the views, the comments, the pay (video_score.gd). The
##            video is kept in player_state.gd's videos and he is paid when it
##            is over, or at once on Esc.
##
## Steps for --do (main.gd hands it each "video:..." step), in order:
##   video:song           a song recorded, as if he had performed one
##   video:cash:n         make his cash n
##   video:spot           stand him by the camcorder (in the studio)
##   video:plan           E at the camcorder: the plan board (or the "record a song first" note)
##   video:buy:cheap      the free card of every row; video:buy:dear the dearest;
##   video:buy:location=court+entourage=few+...   those cards (row=choice id)
##   video:mishaps:id+id  the next take has these mishaps, in this order
##   video:seed:n         the next take's luck
##   video:shoot          SHOOT IT on the board
##   video:auto:skill     the take plays itself from here at that skill, 0 .. 1
##   video:key:J          a key pressed in the take; video:walk:-1 / 1 / 0 holds left, right or nothing
##   video:until:beat     run the take to that beat and hold it (count-in 0..4, ACTION at 4); video:until:end
##   video:prompt         run it until the next move is just reaching the ring
##   video:at:id          run it until that mishap is asking for E
##   video:for:beats      run it on that many beats from where it is
##   video:live:seconds   let it run as it does in play for that long (in real time, the keyboard's keys; key:J presses one)
##   video:premiere       run the rest of the take, to the premiere
##   video:next           Enter on the premiere; video:results straight to the money; video:done back to the game
##   video:esc            Esc at whatever is up
##   video:snap:name      save the picture as it is now beside the --shot file, as name.png
##   video:state          print his cash, songs and videos

const DATA := "res://assets/data/video.json"
const Props := preload("res://scripts/video_props.gd")
const Score := preload("res://scripts/video_score.gd")
const Plan := preload("res://scripts/video_plan.gd")
const Stage := preload("res://scripts/video_stage.gd")
const Take := preload("res://scripts/video_take.gd")
const TakeUI := preload("res://scripts/video_take_ui.gd")
const Premiere := preload("res://scripts/video_premiere.gd")
const UsePoint := preload("res://scripts/use_point.gd")
const PaperActor := preload("res://scripts/paper_actor.gd")
const FONT := preload("res://assets/fonts/Bungee-Regular.ttf")
const PAPER := Color("#f6f1e3")
const TICKET := Color("#f2d24a")
const SHADE := Color(14 / 255.0, 20 / 255.0, 40 / 255.0, 0.9)

## The camcorder in the control room's front right corner, out of the way
## between the couch and the front wall, pointing at the room; and where he
## stands to use it.
const TRIPOD := Vector3(3.05, 0.0, 2.0)
const TRIPOD_YAW := -140.0
const SPOT := Vector3(2.2, 0.0, 1.95)
const STILL := Vector2i(800, 450)

var main: Node3D
var data := {}
var stage_name := ""             # "", "plan", "shoot", "premiere" (or "leaving": on the way back)
var spot: Node3D                 # E by the camcorder
var picks := {}
var forced: Array = []           # mishaps a --do step asked for
var seed_override := -1
var auto_skill := -1.0           # a --do step's player for the next take

var _studio: Node3D
var _plan: CanvasLayer
var _ui: CanvasLayer
var _premiere: CanvasLayer
var _stage: Node3D
var _take: Node
var _toast: PanelContainer
var _toast_text: Label
var _toast_t := 99.0
var _rec: Label
var _rec_box: HBoxContainer
var _counted := false           # this turn at the microphone has been counted as a song
var _moments: Array = []         # caught during the take: {"key", "image", "beat"}
var _pending: Array = []         # moment keys waiting to be caught
var _catching := false
var _result := {}
var _record := {}
var _total := 0
var _seed := 0
var _hidden: Array = []          # the people of the location, hidden for the shoot
var _was := {}                   # how he was before the shoot
var _snap: SubViewport
var _snap_cam: Camera3D
var _live := false               # a --do step letting the take run as it does in play (video:live)


func setup(main_node: Node3D) -> void:
	main = main_node
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA)) if FileAccess.file_exists(DATA) else null
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Could not read %s: no music videos" % DATA)
		return
	data = parsed
	_studio = main._site("studio")
	var control: Node3D = _studio.control
	Props.tripod(control, TRIPOD, TRIPOD_YAW)
	_studio.obstacles.append(Props.footprint(TRIPOD))
	spot = UsePoint.new()
	spot.name = "VideoSpot"
	spot.id = "video"
	spot.use_reach = 1.3             # from SPOT, or anywhere else this close to the tripod
	spot.label_height = 1.62         # the name over the camcorder
	spot.position = TRIPOD
	control.add_child(spot)
	_studio.use_points.append(spot)
	spot.used.connect(_on_spot)
	if main._building == _studio and not main._usables.has(spot):
		main._usables.append(spot)
	main._state.changed.connect(_name_spot)
	_name_spot()

	_plan = Plan.new()
	add_child(_plan)
	_plan.shoot.connect(_on_shoot)
	_plan.cancelled.connect(_on_plan_cancel)
	_ui = TakeUI.new()
	add_child(_ui)
	_premiere = Premiere.new()
	add_child(_premiere)
	_premiere.finished.connect(_on_premiere_done)

	var layer := CanvasLayer.new()
	layer.layer = 8
	add_child(layer)
	_toast = PanelContainer.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.offset_top = 126.0
	var pill := StyleBoxFlat.new()
	pill.bg_color = SHADE
	pill.set_corner_radius_all(14)
	pill.set_border_width_all(4)
	pill.border_color = Color("#14203f")
	pill.content_margin_left = 26.0
	pill.content_margin_right = 26.0
	pill.content_margin_top = 10.0
	pill.content_margin_bottom = 10.0
	_toast.add_theme_stylebox_override("panel", pill)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.modulate.a = 0.0
	layer.add_child(_toast)
	_toast_text = _label(24, TICKET)
	_toast.add_child(_toast_text)
	_rec_box = HBoxContainer.new()
	_rec_box.position = Vector2(34, 30)
	_rec_box.add_theme_constant_override("separation", 12)
	_rec_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rec_box.visible = false
	layer.add_child(_rec_box)
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(18, 18)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var red := StyleBoxFlat.new()
	red.bg_color = Color("#e8392b")
	red.set_corner_radius_all(9)
	red.set_border_width_all(2)
	red.border_color = Color.BLACK
	dot.add_theme_stylebox_override("panel", red)
	_rec_box.add_child(dot)
	_rec = _label(20, PAPER)
	_rec_box.add_child(_rec)

	# The stills of the premiere are caught by a second camera looking at the same world, without the screen's overlays.
	_snap = SubViewport.new()
	_snap.size = STILL
	_snap.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_snap.world_3d = main.get_viewport().find_world_3d()
	add_child(_snap)
	_snap_cam = Camera3D.new()
	_snap.add_child(_snap_cam)
	_snap_cam.current = true


func _word(key: String) -> String:
	return String(data.get("words", {}).get(key, key.to_upper()))


## Songs he has recorded that have no video yet.
func unfilmed() -> int:
	return int(main._state.songs) - (main._state.videos as Array).size()


## What the camcorder says it is for: a video, or a song first.
func _name_spot() -> void:
	spot.label = _word("spot") if unfilmed() > 0 else _word("spot_no_song")


## The song the next video is for: "TRACK 2".
func song_title() -> String:
	return String(data["song"].get("title", "TRACK {n}")).replace("{n}", str((main._state.videos as Array).size() + 1))


# -------------------------------------------------------------- in the studio

func _process(delta: float) -> void:
	if data.is_empty():
		return
	_toast_t += delta
	_toast.modulate.a = clampf(2.6 - _toast_t, 0.0, 1.0) / 0.4 if _toast_t > 2.2 else minf(_toast_t / 0.15, 1.0)
	match stage_name:
		"":
			_watch_the_mic()
		"shoot":
			_rec_box.visible = false
			if _take and (not main._scripted or _live):
				_take.hold_dir = _held()
				_take.tick(delta)
				_pending.append_array(_take.due_stills() if _take else [])
				if not _catching and not _pending.is_empty():
					_catch_one()
		_:
			_rec_box.visible = false


## At the booth microphone: REC while he performs; once he has done a song's
## worth of beats it is a song recorded.
func _watch_the_mic() -> void:
	var at_mic: bool = main._performing and main._actor.performing
	_rec_box.visible = at_mic
	if not at_mic:
		_counted = false
		return
	var beats := float(data["song"].get("beats", 16))
	var done := float(main._perform_time) / PaperActor.BEAT
	if not _counted and done >= beats:
		_counted = true
		record_song()
	var title := String(data["song"].get("title", "TRACK {n}")).replace("{n}", str(int(main._state.songs) + (0 if _counted else 1)))
	if _counted:
		_rec.text = _word("recorded").replace("{title}", title)
	else:
		_rec.text = "%s   %s   %d / %d" % [_word("rec"), title, mini(int(done) + 1, int(beats)), int(beats)]


func record_song() -> void:
	main._state.record_song()
	toast(_word("recorded").replace("{title}", String(data["song"].get("title", "TRACK {n}")).replace("{n}", str(main._state.songs))))
	main._save_game()


func toast(text: String) -> void:
	_toast_text.text = text
	_toast_t = 0.0


## E at the camcorder.
func _on_spot(_id: String, _by: Node3D) -> void:
	if stage_name != "" or data.is_empty():
		return
	if unfilmed() <= 0:
		toast(_word("spot_hint"))
		print("[use] video: no song to film yet")
		return
	open_plan()


func open_plan() -> void:
	stage_name = "plan"
	main._set_mode("video")
	main._tag.visible = false
	main._hint.visible = false
	_plan.open(data, int(main._state.cash), song_title())


func _on_plan_cancel() -> void:
	stage_name = ""
	main._set_mode("play")


# ------------------------------------------------------------------ the shoot

func _on_shoot(chosen_picks: Dictionary) -> void:
	picks = chosen_picks
	_total = Score.price(data["rows"], picks)
	if _total > int(main._state.cash):
		stage_name = ""
		main._set_mode("play")
		return
	stage_name = "shoot"
	main._cut_to(_begin_shoot)


func _begin_shoot() -> void:
	var got := Score.chosen(data["rows"], picks)
	var lead: Node3D = main._actor
	_was = {"weapon": lead.weapon, "face": lead.face.expression if lead.face else ""}
	main.set_process(false)
	main._show_bars(1.0)             # the microphone's black bars put away now (a --do run can come straight from the mic)
	main._open_place(String(got["location"].get("place", "studio")))
	main._set_mode("video")
	main._tag.visible = false
	main._hint.visible = false
	_hidden = []
	for member: Dictionary in main._cast.get(main._place, []):
		var npc: Node3D = member["actor"]
		if npc.visible:
			npc.visible = false
			_hidden.append(npc)
	main._building.show_room(0)
	_stage = Stage.new()
	_stage.name = "VideoSet"
	main.add_child(_stage)
	_stage.build(main, got)
	main._room = main._building.room_at_pos(lead.position, 0)
	main._building.show_room(main._room)
	_seed = seed_override if seed_override >= 0 else 1000 + 7919 * (main._state.videos as Array).size() + int(main._state.songs)
	seed_override = -1
	_moments = []
	_pending = []
	_toast_t = 99.0
	_ui.open(data["words"], "%s   %s" % [song_title(), got["location"]["name"]])
	_take = Take.new()
	_take.name = "Take"
	add_child(_take)
	_take.setup(main, _stage, _ui, data, got, _seed, forced)
	_take.auto = auto_skill
	_take.wrapped.connect(_on_wrapped)
	forced = []
	var when := PackedStringArray()
	for m: Dictionary in _take.mishaps:
		when.append("%s at beat %.1f" % [m["m"]["id"], m["open"]])
	print("[shot] video: shooting %s at %s for %s (seed %d): %d moves, mishaps %s" % [song_title(), got["location"]["name"], _money(_total), _seed, _take.prompts.size(), ", ".join(when)])


## Keys during the take: a move's key or E goes to the take; Esc walks off the set.
func _unhandled_key_input(event: InputEvent) -> void:
	if stage_name != "shoot" or _take == null or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	if event.physical_keycode == KEY_ESCAPE:
		walk_off()
		return
	_take.press(OS.get_keycode_string(event.physical_keycode))


## WASD or the arrows, as a direction on screen.
func _held() -> Vector2:
	return Vector2(
		Input.get_axis("ui_left", "ui_right") + float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		Input.get_axis("ui_up", "ui_down") + float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))).limit_length(1.0)


## Catch the next moment wanted: the same picture the camera sees, without the viewfinder.
func _catch_one() -> void:
	if _pending.is_empty():
		return
	_catching = true
	var key: String = _pending.pop_front()
	var at := float(_take.beat()) if _take else 0.0
	_snap_cam.global_transform = main._camera.global_transform
	_snap_cam.fov = main._camera.fov
	_snap.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var image := _snap.get_texture().get_image()
	_moments.append({"key": key, "image": image, "beat": at})
	_catching = false


## Run the take on at the game's own pace (sixty steps a second) without
## drawing, catching its moments, until it reaches `target` (a beat) or ends.
func run_to(target: float) -> void:
	var steps := 0
	while _take and not _take.done and _take.beat() < target:
		_take.tick(1.0 / 60.0)
		if _take:
			_pending.append_array(_take.due_stills())
		while not _pending.is_empty():
			await _catch_one()
		steps += 1
		if steps % 900 == 0:
			await get_tree().process_frame


## Esc during the take: back to the studio, by the camcorder; nothing is spent.
func walk_off() -> void:
	if stage_name != "shoot":
		return
	stage_name = "leaving"
	main._cut_to(func() -> void:
		_strike()
		_back_to_studio()
		stage_name = ""
		main._set_mode("play")
		toast(_word("walked_off"))
		print("[shot] video: walked off the set; cash %d" % main._state.cash))


## CUT: the plan is paid for, the numbers are worked out, and on to the premiere.
func _on_wrapped() -> void:
	var kept: Dictionary = _take.kept
	var got := Score.chosen(data["rows"], picks)
	var before := int(main._state.cash)
	main._state.spend(_total)
	_result = Score.result(data, picks, kept, _total, _seed)
	var chosen_ids := {}
	for row: String in got:
		chosen_ids[row] = String(got[row]["id"])
	_record = {"song": (main._state.videos as Array).size() + 1, "title": song_title(), "where": String(got["location"]["name"]),
		"day": int(main._day) + 1, "picks": chosen_ids, "spent": _total, "looks": _result["looks"], "chaos": _result["chaos"],
		"swagger": _result["swagger"], "views": _result["views"], "paid": _result["paid"], "stars": _result["stars"],
		"mishaps": kept.get("mishaps", [])}
	print("[shot] video: wrapped. cash %d - %d = %d; moves %d hit (%d perfect), %d missed, %d off beat; looks %d, swagger %d, polish %d, chaos %d; buzz %d: %s views, pays %s, %d stars; mishaps %s" % [
		before, _total, main._state.cash, kept["hits"], kept["perfect"], kept["missed"], kept["flubs"], _result["looks"], _result["swagger"],
		_result["polish"], _result["chaos"], _result["buzz"], _result["views"], _money(int(_result["paid"])), _result["stars"], kept["mishaps"]])
	stage_name = "premiere"
	main._cut_to(_begin_premiere)


func _begin_premiere() -> void:
	_strike()
	_back_to_studio()
	main._set_mode("video")
	if main._actor.face:
		main._actor.face.set_expression("grin")
	var got := Score.chosen(data["rows"], picks)
	_premiere.open(_result, _pick_moments(String(got["location"]["name"])), data["words"], "%s   %s" % [_record["title"], _record["where"]])


## Up to four moments for the premiere, in the order they happened: the
## opening, the mishaps, the best moves, the close.
func _pick_moments(where: String) -> Array:
	var rank := func(key: String) -> int:
		if key == "open":
			return 0
		if key.contains(":handled") or key.contains(":missed"):
			return 1
		if key in ["move:cash", "move:aim", "move:chain"]:
			return 2
		if key.begins_with("move:"):
			return 3
		return 4
	var all := _moments.duplicate()
	all.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra: int = rank.call(a["key"])
		var rb: int = rank.call(b["key"])
		return ra < rb if ra != rb else float(a["beat"]) < float(b["beat"]))
	var keep := all.slice(0, 4)
	keep.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["beat"]) < float(b["beat"]))
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed + 3
	var out: Array = []
	for m: Dictionary in keep:
		var lines: Array = data["captions"].get(String(m["key"]), [])
		var caption := String(lines[rng.randi() % lines.size()]) if not lines.is_empty() else ""
		out.append({"image": m["image"], "caption": caption.replace("{place}", where), "key": m["key"]})
	return out


## Over: he is paid, the video is kept, and he is back in the game.
func _on_premiere_done() -> void:
	if stage_name != "premiere":
		return
	main._state.earn(int(_result.get("paid", 0)))
	main._state.add_video(_record)
	stage_name = ""
	main._set_mode("play")
	main._save_game()
	toast("%s  %s" % [_word("paid"), _money(int(_result.get("paid", 0)))])
	print("[shot] video: premiere over; paid %d, cash %d, videos %d" % [_result.get("paid", 0), main._state.cash, (main._state.videos as Array).size()])


## Take the set down and give him back as he was.
func _strike() -> void:
	_ui.close()
	if _take:
		_take.queue_free()
		_take = null
	if _stage:
		_stage.teardown()
		_stage = null
	for npc: Node3D in _hidden:
		if is_instance_valid(npc):
			npc.visible = true
	_hidden = []
	var lead: Node3D = main._actor
	lead.performing = false
	lead.aiming = false
	lead.aim_way = ""
	lead.weapon = String(_was.get("weapon", lead.weapon))
	if lead.face:
		lead.face.talking = false
		lead.face.set_expression(String(_was.get("face", "neutral")) if String(_was.get("face", "")) != "" else "neutral")
	lead.face_way("front")


## The studio, by the camcorder, the camera following him again.
func _back_to_studio() -> void:
	main._open_place("studio")
	main._actor.position = SPOT
	main._room = main._building.room_at_pos(SPOT, 0)
	main._building.show_room(main._room)
	main._set_camera("follow")
	main.set_process(true)


# ---------------------------------------------------------------- --do steps

func shot_step(bits: PackedStringArray) -> void:
	var what := bits[1] if bits.size() > 1 else ""
	var arg := bits[2] if bits.size() > 2 else ""
	if data.is_empty():
		print("[shot] video: no data")
		return
	match what:
		"song":
			record_song()
			print("[shot] video: songs %d, videos %d" % [main._state.songs, (main._state.videos as Array).size()])
		"cash":
			var want := int(arg)
			if want > int(main._state.cash):
				main._state.earn(want - int(main._state.cash))
			else:
				main._state.spend(int(main._state.cash) - want)
			print("[shot] video: cash %d" % main._state.cash)
		"spot":
			if main._place == "studio":
				main._actor.position = SPOT
				main._room = main._building.room_at_pos(SPOT, 0)
				main._building.show_room(main._room)
				main._follow(0.0, true)
		"plan":
			main._find_nearest()
			if main._nearest == spot:
				main._use_nearest()
			else:
				_on_spot("video", null)
			print("[shot] video: board %s" % ("up" if _plan.is_open() else "not up"))
		"buy":
			if not _plan.is_open():
				print("[shot] video: the board is not up")
				return
			for r: Dictionary in data["rows"]:
				if arg == "cheap":
					_plan.pick(String(r["id"]), 0)
				elif arg == "dear":
					_plan.pick(String(r["id"]), (r["choices"] as Array).size() - 1)
			if arg != "cheap" and arg != "dear":
				for pair: String in arg.split("+"):
					var kv := pair.split("=")
					if kv.size() == 2 and not _plan.pick_named(kv[0], kv[1]):
						print("[shot] video: no %s in %s" % [kv[1], kv[0]])
			print("[shot] video: picked %s; total %s of %s" % [_plan.picks, _money(_plan.total()), _money(int(main._state.cash))])
		"mishaps":
			forced = Array(arg.split("+"))
		"seed":
			seed_override = int(arg)
		"shoot":
			if not _plan.is_open():
				print("[shot] video: the board is not up")
			elif not _plan.can_shoot():
				print("[shot] video: cannot shoot: %s short" % _money(_plan.total() - int(main._state.cash)))
			else:
				_plan.press_shoot()
		"auto":
			auto_skill = float(arg)
			if _take:
				_take.auto = auto_skill
		"key":
			if _take:
				_take.press(arg)
		"walk":
			if _take:
				_take.hold_dir = Vector2(float(arg), 0.0)
		"until":
			if _take:
				await run_to(_take.end_beat() + 1.0 if arg == "end" else float(arg))
		"prompt":
			if _take:
				var next: float = _take.next_prompt()
				if next > 0.0:
					await run_to(next - 0.12)
		"at":
			if _take:
				var when: float = _take.mishap_beat(arg)
				if when < 0.0:
					print("[shot] video: no %s in this take" % arg)
				else:
					await run_to(when)
		"for":
			if _take:
				await run_to(_take.beat() + float(arg))
		"live":
			_live = true
			await main._wait(float(arg))
			_live = false
		"premiere":
			if _take:
				await run_to(_take.end_beat() + 1.0)
		"next":
			_premiere.next()
		"results":
			_premiere.results()
		"done":
			if _premiere.is_open():
				_premiere.results()
				_premiere.next()
		"esc":
			var press := InputEventKey.new()
			press.physical_keycode = KEY_ESCAPE
			press.keycode = KEY_ESCAPE
			press.pressed = true
			Input.parse_input_event(press)
			await main._wait(0.15)
		"state":
			pass
		"snap":
			for i in 3:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var path: String = main._shot_path.get_base_dir().path_join(arg + ".png")
			var err := get_viewport().get_texture().get_image().save_png(path)
			print("[shot] video: %s %s" % ["saved" if err == OK else "FAILED", path])
			return
		_:
			print("[shot] video: no step %s" % what)
	if _take and stage_name == "shoot":
		print("[shot] video: %s at beat %.2f; in shot %s (he is at x %.2f, the camera on %.2f); cash %d" % [what, _take.beat(), _take.in_shot,
			main._actor.position.x, _take.aim_x(), main._state.cash])
	elif what == "state" or what in ["next", "results", "done", "esc"]:
		print("[shot] video: stage '%s'; cash %d; songs %d; videos %d%s" % [stage_name, main._state.cash, main._state.songs, (main._state.videos as Array).size(),
			"; last: %s" % (main._state.videos as Array)[-1] if not (main._state.videos as Array).is_empty() else ""])


## For main.gd's last step before a picture: the camera is the shoot's own.
func hold_camera() -> void:
	if _take and _stage:
		_stage.face_cards(main._camera)
		main._face_cards()


static func _money(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return "$" + out


func _label(size: int, colour: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
