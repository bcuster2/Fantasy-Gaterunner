class_name Economy
extends RefCounted
## Pure economy rules: upgrade effects and costs, perks, milestone rewards, and run payouts.
## Shared by the game, the shop UI, and the simulator's economy model.


# --- Upgrades ---------------------------------------------------------------------------------

## Total effect (in the upgrade's unit, e.g. percent) at a level. Past soft_cap each level adds after_cap.
static func effect(def: Dictionary, level: int) -> float:
	var per := float(def.get("per_level", 1.0))
	var soft := int(def.get("soft_cap", 1000000))
	if level <= soft:
		return per * level
	return per * soft + float(def.get("after_cap", per)) * (level - soft)


static func max_level(def: Dictionary) -> int:
	if def.has("cost_list"):
		return (def["cost_list"] as Array).size()
	return int(def.get("max_level", 0))


## Cost of buying level+1, or -1 when maxed.
static func cost(def: Dictionary, level: int) -> int:
	var cap := max_level(def)
	if cap > 0 and level >= cap:
		return -1
	if def.has("cost_list"):
		return int(def["cost_list"][level])
	var c := float(def.get("cost_base", 10.0)) * pow(level + 1.0, float(def.get("cost_exp", 1.2)))
	if level >= int(def.get("soft_cap", 1000000)):
		c *= float(def.get("cost_softcap_mult", 1.0))
	return int(roundf(c))


static func describe(def: Dictionary, level: int) -> String:
	return String(def.get("desc", "{effect}")).replace("{effect}", GateInfo.num(effect(def, level)))


## Sum of a stat across upgrades and owned perks, e.g. "damage_pct".
static func bonus(stat: String, upgrades_db: Dictionary, levels: Dictionary, perks_db: Dictionary, perks: Array) -> float:
	var total := 0.0
	for id: String in upgrades_db:
		var def: Dictionary = upgrades_db[id]
		if String(def.get("stat", "")) == stat:
			total += effect(def, int(levels.get(id, 0)))
	for perk: String in perks:
		total += float(perks_db.get(perk, {}).get(stat, 0.0))
	return total


## Applies permanent upgrades and perks to a fresh hero. Returns the run's combat limits with the
## element-mastery bonus folded into the weakness multiplier.
static func apply_to_hero(stats: HeroStats, limits: Dictionary, upgrades_db: Dictionary, levels: Dictionary, perks_db: Dictionary, perks: Array) -> Dictionary:
	stats.damage *= 1.0 + bonus("damage_pct", upgrades_db, levels, perks_db, perks) / 100.0
	stats.max_hp *= 1.0 + bonus("hp_pct", upgrades_db, levels, perks_db, perks) / 100.0
	stats.hp = stats.max_hp
	stats.projectiles += int(bonus("projectiles", upgrades_db, levels, perks_db, perks))
	var start_allies := int(bonus("start_allies", upgrades_db, levels, perks_db, perks))
	if start_allies > 0:
		stats.add_allies("skeleton", start_allies, int(limits.get("max_allies", 12)))
	var out := limits.duplicate()
	out["weak_multiplier"] = float(limits.get("weak_multiplier", 2.0)) * (1.0 + bonus("weak_bonus_pct", upgrades_db, levels, perks_db, perks) / 100.0)
	stats.clamp_to(out)
	return out


static func coin_multiplier(upgrades_db: Dictionary, levels: Dictionary, perks_db: Dictionary, perks: Array) -> float:
	return 1.0 + bonus("coin_pct", upgrades_db, levels, perks_db, perks) / 100.0


# --- Runs and milestones ----------------------------------------------------------------------

## Payout for a finished run. collected = coins picked up during the run (kills + boss).
static func run_payout(collected: int, won: bool, level: int, balance: Dictionary, coin_mult: float) -> Dictionary:
	var economy: Dictionary = balance.get("economy", {})
	var kept := float(collected) * (1.0 if won else float(economy.get("loss_keep", 1.0)))
	var bonus_coins := float(economy.get("win_bonus", 25)) * Curves.named(balance, "coin_multiplier", maxi(level, 1)) if won and level > 0 else 0.0
	var base := kept + bonus_coins
	var total := int(roundf(base * coin_mult))
	return {"collected": collected, "win_bonus": int(roundf(bonus_coins)), "upgrade_bonus": total - int(roundf(base)), "total": total}


## The milestone reward for finishing `level`, or {} if it isn't a milestone level.
static func milestone(level: int, milestones_db: Dictionary, balance: Dictionary) -> Dictionary:
	if level <= 0 or level % 10 != 0:
		return {}
	var chest := int(roundf(float(milestones_db.get("chest_base", 120)) * Curves.named(balance, "coin_multiplier", level)))
	var reward: Dictionary = (milestones_db.get("rewards", {}).get(str(level), {}) as Dictionary).duplicate()
	if reward.is_empty():
		reward = {"type": "coins", "title": "Treasure chest", "desc": "A milestone hoard."}
	reward["level"] = level
	reward["coins"] = chest
	return reward
