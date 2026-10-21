class_name HeroStats
extends RefCounted
## Pure build state, shared by the live hero and the headless simulator (no nodes, no autoloads).
## The live allies are reconciled to `allies` by the Squad node.

var max_hp := 100.0
var hp := 100.0
var damage := 5.0
var fire_rate := 3.0
var projectiles := 1
var element := "none"
## ally id -> count
var allies: Dictionary = {}
## Multiplier on ally hp/damage (scales with level so summons stay relevant).
var ally_power := 1.0


static func from_class(def: Dictionary) -> HeroStats:
	var s := HeroStats.new()
	s.max_hp = float(def.get("max_hp", 100))
	s.hp = s.max_hp
	s.damage = float(def.get("damage", 5))
	s.fire_rate = float(def.get("fire_rate", 3.0))
	s.projectiles = int(def.get("projectiles", 1))
	s.element = String(def.get("element", "none"))
	return s


func copy() -> HeroStats:
	var s := HeroStats.new()
	s.max_hp = max_hp
	s.hp = hp
	s.damage = damage
	s.fire_rate = fire_rate
	s.projectiles = projectiles
	s.element = element
	s.allies = allies.duplicate()
	s.ally_power = ally_power
	return s


## Gate kinds: "stat" (default, single effect), "element", "summon", "curse" (list of effects).
## limits = the "combat" section of balance.json.
func apply_gate(gate: Dictionary, limits: Dictionary) -> void:
	match String(gate.get("kind", "stat")):
		"element":
			element = String(gate.get("element", "none"))
		"summon":
			add_allies(String(gate.get("ally", "")), int(gate.get("count", 1)), int(limits.get("max_allies", 12)))
		"curse":
			for effect: Dictionary in gate.get("effects", []):
				apply_effect(effect, limits)
		_:
			apply_effect(gate, limits)
	clamp_to(limits)


## Effect = { stat, op ("add" | "mul"), value }. Stats: damage, fire_rate, projectiles, hp (heal),
## max_hp, hp_pct (percent of max HP, curses use negatives), allies_pct (percent of every ally group),
## summon (adds `value` allies of type `ally`).
func apply_effect(effect: Dictionary, limits: Dictionary) -> void:
	var op := String(effect.get("op", "add"))
	var value := float(effect.get("value", 0))
	match String(effect.get("stat", "")):
		"damage":
			damage = _apply(damage, op, value)
		"fire_rate":
			fire_rate = _apply(fire_rate, op, value)
		"projectiles":
			projectiles = int(roundf(_apply(projectiles, op, value)))
		"hp":
			hp = minf(max_hp, _apply(hp, op, value))
		"max_hp":
			var old_max := max_hp
			max_hp = maxf(1.0, _apply(max_hp, op, value))
			if max_hp >= old_max:
				hp = clampf(hp + (max_hp - old_max), 1.0, max_hp) # growth heals by the amount gained
			else:
				hp = clampf(hp * max_hp / old_max, 1.0, max_hp) # shrinking keeps the same HP fraction
		"hp_pct":
			var floor_hp := float(limits.get("min_hp_after_curse", 1.0))
			hp = clampf(hp + max_hp * value / 100.0, floor_hp, max_hp)
		"summon":
			add_allies(String(effect.get("ally", "skeleton")), int(value), int(limits.get("max_allies", 12)))
		"allies_pct":
			for id: String in allies.keys():
				allies[id] = maxi(0, int(floor(int(allies[id]) * (1.0 + value / 100.0))))
				if allies[id] == 0:
					allies.erase(id)


func add_allies(id: String, count: int, cap: int) -> int:
	if id.is_empty():
		return 0
	var room := maxi(0, cap - ally_count())
	var added := mini(count, room)
	if added > 0:
		allies[id] = int(allies.get(id, 0)) + added
	return added


func remove_ally(id: String) -> void:
	if not allies.has(id):
		return
	allies[id] = int(allies[id]) - 1
	if int(allies[id]) <= 0:
		allies.erase(id)


func ally_count() -> int:
	var n := 0
	for id: String in allies:
		n += int(allies[id])
	return n


func clamp_to(limits: Dictionary) -> void:
	damage = maxf(damage, float(limits.get("min_damage", 1.0)))
	fire_rate = clampf(fire_rate, float(limits.get("min_fire_rate", 0.5)), float(limits.get("max_fire_rate", 12.0)))
	projectiles = clampi(projectiles, 1, int(limits.get("max_projectiles_per_volley", 9)))


func dps() -> float:
	return damage * fire_rate * projectiles


static func _apply(current: float, op: String, value: float) -> float:
	return current * value if op == "mul" else current + value
