extends Node
## The gun store at work. plans/gunstore.gd puts one in the place (named "GunShop") and hands it the counter's
## use point and each range lane; it is the one thing in the place that does anything.
##
## The counter. E there opens the list (gun_counter.gd): each weapon he does not own (player_state.gd `owned`),
## then a box of rounds for each he does. Paid with `spend` (nothing changes if he is short); a weapon bought is
## his through `own` (Q goes round it, as at the start of a game); a box of rounds goes on his `spare`. While the
## list is up the game is in its own mode ("shop": he stands still, no shots, no travel list); as it closes the
## game goes back to "play" and is saved. Names, boxes and prices are placeholders: WEAPONS, ROUNDS.
##
## The range. combat.gd keeps what its last shot hit (`last`: the mesh it stopped on, "on", and where, "at").
## When that is a target's paper, the hole is drawn into the paper's picture where the shot landed and the ring
## it is in is scored (props_gun.gd). E at a booth runs that lane's target in to the shooting line, clips up a
## fresh paper and runs it back out (RUN seconds each way). The shots are combat's own (fx). The mark fx puts
## where a shot lands is hidden on a paper, as it comes (the paper's own hole is the mark there), so each hole
## shows once and a fresh paper is clean; its dust and chips still fly.

const Gun := preload("res://scripts/props_gun.gd")
const Counter := preload("res://scripts/gun_counter.gd")

## What the shop sells, by player_state.gd's weapon names: placeholders, plain words (no makers, no models).
const WEAPONS := [
	{"weapon": "pistol", "name": "PISTOL", "price": 600},
	{"weapon": "uzi", "name": "MACHINE PISTOL", "price": 1800},
	{"weapon": "ak", "name": "ASSAULT RIFLE", "price": 3200},
]
const ROUNDS := {
	"pistol": {"name": "PISTOL ROUNDS", "box": 50, "price": 40},
	"uzi": {"name": "MACHINE PISTOL ROUNDS", "box": 64, "price": 70},
	"ak": {"name": "RIFLE ROUNDS", "box": 60, "price": 90},
}
const RUN := 0.7               # seconds a target takes to run in to the line, and the same back out

var main: Node
var place: Node3D
var counter: CanvasLayer
## Each lane: {"paper", "carrier", "home" (the carrier's z out on the range), "near" (its z at the line),
## "spot" (where he stands in the booth), "image", "tex", "hits", "score", "run" (seconds into a run, or -1),
## "back" (true once the paper is changed and it is on its way back out), "hidden" (fx marks hidden on it)}.
var lanes: Array = []
var _seen: Variant = null      # combat.gd's last shot, as last looked at
var _gathered := false


func _ready() -> void:
	place = get_parent()
	main = place.get_parent()
	counter = Counter.new()
	add_child(counter)
	counter.chosen.connect(_on_chosen)
	counter.closed.connect(_on_closed)


## A lane: its carrier and paper (props_gun.gd `target`), how far in the carrier runs (`near`, metres towards
## the booth along +z) and where he stands to shoot it. The paper gets its own picture to be marked.
func add_lane(made: Dictionary, near: float, spot: Vector3) -> void:
	var image: Image = Gun.target_image()
	var tex := ImageTexture.create_from_image(image)
	var look := StandardMaterial3D.new()
	look.albedo_texture = tex
	look.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	look.roughness = 1.0
	look.metallic_specular = 0.0
	(made["paper"] as MeshInstance3D).material_override = look
	var carrier: Node3D = made["carrier"]
	lanes.append({"paper": made["paper"], "carrier": carrier, "home": carrier.position.z, "near": carrier.position.z + near,
		"spot": spot, "image": image, "tex": tex, "hits": 0, "score": 0, "run": -1.0, "back": false, "hidden": 0})


## The middle of lane i's rings, in the world (where the steps aim).
func bull_of(i: int) -> Vector3:
	return (lanes[i]["paper"] as MeshInstance3D).to_global(Gun.bull_local())


## What E at one of the place's use points does (they are connected here by the plan).
func use(id: String, _by: Node3D = null) -> void:
	if id == "gun:counter":
		open_counter()
	elif id.begins_with("range:"):
		fresh(int(id.trim_prefix("range:")) - 1)


# ------------------------------------------------------------------ the counter

func open_counter() -> void:
	if counter.is_open():
		return
	main._set_mode("shop")
	counter.show_rows(rows(), int(main._state.cash))


## The list: each weapon he does not own, then a box of rounds for each he does.
func rows() -> Array:
	var state: RefCounted = main._state
	var out: Array = []
	for w: Dictionary in WEAPONS:
		if not String(w["weapon"]) in state.owned:
			out.append({"id": w["weapon"], "weapon": w["weapon"], "name": w["name"], "note": "WEAPON", "price": w["price"]})
	for w: Dictionary in WEAPONS:
		var id := String(w["weapon"])
		if id in state.owned:
			var box: Dictionary = ROUNDS[id]
			out.append({"id": "rounds:" + id, "weapon": id, "name": box["name"], "price": box["price"],
				"note": "BOX OF %d  -  YOU HAVE %d" % [int(box["box"]), int(state.loaded.get(id, 0)) + int(state.spare.get(id, 0))]})
	return out


## Buy what a row of the list sells (its "id": a weapon, or "rounds:<weapon>"). What it came to, in words.
func buy(id: String) -> String:
	var state: RefCounted = main._state
	for row: Dictionary in rows():
		if String(row["id"]) != id:
			continue
		if not state.spend(int(row["price"])):
			return "NOT ENOUGH CASH FOR THAT"
		var weapon := String(row["weapon"])
		if id.begins_with("rounds:"):
			state.spare[weapon] = int(state.spare.get(weapon, 0)) + int(ROUNDS[weapon]["box"])
			state.touch()
			return "%d %s BOUGHT" % [int(ROUNDS[weapon]["box"]), row["name"]]
		state.own(weapon)
		return "%s BOUGHT. Q TO HOLD IT" % row["name"]
	return "NOT FOR SALE"


func _on_chosen(id: String) -> void:
	var said := buy(id)
	counter.show_rows(rows(), int(main._state.cash), said)


func _on_closed() -> void:
	main._set_mode("play")
	main._save_game()


# -------------------------------------------------------------------- the range

## Run lane i's target in, give it a fresh paper and run it back out (nothing if it is on a run already).
func fresh(i: int) -> void:
	if i < 0 or i >= lanes.size() or float(lanes[i]["run"]) >= 0.0:
		return
	lanes[i]["run"] = 0.0
	lanes[i]["back"] = false


func _process(delta: float) -> void:
	if main == null or not ("_combat" in main) or main._combat == null or main._building != place:
		return
	if not _gathered:              # what shots can hit here, gathered now, while every target is at home
		_gathered = true
		main._combat.world_for(place)
	var shot: Dictionary = main._combat.last
	if not is_same(shot, _seen):
		_seen = shot
		_on_shot(shot)
	for lane: Dictionary in lanes:
		_run(lane, delta)
		for mark: Node in (lane["paper"] as Node).get_children():      # fx's mark for a shot on the paper: the paper has its own hole
			if mark.has_meta("combat_fx") and (mark as Node3D).visible:
				(mark as Node3D).visible = false
				lane["hidden"] = int(lane["hidden"]) + 1


## A shot that stopped on a target's paper: a hole where it landed, and its score.
func _on_shot(shot: Dictionary) -> void:
	if not shot.has("at") or not shot.has("on"):
		return
	for i in lanes.size():
		var lane: Dictionary = lanes[i]
		var paper: MeshInstance3D = lane["paper"]
		if String(shot["on"]) != String(paper.name) or float(lane["run"]) >= 0.0:
			continue
		var local := paper.to_local(shot["at"])
		var px := Vector2((local.x / Gun.PAPER_W + 0.5) * Gun.TARGET_PX.x, (0.5 - local.y / Gun.PAPER_H) * Gun.TARGET_PX.y)
		Gun.mark_hole(lane["image"], px)
		(lane["tex"] as ImageTexture).update(lane["image"])
		var points := Gun.score_at(px)
		lane["hits"] = int(lane["hits"]) + 1
		lane["score"] = int(lane["score"]) + points
		var said := "BULL'S-EYE" if points == 10 else ("%d POINTS" % points if points > 0 else "ON THE PAPER")
		var hits := int(lane["hits"])
		if main._combat.hud and main._combat.hud.has_method("caption"):
			main._combat.hud.caption("LANE %d   %s   TOTAL %d IN %d %s" % [i + 1, said, int(lane["score"]), hits, "SHOT" if hits == 1 else "SHOTS"])


## A target on its run: in to the line, a fresh paper, back out.
func _run(lane: Dictionary, delta: float) -> void:
	if float(lane["run"]) < 0.0:
		return
	lane["run"] = float(lane["run"]) + delta
	var k := smoothstep(0.0, 1.0, clampf(float(lane["run"]) / RUN, 0.0, 1.0))
	var carrier: Node3D = lane["carrier"]
	if not lane["back"]:
		carrier.position.z = lerpf(float(lane["home"]), float(lane["near"]), k)
		if float(lane["run"]) >= RUN:
			lane["image"] = Gun.target_image()
			(lane["tex"] as ImageTexture).update(lane["image"])
			lane["hits"] = 0
			lane["score"] = 0
			lane["back"] = true
			lane["run"] = 0.0
	else:
		carrier.position.z = lerpf(float(lane["near"]), float(lane["home"]), k)
		if float(lane["run"]) >= RUN:
			carrier.position.z = float(lane["home"])
			lane["run"] = -1.0
