class_name LevelBuilder
extends RefCounted
## Seeded level assembly. Pure: build(level, seed, db, balance) always returns the same plan.
##
## Steps: pick a pacing template -> adjust for the level's rhythm (spike/reward) -> fill each slot
## with a weighted segment for that role -> instantiate events (density-scaled counts, element
## palette, difficulty curves, generated gates) -> fairness repairs -> winnability check with an
## expected-upgrade hero (enemies are scaled down until the best gate path survives with margin).

const COUNT_KEYS := ["count", "rows", "cols"]
const START_OFFSET := 14.0
const ROLE_FALLBACKS := {
	"element_wall": ["pressure"],
	"climax": ["pressure"],
	"intro": ["buildup"],
	"preboss": ["gate"],
}
const ZONES := ["forest", "crypt", "volcano"]


static func build(level: int, seed_value: int, db: Dictionary, balance: Dictionary) -> Dictionary:
	var started := Time.get_ticks_usec()
	level = maxi(1, level)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var rhythm: Dictionary = balance.get("rhythm", {})
	var gen: Dictionary = balance.get("generator", {})
	var kind := Curves.level_kind(level, rhythm)
	var rhythm_mult := Curves.rhythm_mult(kind, rhythm)
	var ctx := make_context(level, db, balance, rng)
	ctx["hp_mult"] = Curves.named(balance, "enemy_hp", level) * rhythm_mult
	ctx["dmg_mult"] = Curves.named(balance, "enemy_damage", level) * rhythm_mult

	var template := GenUtil.pick_weighted(rng, _templates(db), level)
	var slots: Array = (template.get("slots", ["intro", "gate", "buildup", "preboss"]) as Array).duplicate()
	_apply_rhythm(slots, kind)

	var events: Array = []
	var segments_debug: Array = []
	var cursor := START_OFFSET
	var previous_id := ""
	for role: String in slots:
		var seg := _pick_segment(role, level, db, rng, previous_id)
		if seg.is_empty():
			continue
		previous_id = String(seg.get("id", ""))
		var mirror := bool(seg.get("mirror", true)) and rng.randf() < 0.5
		var swap := rng.randf() < 0.5
		for src: Dictionary in seg.get("events", []):
			events.append(_instantiate(src, cursor, mirror, swap, ctx, rng))
		segments_debug.append({"id": previous_id, "role": role, "start": cursor, "end": cursor + float(seg.get("length", 20))})
		cursor += float(seg.get("length", 20))

	var plan := {
		"id": "level_%d" % level,
		"level": level,
		"seed": seed_value,
		"kind": kind,
		"template": String(template.get("id", "")),
		"length": cursor + float(gen.get("end_padding", 30.0)),
		"events": events,
		"palette": ctx["palette"],
		"zone": ZONES[((level - 1) / 10) % ZONES.size()],
		"zone_cycle": (level - 1) / (10 * ZONES.size()),
		"boss": {"kind": "major" if kind == "boss" else "mini"},
		"modifiers": [],
		"coin_mult": Curves.named(balance, "coin_multiplier", level) * (1.5 if kind == "reward" else 1.0),
		"hero_power": float(ctx["power"]),
		"hero_hp_power": float(ctx["hp_power"]),
		"ally_power": float(ctx["power"]),
	}

	var lookback := float(gen.get("wall_lookback", 140.0))
	var window := float(gen.get("density_window", 25.0))
	var density_cap := Curves.named(balance, "max_density", level)
	var fixes := {
		"walls": Fairness.repair_walls(plan, ctx, rng, lookback),
		"gates": Fairness.repair_gates(plan, ctx, rng),
		"density": Fairness.cap_density(plan, db["enemies"], window, density_cap),
	}
	_sort_events(plan)

	# Winnability: the expected hero taking the best path must finish with HP to spare.
	var hero := expected_hero(level, db, balance)
	var margin := float(gen.get("min_hp_margin_spike" if kind in ["spike", "boss"] else "min_hp_margin", 0.15))
	var difficulty := 1.0
	var estimate := Estimator.run(plan, hero, "best", db, balance)
	var repairs := 0
	while (not bool(estimate["survived"]) or float(estimate["hp_frac"]) < margin) and repairs < int(gen.get("max_repairs", 8)):
		var step := float(gen.get("repair_scale", 0.88))
		difficulty *= step
		_scale_enemies(plan, step)
		# Weak builds are often shot-limited (one-shotting already), so later repairs thin crowds too.
		if repairs >= 2:
			for event: Dictionary in plan["events"]:
				if String(event.get("type", "")) == "enemies":
					Fairness.shrink_event(event)
		estimate = Estimator.run(plan, hero, "best", db, balance)
		repairs += 1

	plan["debug"] = {
		"segments": segments_debug,
		"fixes": fixes,
		"difficulty_scale": difficulty,
		"estimate": {"survived": estimate["survived"], "hp_frac": estimate["hp_frac"], "kills": estimate["kills"], "units": estimate["units"]},
		"density_cap": density_cap,
		"gen_ms": (Time.get_ticks_usec() - started) / 1000.0,
	}
	return plan


## Generator context shared with GateFactory (and the simulator).
static func make_context(level: int, db: Dictionary, balance: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var gen: Dictionary = balance.get("generator", {})
	var density_curve: Dictionary = balance.get("curves", {}).get("density", {})
	var density := Curves.eval(density_curve, level)
	var density_cap := float(density_curve.get("cap", 2.0))
	var unlocked := level >= int(gen.get("element_unlock_level", 3))
	return {
		"level": level,
		"gates": db["gates"],
		"elements": db["elements"],
		"power": Curves.named(balance, "player_power", level),
		"hp_power": Curves.named(balance, "player_hp", level),
		"bad_chance": Curves.named(balance, "bad_gate_chance", level) if level >= 2 else 0.0,
		"element_unlocked": unlocked,
		"element_chance": float(gen.get("element_chance", 0.75)),
		"palette": _pick_palette(db["elements"], int(gen.get("palette_size", 2)), rng) if unlocked else [],
		"density_t": inverse_lerp(1.0, density_cap, density) if density_cap > 1.0 else 0.0,
	}


## The hero the fairness check assumes: class base stats with the expected upgrade level.
static func expected_hero(level: int, db: Dictionary, balance: Dictionary, class_id := "battlemage") -> HeroStats:
	var classes: Dictionary = db["classes"]
	var def: Dictionary = classes.get(class_id, classes.values()[0] if not classes.is_empty() else {})
	var s := HeroStats.from_class(def)
	apply_level_scaling(s, Curves.named(balance, "player_power", level), Curves.named(balance, "player_hp", level))
	return s


static func apply_level_scaling(s: HeroStats, power: float, hp_power: float) -> void:
	s.damage *= power
	s.max_hp *= hp_power
	s.hp = s.max_hp
	s.ally_power = power


static func _templates(db: Dictionary) -> Array:
	var out: Array = []
	for id: String in db["pacing"]:
		var t: Dictionary = (db["pacing"][id] as Dictionary).duplicate()
		t["id"] = id
		out.append(t)
	return out


static func _apply_rhythm(slots: Array, kind: String) -> void:
	match kind:
		"reward":
			var p := slots.rfind("pressure")
			if p >= 0:
				slots[p] = "breather"
		"spike", "boss":
			var b := slots.find("breather")
			if b >= 0:
				slots[b] = "pressure"


static func _pick_segment(role: String, level: int, db: Dictionary, rng: RandomNumberGenerator, previous_id: String) -> Dictionary:
	for candidate_role: String in [role] + Array(ROLE_FALLBACKS.get(role, [])):
		var pool: Array = db["segments"].filter(func(s: Dictionary) -> bool: return (s.get("roles", []) as Array).has(candidate_role))
		var seg := GenUtil.pick_weighted(rng, pool, level)
		if not seg.is_empty() and String(seg.get("id", "")) == previous_id:
			seg = GenUtil.pick_weighted(rng, pool, level) # one re-roll to avoid back-to-back repeats
		if not seg.is_empty():
			return seg
	return {}


static func _pick_palette(elements: Dictionary, size: int, rng: RandomNumberGenerator) -> Array:
	var names: Array = elements.keys()
	names.sort()
	GenUtil.shuffle(rng, names)
	return names.slice(0, clampi(size, 1, names.size()))


static func _instantiate(src: Dictionary, cursor: float, mirror: bool, swap: bool, ctx: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var e := {}
	for key: String in src:
		var v: Variant = src[key]
		if key in COUNT_KEYS:
			e[key] = GenUtil.scaled_int(v, float(ctx["density_t"]))
		elif v is Array and key != "gates":
			e[key] = GenUtil.value(rng, v)
		else:
			e[key] = v
	e["d"] = cursor + float(src.get("d", 0.0))
	match String(e.get("type", "")):
		"enemies":
			if mirror and e.has("x"):
				e["x"] = -float(e["x"])
			e["element"] = _resolve_element(String(src.get("element", "none")), swap, ctx, rng)
			if String(src.get("element", "")) == "$wall":
				e["wall"] = true
			e["hp_mult"] = float(e.get("hp", 1.0)) * float(ctx["hp_mult"])
			e["dmg_mult"] = float(ctx["dmg_mult"])
			e.erase("hp")
		"gates":
			e["gates"] = GateFactory.make(String(src.get("pattern", "any")), ctx, rng)
	return e


static func _resolve_element(token: String, swap: bool, ctx: Dictionary, rng: RandomNumberGenerator) -> String:
	var palette: Array = ctx["palette"]
	if palette.is_empty() or not token.begins_with("$"):
		return token if not token.begins_with("$") else "none"
	var a: String = palette[0]
	var b: String = palette[1 % palette.size()]
	if swap:
		var tmp := a
		a = b
		b = tmp
	match token:
		"$wall":
			return a
		"$mix":
			return String(palette[rng.randi_range(0, palette.size() - 1)]) if rng.randf() < float(ctx["element_chance"]) else "none"
		"$B":
			return b if rng.randf() < float(ctx["element_chance"]) else "none"
		_:
			return a if rng.randf() < float(ctx["element_chance"]) else "none"


static func _scale_enemies(plan: Dictionary, step: float) -> void:
	for event: Dictionary in plan["events"]:
		if String(event.get("type", "")) == "enemies":
			event["hp_mult"] = float(event["hp_mult"]) * step
			event["dmg_mult"] = float(event["dmg_mult"]) * step


static func _sort_events(plan: Dictionary) -> void:
	var events: Array = plan["events"]
	for k in events.size():
		events[k]["_seq"] = k
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a["d"]) != float(b["d"]):
			return float(a["d"]) < float(b["d"])
		return int(a["_seq"]) < int(b["_seq"]))
	for event: Dictionary in events:
		event.erase("_seq")
