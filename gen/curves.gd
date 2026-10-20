class_name Curves
extends RefCounted
## Difficulty curves and level rhythm. Pure functions of the level number.


## value = base * (1 + linear * (N-1)^exponent), optionally capped.
static func eval(curve: Dictionary, level: int) -> float:
	var n := maxf(0.0, float(level - 1))
	var value := float(curve.get("base", 1.0)) * (1.0 + float(curve.get("linear", 0.0)) * pow(n, float(curve.get("exponent", 1.0))))
	var cap := float(curve.get("cap", 0.0))
	return minf(value, cap) if cap > 0.0 else value


static func named(balance: Dictionary, curve_name: String, level: int) -> float:
	return eval(balance.get("curves", {}).get(curve_name, {}), level)


## "boss" (every boss_every-th level), "spike", "reward", or "normal".
static func level_kind(level: int, rhythm: Dictionary) -> String:
	var boss_every := int(rhythm.get("boss_every", 10))
	if boss_every > 0 and level % boss_every == 0:
		return "boss"
	var spike_every := int(rhythm.get("spike_every", 5))
	if level >= int(rhythm.get("spike_min_level", 10)) and spike_every > 0 and (level - int(rhythm.get("spike_offset", 0))) % spike_every == 0:
		return "spike"
	var reward_every := int(rhythm.get("reward_every", 7))
	if level > 2 and reward_every > 0 and level % reward_every == int(rhythm.get("reward_offset", 3)):
		return "reward"
	return "normal"


static func rhythm_mult(kind: String, rhythm: Dictionary) -> float:
	match kind:
		"spike":
			return float(rhythm.get("spike_mult", 1.2))
		"reward":
			return float(rhythm.get("reward_mult", 0.8))
	return 1.0
