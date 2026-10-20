class_name Estimator
extends RefCounted
## Fast analytic estimate of how a hero fares on a LevelPlan (no physics, no nodes).
## Used by the generator's winnability check and by the headless simulator.
##
## Model per enemy group: the hero (plus allies) has a time window between entering weapon range
## and contact. Enemies not killed in that window "leak": they hit front-line allies or the hero.
## Ranged enemies fire while alive. Element multipliers, overkill waste, and allies all apply.
##
## Policies:  "best"   = takes the highest-scoring gate (CombatMath.gate_score),
##            "random" = picks gates uniformly (sample many seeds for a median player),
##            "worst"  = takes the lowest-scoring gate.

const GROUP_GAP := 12.0
const MIX_HORIZON := 150.0


## Pass an Array as `trace` to collect a human-readable log of choices and damage.
static func run(plan: Dictionary, start: HeroStats, policy: String, db: Dictionary, balance: Dictionary, rng: RandomNumberGenerator = null, trace = null) -> Dictionary:
	var s := start.copy()
	var limits: Dictionary = balance.get("combat", {})
	var events: Array = plan.get("events", [])
	var kills := 0
	var units := 0
	var coins := 0.0
	var coin_mult := float(plan.get("coin_mult", 1.0)) * float(balance.get("economy", {}).get("coin_multiplier", 1.0))
	var choices: Array = []
	var i := 0
	while i < events.size():
		var event: Dictionary = events[i]
		if String(event.get("type", "")) == "gates":
			var gates: Array = event.get("gates", [])
			if not gates.is_empty():
				var mix := mix_from_events(events, i + 1, float(event["d"]), MIX_HORIZON, db)
				var pick := _choose(gates, s, policy, mix, db, limits, rng)
				s.apply_gate(gates[pick], limits)
				choices.append(pick)
				if trace is Array:
					trace.append("%5dm gate -> %s  (dmg %.1f rate %.1f shots %d %s allies %s)" % [int(event["d"]), gates[pick], s.damage, s.fire_rate, s.projectiles, s.element, s.allies])
			i += 1
			continue
		if String(event.get("type", "")) != "enemies":
			i += 1
			continue
		var group: Array = [event]
		var j := i + 1
		while j < events.size() and String(events[j].get("type", "")) == "enemies" and float(events[j]["d"]) - float(event["d"]) < GROUP_GAP:
			group.append(events[j])
			j += 1
		var hp_before := s.hp
		var result := _engage(group, s, policy, db, balance)
		if trace is Array:
			var names: PackedStringArray = []
			for g: Dictionary in group:
				names.append("%s/%s x%d hp%.1f" % [g.get("enemy"), g.get("element"), Formations.offsets(g).size(), float(g.get("hp_mult", 1))])
			trace.append("%5dm %s  hp %.0f -> %.0f" % [int(event["d"]), ", ".join(names), hp_before, s.hp])
		kills += int(result["kills"])
		units += int(result["units"])
		coins += float(result["coins"]) * coin_mult
		if s.hp <= 0.0:
			return {"survived": false, "distance": float(event["d"]), "hp_frac": 0.0, "kills": kills, "units": units, "coins": coins, "choices": choices, "stats": s}
		i = j
	return {"survived": true, "distance": float(plan.get("length", 0.0)), "hp_frac": s.hp / maxf(s.max_hp, 1.0), "kills": kills, "units": units, "coins": coins, "choices": choices, "stats": s}


## HP-weighted element mix of enemy events after index `from`, within `horizon` meters.
## Element-locked targets are keyed "ward:<element>" (see CombatMath.mix_multiplier).
static func mix_from_events(events: Array, from: int, from_d: float, horizon: float, db: Dictionary) -> Dictionary:
	var mix := {}
	for k in range(from, events.size()):
		var event: Dictionary = events[k]
		if float(event["d"]) > from_d + horizon:
			break
		if String(event.get("type", "")) != "enemies":
			continue
		var def: Dictionary = db["enemies"].get(String(event.get("enemy", "grunt")), {})
		var element := String(event.get("element", "none"))
		var key := ("ward:" + element) if bool(def.get("immune_unless_weak", false)) else element
		var weight := float(def.get("hp", 10)) * float(event.get("hp_mult", 1.0)) * Formations.offsets(event).size()
		mix[key] = float(mix.get(key, 0.0)) + weight
	if mix.is_empty():
		mix["none"] = 1.0
	return mix


static func _choose(gates: Array, s: HeroStats, policy: String, mix: Dictionary, db: Dictionary, limits: Dictionary, rng: RandomNumberGenerator) -> int:
	if policy == "random":
		return rng.randi_range(0, gates.size() - 1) if rng else 0
	var best := 0
	var best_score := -INF if policy != "worst" else INF
	for k in gates.size():
		var score := CombatMath.gate_score(gates[k], s, mix, db["elements"], db["allies"], limits)
		if (policy == "worst" and score < best_score) or (policy != "worst" and score > best_score):
			best_score = score
			best = k
	return best


static func _engage(group: Array, s: HeroStats, policy: String, db: Dictionary, balance: Dictionary) -> Dictionary:
	var limits: Dictionary = balance.get("combat", {})
	var speed := float(balance.get("hero", {}).get("run_speed", 8.0))
	var reach := float(limits.get("projectile_range", 30.0))
	var default_aggro := float(balance.get("enemy", {}).get("aggro_range", 24.0))
	var first_d := float(group[0]["d"])

	# Damage output split: hero (aimed), ranged allies, melee allies (only when enemies close).
	var hero_dps := s.dps() * float(balance.get("estimator", {}).get("hero_aim", 0.7))
	var ranged_dps := 0.0
	var melee_dps := 0.0
	var front_allies := 0
	for id: String in s.allies:
		var def: Dictionary = db["allies"].get(id, {})
		var dps := int(s.allies[id]) * float(def.get("damage", 0)) * float(def.get("attack_rate", 0)) * s.ally_power
		if String(def.get("kind", "melee")) == "ranged":
			ranged_dps += dps * 0.8
		else:
			melee_dps += dps * 0.5
			front_allies += int(s.allies[id])

	var time_used := 0.0
	var kills := 0
	var units := 0
	var coins := 0.0
	var leak_damage := 0.0
	var shot_damage := 0.0
	var dodge := float(balance.get("estimator", {}).get("leak_hit_rate", 1.0))
	for event: Dictionary in group:
		var def: Dictionary = db["enemies"].get(String(event.get("enemy", "grunt")), {})
		var behavior := String(def.get("behavior", "walker"))
		var n := Formations.offsets(event).size()
		units += n
		var unit_hp := float(def.get("hp", 10)) * float(event.get("hp_mult", 1.0))
		var dmg_mult := float(event.get("dmg_mult", 1.0))
		var immune := bool(def.get("immune_unless_weak", false))
		var mult := CombatMath.element_multiplier(s.element, String(event.get("element", "none")), db["elements"], limits, immune)

		# Engagement window for this event (later events in the group arrive later).
		var e_speed := float(def.get("speed", 0.0))
		var aggro := minf(float(def.get("aggro_range", default_aggro)), reach)
		var closing := speed
		var window := reach / speed
		if behavior in ["walker", "charger", "weaver"] and e_speed > 0.0:
			closing = speed + e_speed
			window = (reach - aggro) / speed + aggro / closing
		# Time until this event's units arrive, counted from when the group first came in range:
		# later events and deeper formation rows arrive later. Shared across the group.
		var depth := 0.0
		for offset in Formations.offsets(event):
			depth = maxf(depth, offset.y)
		var arrival := window + (float(event["d"]) - first_d) / speed + depth * 0.5 / closing
		var budget := maxf(0.0, arrival - time_used)

		# Walls: only the piece in the hero's lane matters when it spans the track.
		var blocking := immune and n >= 5
		var targets := 1 if blocking else n
		if behavior == "static" and not blocking:
			targets = 0 # gaps can be steered around
		var hit := s.damage * mult
		var waste := 1.0
		if hit > 0.0:
			waste = unit_hp / (ceilf(unit_hp / hit) * hit)
		var dps := (hero_dps + ranged_dps + melee_dps) * mult * waste
		var needed := INF if dps <= 0.0 else targets * unit_hp / dps
		var killed_frac := 1.0 if needed <= budget else (budget / needed if needed < INF else 0.0)
		time_used += minf(needed, budget)
		var killed := int(floor(targets * killed_frac))
		var leaked := targets - killed
		if behavior == "static" and not blocking:
			killed = 0
		kills += killed
		coins += killed * float(def.get("coins", 1))

		if behavior == "ranged":
			var alive_time := minf(window, needed if needed < INF else window)
			var shots := n * alive_time * 0.5 / maxf(float(def.get("shot_interval", 2.4)), 0.1)
			shot_damage += shots * float(def.get("shot_damage", 8)) * dmg_mult * (0.35 if policy == "best" else 0.6)
			leaked = 0 # archers stand still; the hero steers past
		leak_damage += leaked * float(def.get("contact_damage", 10)) * dmg_mult

	# Front-line allies soak part of the leak and die doing it.
	var soak_share := minf(0.75, front_allies * 0.18)
	var soaked := leak_damage * soak_share
	_damage_allies(s, soaked, db)
	s.hp -= (leak_damage - soaked) * dodge + shot_damage
	return {"kills": kills, "units": units, "coins": coins}


static func _damage_allies(s: HeroStats, amount: float, db: Dictionary) -> void:
	var ids: Array = s.allies.keys()
	ids.sort()
	for id: String in ids:
		if amount <= 0.0:
			return
		var def: Dictionary = db["allies"].get(id, {})
		if String(def.get("kind", "melee")) == "ranged":
			continue
		var unit_hp := float(def.get("hp", 20)) * s.ally_power
		var lost := mini(int(s.allies[id]), int(floor(amount / maxf(unit_hp, 1.0))))
		amount -= lost * unit_hp
		for k in lost:
			s.remove_ally(id)
