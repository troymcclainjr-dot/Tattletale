extends RefCounted
## Every game-state read the HUD makes goes through here, so the HUD only depends on the [HUD]
## names in g.gd / crime.gd and never crashes on missing or stub state (empty G.C, null G.car,
## no W.dan, no camera...). Static only: `const St := preload("res://scripts/ui/hud_state.gd")`.
##
## The autoloads are looked up at run time (g() / audio()) instead of naming the G global, so the
## HUD scripts compile even while g.gd is being edited (or has an error) and pass --check-only.

static var _g: Node = null
static var _audio: Node = null


static func _autoload(n: String) -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root.get_node_or_null(n)
	return null


## The G autoload (or null).
static func g() -> Node:
	if _g == null or not is_instance_valid(_g):
		_g = _autoload("G")
	return _g


static func audio() -> Node:
	if _audio == null or not is_instance_valid(_audio):
		_audio = _autoload("Audio")
	return _audio


static func sfx(name: String, arg = null) -> void:
	var a := audio()
	if a and a.has_method("sfx"):
		a.sfx(name, arg)


## Call a G function if G has it (callbacks from the HUD to the game).
static func call_g(fn: String, args: Array = []) -> Variant:
	var gg := g()
	if gg and gg.has_method(fn):
		return gg.callv(fn, args)
	push_warning("Hud: G.%s() is missing" % fn)
	return null


static func gv(key: String, def = null):
	return field(g(), key, def)


## A constant of g.gd (RANKS, STAGES, TOLD_NAMES, MAILDROP).
static func gconst(key: String, def = null):
	var gg := g()
	if gg == null:
		return def
	var v = gg.get(key)
	if v == null and gg.get_script():
		v = (gg.get_script() as Script).get_script_constant_map().get(key)
	return def if v == null else v


## o.key for a Dictionary or an Object, def when missing/null.
static func field(o, key: String, def = null):
	if o == null:
		return def
	if o is Dictionary:
		var v = o.get(key, def)
		return def if v == null else v
	if o is Object:
		if not is_instance_valid(o):
			return def
		var v = o.get(key)
		return def if v == null else v
	return def


## x/z of anything position-like: {x, z} dict or object, Vector3, Vector2 (x, y) or [x, z].
static func xz(o) -> Variant:
	if o == null:
		return null
	if o is Vector3:
		return Vector2(o.x, o.z)
	if o is Vector2:
		return o
	if o is Array or o is PackedFloat32Array or o is PackedFloat64Array:
		return Vector2(float(o[0]), float(o[1])) if o.size() >= 2 else null
	var x = field(o, "x")
	var z = field(o, "z")
	if x == null or z == null:
		return null
	return Vector2(float(x), float(z))


static func s():
	return gv("S")


static func mode() -> String:
	return str(field(s(), "mode", "title"))


static func live() -> bool:
	var m := mode()
	return m == "play" or m == "puzzle"


static func lock_on() -> bool:
	var l = field(s(), "lock")
	return l != null and not (l is bool and l == false)


static func bino_on() -> bool:
	return bool(field(s(), "bino_on", false))


static func num(key: String, def := 0.0) -> float:
	var v = field(s(), key, def)
	return float(v) if (v is int or v is float) else def


## Crimes in G.C order (the JS Object.values(C) order), skipping anything that isn't a crime.
static func crimes() -> Array:
	var out := []
	var c = gv("C", {})
	if not (c is Dictionary):
		return out
	for k in c:
		var v = c[k]
		if v is Object and is_instance_valid(v):
			out.append(v)
	return out


static func crime(id: String):
	var c = gv("C", {})
	if c is Dictionary and c.has(id) and c[id] is Object:
		return c[id]
	return null


static func active(c) -> bool:
	return bool(field(c, "active", false))


static func cur(c) -> Dictionary:
	var steps = field(c, "steps", [])
	if not (steps is Array) or steps.is_empty():
		return {}
	var gg := g()
	var st = gg.cur(c) if gg else {}
	return st if st is Dictionary else {}


static func kind(st: Dictionary) -> String:
	return str(st.get("k", ""))


static func step_text(st: Dictionary) -> String:
	if st.is_empty():
		return ""
	var gg := g()
	if gg == null:
		var t = st.get("t", "")
		return str(t.call()) if t is Callable else str(t)
	return str(gg.step_text(st))


static func short(c) -> String:
	return str(field(c, "who", "")).split(" ·")[0]


static func mark(c) -> Vector3:
	var gg := g()
	var p = gg.mark_pos(c) if gg else (c.target() if c.has_method("target") else Vector3.ZERO)
	return p if p is Vector3 else Vector3.ZERO


static func left(c) -> float:
	return float(field(c, "left", INF))


static func dan():
	return field(gv("W"), "dan")


static func dan_lost() -> bool:
	return bool(field(dan(), "lost", false))


static func told(id: String) -> bool:
	var t = field(s(), "told", {})
	if t is Dictionary:
		return t.has(id) and t[id] != false
	if t is Array:
		return t.has(id)
	return false


static func told_count(ids: Array) -> int:
	var n := 0
	for id in ids:
		if told(str(id)):
			n += 1
	return n


static func cops_active() -> bool:
	return active(crime("cops"))


static func phones() -> Array:
	var out := []
	var ph = field(gv("W_"), "phones", [])
	if ph is Array:
		for p in ph:
			var v = xz(p)
			if v != null:
				out.append(v)
	return out


static func car_xz() -> Variant:
	return xz(gv("car"))


static func camera() -> Camera3D:
	var gg := g()
	var cam = gg.camera() if gg and gg.has_method("camera") else null
	if cam == null:
		var ml := Engine.get_main_loop()
		if ml is SceneTree:
			cam = (ml as SceneTree).root.get_viewport().get_camera_3d()
	return cam if cam is Camera3D and is_instance_valid(cam) else null


static func need_list() -> Array:
	var gg := g()
	var n = gg.need_list() if gg else []
	return n if n is Array else []


static func stage_name() -> String:
	var st := int(num("stage", 1))
	var info = (gconst("STAGES", {}) as Dictionary).get(st, {})
	return str(info.get("name", "Stage %d" % st))


static func rank() -> String:
	var sc := int(num("score", 0))
	var name := ""
	for r in gconst("RANKS", []):
		if sc >= int(r[0]):
			name = str(r[1])
	return name


static func told_name(id: String) -> String:
	return str((gconst("TOLD_NAMES", {}) as Dictionary).get(id, id))
