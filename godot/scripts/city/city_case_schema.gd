extends RefCounted
## Case definition schema 1: typed validation and normalization. Pure (no
## nodes, no world, no files). normalize() is the only gate between authored
## JSON and the case engine: every field the engine reads exists in the result
## with its documented type and default, every reference is checked, and an
## invalid definition is rejected whole with readable "where: problem" errors.
## Keys starting with "_" are author notes and are ignored. Field reference:
## artifacts/pacifist-foundation/CASE_AUTHORING.md

const PhotoContext := preload("res://scripts/city/city_photo_context.gd")
const SCHEMA := 1
const ID_PATTERN := "^[a-z][a-z0-9_]{1,47}$"
const ACTOR_PATTERN := "^[a-z][a-z0-9_]{0,63}$"
## Reusable player verbs. E verbs run through a range-checked conversation;
## photo through the trusted phone context; the rest through the bounded tick.
const VERBS := ["talk", "examine", "collect", "deliver", "interview", "report", "photo", "visit", "follow", "flee", "await_incident"]
const E_VERBS := ["talk", "examine", "collect", "deliver", "interview", "report"]
const PARTICIPANT_VERBS := ["talk", "deliver", "interview", "report"]
const PROP_VERBS := ["examine", "collect"]
const EVIDENCE_KINDS := ["observation", "photo", "testimony", "item", "report"]
## Clay prop builders in city_missions.gd (the original case props).
const BUILDERS := ["satchel", "parcel", "dumped_bags", "tool_caddy", "torn_notice", "lantern", "checkpoint", "crate", "marker"]
const INCIDENT_ROLES := ["offender", "victim", "witness", "location"]
const MAX_STAGES := 12
const MAX_OBJECTIVES := 6
const MAX_TOPICS := 6
const MAX_PARTICIPANTS := 8
const MAX_ACTORS := 12
const MAX_PROPS := 4
const MAX_EVIDENCE := 12
const MAX_OUTCOMES := 6
const MAX_TEXT := 480
const MAX_POINTS := 10000

const TOP_KEYS := ["schema", "id", "version", "title", "summary", "status", "kind", "legacy_slot", "reward", "discovery", "participants", "props",
	"evidence", "stages", "outcomes", "completion", "incident", "template", "params"]
const DISCOVERY_KEYS := ["trigger", "givers", "requires_completed", "locked_reason", "pitch", "accept", "decline", "start_notice"]
const PARTICIPANT_KEYS := ["actors", "label", "speaker", "bind", "stand_in_line"]
const PROP_KEYS := ["builder", "title", "placement", "solid", "photo_height", "photo_radius", "tag_height"]
const PLACEMENT_KEYS := ["route_metres", "radius", "tolerance"]
const EVIDENCE_KEYS := ["kind", "label"]
const STAGE_KEYS := ["id", "objective", "complete", "objectives"]
const OUTCOME_KEYS := ["rewarded", "terminal", "banner", "notice"]
const TOPIC_KEYS := ["id", "ask", "answer", "required", "after"]
const COMMON_OBJECTIVE_KEYS := ["id", "verb", "objective", "prompt", "dialogue", "speaker", "grants", "requires_evidence", "requires", "optional", "ends_case", "notice", "hide_props"]
const VERB_KEYS := {
	"talk": ["target"],
	"examine": ["target", "hide_after"],
	"collect": ["target"],
	"deliver": ["target", "item"],
	"interview": ["target", "greeting", "topics", "farewell"],
	"report": ["target", "greeting", "missing", "incident"],
	"photo": ["subject", "max_distance", "min_distance", "min_centrality", "count", "min_interval_minutes", "require_tags", "time_window", "area"],
	"visit": ["location", "radius", "dwell"],
	"follow": ["subject", "min_distance", "max_distance", "seconds", "unseen", "view_range", "view_cone", "lose_after", "on_fail"],
	"flee": ["from", "distance", "within", "on_timeout"],
	"await_incident": ["states"],
}
const DEFAULT_PROMPTS := {"talk": "E  Talk to %s", "examine": "E  Inspect the %s", "collect": "E  Pick up the %s", "deliver": "E  Hand over the %s",
	"interview": "E  Ask %s what they saw", "report": "E  File the report"}

## raw: one case Dictionary (templates already merged by the library).
## context: {"legacy": {id: {title, reward, stages}}, "reserved": [ids],
## "known_cases": [ids], "roles": {"@token": [actor ids]}}.
## Returns {"ok", "errors": PackedStringArray, "warnings": PackedStringArray, "case"}.
static func normalize(raw, context: Dictionary = {}) -> Dictionary:
	# Plain arrays: every helper appends to the same list.
	var errors: Array = []
	var warnings: Array = []
	var out := {}
	if not raw is Dictionary:
		errors.append("case: must be an object")
		return {"ok": false, "errors": PackedStringArray(errors), "warnings": PackedStringArray(warnings), "case": {}}
	var data: Dictionary = raw
	var id := str(data.get("id", ""))
	var where := "case " + (id if not id.is_empty() else "<missing id>")
	_keys(data, TOP_KEYS, where, errors)
	if not _integer(data.get("schema"), SCHEMA, SCHEMA):
		errors.append("%s: schema must be %d" % [where, SCHEMA])
	if not _matches(id, ID_PATTERN):
		errors.append("%s: id must match %s" % [where, ID_PATTERN])
	if str(id) in context.get("reserved", []):
		errors.append("%s: id is reserved by a story part or errand" % where)
	if not _integer(data.get("version"), 1, 1000000):
		errors.append("%s: version must be a whole number >= 1" % where)
	out.id = id
	out.version = int(data.get("version", 1)) if _integer(data.get("version"), 1, 1000000) else 1
	out.title = _text(data, "title", where, errors, true)
	out.summary = _text(data, "summary", where, errors, false)
	out.status = str(data.get("status", "ready"))
	if not out.status in ["ready", "draft"]:
		errors.append("%s: status must be \"ready\" or \"draft\"" % where)
	out.kind = str(data.get("kind", "case"))
	if out.kind != "case":
		errors.append("%s: kind must be \"case\" (repeatable work stays a progression errand)" % where)
	out.legacy_slot = bool(data.get("legacy_slot", false)) if data.get("legacy_slot", false) is bool else false
	if data.has("legacy_slot") and not data.legacy_slot is bool:
		errors.append("%s: legacy_slot must be true or false" % where)
	var reward = data.get("reward", {})
	out.reward = {"points": 0}
	if not reward is Dictionary:
		errors.append("%s.reward: must be an object" % where)
	else:
		_keys(reward, ["points"], where + ".reward", errors)
		if not _integer(reward.get("points", 0), 0, MAX_POINTS):
			errors.append("%s.reward.points: whole number 0..%d" % [where, MAX_POINTS])
		else:
			out.reward.points = int(reward.get("points", 0))
	var roles: Dictionary = context.get("roles", {})
	out.participants = _participants(data.get("participants", {}), where, roles, errors)
	out.props = _props(data.get("props", {}), where, errors)
	out.evidence = _evidence(data.get("evidence", {}), where, errors)
	out.incident = _incident(data.get("incident", null), where, errors)
	out.outcomes = _outcomes(data.get("outcomes", null), out.title, where, errors)
	var completion = data.get("completion", {})
	out.completion = {"outcome": "resolved"}
	if not completion is Dictionary:
		errors.append("%s.completion: must be an object" % where)
	else:
		_keys(completion, ["outcome"], where + ".completion", errors)
		out.completion.outcome = str(completion.get("outcome", "resolved"))
	if not out.outcomes.has(out.completion.outcome):
		errors.append("%s.completion.outcome: unknown outcome \"%s\"" % [where, out.completion.outcome])
	out.stages = _stages(data.get("stages", []), out, where, errors, warnings)
	out.discovery = _discovery(data.get("discovery", {}), out, where, context, errors)
	_cross_check(out, where, context, errors, warnings)
	# Template placeholders left in place: playable for testing, not finished content.
	var placeholders: Array = []
	_find_drafts(data, where, placeholders, 0)
	for entry in placeholders:
		warnings.append("%s: placeholder text still says [draft]" % str(entry))
	out.draft_text = placeholders.size()
	var ok := errors.is_empty()
	return {"ok": ok, "errors": PackedStringArray(errors), "warnings": PackedStringArray(warnings), "case": out if ok else {}}

const DRAFT_MARK := "[draft]"

static func _find_drafts(value, path: String, found: Array, depth: int) -> void:
	if depth > 12 or found.size() >= 64:
		return
	if value is String:
		if str(value).begins_with(DRAFT_MARK):
			found.append(path)
	elif value is Dictionary:
		for key in value:
			if not str(key).begins_with("_"):
				_find_drafts(value[key], "%s.%s" % [path, str(key)], found, depth + 1)
	elif value is Array:
		for index in value.size():
			var entry = value[index]
			var label := str(entry.get("id", index)) if entry is Dictionary else str(index)
			_find_drafts(entry, "%s[%s]" % [path, label], found, depth + 1)

# --- Sections ----------------------------------------------------------------------

static func _participants(value, where: String, roles: Dictionary, errors: Array) -> Dictionary:
	var result := {}
	if not value is Dictionary:
		errors.append("%s.participants: must be an object of roles" % where)
		return result
	if value.size() > MAX_PARTICIPANTS:
		errors.append("%s.participants: at most %d roles" % [where, MAX_PARTICIPANTS])
	for key in value:
		if str(key).begins_with("_"):
			continue
		var role := str(key)
		var at := "%s.participants.%s" % [where, role]
		if not _matches(role, ID_PATTERN):
			errors.append("%s: role id must match %s" % [at, ID_PATTERN])
			continue
		var spec = value[key]
		if not spec is Dictionary:
			errors.append("%s: must be an object" % at)
			continue
		_keys(spec, PARTICIPANT_KEYS, at, errors)
		var actors: Array = []
		var listed = spec.get("actors", [])
		if not listed is Array or listed.is_empty():
			errors.append("%s.actors: non-empty list of actor ids, @role tokens or incident:<role>" % at)
		else:
			for entry in listed:
				var actor := str(entry)
				if actor.begins_with("@"):
					if not roles.has(actor):
						errors.append("%s.actors: unknown role token %s" % [at, actor])
						continue
					for candidate in roles[actor]:
						if not str(candidate) in actors:
							actors.append(str(candidate))
				elif actor.begins_with("incident:"):
					if not actor.trim_prefix("incident:") in ["offender", "victim", "witness"]:
						errors.append("%s.actors: incident participants are incident:offender|victim|witness" % at)
					elif not actor in actors:
						actors.append(actor)
				elif not entry is String or not _matches(actor, ACTOR_PATTERN):
					errors.append("%s.actors: \"%s\" is not an actor id" % [at, actor])
				elif not actor in actors:
					actors.append(actor)
		if actors.size() > MAX_ACTORS:
			errors.append("%s.actors: at most %d candidates" % [at, MAX_ACTORS])
		var bind := str(spec.get("bind", "case"))
		if not bind in ["case", "step"]:
			errors.append("%s.bind: \"case\" (same person for the whole case) or \"step\" (any listed person each time)" % at)
		result[role] = {"actors": actors, "label": _text(spec, "label", at, errors, false, role.capitalize()),
			"speaker": _text(spec, "speaker", at, errors, false), "bind": bind, "stand_in_line": _text(spec, "stand_in_line", at, errors, false)}
	return result

static func _props(value, where: String, errors: Array) -> Dictionary:
	var result := {}
	if not value is Dictionary:
		errors.append("%s.props: must be an object" % where)
		return result
	if value.size() > MAX_PROPS:
		errors.append("%s.props: at most %d props" % [where, MAX_PROPS])
	for key in value:
		if str(key).begins_with("_"):
			continue
		var at := "%s.props.%s" % [where, str(key)]
		var spec = value[key]
		if not _matches(str(key), ID_PATTERN) or not spec is Dictionary:
			errors.append("%s: prop ids match %s and hold an object" % [at, ID_PATTERN])
			continue
		_keys(spec, PROP_KEYS, at, errors)
		var builder := str(spec.get("builder", ""))
		if not builder in BUILDERS:
			errors.append("%s.builder: one of %s" % [at, ", ".join(PackedStringArray(BUILDERS))])
		var placement = spec.get("placement", {})
		var place := {"route_metres": 0.0, "radius": 0.35, "tolerance": 2.2}
		if not placement is Dictionary:
			errors.append("%s.placement: must be an object" % at)
		else:
			_keys(placement, PLACEMENT_KEYS, at + ".placement", errors)
			if not _number(placement.get("route_metres"), 0.0, 5000.0):
				errors.append("%s.placement.route_metres: metres along the neighborhood walk, 0..5000" % at)
			else:
				place.route_metres = float(placement.route_metres)
			place.radius = _float(placement, "radius", 0.2, 1.0, 0.35, at + ".placement", errors)
			place.tolerance = _float(placement, "tolerance", 0.5, 6.0, 2.2, at + ".placement", errors)
		if spec.has("solid") and not spec.solid is bool:
			errors.append("%s.solid: true or false" % at)
		result[str(key)] = {"builder": builder, "title": _text(spec, "title", at, errors, false, builder.replace("_", " ").to_upper()),
			"placement": place, "solid": bool(spec.get("solid", false)) if spec.get("solid", false) is bool else false,
			"photo_height": _float(spec, "photo_height", 0.0, 3.0, 0.25, at, errors),
			"photo_radius": _float(spec, "photo_radius", 0.1, 3.0, 0.6, at, errors),
			"tag_height": _float(spec, "tag_height", 0.2, 4.0, 0.95, at, errors)}
	return result

static func _evidence(value, where: String, errors: Array) -> Dictionary:
	var result := {}
	if not value is Dictionary:
		errors.append("%s.evidence: must be an object" % where)
		return result
	if value.size() > MAX_EVIDENCE:
		errors.append("%s.evidence: at most %d items" % [where, MAX_EVIDENCE])
	for key in value:
		if str(key).begins_with("_"):
			continue
		var at := "%s.evidence.%s" % [where, str(key)]
		var spec = value[key]
		if not _matches(str(key), ID_PATTERN) or not spec is Dictionary:
			errors.append("%s: evidence ids match %s and hold an object" % [at, ID_PATTERN])
			continue
		_keys(spec, EVIDENCE_KEYS, at, errors)
		var kind := str(spec.get("kind", ""))
		if not kind in EVIDENCE_KINDS:
			errors.append("%s.kind: one of %s" % [at, ", ".join(PackedStringArray(EVIDENCE_KINDS))])
		result[str(key)] = {"kind": kind, "label": _text(spec, "label", at, errors, true)}
	return result

static func _incident(value, where: String, errors: Array) -> Dictionary:
	if value == null:
		return {}
	if not value is Dictionary:
		errors.append("%s.incident: must be an object" % where)
		return {}
	_keys(value, ["templates", "radius"], where + ".incident", errors)
	var templates: Array = []
	var listed = value.get("templates", [])
	if not listed is Array or listed.is_empty():
		errors.append("%s.incident.templates: non-empty list of incident template ids" % where)
	else:
		for entry in listed:
			if not entry is String or not _matches(str(entry), ACTOR_PATTERN):
				errors.append("%s.incident.templates: \"%s\" is not a template id" % [where, str(entry)])
			else:
				templates.append(str(entry))
	return {"templates": templates, "radius": _float(value, "radius", 5.0, 400.0, 60.0, where + ".incident", errors)}

static func _outcomes(value, title: String, where: String, errors: Array) -> Dictionary:
	var result := {}
	if value == null:
		result["resolved"] = {"rewarded": true, "terminal": true, "banner": (title + " resolved").to_upper(), "notice": ""}
		return result
	if not value is Dictionary or value.is_empty():
		errors.append("%s.outcomes: non-empty object" % where)
		return result
	if value.size() > MAX_OUTCOMES:
		errors.append("%s.outcomes: at most %d" % [where, MAX_OUTCOMES])
	for key in value:
		if str(key).begins_with("_"):
			continue
		var at := "%s.outcomes.%s" % [where, str(key)]
		var spec = value[key]
		if not _matches(str(key), ID_PATTERN) or not spec is Dictionary:
			errors.append("%s: outcome ids match %s and hold an object" % [at, ID_PATTERN])
			continue
		_keys(spec, OUTCOME_KEYS, at, errors)
		for flag in ["rewarded", "terminal"]:
			if spec.has(flag) and not spec[flag] is bool:
				errors.append("%s.%s: true or false" % [at, flag])
		var rewarded: bool = spec.get("rewarded", false) == true
		# A rewarded outcome is always final: the case is in completed_ids.
		var terminal: bool = rewarded or spec.get("terminal", false) == true
		result[str(key)] = {"rewarded": rewarded, "terminal": terminal, "banner": _text(spec, "banner", at, errors, false, (title + " closed").to_upper()),
			"notice": _text(spec, "notice", at, errors, false)}
	return result

static func _discovery(value, case_def: Dictionary, where: String, context: Dictionary, errors: Array) -> Dictionary:
	var result := {"trigger": "offer", "givers": [], "requires_completed": [], "locked_reason": "", "pitch": "", "accept": "", "decline": "Maybe later.", "start_notice": ""}
	if not value is Dictionary:
		errors.append("%s.discovery: must be an object" % where)
		return result
	var at := where + ".discovery"
	_keys(value, DISCOVERY_KEYS, at, errors)
	result.trigger = str(value.get("trigger", "offer"))
	if not result.trigger in ["offer", "incident", "none"]:
		errors.append("%s.trigger: \"offer\", \"incident\" or \"none\"" % at)
	var givers = value.get("givers", [])
	if not givers is Array:
		errors.append("%s.givers: list of participant roles" % at)
	else:
		for giver in givers:
			if not case_def.participants.has(str(giver)):
				errors.append("%s.givers: unknown participant role \"%s\"" % [at, str(giver)])
			else:
				result.givers.append(str(giver))
	if result.trigger == "offer" and result.givers.is_empty():
		errors.append("%s.givers: an offered case needs at least one giver" % at)
	if result.trigger == "incident" and case_def.incident.is_empty():
		errors.append("%s.trigger: \"incident\" needs an incident section" % at)
	var required = value.get("requires_completed", [])
	var known: Array = context.get("known_cases", [])
	if not required is Array:
		errors.append("%s.requires_completed: list of case ids" % at)
	else:
		for other in required:
			if str(other) == str(case_def.id):
				errors.append("%s.requires_completed: a case cannot require itself" % at)
			elif not known.is_empty() and not str(other) in known:
				errors.append("%s.requires_completed: unknown case \"%s\"" % [at, str(other)])
			else:
				result.requires_completed.append(str(other))
	for field in ["locked_reason", "pitch", "accept", "start_notice"]:
		result[field] = _text(value, field, at, errors, false)
	result.decline = _text(value, "decline", at, errors, false, "Maybe later.")
	return result

static func _stages(value, case_def: Dictionary, where: String, errors: Array, warnings: Array) -> Array:
	var result: Array = []
	if not value is Array or value.is_empty() or value.size() > MAX_STAGES:
		errors.append("%s.stages: 1..%d stages" % [where, MAX_STAGES])
		return result
	var stage_ids := {}
	var objective_ids := {}
	for index in value.size():
		var raw = value[index]
		var at := "%s.stages[%d]" % [where, index]
		if not raw is Dictionary:
			errors.append("%s: must be an object" % at)
			continue
		_keys(raw, STAGE_KEYS, at, errors)
		var stage_id := str(raw.get("id", ""))
		if not _matches(stage_id, ID_PATTERN) or stage_ids.has(stage_id):
			errors.append("%s.id: unique id matching %s" % [at, ID_PATTERN])
		stage_ids[stage_id] = true
		var complete := str(raw.get("complete", "all"))
		if not complete in ["all", "any"]:
			errors.append("%s.complete: \"all\" or \"any\"" % at)
		var objectives: Array = []
		var listed = raw.get("objectives", [])
		if not listed is Array or listed.is_empty() or listed.size() > MAX_OBJECTIVES:
			errors.append("%s.objectives: 1..%d objectives" % [at, MAX_OBJECTIVES])
		else:
			for position in listed.size():
				var objective := _objective(listed[position], case_def, "%s.objectives[%d]" % [at, position], errors, warnings)
				if objective.is_empty():
					continue
				if objective_ids.has(objective.id):
					errors.append("%s.objectives[%d].id: \"%s\" is used twice in this case" % [at, position, objective.id])
				objective_ids[objective.id] = true
				objective.stage = index
				objectives.append(objective)
		var required := 0
		for objective in objectives:
			required += int(not bool(objective.optional))
		if complete == "all" and required == 0 and not objectives.is_empty():
			errors.append("%s: an \"all\" stage needs at least one non-optional objective" % at)
		var focus_text := ""
		for objective in objectives:
			if not bool(objective.optional):
				focus_text = str(objective.objective)
				break
		result.append({"id": stage_id, "index": index, "complete": complete, "objectives": objectives,
			"objective": _text(raw, "objective", at, errors, false, focus_text)})
	return result

static func _objective(raw, case_def: Dictionary, at: String, errors: Array, warnings: Array) -> Dictionary:
	if not raw is Dictionary:
		errors.append("%s: must be an object" % at)
		return {}
	var verb := str(raw.get("verb", ""))
	if not verb in VERBS:
		errors.append("%s.verb: one of %s" % [at, ", ".join(PackedStringArray(VERBS))])
		return {}
	var allowed: Array = COMMON_OBJECTIVE_KEYS.duplicate()
	allowed.append_array(VERB_KEYS[verb])
	_keys(raw, allowed, at, errors)
	var id := str(raw.get("id", ""))
	if not _matches(id, ID_PATTERN):
		errors.append("%s.id: must match %s" % [at, ID_PATTERN])
	var result := {"id": id, "verb": verb, "stage": -1, "target": "", "subject": "", "location": "",
		"objective": _text(raw, "objective", at, errors, true), "speaker": _text(raw, "speaker", at, errors, false),
		"optional": raw.get("optional", false) == true, "ends_case": str(raw.get("ends_case", "")), "notice": _text(raw, "notice", at, errors, false),
		"grants": [], "requires_evidence": [], "requires": []}
	if raw.has("optional") and not raw.optional is bool:
		errors.append("%s.optional: true or false" % at)
	if not result.ends_case.is_empty() and not case_def.outcomes.has(result.ends_case):
		errors.append("%s.ends_case: unknown outcome \"%s\"" % [at, result.ends_case])
	var grants = raw.get("grants", [])
	if not grants is Array:
		errors.append("%s.grants: list of evidence ids" % at)
	else:
		for evidence_id in grants:
			if not case_def.evidence.has(str(evidence_id)):
				errors.append("%s.grants: unknown evidence \"%s\"" % [at, str(evidence_id)])
			elif not str(evidence_id) in result.grants:
				result.grants.append(str(evidence_id))
	var needs = raw.get("requires_evidence", [])
	if not needs is Array:
		errors.append("%s.requires_evidence: list of evidence ids (\"a|b\" = either)" % at)
	else:
		for entry in needs:
			var alternatives: Array = []
			for part in str(entry).split("|", false):
				var evidence_id := part.strip_edges()
				if not case_def.evidence.has(evidence_id):
					errors.append("%s.requires_evidence: unknown evidence \"%s\"" % [at, evidence_id])
				else:
					alternatives.append(evidence_id)
			if not alternatives.is_empty():
				result.requires_evidence.append(alternatives)
	var order = raw.get("requires", [])
	if not order is Array:
		errors.append("%s.requires: list of objective ids completed first" % at)
	else:
		for entry in order:
			result.requires.append(str(entry))
	result.hide_props = []
	var hidden = raw.get("hide_props", [])
	if not hidden is Array:
		errors.append("%s.hide_props: list of prop:<id> removed when this objective completes" % at)
	else:
		for entry in hidden:
			var ref := _prop_ref(entry, case_def, at + ".hide_props", errors)
			if not ref.is_empty():
				result.hide_props.append(ref)
	var label := ""
	match verb:
		"talk", "deliver", "interview", "report":
			result.target = _participant_ref(raw.get("target", ""), case_def, at + ".target", errors)
			label = str(case_def.participants.get(result.target.trim_prefix("participant:"), {}).get("label", "them")).to_lower()
		"examine", "collect":
			result.target = _prop_ref(raw.get("target", ""), case_def, at + ".target", errors)
			label = str(case_def.props.get(result.target.trim_prefix("prop:"), {}).get("title", "clue")).to_lower()
	match verb:
		"examine":
			result.hide_after = raw.get("hide_after", false) == true
		"deliver":
			result.item = _prop_ref(raw.get("item", ""), case_def, at + ".item", errors)
			label = str(case_def.props.get(str(result.item).trim_prefix("prop:"), {}).get("title", "item")).to_lower()
		"interview":
			result.greeting = _text(raw, "greeting", at, errors, false)
			result.farewell = _text(raw, "farewell", at, errors, false, "Thanks.")
			result.topics = _topics(raw.get("topics", []), at, errors)
		"report":
			result.greeting = _text(raw, "greeting", at, errors, false)
			result.missing = _text(raw, "missing", at, errors, false)
			result.incident = raw.get("incident", false) == true
			if result.incident and case_def.incident.is_empty():
				errors.append("%s.incident: the case has no incident section" % at)
			if result.requires_evidence.is_empty():
				warnings.append("%s: a report without requires_evidence accepts an empty report" % at)
		"photo":
			result.subject = _any_ref(raw.get("subject", ""), case_def, at + ".subject", errors, false)
			result.max_distance = _float(raw, "max_distance", 1.0, 120.0, 25.0, at, errors)
			result.min_distance = _float(raw, "min_distance", 0.0, 60.0, 0.0, at, errors)
			result.min_centrality = _float(raw, "min_centrality", 0.0, 0.95, 0.0, at, errors)
			result.count = _int(raw, "count", 1, 6, 1, at, errors)
			result.min_interval_minutes = _float(raw, "min_interval_minutes", 0.0, 600.0, 0.0, at, errors)
			result.require_tags = _string_list(raw, "require_tags", at, errors, PhotoContext.MAX_TAG_LENGTH)
			if result.require_tags.size() > PhotoContext.MAX_TAGS:
				errors.append("%s.require_tags: at most %d unique tags" % [at, PhotoContext.MAX_TAGS])
			var tags := {}
			for tag in result.require_tags:
				if tags.has(tag):
					errors.append("%s.require_tags: unique tags of 1..%d characters" % [at, PhotoContext.MAX_TAG_LENGTH])
				tags[tag] = true
			result.time_window = _window(raw.get("time_window", null), at, errors)
			result.area = _area(raw.get("area", null), case_def, at, errors)
			if result.min_distance >= result.max_distance:
				errors.append("%s: min_distance must be below max_distance" % at)
		"visit":
			result.location = _any_ref(raw.get("location", ""), case_def, at + ".location", errors, true)
			result.radius = _float(raw, "radius", 0.5, 60.0, 3.0, at, errors)
			result.dwell = _float(raw, "dwell", 0.0, 120.0, 0.0, at, errors)
		"follow":
			result.subject = _any_ref(raw.get("subject", ""), case_def, at + ".subject", errors, false)
			if result.subject.begins_with("prop:") or result.subject.begins_with("route:") or result.subject.begins_with("pos:"):
				errors.append("%s.subject: follow a person (participant, actor or incident role)" % at)
			result.min_distance = _float(raw, "min_distance", 0.0, 30.0, 2.0, at, errors)
			result.max_distance = _float(raw, "max_distance", 2.0, 80.0, 14.0, at, errors)
			result.seconds = _float(raw, "seconds", 2.0, 900.0, 20.0, at, errors)
			result.unseen = raw.get("unseen", false) == true
			result.view_range = _float(raw, "view_range", 1.0, 40.0, 7.5, at, errors)
			result.view_cone = _float(raw, "view_cone", 10.0, 300.0, 120.0, at, errors)
			result.lose_after = _float(raw, "lose_after", 1.0, 120.0, 8.0, at, errors)
			result.on_fail = _fail_mode(raw, "on_fail", case_def, at, errors)
			if result.min_distance >= result.max_distance:
				errors.append("%s: min_distance must be below max_distance" % at)
		"flee":
			result.subject = _any_ref(raw.get("from", ""), case_def, at + ".from", errors, true)
			result.distance = _float(raw, "distance", 3.0, 400.0, 25.0, at, errors)
			result.within = _float(raw, "within", 0.0, 900.0, 0.0, at, errors)
			result.on_fail = _fail_mode(raw, "on_timeout", case_def, at, errors)
		"await_incident":
			if case_def.incident.is_empty():
				errors.append("%s: await_incident needs the case incident section" % at)
			result.states = _string_list(raw, "states", at, errors)
			if result.states.is_empty():
				errors.append("%s.states: incident states that complete the objective" % at)
	if verb in E_VERBS:
		var fallback := str(DEFAULT_PROMPTS[verb]) % label if str(DEFAULT_PROMPTS[verb]).contains("%s") else str(DEFAULT_PROMPTS[verb])
		result.prompt = _text(raw, "prompt", at, errors, false, fallback)
		if not raw.has("prompt"):
			warnings.append("%s: prompt not authored, using \"%s\"" % [at, fallback])
		result.dialogue = _text(raw, "dialogue", at, errors, false)
		if verb in ["talk", "examine", "collect", "deliver"] and str(result.dialogue).is_empty():
			warnings.append("%s: dialogue not authored (draft text)" % at)
	else:
		result.prompt = ""
		result.dialogue = _text(raw, "dialogue", at, errors, false)
	return result

static func _topics(value, at: String, errors: Array) -> Array:
	var result: Array = []
	if not value is Array or value.is_empty() or value.size() > MAX_TOPICS:
		errors.append("%s.topics: 1..%d interview topics" % [at, MAX_TOPICS])
		return result
	var seen := {}
	var required := 0
	for index in value.size():
		var raw = value[index]
		var where := "%s.topics[%d]" % [at, index]
		if not raw is Dictionary:
			errors.append("%s: must be an object" % where)
			continue
		_keys(raw, TOPIC_KEYS, where, errors)
		var topic_id := str(raw.get("id", ""))
		if not _matches(topic_id, ID_PATTERN) or seen.has(topic_id):
			errors.append("%s.id: unique id matching %s" % [where, ID_PATTERN])
		var after: Array = []
		var earlier = raw.get("after", [])
		if not earlier is Array:
			errors.append("%s.after: list of earlier topic ids" % where)
			earlier = []
		for other in earlier:
			if not seen.has(str(other)):
				errors.append("%s.after: \"%s\" must be an earlier topic" % [where, str(other)])
			else:
				after.append(str(other))
		seen[topic_id] = true
		var needed: bool = raw.get("required", true) != false
		required += int(needed)
		result.append({"id": topic_id, "ask": _text(raw, "ask", where, errors, true), "answer": _text(raw, "answer", where, errors, true),
			"required": needed, "after": after})
	if required == 0:
		errors.append("%s.topics: at least one required topic" % at)
	return result

static func _window(value, at: String, errors: Array) -> Dictionary:
	if value == null:
		return {}
	if not value is Dictionary or not _number(value.get("from"), 0.0, 1440.0) or not _number(value.get("to"), 0.0, 1440.0):
		errors.append("%s.time_window: {\"from\": minute of day, \"to\": minute of day}" % at)
		return {}
	return {"from": float(value.from), "to": float(value.to)}

static func _area(value, case_def: Dictionary, at: String, errors: Array) -> Dictionary:
	if value == null:
		return {}
	if not value is Dictionary:
		errors.append("%s.area: {\"near\": reference, \"radius\": metres}" % at)
		return {}
	_keys(value, ["near", "radius"], at + ".area", errors)
	return {"near": _any_ref(value.get("near", ""), case_def, at + ".area.near", errors, true), "radius": _float(value, "radius", 0.5, 200.0, 10.0, at + ".area", errors)}

static func _fail_mode(raw: Dictionary, key: String, case_def: Dictionary, at: String, errors: Array) -> String:
	var mode := str(raw.get(key, "reset"))
	if mode != "reset" and not case_def.outcomes.has(mode):
		errors.append("%s.%s: \"reset\" or an outcome id" % [at, key])
		return "reset"
	return mode

# --- References --------------------------------------------------------------------

static func _participant_ref(value, case_def: Dictionary, at: String, errors: Array) -> String:
	var role := str(value).trim_prefix("participant:")
	if not case_def.participants.has(role):
		errors.append("%s: unknown participant role \"%s\"" % [at, str(value)])
		return ""
	return "participant:" + role

static func _prop_ref(value, case_def: Dictionary, at: String, errors: Array) -> String:
	var text := str(value)
	if not text.begins_with("prop:") or not case_def.props.has(text.trim_prefix("prop:")):
		errors.append("%s: \"prop:<id>\" of a declared prop" % at)
		return ""
	return text

## participant:<role>, <role>, prop:<id>, actor:<id>, incident:<role>, and for
## places route:<metres> or pos:x,y,z.
static func _any_ref(value, case_def: Dictionary, at: String, errors: Array, places: bool) -> String:
	var text := str(value)
	if text.begins_with("prop:"):
		return _prop_ref(text, case_def, at, errors)
	if text.begins_with("actor:"):
		if not _matches(text.trim_prefix("actor:"), ACTOR_PATTERN):
			errors.append("%s: \"actor:<id>\" needs an actor id" % at)
		return text
	if text.begins_with("incident:"):
		if case_def.incident.is_empty() or not text.trim_prefix("incident:") in INCIDENT_ROLES:
			errors.append("%s: incident:<offender|victim|witness|location> needs the case incident section" % at)
		return text
	if text.begins_with("route:") or text.begins_with("pos:"):
		if not places:
			errors.append("%s: a place is not a photo/follow subject" % at)
		elif text.begins_with("route:") and not _number_text(text.trim_prefix("route:"), 0.0, 5000.0):
			errors.append("%s: route:<metres along the walk>" % at)
		elif text.begins_with("pos:"):
			var parts := text.trim_prefix("pos:").split(",")
			if parts.size() != 3 or not _number_text(parts[0], -100000.0, 100000.0) or not _number_text(parts[1], -1000.0, 1000.0) or not _number_text(parts[2], -100000.0, 100000.0):
				errors.append("%s: pos:x,y,z" % at)
		return text
	return _participant_ref(text, case_def, at, errors)

# --- Whole-case checks ----------------------------------------------------------------

static func _cross_check(case_def: Dictionary, where: String, context: Dictionary, errors: Array, warnings: Array) -> void:
	var legacy: Dictionary = context.get("legacy", {})
	if legacy.has(case_def.id):
		var original: Dictionary = legacy[case_def.id]
		if not bool(case_def.legacy_slot):
			errors.append("%s: id belongs to an original case; set legacy_slot to migrate it" % where)
		elif int(original.get("reward", -1)) != int(case_def.reward.points) or int(original.get("stages", -1)) != case_def.stages.size() or str(original.get("title", "")) != str(case_def.title):
			errors.append("%s: a migrated original keeps its title, reward (%s) and stage count (%s)" % [where, str(original.get("reward")), str(original.get("stages"))])
	elif bool(case_def.legacy_slot):
		errors.append("%s: legacy_slot is only for the six original case ids" % where)
	# Evidence: required items must be grantable no later than the requiring stage.
	var granted_by := {}
	for stage in case_def.stages:
		for objective in stage.objectives:
			for evidence_id in objective.grants:
				if not granted_by.has(evidence_id):
					granted_by[evidence_id] = int(stage.index)
	for evidence_id in case_def.evidence:
		if not granted_by.has(evidence_id):
			warnings.append("%s.evidence.%s: no objective grants it" % [where, evidence_id])
	var objective_stage := {}
	var carried := {}
	for stage in case_def.stages:
		for objective in stage.objectives:
			objective_stage[objective.id] = int(stage.index)
	for stage in case_def.stages:
		for objective in stage.objectives:
			var at := "%s.%s" % [where, objective.id]
			for alternatives in objective.requires_evidence:
				var reachable := false
				for evidence_id in alternatives:
					reachable = reachable or int(granted_by.get(evidence_id, 99)) <= int(stage.index)
				if not reachable:
					errors.append("%s.requires_evidence: %s is never granted before this stage" % [at, "|".join(PackedStringArray(alternatives))])
			for other in objective.requires:
				if not objective_stage.has(other) or int(objective_stage[other]) > int(stage.index) or other == objective.id:
					errors.append("%s.requires: \"%s\" must be an objective in this or an earlier stage" % [at, other])
			if objective.verb == "collect":
				carried[objective.target] = int(stage.index)
			if objective.verb == "deliver" and int(carried.get(objective.item, 99)) > int(stage.index):
				errors.append("%s.item: %s is not collected before it is delivered" % [at, objective.item])
			if objective.verb == "photo" and objective.subject.begins_with("prop:") and objective.count > 1 and objective.min_interval_minutes <= 0.0:
				warnings.append("%s: several photos of a still prop need min_interval_minutes to differ" % at)
	var rewarded := 0
	for outcome in case_def.outcomes.values():
		rewarded += int(bool(outcome.rewarded))
	if int(case_def.reward.points) > 0 and rewarded == 0:
		errors.append("%s: reward points need a rewarded outcome" % where)
	for stage in case_def.stages:
		for objective in stage.objectives:
			if objective.verb == "photo" and objective.subject.begins_with("participant:"):
				var role: String = objective.subject.trim_prefix("participant:")
				if case_def.participants.has(role) and case_def.participants[role].bind == "step":
					warnings.append("%s.%s: photographing a \"step\" role accepts any listed person" % [where, objective.id])

# --- Small typed readers ---------------------------------------------------------------

static func _keys(source: Dictionary, allowed: Array, where: String, errors: Array) -> void:
	for key in source:
		if not str(key).begins_with("_") and not str(key) in allowed:
			errors.append("%s: unknown field \"%s\"" % [where, str(key)])

static func _text(source: Dictionary, key: String, where: String, errors: Array, required: bool, fallback := "") -> String:
	if not source.has(key):
		if required:
			errors.append("%s.%s: required text" % [where, key])
		return fallback
	var value = source[key]
	if not value is String or (required and str(value).strip_edges().is_empty()):
		errors.append("%s.%s: must be text" % [where, key])
		return fallback
	if str(value).length() > MAX_TEXT:
		errors.append("%s.%s: at most %d characters" % [where, key, MAX_TEXT])
		return str(value).left(MAX_TEXT)
	return str(value)

static func _float(source: Dictionary, key: String, low: float, high: float, fallback: float, where: String, errors: Array) -> float:
	if not source.has(key):
		return fallback
	if not _number(source[key], low, high):
		errors.append("%s.%s: number %s..%s" % [where, key, str(low), str(high)])
		return fallback
	return float(source[key])

static func _int(source: Dictionary, key: String, low: int, high: int, fallback: int, where: String, errors: Array) -> int:
	if not source.has(key):
		return fallback
	if not _integer(source[key], low, high):
		errors.append("%s.%s: whole number %d..%d" % [where, key, low, high])
		return fallback
	return int(source[key])

static func _string_list(source: Dictionary, key: String, where: String, errors: Array, max_length: int = 96) -> Array:
	var result: Array = []
	var value = source.get(key, [])
	if not value is Array:
		errors.append("%s.%s: list of text" % [where, key])
		return result
	for entry in value:
		if not entry is String or str(entry).is_empty() or str(entry).length() > max_length:
			errors.append("%s.%s: list of short text" % [where, key])
			return []
		result.append(str(entry))
	return result

static var _patterns: Dictionary = {}

static func _matches(text: String, pattern: String) -> bool:
	if not _patterns.has(pattern):
		var compiled := RegEx.new()
		compiled.compile(pattern)
		_patterns[pattern] = compiled
	var expression: RegEx = _patterns[pattern]
	return expression.search(text) != null

static func _number(value, low: float, high: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) >= low and float(value) <= high

static func _integer(value, low: int, high: int) -> bool:
	return _number(value, low, high) and float(value) == floorf(float(value))

static func _number_text(text: String, low: float, high: float) -> bool:
	var trimmed := text.strip_edges()
	return trimmed.is_valid_float() and _number(trimmed.to_float(), low, high)
