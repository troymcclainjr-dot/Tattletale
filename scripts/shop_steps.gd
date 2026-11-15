extends RefCounted
## --do steps for the gun store (plans/gunstore.gd, gun_shop.gd) and the travel list (travel_menu.gd), for a
## screenshot run (tools/shot.py). main.gd's _take_shot hands these here.
##
##   shop:counter              E at the counter, as he would do it: he is stood on the BUY spot and E opens the list
##   shop:buy:<id>             buy one row of the list, as a click on it would (uzi, ak, pistol, rounds:pistol ...)
##   shop:close                close the list (the game goes back to play, and saves)
##   shop:state                print his cash, the weapons he owns and his rounds for each
##   shop:shoot:<lane>[:n[:cm]] stand him in that booth of the range (1 to 3), the pistol up if his hands are empty,
##                             the cross on the middle of its target, and fire n times (3): prints the holes (and
##                             how many of fx's own marks were hidden on the paper: one a hole). With
##                             cm, each shot is aimed on its own somewhere up to that far off the middle (the same
##                             spots every run), as a hand would wander
##   shop:fresh:<lane>[:s]     E in that booth: the target runs in, gets a fresh paper and runs back out. Waits
##                             till it is home again, or only s seconds (to catch it on the way)
##   shop:click:<row>          a real left click on that row of the counter's list (1 is the top), sent in as the
##                             mouse sends one
##   list:fill:<n>             the travel list holds n rows: the real places, then made-up ones (MADE-UP PLACE 17)
##   list:size:<w>:<h>         the window that size, as a smaller screen has it (list:size:1280:720)
##   list:click:<i>            a real left click on row i of the open travel list (0 is the top; a real place: he goes)
##
## Every line printed starts "[shot] shop:" or "[shot] list:".


static func step(main: Node, bits: PackedStringArray) -> void:
	if bits[0] == "list":
		await _list(main, bits)
		return
	if bits.size() > 1 and bits[1] == "state":          # anywhere: after a save is continued, say
		print("[shot] shop: %s; cash %d (at %s)" % [_state(main), int(main._state.cash), main._place])
		return
	var shop: Node = main._building.get_node_or_null("GunShop") if main._building else null
	if shop == null:
		print("[shot] shop: there is no gun store here (%s)" % main._place)
		return
	match bits[1] if bits.size() > 1 else "":
		"counter":
			for thing in main._usables:
				if is_instance_valid(thing) and "id" in thing and String(thing.id) == "gun:counter":
					main._actor.global_position = Vector3(thing.use_spot().x, main._actor.global_position.y, thing.use_spot().z)
			main._find_nearest()
			var near: String = main._nearest.use_name() if main._nearest else "nothing in reach"
			main._use_nearest()
			await main.get_tree().process_frame
			print("[shot] shop: E at %s: the list is %s, the game is in %s; %s" % [near, "open" if shop.counter.is_open() else "SHUT", main._mode, _rows(shop)])
		"buy":
			if not shop.counter.is_open():
				shop.open_counter()
			var want := bits[2] if bits.size() > 2 else ""
			if bits.size() > 3:                  # rounds:pistol came in as two bits
				want += ":" + bits[3]
			var row := -1
			for i in shop.counter.rows.size():
				if String(shop.counter.rows[i]["id"]) == want:
					row = i
			var cash_was := int(main._state.cash)
			if row < 0:
				print("[shot] shop: %s is not on the list (%s)" % [want, _rows(shop)])
				return
			shop.counter.pick(row)
			await main.get_tree().process_frame
			print("[shot] shop: bought %s: \"%s\"; cash %d -> %d; %s" % [want, shop.counter._said.text, cash_was, int(main._state.cash), _state(main)])
		"close":
			shop.counter.close()
			await main.get_tree().process_frame
			print("[shot] shop: list closed: the game is in %s; saved to %s" % [main._mode, main._save_path if main._save_path != _const(main, "SAVE") else "nowhere (a screenshot run keeps away from the real save)"])
		"shoot":
			var i := int(bits[2]) - 1 if bits.size() > 2 else 0
			var n := int(bits[3]) if bits.size() > 3 else 3
			var spread := float(bits[4]) / 100.0 if bits.size() > 4 else 0.0
			var lane: Dictionary = shop.lanes[i]
			main._teleport(lane["spot"], true)
			if main._actor.weapon == "":
				main._actor.weapon = "pistol"
			for k in 6:
				await main.get_tree().process_frame
			var bull: Vector3 = shop.bull_of(i)
			var flat: Basis = (lane["paper"] as Node3D).global_transform.basis.orthonormalized()
			var rng := RandomNumberGenerator.new()
			rng.seed = 1000 + i                   # the same group every run
			var holes := int(lane["hits"])
			for s in (n if spread > 0.0 else 1):  # with a spread, each shot is aimed on its own, up to that far off the middle
				var off := Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * spread
				var mark := bull + flat.x * off.x + flat.y * off.y
				for k in (30 if s == 0 else 10):  # the cross on it, while he turns and brings the gun up
					main._aim_at(main._camera.unproject_position(mark))
					await main.get_tree().process_frame
				await main._combat.step(PackedStringArray(["fire", "1" if spread > 0.0 else str(n)]))
			for k in 4:
				await main.get_tree().process_frame
			print("[shot] shop: lane %d: %d new holes in the paper, %d in all, score %d (he aimed at %.2f, %.2f, %.2f; aim %s); fx marks hidden on it %d" % [i + 1,
				int(lane["hits"]) - holes, int(lane["hits"]), int(lane["score"]), bull.x, bull.y, bull.z, main._actor.aim_way if main._actor.aim_way != "" else "side-on",
				int(lane["hidden"])])
		"fresh":
			var i := int(bits[2]) - 1 if bits.size() > 2 else 0
			var wait := float(bits[3]) if bits.size() > 3 else 5.0
			var lane: Dictionary = shop.lanes[i]
			var holes := int(lane["hits"])
			for thing in main._usables:
				if is_instance_valid(thing) and "id" in thing and String(thing.id) == "range:%d" % (i + 1):
					main._teleport(Vector3(thing.use_spot().x, 0.0, thing.use_spot().z), true)
			main._find_nearest()
			var near: String = main._nearest.use_name() if main._nearest else "nothing in reach"
			main._use_nearest()
			var started := Time.get_ticks_msec()
			await main.get_tree().process_frame
			while float(lane["run"]) >= 0.0 and Time.get_ticks_msec() - started < int(wait * 1000.0):
				await main.get_tree().process_frame
			var carrier: Node3D = lane["carrier"]
			var gone := float(lane["near"]) - float(lane["home"])
			var where := "home again" if float(lane["run"]) < 0.0 else ("on its way %s, %.0f%% of the way in" % ["out" if lane["back"] else "in", 100.0 * (carrier.position.z - float(lane["home"])) / gone])
			print("[shot] shop: E at %s in lane %d: after %.1f s the target is %s; %d holes before, %d now" % [near, i + 1,
				(Time.get_ticks_msec() - started) / 1000.0, where, holes, int(lane["hits"])])
		"click":
			var i := int(bits[2]) - 1 if bits.size() > 2 else 0
			if not shop.counter.is_open() or i < 0 or i >= shop.counter.rows.size():
				print("[shot] shop: no row %d on the counter's list to click" % (i + 1))
				return
			var want := String(shop.counter.rows[i]["id"])
			var cash_was := int(main._state.cash)
			for k in 3:                           # the list lays its rows out on the frames after it is shown
				await main.get_tree().process_frame
			await _click(main, shop.counter._box.get_child(i))
			print("[shot] shop: clicked row %d (%s): \"%s\"; cash %d -> %d; %s" % [i + 1, want, shop.counter._said.text, cash_was, int(main._state.cash), _state(main)])
		_:
			print("[shot] shop: unknown step %s" % ":".join(bits))


## A real left click, down and up, on the middle of a control: sent in at the window's own pixels, as the mouse
## sends one, so the GUI finds what is under it.
static func _click(main: Node, target: Control) -> void:
	var at: Vector2 = main.get_viewport().get_final_transform() * target.get_global_rect().get_center()
	for down: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = down
		click.position = at
		click.global_position = at
		Input.parse_input_event(click)
		await main.get_tree().process_frame


static func _rows(shop: Node) -> String:
	var out := PackedStringArray()
	for row: Dictionary in shop.counter.rows:
		out.append("%s %s $%d" % [row["id"], row["name"], int(row["price"])])
	return "rows: " + (", ".join(out) if not out.is_empty() else "none")


static func _state(main: Node) -> String:
	var state: RefCounted = main._state
	var rounds := PackedStringArray()
	for w: String in ["pistol", "uzi", "ak"]:
		rounds.append("%s %d+%d" % [w, int(state.loaded.get(w, 0)), int(state.spare.get(w, 0))])
	return "owns %s; rounds (loaded+spare) %s; in his hands: %s" % [", ".join(PackedStringArray(state.owned)), ", ".join(rounds),
		String(main._actor.weapon) if String(main._actor.weapon) != "" else "nothing"]


static func _list(main: Node, bits: PackedStringArray) -> void:
	match bits[1] if bits.size() > 1 else "":
		"fill":
			var n := int(bits[2]) if bits.size() > 2 else 30
			var real: Array = _const(main, "PLACES")
			var rows: Array = real.slice(0, mini(n, real.size()))
			for k in range(rows.size(), n):
				rows.append({"id": "made_up_%d" % (k + 1), "name": "MADE-UP PLACE %d" % (k + 1), "note": "NOT BUILT YET"})
			main._travel.set_places(rows)
			print("[shot] list: %d rows (%d real, %d made up)" % [rows.size(), mini(n, real.size()), rows.size() - mini(n, real.size())])
		"size":
			var want := Vector2i(int(bits[2]), int(bits[3])) if bits.size() > 3 else Vector2i(1280, 720)
			DisplayServer.window_set_size(want)
			for k in 12:
				await main.get_tree().process_frame
			print("[shot] list: the window is %s, the picture %s" % [DisplayServer.window_get_size(), main.get_viewport().get_texture().get_size()])
		"click":
			var i := int(bits[2]) if bits.size() > 2 else 0
			var rows: Array = main._travel._rows
			if not main._travel.is_open() or i < 0 or i >= rows.size():
				print("[shot] list: no row %d on the travel list to click" % i)
				return
			for k in 3:                           # the list lays its rows out on the frames after it opens
				await main.get_tree().process_frame
			var was := String(main._place)
			var want := String(main._travel._places[i]["id"])
			await _click(main, rows[i])
			for k in 60:
				await main.get_tree().process_frame
			print("[shot] list: clicked row %d (%s): the list is %s; the place was %s, now %s" % [i, want, "open" if main._travel.is_open() else "shut", was, main._place])
		_:
			print("[shot] list: unknown step %s" % ":".join(bits))


## One of main.gd's constants (PLACES, SAVE).
static func _const(main: Node, name: String) -> Variant:
	return (main.get_script() as Script).get_script_constant_map()[name]
