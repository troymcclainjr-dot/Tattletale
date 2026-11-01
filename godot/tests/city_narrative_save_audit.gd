extends SceneTree
## Pure cross-section checks against the actual authored narrative validator.
## No world setup, NPC relocation, persistence write or production mutation.
const Narrative := preload("res://scripts/city/city_narrative.gd")
var passes := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	print("[narrative_save_audit] %s %s" % ["PASS" if ok else "FAIL", label])
	passes += int(ok)
	failures += int(not ok)

func _initialize() -> void:
	var narrative := Narrative.new()
	check(narrative.validate([], "", 0, {}, {}).is_empty(), "legacy empty story accepts neutral migration")
	check(narrative.validate(["petals_word"], "petals_report", 0, {"petals_call": "report"}, {}).is_empty(),
		"saved report choice restores matching part 2")
	check(not narrative.validate(["petals_word"], "petals_report", 0, {"petals_call": "protect"}, {}).is_empty(),
		"saved active branch cannot contradict earlier choice")
	check(narrative.validate(["petals_word"], "petals_report", 0, {"petals_call": "report"}, {"officer": true}).is_empty(),
		"dead primary officer permits a surviving authored stand-in")
	var dead_police: Dictionary = {}
	for id in Narrative.ROLES["@police"]:
		dead_police[id] = true
	check(narrative.validate(["petals_word"], "petals_report", 0, {"petals_call": "report"}, dead_police)
		== "case requires deceased contact", "all remaining police replacements dead invalidates active police step")
	check(narrative.validate(["petals_word"], "petals_report", 1, {"petals_call": "report"}, dead_police).is_empty(),
		"already-completed police step does not invalidate later Ines handoff")
	var dead_recipients: Dictionary = {}
	for id in Narrative.RECIPIENTS:
		dead_recipients[id] = true
	check(narrative.validate([], "errand_delivery", 0, {}, dead_recipients) == "case requires deceased contact",
		"all delivery recipients dead invalidates active errand before checkpoint selection")
	dead_recipients.erase(str(Narrative.RECIPIENTS[0]))
	check(narrative.validate([], "errand_delivery", 0, {}, dead_recipients).is_empty(),
		"a surviving delivery recipient remains a valid reroute")
	print("[narrative_save_audit] %d passed; %d failed" % [passes, failures])
	quit(0 if failures == 0 else 1)
