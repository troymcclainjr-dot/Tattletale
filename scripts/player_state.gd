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
var owned: Array = []      # the weapons he has (Q goes round these): he starts with the pistol; the gun store sells the rest
var songs := 0              # songs recorded at the booth microphone
var song_beats: Array = []  # the beat each song was recorded on (assets/beats ids; "" if none was playing), in order
var videos: Array = []      # each music video he has shot: a Dictionary of how it went
var flags := {}             # anything else worth keeping: name to a value JSON can hold
var deeds := {}             # what he has done, name to how many times ("shot_fired", "arrested" ...): what his bars may be about


func _init() -> void:
	reset()


## As a new game starts.
func reset() -> void:
	cash = START_CASH
	health = MAX_HEALTH
	loaded = CLIP.duplicate()
	spare = START_SPARE.duplicate()
	owned = ["pistol"]
	songs = 0
	song_beats = []
	videos = []
	flags = {}
	deeds = {}
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


## He has this weapon from now on (bought, or picked up).
func own(weapon: String) -> void:
	if CLIP.has(weapon) and not weapon in owned:
		owned.append(weapon)
	changed.emit()


## Every weapon is taken off him (searched, arrested).
func disarm() -> void:
	owned = []
	changed.emit()


## He did something worth a bar: `name` is counted (see the song system: bars are unlocked by deeds).
func deed(name: String, n := 1) -> void:
	deeds[name] = int(deeds.get(name, 0)) + maxi(n, 0)
	changed.emit()


## How many times he has done it.
func done(name: String) -> int:
	return int(deeds.get(name, 0))


func hurt(amount: int) -> void:
	health = clampi(health - maxi(amount, 0), 0, MAX_HEALTH)
	changed.emit()


func heal(amount: int) -> void:
	health = clampi(health + maxi(amount, 0), 0, MAX_HEALTH)
	changed.emit()


## A song recorded at the booth microphone (video_shoot.gd), on that beat.
func record_song(beat_id := "") -> void:
	songs += 1
	while song_beats.size() < songs - 1:     # songs from a save older than song_beats: no beat known
		song_beats.append("")
	song_beats.append(beat_id)
	changed.emit()


## A music video shot: how it went (video_shoot.gd's record).
func add_video(video: Dictionary) -> void:
	videos.append(video)
	changed.emit()


## Say that something set directly (a round fired, a flag) has changed.
func touch() -> void:
	changed.emit()


func to_save() -> Dictionary:
	return {"cash": cash, "health": health, "loaded": loaded, "spare": spare, "owned": owned, "songs": songs, "song_beats": song_beats, "videos": videos, "flags": flags, "deeds": deeds}


## From a save. Anything the save does not have keeps its new-game value, so an older save still loads.
func from_save(data: Dictionary) -> void:
	reset()
	cash = int(data.get("cash", cash))
	health = clampi(int(data.get("health", health)), 0, MAX_HEALTH)
	for weapon: String in CLIP:
		loaded[weapon] = int(_dict(data.get("loaded")).get(weapon, loaded[weapon]))
		spare[weapon] = int(_dict(data.get("spare")).get(weapon, spare[weapon]))
	owned = (data["owned"] as Array).duplicate() if typeof(data.get("owned")) == TYPE_ARRAY else CLIP.keys()      # a save from before the gun store had all three
	songs = int(data.get("songs", 0))
	if typeof(data.get("song_beats")) == TYPE_ARRAY:
		song_beats = (data["song_beats"] as Array).map(func(b: Variant) -> String: return String(b) if typeof(b) == TYPE_STRING else "")
	if typeof(data.get("videos")) == TYPE_ARRAY:
		videos = data["videos"]
	flags = _dict(data.get("flags"))
	deeds = _dict(data.get("deeds"))
	changed.emit()


static func _dict(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}
