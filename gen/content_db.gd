class_name ContentDB
extends RefCounted
## Loads every content table from res://data into one Dictionary. Pure (no autoloads), so the
## Content autoload, the generator, and headless tools all read content the same way.
## Any JSON added to data/segments/ joins the segment pool automatically.


static func load_all() -> Dictionary:
	var db := {
		"classes": JsonUtil.strip_comments(JsonUtil.load_dict("res://data/classes.json")),
		"enemies": JsonUtil.strip_comments(JsonUtil.load_dict("res://data/enemies.json")),
		"allies": JsonUtil.strip_comments(JsonUtil.load_dict("res://data/allies.json")),
		"elements": JsonUtil.strip_comments(JsonUtil.load_dict("res://data/elements.json")),
		"gates": JsonUtil.strip_comments(JsonUtil.load_dict("res://data/gates.json")),
		"pacing": JsonUtil.strip_comments(JsonUtil.load_dict("res://data/pacing.json")),
		"bosses": JsonUtil.strip_comments(JsonUtil.load_dict("res://data/bosses.json")),
		"zones": JsonUtil.load_dict("res://data/zones.json"),
		"modifiers": JsonUtil.strip_comments(JsonUtil.load_dict("res://data/modifiers.json")),
		"levels": JsonUtil.load_dir("res://data/levels"),
		"segments": [],
	}
	var segments: Array = []
	var files := JsonUtil.load_dir("res://data/segments")
	for file: String in files:
		for seg: Dictionary in files[file].get("segments", []):
			segments.append(seg)
	# Sorted by id so pool order (and therefore generation) never depends on file order.
	segments.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.get("id", "")) < String(b.get("id", "")))
	db["segments"] = segments
	return db
