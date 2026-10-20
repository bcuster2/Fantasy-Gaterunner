class_name Fairness
extends RefCounted
## Fairness guarantees, applied to every generated plan (and checked by tools/gen_check.gd):
##  1. Every gate set offers at least one safe option (good stat, element, or summon), so two
##     harmful gates are never the only choice.
##  2. Every element-locked wall has an earlier gate set (the last one before it, within
##     wall_lookback meters) that offers the wall's weakness element.
##  3. Enemy density inside any window never exceeds the readability cap for the level.
## Winnability (an expected-upgrade hero survives the best gate path) is enforced by LevelBuilder.

const SAFE := ["good", "element", "summon"]


static func has_safe_option(gates: Array) -> bool:
	for gate: Dictionary in gates:
		if GateInfo.category(gate) in SAFE:
			return true
	return false


static func offers_element(gates: Array, element: String) -> bool:
	for gate: Dictionary in gates:
		if String(gate.get("kind", "")) == "element" and String(gate.get("element", "")) == element:
			return true
	return false


static func repair_gates(plan: Dictionary, ctx: Dictionary, rng: RandomNumberGenerator) -> int:
	var fixes := 0
	for event: Dictionary in plan["events"]:
		if String(event.get("type", "")) != "gates":
			continue
		var gates: Array = event["gates"]
		if has_safe_option(gates):
			continue
		for k in gates.size():
			if GateInfo.category(gates[k]) in ["bad", "curse"]:
				gates[k] = GateFactory.good_gate(ctx, rng)
				fixes += 1
				break
	return fixes


## Wall events carry "wall": true. Fixes the last gate set before each wall, or inserts one.
static func repair_walls(plan: Dictionary, ctx: Dictionary, rng: RandomNumberGenerator, lookback: float) -> int:
	var fixes := 0
	var events: Array = plan["events"]
	var k := 0
	while k < events.size():
		var event: Dictionary = events[k]
		if not bool(event.get("wall", false)):
			k += 1
			continue
		var need := String(ctx["elements"].get(String(event.get("element", "")), {}).get("weak_to", ""))
		if need == "":
			k += 1
			continue
		var gate_index := -1
		for j in range(k - 1, -1, -1):
			if String(events[j].get("type", "")) == "gates":
				gate_index = j
				break
		var wall_d := float(event["d"])
		if gate_index >= 0 and wall_d - float(events[gate_index]["d"]) <= lookback:
			if not offers_element(events[gate_index]["gates"], need):
				events[gate_index]["gates"] = GateFactory.make("element", ctx, rng, need)
				events[gate_index]["repaired"] = "wall:" + need
				fixes += 1
		else:
			events.insert(k, {"d": maxf(4.0, wall_d - 22.0), "type": "gates", "gates": GateFactory.make("element", ctx, rng, need), "repaired": "inserted:" + need})
			k += 1
			fixes += 1
		k += 1
	return fixes


static func density_cost(event: Dictionary, enemies_db: Dictionary) -> float:
	var def: Dictionary = enemies_db.get(String(event.get("enemy", "grunt")), {})
	return Formations.offsets(event).size() * float(def.get("density", 1.0))


## Thins the heaviest event in any over-cap window until every window is readable.
static func cap_density(plan: Dictionary, enemies_db: Dictionary, window: float, cap: float) -> int:
	var fixes := 0
	var enemies: Array = plan["events"].filter(func(e: Dictionary) -> bool: return String(e.get("type", "")) == "enemies")
	for guard in 400:
		var worst_window := -1.0
		var heaviest: Dictionary = {}
		for a: Dictionary in enemies:
			var start := float(a["d"])
			var total := 0.0
			var top: Dictionary = {}
			for b: Dictionary in enemies:
				var d := float(b["d"])
				if d >= start and d < start + window:
					total += density_cost(b, enemies_db)
					if top.is_empty() or density_cost(b, enemies_db) > density_cost(top, enemies_db):
						top = b
			if total > cap and total > worst_window:
				worst_window = total
				heaviest = top
		if heaviest.is_empty():
			break
		if not shrink_event(heaviest):
			plan["events"].erase(heaviest)
			enemies.erase(heaviest)
		fixes += 1
	return fixes


static func shrink_event(event: Dictionary) -> bool:
	if bool(event.get("wall", false)):
		return false
	for key in ["count", "rows", "cols"]:
		if event.has(key) and int(event[key]) > 1:
			event[key] = int(event[key]) - 1
			return true
	return false


## Returns a list of human-readable problems (empty = fair). Used by tests and the debug overlay.
static func validate(plan: Dictionary, ctx: Dictionary, enemies_db: Dictionary, window: float, cap: float, lookback: float) -> Array[String]:
	var problems: Array[String] = []
	var events: Array = plan["events"]
	var last_gates: Dictionary = {}
	for event: Dictionary in events:
		match String(event.get("type", "")):
			"gates":
				if not has_safe_option(event["gates"]):
					problems.append("unsafe gate set at %dm" % int(event["d"]))
				last_gates = event
			"enemies":
				if bool(event.get("wall", false)):
					var need := String(ctx["elements"].get(String(event.get("element", "")), {}).get("weak_to", ""))
					if need != "" and (last_gates.is_empty() or float(event["d"]) - float(last_gates["d"]) > lookback or not offers_element(last_gates["gates"], need)):
						problems.append("wall at %dm lacks a %s gate" % [int(event["d"]), need])
	for a: Dictionary in events:
		if String(a.get("type", "")) != "enemies":
			continue
		var total := 0.0
		for b: Dictionary in events:
			if String(b.get("type", "")) == "enemies" and float(b["d"]) >= float(a["d"]) and float(b["d"]) < float(a["d"]) + window:
				total += density_cost(b, enemies_db)
		if total > cap + 0.001:
			problems.append("density %.1f > %.1f at %dm" % [total, cap, int(a["d"])])
			break
	return problems
