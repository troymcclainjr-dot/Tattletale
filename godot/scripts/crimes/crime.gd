class_name Crime
extends RefCounted
## One case (defCrime in crimes-core.js). Each crime is a subclass that overrides the hooks.
##
## CONTRACT. The HUD reads the fields marked [HUD]; keep their names and meanings.
## Subclasses may add any other fields they need.

var id := ""              # [HUD]
var title := ""           # [HUD]
var who := ""             # [HUD] "Gary · since 2009" (short name = text before " ·")
var time := INF           # seconds allowed (INF = no limit)
var pts := 0
var line: Array = []      # [speaker, text] what 2-Pack says when he gets the evidence
var describe := ""        # [HUD] used by the phone-menu puzzle
var steps: Array = []     # [HUD] [{"k": kind, "t": String or Callable -> String, "m": marker text}]
var bust: Array = []      # cop lines at the bust: [[speaker, text, secs], ...]
var puzzle := ""          # "plate" if reporting needs the plate puzzle
var active := false       # [HUD]
var dispatched := false   # [HUD] cop car on the way
var handling := false     # [HUD] being resolved right now (cutscene, talk)
var left := 0.0           # [HUD] seconds left (INF if no limit)
var full := 1.0           # [HUD] seconds at start (for the bar)
var cool := 0.0
var si := 0               # [HUD] current step index
var no := 0               # [HUD] case number
var frozen := false
var plate := ""           # [HUD] Mama's plate (plate puzzle)
var hint := 0             # [HUD] plate puzzle hint length; the puzzle UI increments it


## Where the crime is happening (binocular target, markers, cop car destination).
func target() -> Vector3:
	return Vector3.ZERO


func start() -> void:
	pass


func update(_dt: float) -> void:
	pass


## E-key action available now, or null: {"x", "z", "r", "rmin" (optional), "label", "fn": Callable}
func act():
	return null


func end(_why: String) -> void:
	pass


## Gate for spy/tail steps (JS spyOk). Default: always OK.
func spy_ok() -> bool:
	return true


## Override and return true to replace the default "say line + EVIDENCE pop" (JS onSpy).
func on_spy() -> bool:
	return false


## Where the two cops stand at a bust: [[x, z], [x, z]].
func slots(_t: Vector3) -> Array:
	return []
