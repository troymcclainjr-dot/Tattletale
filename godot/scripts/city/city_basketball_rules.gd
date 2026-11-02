extends RefCounted
## One-on-one half-court pickup rules: one point inside the arc, two beyond,
## first to eleven. After a basket or a dead ball the other side checks the ball
## at the top of the key; a defensive rebound or loose-ball recovery must be
## taken beyond the arc before it can score. Pure state: the court activity
## reports physical facts (pickups, releases, contacts, rim crossings).

const DEAD_SECONDS := 1.2
const MAX_EVENTS := 24

var target := 11
var score := {"player": 0, "opponent": 0}
## idle → check → live ⇄ dead → … → over, or abandoned.
var phase := "idle"
## Side entitled to the ball: the checking side, or whoever holds it.
var possession := ""
var holder := ""
var last_touch := ""
var needs_clear := false
## The ball's latest release: {id, by, value, valid, shot, touched}. Cleared by a
## pickup, a basket or a dead ball, so a single release can never score twice.
var shot: Dictionary = {}
var shot_serial := 0
var winner := ""
var games := 0
var dead_time := 0.0
var events: Array[Dictionary] = []

static func other(side: String) -> String:
	return "opponent" if side == "player" else "player"

func start(first: String) -> void:
	score = {"player": 0, "opponent": 0}
	winner = ""
	shot = {}
	holder = ""
	last_touch = ""
	needs_clear = false
	possession = first
	phase = "check"
	dead_time = 0.0
	_event({"kind": "start", "side": first})

func active() -> bool:
	return phase in ["check", "live", "dead"]

## A game begun with the ball already in hand still has to clear the arc.
func give(side: String, beyond_arc: bool) -> Dictionary:
	if phase != "check" or side != possession:
		return {}
	phase = "live"
	holder = side
	last_touch = side
	needs_clear = not beyond_arc
	shot = {}
	return _event({"kind": "in_hand", "side": side, "needs_clear": needs_clear})

func can_pick_up(side: String) -> bool:
	if phase == "check":
		return side == possession
	return phase == "live" and holder.is_empty()

func pick_up(side: String, beyond_arc: bool) -> Dictionary:
	if not can_pick_up(side):
		return {}
	var kind := "check"
	if phase == "check":
		# The pickup radius can reach a checked ball from inside the arc.
		needs_clear = not beyond_arc
	elif not shot.is_empty() and bool(shot.shot):
		kind = "offensive_rebound" if str(shot.by) == side else "defensive_rebound"
		# The shooter keeps any unfinished clear; the defence must clear afresh.
		if kind == "defensive_rebound":
			needs_clear = not beyond_arc
	else:
		kind = "recovery" if side == last_touch else "loose_ball"
		if side != last_touch:
			needs_clear = not beyond_arc
	phase = "live"
	holder = side
	possession = side
	last_touch = side
	shot = {}
	return _event({"kind": kind, "side": side, "needs_clear": needs_clear})

func clear(side: String) -> Dictionary:
	if phase != "live" or holder != side or not needs_clear:
		return {}
	needs_clear = false
	return _event({"kind": "cleared", "side": side})

## A shot or a drop. Value is fixed by where the release happened.
func release(side: String, value: int, is_shot: bool) -> Dictionary:
	if phase != "live" or holder != side:
		return {}
	shot_serial += 1
	shot = {"id": shot_serial, "by": side, "value": clampi(value, 1, 2), "valid": not needs_clear, "shot": is_shot, "touched": false}
	holder = ""
	possession = ""
	last_touch = side
	return _event({"kind": "shot" if is_shot else "drop", "side": side, "id": shot_serial, "value": shot.value, "valid": shot.valid})

## First contact with rim, board or floor: the ball becomes a fair rebound.
func touch() -> void:
	if not shot.is_empty():
		shot.touched = true

## The ball went down through the rim. Uncleared releases count nothing and
## turn the ball over; a release that already scored has been consumed.
func basket() -> Dictionary:
	if phase != "live" or shot.is_empty():
		return {}
	var by := str(shot.by)
	var points := int(shot.value) if bool(shot.valid) else 0
	score[by] = int(score[by]) + points
	var result := {"kind": "basket" if points > 0 else "no_basket", "side": by, "points": points, "id": shot.id}
	_dead(other(by))
	if int(score[by]) >= target:
		phase = "over"
		winner = by
		games += 1
		result["winner"] = by
	result["score"] = score.duplicate()
	return _event(result)

## The ball touched the floor outside the half in play, or its holder stepped
## out. The side that did not touch it last checks it up.
func out_of_bounds(culprit := "") -> Dictionary:
	if phase != "live":
		return {}
	var by := culprit
	if by.is_empty():
		by = holder if not holder.is_empty() else last_touch
	if by.is_empty():
		by = other(possession) if not possession.is_empty() else "player"
	_dead(other(by))
	return _event({"kind": "out", "side": by, "to": possession})

func turnover(side: String, reason: String) -> Dictionary:
	if phase != "live":
		return {}
	_dead(other(side))
	return _event({"kind": "turnover", "side": side, "reason": reason, "to": possession})

func tick(delta: float) -> Dictionary:
	if phase != "dead":
		return {}
	dead_time -= delta
	if dead_time > 0.0:
		return {}
	phase = "check"
	return _event({"kind": "check_ready", "side": possession})

## Loser's ball.
func rematch() -> bool:
	if phase != "over":
		return false
	start(other(winner))
	return true

func abandon(reason: String) -> Dictionary:
	if phase == "idle" or phase == "abandoned":
		return {}
	phase = "abandoned"
	holder = ""
	shot = {}
	return _event({"kind": "abandoned", "reason": reason})

func summary() -> Dictionary:
	return {"phase": phase, "score": score.duplicate(), "target": target, "possession": possession,
		"holder": holder, "last_touch": last_touch, "needs_clear": needs_clear,
		"shot": shot.duplicate(), "winner": winner, "games": games}

func _dead(next: String) -> void:
	phase = "dead"
	possession = next
	holder = ""
	shot = {}
	needs_clear = false
	dead_time = DEAD_SECONDS

func _event(event: Dictionary) -> Dictionary:
	events.append(event)
	if events.size() > MAX_EVENTS:
		events.pop_front()
	return event
