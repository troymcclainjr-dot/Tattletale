extends RefCounted
## Police dispatch status shared by city_police_assistance.gd (the only writer
## of dispatch transitions) and the phone's Police page (bounded status cards).
## Pure and static: plain dictionaries in, plain dictionaries out.
##
## Dispatch state (one police call) and incident state (the incident service's
## durable record) stay distinct, and a card shows both. Nothing here predicts:
## there is no ETA or progress percentage anywhere, "en route" comes only from a
## unit that physically moved, and a reported record whose police response is
## not live (a reload) is never shown as still being answered.

## received -> queued | dispatched -> en_route -> on_scene -> handling ->
## resolved | failed | cancelled. "unavailable" is an intake refusal: no call.
const STAGES := ["received", "queued", "dispatched", "en_route", "on_scene", "handling", "resolved", "failed", "cancelled", "unavailable"]
const LIVE_STAGES := ["received", "queued", "dispatched", "en_route", "on_scene", "handling"]
const PRE_ARRIVAL := ["received", "queued", "dispatched", "en_route"]
const HANDLING := ["contact", "warning", "commands", "detaining", "arrest", "force"]
const MAX_CARDS := 4
## Police answer at most this many calls at once (city_police_assistance
## MAX_INCIDENTS); the player's reports among them are listed however old.
const MAX_LIVE_CALLS := 3
const MAX_TIMELINE := 8
const CARD_TIMELINE := 4
const CLOSED_RECORD_STATES := ["resolved", "expired", "cancelled"]
const NOT_LIVE_TEXT := "This response is no longer active, so its result is unknown."
const HANDLING_LABELS := {"contact": "Officer talking with the person", "warning": "Warning issued",
	"commands": "Officers giving commands", "detaining": "Detaining a suspect", "arrest": "Suspect arrested",
	"force": "Police used force: armed threat"}
const RESOLVED_LABELS := {"warned": "Resolved: warning issued", "arrested": "Resolved: arrest made",
	"suspect_killed": "Closed: scene secured", "suspect_left": "Closed: the person had left",
	"no_threat": "Closed: area checked", "case_resolved": "Resolved through the case"}
const SUBJECT_STATES := {"in_custody": [6, "in custody"], "escort": [6, "arrested"], "cuffed": [6, "arrested"],
	"held": [5, "detained"], "cited": [4, "warned by an officer"], "dead": [4, "did not survive"],
	"down": [3, "down"], "warned": [2, "stopped by an officer"], "at_large": [1, "not yet with officers"],
	"lost": [1, "left before officers found them"], "released": [1, "released"]}
const ACCENTS := {"live": Color("7cbcff"), "handling": Color("f2d24a"), "resolved": Color("2f9e5b"),
	"failed": Color("d0182e"), "cancelled": Color("a3b4ae"), "unavailable": Color("d0182e")}
const DEFAULT_ACTION_HINT := "Officers warn, detain or arrest as needed. You never have to step in."

## Coarse status kept for existing consumers (incident relay, fixtures).
static func coarse_status(stage: String, outcome := "") -> String:
	match stage:
		"received", "queued":
			return "report_received"
		"dispatched", "en_route":
			return "responding"
		"on_scene", "handling":
			return "on_scene"
		"unavailable":
			return "unavailable"
	return "unavailable" if outcome == "unavailable" else "resolved"

## Terminal dispatch stage for a police outcome.
static func terminal_stage(outcome: String) -> String:
	if outcome in ["unavailable", "timeout"]:
		return "failed"
	if outcome in ["interrupted", "cancelled"]:
		return "cancelled"
	return "resolved"

## Dispatch stage for a closed incident record (its durable resolution outcome).
static func record_stage(outcome: String) -> String:
	if outcome in ["unanswered", "timeout"]:
		return "failed"
	if outcome in ["interrupted", "cancelled", "expired"]:
		return "cancelled"
	return "resolved"

static func is_live(stage: String) -> bool:
	return stage in LIVE_STAGES

static func label(stage: String, handling := "", outcome := "") -> String:
	match stage:
		"received":
			return "Report received"
		"queued":
			# Neutral: a queued call may have no free officer or none that can get there.
			return "Waiting for a response"
		"dispatched":
			return "Officer dispatched"
		"en_route":
			return "Officer on the way"
		"on_scene":
			return "Officer at the scene"
		"handling":
			return str(HANDLING_LABELS.get(handling, "Officers handling it"))
		"unavailable":
			return "Call not taken"
		"failed":
			return "Officers stood down" if outcome == "timeout" else "No officer could come"
		"cancelled":
			return "Response called off" if outcome == "cancelled" else "Response interrupted"
	return str(RESOLVED_LABELS.get(outcome, "Resolved"))

## What the player can usefully do now. Never asks them to intervene.
static func next_action(stage: String, handling := "", outcome := "", case_linked := false) -> String:
	match stage:
		"received", "queued":
			return "Stay somewhere safe. This card will say if no officer can come."
		"dispatched", "en_route":
			return "Keep clear of the scene. Officers handle it; you never need to step in."
		"on_scene":
			return "Keep your distance while officers check the area."
		"handling":
			if handling == "force":
				return "Take cover and stay out of the line until the scene is secure."
			if handling in ["contact", "warning"]:
				return "Officers are talking with the person. Nothing else is needed from you."
			return "Stay back while officers detain the person."
		"unavailable":
			return "All officers are busy. Try again shortly."
		"failed":
			return "If it is still happening, stay somewhere safe and call again."
		"cancelled":
			return "If there is still a problem here, call again."
	if case_linked:
		return "Check Cases for what happens next."
	if outcome == "suspect_left":
		return "If it happens again, report what you see from here."
	return "Nothing else is needed."

static func accent(stage: String) -> Color:
	if stage == "handling":
		return ACCENTS.handling
	if is_live(stage):
		return ACCENTS.live
	return ACCENTS.get(stage, ACCENTS.cancelled)

## Game-clock time of day ("14:32"); "" when unknown.
static func clock_text(minutes) -> String:
	if not (minutes is float or minutes is int) or not is_finite(float(minutes)) or float(minutes) < 0.0:
		return ""
	var whole := floori(fposmod(float(minutes), 1440.0))
	return "%02d:%02d" % [whole / 60, whole % 60]

## "1 officer on foot and 1 police car"; "" when nobody is assigned.
static func responders_text(responders) -> String:
	if not responders is Dictionary:
		return ""
	var parts: Array[String] = []
	var foot := int(responders.get("foot", 0))
	var cars := int(responders.get("cars", 0))
	if foot > 0:
		parts.append("1 officer on foot" if foot == 1 else "%d officers on foot" % foot)
	if cars > 0:
		parts.append("1 police car" if cars == 1 else "%d police cars" % cars)
	return " and ".join(parts)

## The people involved, as officers actually know them (police suspect states).
static func subject_text(call: Dictionary) -> String:
	var suspects = call.get("suspects", [])
	if not suspects is Array or (suspects as Array).is_empty():
		return "" if not str(call.get("ref", "")).is_empty() else "No one named; officers check the area"
	if (suspects as Array).size() > 1:
		return "%d people involved" % (suspects as Array).size()
	var entry = SUBJECT_STATES.get(str((suspects as Array)[0].get("state", "")), [0, ""])
	return "Person involved: " + str(entry[1]) if not str(entry[1]).is_empty() else ""

## The phone's report button for incidents.phone_report_preview(at): it names
## exactly what pressing it files. {button, hint}.
static func report_action(preview: Dictionary) -> Dictionary:
	var title := str(preview.get("title", ""))
	var street := str(preview.get("street", ""))
	var where := (" near " + street) if not street.is_empty() else ""
	if str(preview.get("kind", "")) == "incident" and not title.is_empty():
		if bool(preview.get("yours", false)):
			return {"button": "Check on your report: " + title,
				"hint": "You already reported this%s. Asking again shows its status and never sends a second response." % where}
		if bool(preview.get("already_reported", false)):
			return {"button": "Confirm the report: " + title,
				"hint": "A neighbor already reported this%s. Your account joins that report; officers are not sent twice." % where}
		return {"button": "Report what you saw: " + title,
			"hint": "You saw this happen%s. A report shares what you saw and where; officers decide how to respond." % where}
	return {"button": "Ask officers to check here",
		"hint": "Nothing you witnessed is close by. A call shares your location; officers check it and act only on violence they find."}

## Bounded phone cards from police dispatch_view() and the incident records the
## player reported or corroborated (incidents.reports_for("player")). A linked
## call merges into its record's card (one card per incident). Live cards come
## first, then the most recent closed ones; at most `limit`.
static func cards(view: Dictionary, records: Array, limit := MAX_CARDS) -> Array:
	var live: Array = view.get("live", []) if view.get("live") is Array else []
	var history: Array = view.get("history", []) if view.get("history") is Array else []
	var refusals: Array = view.get("refusals", []) if view.get("refusals") is Array else []
	var live_by_ref: Dictionary = {}
	var closed_by_ref: Dictionary = {}
	for call in live:
		if call is Dictionary and not str(call.get("ref", "")).is_empty():
			live_by_ref[str(call.ref)] = call
	for call in history:
		if call is Dictionary and not str(call.get("ref", "")).is_empty():
			closed_by_ref[str(call.ref)] = call # Later (newer) entries win.
	var result: Array = []
	var used: Dictionary = {}
	for rec in records:
		if not rec is Dictionary or str(rec.get("id", "")).is_empty():
			continue
		var id := str(rec.id)
		used[id] = true
		result.append(_record_card(rec, live_by_ref.get(id, {}), closed_by_ref.get(id, {})))
	for list in [live, history]:
		for call in list:
			if not call is Dictionary or not bool(call.get("phone", false)):
				continue # Only the player's own calls; neighbors' reports are theirs.
			if str(call.get("source", "")) == "report":
				continue # A filed report is shown through its durable record only.
			var ref := str(call.get("ref", ""))
			if not ref.is_empty() and used.has(ref):
				continue
			var key := "call:" + str(call.get("id", ""))
			if used.has(key):
				continue
			used[key] = true
			result.append(_call_card(call))
	for refusal in refusals:
		if refusal is Dictionary:
			result.append(_refusal_card(refusal))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return bool(a.live) if bool(a.live) != bool(b.live) else float(a.updated) > float(b.updated))
	return result.slice(0, maxi(0, limit))

static func _call_card(call: Dictionary) -> Dictionary:
	var stage := str(call.get("stage", ""))
	var outcome := str(call.get("outcome", ""))
	if stage.is_empty():
		stage = terminal_stage(outcome) if not outcome.is_empty() else "received"
	var title := "Area check"
	match str(call.get("threat", "")):
		"armed":
			title = "Armed person reported"
		"violent":
			title = "Violence reported"
	var card := _card("call:" + str(call.get("id", "")), title, str(call.get("street", "")), stage,
		str(call.get("handling", "")), outcome, str(call.get("message", "")), false)
	card.responders = responders_text(call.get("responders", {})) if is_live(stage) else ""
	card.incident = subject_text(call)
	card.opened = float(call.get("opened_minutes", -1.0))
	card.updated = maxf(float(call.get("updated_minutes", -1.0)), card.opened)
	card.timeline = _timeline_lines(call.get("timeline", []), outcome)
	return _finish(card)

static func _record_card(rec: Dictionary, live_call: Dictionary, closed_call: Dictionary) -> Dictionary:
	var report: Dictionary = rec.get("report", {}) if rec.get("report") is Dictionary else {}
	var resolution: Dictionary = rec.get("resolution", {}) if rec.get("resolution") is Dictionary else {}
	var case_linked := str(rec.get("source", "")).begins_with("case:") or not str(rec.get("case_id", "")).is_empty()
	var state := str(rec.get("state", ""))
	var stage := ""
	var handling := ""
	var outcome := ""
	var text := ""
	var police: Dictionary = {}
	if state in CLOSED_RECORD_STATES:
		# The durable record is the truth about how it ended (also after a reload).
		outcome = str(resolution.get("outcome", ""))
		stage = record_stage(outcome)
		text = str(resolution.get("text", ""))
		police = closed_call if not closed_call.is_empty() else live_call
	elif not live_call.is_empty() and not bool(live_call.get("closing", false)):
		police = live_call
		stage = str(live_call.get("stage", "received"))
		handling = str(live_call.get("handling", ""))
		text = str(live_call.get("message", ""))
	else:
		# Reported, but no live police call answers it (a checkpoint was loaded):
		# never shown as still being answered.
		stage = "cancelled"
		outcome = "interrupted"
		text = NOT_LIVE_TEXT
		police = closed_call
	var card := _card("incident:" + str(rec.get("id", "")), str(rec.get("title", "Report")), str(rec.get("street", "")),
		stage, handling, outcome, text, case_linked)
	var when := clock_text(report.get("minutes", -1.0))
	var at_time := (" at " + when) if not when.is_empty() else ""
	var who := ""
	if str(report.get("by", "")) == "player":
		who = "You reported it" + at_time
	elif not report.is_empty():
		var corroborating = report.get("corroborating", [])
		who = "A neighbor reported it" + at_time + ("; you confirmed it" if corroborating is Array and "player" in corroborating else "")
	var parts: Array[String] = []
	if not who.is_empty():
		parts.append(who)
	if not police.is_empty() and is_live(stage):
		var subject := subject_text(police)
		if not subject.is_empty():
			parts.append(subject)
	card.incident = ". ".join(parts)
	card.responders = responders_text(police.get("responders", {})) if is_live(stage) and not police.is_empty() else ""
	card.opened = float(report.get("minutes", rec.get("created_minutes", -1.0)))
	card.updated = maxf(maxf(float(resolution.get("minutes", -1.0)), float(rec.get("updated_minutes", -1.0))), card.opened)
	if not police.is_empty() and police.get("timeline") is Array and not (police.timeline as Array).is_empty():
		card.timeline = _timeline_lines(police.timeline, outcome)
	else:
		var lines: Array = []
		if not when.is_empty():
			lines.append({"time": when, "label": "Report received"})
		if state in CLOSED_RECORD_STATES:
			lines.append({"time": clock_text(resolution.get("minutes", -1.0)), "label": label(stage, "", outcome)})
		card.timeline = lines
	return _finish(card)

static func _refusal_card(refusal: Dictionary) -> Dictionary:
	var card := _card("refusal:" + str(refusal.get("id", "")), "Call not taken", str(refusal.get("street", "")), "unavailable",
		"", "", str(refusal.get("text", "")), false)
	card.opened = float(refusal.get("minutes", -1.0))
	card.updated = card.opened
	card.timeline = [{"time": clock_text(card.opened), "label": "Call not taken"}]
	return _finish(card)

static func _card(key: String, title: String, street: String, stage: String, handling: String, outcome: String,
		text: String, case_linked: bool) -> Dictionary:
	return {"key": key, "title": title, "street": street, "where": ("Near " + street) if not street.is_empty() else "",
		"stage": stage, "handling": handling, "outcome": outcome, "label": label(stage, handling, outcome),
		"text": text, "next": next_action(stage, handling, outcome, case_linked), "live": is_live(stage),
		"case_linked": case_linked, "incident": "", "responders": "", "opened": -1.0, "updated": -1.0,
		"time": "", "timeline": [], "accent": accent(stage)}

static func _finish(card: Dictionary) -> Dictionary:
	card.time = clock_text(card.opened)
	var lines: Array = card.timeline
	if lines.size() > CARD_TIMELINE:
		card.timeline = lines.slice(lines.size() - CARD_TIMELINE)
	return card

static func _timeline_lines(entries, outcome: String) -> Array:
	var lines: Array = []
	if not entries is Array:
		return lines
	for entry in entries:
		if not entry is Dictionary:
			continue
		var stage := str(entry.get("stage", ""))
		lines.append({"time": clock_text(entry.get("minutes", -1.0)),
			"label": label(stage, str(entry.get("handling", "")), str(entry.get("outcome", outcome)))})
	return lines
