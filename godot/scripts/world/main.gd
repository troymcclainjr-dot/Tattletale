extends Node3D
## The main scene: G builds the block, the cast, the lights and the camera under this node.


func _ready() -> void:
	G.boot(self)
