class_name CombatMath
extends RefCounted
## Pure combat rules shared by the live game, autopilot, and the headless simulator.
## No nodes or autoloads: callers pass the content tables (elements, allies) and limits.


## Damage multiplier for an attack element against a target element.
## Returns 0.0 when the target is immune (wards hit by anything but their weakness).
static func element_multiplier(attack: String, target: String, elements: Dictionary, limits: Dictionary, immune_unless_weak := false) -> float:
	var weak_to := String(elements.get(target, {}).get("weak_to", "")) if elements.has(target) else ""
	if immune_unless_weak and weak_to != "":
		return float(limits.get("weak_multiplier", 2.0)) if attack == weak_to else 0.0
	if attack == "" or attack == "none" or not elements.has(target):
		return 1.0
	if attack == weak_to:
		return float(limits.get("weak_multiplier", 2.0))
	if attack == target:
		return float(limits.get("resist_multiplier", 0.5))
	return 1.0


## Average multiplier the given attack element gets against a weighted mix of targets.
## mix = { "fire": weight, "none": weight, "ward:fire": weight (immune-unless-weak targets) }
static func mix_multiplier(attack: String, mix: Dictionary, elements: Dictionary, limits: Dictionary) -> float:
	var total := 0.0
	var weighted := 0.0
	for key: String in mix:
		var w := float(mix[key])
		var immune := key.begins_with("ward:")
		var target := key.substr(5) if immune else key
		weighted += w * element_multiplier(attack, target, elements, limits, immune)
		total += w
	return weighted / total if total > 0.0 else 1.0


static func ally_dps(stats: HeroStats, allies_db: Dictionary) -> float:
	var dps := 0.0
	for id: String in stats.allies:
		var def: Dictionary = allies_db.get(id, {})
		var uptime := 1.0 if String(def.get("kind", "melee")) == "ranged" else 0.55
		dps += int(stats.allies[id]) * float(def.get("damage", 0)) * float(def.get("attack_rate", 0)) * uptime
	return dps * stats.ally_power


static func ally_hp(stats: HeroStats, allies_db: Dictionary) -> float:
	var hp := 0.0
	for id: String in stats.allies:
		hp += int(stats.allies[id]) * float(allies_db.get(id, {}).get("hp", 0))
	return hp * stats.ally_power


## One-number estimate of build strength against an expected enemy element mix.
## Damage matters most; survivability enters as a square root so HP-for-damage trades stay fair.
static func power(stats: HeroStats, mix: Dictionary, elements: Dictionary, allies_db: Dictionary, limits: Dictionary) -> float:
	var mult := mix_multiplier(stats.element, mix, elements, limits)
	var dps := (stats.dps() + ally_dps(stats, allies_db)) * mult
	var toughness := stats.hp + ally_hp(stats, allies_db) * 0.5
	# Allies soak hits, but the run ends when the hero dies: very low hero HP is near-fatal.
	var danger := smoothstep(0.0, float(limits.get("low_hp_danger", 30.0)), stats.hp)
	return dps * sqrt(maxf(toughness, 1.0) / 100.0) * danger


## Ratio of power after/before taking a gate.
static func gate_score(gate: Dictionary, stats: HeroStats, mix: Dictionary, elements: Dictionary, allies_db: Dictionary, limits: Dictionary) -> float:
	var after := stats.copy()
	after.apply_gate(gate, limits)
	return power(after, mix, elements, allies_db, limits) / maxf(power(stats, mix, elements, allies_db, limits), 0.001)
