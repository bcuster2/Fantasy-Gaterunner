class_name EndlessDirector
extends RefCounted
## Endless mode: one unbounded run stitched from generated levels ("chunks"). Each chunk is an
## ordinary LevelBuilder plan at a rising level tier, shifted to start where the previous chunk
## ended. Only every boss_every-th chunk keeps its boss, so a boss appears every few minutes; the
## gate cadence carries straight across chunk borders. Deterministic per run seed.

var run_seed := 0
var start_tier := 1
var tier_step := 2
var boss_every := 3
var hp_growth := 1.08
var dmg_growth := 1.06
var max_edge := 2.5
var index := 0
var offset := 0.0


func _init(seed_value: int, first_tier: int, cfg: Dictionary) -> void:
	run_seed = seed_value
	start_tier = maxi(1, first_tier)
	tier_step = int(cfg.get("tier_step", 2))
	boss_every = maxi(1, int(cfg.get("boss_every", 3)))
	hp_growth = float(cfg.get("hp_growth", 1.08))
	dmg_growth = float(cfg.get("dmg_growth", 1.06))
	max_edge = float(cfg.get("max_edge", 2.5))


static func start_tier_for(unlocked_level: int, cfg: Dictionary) -> int:
	return maxi(1, int(unlocked_level * float(cfg.get("start_ratio", 0.5))))


## Next chunk as a plan-shaped Dictionary (events already shifted to run distance) plus
## start/end/index. `length` is the chunk's end distance. `current` = the hero's build right now
## (null for the first chunk): enemies scale with how far it exceeds what this tier normally builds.
func next_chunk(db: Dictionary, balance: Dictionary, current: HeroStats = null) -> Dictionary:
	var tier := start_tier + index * tier_step
	var plan := LevelBuilder.build(tier, LevelSeed.fnv1a("endless/%d/%d" % [run_seed, index]), db, balance)
	var build_hp := 1.0
	var build_dmg := 1.0
	if current != null:
		var reference: HeroStats = Estimator.run(plan, LevelBuilder.expected_hero(tier, db, balance), "best", db, balance)["stats"]
		var dps_ratio := Estimator.effective_dps(current, db, balance) / maxf(Estimator.effective_dps(reference, db, balance), 0.001)
		var hp_ratio := current.max_hp / maxf(reference.max_hp, 1.0)
		# A build may be up to max_edge times stronger than normal; beyond that, enemies keep pace.
		build_hp = maxf(dps_ratio, 1.0) / minf(maxf(dps_ratio, 1.0), max_edge)
		build_dmg = maxf(hp_ratio, 1.0) / minf(maxf(hp_ratio, 1.0), max_edge)
	var keep_boss := (index + 1) % boss_every == 0
	# Builds carry over between chunks (7 gates each, multipliers compound), so a chunk's enemies
	# scale with the hero's actual build vs. what a normal level at this tier builds to. A strong
	# build keeps up to max_edge of advantage; a small per-chunk growth eventually ends every run.
	var hp_pressure := pow(hp_growth, index) * build_hp
	var dmg_pressure := pow(dmg_growth, index) * build_dmg
	var events: Array = []
	var boss_event := {}
	for src: Dictionary in plan["events"]:
		var e := src.duplicate(true)
		e["d"] = float(e["d"]) + offset
		match String(e.get("type", "")):
			"enemies":
				e["hp_mult"] = float(e["hp_mult"]) * hp_pressure
				e["dmg_mult"] = float(e["dmg_mult"]) * dmg_pressure
			"boss":
				e["hp"] = roundf(float(e["hp"]) * hp_pressure)
				e["damage_unit"] = float(e["damage_unit"]) * dmg_pressure
		if String(e.get("type", "")) == "boss":
			if keep_boss:
				boss_event = e
				events.append(e)
			continue
		events.append(e)
	var chunk := plan.duplicate()
	chunk.erase("debug")
	chunk["events"] = events
	chunk["index"] = index
	chunk["tier"] = tier
	chunk["start"] = offset
	chunk["end"] = offset + float(plan["length"])
	chunk["length"] = chunk["end"]
	chunk["boss_event"] = boss_event
	chunk["pressure"] = {"hp": hp_pressure, "dmg": dmg_pressure}
	offset = float(chunk["end"]) + (8.0 if keep_boss else 0.0)
	index += 1
	return chunk
