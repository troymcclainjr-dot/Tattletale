extends RefCounted
## Someone drawn only from the front, going any way he likes (combat_people.gd's frightened people): which way
## his card turns, and what it shows from behind.
##
## He faces the way he goes (the house rule). His card turns about its upright to face that way, up to TURN_MOST
## from facing the camera: going across the screen he is turned that far (and drawn a little narrower), going at
## the camera he faces it square. Going away from the camera the card turns on round and is seen from behind,
## and then it shows his back, made from his front drawing: mirrored (the card is seen from behind), his loose
## face left off, his face filled in with the colour of his hair (people_backs.py found which pixels that is
## and the colour: rig.json's "back"). Standing still he faces the camera, as he was drawn.

const TURN_MOST := 1.13          # radians (65 degrees): as far as the card turns from facing the camera, or from facing away
const SWAY := 0.12               # radians: going nearly straight across the screen, he keeps to the half he faces now

static var _made := {}           # a drawing's instance id: its back (null if the character has none)


## The turn of his card (paper_actor.gd's _yaw) that faces the floor direction `way` as nearly as it can,
## counted on from `now` so that it turns the short way round.
static func yaw_for(a: Node3D, way: Vector2, now: float) -> float:
	var want := wrapf(atan2(way.x, way.y) - a.global_rotation.y, -PI, PI)
	var size := absf(want)
	if size > TURN_MOST and size < PI - TURN_MOST:
		var away_now := cos(now) < 0.0
		var to_back := size > PI * 0.5 + (-SWAY if away_now else SWAY)
		want = signf(want) * (PI - TURN_MOST if to_back else TURN_MOST)
	return toward(now, want)


## As yaw_for, kept to one side: the side facing the camera (away false: no more than TURN_MOST from it) or the
## side facing away from it.
static func yaw_on_side(a: Node3D, way: Vector2, now: float, away: bool) -> float:
	var want := wrapf(atan2(way.x, way.y) - a.global_rotation.y, -PI, PI)
	var size := absf(want)
	var side := signf(want) if want != 0.0 else 1.0
	if away and size < PI - TURN_MOST:
		want = side * (PI - TURN_MOST)
	elif not away and size > TURN_MOST:
		want = side * TURN_MOST
	return toward(now, want)


## The turn `want` (radians, any number of turns round) counted on from `now`, the short way round.
static func toward(now: float, want: float) -> float:
	return now + wrapf(want - now, -PI, PI)


## The floor direction his card faces at turn `yaw`.
static func facing(a: Node3D, yaw: float) -> Vector2:
	var t: float = a.global_rotation.y + yaw
	return Vector2(sin(t), cos(t))


## Does this character turn his card to go about (drawn from the front only, with a back made for him)?
static func turns(a: Node3D) -> bool:
	return a._views.size() == 1 and a._rig.has("back")


## Each frame after he walks: from behind, his back; from in front, his drawing and his face.
static func show_side(a: Node3D) -> void:
	var away := cos(float(a._yaw)) < 0.0
	for param: String in ["art", "under"]:
		if param == "under" and not bool(a._mat.get_shader_parameter("has_under")):
			continue
		var tex: Texture2D = a._mat.get_shader_parameter(param)
		if tex == null:
			continue
		var is_back := tex.has_meta("people_back_of")
		if away and not is_back:
			var back := back_of(a, tex)
			if back:
				a._put(param, back)
		elif not away and is_back:
			a._put(param, tex.get_meta("people_back_of"))
	if a.face:
		a.face.visible = not away and a._views[a.view]["data"].has("face")


## His drawing as it was, his face back on (he is calm again, or down).
static func front_again(a: Node3D) -> void:
	for param: String in ["art", "under"]:
		var tex: Texture2D = a._mat.get_shader_parameter(param)
		if tex and tex.has_meta("people_back_of"):
			a._put(param, tex.get_meta("people_back_of"))
	if a.face:
		a.face.visible = a._views[a.view]["data"].has("face")


## The back made from drawing `tex`: once for each drawing, kept for everyone who wears it.
static func back_of(a: Node3D, tex: Texture2D) -> Texture2D:
	var key := tex.get_instance_id()
	if _made.has(key):
		return _made[key]
	var out: Texture2D = null
	var info: Dictionary = a._rig.get("back", {})
	var path: String = a._dir.path_join(String(info.get("mask", "")))
	if not info.is_empty() and ResourceLoader.exists(path):
		var img := tex.get_image()
		var mask: Image = (load(path) as Texture2D).get_image()
		if img and mask:
			img = img.duplicate()
			for each: Image in [img, mask]:
				if each.is_compressed():
					each.decompress()
				each.clear_mipmaps()
				if each.get_format() != Image.FORMAT_RGBA8:
					each.convert(Image.FORMAT_RGBA8)
			if mask.get_size() != img.get_size():
				mask.resize(img.get_width(), img.get_height(), Image.INTERPOLATE_NEAREST)
			var used := mask.get_used_rect()
			if used.has_area():
				var hair: Array = info.get("hair", [40.0, 32.0, 30.0])
				var fill := Image.create(used.size.x, used.size.y, false, Image.FORMAT_RGBA8)
				fill.fill(Color8(int(hair[0]), int(hair[1]), int(hair[2])))
				img.blit_rect_mask(fill, mask.get_region(used), Rect2i(Vector2i.ZERO, used.size), used.position)
				img.generate_mipmaps()
				out = ImageTexture.create_from_image(img)
				out.set_meta("people_back_of", tex)
	_made[key] = out
	return out
