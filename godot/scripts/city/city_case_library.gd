extends RefCounted
## Loads case definitions from res://assets/data/cases/: the index lists
## template files and case files (relative paths). A case may start from a
## template ("template": id, "params": {...}); the case then overrides it:
## objects merge key by key, arrays of objects merge by "id" (template order
## kept, new ids appended), any other value replaces, and null deletes a
## template field. "{param}" placeholders in template text are filled from
## params; a placeholder that is exactly "{param}" keeps the param's type.
## Every merged case then passes city_case_schema.gd. A file that fails is
## rejected whole and reported; the others still load.

const Schema := preload("res://scripts/city/city_case_schema.gd")
const INDEX_PATH := "res://assets/data/cases/index.json"
const MAX_FILE_BYTES := 65536
const MAX_CASES := 64
const MAX_TEMPLATES := 32
const MAX_DEPTH := 12

static var _cache: Dictionary = {}

## Cached per index path and context. Returns {"cases": {id: case}, "order",
## "errors", "warnings", "rejected": {file: errors}, "templates": [ids], "sources": {id: file}}.
static func load_index(context: Dictionary, path: String = INDEX_PATH) -> Dictionary:
	var key := path + "|" + JSON.stringify(context)
	if not _cache.has(key):
		_cache[key] = _read_index(context, path)
	return _cache[key]

static func clear_cache() -> void:
	_cache.clear()

## File-free entry point (fixtures, tools): raw case dictionaries plus
## template id -> template case object.
static func load_definitions(raw_cases: Array, templates: Dictionary, context: Dictionary) -> Dictionary:
	var result := _empty()
	result.templates = templates.keys()
	for raw in raw_cases:
		_add_case(result, raw, templates, context, "<fixture %s>" % str(raw.get("id", "?") if raw is Dictionary else "?"))
	return result

## errors/warnings are plain arrays of text so every step appends to the same list.
static func _empty() -> Dictionary:
	return {"cases": {}, "order": [], "errors": [], "warnings": [], "rejected": {}, "templates": [], "sources": {}}

static func _read_index(context: Dictionary, path: String) -> Dictionary:
	var result := _empty()
	var index = _read_json(path)
	if not index is Dictionary:
		result.errors.append("%s: %s" % [path, str(index) if index is String else "unreadable"])
		return result
	if not Schema._integer(index.get("schema"), Schema.SCHEMA, Schema.SCHEMA):
		result.errors.append("%s: schema must be %d" % [path, Schema.SCHEMA])
		return result
	var base := path.get_base_dir()
	var templates := {}
	var template_files = index.get("templates", [])
	var case_files = index.get("cases", [])
	if not template_files is Array or not case_files is Array or template_files.size() > MAX_TEMPLATES or case_files.size() > MAX_CASES:
		result.errors.append("%s: \"templates\" and \"cases\" are lists of relative .json paths" % path)
		return result
	for relative in template_files:
		var file := _resolve(base, relative)
		if file.is_empty():
			result.errors.append("%s: invalid template path %s" % [path, str(relative)])
			continue
		var data = _read_json(file)
		if not data is Dictionary or not Schema._integer(data.get("schema"), Schema.SCHEMA, Schema.SCHEMA) or not data.get("case") is Dictionary \
				or not Schema._matches(str(data.get("template", "")), Schema.ID_PATTERN):
			result.errors.append("%s: a template is {\"schema\": %d, \"template\": id, \"case\": {...}}" % [file, Schema.SCHEMA])
			continue
		if templates.has(str(data.template)):
			result.errors.append("%s: template id %s is defined twice" % [file, str(data.template)])
			continue
		templates[str(data.template)] = data.case
		result.templates.append(str(data.template))
	for relative in case_files:
		var file := _resolve(base, relative)
		if file.is_empty():
			result.errors.append("%s: invalid case path %s" % [path, str(relative)])
			continue
		var raw = _read_json(file)
		if not raw is Dictionary:
			result.rejected[file] = PackedStringArray([str(raw) if raw is String else "unreadable"])
			result.errors.append("%s: %s" % [file, str(raw) if raw is String else "unreadable"])
			continue
		_add_case(result, raw, templates, context, file)
	return result

static func _add_case(result: Dictionary, raw, templates: Dictionary, context: Dictionary, source: String) -> void:
	var expanded := expand(raw, templates)
	if not expanded.errors.is_empty():
		result.rejected[source] = expanded.errors
		for error in expanded.errors:
			result.errors.append("%s: %s" % [source, error])
		return
	var normalized := Schema.normalize(expanded.case, context)
	for warning in normalized.warnings:
		result.warnings.append("%s: %s" % [source, warning])
	var id := str(expanded.case.get("id", ""))
	if not bool(normalized.ok):
		result.rejected[source] = normalized.errors
		for error in normalized.errors:
			result.errors.append("%s: %s" % [source, error])
		return
	if result.cases.has(id):
		result.rejected[source] = PackedStringArray(["case id %s is defined twice" % id])
		result.errors.append("%s: case id %s is defined twice" % [source, id])
		return
	normalized.case.template = str(raw.get("template", "")) if raw is Dictionary else ""
	result.cases[id] = normalized.case
	result.order.append(id)
	result.sources[id] = source

## Template merge + parameter substitution. {"case": merged, "errors"}.
static func expand(raw, templates: Dictionary) -> Dictionary:
	var errors: Array = []
	if not raw is Dictionary:
		return {"case": {}, "errors": ["case must be an object"]}
	var merged: Dictionary = raw.duplicate(true)
	var template_id := str(raw.get("template", ""))
	if not template_id.is_empty():
		if not templates.has(template_id):
			return {"case": {}, "errors": ["unknown template \"%s\"" % template_id]}
		var base = templates[template_id]
		merged = _merge(base.duplicate(true), raw.duplicate(true), 0)
	var params = raw.get("params", {})
	if not params is Dictionary:
		errors.append("params must be an object")
		params = {}
	merged.erase("template")
	merged.erase("params")
	var filled = _substitute(merged, params, errors, 0)
	return {"case": filled if filled is Dictionary else {}, "errors": errors}

static func _merge(base, over, depth: int):
	if depth > MAX_DEPTH:
		return over
	if base is Dictionary and over is Dictionary:
		var result: Dictionary = base
		for key in over:
			if over[key] == null:
				result.erase(key)
			elif result.has(key):
				result[key] = _merge(result[key], over[key], depth + 1)
			else:
				result[key] = over[key]
		return result
	if base is Array and over is Array and _id_list(base) and _id_list(over):
		var result: Array = base
		for entry in over:
			var found := -1
			for index in result.size():
				if str(result[index].get("id", "")) == str(entry.get("id", "")):
					found = index
					break
			if found >= 0:
				result[found] = _merge(result[found], entry, depth + 1)
			else:
				result.append(entry)
		return result
	return over

static func _id_list(value: Array) -> bool:
	if value.is_empty():
		return false
	for entry in value:
		if not entry is Dictionary or not entry.has("id"):
			return false
	return true

static var _placeholder: RegEx

static func _substitute(value, params: Dictionary, errors: Array, depth: int):
	if depth > MAX_DEPTH:
		return value
	if value is Dictionary:
		var result := {}
		for key in value:
			# Author notes ("_about", ...) are copied as written.
			result[key] = value[key] if str(key).begins_with("_") else _substitute(value[key], params, errors, depth + 1)
		return result
	if value is Array:
		var result: Array = []
		for entry in value:
			result.append(_substitute(entry, params, errors, depth + 1))
		return result
	if not value is String or not str(value).contains("{"):
		return value
	if _placeholder == null:
		_placeholder = RegEx.new()
		_placeholder.compile("\\{([a-z][a-z0-9_]*)\\}")
	var text: String = value
	var whole := _placeholder.search(text)
	if whole != null and whole.get_start() == 0 and whole.get_end() == text.length():
		var name := whole.get_string(1)
		if not params.has(name):
			errors.append("unresolved template parameter {%s}" % name)
			return value
		return params[name]
	for found in _placeholder.search_all(text):
		var name := found.get_string(1)
		if not params.has(name):
			errors.append("unresolved template parameter {%s}" % name)
			continue
		text = text.replace("{%s}" % name, str(params[name]))
	return text

static func _resolve(base: String, relative) -> String:
	if not relative is String:
		return ""
	var text: String = relative
	if text.is_empty() or text.contains("..") or text.contains("\\") or text.begins_with("/") or text.contains(":") or not text.ends_with(".json"):
		return ""
	return base.path_join(text)

static func _read_json(path: String):
	if not FileAccess.file_exists(path):
		return "missing file"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "unreadable file"
	if file.get_length() > MAX_FILE_BYTES:
		file.close()
		return "file larger than %d bytes" % MAX_FILE_BYTES
	var text := file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return "JSON error line %d: %s" % [parser.get_error_line(), parser.get_error_message()]
	return parser.data
