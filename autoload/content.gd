extends Node
## Registry of data-driven content. Anything dropped into these files/folders enters the pools
## automatically; nothing is registered by hand.

var classes: Dictionary = {}
var enemies: Dictionary = {}
var levels: Dictionary = {}


func _init() -> void:
	reload()


func reload() -> void:
	classes = JsonUtil.strip_comments(JsonUtil.load_dict("res://data/classes.json"))
	enemies = JsonUtil.strip_comments(JsonUtil.load_dict("res://data/enemies.json"))
	levels = JsonUtil.load_dir("res://data/levels")


func enemy(id: String) -> Dictionary:
	if not enemies.has(id):
		push_warning("Unknown enemy id '%s', falling back to grunt" % id)
		return enemies.get("grunt", {})
	return enemies[id]


func hero_class(id: String) -> Dictionary:
	if not classes.has(id):
		return classes.values()[0] if not classes.is_empty() else {}
	return classes[id]
