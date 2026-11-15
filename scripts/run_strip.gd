extends RefCounted
## Frames through one run cycle, side by side, to judge the sprint (`--strip=` in main.gd).
## Motion cannot be photographed, so the character is frozen at points of the cycle instead.
##
##   --strip=weapons:rigs:views[:frames]        e.g.  --strip=none+ak:e:s+f+b:8
##
## For each rig, weapon and view (s side, m side facing left, f front, b back) the character
## sprints on a plain backdrop and is frozen at `frames` evenly spaced points of one run cycle
## (two steps, starting with his feet furthest apart); each is photographed square-on and close,
## and cropped. One sheet for each, beside the shot: <shot>_<rig>_<weapon>_<view>.png, the frames
## left to right at full size (500 pixels to the metre). The shot itself is all the sheets at a
## quarter of that, one above the other. A view the drawing does not have is left out.
## Clothes put on first with --do=outfit:... are worn (a character whose clothes are layers).

const PaperActor := preload("res://scripts/paper_actor.gd")
const ORIGIN := Vector3(0, 900, 0)    # far above the places, out of everything's way
const TALL := 1.8                      # metres of picture, from just under his feet
const WIDE := 2.0                      # metres across each frame: his lean, his arms and what trails behind him
const FOV := 24.0
const VIEWS := {"s": ["side", false, Vector2(1, 0)], "m": ["side", true, Vector2(-1, 0)], "f": ["front", false, Vector2(0, 1)], "b": ["back", false, Vector2(0, -1)]}


static func shoot(host: Node3D, camera: Camera3D, spec: String, out: String, outfit: Dictionary) -> void:
	var bits := spec.split(":")
	var weapons := bits[0].split("+")
	var rigs := (bits[1] if bits.size() > 1 else "e").split(",")
	var views := (bits[2] if bits.size() > 2 else "s+f+b").split("+")
	var frames := maxi(int(bits[3]) if bits.size() > 3 else 8, 1)
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color(0.56, 0.6, 0.66)
	grey.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	Kit.box(host, Vector3(60, 30, 0.1), ORIGIN + Vector3(0, 0, -1.2), grey)
	var floor_look := StandardMaterial3D.new()
	floor_look.albedo_color = Color(0.44, 0.47, 0.52)
	floor_look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	Kit.box(host, Vector3(60, 0.1, 6), ORIGIN + Vector3(0, -0.05, 0), floor_look)
	camera.fov = FOV
	var far := TALL * 0.5 / tan(deg_to_rad(FOV * 0.5))
	var mid := ORIGIN + Vector3(0, TALL * 0.5 - 0.06, 0)
	camera.look_at_from_position(mid + Vector3(0, 0, far), mid)
	var sheets: Array[Image] = []
	for rig: String in rigs:
		for weapon: String in weapons:
			for v: String in views:
				if not VIEWS.has(v):
					continue
				var way: Array = VIEWS[v]
				var who: Node3D = PaperActor.new()
				host.add_child(who)
				if not who.set_rig("res://assets/characters/" + rig):
					who.queue_free()
					continue
				if who.has_wardrobe() and not outfit.is_empty():
					who.wear(outfit)
				who.position = ORIGIN
				who.areas = [Rect2(-9999, -9999, 19998, 19998)]
				who.weapon = "" if weapon == "none" else weapon
				who.face_way(way[0], way[1])
				for f in 90:
					who.walk(Vector2.ZERO, Vector2.ZERO, 1.0 / 60.0)
				if who.view != way[0]:
					print("[shot] strip: %s has no %s drawing" % [rig, way[0]])
					who.queue_free()
					continue
				var dir: Vector2 = way[2]
				who.sprinting = true
				for f in 45:
					who.walk(dir, dir, 1.0 / 60.0)
				var rate: float = who.STEP_RATE * maxf(who.speed, 1.0) * who.RUN_STEPS      # radians of cycle a second, flat out
				who.walk(dir, dir, fposmod(-float(who._phase), TAU) / rate)                # on to the start of a cycle
				var sheet: Image = null
				for k in frames:
					if k > 0:
						who.walk(dir, dir, TAU / rate / frames)
					who.position = ORIGIN
					for i in 3:
						await host.get_tree().process_frame
					await RenderingServer.frame_post_draw
					var shot := host.get_viewport().get_texture().get_image()
					var px := float(shot.get_height()) / TALL
					var w := int(WIDE * px)
					var x := int(shot.get_width() * 0.5 - w * 0.5)
					var frame := shot.get_region(Rect2i(x, 0, w, shot.get_height()))
					if sheet == null:
						sheet = Image.create(w * frames, shot.get_height(), false, frame.get_format())
					sheet.blit_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), Vector2i(w * k, 0))
				who.queue_free()
				if sheet:
					var path := "%s_%s_%s_%s.png" % [out.get_basename(), rig, weapon, v]
					print("[shot] strip: %s %s" % ["saved" if sheet.save_png(path) == OK else "FAILED", path])
					sheets.append(sheet)
	if sheets.is_empty():
		return
	var small: Array[Image] = []
	var width := 0
	var height := 0
	for sheet: Image in sheets:
		var s: Image = sheet.duplicate()
		s.resize(sheet.get_width() / 4, sheet.get_height() / 4, Image.INTERPOLATE_BILINEAR)
		small.append(s)
		width = maxi(width, s.get_width())
		height += s.get_height()
	var all := Image.create(width, height, false, small[0].get_format())
	all.fill(Color(0.1, 0.1, 0.12))
	var y := 0
	for s: Image in small:
		all.blit_rect(s, Rect2i(Vector2i.ZERO, s.get_size()), Vector2i(0, y))
		y += s.get_height()
	print("[shot] %s %s" % ["saved" if all.save_png(out) == OK else "FAILED", out])
