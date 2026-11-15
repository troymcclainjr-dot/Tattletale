extends Node
## Shooting. main.gd makes one (`_combat`) and hands it the --do steps it does not know itself (step()) and
## each --lineup figure (lineup()); the rest it does on its own, each frame after main.gd's own work.
##
## Left mouse while he points what he holds (right mouse or Ctrl) fires it: the pistol once a click, the Uzi
## and the AK for as long as the button is held. R reloads from his spare rounds (a short pause, the gun comes
## down); an empty gun only clicks. A shot leaves the muzzle for whatever the red cross is over (a person first,
## then glass, then a wall or a prop) and cannot go through a wall he stands behind; with Ctrl (no cross) it
## goes along the barrel. combat_world.gd finds what it hits, combat_fx.gd draws it, combat_glass.gd breaks
## glass, combat_people.gd looks after the shot and the frightened, combat_hud.gd is the bottom-left corner.
## Rounds, health and cash are main.gd's `_state` (player_state.gd).

const World := preload("res://scripts/combat_world.gd")
const Fx := preload("res://scripts/combat_fx.gd")
const Glass := preload("res://scripts/combat_glass.gd")
const People := preload("res://scripts/combat_people.gd")
const Hud := preload("res://scripts/combat_hud.gd")
const PlayerState := preload("res://scripts/player_state.gd")

## Placeholder numbers. every: seconds between shots; auto: it fires while the button is held; damage: of a
## person's 100; spread: radians either side of the cross; reload: seconds; flash and shell: metres long (the
## cases are drawn far bigger than real ones, like the guns, or they would not show).
const GUNS := {
	"pistol": {"every": 0.16, "auto": false, "damage": 34, "spread": 0.006, "reload": 1.0, "flash": 0.25, "shell": 0.085},
	"uzi": {"every": 0.085, "auto": true, "damage": 20, "spread": 0.035, "reload": 1.3, "flash": 0.27, "shell": 0.085},
	"ak": {"every": 0.1, "auto": true, "damage": 45, "spread": 0.02, "reload": 1.6, "flash": 0.36, "shell": 0.105},
}
const SPRINT_SPREAD := 2.5        # running, his shots go this much wider
const RANGE := 60.0               # metres
const HOSPITAL_BILL := 500        # dollars, placeholder: what waking up in hospital costs
const HOSPITAL_ROOM := "TREATMENT"

var main: Node
var fx: Node3D
var hud: CanvasLayer
var people: RefCounted
var show_hud := true
var last := {}                    # what the last shot did (for the steps and the check)
var _worlds := {}                 # a place's node: its combat_world.gd
var _rng := RandomNumberGenerator.new()
var _cooldown := 0.0
var _reload_left := -1.0
var _reload_of := ""
var _was_down := false
var _building: Node3D             # the place last seen
var _place := ""
var _day := -1
var _frozen := false
var _spot_pane: MeshInstance3D      # the pane _target_of("window") found


func _ready() -> void:
	main = get_parent()
	_rng.seed = 7
	fx = Fx.new()
	fx.name = "CombatFx"
	add_child(fx)
	hud = Hud.new()
	add_child(hud)
	hud.watch(main._state)
	people = People.new()
	people.main = main
	people.fx = fx
	people.world_of = world_for
	main._state.changed.connect(_on_state)


func _exit_tree() -> void:
	Glass.forget()


## What shots can hit at a place (its node), gathered the first time it is asked for.
func world_for(place: Node3D) -> RefCounted:
	if place == null:
		return null
	if not _worlds.has(place):
		var w := World.new()
		w.build(place, place.doors if "doors" in place else [])
		_worlds[place] = w
	return _worlds[place]


func _on_state() -> void:
	if main._building:
		people.reconcile(main._place)


func _process(delta: float) -> void:
	var lead: Node3D = main._actor
	hud.weapon = lead.weapon
	hud.visible = show_hud and main._mode == "play" and main._shot_lineup == "" and not main._talk.is_open() and not main._travel.is_open()
	hud._panel.modulate.a = 1.0 - float(main._bar)
	if main._scripted and not main.is_processing():
		return                      # a screenshot's last frames: everything stays where it is
	var dt := 1.0 / 60.0 if main._scripted else delta
	fx.camera = main._camera
	_watch()
	if _frozen:
		return
	var down := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var free: bool = not main._scripted and main._mode == "play" and not main._talk.is_open() and not main._travel.is_open() and not main._performing
	if free and down and lead.weapon != "" and lead.aiming and (not _was_down or GUNS.get(lead.weapon, {}).get("auto", false)):
		fire()
	_was_down = down
	_cooldown = maxf(_cooldown - dt, 0.0)
	lead.recoil = move_toward(lead.recoil, 0.0, dt * 8.0)
	if _reload_left >= 0.0:
		if lead.weapon != _reload_of:
			_end_reload(false)
		else:
			_reload_left -= dt
			hud.reload = 1.0 - _reload_left / float(GUNS[_reload_of]["reload"])
			if _reload_left <= 0.0:
				_end_reload(true)
	fx.tick(dt)
	people.tick(dt)
	hud.tick(dt)


## A place left, a new day.
func _watch() -> void:
	if main._building != _building:
		if _building != null:
			people.left(_place)
			fx.drop_moving()
		_building = main._building
		_place = main._place
		people.reconcile(_place)
	if int(main._day) != _day:
		if _day >= 0:
			_new_day()
		_day = int(main._day)


## A new day: the dead are up (the flags say who is down on which day), the glass is mended, the cases and
## marks are swept up (placeholder rule).
func _new_day() -> void:
	for w: RefCounted in _worlds.values():
		for e: RefCounted in w.glass():
			Glass.mend(e.mi)
	fx.clear()
	for place: String in main._cast:
		people.reconcile(place)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or (event as InputEventKey).physical_keycode != KEY_R:
		return
	if main._talk.is_open() or main._travel.is_open() or main._mode != "play" or main._performing:
		return
	reload()


# ------------------------------------------------------------ firing

## Pull the trigger once. False if nothing went off (an empty gun clicks).
func fire() -> bool:
	var lead: Node3D = main._actor
	var w: String = lead.weapon
	if not GUNS.has(w) or _cooldown > 0.0 or _reload_left >= 0.0:
		return false
	var state: RefCounted = main._state
	if int(state.loaded.get(w, 0)) <= 0:
		_cooldown = 0.25
		hud.click()
		last = {"what": "click"}
		return false
	state.loaded[w] = int(state.loaded[w]) - 1
	state.touch()
	_cooldown = float(GUNS[w]["every"])
	_shoot(w)
	return true


func _shoot(w: String) -> void:
	var lead: Node3D = main._actor
	var gun: Dictionary = GUNS[w]
	var gp: Dictionary = lead.gun_points()
	var muzzle: Vector3 = gp.get("muzzle", lead.global_position + Vector3(0.0, lead.height * 0.62, 0.0))
	var target := _target(gp, muzzle)
	var spread: float = float(gun["spread"]) * (SPRINT_SPREAD if lead.sprinting else 1.0)
	var dir := _scatter((target - muzzle).normalized(), spread)
	var room := _node_for(lead.global_position)
	var chest := lead.global_position + Vector3(0.0, lead.height * 0.62, 0.0)
	last = _trace(muzzle, dir, int(gun["damage"]), chest)
	lead.recoil = 1.0
	fx.flash(gp, float(gun["flash"]), room)
	_eject(gp, gun, room, lead.global_position.y)
	people.alarm(lead.global_position)


## Where the shot is going: what the red cross is over, or along the barrel with no cross.
func _target(gp: Dictionary, muzzle: Vector3) -> Vector3:
	if not main._cross.visible:
		var along: Vector3 = gp.get("dir", (main._actor.global_transform.basis.x as Vector3))
		return muzzle + along * RANGE
	var cam: Camera3D = main._camera
	var at: Vector2 = main._cross.at
	var from := cam.project_ray_origin(at)
	var d := cam.project_ray_normal(at)
	var far := from + d * 80.0
	var hit: Dictionary = world_for(main._building).trace(from, far)
	var solid := float(hit["t"]) * 80.0 if hit["hit"] else INF
	var who: Dictionary = people.pick(from, d)
	if not who.is_empty() and float(who["dist"]) < solid + 0.3:
		return who["point"]
	var panes: Array = hit["panes"]
	if not panes.is_empty():
		return panes[0]["pos"]
	return hit["pos"] if hit["hit"] else far


## A direction turned a little, at random, no more than `spread` radians.
func _scatter(dir: Vector3, spread: float) -> Vector3:
	if spread <= 0.0:
		return dir
	var x := dir.cross(Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT).normalized()
	var y := dir.cross(x).normalized()
	var a := _rng.randf() * TAU
	var r := spread * sqrt(_rng.randf())
	return (dir + (x * cos(a) + y * sin(a)) * tan(r)).normalized()


## The shot itself: glass on the way breaks, and the first person or solid thing takes it. If the gun pokes
## through a wall he stands against (from his chest to the muzzle), the shot goes into that wall.
func _trace(muzzle: Vector3, dir: Vector3, damage: int, chest: Vector3) -> Dictionary:
	var w := world_for(main._building)
	var from := muzzle
	var end := muzzle + dir * RANGE
	var hit: Dictionary = w.trace(chest, muzzle)
	if hit["hit"]:
		from = chest
		end = muzzle
	else:
		hit = w.trace(muzzle, end)
	var who: Dictionary = people.along(from, end)
	var stop := float(hit["t"]) if hit["hit"] else 1.0
	var person_first := not who.is_empty() and float(who["t"]) < stop
	if person_first:
		stop = float(who["t"])
	var broke := 0
	for pane: Dictionary in hit["panes"]:
		if float(pane["t"]) >= stop:
			break
		if _break(pane["entry"].mi, pane["pos"], dir):
			broke += 1
	var out := {"what": "nothing", "panes": broke, "from": from}
	if person_first:
		var p: RefCounted = who["person"]
		out["what"] = "person"
		out["who"] = String(p.actor.display_name) if p.actor.display_name != "" else String(p.actor.name)
		out["result"] = people.hit(p, who["point"], dir, damage)
		out["at"] = who["point"]
	elif hit["hit"]:
		var at: Vector3 = hit["pos"]
		out["at"] = at
		if hit["block"]:
			out["what"] = "car glass"
			Glass.crack(hit["mi"], at, hit["normal"], _rng)
			fx.shards(at, hit["normal"], dir, 0.08, 6, w.floor_at(at, main._actor.global_position.y), _node_for(at))
		else:
			out["what"] = "metal" if hit["metal"] else "wall"
			out["on"] = String((hit["mi"] as Node).name)
			fx.impact(at, hit["normal"], hit["mi"], hit["metal"], _node_for(at), w.floor_at(at, main._actor.global_position.y))
	return out


## Break a pane at `pos` (unless the shot goes through its hole). True if it broke.
func _break(mi: MeshInstance3D, pos: Vector3, dir: Vector3) -> bool:
	if Glass.in_hole(mi, pos):
		return false
	var hole: Dictionary = Glass.shatter(mi, pos, _rng, _twins(mi))
	var centre: Vector3 = hole["center"]
	var ground: float = world_for(main._building).floor_at(centre, main._actor.global_position.y)
	var count := clampi(10 + int(float(hole["radius"]) * 24.0), 10, 22)
	fx.shards(centre, hole["normal"], dir, float(hole["radius"]), count, ground, _node_for(centre))
	return true


## Panes in exactly the same place as this one (the studio's see-through copy of a wall has its own).
func _twins(mi: MeshInstance3D) -> Array:
	var out: Array = []
	for e: RefCounted in world_for(main._building).glass():
		var other: MeshInstance3D = e.mi
		if other != mi and other.mesh is BoxMesh and mi.mesh is BoxMesh \
				and other.global_position.distance_to(mi.global_position) < 0.01 \
				and (other.mesh as BoxMesh).size.is_equal_approx((mi.mesh as BoxMesh).size):
			out.append(other)
	return out


## The spent case, out of the port to the right of the barrel, up and back.
func _eject(gp: Dictionary, gun: Dictionary, room: Node3D, ground: float) -> void:
	if gp.is_empty():
		return
	var d: Vector3 = gp["dir"]
	var side := d.cross(Vector3.UP)
	if side.length() < 0.2:
		side = main._camera.global_transform.basis.x
	side = side.normalized()
	var vel := side * _rng.randf_range(1.0, 1.7) + Vector3.UP * _rng.randf_range(1.7, 2.4) - d * _rng.randf_range(0.3, 0.7)
	fx.shell(gp["eject"], vel, ground, float(gun["shell"]), room)


## The node things at `at` go in, so that they are hidden with their room.
func _node_for(at: Vector3) -> Node3D:
	return people._node_for(at)


# ------------------------------------------------------------ reloading, hurt

## R: fill the magazine from his spare rounds. False if there is nothing to do.
func reload() -> bool:
	var lead: Node3D = main._actor
	var w: String = lead.weapon
	if not GUNS.has(w) or _reload_left >= 0.0:
		return false
	var state: RefCounted = main._state
	if int(state.loaded.get(w, 0)) >= int(PlayerState.CLIP[w]) or int(state.spare.get(w, 0)) <= 0:
		return false
	_reload_left = float(GUNS[w]["reload"])
	_reload_of = w
	lead.lowered = true
	hud.reload = 0.0
	return true


func _end_reload(done: bool) -> void:
	var lead: Node3D = main._actor
	if done:
		var state: RefCounted = main._state
		var w := _reload_of
		var loaded := int(state.loaded.get(w, 0))
		var take := mini(int(PlayerState.CLIP[w]) - loaded, int(state.spare.get(w, 0)))
		state.loaded[w] = loaded + take
		state.spare[w] = int(state.spare[w]) - take
		state.touch()
	lead.lowered = false
	_reload_left = -1.0
	_reload_of = ""
	hud.reload = -1.0


## Something hurts him (nothing here shoots back yet: the hurt:n step). At no health he wakes in hospital.
func hurt(amount: int) -> void:
	main._state.hurt(amount)
	hud.hurt()
	if int(main._state.health) <= 0:
		_to_hospital()


## He wakes in hospital with his health back, and the bill paid out of his cash (placeholder numbers).
func _to_hospital() -> void:
	var bill := mini(HOSPITAL_BILL, int(main._state.cash))
	main._cut_to(func() -> void:
		main._travel_to("hospital", true)
		main._teleport(main._spot_in_room(HOSPITAL_ROOM), true)
		main._actor.show_face()
		main._state.heal(PlayerState.MAX_HEALTH)
		main._state.spend(bill)
		hud.caption("HOSPITAL BILL  %s" % Hud.dollars(-bill))
		main._save_game()
		print("[shot] hurt: he wakes in the hospital, %s paid" % Hud.dollars(bill)))


# ------------------------------------------------------------ screenshot steps

## A --do step main.gd does not know (see the top of main.gd).
func step(bits: PackedStringArray) -> void:
	match bits[0]:
		"fire":             # fire or fire:n
			var n := int(bits[1]) if bits.size() > 1 else 1
			await _raise()
			var went: int = await _fire(n)
			print("[shot] fire: %d of %d went off; %s; last: %s" % [went, n, _rounds(), _said(last)])
		"reload":           # reload (and wait till it is done) or reload:start (to catch it part-way)
			var started := reload()
			while _reload_left >= 0.0 and not (bits.size() > 1 and bits[1] == "start"):
				await get_tree().process_frame
			print("[shot] reload: %s; %s" % [("started" if _reload_left >= 0.0 else "done") if started else "nothing to do", _rounds()])
		"hurt":             # hurt:n
			hurt(int(bits[1]) if bits.size() > 1 else 10)
			print("[shot] hurt: health %d, cash %s" % [int(main._state.health), Hud.dollars(int(main._state.cash))])
		"shoot":            # shoot:who or shoot:who:n; who is a name (TRE, nurse), window, car or someone
			var who := bits[1] if bits.size() > 1 else "someone"
			var target: Variant = _target_of(who)
			if target == null:
				print("[shot] shoot: nothing called %s in sight here" % who)
				return
			await _aim_on(target)
			var n := int(bits[2]) if bits.size() > 2 else 1
			var went: int = await _fire(n, target)
			print("[shot] shoot %s: %d of %d went off; %s; last: %s" % [who, went, n, _rounds(), _said(last)])
		"aimon":            # aimon:who: the cross on it, nothing fired
			var target: Variant = _target_of(bits[1] if bits.size() > 1 else "someone")
			if target != null:
				await _aim_on(target)
		"hud":              # hud:0 hides it, hud:1 shows it
			show_hud = bits.size() < 2 or bits[1] != "0"
		"freeze":           # everything that is flying stops where it is
			_frozen = true
			fx.frozen = true
		"combatcheck":
			await _check()
		_:
			print("[shot] unknown step: %s" % ":".join(bits))


## He brings up what he holds, if it is not up yet.
func _raise() -> void:
	if main._actor.aiming:
		return
	main._actor.aiming = true
	for i in 24:
		await get_tree().process_frame


## Fire n times as fast as the gun goes, keeping the cross on `target` (a point, or someone, followed as he
## moves) if there is one. How many went off.
func _fire(n: int, target: Variant = null) -> int:
	var went := 0
	for i in n:
		while _cooldown > 0.0 or _reload_left >= 0.0:
			await get_tree().process_frame
			if target != null:
				main._aim_at(main._camera.unproject_position(_point_of(target)))
		if fire():
			went += 1
	return went


## Point at `target` (a point in the world, or someone) and wait for him to turn and bring the gun up.
func _aim_on(target: Variant) -> void:
	main._actor.aiming = true
	for i in 30:
		main._aim_at(main._camera.unproject_position(_point_of(target)))
		await get_tree().process_frame
	main._aim_at(main._camera.unproject_position(_point_of(target)))


## Where to aim at a target: a point is itself; someone is aimed at in the middle of his chest.
func _point_of(target: Variant) -> Vector3:
	if target is Node3D:
		var a: Node3D = target
		return a.global_position + Vector3(0.0, a.height * 0.6, 0.0)
	return target


## Something to aim at: someone (by name, or "someone": the nearest), "window" (a point on the nearest pane in
## sight that is not broken yet; the pane is kept in _spot_pane) or "car" (the nearest car glass in sight).
## Null if there is none.
func _target_of(who: String) -> Variant:
	var lead: Node3D = main._actor
	_spot_pane = null
	if who == "window" or who == "glass" or who == "car":
		var best: Variant = null
		var near := INF
		var cam: Camera3D = main._camera
		var w := world_for(main._building)
		for e: RefCounted in w.glass():
			var mi: MeshInstance3D = e.mi
			if e.thin != (who != "car") or mi.has_meta("broken") or not mi.is_visible_in_tree():
				continue
			for c: Vector3 in _pane_points(mi):
				if not cam.is_position_in_frustum(c):
					continue
				var look: Dictionary = w.trace(cam.global_position, c + (c - cam.global_position).normalized() * 0.05)
				var panes: Array = look["panes"]
				var seen: bool = (look["block"] and look["mi"] == mi) if who == "car" else (not panes.is_empty() and panes[0]["entry"].mi == mi)
				if not seen:
					continue
				var away := c.distance_to(lead.global_position)
				if away < near:
					near = away
					best = c
					_spot_pane = mi
				break
		return best
	var nearest: Variant = null
	var gap := INF
	for p: RefCounted in people.living_here():
		var a: Node3D = p.actor
		var called := String(a.display_name).to_lower() == who.to_lower() or String(a.name).to_lower() == who.to_lower()
		if called:
			return a
		if who == "someone":
			var d := a.global_position.distance_to(lead.global_position)
			if d < gap:
				gap = d
				nearest = a
	return nearest


## Points on a pane to aim at: its middle, then the middles of its quarters (a bar can cross the middle).
static func _pane_points(mi: MeshInstance3D) -> Array:
	var box := mi.get_aabb()
	var c := box.get_center()
	var s := box.size
	var axes := [0, 1, 2]
	axes.sort_custom(func(a: int, b: int) -> bool: return s[a] > s[b])
	var u := Vector3.ZERO
	u[axes[0]] = s[axes[0]] * 0.25
	var v := Vector3.ZERO
	v[axes[1]] = s[axes[1]] * 0.25
	var out: Array = []
	for off: Vector3 in [Vector3.ZERO, u + v, u - v, -u + v, -u - v]:
		out.append(mi.global_transform * (c + off))
	return out


func _rounds() -> String:
	var w: String = main._actor.weapon
	if w == "":
		return "hands empty"
	return "%s %d / %d" % [w, int(main._state.loaded.get(w, 0)), int(main._state.spare.get(w, 0))]


func _said(shot: Dictionary) -> String:
	var through := " (through %d panes)" % int(shot["panes"]) if int(shot.get("panes", 0)) > 0 else ""
	var spot := ""
	if shot.has("at"):
		var at: Vector3 = shot["at"]
		spot = " at %.2f, %.2f, %.2f" % [at.x, at.y, at.z]
	match String(shot.get("what", "")):
		"person":
			return "%s, %s%s%s" % [shot["who"], shot["result"], spot, through]
		"wall", "metal":
			return "%s %s%s%s" % [shot["what"], shot.get("on", ""), spot, through]
		"":
			return "-"
	return "%s%s%s" % [shot["what"], spot, through]


## --do=combatcheck: at this place, a shot at a window breaks it, enough shots at someone put him down with a
## pool under him, the rounds go down by the shots fired and the HUD shows what the player state holds.
func _check() -> void:
	var problems := 0
	var lead: Node3D = main._actor
	if lead.weapon == "":
		lead.weapon = "pistol"
	await _raise()
	var w: String = lead.weapon
	var state: RefCounted = main._state
	var had := int(state.loaded[w]) + int(state.spare[w])
	var fired := 0
	var spot: Variant = _target_of("window")
	var pane := _spot_pane
	if spot == null:
		print("[shot] check: no window in sight from where he stands")
	else:
		await _aim_on(spot)
		fired += await _fire(1, spot)
		var broken := pane.has_meta("broken")
		print("[shot] check: window %s: %s (the shot: %s)" % [pane.name, "broken" if broken else "NOT BROKEN", _said(last)])
		if not broken:
			problems += 1
	var victim: RefCounted = null
	var gap := INF
	for p: RefCounted in people.living_here():
		var d: float = p.actor.global_position.distance_to(lead.global_position)
		if d < gap:
			gap = d
			victim = p
	if victim == null:
		print("[shot] check: nobody here to shoot")
	else:
		var a: Node3D = victim.actor
		var called: String = a.display_name if a.display_name != "" else String(a.name)
		await _aim_on(a)
		var shots := 0
		while victim.state != "dead" and shots < 14:
			if int(state.loaded[w]) == 0:
				reload()
				while _reload_left >= 0.0:
					await get_tree().process_frame
			var went: int = await _fire(1, a)
			fired += went
			shots += 1
			if went == 0:
				break
		for i in 50:
			await get_tree().process_frame
		var down: bool = people.is_down(victim)
		var pool: bool = people.has_pool(victim)
		print("[shot] check: %s %s after %d shots (the last: %s); pool under him: %s" % [called, "down" if down else "STILL UP", shots, _said(last), "yes" if pool else "NO"])
		if not down or not pool:
			problems += 1
	for i in 3:
		await get_tree().process_frame
	var now := int(state.loaded[w]) + int(state.spare[w])
	var right := had - now == fired
	print("[shot] check: rounds %d before, %d after, %d fired: %s" % [had, now, fired, "ok" if right else "WRONG"])
	if not right:
		problems += 1
	var shown: Dictionary = hud.shown
	var same: bool = int(shown.get("loaded", -1)) == int(state.loaded[w]) and int(shown.get("spare", -1)) == int(state.spare[w]) \
			and int(shown.get("health", -1)) == int(state.health) and int(shown.get("cash", -1)) == int(state.cash)
	print("[shot] check: HUD shows %s, %d / %d, health %d, %s; the state has %d / %d, health %d, %s: %s" % [shown.get("weapon", "-"),
			int(shown.get("loaded", -1)), int(shown.get("spare", -1)), int(shown.get("health", -1)), Hud.dollars(int(shown.get("cash", 0))),
			int(state.loaded[w]), int(state.spare[w]), int(state.health), Hud.dollars(int(state.cash)), "ok" if same else "WRONG"])
	if not same:
		problems += 1
	print("[shot] check: %d problems" % problems)


# ------------------------------------------------------------ --lineup

## A figure of the lineup is set up: with an x in its pose it is caught firing (the flash, the kick, a case
## just out of the port).
func lineup(who: Node3D, pose: String) -> void:
	if not pose.contains("x") or who.weapon == "":
		return
	who.recoil = 0.75
	who.walk(Vector2.ZERO, Vector2.ZERO, 1.0 / 60.0)
	_lineup_fire.call_deferred(who)


func _lineup_fire(who: Node3D) -> void:
	fx.camera = main._camera
	var gp: Dictionary = who.gun_points()
	if gp.is_empty():
		print("[shot] lineup: %s is not up to fire" % who.weapon)
		return
	var gun: Dictionary = GUNS.get(who.weapon, GUNS["pistol"])
	fx.flash(gp, float(gun["flash"]), fx)
	var d: Vector3 = gp["dir"]
	var side := d.cross(Vector3.UP)
	if side.length() < 0.2:
		side = main._camera.global_transform.basis.x
	side = side.normalized()
	fx.shell(gp["eject"] + side * 0.05 + Vector3.UP * 0.09 - d * 0.03, side + Vector3.UP * 2.0, who.global_position.y, float(gun["shell"]), fx)
	print("[shot] lineup: %s fires %s" % [who.weapon, gp["art"] if gp["art"] != "" else "side-on"])
