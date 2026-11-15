extends RefCounted
## What the lead has, kept in the save: his cash, his health, the rounds for each
## weapon, what he has recorded and filmed. main.gd owns the one there is
## (`_state`) and writes it into the save under "state".
##
## Change a number through the methods here, never by setting it: each one emits
## `changed`, which is what the HUD (and anything else that shows a number)
## listens to.

signal changed

const START_CASH := 2500
const MAX_HEALTH := 100
const CLIP := {"pistol": 12, "uzi": 32, "ak": 30}            # rounds a full magazine holds
const START_SPARE := {"pistol": 48, "uzi": 96, "ak": 90}     # rounds he starts with besides the loaded magazine

var cash := START_CASH
var health := MAX_HEALTH
var loaded := {}            # weapon: rounds in its magazine
var spare := {}             # weapon: rounds he carries besides
var songs := 0              # songs recorded at the booth microphone
var videos: Array = []      # each music video he has shot: a Dictionary of how it went
var flags := {}             # anything else worth keeping: name to a value JSON can hold


func _init() -> void:
	reset()


## As a new game starts.
func reset() -> void:
	cash = START_CASH
	health = MAX_HEALTH
	loaded = CLIP.duplicate()
	spare = START_SPARE.duplicate()
	songs = 0
	videos = []
	flags = {}
	changed.emit()


func earn(amount: int) -> void:
	cash += maxi(amount, 0)
	changed.emit()


## Pay `amount` if he has it. False, and nothing paid, if he does not.
func spend(amount: int) -> bool:
	if amount < 0 or amount > cash:
		return false
	cash -= amount
	changed.emit()
	return true


func hurt(amount: int) -> void:
	health = clampi(health - maxi(amount, 0), 0, MAX_HEALTH)
	changed.emit()


func heal(amount: int) -> void:
	health = clampi(health + maxi(amount, 0), 0, MAX_HEALTH)
	changed.emit()


## Say that something set directly (a round fired, a flag) has changed.
func touch() -> void:
	changed.emit()


func to_save() -> Dictionary:
	return {"cash": cash, "health": health, "loaded": loaded, "spare": spare, "songs": songs, "videos": videos, "flags": flags}


## From a save. Anything the save does not have keeps its new-game value, so an older save still loads.
func from_save(data: Dictionary) -> void:
	reset()
	cash = int(data.get("cash", cash))
	health = clampi(int(data.get("health", health)), 0, MAX_HEALTH)
	for weapon: String in CLIP:
		loaded[weapon] = int(_dict(data.get("loaded")).get(weapon, loaded[weapon]))
		spare[weapon] = int(_dict(data.get("spare")).get(weapon, spare[weapon]))
	songs = int(data.get("songs", 0))
	if typeof(data.get("videos")) == TYPE_ARRAY:
		videos = data["videos"]
	flags = _dict(data.get("flags"))
	changed.emit()


static func _dict(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}
