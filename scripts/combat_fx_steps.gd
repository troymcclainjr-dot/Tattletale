extends RefCounted
## The fx --do steps (combat.gd's step() hands them here), so tracers and breaking glass can be photographed
## and checked with nobody at the keyboard:
##
##   tracers:every | some | none   which rounds draw a tracer: every one, the game's rule (some), or none
##   glassseed:n               another way for the same shots to break the glass (0, the game's, is the default)
##   panes                     list the glass here: number, where, how big, which way it faces, what is left of it
##   pane:near | pane:x:y:z | pane:i     the pane the next steps work on: the nearest in sight not broken yet, the
##                             one nearest that point, or number i of the list
##   hitpane:spot[:n]          the cross on that spot of the pane and n rounds (1) from what he holds. A spot is
##                             middle, left, right, top, bottom, topleft, topright, bottomleft, bottomright,
##                             edge (by its left edge), corner (in its top left corner), or u/v: -1..1 across
##                             and up it as the camera sees it (0.6/-0.3)
##   paneeye[:dist]            later pictures look square at the pane from his side of it, dist metres off
##   panestrip:name:n[:spot]   n rounds at the pane one at a time (the first at spot, the rest wandering a little
##                             about it); after each, once the glass has landed, a picture of the pane: all of
##                             them in a row, the whole pane first, in name.png beside the shot
##   otherside[:dist]          stand him on the other side of the pane, about dist metres (2) from it
##   fireat:x:y:z[:n]          the cross on that point and n rounds (1) at it (to see him fire any way: at the camera)
##   glasscheck                the glass checks combatcheck runs, on their own (see check())

const ShotSteps := preload("res://scripts/shot_steps.gd")
const Glass := preload("res://scripts/combat_glass.gd")
const Fx := preload("res://scripts/combat_fx.gd")
const PlayerState := preload("res://scripts/player_state.gd")

const STEPS := ["tracers", "glassseed", "panes", "pane", "hitpane", "paneeye", "panestrip", "otherside", "fireat", "glasscheck"]
const SPOTS := {
	"middle": Vector2(0.0, 0.0), "left": Vector2(-0.5, 0.0), "right": Vector2(0.5, 0.0), "top": Vector2(0.0, 0.5),
	"bottom": Vector2(0.0, -0.5), "topleft": Vector2(-0.5, 0.5), "topright": Vector2(0.5, 0.5),
	"bottomleft": Vector2(-0.5, -0.5), "bottomright": Vector2(0.5, -0.5), "edge": Vector2(-0.9, 0.05),
	"corner": Vector2(-0.88, 0.86),
}
const STRIP_H := 320                # pixels: each picture of a strip

static var pane: MeshInstance3D     # the pane the steps work on


static func step(combat: Node, bits: PackedStringArray) -> void:
	var main: Node = combat.main
	match bits[0]:
		"tracers":
			combat.tracers = bits[1] if bits.size() > 1 else "some"
			print("[shot] tracers: %s" % combat.tracers)
		"glassseed":
			Glass.glass_seed = int(bits[1]) if bits.size() > 1 else 0
			print("[shot] glassseed: %d" % Glass.glass_seed)
		"panes":
			var i := 0
			for e: RefCounted in combat.world_for(main._building).glass():
				var mi: MeshInstance3D = e.mi
				var c: Vector3 = mi.global_transform * mi.get_aabb().get_center()
				var s: Vector3 = mi.get_aabb().size
				print("[shot] pane %d: %s at %.2f, %.2f, %.2f, %.2f x %.2f x %.2f, %s, %s%s" % [i, mi.name, c.x, c.y, c.z, s.x, s.y, s.z,
						"pane" if e.thin else "block", Glass.describe(mi), "" if mi.is_visible_in_tree() or mi.has_meta("broken") else ", hidden"])
				i += 1
		"pane":
			pane = _pick(combat, bits)
			if pane == null:
				print("[shot] pane: none found")
			else:
				var c: Vector3 = pane.global_transform * pane.get_aabb().get_center()
				print("[shot] pane: %s at %.2f, %.2f, %.2f (%s)" % [pane.name, c.x, c.y, c.z, Glass.describe(pane)])
		"hitpane":
			if not _ready_pane():
				return
			var n := int(bits[2]) if bits.size() > 2 else 1
			_follow_again(main)
			var at := spot(pane, bits[1] if bits.size() > 1 else "middle", main._camera)
			var clear := open(combat, pane, at)
			var went: int = await shoot_at(combat, at, n)
			var art := String(main._actor.gun_points().get("art", ""))
			print("[shot] hitpane %s: %d of %d went off, %s%s; last: %s; the pane: %s" % [bits[1] if bits.size() > 1 else "middle", went, n,
					"side-on" if art == "" else art, "" if clear else " (that spot is a hole, or hidden or out of his reach from here)",
					combat._said(combat.last), Glass.describe(pane)])
		"paneeye":
			if not _ready_pane():
				return
			eye_on(main, pane, float(bits[1]) if bits.size() > 1 else 0.0)
		"panestrip":
			if not _ready_pane():
				return
			await strip(combat, bits[1] if bits.size() > 1 else "panestrip", int(bits[2]) if bits.size() > 2 else 4, bits[3] if bits.size() > 3 else "middle")
		"otherside":
			if not _ready_pane():
				return
			await other_side(combat, pane, float(bits[1]) if bits.size() > 1 else 2.0)
		"fireat":
			var at := Vector3(float(bits[1]), float(bits[2]), float(bits[3])) if bits.size() > 3 else Vector3.ZERO
			var n := int(bits[4]) if bits.size() > 4 else 1
			var went: int = await shoot_at(combat, at, n)
			var gp: Dictionary = main._actor.gun_points()
			print("[shot] fireat: %d of %d went off, %s; last: %s" % [went, n, "side-on" if String(gp.get("art", "")) == "" else String(gp.get("art", "")), combat._said(combat.last)])
		"glasscheck":
			var problems: int = await check(combat, null)
			print("[shot] glasscheck: %d problems" % problems)


static func _ready_pane() -> bool:
	if pane == null or not is_instance_valid(pane):
		print("[shot] no pane chosen: pane:near first")
		return false
	return true


## pane:near, pane:x:y:z or pane:i.
static func _pick(combat: Node, bits: PackedStringArray) -> MeshInstance3D:
	var main: Node = combat.main
	var all: Array = combat.world_for(main._building).glass()
	if bits.size() < 2 or bits[1] == "near":
		var spot_at: Variant = combat._target_of("window")
		return combat._spot_pane if spot_at != null else null
	if bits.size() == 2:
		var i := int(bits[1])
		return all[i].mi if i >= 0 and i < all.size() else null
	var p := Vector3(float(bits[1]), float(bits[2]), float(bits[3]) if bits.size() > 3 else 0.0)
	var best: MeshInstance3D = null
	var gap := INF
	for e: RefCounted in all:
		var mi: MeshInstance3D = e.mi
		var d := (mi.global_transform * mi.get_aabb().get_center()).distance_to(p)
		if d < gap:
			gap = d
			best = mi
	return best


## The pane as the camera sees it: its middle `c`, `u` (half its width, pointing right on the screen), `v` (half its
## height, pointing up) and `n` (its face).
static func frame_of(mi: MeshInstance3D, cam: Camera3D) -> Dictionary:
	var box := mi.get_aabb()
	var s := box.size
	var k := 0 if s.x <= s.y and s.x <= s.z else (1 if s.y <= s.z else 2)
	var b := mi.global_transform.basis
	var a: Vector3 = b[(k + 1) % 3] * s[(k + 1) % 3] * 0.5
	var d: Vector3 = b[(k + 2) % 3] * s[(k + 2) % 3] * 0.5
	var up := a if absf(a.normalized().y) > absf(d.normalized().y) else d
	var across := d if up == a else a
	if up.y < 0.0:
		up = -up
	if cam and across.dot(cam.global_transform.basis.x) < 0.0:
		across = -across
	return {"c": mi.global_transform * box.get_center(), "u": across, "v": up, "n": (b[k] as Vector3).normalized()}


## A named spot on the pane (see SPOTS), or u/v.
static func spot(mi: MeshInstance3D, name: String, cam: Camera3D) -> Vector3:
	var f := frame_of(mi, cam)
	var at: Vector2 = SPOTS.get(name, Vector2.ZERO)
	if name.contains("/"):
		var uv := name.split("/")
		at = Vector2(float(uv[0]), float(uv[1]))
	return f["c"] + (f["u"] as Vector3) * at.x + (f["v"] as Vector3) * at.y


## Can a round be put on `p`, a point on pane `mi`, from here: glass there (not a hole), the pane the first thing
## the camera sees there, and nothing solid between his chest and it?
static func open(combat: Node, mi: MeshInstance3D, p: Vector3) -> bool:
	var main: Node = combat.main
	if Glass.in_hole(mi, p):
		return false
	var w: RefCounted = combat.world_for(main._building)
	var lead: Node3D = main._actor
	return _meets(w, main._camera.global_position, p, mi) and _meets(w, lead.global_position + Vector3(0.0, lead.height * 0.62, 0.0), p, mi)


## Going from `from` to `p` on pane `mi`, the first glass met is that pane (or one showing its glass), before
## anything solid.
static func _meets(w: RefCounted, from: Vector3, p: Vector3, mi: MeshInstance3D) -> bool:
	var look: Dictionary = w.trace(from, p + (p - from).normalized() * 0.05)
	for seen: Dictionary in look["panes"]:
		if Glass.in_hole(seen["entry"].mi, seen["pos"]):
			continue
		var it: MeshInstance3D = seen["entry"].mi
		var same := it == mi or Glass.same(it, mi) or it.global_position.distance_to(mi.global_position) < 0.01     # (or its twin)
		return same and not (look["hit"] and float(look["t"]) < float(seen["t"]))
	return false


## The camera back behind him at once (after a picture from somewhere else), so the cross is put as in the game.
static func _follow_again(main: Node) -> void:
	if main._cam_name == "follow":
		main._follow(0.0, true)


## The cross on `at` and n rounds at it (topped up first, so a strip never runs dry). How many went off.
static func shoot_at(combat: Node, at: Vector3, n: int) -> int:
	var main: Node = combat.main
	if main._actor.weapon == "":
		main._actor.weapon = "pistol"
	_follow_again(main)
	await combat._raise()
	var w: String = main._actor.weapon
	if int(main._state.loaded.get(w, 0)) < n:
		main._state.loaded[w] = maxi(int(PlayerState.CLIP[w]), n)
		main._state.touch()
	await combat._aim_on(at)
	return await combat._fire(n, at)


## Later pictures look square at the pane from his side of it.
static func eye_on(main: Node, mi: MeshInstance3D, dist: float) -> void:
	var f := frame_of(mi, main._camera)
	var c: Vector3 = f["c"]
	var n: Vector3 = f["n"]
	if n.dot(main._actor.global_position - c) < 0.0:
		n = -n
	var size := maxf((f["u"] as Vector3).length(), (f["v"] as Vector3).length()) * 2.0
	if dist <= 0.0:
		dist = clampf(size * 1.6, 1.4, 6.0)
	var eye := c + n * dist + Vector3.UP * minf(dist * 0.06, 0.25)       # low: under an awning, over a sill
	var look := c - Vector3.UP * minf((f["v"] as Vector3).length() * 0.2, 0.2)
	main._shot_eye = PackedFloat64Array([eye.x, eye.y, eye.z, look.x, look.y, look.z])
	ShotSteps._fov = 50.0
	print("[shot] paneeye: from %.2f, %.2f, %.2f" % [eye.x, eye.y, eye.z])


## A picture from the eye (as shot_steps.gd's snap takes one), handed back rather than saved.
static func grab(main: Node) -> Image:
	main.set_process(false)
	main._fade.color.a = 0.0
	main._change_room(main._building.room_at_pos(main._actor.position, main._room), true)
	if main._cam_name == "follow":
		main._follow(0.0, true)
	main._show_doors()
	var eye: PackedFloat64Array = main._shot_eye
	if eye.size() == 6:
		main._camera.fov = ShotSteps._fov
		main._camera.look_at_from_position(Vector3(eye[0], eye[1], eye[2]), Vector3(eye[3], eye[4], eye[5]))
		main._face_cards()
	for i in 6:
		await main.get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = main.get_viewport().get_texture().get_image()
	main.set_process(true)
	return img


## panestrip: the pane whole, then after each of n rounds, side by side in one picture.
static func strip(combat: Node, name: String, n: int, from: String) -> void:
	var main: Node = combat.main
	var cam: Camera3D = main._camera
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	var at0: Vector2 = SPOTS.get(from, Vector2.ZERO)
	if from.contains("/"):
		at0 = Vector2(float(from.split("/")[0]), float(from.split("/")[1]))
	var frames: Array = []
	var crop := Rect2i()
	for k in n + 1:
		if k > 0:
			_follow_again(main)
			var p := spot(pane, "%f/%f" % [at0.x, at0.y], cam)
			for tries in 16:                # the rest wander about the first, onto glass he can hit that is still there
				if k == 1 or open(combat, pane, p):
					break
				var at := (at0 + Vector2(rng.randf_range(-0.45, 0.45), rng.randf_range(-0.42, 0.42)) * (1.0 + float(tries) * 0.1)).clamp(Vector2(-0.9, -0.9), Vector2(0.9, 0.9))
				p = spot(pane, "%f/%f" % [at.x, at.y], cam)
			await shoot_at(combat, p, 1)
			print("[shot] panestrip %s %d: %s; the pane: %s" % [name, k, combat._said(combat.last), Glass.describe(pane)])
			for i in 70:                  # the glass lands
				await main.get_tree().process_frame
		var img: Image = await grab(main)
		if k == 0:
			crop = _crop_of(pane, cam, img.get_size())
		var part := img.get_region(crop)
		part.resize(int(float(crop.size.x) * float(STRIP_H) / float(crop.size.y)), STRIP_H, Image.INTERPOLATE_LANCZOS)
		frames.append(part)
	var gap := 8
	var wide := 0
	for f: Image in frames:
		wide += f.get_width() + gap
	var out := Image.create_empty(wide - gap, STRIP_H, false, (frames[0] as Image).get_format())
	out.fill(Color(0.1, 0.1, 0.12))
	var x := 0
	for f: Image in frames:
		out.blit_rect(f, Rect2i(Vector2i.ZERO, f.get_size()), Vector2i(x, 0))
		x += f.get_width() + gap
	var path := String(main._shot_path).get_base_dir().path_join(name + ".png")
	var err := out.save_png(path)
	print("[shot] panestrip: %s %s" % ["saved" if err == OK else "FAILED", path])


## Where the pane is in the picture, with room round it and below it (where the glass falls).
static func _crop_of(mi: MeshInstance3D, cam: Camera3D, size: Vector2i) -> Rect2i:
	var f := frame_of(mi, cam)
	var c: Vector3 = f["c"]
	var u: Vector3 = f["u"]
	var v: Vector3 = f["v"]
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p: Vector3 in [c + u + v, c - u + v, c + u - v, c - u - v]:
		var s := cam.unproject_position(p)
		lo = lo.min(s)
		hi = hi.max(s)
	var span := hi - lo
	lo -= Vector2(span.x * 0.22, span.y * 0.2)
	hi += Vector2(span.x * 0.22, span.y * 0.75)
	lo = lo.clamp(Vector2.ZERO, Vector2(size))
	hi = hi.clamp(Vector2.ZERO, Vector2(size))
	return Rect2i(Vector2i(lo), Vector2i(hi - lo).max(Vector2i(8, 8)))


## Stand him on the other side of the pane, about `dist` from it, where he can stand with room behind him (so his
## gun, drawn side-on, is not in the wall at his back).
static func other_side(combat: Node, mi: MeshInstance3D, dist: float) -> void:
	var main: Node = combat.main
	var lead: Node3D = main._actor
	var f := frame_of(mi, main._camera)
	var c: Vector3 = f["c"]
	var n: Vector3 = f["n"]
	if n.dot(lead.global_position - c) > 0.0:
		n = -n                          # towards the far side
	lead.areas = main._building.walk_areas()
	var flat := Vector2(n.x, n.z).normalized()
	var best := Vector2.INF
	for r: float in [dist, dist * 0.75, dist * 1.3, dist * 0.5, dist * 1.7]:
		for a: float in [0.0, 0.35, -0.35, 0.7, -0.7]:
			var s := Vector2(c.x, c.z) + flat.rotated(a) * r
			if lead.can_stand(s) and lead.can_stand(s + flat.rotated(a) * 0.7):
				best = s
				break
		if best != Vector2.INF:
			break
	if best == Vector2.INF:
		print("[shot] otherside: nowhere to stand behind %s" % mi.name)
		return
	main._teleport(Vector3(best.x, lead.global_position.y, best.y), true)
	main._aim_off()
	for i in 6:
		await main.get_tree().process_frame
	print("[shot] otherside: at %.2f, %.2f, in the %s" % [best.x, best.y, main._building.rooms[main._room]["name"]])


## The glass checks (combatcheck runs them after its own; glasscheck alone). On a pane in sight (one not broken
## yet, else `was`, the one combatcheck broke): a round at one side of it and a round at the other each break it,
## and after both the first hole is still a hole; no other pane here (the next one in the same window) broke unless a
## round went through it; a round through a hole breaks nothing more; the panes in the same spot show the same glass;
## once it has all come down, every piece of glass lies on something. A car's glass in sight takes a hole and stops
## the round. Prints each; returns how many problems.
static func check(combat: Node, was: MeshInstance3D) -> int:
	var main: Node = combat.main
	var problems := 0
	var cam: Camera3D = main._camera
	var w: RefCounted = combat.world_for(main._building)
	var spot_at: Variant = combat._target_of("window")
	var mi: MeshInstance3D = combat._spot_pane if spot_at != null else was
	var spots: Array = []
	if mi != null and is_instance_valid(mi):
		_follow_again(main)
		for uv: Vector2 in [Vector2(-0.45, 0.15), Vector2(0.45, -0.1), Vector2(-0.5, -0.45), Vector2(0.5, 0.45), Vector2(0.0, 0.55),
				Vector2(0.0, -0.55), Vector2(-0.75, 0.0), Vector2(0.75, 0.0)]:
			var p := spot(mi, "%f/%f" % [uv.x, uv.y], cam)
			if spots.size() < 2 and open(combat, mi, p) and (spots.is_empty() or (spots[0][0] as Vector2).distance_to(uv) > 0.5):
				spots.append([uv, p])
	if spots.size() < 2:
		print("[shot] glasscheck: no pane in sight with glass to shoot at two spots")
	else:
		var holes: Array = []
		var was_hits := {}                          # every pane here: how often it had been broken
		for e: RefCounted in w.glass():
			was_hits[e.mi] = Glass.hits(e.mi)
		var broken: Array = []                      # the panes the rounds broke
		for s: Array in spots:
			var before := Glass.hits(mi)
			await shoot_at(combat, s[1], 1)
			for g: Array in combat.last.get("glass", []):
				if bool(g[2]):
					broken.append(g[0])
			var at: Variant = _through(combat.last, mi)
			if at == null or Glass.hits(mi) != before + 1:
				print("[shot] glasscheck: the round at %s of %s did NOT break it (%s)" % [str(s[0]), mi.name, combat._said(combat.last)])
				problems += 1
			else:
				holes.append(at)
		var stray := 0                              # a pane beside it (another in the same window) broke with no round through it
		for e: RefCounted in w.glass():
			if was_hits.has(e.mi) and Glass.hits(e.mi) != int(was_hits[e.mi]) and not broken.any(func(b: MeshInstance3D) -> bool: return b == e.mi or Glass.same(b, e.mi)):
				stray += 1
		print("[shot] glasscheck: of the %d panes here, %d broke with no round through them: %s" % [was_hits.size(), stray, "ok" if stray == 0 else "WRONG"])
		if stray > 0:
			problems += 1
		var kept := 0
		for at: Vector3 in holes:
			if Glass.in_hole(mi, at):
				kept += 1
		print("[shot] glasscheck: %s: %d rounds broke it, %d of their holes still holes after both: %s; %s" % [mi.name, holes.size(),
				kept, "ok" if kept == holes.size() else "A HOLE MENDED", Glass.describe(mi)])
		if kept < holes.size():
			problems += 1
		if not holes.is_empty():
			var left := Glass.left(mi)
			var hits := Glass.hits(mi)
			var broke: bool = combat._break(mi, holes[0], ((holes[0] as Vector3) - cam.global_position).normalized())
			var same := not broke and is_equal_approx(Glass.left(mi), left) and Glass.hits(mi) == hits
			print("[shot] glasscheck: a round through the first hole: %s" % ("nothing more breaks: ok" if same else "IT BROKE MORE"))
			if not same:
				problems += 1
		var twins: Array = combat._twins(mi)
		var shared := 0
		for t: MeshInstance3D in twins:
			if Glass.same(mi, t) and not t.visible:
				shared += 1
		print("[shot] glasscheck: %d panes in the same spot, %d showing the same glass: %s" % [twins.size(), shared, "ok" if shared == twins.size() else "WRONG"])
		if shared < twins.size():
			problems += 1
	for i in 120:                                   # everything comes down
		await main.get_tree().process_frame
	var lying: Array = combat.fx.lying(Fx.PIECE)
	var falling: int = combat.fx.count(Fx.PIECE) - lying.size()
	var loose := 0
	for p: Vector3 in lying:
		if w.fall_hit(p + Vector3(0.0, 0.03, 0.0), p - Vector3(0.0, 0.05, 0.0)).is_empty():
			loose += 1
	print("[shot] glasscheck: %d pieces of glass lie about, %d on nothing, %d still falling: %s" % [lying.size(), loose, falling,
			"ok" if loose == 0 and falling == 0 else "WRONG"])
	if loose > 0 or falling > 0:
		problems += 1
	var car_at: Variant = combat._target_of("car")
	if car_at == null:
		print("[shot] glasscheck: no car glass in sight")
	else:
		var car: MeshInstance3D = combat._spot_pane
		var marks: int = Glass.cracks_on(car)
		await shoot_at(combat, car_at, 1)
		var stopped: bool = String(combat.last.get("what", "")) == "car glass"
		var marked: bool = Glass.cracks_on(car) > marks or marks >= 6
		print("[shot] glasscheck: car glass %s: %s, %s" % [car.name, "the round stopped there" if stopped else "THE ROUND WENT ON (%s)" % combat._said(combat.last),
				"a hole on it" if marked else "NO HOLE ON IT"])
		if not stopped or not marked:
			problems += 1
	return problems


## Where the last round broke `mi` (or a pane showing its glass), or null.
static func _through(shot: Dictionary, mi: MeshInstance3D) -> Variant:
	for g: Array in shot.get("glass", []):
		if bool(g[2]) and (g[0] == mi or Glass.same(g[0], mi)):
			return g[1]
	return null
