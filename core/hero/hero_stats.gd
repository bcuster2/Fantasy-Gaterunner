class_name HeroStats
extends RefCounted
## Pure combat stats, shared by the live hero and the headless simulator (no nodes, no autoloads).

var max_hp := 100.0
var hp := 100.0
var damage := 5.0
var fire_rate := 3.0
var projectiles := 1


static func from_class(def: Dictionary) -> HeroStats:
	var s := HeroStats.new()
	s.max_hp = float(def.get("max_hp", 100))
	s.hp = s.max_hp
	s.damage = float(def.get("damage", 5))
	s.fire_rate = float(def.get("fire_rate", 3.0))
	s.projectiles = int(def.get("projectiles", 1))
	return s


func copy() -> HeroStats:
	var s := HeroStats.new()
	s.max_hp = max_hp
	s.hp = hp
	s.damage = damage
	s.fire_rate = fire_rate
	s.projectiles = projectiles
	return s


## limits = the "combat" section of balance.json.
func apply_gate(gate: Dictionary, limits: Dictionary) -> void:
	var op := String(gate.get("op", "add"))
	var value := float(gate.get("value", 0))
	match String(gate.get("stat", "")):
		"damage":
			damage = _apply(damage, op, value)
		"fire_rate":
			fire_rate = _apply(fire_rate, op, value)
		"projectiles":
			projectiles = int(roundf(_apply(projectiles, op, value)))
	clamp_to(limits)


func clamp_to(limits: Dictionary) -> void:
	damage = maxf(damage, float(limits.get("min_damage", 1.0)))
	fire_rate = clampf(fire_rate, float(limits.get("min_fire_rate", 0.5)), float(limits.get("max_fire_rate", 12.0)))
	projectiles = clampi(projectiles, 1, int(limits.get("max_projectiles_per_volley", 9)))


func dps() -> float:
	return damage * fire_rate * projectiles


static func _apply(current: float, op: String, value: float) -> float:
	return current * value if op == "mul" else current + value
