extends Node3D
## One run through a LevelPlan. Owns the world, the pools, and the per-frame update order:
## input -> hero -> spawning -> firing -> enemies -> projectiles -> gates -> cleanup -> fx/camera.

enum State { RUNNING, DEAD, WON }

const SPAWN_AHEAD := 70.0

var plan: Dictionary
var state := State.RUNNING
var hero: Hero
var camera: CameraRig
var projectiles: ProjectileSystem
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
var _hurt_fx_cooldown := 0.0
var _drag_index := -1
var _elapsed := 0.0


func _ready() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	plan = LevelGenerator.get_plan(GameState.level)
	_events = plan["events"]
	_length = float(plan["length"])
	_track_width = Balance.f("track.width")
	_combat = Balance.section("combat")
	_max_enemies = Balance.i("enemy.max_alive")
	_despawn_behind = Balance.f("enemy.despawn_behind")

	_build_environment()
	TrackBuilder.build(self, _length, _track_width * 0.5, int(plan.get("level", 1)) * 7919)

	hero = Hero.new()
	hero.name = "Hero"
	add_child(hero)
	hero.setup(Content.hero_class(GameState.hero_class))
	hero.died.connect(_on_hero_died)

	camera = CameraRig.new()
	add_child(camera)
	camera.setup()

	projectiles = ProjectileSystem.new()
	add_child(projectiles)
	projectiles.setup(Color("#36C8FF"))
	projectiles.hit.connect(_on_projectile_hit)

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
	hero.hp_changed.connect(hud.set_hp)
	hud.set_hp(hero.stats.hp, hero.stats.max_hp)
	hud.set_stats(hero.stats)
	hud.set_coins(0)


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

	_tick_enemies(delta)
	projectiles.tick(delta, enemies)
	_check_gates()
	_sweep_enemies()

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
	var half := _track_width * 0.5 - 0.45
	for offset in Formations.offsets(event):
		if enemies.size() >= _max_enemies:
			break
		var e := _enemy_pool.acquire() as Enemy
		var x := clampf(center_x + offset.x, -half, half)
		e.spawn(id, def, hp_mult, Vector3(x, 0, -(float(event["d"]) + offset.y)))
		enemies.append(e)


func _spawn_gates(event: Dictionary) -> void:
	var gate_set := GateSet.new()
	add_child(gate_set)
	gate_set.position = Vector3(0, 0, -float(event["d"]))
	gate_set.setup(event.get("gates", []), _track_width)
	gate_sets.append(gate_set)


# --- Combat -----------------------------------------------------------------------------------

func _fire() -> void:
	var stats := hero.stats
	var origin := hero.muzzle_position()
	var aim := _aim_direction(origin)
	var count := stats.projectiles
	var spacing := float(_combat.get("projectile_spacing", 0.3))
	var fan := deg_to_rad(float(_combat.get("projectile_fan_degrees", 3.5)))
	for k in count:
		var offset := k - (count - 1) * 0.5
		var dir := aim.rotated(Vector3.UP, -offset * fan)
		var right := Vector3(-dir.z, 0, dir.x)
		projectiles.spawn(origin + right * (offset * spacing), dir, stats.damage)
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


func _on_projectile_hit(e: Enemy, damage: float, at: Vector3) -> void:
	var killed := e.take_damage(damage)
	e.pending_damage += damage
	if killed or e.number_cooldown <= 0.0:
		e.number_cooldown = Balance.f("feel.damage_number_interval")
		numbers.pop(at + Vector3(0, 0.5, 0), GateInfo.num(roundf(e.pending_damage)), Color("#FFF4C2"), 1.2)
		e.pending_damage = 0.0
	AudioManager.play("hit", -12.0, 0.15, 0.04)
	if killed:
		_on_enemy_killed(e)


func _on_enemy_killed(e: Enemy) -> void:
	kills += 1
	coins += int(roundf(e.coins * Balance.f("economy.coin_multiplier", 1.0)))
	hud.set_coins(coins)
	bursts.burst(e.position + Vector3(0, 0.7, 0), e.color)
	camera.add_trauma(Balance.f("feel.shake_kill"))
	AudioManager.play("kill", -6.0, 0.15, 0.03)


func _tick_enemies(delta: float) -> void:
	var hero_pos := hero.position
	for e in enemies:
		if not e.active:
			continue
		e.tick(delta, hero_pos)
		var dz := e.position.z - hero_pos.z
		if dz > _despawn_behind:
			e.active = false
			continue
		var reach := e.radius + hero.radius
		if hero.alive and absf(dz) < reach and absf(e.position.x - hero_pos.x) < reach:
			_enemy_reached_hero(e)


## Crowd-runner rule: an enemy that reaches the hero deals its damage and is destroyed.
func _enemy_reached_hero(e: Enemy) -> void:
	e.active = false
	e.visible = false
	bursts.burst(e.position + Vector3(0, 0.7, 0), e.color)
	hero.take_hit(e.contact_damage)
	numbers.pop(hero.position + Vector3(0, 2.2, 0), "-" + GateInfo.num(e.contact_damage), Color("#FF5A5A"), 1.2)
	if _hurt_fx_cooldown <= 0.0:
		_hurt_fx_cooldown = Balance.f("hero.hurt_fx_cooldown")
		camera.add_trauma(Balance.f("feel.shake_hero_hit"))
		AudioManager.play("hurt", -2.0, 0.1)
		GameState.vibrate(Balance.i("feel.vibrate_ms_hit"))
		if hero.alive:
			_hit_stop(Balance.f("feel.hit_stop_hero_hit"))


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
		hero.stats.apply_gate(gate, _combat)
		gate_set.trigger(lane)
		gate_sets.remove_at(k)

		var good := GateInfo.is_good(gate)
		var tint := GateInfo.color(gate)
		AudioManager.play("gate_good" if good else "gate_bad", -3.0, 0.0)
		numbers.pop(hero.position + Vector3(0, 3.0, -1.0), GateInfo.short_text(gate), tint.lightened(0.35), 1.7, 1.1)
		hud.set_stats(hero.stats, String(gate.get("stat", "")), good)
		hud.flash(tint, 0.22)
		camera.add_trauma(Balance.f("feel.shake_gate"))
		bursts.burst(hero.position + Vector3(0, 1.4, -0.5), tint)


# --- Run end ----------------------------------------------------------------------------------

func _on_hero_died() -> void:
	state = State.DEAD
	hero.visible = false
	for i in 3:
		bursts.burst(hero.position + Vector3(randf_range(-0.4, 0.4), 0.6 + i * 0.4, 0), Color("#FF5A5A") if i != 1 else Color("#3F6FD8"))
	camera.add_trauma(1.0)
	AudioManager.play("lose", 0.0, 0.0)
	_log_result("DIED")
	Engine.time_scale = Balance.f("feel.death_slowmo_scale")
	await get_tree().create_timer(Balance.f("feel.death_slowmo_time"), true, false, true).timeout
	Engine.time_scale = 1.0
	hud.show_result(false, _summary())


func _win() -> void:
	state = State.WON
	AudioManager.play("win", 0.0, 0.0)
	for i in 4:
		bursts.burst(hero.position + Vector3(randf_range(-3, 3), 2.0, -2.0), [Color("#FFD166"), Color("#3FA9FF"), Color("#FF6B6B"), Color("#7CF29A")][i])
	hud.show_result(true, _summary())
	_log_result("WON")


func _summary() -> String:
	var s := hero.stats
	return "Distance  %dm\nKills  %d     Coins  %d\n\nDMG %s  |  RATE %s/s  |  SHOTS %d" % [
		mini(int(-hero.position.z), int(_length)), kills, coins,
		GateInfo.num(snappedf(s.damage, 0.1)), GateInfo.num(snappedf(s.fire_rate, 0.1)), s.projectiles,
	]


func _log_result(outcome: String) -> void:
	print("[run] %s at %.0fm after %.1fs | hp %.0f | kills %d | coins %d | dmg %.1f rate %.1f shots %d" % [
		outcome, -hero.position.z, _elapsed, hero.stats.hp, kills, coins,
		hero.stats.damage, hero.stats.fire_rate, hero.stats.projectiles,
	])


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


## Dev-only bot: heads for the best-scoring gate lane, otherwise lines up with the nearest enemy.
func _autopilot() -> void:
	var nearest_gate: GateSet = null
	for gate_set in gate_sets:
		if hero.position.z - gate_set.position.z < 40.0 and (nearest_gate == null or gate_set.position.z > nearest_gate.position.z):
			nearest_gate = gate_set
	if nearest_gate:
		var best_lane := 0
		var best_score := -INF
		for lane in nearest_gate.gates.size():
			var gate_score := GateInfo.score(nearest_gate.gates[lane], hero.stats, _combat)
			if gate_score > best_score:
				best_score = gate_score
				best_lane = lane
		hero.target_x = nearest_gate.lane_center(best_lane)
		return
	var nearest: Enemy = null
	for e in enemies:
		if e.active and e.position.z < hero.position.z and (nearest == null or e.position.z > nearest.position.z):
			nearest = e
	if nearest:
		hero.target_x = clampf(nearest.position.x, -3.4, 3.4)
