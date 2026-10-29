extends Node
## G: the game's shared state and core helpers (state.js + the shared parts of crimes-core.js),
## the main loop and the input (game.js). Every JS global lives here under the same name
## (functions in snake_case), so the port reads like the original: S.score -> G.S.score,
## startCrime(id) -> Crimes.start_crime(id).
##
## CONTRACT. The HUD and audio ports rely on everything marked [HUD]. The simulation port
## owns this file and may add anything, but must keep those names, types and meanings.

# ---------------------------------------------------------------- state
class GameState:
	var mode := "title"      # [HUD] "title" | "play" | "puzzle" | "cut" | "video" | "over" | "pause"
	var score := 0           # [HUD]
	var strikes := 0         # [HUD] crimes that got away (3 = shift over)
	var busts := 0           # [HUD]
	var still := 0           # [HUD] times Gary was reported (he's still there)
	var time := 0.0          # [HUD] seconds on the block
	var stage := 1           # [HUD]
	var told := {}           # [HUD] set of crime ids told on: id -> true
	var bino_on := false     # [HUD]
	var lock = null          # [HUD] Dictionary while a minigame/scene lock is up, else null
	var pz = null            # [HUD] {"focus": Crime, "kind": String, "done": bool} during a puzzle
	var music_on := true     # [HUD]
	var case_no := 0
	var spawn_t := 5.0
	var first_ev := true
	var ev := 0.0
	var ev_id = null
	var next = "granny"
	var gary_t := 0.0
	var finale_queued := false
	var fin = null


class PlayerState:
	var x := 0.6             # [HUD]
	var z := -4.0            # [HUD]
	var yaw := PI / 2        # [HUD]
	var phase := 0.0
	var moving := false
	var run := false


var clock := 0.0
var S := GameState.new()     # [HUD]
var P := PlayerState.new()   # [HUD]
var cam_yaw := PI / 2        # [HUD] third-person camera heading
var cam_pitch := 0.32
var bino_yaw := 0.0          # [HUD] binocular heading
var bino_pitch := 0.0
var bino_fov := 16.0
var C := {}                  # [HUD] id -> Crime
var W := {}                  # world refs; [HUD] reads W.dan.escort / W.dan.lost / W.dan.x / W.dan.z
var W_ := {}                 # [HUD] W_.phones: Array of objects/dicts with x, z
var car = null               # [HUD] car.x, car.z

# the world (state.js build): collision, the cast, the scene
var SOLIDS: Array = []       # Solid
var OCCLUDERS: Array = []    # AABB of each occluder box (the StaticBody3D boxes are what rays hit)
var bodies: Array = []       # Body
var car_body: Body
var player_body: Body
var tp: Puppet
var ricky: Puppet
var granny: Puppet
var gary: Puppet
var timmy: Puppet
var mailman: Puppet
var dan: Puppet
var steve: Puppet
var talkers: Array = []
var smoke: CPUParticles3D
var world_root: Node3D
var cam: Camera3D
var cam_attr: CameraAttributesPractical
var cam_pos := Vector3.ZERO
var cam_look := Vector3.ZERO
var built := false

# input: simulated keys (tests and debug, like the JS K) on top of the real input actions
var K := {}
var drag := false
var manual := false          # true: tests drive tick() themselves
var cam_override = null      # {"p": Vector3, "l": Vector3, "f": float}: a fixed camera (screenshots)
var bino_label := ""         # what the binoculars said last (tests, debugging)

# ---------------------------------------------------------------- constants (crimes-core.js)
const RANKS := [[0, "Hall Monitor"], [600, "Block Captain"], [1500, "Neighborhood Watch"], [3000, "Precinct Pest"], [5000, "Snitch 4 Life"]]  # [HUD]
const STAGES := {  # [HUD]
	1: {"pool": ["ricky", "granny", "timmy", "lawn", "mail"], "first": "granny", "name": "Stage 1", "sub": "Snitch Season"},
	2: {"pool": ["mama", "daddy", "squirrel", "baby"], "first": "daddy", "name": "Stage 2", "sub": "Verse 3: everybody he's ever told on"},
}
const TOLD_NAMES := {"ricky": "Ricky", "granny": "Grandma", "timmy": "Timmy", "lawn": "Lawn", "mail": "Mailman", "gary": "Gary", "mama": "Mama", "daddy": "Daddy", "squirrel": "Squirrel", "baby": "Baby", "cops": "The cops"}  # [HUD]
const MAILDROP := [5.9, -3.0]  # [HUD]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Crimes.define_all()


## Break the reference cycles (step lambdas, body callables) so nothing leaks at exit.
func _exit_tree() -> void:
	for c in C.values():
		c.steps.clear()
	C.clear()
	for b in bodies:
		b.pos = Callable()
		b.on = Callable()
	bodies.clear()
	if car_body:
		car_body.pos = Callable()
		car_body.on = Callable()
	LATER.clear()
	W.clear()
	W_.clear()
	SOLIDS.clear()
	car = null
	S.lock = null
	S.pz = null
	S.fin = null
	talkers.clear()
	Prim.clear_cache()


# ---------------------------------------------------------------- later()
var LATER: Array = []


## Run fn after sec seconds of game clock (pauses with the game). JS later().
func later(sec: float, fn: Callable) -> void:
	LATER.append([clock + sec, fn])


func run_later() -> void:
	var i := LATER.size() - 1
	while i >= 0:
		if i < LATER.size() and clock >= LATER[i][0]:
			var f: Callable = LATER[i][1]
			LATER.remove_at(i)
			f.call()
		i -= 1


## Say each line in turn ([who, text, secs]), then run done (JS talk()).
func talk(lines: Array, done = null) -> void:
	var t := 0.0
	for l in lines:
		Hud.say(l[0], l[1], l[2])
		t += l[2]
	if done != null:
		later(t, done)


## An input action, held for real or by the tests (K).
func key(action: String) -> bool:
	if K.get(action, false):
		return true
	return not manual and Input.is_action_pressed(action)


# ---------------------------------------------------------------- [HUD] queries
## Current step of a crime: {"k", "t", "m"}.
func cur(c: Crime) -> Dictionary:
	return c.steps[mini(c.si, c.steps.size() - 1)] if c.steps.size() else {}


func step_text(st: Dictionary) -> String:
	var t = st.get("t", "")
	return t.call() if t is Callable else str(t)


## "Gary · since 2009" -> "Gary"
func short_name(c: Crime) -> String:
	return c.who.split(" ·")[0]


## Where the marker / mini-map dot for a crime goes (JS markPos).
func mark_pos(c: Crime) -> Vector3:
	if not c.dispatched and not c.handling:
		var a = c.act()
		if a:
			return Vector3(a.x, 0.3, a.z)
	return c.target()


## What E would do here, or null: {"kind": "crime"|"phone"|"cops"|"copsaway", "label": String, ...}
func nearest_interact():
	if not built:
		return null
	return Interact.nearest_interact()


## Crime ids that must be told on to clear the current stage (pool + gary).
func need_list() -> Array:
	return STAGES[S.stage]["pool"] + ["gary"]


## The camera the HUD projects markers with.
func camera() -> Camera3D:
	return cam if cam else get_viewport().get_camera_3d()


# ---------------------------------------------------------------- [HUD] callbacks
## Make a speaker's puppet(s) move their mouth for secs (JS r.talk). who = speaker id (TWOPACK, GARY, COPS...).
func set_talking(who: String, secs: float) -> void:
	if not built:
		return
	var rigs: Array = {"TWOPACK": [tp], "GARY": [gary], "RICKY": [ricky], "DAN": [dan], "STEVE": [steve], "COPS": [dan, steve],
		"TIMMY": [timmy], "MAMA": [W.mama], "GRANDMA": [granny], "MAILMAN": [mailman], "DADDY": [W.dad], "VENDOR": [W.vendor]}.get(who, [])
	for r in rigs:
		r.talk = secs


func start_game() -> void:
	Game.start_game()


func start_stage(n: int, keep: bool) -> void:
	Game.start_stage(n, keep)


## The payphone puzzle was solved: operator line, dispatch, close (JS solved()).
func puzzle_solved() -> void:
	Puzzles.solved()


## Wrong puzzle answer: every pending crime loses sec seconds (JS penalty()). Also flashes via Hud.penalty_flash.
func penalty(sec: int) -> void:
	for c in Crimes.pending_evidence():
		if not is_inf(c.left):
			c.left -= sec
	Hud.penalty_flash(sec)


## Hang up the payphone (button or Esc).
func hang_up() -> void:
	if S.mode == "puzzle":
		Audio.sfx("buzz")
		Puzzles.close_puzzle()


## Highest stage reached (saved), 1 or 2.
func saved_stage() -> int:
	return Game.saved_stage()


# ---------------------------------------------------------------- build (state.js)
## Called by the main scene: builds the block and the cast under root and shows the title.
func boot(root: Node3D) -> void:
	world_root = root
	var look := Lighting.setup(root)
	cam = look.cam
	cam_attr = look.attr
	build(root)
	built = true
	S.stage = 1
	S.told = {}
	Crimes.start_crime("gary")
	Player.update_camera(0.0, true)
	Hud.show_title(saved_stage() >= 2)


func build(root: Node3D) -> void:
	SOLIDS.clear()
	OCCLUDERS.clear()
	bodies.clear()
	W.clear()
	W_.clear()
	World.build_block(root)
	tp = Cast.person("two_pack", root)
	ricky = Cast.person("ricky", root)
	granny = Cast.person("granny", root)
	# Gary lies along the gutter: feet at x = -1.95, head toward -x, face up
	var g_outer := Prim.group(root, -1.95, 0.21, 0.73, "GaryOuter")
	g_outer.rotation.y = PI / 2
	var g_inner := Prim.group(g_outer, 0, 0, 0, "GaryInner")
	g_inner.rotation.x = -PI / 2
	gary = Cast.person("gary", g_inner)
	gary.outer = g_outer
	gary.inner = g_inner
	smoke = _make_smoke(root)
	timmy = Cast.person("timmy", root)
	mailman = Cast.person("mailman", root)
	dan = Cast.person("cop_dan", root)
	steve = Cast.person("cop_steve", root)
	car = CopCar.make(root)
	player_body = Movement.add_body(0.33, func(): return Vector3(P.x, 0, P.z), func(): return true)
	World.build_stage2(root)
	W.ricky = Walker.make(ricky, 0.32, 1.15)
	W.granny = Walker.make(granny, 0.42, 0.33)
	W.dan = Walker.make(dan, 0.34, 1.6)
	W.steve = Walker.make(steve, 0.34, 1.6)
	for k in ["ricky", "granny", "dan", "steve"]:
		var w: Walker = W[k]
		w.body = Movement.add_body(w.r, func(): return Vector3(w.x, 0, w.z), func(): return w.visible)
	Movement.add_body(0.3, func(): return Vector3(16.5, 0, -3.75), func(): return timmy.g.visible)
	W.mail = Walker.make(mailman, 0.34, 1.0)
	W.mail.body = Movement.add_body(0.34, func(): return Vector3(W.mail.x, 0, W.mail.z), func(): return W.mail.visible)
	W.mama = Cast.person("mama", root)
	W.mama.g.visible = false
	Movement.add_body(0.3, func(): return Vector3(17.1, 0, -6.7), func(): return W.mama.g.visible)
	W.bills = []
	for k in 6:
		var b := Assets.model("cash_bill")
		b.position = Vector3(0, 0.19, 0)
		b.visible = false
		b.set_meta("t", 0.0)
		root.add_child(b)
		W.bills.append(b)
	car_body = Body.make(0.0, func(): return Vector3(car.x, 0, car.z), func(): return false)
	ricky.g.visible = false
	granny.g.visible = false
	timmy.g.visible = false
	mailman.g.visible = false
	W_.stand_closed.visible = true
	W_.stand_sign.visible = false
	talkers = [tp, ricky, gary, dan, steve, granny, timmy, mailman, W.mama, W.dad, W.vendor]
	for L in W.liners:
		talkers.append(L.rig)
	cops_home()


func cops_home() -> void:
	for e in [[W.dan, 35.2, -2.75], [W.steve, 37.3, -2.7]]:
		var w: Walker = e[0]
		if w.escort:
			continue
		w.x = e[1]
		w.z = e[2]
		w.yaw = 0.0
		w.target = null
		w.visible = true
		w.rig.g.visible = true


## Gary's smoke: a few soft puffs rising from his mouth.
func _make_smoke(root: Node3D) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "GarySmoke"
	p.amount = 7
	p.lifetime = 1.0 / 0.42
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.06
	p.direction = Vector3(0, 1, 0)
	p.spread = 12.0
	p.gravity = Vector3(0.05, 0.12, 0)
	p.initial_velocity_min = 0.55
	p.initial_velocity_max = 0.75
	p.damping_min = 0.05
	p.damping_max = 0.1
	var sc := Curve.new()
	for i in 9:
		var u := i / 8.0
		sc.add_point(Vector2(u, (0.4 + 1.6 * u) * (1.0 - u) / 0.625))
	p.scale_amount_curve = sc
	p.scale_amount_min = 0.9
	p.scale_amount_max = 1.1
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.92, 0.92, 0.92, 0.0))
	ramp.set_color(1, Color(0.92, 0.92, 0.92, 0.0))
	ramp.add_point(0.15, Color(0.93, 0.93, 0.93, 0.5))
	ramp.add_point(0.7, Color(0.9, 0.9, 0.9, 0.35))
	p.color_ramp = ramp
	# soft round puffs: a radial falloff on camera-facing quads
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	var fall := Gradient.new()
	fall.set_color(0, Color(1, 1, 1, 1))
	fall.set_color(1, Color(1, 1, 1, 0))
	fall.add_point(0.55, Color(1, 1, 1, 0.55))
	tex.gradient = fall
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.disable_receive_shadows = true
	var sm := QuadMesh.new()
	sm.size = Vector2(0.3, 0.3)
	sm.material = m
	p.mesh = sm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(p)
	return p


func set_dof(on: bool) -> void:
	if cam_attr and cam_attr.dof_blur_far_enabled != on:
		cam_attr.dof_blur_far_enabled = on


# ---------------------------------------------------------------- loop (game.js)
func _process(delta: float) -> void:
	if not built or manual:
		return
	if S.mode == "play" and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED:
		_set_pause(true)
	frame(delta)


func frame(delta: float) -> void:
	var dt := minf(0.05, delta)
	if S.mode != "pause":
		tick(dt)


func tick(dt: float) -> void:
	clock += dt
	run_later()
	if S.mode == "play" or S.mode == "puzzle":
		S.time += dt
		Crimes.update_crimes(dt)
		car.update(dt)
		if S.mode == "play":
			Player.update_player(dt)
			Player.update_bino(dt)
		elif S.pz != null and not S.pz.focus.active and not S.pz.done:
			Hud.toast("Too late. They got away.")
			Puzzles.close_puzzle()
	else:
		car.update(dt)
		if S.mode == "cut":
			Game.update_finale(dt)
	Animate.animate_all(dt)
	Player.update_camera(dt)


func _set_pause(on: bool) -> void:
	S.mode = "pause" if on else "play"
	Hud.show_pause(on)
	Audio.set_paused(on)


# ---------------------------------------------------------------- input
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		drag = false


func _input(e: InputEvent) -> void:
	# releases always end a drag, wherever the mouse is
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
		drag = false


func _unhandled_input(e: InputEvent) -> void:
	if not built:
		return
	if e is InputEventKey and e.pressed:
		_key(e)
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_LEFT:
			drag = true
		elif S.bino_on and (e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			bino_fov = clampf(bino_fov + (3.0 if e.button_index == MOUSE_BUTTON_WHEEL_DOWN else -3.0), 8.0, 34.0)
	elif e is InputEventMouseMotion:
		if S.mode != "play":
			return
		# screen pixels, like the JS movementX/Y (relative is scaled by the canvas stretch)
		var rel: Vector2 = e.screen_relative
		if S.bino_on:
			var s := 0.0022 * (bino_fov / 16.0)
			bino_yaw -= rel.x * s
			bino_pitch = clampf(bino_pitch - rel.y * s, -0.5, 0.45)
			return
		if drag:
			cam_yaw -= rel.x * 0.006
			cam_pitch = clampf(cam_pitch + rel.y * 0.004, 0.05, 0.95)


func _key(e: InputEventKey) -> void:
	if S.mode == "puzzle":
		if e.is_action_pressed("cancel"):
			hang_up()
		else:
			var k := _puzzle_key(e)
			if k != "":
				Hud.puzzle_key(k)
		return
	if S.mode == "cut" or S.mode == "video":
		return
	if e.is_action_pressed("pause") and (S.mode == "play" or S.mode == "pause"):
		_set_pause(S.mode == "play")
		return
	if e.is_action_pressed("toggle_music"):
		S.music_on = not S.music_on
		Audio.set_music(S.music_on)
		Hud.toast("Music on" if S.music_on else "Music off")
		return
	if S.mode != "play":
		return
	if S.lock != null:
		if e.is_action_pressed("interact"):
			Minigames.lock_press()
		elif e.is_action_pressed("cancel"):
			Minigames.cancel_lock()
		return
	if e.is_action_pressed("interact"):
		Interact.interact()


static func _puzzle_key(e: InputEventKey) -> String:
	if e.keycode == KEY_BACKSPACE:
		return "Backspace"
	var ch := char(e.unicode) if e.unicode > 0 else ""
	if ch in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "#"]:
		return ch
	return ""


# ---------------------------------------------------------------- debug hooks (the JS window.__tt)
## G.tt_start_crime("ricky"), G.tt_stage(2), G.tt_teleport(x, z, yaw), G.tt_aim(yaw, pitch), G.tick(dt)
func tt_start_crime(id: String) -> void:
	Crimes.start_crime(id)


func tt_stage(n: int) -> void:
	Game.start_stage(n, false)


func tt_teleport(x: float, z: float, yaw := INF) -> void:
	P.x = x
	P.z = z
	if not is_inf(yaw):
		P.yaw = yaw
		cam_yaw = yaw
	Player.update_camera(0.0, true)


func tt_aim(yaw: float, pitch: float) -> void:
	bino_yaw = yaw
	bino_pitch = pitch
