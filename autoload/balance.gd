extends Node
## Global tunables from res://data/balance.json.
## Usage: Balance.f("hero.run_speed"), Balance.i("combat.max_live_projectiles"), Balance.section("combat").

const PATH := "res://data/balance.json"

var data: Dictionary = {}


func _init() -> void:
	reload()


func reload() -> void:
	data = JsonUtil.load_dict(PATH)


func get_value(path: String, default: Variant = null) -> Variant:
	var node: Variant = data
	for key in path.split("."):
		if node is Dictionary and (node as Dictionary).has(key):
			node = node[key]
		else:
			push_warning("Balance key missing: %s" % path)
			return default
	return node


func f(path: String, default := 0.0) -> float:
	return float(get_value(path, default))


func i(path: String, default := 0) -> int:
	return int(get_value(path, default))


func section(name: String) -> Dictionary:
	var value: Variant = data.get(name, {})
	return value if value is Dictionary else {}
