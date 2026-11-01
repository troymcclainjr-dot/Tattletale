extends RefCounted
## Serializable conversation graph. Conditions and hooks are resolved by the host.
## Nodes: {speaker, lines:[], choices:[{text,next,condition,hook}], next, condition}.
signal changed
signal closed
var graph: Dictionary = {}
var node_id := ""
var line_index := 0
var active := false
var selected := 0
var condition: Callable
var hook: Callable

func open(data: Dictionary, conditions: Callable = Callable(), hooks: Callable = Callable()) -> bool:
	graph = data.duplicate(true)
	condition = conditions
	hook = hooks
	return _enter(str(graph.get("start", "start")))

func _allowed(value) -> bool:
	return str(value).is_empty() or (condition.is_valid() and bool(condition.call(value)))

func _enter(id: String) -> bool:
	if id.is_empty() or not graph.get("nodes", {}).has(id):
		close()
		return false
	var entry: Dictionary = graph.nodes[id]
	if not _allowed(entry.get("condition", "")):
		close()
		return false
	node_id = id
	line_index = 0
	selected = 0
	active = true
	changed.emit()
	return true

func current() -> Dictionary:
	if not active:
		return {}
	var entry: Dictionary = graph.nodes[node_id]
	var lines: Array = entry.get("lines", [])
	return {"speaker": str(entry.get("speaker", "Neighbor")), "text": str(lines[line_index]) if line_index < lines.size() else "", "choices": choices()}

func choices() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not active:
		return result
	var entry: Dictionary = graph.nodes[node_id]
	if line_index < entry.get("lines", []).size() - 1:
		return result
	for choice in entry.get("choices", []):
		if _allowed(choice.get("condition", "")):
			result.append(choice)
	return result

func advance() -> void:
	if not active:
		return
	var entry: Dictionary = graph.nodes[node_id]
	if line_index < entry.get("lines", []).size() - 1:
		line_index += 1
		changed.emit()
	elif not choices().is_empty():
		choose(selected)
	else:
		_enter(str(entry.get("next", "")))

func choose(index: int) -> void:
	var available := choices()
	if index < 0 or index >= available.size():
		return
	var choice: Dictionary = available[index]
	var action = choice.get("hook", {})
	if not action.is_empty() and (not hook.is_valid() or not bool(hook.call(action))):
		return
	_enter(str(choice.get("next", "")))

func close() -> void:
	var was_active := active
	active = false
	node_id = ""
	if was_active:
		closed.emit()
