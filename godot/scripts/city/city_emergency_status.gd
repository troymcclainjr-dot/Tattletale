extends RefCounted
## Medical response vocabulary shared by city_emergency_response.gd (the only
## writer of medical transitions), city_incidents.gd (the durable record relay)
## and city_police_status.gd (incident cards). Pure and static: plain data in,
## plain data out.
##
## One medical call: requested -> queued | dispatched -> en_route -> staging ->
## on_scene -> treating -> resolved | failed | cancelled. "En route" only once
## the ambulance physically moved, "on scene" only once it stopped at the end of
## its route, "treating" only while a paramedic is with the injured person.
## Nothing here predicts: no ETA, countdown, distance remaining or percentage.
## Contract: .work/next-five-20261101/aftermath-contract.md.

## "injured" is the incident record's own fact (combat reported the injury);
## no medical call exists yet at that stage.
const STAGES := ["injured", "requested", "queued", "dispatched", "en_route", "staging", "on_scene", "treating",
	"resolved", "failed", "cancelled"]
const LIVE_STAGES := ["requested", "queued", "dispatched", "en_route", "staging", "on_scene", "treating"]
const PRE_ARRIVAL := ["requested", "queued", "dispatched", "en_route", "staging"]
## Timeline steps also record "cleared": the ambulance really drove away from
## the scene after the call closed (the road is free again). Never a stage.
const TIMELINE_STAGES := ["injured", "requested", "queued", "dispatched", "en_route", "staging", "on_scene", "treating",
	"resolved", "failed", "cancelled", "cleared"]
const OUTCOMES := ["treated", "unreachable", "blocked", "no_access", "unavailable", "unsafe", "timeout",
	"patient_left", "patient_died", "in_custody", "cancelled", "interrupted"]
const FAILED_OUTCOMES := ["unreachable", "blocked", "no_access", "unavailable", "unsafe", "timeout"]
const INJURIES := ["knocked_down", "hurt"]
const CLEARANCES := ["", "at_scene", "cleared"]
const MAX_TIMELINE := 6
const NOT_LIVE_TEXT := "This medical response is no longer active, so its result is unknown."
const LABELS := {"requested": "Ambulance requested", "queued": "Waiting for an ambulance",
	"dispatched": "Ambulance dispatched", "en_route": "Ambulance on the way",
	"staging": "Ambulance waiting until the scene is safe", "on_scene": "Ambulance at the scene",
	"treating": "Paramedics treating the injured person"}
const OUTCOME_LABELS := {"treated": "Treated by paramedics", "unreachable": "No road route for the ambulance",
	"blocked": "Ambulance could not get through", "no_access": "Paramedics could not reach the person",
	"unavailable": "No ambulance could come", "unsafe": "Scene never safe for paramedics",
	"timeout": "Medical response ran out of time", "patient_left": "The injured person left before help arrived",
	"patient_died": "The injured person died", "in_custody": "The injured person is in police custody",
	"cancelled": "Ambulance called off", "interrupted": "Medical response interrupted"}

static func is_live(stage) -> bool:
	return str(stage) in LIVE_STAGES

## Terminal stage for a medical outcome.
static func terminal_stage(outcome: String) -> String:
	if outcome == "treated":
		return "resolved"
	if outcome in FAILED_OUTCOMES:
		return "failed"
	return "cancelled"

static func label(stage: String, outcome := "") -> String:
	if LABELS.has(stage):
		return str(LABELS[stage])
	if stage == "injured":
		return "Someone was hurt"
	if stage == "cleared":
		return "Ambulance left the scene"
	return str(OUTCOME_LABELS.get(outcome, "Medical response closed"))

static func clearance_text(clearance: String) -> String:
	match clearance:
		"at_scene":
			return "the ambulance is still at the scene"
		"cleared":
			return "the ambulance has left the scene"
	return ""

## One line for an incident card. `live` is whether a medical call still
## answers the record in this session: a live stage without one (a reload) is
## never shown as still under way.
static func summary(medical: Dictionary, live := true) -> String:
	var stage := str(medical.get("stage", ""))
	if stage.is_empty() or stage == "injured":
		return ""
	if is_live(stage) and not live:
		return "Medical response interrupted"
	var text := label(stage, str(medical.get("outcome", "")))
	var road := clearance_text(str(medical.get("clearance", "")))
	if not road.is_empty() and stage in ["treating", "resolved", "failed", "cancelled"]:
		text += "; " + road
	return text

## What the player can usefully do. Never asks them to intervene or treat anyone.
static func next_action(stage: String, outcome := "") -> String:
	match stage:
		"requested", "queued", "dispatched", "en_route":
			return "Paramedics are coming for the injured person. Keep the street clear for the ambulance."
		"staging":
			return "Stay back. Paramedics go in once the scene is safe."
		"on_scene", "treating":
			return "Give the paramedics room to work."
	if outcome in FAILED_OUTCOMES or outcome == "interrupted":
		return "If someone is still hurt, report it again."
	return ""

static func injury_text(injury: String) -> String:
	return "knocked down" if injury == "knocked_down" else "hurt"
