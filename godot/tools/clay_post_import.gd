@tool
extends EditorScenePostImport
## Runs on every imported .glb (set as the scene importer default in project.godot):
## replaces the Blender materials with the shared clay materials named after them.


func _post_import(scene: Node) -> Object:
	ClayLib.apply(scene)
	return scene
