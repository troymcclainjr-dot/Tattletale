extends RefCounted
## People who are shot, and the people round them (combat.gd hands shots on to this).
##
## A person hit flinches and pulls a hurt face; with no health left he drops where he stands: his card goes
## over and lies flat on the floor, face up, eyes shut (paper_actor.gd's `fallen`), and a pool of blood spreads
## from under him and stays. The dead do not walk, talk, blink or stand in anyone's way.
##
## Everyone near a shot is frightened: they turn to the shooter with a scared face, then run from him to the far
## side of where they may walk (their room, or where they wander), facing the way they run, round props and
## round each other. Someone drawn only from the front can only run towards the camera (the way he faces), and
## someone with no legs drawn cannot run at all: they cower where they are. With no shot for CALM seconds they go
## back to what they were doing; when he leaves a place, those who ran are back in their places.
##
## Placeholder rule: the dead stay dead (in the save, in the player state's flags) until he next sleeps.

const PaperActor := preload("res://scripts/paper_actor.gd")
const HEALTH := 100              # a person's, placeholder
const REACT := 18.0              # metres: people this near a shot are frightened by it
const CALM := 12.0               # seconds with no shot before the frightened go back to what they were doing
const FALL := 0.55               # seconds to go down
const POOL_SECONDS := 4.0        # for the pool to spread
const POOL_RADIUS := 0.95        # metres, about (the ring is 0.8 of it, wobbling): it shows round someone the size of the lead
const FLEE_CONE := 0.7           # radians: drawn only from the front, he runs no further than this from straight at the camera
const TURN := 0.22               # seconds to turn round before running a new way (paper_actor.gd's flip, and a little)
const GRID := 0.25               # metres: the squares a runner's way is found on
const HURT_FACE := 0.6           # seconds of the hurt face before the scared one


class Person:
	var actor: Node3D
	var member: Dictionary
	var place := ""
	var index := 0
	var health := HEALTH
	var state := "calm"          # "calm", "alarmed", "fleeing", "cowering", "dead"
	var wait := 0.0
	var quiet := 0.0
	var taken := false
	var brain_was: Variant = null
	var areas_was: Array = []
	var others_was: Array = []
	var face_was := "neutral"
	var reach_was := 1.6
	var home := Vector3.ZERO
	var hurt_t := 0.0
	var fall_t := -1.0
	var pool: MeshInstance3D
	var flee                     # his Flee while he is frightened


## Stands in for someone's brain in main.gd's cast while he is frightened: main.gd calls tick() each frame.
class Flee:
	var frozen := false
	var person:                  # the Person it moves (held weakly: the Person holds this Flee)
		get:
			return _person.get_ref() if _person else null
		set(value):
			_person = weakref(value)
	var _person: WeakRef
	var to_screen: Callable
	var path := PackedVector2Array()
	var at := 0
	var turning := 0.0
	var stuck := 0.0

	func tick(delta: float) -> void:
		if person == null:
			return
		var a: Node3D = person.actor
		if frozen or person.state != "fleeing":
			a.sprinting = false
			a.walk(Vector2.ZERO, Vector2.ZERO, delta)
			return
		if turning > 0.0:
			turning -= delta
			a.walk(Vector2.ZERO, Vector2.ZERO, delta)
			return
		var here := Vector2(a.position.x, a.position.z)
		while at < path.size() and here.distance_to(path[at]) < 0.14:
			at += 1
			if at < path.size() and _turn_for(path[at] - here):
				a.walk(Vector2.ZERO, Vector2.ZERO, delta)
				return
		if at >= path.size():
			person.state = "cowering"
			a.sprinting = false
			a.walk(Vector2.ZERO, Vector2.ZERO, delta)
			return
		var dir := (path[at] - here).normalized()
		a.sprinting = true
		a.walk(dir, to_screen.call(dir), delta)
		var moved := Vector2(a.position.x, a.position.z).distance_to(here)
		stuck = stuck + delta if moved < PaperActor.WALK_SPEED * float(a.speed) * delta * 0.3 else 0.0
		if stuck > 0.4:              # someone or something in the way: he stays where he is
			person.state = "cowering"
			a.sprinting = false

	## Before he runs a new way he turns to face it, standing (the house rule). True while he does.
	func _turn_for(way: Vector2) -> bool:
		var a: Node3D = person.actor
		var screen: Vector2 = to_screen.call(way.normalized())
		var view := "front"
		var mirrored := false
		if a._views.has("side") and absf(screen.x) >= absf(screen.y) * 0.7:
			view = "side"
			mirrored = screen.x < 0.0
		elif a._views.has("back") and screen.y < 0.0:
			view = "back"
		elif a._views.size() == 1:
			mirrored = screen.x < -0.1 if absf(screen.x) > 0.1 else a._want_yaw > 1.0
		if a.view == view and is_equal_approx(a._want_yaw, PI if mirrored else 0.0):
			return false
		a.face_way(view, mirrored)
		turning = TURN
		return true


var main: Node
var fx: Node3D
var world_of: Callable           # place node -> combat_world.gd for it
var _people := {}                # "place:index": Person
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.seed = 23


## The person for main.gd's cast entry `index` at `place`.
func _person(place: String, index: int) -> Person:
	var key := "%s:%d" % [place, index]
	if not _people.has(key):
		var p := Person.new()
		var member: Dictionary = main._cast[place][index]
		p.member = member
		p.actor = member["actor"]
		p.place = place
		p.index = index
		p.home = p.actor.position
		p.reach_was = p.actor.use_reach
		_people[key] = p
	return _people[key]


## Everyone at the place he is at, alive or not.
func here() -> Array:
	var out: Array = []
	var cast: Array = main._cast.get(main._place, [])
	for i in cast.size():
		out.append(_person(main._place, i))
	return out


func living_here() -> Array:
	var out: Array = []
	for p: Person in here():
		if p.state != "dead" and p.actor.is_visible_in_tree():
			out.append(p)
	return out


## Whoever's drawing is under a ray from the camera (the cross): {"person", "dist", "point"}, or {}.
func pick(from: Vector3, dir: Vector3) -> Dictionary:
	var best := {}
	var near := INF
	for p: Person in living_here():
		var a := p.actor
		var n: Vector3 = a.global_transform.basis.z
		var across: Vector3 = a.global_transform.basis.x
		var facing := dir.dot(n)
		if absf(facing) < 1e-4:
			continue
		var t := (a.global_position - from).dot(n) / facing
		if t <= 0.0 or t > near:
			continue
		var on := from + dir * t
		var u := (on - a.global_position).dot(across)
		var v := on.y - a.global_position.y
		var h: float = a.height
		var wide: float = a.reach / 0.4
		var half := (0.13 if v > h * 0.82 else (0.25 if v > h * 0.45 else 0.17)) * wide
		if v < 0.0 or v > h * 1.02 or absf(u) > half:
			continue
		near = t
		best = {"person": p, "dist": t, "point": on}
	return best


## The first person a shot from `from` to `to` goes into: {"person", "t" (0..1 along it), "point"}, or {}.
func along(from: Vector3, to: Vector3) -> Dictionary:
	var best := {}
	var first := INF
	var d := to - from
	var flat := Vector2(d.x, d.z)
	var len2 := flat.length_squared()
	if len2 < 1e-8:
		return best
	var f := Vector2(from.x, from.z)
	for p: Person in living_here():
		var a := p.actor
		var c := Vector2(a.global_position.x, a.global_position.z)
		var r: float = 0.24 * a.reach / 0.4
		var t := clampf((c - f).dot(flat) / len2, 0.0, 1.0)
		var gap := (f + flat * t).distance_squared_to(c)
		if gap > r * r:
			continue
		var t0 := maxf(t - sqrt(r * r - gap) / sqrt(len2), 0.0)
		var y := from.y + d.y * t0
		var y1 := from.y + d.y * t
		var foot: float = a.global_position.y
		if (y < foot or y > foot + a.height) and (y1 < foot or y1 > foot + a.height):
			continue
		if t0 < first:
			first = t0
			best = {"person": p, "t": t0, "point": from + d * t0}
	return best


# ------------------------------------------------------------ shot, frightened

## Someone is hit by a shot going `dir` at `point`, for `damage`. Returns "down" if that was the end of him.
func hit(p: Person, point: Vector3, dir: Vector3, damage: int) -> String:
	if p.state == "dead":
		return "dead"
	p.health -= damage
	var a := p.actor
	var eye: Basis = main._camera.global_transform.basis
	var plane := point - a.global_transform.basis.z * (point - a.global_position).dot(a.global_transform.basis.z)
	fx.blood(plane + (main._camera.global_position - plane).normalized() * 0.06, dir, a.global_position.y, _node_for(a.global_position))
	if p.health <= 0:
		_die(p, dir)
		return "down"
	a.flinch = -0.2 * signf(dir.dot(eye.x))      # he jerks away from the shot, across the screen
	p.hurt_t = HURT_FACE
	if a.face:
		a.face.set_expression("hurt", true)
	_frighten(p, main._actor.global_position)
	return "hit"


## A shot was fired from `at`: everyone near it is frightened.
func alarm(at: Vector3) -> void:
	for p: Person in living_here():
		if p.actor.global_position.distance_to(at) <= REACT:
			_frighten(p, at)


func _frighten(p: Person, at: Vector3) -> void:
	p.quiet = 0.0
	if p.state != "calm":
		return
	_take_over(p)
	p.state = "alarmed"
	p.wait = _rng.randf_range(0.15, 0.45)
	var a := p.actor
	var across: float = main._screen_dir(Vector2(at.x - a.position.x, at.z - a.position.z)).x
	a.face_side(across)          # he turns to look (if he can turn)
	if a.face:
		if p.hurt_t <= 0.0:
			a.face.set_expression("scared", true)
		a.face.look(signf(across) * (1.0 if not a._views.has("side") else 0.0))


## From now on this person is moved by a Flee, not by what moved him before (put back by _let_go).
func _take_over(p: Person) -> void:
	if p.taken:
		return
	p.taken = true
	var a := p.actor
	p.brain_was = p.member["brain"]
	p.areas_was = a.areas.duplicate()
	p.others_was = a.others.duplicate()
	p.face_was = a.face.expression if a.face else "neutral"
	var flee := Flee.new()
	flee.person = p
	flee.to_screen = Callable(main, "_screen_dir")
	p.flee = flee
	p.member["brain"] = flee


## Back to what he was doing.
func _let_go(p: Person) -> void:
	if not p.taken:
		return
	p.taken = false
	var a := p.actor
	p.member["brain"] = p.brain_was
	a.areas = p.areas_was
	a.others = p.others_was
	a.sprinting = false
	a.cower = 0.0
	a.flinch = 0.0
	if a.face:
		a.face.set_expression(p.face_was if p.face_was != "" else "neutral")
		a.face.look(0.0)
	p.state = "calm"


## Where he may run: his wandering ground, or the room he stands in.
func _ground(p: Person) -> Array:
	var brain: Variant = p.brain_was
	if brain != null and "home" in brain and (brain.home as Rect2).has_area():
		return [brain.home]
	var b: Node3D = main._building
	var room: Dictionary = b.rooms[b.room_at_pos(p.actor.global_position, 0)]
	if room.has("areas"):
		return room["areas"]
	return [(room["area"] as Rect2).grow_individual(-0.4, -0.26, -0.4, -0.26)]


## Find a way to run from `from`, and start him on it (or he cowers where he is).
func _run_from(p: Person, from: Vector3) -> void:
	var a := p.actor
	var flee: Flee = p.flee
	a.areas = _ground(p)
	a.others = [main._actor]
	for q: Person in living_here():
		if q != p:
			a.others.append(q.actor)
	var view: Dictionary = a._views.get("front", {})
	if view.get("limbs") == null:             # no legs drawn to run on
		p.state = "cowering"
		return
	var start := Vector2(a.position.x, a.position.z)
	var shooter := Vector2(from.x, from.z)
	var path := PackedVector2Array()
	if a._views.has("side") and a._views.has("back"):
		path = _way_out(a, start, shooter)
	else:
		path = _straight_out(a, start, shooter)
	if path.is_empty():
		p.state = "cowering"
		return
	flee.path = path
	flee.at = 0
	flee.stuck = 0.0
	p.state = "fleeing"
	flee._turn_for(path[0] - start)


## Someone who can face any way: the floor he can reach, on a grid, and the far side of it from the shooter.
func _way_out(a: Node3D, start: Vector2, shooter: Vector2) -> PackedVector2Array:
	var from := Vector2i(roundi(start.x / GRID), roundi(start.y / GRID))
	var seen := {from: from}
	var queue: Array = [from]
	var best := from
	var best_score := start.distance_to(shooter)
	var head := 0
	while head < queue.size() and queue.size() < 1600:
		var cell: Vector2i = queue[head]
		head += 1
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + step
			if seen.has(next):
				continue
			var spot := Vector2(next) * GRID
			if not a.can_stand(spot):
				continue
			seen[next] = cell
			queue.append(next)
			var score := spot.distance_to(shooter) - 0.15 * spot.distance_to(start)
			if score > best_score + 0.01:
				best_score = score
				best = next
	if best == from or Vector2(best).distance_to(Vector2(from)) * GRID < 0.6:
		return PackedVector2Array()
	var cells: Array = []
	var back: Vector2i = best
	while back != from:
		cells.push_front(back)
		back = seen[back]
	# Straighten it: from each point, on to the furthest one that can be walked to in a straight line.
	var out := PackedVector2Array()
	var at := start
	var i := 0
	while i < cells.size():
		var j := cells.size() - 1
		while j > i and not _clear_line(a, at, Vector2(cells[j]) * GRID):
			j -= 1
		at = Vector2(cells[j]) * GRID
		out.append(at)
		i = j + 1
	return out


## Someone drawn only from the front runs towards the camera, within FLEE_CONE of straight at it.
func _straight_out(a: Node3D, start: Vector2, shooter: Vector2) -> PackedVector2Array:
	var near: Vector2 = main._floor_dir(Vector2(0.0, 1.0)).normalized()
	var best := PackedVector2Array()
	var best_score := 0.25
	for i in 9:
		var way := near.rotated(lerpf(-FLEE_CONE, FLEE_CONE, float(i) / 8.0))
		var length := 0.0
		while length < 6.0 and a.can_stand(start + way * (length + 0.1)):
			length += 0.1
		if length < 0.6:
			continue
		var end := start + way * length
		var score := end.distance_to(shooter) - start.distance_to(shooter) + 0.05 * length
		if score > best_score:
			best_score = score
			best = PackedVector2Array([end])
	return best


func _clear_line(a: Node3D, from: Vector2, to: Vector2) -> bool:
	var n := int(ceil(from.distance_to(to) / 0.1))
	for k in range(1, n + 1):
		if not a.can_stand(from.lerp(to, float(k) / float(n))):
			return false
	return true


# ------------------------------------------------------------ down

func _die(p: Person, dir: Vector3, lay := Vector3.ZERO, write := true) -> void:
	_take_over(p)
	p.state = "dead"
	p.health = 0
	p.member["brain"] = null              # nothing walks him now; main.gd only keeps his drawing posed
	var a := p.actor
	a.weapon = ""
	a.aiming = false
	a.sprinting = false
	a.cower = 0.0
	a.flinch = 0.0
	a.use_reach = -1.0                    # nobody to talk to
	if a.face:
		a.face.set_expression("preachy", true)     # eyes shut
		a.face.hold_mouth("mouth_oh")
		a.face.look(0.0)
	a.fall_to = lay if lay != Vector3.ZERO else _fall_way(p, dir)
	a.fall_lift = _floor_under(p) - a.global_position.y
	p.fall_t = 0.0
	_out_of_the_way(p)
	if write:
		_remember(p)


## The way his head goes as he falls: across the screen, away from the shot, where there is floor for him.
func _fall_way(p: Person, dir: Vector3) -> Vector3:
	var eye: Basis = main._camera.global_transform.basis
	var right := Vector3(eye.x.x, 0.0, eye.x.z).normalized()
	var away := -Vector3(eye.z.x, 0.0, eye.z.z).normalized()
	var push := right if Vector3(dir.x, 0.0, dir.z).dot(right) >= 0.0 else -right
	for way: Vector3 in [push, push.rotated(Vector3.UP, 0.4 * signf(push.dot(right))), -push, away, (push + away).normalized(), (-push + away).normalized(), -away]:
		if _room_to_lie(p, way):
			return way
	return push


func _room_to_lie(p: Person, way: Vector3) -> bool:
	var a := p.actor
	var b := _site_of(p)
	var room: Dictionary = b.rooms[b.room_at_pos(a.global_position, 0)]
	var floor_rect: Rect2 = room.get("rect", room.get("area", Rect2()))
	floor_rect = floor_rect.grow(-0.12)
	for k: float in [0.3, 0.6, 0.85, 1.0]:
		var spot: Vector3 = a.global_position + way * a.height * k
		var flat := Vector2(spot.x, spot.z)
		if not floor_rect.has_point(flat):
			return false
		for prop: Rect2 in b.obstacles:
			if prop.grow(0.05).has_point(flat):
				return false
	return true


## The dead stand in nobody's way.
func _out_of_the_way(p: Person) -> void:
	main._actor.others.erase(p.actor)
	for q: Person in here():
		q.actor.others.erase(p.actor)
		if q.taken:
			q.others_was.erase(p.actor)


## In the player state's flags: who is down where, today.
func _remember(p: Person) -> void:
	var state: RefCounted = main._state
	var dead: Dictionary = state.flags.get("dead", {})
	if int(dead.get("day", -1)) != int(main._day):
		dead = {"day": main._day, "who": {}}
	var who: Dictionary = dead["who"].get(p.place, {})
	var a := p.actor
	who[str(p.index)] = [snappedf(a.position.x, 0.01), snappedf(a.position.z, 0.01), snappedf(a.fall_to.x, 0.001), snappedf(a.fall_to.z, 0.001)]
	dead["who"][p.place] = who
	state.flags["dead"] = dead
	state.touch()


## Make what the flags say true at `place`: the dead are down (with their pools, at once), the rest are up.
func reconcile(place: String) -> void:
	if not main._cast.has(place):
		return
	var dead: Dictionary = main._state.flags.get("dead", {})
	var who: Dictionary = {}
	if int(dead.get("day", -1)) == int(main._day):
		who = dead.get("who", {}).get(place, {})
	var cast: Array = main._cast[place]
	for i in cast.size():
		var p := _person(place, i)
		var key := str(i)
		if who.has(key) and p.state != "dead":
			var at: Array = who[key]
			_take_over(p)
			p.actor.position = Vector3(float(at[0]), p.actor.position.y, float(at[1]))
			_die(p, Vector3.ZERO, Vector3(float(at[2]), 0.0, float(at[3])), false)
			p.fall_t = FALL
			p.actor.fallen = 1.0
		elif not who.has(key) and p.state == "dead":
			_revive(p)
	if place == main._place and main._building.is_visible_in_tree():
		for p: Person in here():
			if p.state == "dead":
				_out_of_the_way(p)
				if p.pool == null and p.fall_t >= FALL:           # down when he came: his floor and his pool, now it can be seen
					p.actor.fall_lift = _floor_under(p) - p.actor.global_position.y
					_pool_for(p, 0.0)


func _revive(p: Person) -> void:
	var a := p.actor
	if p.pool:
		fx.lift_pool(p.pool)
		p.pool = null
	a.fallen = 0.0
	a.use_reach = p.reach_was
	p.fall_t = -1.0
	p.health = HEALTH
	if a.face:
		a.face.hold_mouth("")
	a.position = p.home
	a.face_way("front")
	_let_go(p)
	if p.place == main._place and not main._actor.others.has(a):
		main._actor.others.append(a)


## He has left `place`: those there who ran are back where they were, unfrightened.
func left(place: String) -> void:
	for key: String in _people:
		var p: Person = _people[key]
		if p.place == place and p.state != "dead" and p.taken:
			p.actor.position = p.home
			p.actor.face_way("front")
			p.hurt_t = 0.0
			p.health = HEALTH
			_let_go(p)


func _pool_for(p: Person, seconds: float) -> void:
	if p.pool:
		return
	var a := p.actor
	var feet: Vector3 = a.global_position
	var at: Vector3 = feet + a.fall_to * a.height * 0.42
	p.pool = fx.pool(Vector3(at.x, _floor_under(p) + 0.004, at.z), POOL_RADIUS * a.reach / 0.4, seconds, _node_for(feet, _site_of(p)))


## The place someone belongs to (its node).
func _site_of(p: Person) -> Node3D:
	return main._sites.get(p.place, main._building)


## The top of the floor he lies on: the highest under his feet, middle and head that is no more than a step
## above his feet (a court, a rug; not a bench his head is under).
func _floor_under(p: Person) -> float:
	var a := p.actor
	var feet: Vector3 = a.global_position
	var w = world_of.call(_site_of(p))
	if w == null:
		return feet.y
	var top := feet.y
	for k: float in [0.0, 0.45, 0.85]:
		var at: Vector3 = feet + a.fall_to * a.height * k
		top = maxf(top, w.floor_at(Vector3(at.x, feet.y - 0.38, at.z), feet.y))      # it looks down from 0.12 above his feet
	return top


## The node things on the floor at `at` go in, so that they are hidden with the room (a band of a place,
## a room of the studio).
func _node_for(at: Vector3, site: Node3D = null) -> Node3D:
	var b: Node3D = site if site else main._building
	var room: Dictionary = b.rooms[b.room_at_pos(at, maxi(main._room, 0) if b == main._building else 0)]
	if room.has("node"):
		return room["node"]
	return b.node_of(room["band"])


# ------------------------------------------------------------ each frame

func tick(delta: float) -> void:
	for p: Person in here():
		var a := p.actor
		if p.state == "dead":
			if p.fall_t >= 0.0 and p.fall_t < FALL:
				p.fall_t += delta
				a.fallen = clampf(p.fall_t / FALL, 0.0, 1.0)
				if p.fall_t >= FALL:
					_pool_for(p, POOL_SECONDS)
			continue
		if a.flinch != 0.0:
			a.flinch = move_toward(a.flinch, 0.0, delta * 1.4)
		if p.hurt_t > 0.0:
			p.hurt_t -= delta
			if p.hurt_t <= 0.0 and a.face and p.state != "calm":
				a.face.set_expression("scared", true)
		a.cower = move_toward(a.cower, 1.0 if p.state == "cowering" else 0.0, delta * 4.0)
		match p.state:
			"alarmed":
				p.wait -= delta
				if p.wait <= 0.0:
					_run_from(p, main._actor.global_position)
			"fleeing", "cowering":
				p.quiet += delta
				if p.state == "cowering" and p.quiet > CALM:
					p.health = maxi(p.health, int(HEALTH * 0.5))
					_let_go(p)


## For the check: is this person down, and is there a pool under him?
func is_down(p: Person) -> bool:
	return p.state == "dead"


func has_pool(p: Person) -> bool:
	return p.pool != null and is_instance_valid(p.pool) and p.pool.is_visible_in_tree()
