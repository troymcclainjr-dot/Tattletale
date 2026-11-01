extends SceneTree
## Pure metadata regression: no scene, profile, rendering or physics needed.
const Context = preload("res://scripts/city/city_photo_context.gd")
var passed := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		push_error(message)

func _first_provider() -> Array:
	return [{"id": "subject", "position": Vector3.ZERO, "tags": ["first"]}]

func _second_provider() -> Array:
	return [{"id": "subject", "position": Vector3.ZERO, "tags": ["second"]}]

func _run() -> void:
	var actor := Node3D.new()
	var replacement := Node3D.new()
	var entries: Array[Dictionary] = []
	var seen: Dictionary = {}
	var position := Vector3(3, 1.2, -8)
	Context._add(entries, seen, {"id": "crowd_7", "kind": "actor", "position": position,
		"node": actor, "tags": ["down", "down"]})
	Context._add(entries, seen, {"id": "crowd_7", "kind": "actor", "position": Vector3.ZERO,
		"node": replacement, "tags": ["incident:sample", "role:offender", "down"], "max_distance": 999.0}, true)
	_check(entries.size() == 1, "Provider and generic actor must produce one subject")
	_check(entries[0].tags == ["incident:sample", "role:offender", "down"], "Provider tags merge and deduplicate")
	_check(entries[0].node == actor and entries[0].position == position, "Provider enrichment preserves live geometry provenance")
	_check(entries[0].max_distance == Context.MAX_RANGE, "Provider reach is clamped to capture range")
	var provider_tags: Array = []
	for index in range(Context.MAX_TAGS):
		provider_tags.append("required_%d" % index)
	Context._add(entries, seen, {"id": "crowd_7", "kind": "actor", "position": position, "tags": provider_tags}, true)
	_check(entries[0].tags == provider_tags, "Provider tags take priority at the tag cap")
	Context._add(entries, seen, {"id": "crowd_7", "kind": "actor", "position": position, "tags": ["generic"]})
	_check(entries[0].tags == provider_tags, "Later generic enrichment cannot displace required tags")
	var long_case_tag := "case:" + "a".repeat(48)
	var boundary_tag := "b".repeat(96)
	_check(Context._tags([long_case_tag, boundary_tag]) == [long_case_tag, boundary_tag], "Valid 53- and 96-character identifiers survive intact")
	_check(Context._tags(["b".repeat(97), "", 17, "valid", "valid"]) == ["valid"], "Invalid and duplicate tags are omitted without truncation")
	Context._add(entries, seen, {"id": "crowd_7", "kind": "object", "position": position})
	_check(entries.size() == 2, "Same ID with a different subject kind remains distinct")
	for index in range(Context.MAX_CANDIDATES):
		Context._add(entries, seen, {"id": "extra_%d" % index, "position": position})
	_check(entries.size() == Context.MAX_CANDIDATES, "Candidate count stays bounded")
	Context._add(entries, seen, {"id": "crowd_7", "kind": "actor", "position": position, "tags": ["late_provider"]}, true)
	_check(entries[0].tags[0] == "late_provider", "Enrichment still works when the candidate cap is full")
	var providers: Array[Callable] = [_first_provider, _second_provider]
	var supplied := Context.candidates(null, providers)
	_check(supplied.size() == 1 and supplied[0].tags == ["second", "first"], "Public provider pipeline applies duplicate merging")
	var subjects: Array[Dictionary] = []
	var used_bytes := 2
	for index in range(30):
		used_bytes = Context._append_subject(subjects, {"id": str(index), "tags": ["small"]}, used_bytes)
	_check(subjects.size() == Context.MAX_SUBJECTS, "Captured subject count stays capped at 24")
	_check(used_bytes == JSON.stringify(Context.json_safe(subjects)).to_utf8_buffer().size(), "Budget matches serialized array including separators")
	subjects.clear()
	used_bytes = 2
	var unicode_tags: Array = []
	for index in range(Context.MAX_TAGS):
		unicode_tags.append(str(index) + "界".repeat(95))
	for index in range(24):
		used_bytes = Context._append_subject(subjects, {"id": str(index), "position": position,
			"tags": unicode_tags}, used_bytes)
	_check(subjects.size() > 0 and subjects.size() < 24, "UTF-8 metadata budget limits large valid subject sets")
	_check(used_bytes <= Context.MAX_SUBJECT_JSON_BYTES and used_bytes == JSON.stringify(Context.json_safe(subjects)).to_utf8_buffer().size(), "UTF-8 serialized subject budget is exact and bounded")
	_check(subjects[0].tags == unicode_tags, "Budget never truncates accepted evidence tags")
	var before := subjects.size()
	var after_bytes: int = Context._append_subject(subjects, {"id": "oversized", "label": "x".repeat(11000)}, used_bytes)
	_check(subjects.size() == before and after_bytes == used_bytes, "An oversized subject is omitted intact")
	actor.free()
	replacement.free()
	print("PHOTO_CONTEXT_MERGE_SMOKE: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
