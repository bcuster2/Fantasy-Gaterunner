extends Node3D
## One run through a LevelPlan. Owns the world, the pools, and the per-frame update order:
## input -> hero -> spawning -> firing -> allies -> enemies -> projectiles -> gates -> cleanup -> fx.
## Every point of damage to an enemy goes through _damage_enemy() so element rules apply uniformly.
## Levels with a boss end in an arena: the hero stops at the arena line, the boss fights from its dais,
## and the run is won when the boss falls.
## Modes (GameState.mode): "campaign" (numbered level), "daily" (date-seeded, fixed modifiers, expected
## hero), "endless" (EndlessDirector feeds generated chunks forever; bosses don't end the run).

enum State { RUNNING, DEAD, WON }

## Emitted once when the run ends: { won, level, distance, hp, hp_frac, kills, units, coins, time }.
signal finished(result: Dictionary)

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
var sparks: Sparks
var shockwaves: Shockwaves
var bolts: Bolts
var coin_shower: CoinShower
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
var boss: Boss = null
var arena: BossArena = null
var _boss_event: Dictionary = {}
var _in_arena := false
var _zone: Dictionary = {}
var _boss_cfg: Dictionary = {}
var _boss_hit_stop_cd := 0.0
var _summon_hp_mult := 1.0
var _summon_dmg_mult := 1.0
var _arena_time := 0.0
## Shop coin bonus (upgrades + perks) applied to the payout at the end.
var _coin_bonus := 1.0
var _ended := false
## First-run tutorial (level 1 until completed once).
var _tutorial := false
var _tutorial_step := 0
## The next tutorial tip waits until this time so tips never cover each other.
var _tutorial_hold := 0.0
var _tutorial_gate_z := 0.0
# Endless mode.
var _endless: EndlessDirector = null
var _chunks: Array[Dictionary] = []
var _active_chunk := -1
var _bosses_defeated := 0
var _title_timer := 0.0
var _daily_date := ""
var _env: Environment
var _coin_combo := 0
var _coin_combo_timer := 0.0
var _dust_timer := 0.0
var _sun: DirectionalLight3D


func _ready() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	match GameState.mode:
		"endless":
			var cfg := Balance.section("endless")
			_endless = EndlessDirector.new(randi(), EndlessDirector.start_tier_for(SaveManager.unlocked_level(), cfg), cfg)
			plan = _endless.next_chunk(Content.db, Balance.data)
		"daily":
			_daily_date = LevelGenerator.today_utc()
			plan = LevelGenerator.get_daily_plan(_daily_date)
			if not GameState.autopilot:
				SaveManager.start_daily_attempt(_daily_date)
		_:
			plan = LevelGenerator.get_plan(GameState.level, GameState.seed_override)
	_events = plan["events"]
	_length = float(plan["length"])
	_track_width = Balance.f("track.width")
	_combat = Balance.section("combat")
	_max_enemies = Balance.i("enemy.max_alive")
	_despawn_behind = Balance.f("enemy.despawn_behind")
	_number_interval = Balance.f("feel.damage_number_interval")

	_boss_cfg = Balance.section("boss")
	_zone = ZoneTheme.resolve(Content.zones, String(plan.get("zone", "forest")), int(plan.get("zone_cycle", 0)))
	for event: Dictionary in _events:
		match String(event.get("type", "")):
			"boss":
				_boss_event = event
			"enemies":
				_summon_hp_mult = float(event.get("hp_mult", 1.0))
				_summon_dmg_mult = float(event.get("dmg_mult", 1.0))
	_build_environment()
	if _endless:
		_boss_event = {} # endless bosses are picked up as their chunks spawn
		_add_chunk_world(plan)
	else:
		var arena_d := float(_boss_event["d"]) if not _boss_event.is_empty() else -1.0
		TrackBuilder.build(self, _length + (40.0 if arena_d >= 0.0 else 0.0), _track_width * 0.5, int(plan.get("seed", 1)), _zone, arena_d)

	hero = Hero.new()
	hero.name = "Hero"
	add_child(hero)
	var class_def := Content.hero_class(GameState.hero_class).duplicate()
	var skin: Dictionary = Content.skins.get(String(SaveManager.data.get("selected_skin", "default")), {})
	if skin.has("robe"):
		class_def["color"] = skin["robe"]
	hero.setup(class_def)
	var perk_defs: Dictionary = Content.milestones.get("perks", {})
	_coin_bonus = Economy.coin_multiplier(Content.upgrades, SaveManager.upgrade_levels(), perk_defs, SaveManager.perks())
	if GameState.assume_upgrades or GameState.mode == "daily":
		# The daily challenge is the same for everyone: the generator's expected hero, not the shop.
		LevelBuilder.apply_level_scaling(hero.stats, float(plan.get("hero_power", 1.0)), float(plan.get("hero_hp_power", 1.0)))
	else:
		# Real progression: shop upgrades and milestone perks.
		_combat = Economy.apply_to_hero(hero.stats, _combat, Content.upgrades, SaveManager.upgrade_levels(), perk_defs, SaveManager.perks())
	hero.stats.ally_power = float(plan.get("ally_power", 1.0))
	hero.refresh_hp()
	hero.died.connect(_on_hero_died)

	squad = Squad.new()
	squad.name = "Squad"
	add_child(squad)
	squad.setup()
	squad.melee_hit.connect(_on_ally_melee)
	squad.ranged_shot.connect(_on_ally_shot)
	squad.melee_boss.connect(_on_ally_melee_boss)

	camera = CameraRig.new()
	add_child(camera)
	camera.setup()

	projectiles = ProjectileSystem.new()
	add_child(projectiles)
	projectiles.setup()
	projectiles.hit.connect(_on_projectile_hit)
	projectiles.boss_hit.connect(_on_projectile_boss_hit)

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
	sparks = Sparks.new()
	add_child(sparks)
	sparks.setup()
	shockwaves = Shockwaves.new()
	add_child(shockwaves)
	shockwaves.setup()
	bolts = Bolts.new()
	add_child(bolts)
	bolts.setup()
	coin_shower = CoinShower.new()
	add_child(coin_shower)
	coin_shower.setup()
	coin_shower.collected.connect(_on_coin_collected)

	var enemy_root := Node3D.new()
	enemy_root.name = "Enemies"
	add_child(enemy_root)
	_enemy_pool = NodePool.new(enemy_root, func() -> Enemy: return Enemy.new(), 40)

	hud = Hud.new()
	add_child(hud)
	hud.restart_requested.connect(_restart)
	hud.next_requested.connect(_next_level)
	hud.menu_requested.connect(func() -> void: GameState.go(_menu_screen()))
	hud.set_level_title(_level_title())
	hero.hp_changed.connect(hud.set_hp)
	hud.set_hp(hero.stats.hp, hero.stats.max_hp)
	hud.set_stats(hero.stats)
	hud.set_coins(0)
	_sync_build(false)
	var modifier_names: Array = []
	var modifier_lines: PackedStringArray = []
	for mod: String in plan.get("modifiers", []):
		var def: Dictionary = Content.modifiers.get(mod, {})
		modifier_names.append(String(def.get("name", mod.to_upper())))
		modifier_lines.append("%s: %s" % [def.get("name", mod), def.get("desc", "")])
	hud.set_modifiers(modifier_names)
	if int(plan.get("level", 0)) > 0:
		var subtitle := String(_zone.get("name", ""))
		if _endless:
			subtitle = "Survive as long as you can.\nA boss every few minutes."
		elif GameState.mode == "daily":
			subtitle = "Today's challenge  ·  " + _daily_date
		hud.show_banner(_banner_title(), subtitle + ("\n" + "\n".join(modifier_lines) if not modifier_lines.is_empty() else ""))
	_tutorial = GameState.mode == "campaign" and int(plan.get("level", 0)) == 1 and not bool(SaveManager.data.get("tutorial_done", false)) and not GameState.autopilot
	if GameState.start_distance != 0.0:
		var skip := GameState.start_distance
		if skip < 0.0:
			skip = float(_boss_event.get("d", _length)) - 45.0
		GameState.start_distance = 0.0
		hero.position.z = -skip
		while _next_event < _events.size() and float(_events[_next_event]["d"]) < skip and String(_events[_next_event].get("type", "")) != "boss":
			_next_event += 1
	AudioManager.play_music(String(plan.get("zone", "forest")))
	AudioManager.play("level_start")
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
	if _tutorial:
		_tick_tutorial()
	if GameState.autopilot and state == State.RUNNING:
		_autopilot()

	hero.update_motion(delta)
	var distance := -hero.position.z
	_spawn_events(distance)

	if state == State.RUNNING and hero.alive:
		for shot in hero.shots_due(delta):
			_fire()

	_tick_boss(delta, distance)
	squad.tick(delta, hero.position, enemies, boss)
	_tick_enemies(delta)
	projectiles.tick(delta, enemies, boss)
	enemy_shots.tick(delta, hero, squad.allies)
	_check_gates()
	_sweep_enemies()
	if squad.sweep():
		hud.set_allies(hero.stats.ally_count(), int(_combat.get("max_allies", 12)))

	numbers.tick(delta)
	shockwaves.tick(delta)
	bolts.tick(delta)
	coin_shower.tick(delta, hero.position)
	_tick_feel(delta)
	camera.follow(hero.position, delta)
	if _endless:
		_tick_endless(delta, distance)
	else:
		hud.set_progress(distance / _length)
		if state == State.RUNNING and _boss_event.is_empty() and distance >= _length:
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
			"boss":
				_spawn_boss(event)


func _spawn_enemies(event: Dictionary) -> void:
	var id := String(event.get("enemy", "grunt"))
	var def := Content.enemy(id)
	var center_x := float(event.get("x", 0.0))
	var hp_mult := float(event.get("hp_mult", 1.0))
	var element := String(event.get("element", "none"))
	var elite_def: Dictionary = Content.modifiers.get("elite", {}) if bool(event.get("elite", false)) else {}
	var half := _track_width * 0.5 - 0.45
	for offset in Formations.offsets(event):
		if enemies.size() >= _max_enemies:
			break
		var e := _enemy_pool.acquire() as Enemy
		var x := clampf(center_x + offset.x, -half, half)
		e.spawn(id, def, hp_mult, Vector3(x, 0, -(float(event["d"]) + offset.y)), element, float(event.get("dmg_mult", 1.0)), elite_def)
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
	AudioManager.play("shoot" if stats.element == "none" else "shoot_" + stats.element, 0.0, 0.08)


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
	if best == Vector3.FORWARD and boss and boss.fighting:
		var to_boss := Vector3(boss.position.x - origin.x, 0, boss.position.z - origin.z)
		if to_boss.z < -0.5:
			best = to_boss.normalized()
	return best


func _on_ally_melee(ally: Ally, enemy: Enemy) -> void:
	_damage_enemy(enemy, ally.damage, hero.stats.element, enemy.position + Vector3(0, enemy.hit_height, 0))
	AudioManager.play("hit", 0.0, 0.2, 0.05)


func _on_ally_shot(ally: Ally, origin: Vector3) -> void:
	var element := hero.stats.element
	projectiles.spawn(origin, _aim_direction(origin), ally.damage, element, Content.element_color(element).lightened(0.25), ally.attack_range)


func _on_projectile_hit(e: Enemy, damage: float, at: Vector3, element: String) -> void:
	_damage_enemy(e, damage, element, at)
	sparks.emit(Sparks.style_for(element), at)


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
			AudioManager.play("immune", 0.0, 0.1, 0.08)
		return
	var amount := base * mult
	var killed := e.take_damage(amount)
	_show_damage(e, amount, mult, at, killed)
	AudioManager.play("hit_weak" if mult > 1.01 else "hit", 0.0, 0.15)
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
				bolts.spawn(e.position + Vector3(0, e.hit_height, 0), other.position + Vector3(0, other.hit_height, 0), Content.element_color(element))
				sparks.emit("lightning", other.position + Vector3(0, other.hit_height, 0))
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
	# Coins burst out of the enemy and fly to the hero; they're counted when they arrive.
	var value := int(roundf(e.coins * Balance.f("economy.coin_multiplier", 1.0) * float(plan.get("coin_mult", 1.0))))
	coin_shower.spawn(e.position, value)
	var burst_color := Content.element_color(e.element) if e.element != "none" else e.color
	bursts.burst(e.position + Vector3(0, 0.7, 0), burst_color)
	camera.add_trauma(Balance.f("feel.shake_kill"))
	if e.elite:
		sparks.emit("gold", e.position + Vector3(0, 1.0, 0))
		shockwaves.spawn(e.position, Color("#FFD166"), 2.2, 0.35)
		AudioManager.play("kill_elite")
	else:
		AudioManager.play("kill", 0.0, 0.15)


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
			AudioManager.play("enemy_shot", 0.0, 0.1, 0.1)
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
		AudioManager.play("hurt", 0.0, 0.1)
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
	sparks.emit("bone", ally.position + Vector3(0, 0.8, 0))
	AudioManager.play("ally_die", 0.0, 0.15, 0.05)


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
			AudioManager.play("element", 0.0, 0.0)
		"summon":
			AudioManager.play("summon", 0.0, 0.0)
		"curse":
			AudioManager.play("curse", 0.0, 0.0)
			camera.add_trauma(0.35)
		"bad":
			AudioManager.play("gate_bad", 0.0, 0.0)
		_:
			AudioManager.play("gate_good", 0.0, 0.0)
	numbers.pop(hero.position + Vector3(0, 3.0, -1.0), GateInfo.short_text(gate), tint.lightened(0.35), 1.6, 1.2)
	shockwaves.spawn(hero.position, tint, 4.0, 0.5)
	GameState.vibrate(15)
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
	if arena:
		arena.clear()
	hero.visible = false
	enemy_shots.clear()
	for i in 3:
		bursts.burst(hero.position + Vector3(randf_range(-0.4, 0.4), 0.6 + i * 0.4, 0), Color("#FF5A5A") if i != 1 else Color("#3F6FD8"))
	camera.add_trauma(1.0)
	AudioManager.play("lose", 0.0, 0.0)
	_log_result("DIED")
	finished.emit(_result(false))
	if GameState.fast_results:
		_finish_run(false)
		return
	Engine.time_scale = Balance.f("feel.death_slowmo_scale")
	await get_tree().create_timer(Balance.f("feel.death_slowmo_time"), true, false, true).timeout
	Engine.time_scale = 1.0
	_finish_run(false)


func _win() -> void:
	state = State.WON
	enemy_shots.clear()
	AudioManager.play("win", 0.0, 0.0)
	for i in 4:
		bursts.burst(hero.position + Vector3(randf_range(-3, 3), 2.0, -2.0), [Color("#FFD166"), Color("#3FA9FF"), Color("#FF6B6B"), Color("#7CF29A")][i])
	_finish_run(true)
	_log_result("WON")
	finished.emit(_result(true))


func _result(won: bool) -> Dictionary:
	var units := 0
	for event: Dictionary in _events:
		if String(event.get("type", "")) == "enemies":
			units += Formations.offsets(event).size()
	return {
		"won": won, "level": int(plan.get("level", 0)), "distance": minf(-hero.position.z, _length),
		"hp": hero.stats.hp, "hp_frac": hero.stats.hp / maxf(hero.stats.max_hp, 1.0),
		"kills": kills, "units": units, "coins": coins, "time": _elapsed, "damage_log": _damage_log.duplicate(),
		"boss": String(_boss_event.get("boss", "")), "boss_hp_frac": (boss.hp / boss.max_hp) if boss else 0.0,
	}


func _summary() -> String:
	var s := hero.stats
	var boss_line := ""
	if boss:
		boss_line = "\n%s %s" % [boss.display_name, "defeated" if not boss.alive else "%d%% HP left" % int(boss.hp / boss.max_hp * 100.0)]
	return "Distance  %dm\nKills  %d     Coins  %d%s\n\nDMG %s  |  RATE %s/s  |  SHOTS %d\n%s  |  ALLIES %d" % [
		mini(int(-hero.position.z), int(_length)), kills, coins, boss_line,
		GateInfo.num(snappedf(s.damage, 0.1)), GateInfo.num(snappedf(s.fire_rate, 0.1)), s.projectiles,
		Content.element_name(s.element), s.ally_count(),
	]


func _log_result(outcome: String) -> void:
	var s := hero.stats
	print("[run] %s at %.0fm after %.1fs | hp %.0f | kills %d | coins %d | dmg %.1f rate %.1f shots %d | %s | allies %s" % [
		outcome, -hero.position.z, _elapsed, s.hp, kills, coins, s.damage, s.fire_rate, s.projectiles, s.element, s.allies,
	])
	print("[run] damage taken by source: %s" % _damage_log)
	if boss:
		print("[run] boss %s hp %d/%d, fight %.1fs" % [boss.boss_id, int(boss.hp), int(boss.max_hp), _elapsed - _arena_time])


## Banks the payout, records progress, and shows the results screen (once per run).
func _finish_run(won: bool) -> void:
	if _ended:
		return
	_ended = true
	coins += coin_shower.collect_all()
	hud.set_coins(coins)
	AdManager.on_run_completed()
	match GameState.mode:
		"endless":
			_finish_endless()
			return
		"daily":
			_finish_daily(won)
			return
	var level := int(plan.get("level", 0))
	var payout := Economy.run_payout(coins, won, level, Balance.data, _coin_bonus)
	var reward := {}
	# Bot/tool runs never touch the player's save.
	var campaign := GameState.mode == "campaign" and level > 0 and not GameState.fast_results and not GameState.autopilot
	if campaign:
		reward = SaveManager.record_campaign_run(level, won, int(payout["total"]), kills, _elapsed)
	var lines: PackedStringArray = [_summary(), ""]
	lines.append("Coins collected  %d" % int(payout["collected"]))
	if int(payout["win_bonus"]) > 0:
		lines.append("Victory bonus  +%d" % int(payout["win_bonus"]))
	if int(payout["upgrade_bonus"]) > 0:
		lines.append("Treasure Sense  +%d" % int(payout["upgrade_bonus"]))
	lines.append("TOTAL  +%d" % int(payout["total"]))
	var buttons: Array = []
	if won and level > 0:
		buttons.append(["NEXT LEVEL", _next_level])
	buttons.append(["REPLAY" if won else "TRY AGAIN", _restart])
	if not won:
		buttons.append(["UPGRADES", func() -> void:
			GameState.return_screen = "map"
			GameState.go("shop")])
	buttons.append(["MAP", func() -> void: GameState.go("map")])
	hud.show_result(won, "\n".join(lines), buttons)
	if not reward.is_empty():
		hud.show_reward(reward)


func _next_level() -> void:
	GameState.level = int(plan.get("level", 0)) + 1
	GameState.seed_override = -1
	_restart()


## Where "menu"/quit buttons lead for the current mode.
func _menu_screen() -> String:
	match GameState.mode:
		"endless":
			return "endless"
		"daily":
			return "daily"
	return "map"


func _banner_title() -> String:
	if _endless:
		return "ENDLESS"
	if GameState.mode == "daily":
		return "DAILY CHALLENGE"
	return _level_title()


func _level_title() -> String:
	if _endless:
		return "ENDLESS  ·  %dm  ·  SCORE %d" % [int(-hero.position.z) if hero else 0, _endless_score()]
	if GameState.mode == "daily":
		return "DAILY  ·  " + _daily_date
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
	if duration <= 0.0 or Engine.time_scale < 1.0 or GameState.fast_results:
		return
	Engine.time_scale = 0.05
	await get_tree().create_timer(duration, true, false, true).timeout
	if state != State.DEAD:
		Engine.time_scale = 1.0


# --- World ------------------------------------------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = ZoneTheme.color(_zone, "sky", Color("#9DCBEA"))
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = ZoneTheme.color(_zone, "ambient", Color("#C4D3EA"))
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = ZoneTheme.color(_zone, "fog", Color("#A9CFEA"))
	env.fog_density = float(_zone.get("fog_density", 0.008))
	if (plan.get("modifiers", []) as Array).has("fog"):
		env.fog_density = float(Content.modifiers.get("fog", {}).get("fog_density", 0.05))
		env.background_color = env.fog_light_color
	env.fog_sky_affect = 0.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	_env = env

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = float(_zone.get("sun_energy", 1.15))
	sun.light_color = ZoneTheme.color(_zone, "sun", Color("#FFF2DC"))
	sun.shadow_enabled = false
	add_child(sun)
	_sun = sun


# --- Feel -------------------------------------------------------------------------------------

func _on_coin_collected(value: int, at: Vector3) -> void:
	coins += value
	hud.set_coins(coins)
	# Quick pickups climb in pitch; the combo resets after a short pause.
	_coin_combo = mini(_coin_combo + 1, 16)
	_coin_combo_timer = 0.45
	AudioManager.play("coin", 0.0, 0.0, 0.0, 1.0 + _coin_combo * 0.035)
	if not camera.is_position_behind(at):
		hud.coin_fly(camera.unproject_position(at))


func _tick_feel(delta: float) -> void:
	_coin_combo_timer -= delta
	if _coin_combo_timer <= 0.0:
		_coin_combo = 0
	# Footstep dust while running.
	if hero.alive and not _in_arena and state == State.RUNNING:
		_dust_timer -= delta
		if _dust_timer <= 0.0:
			_dust_timer = 0.24
			sparks.emit("dust", hero.position + Vector3(randf_range(-0.2, 0.2), 0.1, 0.3))


# --- Endless ----------------------------------------------------------------------------------

## Builds a chunk's track (exactly its own distance range, so neighbours never overlap) and its
## arena if it ends in a boss. The chunk keeps its world root so it can be freed once passed.
func _add_chunk_world(chunk: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "Chunk%d" % int(chunk["index"])
	add_child(root)
	var zone := ZoneTheme.resolve(Content.zones, String(chunk.get("zone", "forest")), int(chunk.get("zone_cycle", 0)))
	var boss_event: Dictionary = chunk.get("boss_event", {})
	var from_d := float(chunk["start"]) - (40.0 if int(chunk["index"]) == 0 else 0.0)
	var to_d := float(chunk["end"]) + (8.0 if not boss_event.is_empty() else 0.0)
	TrackBuilder.build_range(root, from_d, to_d, _track_width * 0.5, int(chunk.get("seed", 1)), zone)
	if not boss_event.is_empty():
		TrackBuilder.build_arena(root, float(boss_event["d"]), _track_width * 0.5, zone)
	var entry := chunk.duplicate()
	entry.erase("events")
	entry["root"] = root
	entry["zone_theme"] = zone
	_chunks.append(entry)


func _tick_endless(delta: float, distance: float) -> void:
	var cfg := Balance.section("endless")
	var last: Dictionary = _chunks[-1]
	# Generate the next chunk well before the current one runs out.
	if distance + float(cfg.get("generate_ahead", 160.0)) > float(last["end"]):
		var chunk := _endless.next_chunk(Content.db, Balance.data, hero.stats)
		_events.append_array(chunk["events"])
		_add_chunk_world(chunk)
	# Entering a new chunk: switch zone look, ally power, and summon scaling.
	for k in _chunks.size():
		var c := _chunks[k]
		if k > _active_chunk and distance >= float(c["start"]):
			_active_chunk = k
			plan["coin_mult"] = c.get("coin_mult", 1.0)
			hero.stats.ally_power = float(c.get("ally_power", 1.0))
			_apply_zone(c["zone_theme"])
			if GameState.autopilot:
				print("[endless] chunk %d tier %d at %dm  t=%.0fs  hp %d/%d  kills %d  bosses %d  pressure %s  nodes %d" % [
					int(c["index"]), int(c.get("tier", 1)), int(distance), _elapsed, int(hero.stats.hp), int(hero.stats.max_hp),
					kills, _bosses_defeated, c.get("pressure", {}), get_tree().get_node_count()])
			if k > 0:
				hud.show_banner("TIER %d" % int(c.get("tier", 1)), String((c["zone_theme"] as Dictionary).get("name", "")), Color("#FFD166"), 1.2)
	# Free worlds far behind the hero.
	while _chunks.size() > 1 and distance - float(_chunks[0]["end"]) > float(cfg.get("cleanup_behind", 120.0)):
		(_chunks[0]["root"] as Node).queue_free()
		_chunks.remove_at(0)
		_active_chunk -= 1
	# Consumed events are dropped so the list stays small however long the run lasts.
	if _next_event > 200:
		_events = _events.slice(_next_event)
		_next_event = 0
	for k in range(_next_event, mini(_next_event + 8, _events.size())):
		if String(_events[k].get("type", "")) == "enemies":
			_summon_hp_mult = float(_events[k].get("hp_mult", 1.0))
			_summon_dmg_mult = float(_events[k].get("dmg_mult", 1.0))
			break
	var current := _chunks[clampi(_active_chunk, 0, _chunks.size() - 1)]
	hud.set_progress((distance - float(current["start"])) / maxf(float(current["end"]) - float(current["start"]), 1.0))
	_title_timer -= delta
	if _title_timer <= 0.0:
		_title_timer = 0.5
		hud.set_level_title(_level_title())


func _endless_score() -> int:
	return int(maxf(0.0, -hero.position.z)) + kills if hero else 0


func _apply_zone(zone: Dictionary) -> void:
	_zone = zone
	AudioManager.play_music(String(zone.get("id", "forest")))
	if _env:
		_env.background_color = ZoneTheme.color(zone, "sky", Color("#9DCBEA"))
		_env.ambient_light_color = ZoneTheme.color(zone, "ambient", Color("#C4D3EA"))
		_env.fog_light_color = ZoneTheme.color(zone, "fog", Color("#A9CFEA"))
		_env.fog_density = float(zone.get("fog_density", 0.008))
	if _sun:
		_sun.light_color = ZoneTheme.color(zone, "sun", Color("#FFF2DC"))
		_sun.light_energy = float(zone.get("sun_energy", 1.15))


## Endless: a boss falling is a checkpoint, not the end. Clear the arena and run on.
func _resume_after_boss() -> void:
	if arena:
		arena.queue_free()
		arena = null
	if boss:
		boss.queue_free()
		boss = null
	_boss_event = {}
	_in_arena = false
	hud.hide_boss()
	hud.show_banner("BOSS DEFEATED!", "The road goes on...", Color("#FFD166"), 1.4)
	AudioManager.play_music(String(_zone.get("id", "forest")))
	hero.set_running(true, 0.8)


func _finish_endless() -> void:
	var distance := -hero.position.z
	var score := _endless_score()
	var tier := int(_chunks[clampi(_active_chunk, 0, _chunks.size() - 1)].get("tier", 1)) if not _chunks.is_empty() else 1
	var payout := Economy.run_payout(coins, false, tier, Balance.data, _coin_bonus)
	var best := false
	if not GameState.autopilot and not GameState.fast_results:
		best = SaveManager.record_endless(score, distance, int(payout["total"]), kills, _elapsed)
	var high: int = int(SaveManager.data["high_scores"]["endless_score"])
	var lines: PackedStringArray = [
		"SCORE  %d%s" % [score, "   NEW BEST!" if best else ""],
		"Best  %d" % high,
		"",
		"Distance  %dm     Kills  %d" % [int(distance), kills],
		"Bosses defeated  %d     Tier reached  %d" % [_bosses_defeated, tier],
		"",
		"Coins  +%d" % int(payout["total"]),
	]
	hud.show_result(false, "\n".join(lines), [
		["PLAY AGAIN", _restart],
		["BACK", func() -> void: GameState.go("endless")],
	], "NEW BEST!" if best else "RUN OVER")


func _finish_daily(won: bool) -> void:
	var distance := -hero.position.z
	var score := int(distance) + kills
	var payout := Economy.run_payout(coins, won, int(plan.get("level", 1)), Balance.data, _coin_bonus)
	var bonus := 0
	if won:
		var cfg := Balance.section("daily")
		bonus = int(roundf(float(cfg.get("bonus_base", 400)) * Curves.named(Balance.data, "coin_multiplier", SaveManager.unlocked_level())))
	var total := int(payout["total"]) + bonus
	if not GameState.autopilot and not GameState.fast_results:
		SaveManager.record_daily_result(_daily_date, won, score, total, kills, _elapsed)
	var lines: PackedStringArray = [_summary(), "", "Score  %d" % score, "Coins  +%d" % int(payout["total"])]
	if bonus > 0:
		lines.append("Daily bonus  +%d" % bonus)
	var buttons: Array = []
	if not won and SaveManager.daily_can_retry(_daily_date):
		buttons.append(["RETRY  (WATCH AD)", func() -> void:
			AdManager.show_rewarded("daily_retry", func() -> void:
				SaveManager.grant_daily_retry(_daily_date)
				GameState.go("run"))])
	buttons.append(["BACK", func() -> void: GameState.go("daily")])
	hud.show_result(won, "\n".join(lines), buttons, "DAILY CLEARED!" if won else "")


# --- Boss -------------------------------------------------------------------------------------

func _spawn_boss(event: Dictionary) -> void:
	var def: Dictionary = Content.bosses.get(String(event.get("boss", "")), {})
	if def.is_empty():
		return
	var distance := float(_boss_cfg.get("distance", 20.0))
	_boss_event = event
	boss = Boss.new()
	boss.name = "Boss"
	add_child(boss)
	boss.setup(event, def, Content.modifiers)
	boss.position = Vector3(0, 0, -(float(event["d"]) + distance))
	boss.phase_changed.connect(_on_boss_phase)
	arena = BossArena.new()
	add_child(arena)
	var tint := Content.element_color(boss.element) if boss.element != "none" else Color("#FF5A3B")
	arena.setup(-float(event["d"]), boss.position.z, _track_width, int(_boss_cfg.get("lanes", 4)), tint)
	arena.hero_hit.connect(_on_arena_hero_hit)
	arena.ally_hit.connect(_on_enemy_shot_ally)
	arena.impact.connect(_on_arena_impact)
	arena.volley_requested.connect(_on_boss_volley)
	arena.summon_requested.connect(_on_boss_summon)


func _tick_boss(delta: float, distance: float) -> void:
	if boss == null:
		return
	_boss_hit_stop_cd -= delta
	if not _in_arena and state == State.RUNNING and distance >= float(_boss_event["d"]):
		_in_arena = true
		_arena_time = _elapsed
		hero.set_running(false, float(_boss_cfg.get("stop_time", 0.6)))
		boss.start_fight()
		hud.show_boss(boss.display_name, boss.element, boss.max_hp)
		var weak := Content.weakness_of(boss.element)
		hud.show_banner(boss.display_name.to_upper(), ("Weak to %s" % Content.element_name(weak)) if weak != "" else "", Color("#FFB3A0"), 1.6)
		camera.add_trauma(0.4)
		AudioManager.play("boss_roar")
		AudioManager.play_music("boss", 0.6)
		shockwaves.spawn(boss.position, Color("#FF5A3B"), 7.0, 0.8)
	var orders := boss.tick(delta)
	if state == State.RUNNING:
		for attack: Dictionary in orders:
			arena.execute(attack, hero.position.x, boss.lane_rng())
			if String(attack.get("type", "")) in ["slam", "sweep"]:
				AudioManager.play("telegraph")
	arena.tick(delta, hero, squad.allies)


func _damage_boss(base: float, element: String, at: Vector3) -> void:
	if boss == null or not boss.alive or not boss.fighting:
		return
	var mult := CombatMath.element_multiplier(element, boss.element, Content.elements, _combat)
	var amount := base * mult
	var killed := boss.take_damage(amount)
	hud.set_boss_hp(boss.hp, boss.max_hp)
	numbers.pop(at + Vector3(randf_range(-0.8, 0.8), 0.8, 0.5), GateInfo.num(roundf(amount)) + ("!" if mult > 1.01 else ""),
		Color("#FFB23E") if mult > 1.01 else (Color(0.7, 0.72, 0.78) if mult < 0.99 else Color("#FFF4C2")), 2.6 if mult > 1.01 else 2.1)
	if _boss_hit_stop_cd <= 0.0:
		_boss_hit_stop_cd = float(_boss_cfg.get("hit_stop_cooldown", 0.25))
		_hit_stop(float(_boss_cfg.get("hit_stop", 0.035)))
	if killed:
		_on_boss_defeated()


func _on_projectile_boss_hit(damage: float, at: Vector3, element: String) -> void:
	_damage_boss(damage, element, at)
	AudioManager.play("hit", 0.0, 0.15, 0.04)


func _on_ally_melee_boss(ally: Ally) -> void:
	if boss:
		_damage_boss(ally.damage * 0.6, hero.stats.element, boss.position + Vector3(0, boss.hit_height, boss.radius))


func _on_boss_phase(index: int) -> void:
	camera.add_trauma(0.7)
	_hit_stop(float(_boss_cfg.get("phase_hit_stop", 0.18)))
	hud.flash(Color("#FF3B3B"), 0.3)
	hud.show_banner("PHASE %d" % (index + 1), "%s grows desperate!" % boss.display_name, Color("#FF8A6B"), 1.0)
	bursts.burst(boss.position + Vector3(0, boss.hit_height, 0), Content.element_color(boss.element))
	shockwaves.spawn(boss.position, Color("#FF8A6B"), 9.0, 0.7)
	AudioManager.play("phase")


func _on_boss_defeated() -> void:
	arena.clear()
	for i in 6:
		bursts.burst(boss.position + Vector3(randf_range(-2, 2), randf_range(1, 4), randf_range(-1, 1)), Content.element_color(boss.element) if i % 2 == 0 else Color("#FFD166"))
	boss.visible = false
	camera.add_trauma(1.0)
	_hit_stop(float(_boss_cfg.get("death_hit_stop", 0.25)))
	coin_shower.spawn(boss.position, int(roundf(float(boss.def.get("coins", 10)) * float(plan.get("coin_mult", 1.0)))), 24)
	shockwaves.spawn(boss.position, Color("#FFD166"), 12.0, 0.9)
	sparks.emit("gold", boss.position + Vector3(0, 2.0, 0))
	AudioManager.play("boss_slam")
	AudioManager.play("kill_elite")
	GameState.vibrate(60)
	_bosses_defeated += 1
	if _endless:
		_resume_after_boss()
	else:
		_win()


func _on_arena_hero_hit(damage: float, at: Vector3) -> void:
	bursts.burst(at, Color("#FF5A3B"))
	_damage_log["boss"] = float(_damage_log.get("boss", 0.0)) + damage
	_hurt_hero(damage)


func _on_arena_impact(at: Vector3, tint: Color, strength: float) -> void:
	bursts.burst(at, tint)
	shockwaves.spawn(at, tint, 2.4, 0.35)
	camera.add_trauma(strength * 0.5)
	AudioManager.play("boss_slam", 0.0, 0.1, 0.12)


func _on_boss_volley(attack: Dictionary) -> void:
	var count := maxi(1, int(attack.get("shots", 3)))
	var spread := deg_to_rad(float(attack.get("spread", 12.0)))
	var origin := boss.position + Vector3(0, minf(boss.hit_height, 2.5), boss.radius)
	var aim := Vector3(hero.position.x - origin.x, 0, hero.position.z - origin.z).normalized()
	var tint := Content.element_color(boss.element) if boss.element != "none" else Color("#FF5A3B")
	for k in count:
		var offset := (k - (count - 1) * 0.5) * (spread / maxf(count - 1, 1))
		var dir := aim.rotated(Vector3.UP, offset)
		enemy_shots.spawn(origin, origin + dir * 30.0, float(attack.get("speed", 12.0)), float(attack.get("damage_abs", 8.0)), tint, 32.0)
	AudioManager.play("enemy_shot", 0.0, 0.1)


func _on_boss_summon(attack: Dictionary) -> void:
	var event := {
		"d": float(_boss_event["d"]) + 11.0,
		"type": "enemies",
		"enemy": String(attack.get("enemy", "grunt")),
		"formation": String(attack.get("formation", "line")),
		"count": int(attack.get("count", 3)),
		"rows": int(attack.get("rows", 2)),
		"cols": int(attack.get("cols", 3)),
		"spacing": float(attack.get("spacing", 1.3)),
		"x": randf_range(-1.0, 1.0),
		"element": String(attack.get("element", boss.element)),
		"hp_mult": _summon_hp_mult * float(attack.get("hp", 0.6)),
		"dmg_mult": _summon_dmg_mult,
	}
	_spawn_enemies(event)
	bursts.burst(Vector3(0, 1.0, -event["d"]), Content.element_color(boss.element))


# --- First-run tutorial ----------------------------------------------------------------------

## Short guided first run in level 1: steering, auto-attack, gates, and boss telegraphs. Uses gentle
## slow motion at the two moments that need a decision.
func _tick_tutorial() -> void:
	var distance := -hero.position.z
	# The gate tip outranks earlier tips: it must appear before the first gate arrives.
	if _tutorial_step in [1, 2]:
		for gate_set in gate_sets:
			if hero.position.z - gate_set.position.z < 26.0:
				_tutorial_step = 2
				_tutorial_hold = 0.0
	if _elapsed < _tutorial_hold and _tutorial_step not in [3, 6]:
		return
	match _tutorial_step:
		0:
			hud.show_tip("Drag left and right to steer", 3.0)
			_tutorial_hold = _elapsed + 2.2
			_tutorial_step = 1
		1:
			for e in enemies:
				if e.active and hero.position.z - e.position.z < 22.0:
					hud.show_tip("Your mage attacks automatically.\nLine up with enemies!", 3.0)
					_tutorial_hold = _elapsed + 2.2
					_tutorial_step = 2
					break
		2:
			for gate_set in gate_sets:
				if hero.position.z - gate_set.position.z < 26.0:
					hud.show_tip("Steer through a gate to power up.\nPick one!", 30.0)
					_tutorial_gate_z = gate_set.position.z
					Engine.time_scale = 0.45
					_tutorial_step = 3
					break
		3:
			if hero.position.z < _tutorial_gate_z - 0.5 or distance > 80.0:
				Engine.time_scale = 1.0
				hud.show_tip("Every gate changes your build.\nAdapt to what you're offered!", 3.0)
				_tutorial_hold = _elapsed + 3.2
				_tutorial_step = 4
		4:
			if _in_arena:
				hud.show_tip("Boss! Red lanes are about to be hit.\nSteer out of them!", 4.0)
				_tutorial_step = 5
		5:
			if arena and not arena.danger_lanes().is_empty():
				Engine.time_scale = 0.5
				_tutorial_step = 6
		6:
			if arena and arena.danger_lanes().is_empty():
				Engine.time_scale = 1.0
				_tutorial_step = 7
				_tutorial = false


# --- Dev autopilot ----------------------------------------------------------------------------

## Expected enemy element mix over the next stretch (same rules as the Estimator).
func upcoming_mix(horizon: float) -> Dictionary:
	var here := -hero.position.z
	var start := 0
	while start < _events.size() and float(_events[start]["d"]) < here:
		start += 1
	return Estimator.mix_from_events(_events, start, here, horizon, Content.db)


## Dev bot (also drives tools/calibrate): avoids wall pieces first, then heads for the best-scoring
## gate lane, otherwise lines up with the nearest mobile enemy. It never dodges shots, so it plays a
## little worse than a careful human.
func _autopilot() -> void:
	# 0. Boss arena: stand in the nearest lane that isn't about to be hit.
	if _in_arena and arena:
		var danger := arena.danger_lanes()
		var here := arena.lane_of(hero.position.x)
		if danger.has(here):
			var best_lane := here
			var best_cost := INF
			for lane in arena.lanes:
				if danger.has(lane):
					continue
				var cost := absf(lane - here) + absf(lane - (arena.lanes - 1) * 0.5) * 0.1
				if cost < best_cost:
					best_cost = cost
					best_lane = lane
			hero.target_x = arena.lane_center(best_lane)
		return
	# 1. Wall pieces ahead or alongside: take the gap; with no gap, break one piece.
	var blockers: Array[float] = []
	var weakest: Enemy = null
	for e in enemies:
		var ahead := hero.position.z - e.position.z
		if e.active and e.behavior == "static" and ahead > -1.5 and ahead < 14.0:
			blockers.append(e.position.x)
			if weakest == null or e.hp < weakest.hp:
				weakest = e
	if not blockers.is_empty():
		var best_x := hero.target_x
		var best_clear := -INF
		for step in 18:
			var x := -3.4 + step * 0.4
			var clear := INF
			for bx in blockers:
				clear = minf(clear, absf(bx - x))
			# Prefer staying close to the current line when clearances tie.
			var score := clear - absf(x - hero.position.x) * 0.05
			if score > best_clear:
				best_clear = score
				best_x = x
		var gap := INF
		for bx in blockers:
			gap = minf(gap, absf(bx - best_x))
		if gap < weakest.radius + hero.radius:
			best_x = weakest.position.x
		hero.target_x = best_x
		return
	# 2. Gate choice.
	var nearest_gate: GateSet = null
	for gate_set in gate_sets:
		if hero.position.z - gate_set.position.z < 40.0 and (nearest_gate == null or gate_set.position.z > nearest_gate.position.z):
			nearest_gate = gate_set
	if nearest_gate:
		var mix := upcoming_mix(Estimator.MIX_HORIZON)
		var best_lane := 0
		var best_score := -INF
		for lane in nearest_gate.gates.size():
			var gate_score := CombatMath.gate_score(nearest_gate.gates[lane], hero.stats, mix, Content.elements, Content.allies, _combat)
			if gate_score > best_score:
				best_score = gate_score
				best_lane = lane
		hero.target_x = nearest_gate.lane_center(best_lane)
		return
	# 3. Line up with the nearest mobile enemy (static and ranged ones get aim assist).
	var nearest: Enemy = null
	for e in enemies:
		if e.active and e.behavior != "ranged" and e.behavior != "static" and e.position.z < hero.position.z and (nearest == null or e.position.z > nearest.position.z):
			nearest = e
	if nearest:
		hero.target_x = clampf(nearest.position.x, -3.4, 3.4)
