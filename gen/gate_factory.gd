class_name GateFactory
extends RefCounted
## Turns a gate pattern ("any", "stat", "element", "summon", "curse", "breather", "preboss") into
## concrete gate definitions scaled for the level. Pure: the context carries every table it needs.
##
## ctx keys: level, gates (gates.json), elements, palette (Array[String]), element_unlocked,
##           power (player_power curve), hp_power (player_hp curve), bad_chance.


static func make(pattern: String, ctx: Dictionary, rng: RandomNumberGenerator, required_element := "") -> Array:
	var level := int(ctx["level"])
	if required_element != "":
		pattern = "element"
	if pattern == "any":
		pattern = String(GenUtil.pick_weighted(rng, _pattern_list(ctx), level).get("id", "stat"))
	if pattern == "element" and not bool(ctx["element_unlocked"]):
		pattern = "stat"
	if pattern in ["summon", "curse"] and _pool(ctx, pattern).filter(func(t: Dictionary) -> bool: return GenUtil.available(t, level)).is_empty():
		pattern = "stat"

	var out: Array = []
	match pattern:
		"element":
			out = _element_options(ctx, rng, required_element)
		"summon":
			out = [summon_gate(ctx, rng), good_gate(ctx, rng)]
			if level >= 6 and rng.randf() < 0.3:
				out.append(summon_gate(ctx, rng))
		"curse":
			out = [curse_gate(ctx, rng), good_gate(ctx, rng) if rng.randf() < 0.6 else summon_gate(ctx, rng)]
		"breather":
			out = [_template_gate(GenUtil.pick_weighted(rng, _pool(ctx, "heal"), level), ctx, rng), good_gate(ctx, rng)]
		"preboss":
			out = _distinct(ctx, rng, "strong", 3)
		_:
			var count := 3 if level >= 3 and rng.randf() < 0.35 else 2
			out = _distinct(ctx, rng, "good", count)
			if rng.randf() < float(ctx["bad_chance"]):
				var bad := GenUtil.pick_weighted(rng, _pool(ctx, "bad"), level)
				if not bad.is_empty():
					out[rng.randi_range(0, out.size() - 1)] = _template_gate(bad, ctx, rng)
	GenUtil.shuffle(rng, out)
	return out


static func good_gate(ctx: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	return _template_gate(GenUtil.pick_weighted(rng, _pool(ctx, "good"), int(ctx["level"])), ctx, rng)


static func summon_gate(ctx: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var t := GenUtil.pick_weighted(rng, _pool(ctx, "summon"), int(ctx["level"]))
	if t.is_empty():
		return good_gate(ctx, rng)
	var count_value: Variant = t.get("count", 1)
	var count := rng.randi_range(int(count_value[0]), int(count_value[1])) if count_value is Array else int(count_value)
	return {"kind": "summon", "ally": String(t.get("ally", "skeleton")), "count": count}


static func curse_gate(ctx: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var t := GenUtil.pick_weighted(rng, _pool(ctx, "curse"), int(ctx["level"]))
	if t.is_empty():
		return good_gate(ctx, rng)
	return {"kind": "curse", "id": String(t.get("id", "")), "effects": (t.get("effects", []) as Array).duplicate(true)}


static func _element_options(ctx: Dictionary, rng: RandomNumberGenerator, required: String) -> Array:
	var elements: Dictionary = ctx["elements"]
	var names: Array = elements.keys()
	names.sort()
	# Weaknesses of this level's enemy palette come first so the answer is usually on offer.
	var preferred: Array = []
	if required != "":
		preferred.append(required)
	for element: String in ctx["palette"]:
		var weak := String(elements.get(element, {}).get("weak_to", ""))
		if weak != "" and not preferred.has(weak):
			preferred.append(weak)
	var rest := names.filter(func(n: String) -> bool: return not preferred.has(n))
	GenUtil.shuffle(rng, rest)
	var count := 3 if rng.randf() < 0.5 else 2
	var picked: Array = []
	for name: String in preferred + rest:
		if picked.size() >= count:
			break
		picked.append(name)
	var out: Array = []
	for name: String in picked:
		out.append({"kind": "element", "element": name})
	# Sometimes trade one element option for a stat boost, but never the required one.
	if out.size() == 3 and rng.randf() < 0.35:
		var idx := out.size() - 1
		if String(out[idx]["element"]) != required:
			out[idx] = good_gate(ctx, rng)
	return out


## Up to `count` gates from a pool, preferring different stats so choices feel distinct.
static func _distinct(ctx: Dictionary, rng: RandomNumberGenerator, pool_name: String, count: int) -> Array:
	var out: Array = []
	var used_stats: Array = []
	for attempt in count * 4:
		if out.size() >= count:
			break
		var t := GenUtil.pick_weighted(rng, _pool(ctx, pool_name), int(ctx["level"]))
		if t.is_empty():
			break
		var stat := String(t.get("stat", ""))
		if used_stats.has(stat) and attempt < count * 3:
			continue
		used_stats.append(stat)
		out.append(_template_gate(t, ctx, rng))
	while out.size() < count:
		out.append(good_gate(ctx, rng))
	return out


static func _template_gate(t: Dictionary, ctx: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	if t.is_empty():
		return {"stat": "damage", "op": "add", "value": 1}
	var op := String(t.get("op", "add"))
	var v := GenUtil.value(rng, t.get("value", 1))
	match String(t.get("scale", "")):
		"power":
			v *= float(ctx["power"])
		"hp":
			v *= float(ctx["hp_power"])
	if op == "mul":
		v = snappedf(v, 0.25)
	elif String(t.get("stat", "")) == "fire_rate":
		v = snappedf(v, 0.5)
	else:
		v = roundf(v)
	if v == 0.0 and op == "add":
		v = 1.0
	return {"stat": String(t.get("stat", "damage")), "op": op, "value": v}


static func _pool(ctx: Dictionary, pool_name: String) -> Array:
	return ctx["gates"].get(pool_name, [])


static func _pattern_list(ctx: Dictionary) -> Array:
	var out: Array = []
	var patterns: Dictionary = ctx["gates"].get("patterns", {})
	for id: String in patterns:
		if id.begins_with("_"):
			continue
		var entry: Dictionary = (patterns[id] as Dictionary).duplicate()
		entry["id"] = id
		out.append(entry)
	return out
