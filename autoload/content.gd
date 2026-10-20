extends Node
## Registry of data-driven content. Anything dropped into these files/folders enters the pools
## automatically; nothing is registered by hand.

var classes: Dictionary = {}
var enemies: Dictionary = {}
var allies: Dictionary = {}
var elements: Dictionary = {}
var levels: Dictionary = {}

var _icons: Dictionary = {}


func _init() -> void:
	reload()


func reload() -> void:
	classes = JsonUtil.strip_comments(JsonUtil.load_dict("res://data/classes.json"))
	enemies = JsonUtil.strip_comments(JsonUtil.load_dict("res://data/enemies.json"))
	allies = JsonUtil.strip_comments(JsonUtil.load_dict("res://data/allies.json"))
	elements = JsonUtil.strip_comments(JsonUtil.load_dict("res://data/elements.json"))
	levels = JsonUtil.load_dir("res://data/levels")
	_icons.clear()


func enemy(id: String) -> Dictionary:
	if not enemies.has(id):
		push_warning("Unknown enemy id '%s', falling back to grunt" % id)
		return enemies.get("grunt", {})
	return enemies[id]


func ally(id: String) -> Dictionary:
	if not allies.has(id):
		push_warning("Unknown ally id '%s'" % id)
		return {}
	return allies[id]


func hero_class(id: String) -> Dictionary:
	if not classes.has(id):
		return classes.values()[0] if not classes.is_empty() else {}
	return classes[id]


func element_color(element: String) -> Color:
	if not elements.has(element):
		return Color("#36C8FF")
	return Color(String(elements[element].get("color", "#FFFFFF")))


func element_name(element: String) -> String:
	if not elements.has(element):
		return "ARCANE"
	return String(elements[element].get("name", element.to_upper()))


func weakness_of(element: String) -> String:
	if not elements.has(element):
		return ""
	return String(elements[element].get("weak_to", ""))


func element_icon(element: String) -> Texture2D:
	if _icons.has(element):
		return _icons[element]
	var texture: Texture2D = null
	if elements.has(element):
		var path := String(elements[element].get("icon", ""))
		if ResourceLoader.exists(path):
			texture = load(path)
	_icons[element] = texture
	return texture
