class_name JsonUtil
extends RefCounted
## JSON loading helpers. Static so headless tools can use them without autoloads.


static func load_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Missing JSON file: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	push_error("JSON file is not an object: %s" % path)
	return {}


## Loads every *.json in a folder, keyed by file name without extension.
static func load_dir(dir_path: String) -> Dictionary:
	var out := {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for file in dir.get_files():
		if file.ends_with(".json"):
			out[file.get_basename()] = load_dict(dir_path.path_join(file))
	return out


## Drops "_doc"-style comment keys from a content table.
static func strip_comments(table: Dictionary) -> Dictionary:
	var out := {}
	for key: String in table:
		if not key.begins_with("_"):
			out[key] = table[key]
	return out
