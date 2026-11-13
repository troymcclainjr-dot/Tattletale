extends Node
## Walks a paper actor about the floor on its own: pick a clear spot, walk to it,
## stand a while, pick another. If something is in the way for half a second it
## gives up on that spot and rests. Set `frozen` to make it stand still (while
## someone is talking to it, say).

var actor: Node3D             # a paper actor
var to_screen := Callable()   # floor direction (Vector2) -> the same direction on screen
var frozen := false
var home := Rect2()           # it only heads for spots inside this (x, z)

var _goal := Vector2.ZERO
var _rest := 1.5
var _stuck := 0.0
var _rng := RandomNumberGenerator.new()


func tick(delta: float) -> void:
	if frozen or _rest > 0.0:
		actor.walk(Vector2.ZERO, Vector2.ZERO, delta)
		if not frozen:
			_rest -= delta
			if _rest <= 0.0:
				_pick()
		return
	var at := Vector2(actor.position.x, actor.position.z)
	var to := _goal - at
	if to.length() < 0.12:
		_stop()
		return
	var dir := to.normalized()
	actor.walk(dir, to_screen.call(dir), delta)
	var moved := (Vector2(actor.position.x, actor.position.z) - at).length()
	_stuck = _stuck + delta if moved < actor.WALK_SPEED * actor.speed * delta * 0.3 else 0.0
	if _stuck > 0.5:
		_stop()


func _stop() -> void:
	_stuck = 0.0
	_rest = _rng.randf_range(1.0, 3.5)


func _pick() -> void:
	var at := Vector2(actor.position.x, actor.position.z)
	for i in 30:
		var p := home.position + Vector2(_rng.randf(), _rng.randf()) * home.size
		if actor.can_stand(p) and p.distance_to(at) > 1.0:
			_goal = p
			return
	_rest = 1.0
