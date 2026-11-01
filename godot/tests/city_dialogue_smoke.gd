extends SceneTree
## Fast deterministic graph/choice tests; does not instantiate the neighborhood.
const State := preload("res://scripts/city/city_dialogue_state.gd")
const T := preload("res://scripts/ui/hud_theme.gd")
var failures := 0

func check(value: bool, label: String) -> void:
	print("[city_dialogue] %s %s" % ["PASS" if value else "FAIL", label])
	if not value:
		failures += 1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var calls := [0]
	var model := State.new()
	var data := {"start": "start", "nodes": {"start": {"speaker": "Resident", "lines": ["First exact line.", "Second exact line."], "choices": [{"text": "Hidden", "condition": "locked"}, {"text": "Accept", "hook": {"kind": "accept"}, "next": "done"}, {"text": "Leave"}]}, "done": {"speaker": "Resident", "lines": ["Thank you."]}}}
	var resolver := func(_action): calls[0] += 1; return true
	check(model.open(data, func(_key): return false, resolver), "valid graph opens")
	check(calls[0] == 0 and model.current().text == "First exact line.", "opening is read-only and preserves exact text")
	check(model.choices().is_empty(), "choices wait for last line")
	model.advance()
	check(model.current().text == "Second exact line." and calls[0] == 0, "line advance has no mission hook")
	check(model.choices().size() == 2 and model.choices()[0].text == "Accept", "conditions filter choices")
	model.choose(99)
	check(calls[0] == 0, "invalid choice cannot execute hooks")
	model.choose(0)
	check(calls[0] == 1 and model.current().text == "Thank you.", "explicit choice executes hook and branches")
	model.advance()
	model.choose(0)
	check(not model.active and calls[0] == 1, "terminal/repeated callback cannot repeat reward")
	model.open(data, func(_key): return false, resolver)
	model.close()
	check(calls[0] == 1 and not model.active, "Escape/close has no hooks")
	model.open(data, func(_key): return false, func(_action): return false)
	model.advance()
	model.choose(0)
	check(model.active and model.node_id == "start", "failed/stale action leaves conversation at current node")
	model.close()
	check(not model.open({"start": "missing", "nodes": {}}), "invalid graph closes safely")
	for kind in ["display", "body500", "body600", "body700", "mono", "monob"]:
		check(T.font(kind) != null and bool(T._real.get(kind, false)), "original bundled font loads: " + kind)
	quit(0 if failures == 0 else 1)
