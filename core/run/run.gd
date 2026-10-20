extends Node3D
## One run through a LevelPlan. Owns the world, the pools, and the per-frame update order:
## input -> hero -> spawning -> firing -> allies -> enemies -> projectiles -> gates -> cleanup -> fx.
## Every point of damage to an enemy goes through _damage_enemy() so element rules apply uniformly.

enum State { RUNNING, DEAD, WON }

const SPAWN_AHEAD := 70.0

var plan: Dictionary
var state := State.RUNNING
var hero: Hero
var squad: Squad
var camera: CameraRig
var projectiles: ProjectileSystem
var enemy_shots: EnemyShots
var numbers: DamageNumbers
var bursts: BurstPool
var hud: Hud
var enemies: Array[Enemy] = []
var gate_sets: Array[GateSet] = []
var coins := 0
var kills := 0

var _enemy_pool: NodePool
var _events: Array = []
var _next_event := 0
var _length := 400.0
var _track_width := 8.0
var _combat: Dictionary
var _max_enemies := 70
var _despawn_behind := 4.0
var _number_interval := 0.15
var _hurt_fx_cooldown := 0.0
var _drag_index := -1
var _elapsed := 0.0
## Damage taken by source (enemy id or "shot"); printed with the run summary for tuning.
var _damage_log: Dictionary = {}


func _ready() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	plan = LevelGenerator.get_plan(GameState.level, GameState.seed_override)
	_events = plan["events"]
	_length = float(plan["length"])
	_track_width = Balance.f("track.width")
	_combat = Balance.section("combat")
	_max_enemies = Balance.i("enemy.max_alive")
	_despawn_behind = Balance.f("enemy.despawn_behind")
	_number_interval = Balance.f("feel.damage_number_interval")

	_build_environment()
	TrackBuilder.build(self, _length, _track_width * 0.5, int(plan.get("seed", 1)))

	hero = Hero.new()
	hero.name = "Hero"
	add_child(hero)
	hero.setup(Content.hero_class(GameState.hero_class))
	if GameState.assume_upgrades:
		LevelBuilder.apply_level_scaling(hero.stats, float(plan.get("hero_power", 1.0)), float(plan.get("hero_hp_power", 1.0)))
	hero.stats.ally_power = float(plan.get("ally_power", 1.0))
	hero.refresh_hp()
	hero.died.connect(_on_hero_died)

	squad = Squad.new()
	squad.name = "Squad"
	add_child(squad)
	squad.setup()
	squad.melee_hit.connect(_on_ally_melee)
	squad.ranged_shot.connect(_on_ally_shot)

	camera = CameraRig.new()
	add_child(camera)
	camera.setup()

	projectiles = ProjectileSystem.new()
	add_child(projectiles)
	projectiles.setup()
	projectiles.hit.connect(_on_projectile_hit)

	enemy_shots = EnemyShots.new()
	add_child(enemy_shots)
	enemy_shots.setup()
	enemy_shots.hit_hero.connect(_on_enemy_shot_hero)
	enemy_shots.hit_ally.connect(_on_enemy_shot_ally)

	numbers = DamageNumbers.new()
	add_child(numbers)
	numbers.setup()

	bursts = BurstPool.new()
	add_child(bursts)
	bursts.setup()

	var enemy_root := Node3D.new()
	enemy_root.name = "Enemies"
	add_child(enemy_root)
	_enemy_pool = NodePool.new(enemy_root, func() -> Enemy: return Enemy.new(), 40)

	hud = Hud.new()
	add_child(hud)
	hud.restart_requested.connect(_restart)
	hud.next_requested.connect(_next_level)
	hud.set_level_title(_level_title())
	hero.hp_changed.connect(hud.set_hp)
	hud.set_hp(hero.stats.hp, hero.stats.max_hp)
	hud.set_stats(hero.stats)
	hud.set_coins(0)
	_sync_build(false)
	if GameState.debug_overlay:
		_build_debug_overlay()
	if GameState.is_dev_build():
		var debug_menu := DebugMenu.new()
		add_child(debug_menu)
		debug_menu.setup(plan)


func _exit_tree() -> void:
	Engine.time_scale = 1.0


func _input(event: InputEvent) -> void:
	if state != State.RUNNING or get_tree().paused:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _drag_index == -1:
			_drag_index = touch.index
		elif not touch.pressed and touch.index == _drag_index:
			_drag_index = -1
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index != _drag_index and _drag_index != -1:
			return
		var screen_width := get_viewport().get_visible_rect().size.x
		hero.steer_by(drag.relative.x / screen_width * _track_width * Balance.f("hero.steer_sensitivity"))
		hud.hide_hint()


func _process(delta: float) -> void:
	_elapsed += delta
	_hurt_fx_cooldown -= delta
	if GameState.autopilot and state == State.RUNNING:
		_autopilot()

	hero.update_motion(delta)
	var distance := -hero.position.z
	_spawn_events(distance)

	if state == State.RUNNING and hero.alive:
		for shot in hero.shots_due(delta):
			_fire()

	squad.tick(delta, hero.position, enemies)
	_tick_enemies(delta)
	projectiles.tick(delta, enemies)
	enemy_shots.tick(delta, hero, squad.allies)
	_check_gates()
	_sweep_enemies()
	if squad.sweep():
		hud.set_allies(hero.stats.ally_count(), int(_combat.get("max_allies", 12)))

	numbers.tick(delta)
	camera.follow(hero.position, delta)
	hud.set_progress(distance / _length)

	if state == State.RUNNING and distance >= _length:
		_win()


# --- Spawning ---------------------------------------------------------------------------------

func _spawn_events(distance: float) -> void:
	while _next_event < _events.size() and float(_events[_next_event]["d"]) <= distance + SPAWN_AHEAD:
		var event: Dictionary = _events[_next_event]
		_next_event += 1
		match String(event.get("type", "")):
			"enemies":
				_spawn_enemies(event)
			"gates":
				_spawn_gates(event)


func _spawn_enemies(event: Dictionary) -> void:
	var id := String(event.get("enemy", "grunt"))
	var def := Content.enemy(id)
	var center_x := float(event.get("x", 0.0))
	var hp_mult := float(event.get("hp_mult", 1.0))
	var element := String(event.get("element", "none"))
	var half := _track_width * 0.5 - 0.45
	for offset in Formations.offsets(event):
		if enemies.size() >= _max_enemies:
			break
		var e := _enemy_pool.acquire() as Enemy
		var x := clampf(center_x + offset.x, -half, half)
		e.spawn(id, def, hp_mult, Vector3(x, 0, -(float(event["d"]) + offset.y)), element, float(event.get("dmg_mult", 1.0)))
		enemies.append(e)


func _spawn_gates(event: Dictionary) -> void:
	var gate_set := GateSet.new()
	add_child(gate_set)
	gate_set.position = Vector3(0, 0, -float(event["d"]))
	gate_set.setup(event.get("gates", []), _track_width)
	gate_sets.append(gate_set)


# --- Hero and ally attacks --------------------------------------------------------------------

func _fire() -> void:
	var stats := hero.stats
	var origin := hero.muzzle_position()
	var aim := _aim_direction(origin)
	var count := stats.projectiles
	var spacing := float(_combat.get("projectile_spacing", 0.3))
	var fan := deg_to_rad(float(_combat.get("projectile_fan_degrees", 3.5)))
	var color := Content.element_color(stats.element)
	for k in count:
		var offset := k - (count - 1) * 0.5
		var dir := aim.rotated(Vector3.UP, -offset * fan)
		var right := Vector3(-dir.z, 0, dir.x)
		projectiles.spawn(origin + right * (offset * spacing), dir, stats.damage, stats.element, color)
	hero.on_fired()
	AudioManager.play("shoot", -16.0, 0.08, 0.06)


## Straight ahead, nudged toward the best-aligned enemy inside a narrow cone.
func _aim_direction(origin: Vector3) -> Vector3:
	var cone := deg_to_rad(float(_combat.get("aim_assist_degrees", 12.0)))
	var reach := float(_combat.get("projectile_range", 30.0))
	var best_angle := cone
	var best := Vector3.FORWARD
	for e in enemies:
		if not e.active:
			continue
		var to := Vector3(e.position.x - origin.x, 0, e.position.z - origin.z)
		if to.z >= -0.5 or -to.z > reach:
			continue
		var angle := absf(atan2(to.x, -to.z))
		if angle < best_angle:
			best_angle = angle
			best = to.normalized()
	return best


func _on_ally_melee(ally: Ally, enemy: Enemy) -> void:
	_damage_enemy(enemy, ally.damage, hero.stats.element, enemy.position + Vector3(0, enemy.hit_height, 0))
	AudioManager.play("hit", -10.0, 0.2, 0.05)


func _on_ally_shot(ally: Ally, origin: Vector3) -> void:
	var element := hero.stats.element
	projectiles.spawn(origin, _aim_direction(origin), ally.damage, element, Content.element_color(element).lightened(0.25), ally.attack_range)


func _on_projectile_hit(e: Enemy, damage: float, at: Vector3, element: String) -> void:
	_damage_enemy(e, damage, element, at)
	AudioManager.play("hit", -12.0, 0.15, 0.04)


# --- Damage resolution ------------------------------------------------------------------------

## The single damage path for enemies: element multiplier, immunity, on-hit effects, numbers, kills.
func _damage_enemy(e: Enemy, base: float, element: String, at: Vector3, with_effects := true) -> void:
	if not e.active:
		return
	var mult := CombatMath.element_multiplier(element, e.element, Content.elements, _combat, e.immune_unless_weak)
	if mult <= 0.0:
		if e.number_cooldown <= 0.0:
			e.number_cooldown = _number_interval * 3.0
			numbers.pop(at + Vector3(0, 0.6, 0), "IMMUNE", Color(0.75, 0.75, 0.8), 0.9)
			AudioManager.play("immune", -8.0, 0.1, 0.08)
		return
	var amount := base * mult
	var killed := e.take_damage(amount)
	_show_damage(e, amount, mult, at, killed)
	if with_effects:
		_apply_element_effect(e, amount, element, killed)
	if killed:
		_on_enemy_killed(e)


func _show_damage(e: Enemy, amount: float, mult: float, at: Vector3, killed: bool) -> void:
	e.pending_damage += amount
	if not killed and e.number_cooldown > 0.0:
		return
	e.number_cooldown = _number_interval
	var text := GateInfo.num(roundf(e.pending_damage))
	var color := Color("#FFF4C2")
	var size := 1.2
	if mult > 1.01:
		text += "!"
		color = Color("#FFB23E")
		size = 1.55
	elif mult < 0.99:
		color = Color(0.7, 0.72, 0.78)
		size = 0.95
	numbers.pop(at + Vector3(0, 0.5, 0), text, color, size)
	e.pending_damage = 0.0


func _apply_element_effect(e: Enemy, amount: float, element: String, killed: bool) -> void:
	var effect: Dictionary = Content.elements.get(element, {}).get("effect", {}) if Content.elements.has(element) else {}
	match String(effect.get("type", "")):
		"burn":
			if not killed:
				e.apply_burn(amount * float(effect.get("fraction", 0.3)), float(effect.get("duration", 1.5)))
		"slow":
			if not killed:
				e.apply_slow(float(effect.get("amount", 0.4)), float(effect.get("duration", 1.0)))
		"chain":
			var radius := float(effect.get("radius", 3.0))
			var targets := int(effect.get("targets", 1))
			for other in _nearest_enemies(e.position, radius, targets, e):
				bursts.burst(other.position + Vector3(0, other.hit_height, 0), Content.element_color(element))
				_damage_enemy(other, amount * float(effect.get("fraction", 0.5)), element, other.position + Vector3(0, other.hit_height, 0), false)


func _nearest_enemies(from: Vector3, radius: float, count: int, exclude: Enemy) -> Array[Enemy]:
	var found: Array[Enemy] = []
	var r2 := radius * radius
	for e in enemies:
		if e.active and e != exclude and from.distance_squared_to(e.position) < r2:
			found.append(e)
	found.sort_custom(func(a: Enemy, b: Enemy) -> bool: return from.distance_squared_to(a.position) < from.distance_squared_to(b.position))
	return found.slice(0, count)


func _on_enemy_killed(e: Enemy) -> void:
	kills += 1
	coins += int(roundf(e.coins * Balance.f("economy.coin_multiplier", 1.0) * float(plan.get("coin_mult", 1.0))))
	hud.set_coins(coins)
	var burst_color := Content.element_color(e.element) if e.element != "none" else e.color
	bursts.burst(e.position + Vector3(0, 0.7, 0), burst_color)
	camera.add_trauma(Balance.f("feel.shake_kill"))
	AudioManager.play("kill", -6.0, 0.15, 0.03)


# --- Enemies ----------------------------------------------------------------------------------

func _tick_enemies(delta: float) -> void:
	var hero_pos := hero.position
	for e in enemies:
		if not e.active:
			continue
		if e.tick(delta, hero_pos):
			_on_enemy_killed(e)
			continue
		if e.wants_shot(delta, hero_pos) and state == State.RUNNING:
			var shot_color := Content.element_color(e.element) if e.element != "none" else Color("#FF5A3B")
			enemy_shots.spawn(e.position + Vector3(0, 1.0, 0.4), hero_pos, float(e.def.get("shot_speed", 11.0)),
				float(e.def.get("shot_damage", 8)) * e.dmg_mult, shot_color, float(e.def.get("shot_range", 24.0)))
			AudioManager.play("enemy_shot", -10.0, 0.1, 0.1)
		var dz := e.position.z - hero_pos.z
		if dz > _despawn_behind:
			e.active = false
			continue
		if _collide_allies(e):
			continue
		var reach := e.radius + hero.radius
		if hero.alive and absf(dz) < reach and absf(e.position.x - hero_pos.x) < reach:
			_enemy_reached_hero(e)


## Enemies that bump into an ally trade blows: the ally takes contact damage, the enemy takes the
## ally's contact damage (element rules apply) and is knocked back if it survives.
func _collide_allies(e: Enemy) -> bool:
	for a in squad.allies:
		if not a.active:
			continue
		var reach := e.radius + a.radius
		if absf(e.position.z - a.position.z) < reach and absf(e.position.x - a.position.x) < reach:
			if a.take_damage(e.contact_damage):
				_on_ally_died(a)
			_damage_enemy(e, a.contact_damage, hero.stats.element, e.position + Vector3(0, e.hit_height, 0))
			if e.active:
				e.knock_back(Balance.f("enemy.knockback"))
			return true
	return false


## Crowd-runner rule: an enemy that reaches the hero deals its damage and is destroyed.
func _enemy_reached_hero(e: Enemy) -> void:
	e.active = false
	e.visible = false
	bursts.burst(e.position + Vector3(0, 0.7, 0), e.color)
	_damage_log[e.enemy_id] = float(_damage_log.get(e.enemy_id, 0.0)) + e.contact_damage
	_hurt_hero(e.contact_damage)


func _hurt_hero(amount: float) -> void:
	hero.take_hit(amount)
	numbers.pop(hero.position + Vector3(0, 2.2, 0), "-" + GateInfo.num(roundf(amount)), Color("#FF5A5A"), 1.2)
	if _hurt_fx_cooldown <= 0.0:
		_hurt_fx_cooldown = Balance.f("hero.hurt_fx_cooldown")
		camera.add_trauma(Balance.f("feel.shake_hero_hit"))
		AudioManager.play("hurt", -2.0, 0.1)
		GameState.vibrate(Balance.i("feel.vibrate_ms_hit"))
		if hero.alive:
			_hit_stop(Balance.f("feel.hit_stop_hero_hit"))


func _on_enemy_shot_hero(damage: float, at: Vector3) -> void:
	bursts.burst(at, Color("#FF5A3B"))
	_damage_log["shot"] = float(_damage_log.get("shot", 0.0)) + damage
	_hurt_hero(damage)


func _on_enemy_shot_ally(ally: Ally, damage: float) -> void:
	if ally.take_damage(damage):
		_on_ally_died(ally)


func _on_ally_died(ally: Ally) -> void:
	hero.stats.remove_ally(ally.ally_id)
	bursts.burst(ally.position + Vector3(0, 0.8, 0), Color("#E8E2D0"))
	AudioManager.play("ally_die", -6.0, 0.15, 0.05)


func _sweep_enemies() -> void:
	for k in range(enemies.size() - 1, -1, -1):
		var e := enemies[k]
		if not e.active:
			enemies.remove_at(k)
			_enemy_pool.release(e)


# --- Gates ------------------------------------------------------------------------------------

func _check_gates() -> void:
	if not hero.alive:
		return
	for k in range(gate_sets.size() - 1, -1, -1):
		var gate_set := gate_sets[k]
		if hero.position.z > gate_set.position.z:
			continue
		var lane := gate_set.lane_at(hero.position.x)
		var gate: Dictionary = gate_set.gates[lane]
		var old_element := hero.stats.element
		hero.stats.apply_gate(gate, _combat)
		gate_set.trigger(lane)
		gate_sets.remove_at(k)
		_on_gate_taken(gate, old_element)


func _on_gate_taken(gate: Dictionary, old_element: String) -> void:
	if GameState.autopilot:
		print("[gate] %.0fm took %s | hp %.0f kills %d" % [-hero.position.z, GateInfo.short_text(gate), hero.stats.hp, kills])
	var tint := GateInfo.color(gate)
	var category := GateInfo.category(gate)
	match category:
		"element":
			AudioManager.play("element", -2.0, 0.0)
		"summon":
			AudioManager.play("summon", -2.0, 0.0)
		"curse":
			AudioManager.play("curse", 0.0, 0.0)
			camera.add_trauma(0.35)
		"bad":
			AudioManager.play("gate_bad", -3.0, 0.0)
		_:
			AudioManager.play("gate_good", -3.0, 0.0)
	numbers.pop(hero.position + Vector3(0, 3.0, -1.0), GateInfo.short_text(gate), tint.lightened(0.35), 1.6, 1.2)
	hud.flash(tint, 0.3 if category == "curse" else 0.22)
	camera.add_trauma(Balance.f("feel.shake_gate"))
	bursts.burst(hero.position + Vector3(0, 1.4, -0.5), tint)
	var changed := String(gate.get("stat", ""))
	hud.set_stats(hero.stats, changed, GateInfo.is_good(gate))
	_sync_build(hero.stats.element != old_element)
	hero.refresh_hp()


## Pushes HeroStats to visuals: element tints, ally squad, HUD badges.
func _sync_build(element_changed: bool) -> void:
	var stats := hero.stats
	if element_changed:
		hero.set_element(stats.element)
		squad.set_element_tint(Content.element_color(stats.element))
	squad.reconcile(stats, hero.position)
	hud.set_element(stats.element)
	hud.set_allies(stats.ally_count(), int(_combat.get("max_allies", 12)))


# --- Run end ----------------------------------------------------------------------------------

func _on_hero_died() -> void:
	state = State.DEAD
	hero.visible = false
	enemy_shots.clear()
	for i in 3:
		bursts.burst(hero.position + Vector3(randf_range(-0.4, 0.4), 0.6 + i * 0.4, 0), Color("#FF5A5A") if i != 1 else Color("#3F6FD8"))
	camera.add_trauma(1.0)
	AudioManager.play("lose", 0.0, 0.0)
	_log_result("DIED")
	Engine.time_scale = Balance.f("feel.death_slowmo_scale")
	await get_tree().create_timer(Balance.f("feel.death_slowmo_time"), true, false, true).timeout
	Engine.time_scale = 1.0
	hud.show_result(false, _summary(), false)


func _win() -> void:
	state = State.WON
	enemy_shots.clear()
	AudioManager.play("win", 0.0, 0.0)
	for i in 4:
		bursts.burst(hero.position + Vector3(randf_range(-3, 3), 2.0, -2.0), [Color("#FFD166"), Color("#3FA9FF"), Color("#FF6B6B"), Color("#7CF29A")][i])
	hud.show_result(true, _summary(), int(plan.get("level", 0)) > 0)
	_log_result("WON")


func _summary() -> String:
	var s := hero.stats
	return "Distance  %dm\nKills  %d     Coins  %d\n\nDMG %s  |  RATE %s/s  |  SHOTS %d\n%s  |  ALLIES %d" % [
		mini(int(-hero.position.z), int(_length)), kills, coins,
		GateInfo.num(snappedf(s.damage, 0.1)), GateInfo.num(snappedf(s.fire_rate, 0.1)), s.projectiles,
		Content.element_name(s.element), s.ally_count(),
	]


func _log_result(outcome: String) -> void:
	var s := hero.stats
	print("[run] %s at %.0fm after %.1fs | hp %.0f | kills %d | coins %d | dmg %.1f rate %.1f shots %d | %s | allies %s" % [
		outcome, -hero.position.z, _elapsed, s.hp, kills, coins, s.damage, s.fire_rate, s.projectiles, s.element, s.allies,
	])
	print("[run] damage taken by source: %s" % _damage_log)


func _next_level() -> void:
	GameState.level = int(plan.get("level", 0)) + 1
	GameState.seed_override = -1
	_restart()


func _level_title() -> String:
	var level := int(plan.get("level", 0))
	if level <= 0:
		return "TEST LEVEL"
	var title := "LEVEL %d" % level
	match String(plan.get("kind", "")):
		"spike":
			title += "  ·  HARD"
		"reward":
			title += "  ·  BONUS"
		"boss":
			title += "  ·  BOSS"
	if GameState.seed_override >= 0:
		title += "  ·  SEED %d" % GameState.seed_override
	return title


## Dev overlay: segment boundaries, roles and ids drawn beside the track.
func _build_debug_overlay() -> void:
	var dbg: Dictionary = plan.get("debug", {})
	var line_mat := Placeholders.overlay(Color(1, 0.2, 0.9, 0.55))
	for seg: Dictionary in dbg.get("segments", []):
		var z := -float(seg["start"])
		add_child(Placeholders.part(Placeholders.box(Vector3(_track_width + 3.0, 0.05, 0.12)), line_mat, Vector3(0, 0.06, z)))
		var label := Label3D.new()
		label.text = "%s\n%s" % [String(seg["role"]).to_upper(), seg["id"]]
		label.font_size = 64
		label.pixel_size = 0.012
		label.modulate = Color(1, 0.6, 1)
		label.outline_size = 12
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3(-_track_width * 0.5 - 2.6, 1.2, z - 2.0)
		add_child(label)
	for event: Dictionary in plan.get("events", []):
		if event.has("repaired"):
			var tag := Label3D.new()
			tag.text = "FIX: %s" % event["repaired"]
			tag.font_size = 56
			tag.pixel_size = 0.01
			tag.modulate = Color(1, 0.85, 0.2)
			tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			tag.position = Vector3(_track_width * 0.5 + 2.4, 1.5, -float(event["d"]))
			add_child(tag)


func _restart() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_tree().reload_current_scene()


func _hit_stop(duration: float) -> void:
	if duration <= 0.0 or Engine.time_scale < 1.0:
		return
	Engine.time_scale = 0.05
	await get_tree().create_timer(duration, true, false, true).timeout
	if state != State.DEAD:
		Engine.time_scale = 1.0


# --- World ------------------------------------------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#9DCBEA")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#C4D3EA")
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color("#A9CFEA")
	env.fog_density = 0.008
	env.fog_sky_affect = 0.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 1.15
	sun.light_color = Color("#FFF2DC")
	sun.shadow_enabled = false
	add_child(sun)


# --- Dev autopilot ----------------------------------------------------------------------------

## Expected enemy element mix over the next stretch, weighted by HP. Wards count as "ward:<el>".
func upcoming_mix(horizon: float) -> Dictionary:
	var mix := {}
	var here := -hero.position.z
	for e in enemies:
		if e.active and e.position.z < hero.position.z:
			var key := ("ward:" + e.element) if e.immune_unless_weak else e.element
			mix[key] = float(mix.get(key, 0.0)) + e.hp
	for k in range(_next_event, _events.size()):
		var event: Dictionary = _events[k]
		if float(event["d"]) > here + horizon:
			break
		if String(event.get("type", "")) != "enemies":
			continue
		var def := Content.enemy(String(event.get("enemy", "grunt")))
		var element := String(event.get("element", "none"))
		var key := ("ward:" + element) if bool(def.get("immune_unless_weak", false)) else element
		var weight := float(def.get("hp", 10)) * float(event.get("hp_mult", 1.0)) * Formations.offsets(event).size()
		mix[key] = float(mix.get(key, 0.0)) + weight
	if mix.is_empty():
		mix["none"] = 1.0
	return mix


## Dev-only bot: heads for the best-scoring gate lane, dodges enemy shots crudely by lining up
## with the nearest enemy otherwise.
func _autopilot() -> void:
	var nearest_gate: GateSet = null
	for gate_set in gate_sets:
		if hero.position.z - gate_set.position.z < 40.0 and (nearest_gate == null or gate_set.position.z > nearest_gate.position.z):
			nearest_gate = gate_set
	if nearest_gate:
		var mix := upcoming_mix(120.0)
		var best_lane := 0
		var best_score := -INF
		for lane in nearest_gate.gates.size():
			var gate_score := CombatMath.gate_score(nearest_gate.gates[lane], hero.stats, mix, Content.elements, Content.allies, _combat)
			if gate_score > best_score:
				best_score = gate_score
				best_lane = lane
		hero.target_x = nearest_gate.lane_center(best_lane)
		return
	var nearest: Enemy = null
	for e in enemies:
		if e.active and e.behavior != "ranged" and e.position.z < hero.position.z and (nearest == null or e.position.z > nearest.position.z):
			nearest = e
	if nearest:
		hero.target_x = clampf(nearest.position.x, -3.4, 3.4)
