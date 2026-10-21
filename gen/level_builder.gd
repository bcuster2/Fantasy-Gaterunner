class_name LevelBuilder
extends RefCounted
## Seeded level assembly. Pure: build(level, seed, db, balance) always returns the same plan.
##
## Steps: place gates on the fixed cadence (random contents) -> pick a pacing template for what to
## fight between them -> adjust for the level's rhythm (spike/reward) -> fill each stretch with a
## weighted segment for its role -> instantiate events (density-scaled counts, element palette,
## difficulty curves) -> fairness repairs -> difficulty targeting and a winnability guarantee.

const COUNT_KEYS := ["count", "rows", "cols"]
const START_OFFSET := 14.0
const ROLE_FALLBACKS := {
	"element_wall": ["pressure"],
	"climax": ["pressure"],
	"intro": ["buildup"],
	"breather": ["intro"],
	"finale": ["climax", "pressure"],
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
	ctx["hp_mult"] = Curves.named(balance, "enemy_hp", level)
	ctx["dmg_mult"] = Curves.named(balance, "enemy_damage", level)
	# Spike/reward multipliers lean on the back half (see _opening_weighted): a spike level is a
	# harder climax, never an unwinnable opening for a base-stat hero.
	ctx["rhythm_mult"] = rhythm_mult
	ctx["opening_weight"] = float(gen.get("upscale_opening_weight", 0.25))

	var template := GenUtil.pick_weighted(rng, _templates(db), level)
	var cadence: Dictionary = gen.get("cadence", {})
	var gate_count := int(cadence.get("gate_count", 6))
	var interval := float(cadence.get("interval", 58.0))
	var clear_after := float(cadence.get("clear_after_gate", 12.0))
	var clear_before := float(cadence.get("clear_before_gate", 6.0))
	var first_gate := START_OFFSET + float(cadence.get("intro_length", 40.0))
	var roles: Array = (template.get("intervals", []) as Array).duplicate()
	while roles.size() < gate_count:
		roles.append("pressure")
	roles.resize(gate_count)
	_apply_rhythm(roles, kind)

	# Fixed cadence: gate k always sits at first_gate + k * interval, with random contents. Enemy
	# segments fill the stretch after each gate. The hero starts every run weak, so crowds and
	# toughness ramp up across the level (early stretches use part of the density and HP).
	var events: Array = []
	var segments_debug: Array = []
	var previous_id := ""
	var ramp_full := float(gen.get("ramp_full_at", 0.6))
	for stretch in gate_count + 1:
		var role := String(template.get("intro", "intro")) if stretch == 0 else String(roles[stretch - 1])
		var start := START_OFFSET if stretch == 0 else first_gate + (stretch - 1) * interval + clear_after
		var room := (first_gate - clear_before - START_OFFSET) if stretch == 0 else (interval - clear_after - clear_before)
		if stretch > 0:
			var gate_d := first_gate + (stretch - 1) * interval
			events.append({"d": gate_d, "type": "gates", "gates": GateFactory.make("any", ctx, rng), "cadence": stretch})
			segments_debug.append({"id": "gate %d" % stretch, "role": "gate", "start": gate_d, "end": gate_d})
		var progress := float(stretch) / float(gate_count)
		var ramp := smoothstep(0.0, ramp_full, progress)
		ctx["slot_density_t"] = float(ctx["density_t"]) * lerpf(float(gen.get("density_ramp_start", 0.2)), 1.0, ramp)
		ctx["slot_hp_mult"] = float(ctx["hp_mult"]) * lerpf(float(gen.get("hp_ramp_start", 0.75)), 1.0, ramp)
		ctx["progress"] = progress
		var seg := _pick_segment(role, level, db, rng, previous_id, room + 4.0)
		if seg.is_empty():
			continue
		previous_id = String(seg.get("id", ""))
		var mirror := bool(seg.get("mirror", true)) and rng.randf() < 0.5
		var swap := rng.randf() < 0.5
		for src: Dictionary in seg.get("events", []):
			if float(src.get("d", 0.0)) <= room:
				events.append(_instantiate(src, start, mirror, swap, ctx, rng))
		segments_debug.append({"id": previous_id, "role": role, "start": start, "end": start + minf(room, float(seg.get("length", room)))})

	var preboss_d := first_gate + gate_count * interval
	events.append({"d": preboss_d, "type": "gates", "gates": GateFactory.make("preboss", ctx, rng), "cadence": gate_count + 1})
	segments_debug.append({"id": "pre-boss gate", "role": "preboss", "start": preboss_d, "end": preboss_d})

	# Every level ends on a fight, not a gate: a final wave right after the pre-boss gate tests the
	# finished build. (Milestone 5's boss arena follows it.)
	var finale_start := preboss_d + clear_after
	var finale_room := float(cadence.get("finale_length", 44.0))
	ctx["slot_density_t"] = float(ctx["density_t"])
	ctx["slot_hp_mult"] = float(ctx["hp_mult"])
	ctx["progress"] = 1.0
	var finale_role := String(template.get("finale", "finale"))
	var finale := _pick_segment(finale_role, level, db, rng, previous_id, finale_room + 4.0)
	var last_enemy_d := finale_start
	if not finale.is_empty():
		var mirror_finale := bool(finale.get("mirror", true)) and rng.randf() < 0.5
		var swap_finale := rng.randf() < 0.5
		for src: Dictionary in finale.get("events", []):
			if float(src.get("d", 0.0)) <= finale_room:
				var e := _instantiate(src, finale_start, mirror_finale, swap_finale, ctx, rng)
				events.append(e)
				var depth := 0.0
				for offset in Formations.offsets(e):
					depth = maxf(depth, offset.y)
				last_enemy_d = maxf(last_enemy_d, float(e["d"]) + depth)
		segments_debug.append({"id": String(finale.get("id", "")), "role": finale_role, "start": finale_start, "end": finale_start + finale_room})
	var finish_d := maxf(finale_start + finale_room, last_enemy_d + float(cadence.get("finish_after_last_enemy", 14.0)))

	var plan := {
		"id": "level_%d" % level,
		"level": level,
		"seed": seed_value,
		"kind": kind,
		"template": String(template.get("id", "")),
		"length": finish_d,
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

	# Difficulty targeting + winnability. The curves set the baseline; the estimator then nudges enemy
	# HP/damage so a median player's score lands inside the target band for this level kind (keeps the
	# spike/reward rhythm readable and evens out segment luck). Score = distance fraction reached if
	# the median path dies, else 1 + remaining HP fraction. Finally a hard guarantee: the best path
	# must survive with a margin, scaling down and thinning crowds if needed.
	var hero := expected_hero(level, db, balance)
	var band: Array = (gen.get("target_median_score", {}).get(kind, [0.75, 1.15]) as Array).duplicate()
	# Onboarding: the first levels aim higher, fading to the normal bands by onboarding_levels.
	var onboarding := clampf(1.0 - float(level - 1) / maxf(1.0, float(gen.get("onboarding_levels", 15))), 0.0, 1.0)
	band[0] = float(band[0]) + float(gen.get("onboarding_shift", 0.35)) * onboarding
	band[1] = float(band[1]) + float(gen.get("onboarding_shift", 0.35)) * onboarding
	# New players: through the first levels the median gate path must actually finish.
	if level <= int(gen.get("onboarding_survive_levels", 15)):
		band[0] = maxf(float(band[0]), 1.05)
		band[1] = maxf(float(band[1]), float(band[0]) + 0.3)
	var margin := float(gen.get("min_hp_margin_spike" if kind in ["spike", "boss"] else "min_hp_margin", 0.15))
	var max_up := float(gen.get("max_upscale", 1.4))
	var difficulty := 1.0
	var median_score := median_score_of(plan, hero, db, balance)
	for tune in int(gen.get("max_tune_steps", 6)):
		var hp := median_score
		var step := 1.0
		if hp < float(band[0]):
			step = float(gen.get("tune_down", 0.9))
		elif hp > float(band[1]) and difficulty < max_up:
			step = minf(float(gen.get("tune_up", 1.1)), max_up / difficulty)
		if is_equal_approx(step, 1.0):
			break
		difficulty *= step
		# Making a level harder mostly toughens the later stretches, where gate-built power lives;
		# the opening (base stats) barely changes. Easing applies everywhere.
		_scale_enemies(plan, step, float(gen.get("upscale_opening_weight", 0.25)) if step > 1.0 else 1.0)
		median_score = median_score_of(plan, hero, db, balance)
	var estimate := Estimator.run(plan, hero, "best", db, balance)
	var repairs := 0
	# The margin applies to the closest call during the run, not the HP left at the finish.
	while (not bool(estimate["survived"]) or float(estimate["min_hp_frac"]) < margin) and repairs < int(gen.get("max_repairs", 8)):
		var repair_step := float(gen.get("repair_scale", 0.88))
		difficulty *= repair_step
		_scale_enemies(plan, repair_step)
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
		"median_score": median_score_of(plan, hero, db, balance),
		"estimate": {"survived": estimate["survived"], "hp_frac": estimate["hp_frac"], "min_hp_frac": estimate["min_hp_frac"], "kills": estimate["kills"], "units": estimate["units"]},
		"density_cap": density_cap,
		"gen_ms": (Time.get_ticks_usec() - started) / 1000.0,
	}
	return plan


## Difficulty signal: distance fraction if the median gate path dies, else 1 + HP fraction left.
static func median_score_of(plan: Dictionary, hero: HeroStats, db: Dictionary, balance: Dictionary) -> float:
	var r := Estimator.run(plan, hero, "median", db, balance)
	if bool(r["survived"]):
		return 1.0 + float(r["hp_frac"])
	return float(r["distance"]) / maxf(float(plan.get("length", 1.0)), 1.0)


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


static func _pick_segment(role: String, level: int, db: Dictionary, rng: RandomNumberGenerator, previous_id: String, max_length := INF) -> Dictionary:
	for candidate_role: String in [role] + Array(ROLE_FALLBACKS.get(role, [])):
		var pool: Array = db["segments"].filter(func(s: Dictionary) -> bool:
			return (s.get("roles", []) as Array).has(candidate_role) and float(s.get("length", 0.0)) <= max_length)
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
			e[key] = GenUtil.scaled_int(v, float(ctx.get("slot_density_t", ctx["density_t"])))
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
			var rhythm := _opening_weighted(float(ctx.get("rhythm_mult", 1.0)), float(ctx.get("progress", 1.0)), float(ctx.get("opening_weight", 1.0)))
			e["hp_mult"] = float(e.get("hp", 1.0)) * float(ctx.get("slot_hp_mult", ctx["hp_mult"])) * rhythm
			e["progress"] = snappedf(float(ctx.get("progress", 1.0)), 0.001)
			e["dmg_mult"] = float(ctx["dmg_mult"]) * rhythm
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


## factor^weight, where weight rises from opening_weight at the start of the level to 1.0 by the
## halfway point: harder-than-baseline multipliers mostly land where the build has grown.
static func _opening_weighted(factor: float, progress: float, opening_weight: float) -> float:
	if factor <= 1.0:
		return factor
	return pow(factor, lerpf(opening_weight, 1.0, clampf(progress * 2.0, 0.0, 1.0)))


## Scales enemy HP/damage; with opening_weight < 1 increases mostly hit the back half.
static func _scale_enemies(plan: Dictionary, step: float, opening_weight := 1.0) -> void:
	for event: Dictionary in plan["events"]:
		if String(event.get("type", "")) == "enemies":
			var factor := _opening_weighted(step, float(event.get("progress", 1.0)), opening_weight)
			event["hp_mult"] = float(event["hp_mult"]) * factor
			event["dmg_mult"] = float(event["dmg_mult"]) * factor


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
