extends RefCounted
## Ambient incident templates for city_incidents.gd. Every entry is grounded in
## an existing scenario: the original block's crime list (js/crimes-*.js) or a
## Pen Lucy case (city_missions.gd). No new story, case or dialogue lives here:
## a template only says what a real neighbor physically does, who may report it
## and how the police respond proportionately.
##
## Fields: title/origin (provenance), category, policy ("warn" = an officer stops
## the person and issues a warning; "detain" = warn, comply, custody), weight
## (ambient spawn share; 0 = external/case use only), people (1 offender, or 2
## with a victim), npc_reports (who besides the player may call it in: "none",
## "victim" or "witness") and report_delay (seconds before that call).

const TEMPLATES := {
	"jaywalking": {"title": "Jaywalking", "origin": "js/crimes-stage1.js:granny",
		"category": "infraction", "policy": "warn", "weight": 3, "people": 1,
		"npc_reports": "none", "report_delay": [0.0, 0.0]},
	"mail_tampering": {"title": "Bending the mail", "origin": "js/crimes-stage1.js:mail; city_missions.gd:parcel_report",
		"category": "infraction", "policy": "warn", "weight": 2, "people": 1,
		"npc_reports": "none", "report_delay": [0.0, 0.0]},
	"sidewalk_dumping": {"title": "Keep the sidewalk clear", "origin": "city_missions.gd:dumping",
		"category": "infraction", "policy": "warn", "weight": 2, "people": 1,
		"npc_reports": "none", "report_delay": [0.0, 0.0]},
	"bag_snatch": {"title": "Lost satchel", "origin": "city_missions.gd:lost_satchel; js/crimes-stage1.js:ricky",
		"category": "theft", "policy": "detain", "weight": 1, "people": 2,
		"npc_reports": "victim", "report_delay": [5.0, 9.0]},
	"street_fight": {"title": "Street fight", "origin": "city_combat.gd neighbor melee",
		"category": "violence", "policy": "detain", "weight": 1, "people": 2,
		"npc_reports": "witness", "report_delay": [4.0, 8.0]},
	# External sources (cases, traffic): opened through open_incident(), never spawned.
	"red_light": {"title": "Running a red light", "origin": "js/crimes-stage2.js:mama",
		"category": "infraction", "policy": "warn", "weight": 0, "people": 1,
		"npc_reports": "none", "report_delay": [0.0, 0.0]},
	"case": {"title": "Neighborhood case", "origin": "city cases",
		"category": "infraction", "policy": "warn", "weight": 0, "people": 1,
		"npc_reports": "none", "report_delay": [0.0, 0.0]},
}

static func has(id: String) -> bool:
	return TEMPLATES.has(id)

static func template(id: String) -> Dictionary:
	return (TEMPLATES.get(id, {}) as Dictionary).duplicate(true)

static func ambient_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in TEMPLATES:
		if int(TEMPLATES[id].weight) > 0:
			ids.append(str(id))
	ids.sort()
	return ids

## Weighted choice from `allowed` with a caller-owned generator (deterministic).
static func pick(rng: RandomNumberGenerator, allowed: Array) -> String:
	var total := 0
	for id in allowed:
		total += int(TEMPLATES.get(id, {}).get("weight", 0))
	if total <= 0:
		return ""
	var roll := rng.randi_range(1, total)
	for id in allowed:
		roll -= int(TEMPLATES.get(id, {}).get("weight", 0))
		if roll <= 0:
			return str(id)
	return str(allowed[-1])
