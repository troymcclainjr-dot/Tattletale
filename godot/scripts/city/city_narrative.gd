extends RefCounted
## "Petal Pushers": a short three-part branching chain about the unlicensed
## flower cart that daily resident Ines Morales runs on Dumbarton Avenue
## (report / protect / negotiate / intimidate), plus bounded, repeatable,
## lawful errands so cash never runs out for good. Authored here like the six
## neighborhood cases in city_missions.gd; every number (reputation,
## relationships, money, cooldown) is progression data. Durable choices and
## relationships live in progression; the active part/stage is the ordinary
## mission active_id/stage. Contacts are existing authored or daily-resident
## identities. Nobody is revived or respawned, and nothing reads appearance.
## Nonviolent policy (city_play_mode.gd RETIRED_STORY_OPTIONS): coercive
## options stay authored below but are never offered or committed. A save that
## already took the intimidate branch keeps it and can only end it by making
## amends; if a remaining decision has no reachable option left, the part is
## put on hold (never soft-locked) until the player can afford it.

const PlayMode := preload("res://scripts/city/city_play_mode.gd")
const VENDOR := "daily_ines_morales"
const CALL := "petals_call"
const FINAL := "petals_final"
const CLOSED_FLAG := "petals_closed"
const BRANCHES := ["report", "protect", "negotiate", "intimidate"]
const INTERACT_RADIUS := 2.4
const BARK_RADIUS := 6.0
const BARK_COOLDOWN := 90.0
const BARK_GAP := 15.0
const LOW_CASH := 40
const CASH_HINT_GAP := 600.0
## Ordered stand-ins: the first living, present identity takes the step.
const ROLES := {
	"@police": ["officer", "patrol_officer_0", "patrol_officer_1", "patrol_officer_2", "patrol_officer_3", "patrol_officer_4", "patrol_officer_5"],
	"@street": ["lookout", "ambient_neighbor", "ambient_granny"],
	"@organizer": ["organizer", "daily_aisha_bell"],
	# Walking neighbors first: they never hold a case offer that would hide the job.
	"@carrier": ["ambient_mailman", "ambient_granny", "ambient_neighbor", "caretaker", "gardener", "organizer"],
}
const ROLE_NAMES := {"@police": "An officer", "@street": "Someone on the Dumbarton corner", "@organizer": "The block organizer",
	"@carrier": "The mail carrier", "@recipient": "A neighbor"}
const STAND_INS := {
	"@police": "Officer Dan's not on this beat anymore. I'll take it from here.",
	"@street": "Malik's not around anymore, but the corner still talks.",
	"@organizer": "The organizer's gone, so the block association sent me.",
}
## Every story/errand offer comes from one of these (plain id or token).
const GIVERS := [VENDOR, "@street", "@police", "@carrier"]
## Delivery recipients rotate by completed run; the giver is skipped.
const RECIPIENTS := ["gardener", "organizer", "caretaker", "resident", "daily_nadine_brooks", "daily_celia_grant", "daily_ruth_daniels",
	"daily_theo_washington", "daily_june_harris", "daily_pearl_sutton"]
const NAMES := {"daily_ines_morales": "Ines Morales", "officer": "Officer Dan", "lookout": "Malik", "organizer": "Block organizer",
	"resident": "Ms. Lena", "gardener": "Community gardener", "caretaker": "Porch caretaker", "ambient_mailman": "Mail carrier",
	"ambient_neighbor": "Neighbor", "ambient_granny": "Neighbor", "daily_aisha_bell": "Aisha Bell"}

const PARTS := {
	"petals_word": {"title": "The flower cart complaint", "part": 1, "branch": "", "reward": 0, "givers": [VENDOR, "@street"],
		"accept": "Tell me about the cart complaint.",
		"pitch": "You're 2-Pack, right? The neighborhood watch? Somebody called in a complaint about my flower cart.",
		"pitches": {"@street": "Heads up, 2-Pack. Somebody called in Ines's flower cart on Dumbarton. No permit, they say."},
		"steps": [
			{"target": VENDOR, "objective": "Hear Ines out about the flower cart complaint", "prompt": "E  Ask about the complaint",
				"dialogue": "Eleven years I've sold sunflowers on this corner. Now somebody says I need a vendor permit, and my cart sits a foot past the curb line. Officer Dan wants to know who runs it."},
			{"target": "@street", "objective": "Ask the Dumbarton corner what people are saying", "prompt": "E  Ask what the corner heard",
				"dialogue": "Whole corner knows, 2-Pack. Dan wants a name, and everybody knows you're the one who talks to Dan. Whatever you do next, Dumbarton is watching."},
			{"target": VENDOR, "decision": CALL, "objective": "Decide what to do about Ines's cart", "prompt": "E  Decide about the cart",
				"dialogue": "So, neighborhood watch. Are you going to tell on my sunflowers?",
				"options": [
					{"option": "report", "text": "Rules are rules, Ines. I'm telling Officer Dan.",
						"outcome": "Then go tell him. I'll be right here selling sunflowers until he makes me stop."},
					{"option": "protect", "text": "Nobody touches this cart. Dan gets nothing from me.",
						"outcome": "For a flower cart? ...Dumbarton's lucky to have you, 2-Pack."},
					{"option": "negotiate", "text": "Let's get you a permit before Dan writes anything.",
						"outcome": "If you can get the paperwork moving, I'll sign whatever they want."},
					{"option": "intimidate", "text": "Silence costs, Ines. Call it a $%d corner fee.", "amount": "petals_call_intimidate",
						"outcome": "A corner fee. On sunflowers. ...Fine. Take it and leave my cart alone."}]}]},
	"petals_report": {"title": "Telling Officer Dan", "part": 2, "branch": "report", "reward": 90, "givers": [VENDOR, "@street"],
		"accept": "Let's finish this.", "pitch": "Officer Dan is still waiting on your report, neighborhood watch.",
		"steps": [
			{"target": "@police", "objective": "File the vendor report with Officer Dan", "prompt": "E  File the vendor report",
				"dialogue": "Unlicensed vending, cart past the curb line. Noted. I'll write a warning, not a fine. Hand it to Ms. Morales for me? It lands softer from a neighbor."},
			{"target": VENDOR, "objective": "Deliver Officer Dan's warning to Ines", "prompt": "E  Hand over the warning",
				"dialogue": "A warning, hand-delivered by the neighborhood watch. I'll file for the permit. Don't expect a sunflower from me."}]},
	"petals_protect": {"title": "Nobody saw nothing", "part": 2, "branch": "protect", "reward": 0, "givers": [VENDOR, "@street"],
		"accept": "Let's finish this.", "pitch": "Dan is still asking questions about my cart.",
		"steps": [
			{"target": "@street", "objective": "Tell the corner that Ines's cart is covered", "prompt": "E  Pass the word",
				"dialogue": "Say less. If Dan asks, nobody on Dumbarton has seen a flower in their whole life."},
			{"target": "@police", "objective": "Stonewall Officer Dan about the cart", "prompt": "E  Tell Dan you saw nothing",
				"dialogue": "Nobody knows whose cart it is? On a block with forty porches? Fine. But I'll be keeping an eye on that corner myself."},
			{"target": VENDOR, "objective": "Tell Ines her cart is covered", "prompt": "E  Tell Ines she's covered",
				"dialogue": "You stood up for me in front of Dan? Here, sunflower money. Don't argue with me."}]},
	"petals_negotiate": {"title": "Permit paperwork", "part": 2, "branch": "negotiate", "reward": 60, "givers": [VENDOR, "@street"],
		"accept": "Let's finish this.", "pitch": "Any news on that permit paperwork?",
		"steps": [
			{"target": "@organizer", "objective": "Get a vendor permit form from the block organizer", "prompt": "E  Ask about vendor permits",
				"dialogue": "Vendor permits? The block association keeps the forms. The fee is waived if a neighbor vouches. Take this one to Ines."},
			{"target": VENDOR, "objective": "Bring the permit form to Ines", "prompt": "E  Hand over the permit form",
				"dialogue": "You'd vouch for me? Then I'll sign, and I'll move the cart back behind the curb line. Tell Dan it's pending."},
			{"target": "@police", "objective": "Tell Officer Dan the permit is pending", "prompt": "E  Report the pending permit",
				"dialogue": "Permit pending and the cart's behind the curb? That's all I needed. No warning. Nice work, 2-Pack."}]},
	"petals_intimidate": {"title": "The corner fee", "part": 2, "branch": "intimidate", "reward": 0, "givers": [VENDOR, "@street"],
		"accept": "Let's finish this.", "pitch": "The corner is still talking about your fee.",
		"steps": [
			{"target": "@street", "objective": "Let the corner know Ines pays a fee now", "prompt": "E  Tell the corner about the fee",
				"dialogue": "You're taxing a flower cart? That's cold, 2-Pack. The corner's going to talk about this for weeks."},
			{"target": "@police", "objective": "Keep Officer Dan away from the corner", "prompt": "E  Steer Dan away",
				"dialogue": "Nothing to see on Dumbarton? Funny. Ms. Morales looked scared this morning. I'll remember that, 2-Pack."}]},
	"petals_end_report": {"title": "Sunflowers and paperwork", "part": 3, "branch": "report", "reward": 0, "givers": [VENDOR],
		"accept": "What happened with the permit?", "pitch": "The permit office bounced my form. Twice. You started this, so you can help me finish it.",
		"steps": [
			{"target": "@organizer", "objective": "Ask the block organizer why Ines's permit bounced", "prompt": "E  Ask about the bounced permit",
				"dialogue": "Her form bounced on a missing signature. The association can resubmit it, but someone has to walk it over and tell her."},
			{"target": VENDOR, "decision": FINAL, "objective": "Settle things with Ines", "prompt": "E  Settle things with Ines",
				"dialogue": "Well? Did you come to help, or to check if I'm still breaking the rules?",
				"options": [
					{"option": "report_amends", "text": "I'll walk your form in myself. My bad, Ines.", "outcome": "...Thank you. You're still a snitch. A helpful one."},
					{"option": "report_firm", "text": "The law is the law, Ines. Fix it yourself.", "outcome": "Then I'll fix it without you. Stay off my side of the street."}]}]},
	"petals_end_protect": {"title": "Dan's stakeout", "part": 3, "branch": "protect", "reward": 0, "givers": [VENDOR],
		"accept": "Tell me about Dan.", "pitch": "Officer Dan has parked himself by my cart all week. I can't sell like this.",
		"steps": [
			{"target": "@police", "objective": "Hear Officer Dan out about the stakeout", "prompt": "E  Ask about the stakeout",
				"dialogue": "A week by that cart and still no permit. Last chance, 2-Pack. Either she files, or I write it up."},
			{"target": VENDOR, "decision": FINAL, "objective": "Tell Ines how this ends", "prompt": "E  Tell Ines how this ends",
				"dialogue": "Dan's still out there. What do we do, 2-Pack?",
				"options": [
					{"option": "protect_amends", "text": "File the permit. I'll walk it to Dan myself.", "outcome": "Paper armor. Fine. Smart, even."},
					{"option": "protect_firm", "text": "Keep selling. This corner answers to us.", "outcome": "Then the sunflowers keep coming. Dumbarton's protector."}]}]},
	"petals_end_negotiate": {"title": "Grand reopening", "part": 3, "branch": "negotiate", "reward": 0, "givers": [VENDOR],
		"accept": "Let's celebrate.", "pitch": "The permit came through! Come by the cart, I owe you.",
		"steps": [
			{"target": "@organizer", "objective": "Hear the permit news from the block organizer", "prompt": "E  Ask about the permit",
				"dialogue": "Approved. Ines Morales is the first licensed vendor on Dumbarton. The association wants to put you in the newsletter."},
			{"target": VENDOR, "decision": FINAL, "objective": "Celebrate with Ines", "prompt": "E  Celebrate with Ines",
				"dialogue": "Licensed! Eleven years and one neighborhood watch later. Let me pay you something.",
				"options": [
					{"option": "negotiate_amends", "text": "Keep it. Just keep the sunflowers coming.", "outcome": "Then you get the first sunflowers every morning."},
					{"option": "negotiate_firm", "text": "Ten percent of sales. Call it a consulting fee.", "outcome": "Ten percent? ...Fine. Paperwork isn't free, I guess."}]}]},
	"petals_end_intimidate": {"title": "Payback", "part": 3, "branch": "intimidate", "reward": 0, "givers": [VENDOR],
		"accept": "What did Dan say?", "pitch": "I went to Officer Dan about your corner fee. He wants a word with you.",
		"steps": [
			{"target": "@police", "objective": "Face Officer Dan about the corner fee", "prompt": "E  Hear Dan out",
				"dialogue": "Ms. Morales says somebody's charging her a corner fee. Your name came up. I can't prove it, so I'm asking you to make it right."},
			{"target": VENDOR, "decision": FINAL, "objective": "Decide what Ines is owed", "prompt": "E  Face Ines",
				"dialogue": "Dan says he talked to you. So? Do I keep paying?",
				"options": [
					{"option": "intimidate_amends", "text": "Here's your $%d back. I was out of line.", "amount": "petals_final_intimidate_amends",
						"unmet": "I can't pay you back yet. (Need $%d)", "outcome": "You actually paid it back. I didn't think you would."},
					{"option": "intimidate_firm", "text": "The fee's going up. Another $%d.", "amount": "petals_final_intimidate_firm",
						"outcome": "Take it. Just... keep walking, 2-Pack."}]}]},
}

const ENDINGS := {
	"report_amends": {"label": "Snitch with a heart", "summary": "Ines got her permit with your help. She still calls you a snitch, but she smiles when she says it.", "sign": "PERMIT ON FILE"},
	"report_firm": {"label": "By the book", "summary": "Officer Dan commended you. Ines keeps her distance and her receipts.", "sign": "CITED · PERMIT REQUIRED"},
	"protect_amends": {"label": "Paper armor", "summary": "The permit is filed and Officer Dan backed off. Everyone wins, mostly.", "sign": "PERMIT ON FILE"},
	"protect_firm": {"label": "Dumbarton's protector", "summary": "The corner answers to 2-Pack now. Officer Dan is watching.", "sign": "PROTECTED CORNER"},
	"negotiate_amends": {"label": "Block broker", "summary": "Ines is Dumbarton's first licensed vendor, and the block association loves you.", "sign": "LICENSED VENDOR"},
	"negotiate_firm": {"label": "Middleman", "summary": "Ines pays your consulting fee. The newsletter left your name out.", "sign": "LICENSED · ASK ABOUT FEES"},
	"intimidate_amends": {"label": "Changed tune", "summary": "You paid Ines back. Officer Dan is willing to forget the whole thing.", "sign": "OPEN AGAIN"},
	"intimidate_firm": {"label": "Petal tax collector", "summary": "Ines pays, Officer Dan suspects, and Dumbarton goes quiet when you walk by.", "sign": "CORNER FEE PAID"},
}

## Repeatable and never completed. Payouts and unlocks are progression errand
## variants; one shared durable cooldown bounds the income rate.
const ERRANDS := {
	"errand_delivery": {"title": "Block delivery", "variant": "delivery", "giver": "@carrier", "offset": 0, "prop": "parcel", "carry": true,
		"banner": "PARCEL DELIVERED", "pitch": "Got a parcel for a neighbor and too many stops left. $%d if you run it over.",
		"accept": "I'll run it over. ($%d)",
		"steps": [{"target": "@recipient", "objective": "Deliver the parcel to %s", "prompt": "E  Deliver the parcel",
			"dialogue": "That's mine! Thanks for bringing it by."}]},
	"errand_flowers": {"title": "Flower delivery", "variant": "flowers", "giver": VENDOR, "offset": 5, "prop": "bouquet", "carry": true,
		"banner": "SUNFLOWERS DELIVERED", "pitch": "I've got sunflowers that need to get across the block. $%d, and don't squash them.",
		"accept": "Sunflower delivery, coming up. ($%d)",
		"steps": [{"target": "@recipient", "objective": "Deliver Ines's sunflowers to %s", "prompt": "E  Deliver the sunflowers",
			"dialogue": "Sunflowers from Ines? That just made my whole day."}]},
	"errand_watch": {"title": "Watch walk", "variant": "watch", "giver": "@police", "prop": "checkpoint", "distance": 140.0, "spread": 160,
		"passable": true, "banner": "ALL QUIET · REPORTED", "clue": "WATCH CHECKPOINT",
		"pitch": "Walk the watch route, check the corner I mark, and report back. The watch fund pays $%d.", "accept": "I'll walk the route. ($%d)",
		"steps": [
			{"target": "clue", "objective": "Check the watch checkpoint along Old York", "prompt": "E  Check the corner",
				"dialogue": "All quiet at the checkpoint. Nothing to report, which is the best kind of report."},
			{"target": "@police", "objective": "Report back to the officer", "prompt": "E  Report all quiet",
				"dialogue": "All quiet. That's what I like to hear. Here's the stipend."}]},
	"errand_corner": {"title": "Soda run", "variant": "corner", "giver": "@street", "prop": "crate", "distance": 70.0, "spread": 120,
		"carry_after": 0, "banner": "SODAS DELIVERED", "clue": "SODA CRATE",
		"pitch": "Corner's thirsty. Grab the soda crate up Old York and bring it back. $%d, no questions.", "accept": "One soda run. ($%d)",
		"steps": [
			{"target": "clue", "objective": "Pick up the soda crate along Old York", "prompt": "E  Pick up the soda crate",
				"dialogue": "A crate of cold sodas, right where the corner said."},
			{"target": "@street", "objective": "Bring the sodas back to the corner", "prompt": "E  Hand over the sodas",
				"dialogue": "Cold ones for the corner. You're all right, 2-Pack."}]},
}

var missions
var _clock := 0.0
var _check_clock := 0.0
var _bark_clock := 0.0
var _last_bark := -1000.0
var _spoken: Dictionary = {}
var _cash_hint_at := -1000.0
var _sign_root: Node3D
var _sign: Label3D
var _sign_text := ""
var _errand_run := -1

func setup(owner) -> void:
	missions = owner

# --- Ids, schema and authored steps ------------------------------------------------

func owns(id: String) -> bool:
	return PARTS.has(id) or ERRANDS.has(id)

func is_story(id: String) -> bool:
	return PARTS.has(id)

func is_errand(id: String) -> bool:
	return ERRANDS.has(id)

## Appended after the six original cases by missions.save_schema(). Story
## rewards are fixed per id so the saved score stays a pure sum.
func schema() -> Dictionary:
	var result := {}
	for id in PARTS:
		result[id] = {"reward": int(PARTS[id].reward), "stages": PARTS[id].steps.size(), "kind": "story"}
	for id in ERRANDS:
		result[id] = {"reward": 0, "stages": ERRANDS[id].steps.size(), "kind": "errand"}
	return result

## Copies of the authored steps. Targets may be @role tokens (see resolve()).
func steps(id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for step in _authored(id):
		result.append(step.duplicate(true))
	return result

## Read-only authored steps (no copy) for the frequent status checks.
func _authored(id: String) -> Array:
	if PARTS.has(id):
		return PARTS[id].steps
	if ERRANDS.has(id):
		return ERRANDS[id].steps
	return []

func title(id: String) -> String:
	if PARTS.has(id):
		return "Petal Pushers %d/3 · %s" % [int(PARTS[id].part), str(PARTS[id].title)]
	if ERRANDS.has(id):
		return str(ERRANDS[id].title)
	return ""

func objective(id: String, step: Dictionary) -> String:
	var text := str(step.get("objective", ""))
	if text.contains("%s"):
		var who := resolve(str(step.get("target", "")), id)
		text = text % (name_for(who) if not who.is_empty() else "a neighbor")
	return text

func start_notice(id: String) -> String:
	var first := _authored(id)
	var goal := objective(id, first[0]) if not first.is_empty() else ""
	if PARTS.has(id):
		return "Petal Pushers, part %d of 3: %s. %s. Follow the case marker; press E at each step." % [int(PARTS[id].part), str(PARTS[id].title), goal]
	return "%s: %s. Follow the case marker." % [title(id), goal]

func completion_banner(id: String) -> String:
	if not PARTS.has(id):
		return title(id).to_upper()
	match int(PARTS[id].part):
		1:
			return "DECISION MADE · PART 1 OF 3"
		2:
			return "PART 2 OF 3 COMPLETE"
	return "ENDING · " + str(ENDINGS.get(_final(), {}).get("label", "Petal Pushers")).to_upper()

# --- Props (built by missions with its existing clay helpers) ----------------------

func has_clue(id: String, from_stage: int = 0) -> bool:
	var list := _authored(id)
	for index in range(maxi(0, from_stage), list.size()):
		if str(list[index].target) == "clue":
			return true
	return false

func prop_kind(id: String) -> String:
	return str(ERRANDS[id].get("prop", "")) if ERRANDS.has(id) else ""

func clue_title(id: String) -> String:
	return str(ERRANDS[id].get("clue", "CLUE")) if ERRANDS.has(id) else "CLUE"

func clue_passable(id: String) -> bool:
	return ERRANDS.has(id) and bool(ERRANDS[id].get("passable", false))

func carries_from_start(id: String) -> bool:
	return ERRANDS.has(id) and bool(ERRANDS[id].get("carry", false))

## Index of the step after which the clue is carried, or -1.
func carry_after(id: String) -> int:
	return int(ERRANDS[id].get("carry_after", -1)) if ERRANDS.has(id) else -1

## Route metres for a clue; varies with the run count so repeats move around.
func placement_distance(id: String) -> float:
	if not ERRANDS.has(id):
		return 120.0
	var spec: Dictionary = ERRANDS[id]
	return float(spec.get("distance", 120.0)) + float((_errand_runs() * 53) % maxi(1, int(spec.get("spread", 1))))

# --- Contacts ------------------------------------------------------------------------

## Actor id for a step target. Tokens pick the first living, present stand-in;
## "" means nobody can take the step right now. Plain ids are returned as-is.
func resolve(target: String, case_id: String = "") -> String:
	if target == "clue" or not target.begins_with("@"):
		return target
	if target == "@recipient":
		for candidate in _recipient_order(case_id):
			if _present(str(candidate)):
				return str(candidate)
		return ""
	for candidate in ROLES.get(target, []):
		if _present(str(candidate)):
			return str(candidate)
	return ""

func primary(target: String) -> String:
	var candidates: Array = ROLES.get(target, [])
	return str(candidates[0]) if not candidates.is_empty() else target

func name_for(actor_id: String) -> String:
	if NAMES.has(actor_id):
		return str(NAMES[actor_id])
	if actor_id.begins_with("patrol_officer_"):
		return "Patrol officer"
	var npcs = missions.npcs if missions != null else null
	var actor = npcs.get_actor(actor_id) if npcs != null and not actor_id.is_empty() else null
	if actor != null:
		var label = actor.get("display_name")
		if label is String and not str(label).is_empty():
			return str(label).get_slice(" · ", 0)
	return "Neighbor"

func _role_name(target: String) -> String:
	return str(ROLE_NAMES[target]) if ROLE_NAMES.has(target) else name_for(target)

func _recipient_order(case_id: String) -> Array:
	var order: Array = []
	var giver := ""
	var offset := 0
	if ERRANDS.has(case_id):
		giver = resolve(str(ERRANDS[case_id].giver), case_id)
		offset = int(ERRANDS[case_id].get("offset", 0))
	var count := RECIPIENTS.size()
	var runs := _errand_runs()
	for step in count:
		var candidate := str(RECIPIENTS[(runs * 3 + offset + step) % count])
		if candidate != giver:
			order.append(candidate)
	return order

func _present(id: String) -> bool:
	var npcs = missions.npcs if missions != null else null
	if npcs == null or id.is_empty():
		return false
	var actor = npcs.get_actor(id)
	if actor == null or _dead(id, actor) or is_contact_in_custody(id):
		return false
	var at: Vector3 = npcs.actor_position(id)
	return at.is_finite()

func is_contact_in_custody(id: String) -> bool:
	var npcs = missions.npcs if missions != null else null
	var actor = npcs.get_actor(id) if npcs != null and not id.is_empty() else null
	return actor != null and not _dead(id, actor) and (bool(actor.get_meta("police_custody", false)) or bool(actor.get_meta("police_custody_completed", false)))

## A stand-in still takes precedence. Custody is absence, never a death flag.
func custody_blocker(id: String, from_stage := 0) -> String:
	var list := _authored(id)
	for index in range(maxi(0, from_stage), list.size()):
		var target := str(list[index].target)
		if target == "clue":
			continue
		var resolved := resolve(target, id)
		if not resolved.is_empty():
			if is_contact_in_custody(resolved):
				return name_for(resolved)
			continue
		var candidates: Array = _recipient_order(id) if target == "@recipient" else ROLES.get(target, [])
		for candidate in candidates:
			if is_contact_in_custody(str(candidate)):
				return _role_name(target)
	return ""

func _dead(id: String, actor = null) -> bool:
	var combat = _combat()
	if combat != null and combat.has_method("is_actor_dead") and bool(combat.is_actor_dead(id)):
		return true
	if actor == null and missions != null and missions.npcs != null:
		actor = missions.npcs.get_actor(id)
	return actor != null and bool(actor.get_meta("city_dead", false))

## True only when every candidate has died; an absent contact may return.
func _gone_for_good(target: String) -> bool:
	if target == "clue":
		return false
	if target == "@recipient":
		for candidate in RECIPIENTS:
			if not _dead(str(candidate)):
				return false
		return true
	if not target.begins_with("@"):
		return _dead(target)
	for candidate in ROLES.get(target, []):
		if not _dead(str(candidate)):
			return false
	return true

## Display name of the first remaining step nobody can take, or "".
func _missing_contact(id: String, from_stage: int) -> String:
	var list := _authored(id)
	for index in range(maxi(0, from_stage), list.size()):
		var target := str(list[index].target)
		if target == "clue":
			continue
		var actor_id := resolve(target, id)
		if actor_id.is_empty() or not _present(actor_id):
			return _role_name(target)
	return ""

## Whether `actor_id` was the identity taking the step before it died.
func _was_resolved(target: String, case_id: String, actor_id: String) -> bool:
	if target == actor_id:
		return true
	var order: Array = _recipient_order(case_id) if target == "@recipient" else ROLES.get(target, [])
	for candidate in order:
		if str(candidate) == actor_id:
			return true
		if _present(str(candidate)):
			return false
	return false

# --- Story state (derived from mission completion + progression choices) ----------

func _progression():
	var level = missions.level if missions != null else null
	if level == null:
		return null
	var progression = level.get("progression")
	if progression == null or not is_instance_valid(progression) or not bool(progression.get("enabled")):
		return null
	return progression

func _combat():
	var level = missions.level if missions != null else null
	if level == null:
		return null
	var combat = level.get("combat")
	return combat if is_instance_valid(combat) else null

func _branch() -> String:
	var progression = _progression()
	return str(progression.choice_of(CALL)) if progression != null else ""

func _final() -> String:
	var progression = _progression()
	return str(progression.choice_of(FINAL)) if progression != null else ""

func _errand_runs() -> int:
	var progression = _progression()
	return int(progression.errand_runs) if progression != null else 0

func _finished() -> bool:
	for branch in BRANCHES:
		if missions.completed_ids.has("petals_end_" + str(branch)):
			return true
	return false

func is_closed() -> bool:
	if _finished():
		return false
	var progression = _progression()
	if progression != null and bool(progression.meets("flag:" + CLOSED_FLAG)):
		return true
	return _dead(VENDOR)

func closed_reason() -> String:
	if _dead(VENDOR):
		return "Ines Morales has died. The flower cart stays chained to the fence."
	return "The people this story needed are gone."

## {state, reason, startable}. States: completed, active, available, locked,
## skipped (another branch was chosen), unavailable (contact absent or on
## policy hold, see _policy_hold), closed. ignore_hold resumes a restored part.
func part_state(id: String, from_stage: int = 0, ignore_hold: bool = false) -> Dictionary:
	var info := {"id": id, "state": "locked", "reason": "", "startable": false}
	if not PARTS.has(id):
		return info
	var part: Dictionary = PARTS[id]
	var branch := str(part.branch)
	if missions.completed_ids.has(id):
		info.state = "completed"
		info.reason = _completion_reason(id)
		return info
	if str(missions.active_id) == id:
		info.state = "active"
		return info
	var progression = _progression()
	if progression == null:
		info.reason = "Story progress is unavailable in this session."
		return info
	if is_closed():
		info.state = "closed"
		info.reason = closed_reason()
		return info
	var chosen := _branch()
	match int(part.part):
		1:
			if not chosen.is_empty():
				info.reason = "Already decided."
				return info
		2:
			if not missions.completed_ids.has("petals_word"):
				info.reason = "Starts once you decide what to do about Ines's cart."
				return info
			if chosen != branch:
				info.state = "skipped"
				return info
		3:
			if not missions.completed_ids.has("petals_" + branch):
				info.reason = "Starts after part 2."
				return info
			if chosen != branch:
				info.state = "skipped"
				return info
			if not _final().is_empty():
				info.reason = "Already decided."
				return info
	var missing := _missing_contact(id, from_stage)
	if not missing.is_empty():
		info.state = "unavailable"
		var detained := custody_blocker(id, from_stage)
		info.reason = "%s is in police custody." % detained if not detained.is_empty() else "%s is not around right now." % missing
		return info
	var hold := "" if ignore_hold else _policy_hold(id, from_stage)
	if not hold.is_empty():
		info.state = "unavailable"
		info.reason = hold
		return info
	info.state = "available"
	info.startable = true
	var names := PackedStringArray()
	for giver in part.givers:
		var who := resolve(str(giver), id)
		if not who.is_empty():
			names.append(name_for(who))
	info.reason = "Talk to %s." % " or ".join(names) if not names.is_empty() else "Waiting for a contact."
	return info

func _completion_reason(id: String) -> String:
	var progression = _progression()
	match int(PARTS[id].part):
		1:
			var chosen := _branch()
			if progression != null and not chosen.is_empty():
				return "You chose: %s." % str(progression.config.decisions[CALL].options[chosen].label)
		3:
			var ending: Dictionary = ENDINGS.get(_final(), {})
			if not ending.is_empty():
				return "%s. %s" % [str(ending.label), str(ending.summary)]
	return "Done."

## Missions start gate (offer, auto-start and restore all pass through it).
## A restored errand was eligible when it started; its unlock may since have
## lapsed (Ines died mid-delivery), so resuming only needs its contacts. The
## payout itself still checks the durable cooldown.
func can_start(id: String, from_stage: int = 0, resuming: bool = false) -> bool:
	if PARTS.has(id):
		# A restored part always resumes (a refusal would reject the checkpoint);
		# _reconcile then puts it on hold if it cannot be finished yet.
		return bool(part_state(id, from_stage, resuming).startable)
	if ERRANDS.has(id):
		var progression = _progression()
		if progression == null:
			return false
		var status: Dictionary = progression.errand_status(str(ERRANDS[id].variant))
		return (resuming or bool(status.available)) and _missing_contact(id, from_stage).is_empty()
	return false

func on_case_started(id: String) -> void:
	_errand_run = _errand_runs() if ERRANDS.has(id) else -1
	_refresh_sign()

# --- Offers and conversations ------------------------------------------------------

## Offers from the giver nearest the player within interaction range. Missions
## asks only when no original case offer is in range, so the six original offer
## conversations never change.
func nearby_offers() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if missions == null or missions.level == null or missions.npcs == null or not str(missions.active_id).is_empty():
		return found
	var player = missions.level.get("player")
	if player == null or not is_instance_valid(player):
		return found
	var here: Vector3 = player.global_position
	# Cheap range test first (called by the HUD several times a second): only
	# a giver standing within reach makes the eligibility rules run at all.
	var reachable := {}
	for giver in GIVERS:
		var actor_id := resolve(str(giver))
		if actor_id.is_empty() or reachable.has(actor_id):
			continue
		var at: Vector3 = missions.npcs.actor_position(actor_id)
		if at.is_finite() and Vector2(at.x - here.x, at.z - here.z).length() <= INTERACT_RADIUS:
			reachable[actor_id] = at
	if reachable.is_empty():
		return found
	var by_actor := {}
	for offer in _offer_candidates():
		var actor_id := str(offer.actor_id)
		if not reachable.has(actor_id):
			continue
		if not by_actor.has(actor_id):
			by_actor[actor_id] = []
		by_actor[actor_id].append(offer)
	var nearest := ""
	var distance := INF
	for actor_id in by_actor:
		var at: Vector3 = reachable[actor_id]
		var flat := Vector2(at.x - here.x, at.z - here.z).length()
		if flat < distance and missions._can_interact(at):
			nearest = str(actor_id)
			distance = flat
	if not nearest.is_empty():
		for offer in by_actor[nearest]:
			found.append(offer)
	return found

func nearest_offer() -> Dictionary:
	var offers := nearby_offers()
	return offers[0] if not offers.is_empty() else {}

func _offer_candidates() -> Array[Dictionary]:
	var offers: Array[Dictionary] = []
	var progression = _progression()
	if progression == null:
		return offers
	for id in PARTS:
		if not bool(part_state(str(id)).startable):
			continue
		for giver in PARTS[id].givers:
			var actor_id := resolve(str(giver), str(id))
			if actor_id.is_empty() or not _present(actor_id):
				continue
			offers.append({"id": str(id), "kind": "story", "actor_id": actor_id, "title": str(PARTS[id].title),
				"pitch": str(PARTS[id].get("pitches", {}).get(str(giver), PARTS[id].pitch)), "accept": str(PARTS[id].accept)})
	for id in ERRANDS:
		var spec: Dictionary = ERRANDS[id]
		var status: Dictionary = progression.errand_status(str(spec.variant))
		if not bool(status.available):
			continue
		var giver := resolve(str(spec.giver), str(id))
		if giver.is_empty() or not _present(giver) or not _missing_contact(str(id), 0).is_empty():
			continue
		offers.append({"id": str(id), "kind": "errand", "actor_id": giver, "title": str(spec.title),
			"pitch": str(spec.pitch) % int(status.payout), "accept": str(spec.accept) % int(status.payout)})
	return offers

func offer_conversation() -> Dictionary:
	var offers := nearby_offers()
	if offers.is_empty():
		return {}
	var actor_id := str(offers[0].actor_id)
	var lines: Array = []
	var replies: Array = []
	for offer in offers:
		lines.append(str(offer.pitch))
		replies.append({"text": str(offer.accept), "hook": {"kind": "story_start" if str(offer.kind) == "story" else "errand_start", "id": str(offer.id)}})
	replies.append({"text": "Maybe later."})
	return {"actor_id": actor_id, "start": "start", "reactions": false, "nodes": {"start": {"speaker": name_for(actor_id), "lines": lines, "choices": replies}}}

## Hook {"kind": "story_start"|"errand_start", "id"}; rechecks range and
## eligibility so a stale reply starts nothing.
func commit_offer(action: Dictionary) -> bool:
	var wanted := str(action.get("id", ""))
	var kind := "story" if str(action.get("kind", "")) == "story_start" else "errand"
	for offer in nearby_offers():
		if str(offer.id) == wanted and str(offer.kind) == kind:
			return bool(missions.start_case(wanted))
	return false

func step_conversation(id: String, stage: int, step: Dictionary) -> Dictionary:
	var token := str(step.get("target", ""))
	var actor_id := resolve(token, id)
	var lines: Array = []
	if token.begins_with("@") and STAND_INS.has(token) and actor_id != primary(token):
		lines.append(str(STAND_INS[token]))
	lines.append(str(step.get("dialogue", "")))
	var replies: Array = []
	if step.has("decision"):
		var progression = _progression()
		for option in step.get("options", []):
			if not PlayMode.story_option_allowed(str(step.decision), str(option.option)):
				continue
			var requires := _option_requirement(str(step.decision), str(option.option))
			var reply := {"text": _amount_text(str(option.text), str(option.get("amount", ""))),
				"hook": {"kind": "case_step", "id": id, "stage": stage, "choice": str(option.option)}}
			if not requires.is_empty():
				reply["condition"] = requires
			replies.append(reply)
			if not requires.is_empty() and option.has("unmet") and progression != null:
				replies.append({"text": _amount_text(str(option.unmet), str(option.get("amount", ""))), "condition": "not (%s)" % requires})
		replies.append({"text": "I need to think it over."})
	else:
		replies.append({"text": str(step.get("prompt", "")).trim_prefix("E  "), "hook": {"kind": "case_step", "id": id, "stage": stage}})
		replies.append({"text": "I'll come back."})
	var speaker := "2-Pack" if token == "clue" else name_for(actor_id)
	return {"actor_id": actor_id if token != "clue" else "clue", "start": "start", "reactions": false,
		"nodes": {"start": {"speaker": speaker, "lines": lines, "choices": replies}}}

## Missions calls this inside its range-checked step commit. Ordinary steps
## take no choice. A decision step needs one authored option and commits it to
## progression first, so a refused choice advances nothing. {ok, line}.
func accept_step(id: String, step: Dictionary, choice: String) -> Dictionary:
	var result := {"ok": false, "line": ""}
	if not step.has("decision"):
		result.ok = choice.is_empty()
		return result
	var option := _option(step, choice)
	var progression = _progression()
	if option.is_empty() or progression == null:
		return result
	if not PlayMode.story_option_allowed(str(step.decision), choice):
		missions.notice.emit(_refusal("option retired"))
		return result
	var outcome: Dictionary = progression.commit_choice(str(step.decision), choice, {"case": id})
	if not bool(outcome.get("ok", false)):
		missions.notice.emit(_refusal(str(outcome.get("reason", ""))))
		return result
	result.ok = true
	result.line = str(option.get("outcome", ""))
	return result

func _option(step: Dictionary, choice: String) -> Dictionary:
	if choice.is_empty():
		return {}
	for option in step.get("options", []):
		if str(option.option) == choice:
			return option
	return {}

func _option_requirement(decision: String, option: String) -> String:
	var progression = _progression()
	if progression == null:
		return ""
	var decisions: Dictionary = progression.config.get("decisions", {})
	if not decisions.has(decision) or not decisions[decision].options.has(option):
		return ""
	return str(decisions[decision].options[option].requires)

## Money in authored reply text comes from the configured action, never a copy.
func _amount_text(text: String, action_id: String) -> String:
	if action_id.is_empty() or not text.contains("%d"):
		return text
	var progression = _progression()
	var amount := 0
	if progression != null and progression.config.actions.has(action_id):
		amount = absi(int(progression.config.actions[action_id].money))
	return text % amount

func _refusal(reason: String) -> String:
	match reason:
		"insufficient funds":
			return "You don't have enough cash for that yet."
		"already chosen":
			return "That's already settled."
		"requirement not met":
			return "You can't do that yet."
		"option retired":
			return "That's not how 2-Pack handles things anymore."
	return "That isn't possible right now."

## Nonviolent policy guard. Only decisions that lost options to
## RETIRED_STORY_OPTIONS are checked, so unaffected decisions behave exactly as
## authored. If such a remaining decision has no allowed option the player can
## commit right now (requirement and the action's own cost), the part would
## strand the player: an active story part blocks every errand and case, which
## are the only income. The part then waits; the reason says what unblocks it.
## "" when the part can be played through.
func _policy_hold(id: String, from_stage: int = 0) -> String:
	var progression = _progression()
	if progression == null or not PARTS.has(id):
		return ""
	var list := _authored(id)
	for index in range(maxi(0, from_stage), list.size()):
		var step: Dictionary = list[index]
		if not step.has("decision"):
			continue
		var decision := str(step.decision)
		var retired := false
		var reachable := false
		var cost := -1
		for option in step.get("options", []):
			var choice := str(option.option)
			if not PlayMode.story_option_allowed(decision, choice):
				retired = true
				continue
			var need := _option_cost(progression, decision, choice)
			cost = need if cost < 0 else mini(cost, need)
			if bool(progression.choice_available(decision, choice).get("ok", false)) and int(progression.money) >= need:
				reachable = true
		if not retired or reachable or cost < 0:
			continue
		var who := name_for(resolve(str(step.get("target", "")), id))
		if cost > 0:
			return "On hold until you have $%d to make things right with %s. Paid block errands can cover it." % [cost, who]
		return "On hold: there's no way to settle things with %s yet." % who
	return ""

## Dollars an option needs: its money requirement or its action's own charge.
func _option_cost(progression, decision: String, option: String) -> int:
	var spec: Dictionary = progression.config.decisions[decision].options[option]
	var action: Dictionary = progression.config.actions.get(str(spec.action), {})
	var need := maxi(0, -int(action.get("money", 0)))
	var requires := str(spec.get("requires", "")).replace(" ", "")
	if requires.begins_with("money>=") and requires.substr(7).is_valid_int():
		need = maxi(need, requires.substr(7).to_int())
	return need

## An active part that cannot be finished is set aside, not left blocking.
func _hold_if_stranded() -> void:
	var active := str(missions.active_id)
	if not is_story(active):
		return
	var hold := _policy_hold(active, int(missions.stage))
	if hold.is_empty():
		return
	missions.cancel_case()
	missions.notice.emit("%s · %s" % [title(active), hold])

# --- Completion, deaths and ticking -----------------------------------------------

## After a story part is recorded and cleared: start the next part or announce.
func after_story(id: String) -> void:
	if not PARTS.has(id):
		return
	match int(PARTS[id].part):
		1:
			var next := "petals_" + _branch()
			if not (PARTS.has(next) and bool(missions.start_case(next))):
				missions.notice.emit("Part 2 is waiting. Talk to Ines when the people involved are around.")
		2:
			missions.notice.emit("Petal Pushers part 2 of 3 is done. Later, Ines will want a word about how it all settled.")
		3:
			var ending: Dictionary = ENDINGS.get(_final(), {})
			missions.notice.emit("Petal Pushers ending · %s: %s" % [str(ending.get("label", "")), str(ending.get("summary", ""))])
	_refresh_sign()

## Pays the finished errand once (run captured at start) and returns the
## banner for the completion effect.
func complete_errand(id: String) -> String:
	var spec: Dictionary = ERRANDS[id]
	var progression = _progression()
	var paid := 0
	var reason := "progress is unavailable"
	if progression != null:
		var run := _errand_run if _errand_run >= 0 else int(progression.errand_runs)
		var result: Dictionary = progression.pay_errand(str(spec.variant), run)
		paid = int(result.get("paid", 0))
		reason = str(result.get("reason", ""))
	_errand_run = -1
	if paid > 0:
		var wait := int(progression.errand_status().seconds_left)
		missions.notice.emit("%s done. +$%d. More paid work in %d:%02d." % [str(spec.title), paid, wait / 60, wait % 60])
		return "%s\n+$%d" % [str(spec.banner), paid]
	missions.notice.emit("%s done, but nothing was paid (%s)." % [str(spec.title), reason])
	return str(spec.banner)

func on_actor_died(id: String) -> void:
	if id == VENDOR and not _finished():
		_close("Ines Morales has died. The flower cart stays chained to the fence.")
	_check_active(id)
	_close_if_doomed()

## The part the chain is waiting on (active, or the next one), "" when done.
func _pending_part() -> String:
	var active := str(missions.active_id)
	if is_story(active):
		return active
	if not missions.completed_ids.has("petals_word"):
		return "petals_word"
	var branch := _branch()
	if branch.is_empty():
		return ""
	for id in ["petals_" + branch, "petals_end_" + branch]:
		if not missions.completed_ids.has(id):
			return id
	return ""

## A part paused for an absent stand-in still closes once every candidate for
## one of its remaining steps has died; nothing will ever bring them back.
func _close_if_doomed() -> void:
	if _finished() or is_closed():
		return
	var part := _pending_part()
	if part.is_empty():
		return
	var from_stage := int(missions.stage) if str(missions.active_id) == part else 0
	var list := _authored(part)
	for index in range(maxi(0, from_stage), list.size()):
		var target := str(list[index].target)
		if _gone_for_good(target):
			_close("%s is gone, and nobody else can see this through." % _role_name(target), missions.completed_ids.has("petals_word"))
			return

## Stand-in first; otherwise end the active part/errand without reward. A story
## part whose contact can never return closes the chain.
func _check_active(dead_id: String) -> void:
	var active := str(missions.active_id)
	if not owns(active):
		return
	var stage := int(missions.stage)
	var list := _authored(active)
	var missing := _missing_contact(active, stage)
	if missing.is_empty():
		if not dead_id.is_empty() and stage < list.size() and _was_resolved(str(list[stage].target), active, dead_id):
			var stand_in := resolve(str(list[stage].target), active)
			if not stand_in.is_empty() and stand_in != dead_id:
				missions.notice.emit("%s can't help anymore. %s will take it from here." % [name_for(dead_id), name_for(stand_in)])
		return
	var permanent := false
	for index in range(stage, list.size()):
		permanent = permanent or _gone_for_good(str(list[index].target))
	missions.cancel_case()
	_errand_run = -1
	var detained := custody_blocker(active, stage)
	if not detained.is_empty():
		missions.notice.emit("Case paused without a reward: %s is in police custody. Other cases and errands remain available." % detained)
	elif is_story(active) and permanent:
		_close("%s is gone, and nobody else can see this through." % missing, true)
	elif is_story(active):
		missions.notice.emit("%s is on hold: %s is not around. Talk to Ines to pick it back up." % [title(active), missing])
	else:
		missions.notice.emit("Errand closed without pay: %s is not around." % missing)

func _close(reason: String, announce: bool = false) -> void:
	var active := str(missions.active_id)
	var started: bool = announce or missions.completed_ids.has("petals_word") or is_story(active)
	if is_story(active):
		missions.cancel_case()
	var progression = _progression()
	if progression != null and not bool(progression.meets("flag:" + CLOSED_FLAG)):
		progression.apply_action(CLOSED_FLAG)
	if started:
		missions.notice.emit("Petal Pushers is over: %s" % reason)
	_refresh_sign()

## Unpaused only (missions.tick). Contact checks cover deaths restored after
## the mission state; barks are throttled and bounded to a few contacts.
func tick(delta: float) -> void:
	if missions == null or missions.level == null or not is_finite(delta) or delta <= 0.0:
		return
	_clock += minf(delta, 1.0)
	_check_clock += delta
	if _check_clock >= 1.0:
		_check_clock = 0.0
		_reconcile()
	_bark_clock += delta
	if _bark_clock >= 0.5:
		_bark_clock = 0.0
		_barks()

func _reconcile() -> void:
	if not _finished() and _dead(VENDOR):
		var progression = _progression()
		if progression != null and not bool(progression.meets("flag:" + CLOSED_FLAG)):
			_close("Ines Morales has died. The flower cart stays chained to the fence.")
	if owns(str(missions.active_id)):
		_check_active("")
	_hold_if_stranded()
	_close_if_doomed()
	_refresh_sign()
	_cash_hint()

func _cash_hint() -> void:
	var progression = _progression()
	if progression == null or int(progression.money) >= LOW_CASH or _clock - _cash_hint_at < CASH_HINT_GAP or not str(missions.active_id).is_empty():
		return
	var giver := resolve(str(ERRANDS.errand_delivery.giver), "errand_delivery")
	var status: Dictionary = progression.errand_status("delivery")
	if giver.is_empty() or not bool(status.available):
		return
	_cash_hint_at = _clock
	missions.notice.emit("Short on cash? The %s on Old York pays $%d for block deliveries." % [name_for(giver).to_lower(), int(status.payout)])

func _bark_actors() -> Array:
	var actors: Array = [VENDOR, "officer", "lookout", "organizer"]
	var carrier := resolve("@carrier", "errand_delivery")
	if not carrier.is_empty() and not carrier in actors:
		actors.append(carrier)
	return actors

func _barks() -> void:
	var progression = _progression()
	var player = missions.level.get("player")
	if progression == null or player == null or not is_instance_valid(player) or missions.npcs == null or _clock - _last_bark < BARK_GAP:
		return
	var here: Vector3 = player.global_position
	var busy := ""
	var active := str(missions.active_id)
	if not active.is_empty() and int(missions.stage) < missions._steps.size():
		busy = resolve(str(missions._steps[int(missions.stage)].target), active)
	for actor_id in _bark_actors():
		var id := str(actor_id)
		if id == busy or _clock - float(_spoken.get(id, -1000.0)) < BARK_COOLDOWN:
			continue
		var actor = missions.npcs.get_actor(id)
		if actor == null or _dead(id, actor) or not bool(actor.get("enabled")):
			continue
		var at: Vector3 = actor.global_position
		if Vector2(at.x - here.x, at.z - here.z).length() > BARK_RADIUS or absf(at.y - here.y) > 3.0:
			continue
		var line := str(progression.reaction_line(id))
		if line.is_empty() and id == resolve("@carrier", "errand_delivery") and active.is_empty():
			var status: Dictionary = progression.errand_status("delivery")
			if bool(status.available):
				line = "Paid deliveries for the block, if you want work. $%d a run." % int(status.payout)
		if line.is_empty():
			continue
		missions.npcs.speak(id, line, 4.5)
		_spoken[id] = _clock
		_last_bark = _clock
		return

# --- World sign at the cart ------------------------------------------------------

func _sign_label() -> String:
	if is_closed():
		return "INES' FLOWERS\nCLOSED"
	var ending_id := _final()
	if not ending_id.is_empty():
		return "INES' FLOWERS\n" + str(ENDINGS.get(ending_id, {}).get("sign", "OPEN"))
	match _branch():
		"report":
			return "INES' FLOWERS\nWARNING NOTICE POSTED"
		"protect":
			return "INES' FLOWERS\nUNDER 2-PACK'S WATCH"
		"negotiate":
			return "INES' FLOWERS\nPERMIT PENDING"
		"intimidate":
			return "INES' FLOWERS\nCASH ONLY"
	return "INES' FLOWERS\nSUNFLOWERS · DUMBARTON"

## Ines's real work anchor from her existing daily route (read-only).
func _cart_anchor() -> Vector3:
	var level = missions.level if missions != null else null
	var residents = level.get("residents") if level != null else null
	if residents == null or not is_instance_valid(residents):
		return Vector3.INF
	var routes = residents.get("routes")
	if not routes is Dictionary or not routes.has(VENDOR) or not routes[VENDOR] is Dictionary:
		return Vector3.INF
	var points = routes[VENDOR].get("points")
	var anchors = routes[VENDOR].get("anchors")
	if not points is Array or not anchors is Dictionary:
		return Vector3.INF
	var index := int(anchors.get("work", -1))
	if index < 0 or index >= points.size() or not points[index] is Vector3:
		return Vector3.INF
	return points[index]

func _refresh_sign() -> void:
	if missions == null or not missions.is_inside_tree():
		return
	var text := _sign_label()
	if text == _sign_text and is_instance_valid(_sign):
		return
	var anchor := _cart_anchor()
	if not anchor.is_finite():
		return
	if not is_instance_valid(_sign_root):
		_sign_root = Node3D.new()
		_sign_root.name = "InesFlowerCartSign"
		missions.add_child(_sign_root)
		_sign = missions._tag(_sign_root, text, 2.35)
		_sign.visibility_range_end = 30.0
	_sign_root.position = anchor
	_sign.text = text
	_sign_text = text

func sign_text() -> String:
	return _sign_text

# --- Ledger and validation ---------------------------------------------------------

func ledger() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var branch := _branch()
	rows.append(_row("petals_word"))
	for spec in [["petals_", "2/3", "Depends on what you decide about Ines's cart."], ["petals_end_", "3/3", "Follows part 2."]]:
		var id := str(spec[0]) + branch
		if not branch.is_empty() and PARTS.has(id):
			rows.append(_row(id))
		else:
			var closed := is_closed()
			rows.append({"id": "petals_part_" + str(spec[1]).left(1), "title": "Petal Pushers " + str(spec[1]),
				"state": "closed" if closed else "locked", "reason": closed_reason() if closed else str(spec[2])})
	var ending_id := _final()
	if not ending_id.is_empty():
		var ending: Dictionary = ENDINGS.get(ending_id, {})
		rows.append({"id": "petals_ending", "title": "Ending · " + str(ending.get("label", ending_id)), "state": "completed", "reason": str(ending.get("summary", ""))})
	rows.append(errand_summary())
	return rows

func _row(id: String) -> Dictionary:
	var info := part_state(id)
	var reason := str(info.reason)
	if str(info.state) == "active" and int(missions.stage) < missions._steps.size():
		reason = "Step %d of %d: %s" % [int(missions.stage) + 1, missions._steps.size(), objective(id, missions._steps[int(missions.stage)])]
	return {"id": id, "title": title(id), "state": str(info.state), "reason": reason}

func errand_summary() -> Dictionary:
	var result := {"id": "errands", "title": "Block errands", "state": "unavailable", "reason": "Paid errands are unavailable in this session.",
		"runs": 0, "earned": 0, "seconds_left": 0, "offers": []}
	var progression = _progression()
	if progression == null:
		return result
	var clock: Dictionary = progression.errand_status()
	result.runs = int(clock.runs)
	result.earned = int(clock.earned)
	result.seconds_left = int(clock.seconds_left)
	var open := PackedStringArray()
	for id in ERRANDS:
		var spec: Dictionary = ERRANDS[id]
		var status: Dictionary = progression.errand_status(str(spec.variant))
		var giver := resolve(str(spec.giver), str(id))
		if bool(status.unlocked) and not giver.is_empty() and _present(giver):
			open.append("%s $%d from %s" % [str(spec.title), int(status.payout), name_for(giver)])
	var active := str(missions.active_id)
	if is_errand(active):
		result.state = "active"
		result.reason = "In progress: %s." % title(active)
	elif open.is_empty():
		result.reason = "No one is offering paid errands right now."
	elif not bool(clock.ready):
		result.state = "cooling down"
		result.reason = "Next paid errand in %d:%02d." % [int(clock.seconds_left) / 60, int(clock.seconds_left) % 60]
	else:
		result.state = "available"
		result.reason = "Paid errands: %s." % "; ".join(open)
	result.reason = "%s %d done, $%d earned." % [str(result.reason), int(result.runs), int(result.earned)]
	result.offers = Array(open)
	return result

## Pure cross-check of saved mission progress against the same snapshot's
## progression choices and death registry. "" when consistent.
func validate(completed: Array, active: String, stage: int, choice_map: Dictionary, dead: Dictionary) -> String:
	var chosen := str(choice_map.get(CALL, ""))
	var ending_id := str(choice_map.get(FINAL, ""))
	if not chosen.is_empty() and not chosen in BRANCHES:
		return "invalid story choice"
	var done := {}
	for id in completed:
		done[str(id)] = true
	if done.has("petals_word") != (not chosen.is_empty()):
		return "story choice mismatch"
	var seconds := 0
	var thirds := 0
	for option in BRANCHES:
		if done.has("petals_" + str(option)):
			seconds += 1
			if str(option) != chosen:
				return "story branch mismatch"
		if done.has("petals_end_" + str(option)):
			thirds += 1
			if str(option) != chosen or not done.has("petals_" + str(option)):
				return "story branch mismatch"
	if seconds > 1 or thirds > 1:
		return "story branch mismatch"
	if (thirds == 1) != (not ending_id.is_empty()) or (not ending_id.is_empty() and not ending_id.begins_with(chosen + "_")):
		return "story ending mismatch"
	if PARTS.has(active):
		if done.has(active):
			return "story part already complete"
		var part: Dictionary = PARTS[active]
		var part_branch := str(part.branch)
		var ordered := true
		match int(part.part):
			1:
				ordered = chosen.is_empty()
			2:
				ordered = done.has("petals_word") and part_branch == chosen
			3:
				ordered = done.has("petals_" + part_branch) and part_branch == chosen and ending_id.is_empty()
		if not ordered:
			return "story part out of order"
	if owns(active):
		var list := _authored(active)
		for index in range(clampi(stage, 0, list.size()), list.size()):
			if _all_dead(str(list[index].target), dead):
				return "case requires deceased contact"
	return ""

func _all_dead(target: String, dead: Dictionary) -> bool:
	if target == "clue":
		return false
	if target == "@recipient":
		for candidate in RECIPIENTS:
			if not dead.has(str(candidate)):
				return false
		return true
	if not target.begins_with("@"):
		return dead.has(target)
	for candidate in ROLES.get(target, []):
		if not dead.has(str(candidate)):
			return false
	return true
