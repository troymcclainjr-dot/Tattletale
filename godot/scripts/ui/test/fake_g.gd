extends "res://scripts/core/g.gd"
## Test double for the HUD harness (hud_test.gd): the real G state and [HUD] queries, with
## G's own loop switched off, nearest_interact() faked and the HUD callbacks recorded.

var fake_interact = null
var calls: Array = []


func _ready() -> void:
	pass


func _process(_delta: float) -> void:
	pass


func _physics_process(_delta: float) -> void:
	pass


func _input(_event: InputEvent) -> void:
	pass


func _unhandled_input(_event: InputEvent) -> void:
	pass


func nearest_interact():
	return fake_interact


func set_talking(who: String, secs: float) -> void:
	calls.append(["set_talking", who, snappedf(secs, 0.01)])


func start_game() -> void:
	calls.append(["start_game"])


func start_stage(n: int, keep: bool) -> void:
	calls.append(["start_stage", n, keep])


func puzzle_solved() -> void:
	calls.append(["puzzle_solved"])
	if S.pz is Dictionary:
		S.pz["done"] = true


func penalty(sec: int) -> void:
	calls.append(["penalty", sec])


func hang_up() -> void:
	calls.append(["hang_up"])
