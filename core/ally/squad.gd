class_name Squad
extends Node3D
## Owns the live allies: keeps them in sync with HeroStats.allies, lays out the formation,
## and decides when each ally attacks. Damage resolution stays in Run (one damage path).

signal melee_hit(ally: Ally, enemy: Enemy)
signal ranged_shot(ally: Ally, origin: Vector3)

var allies: Array[Ally] = []

var _pool: NodePool
var _half_width := 3.4
var _smoothing := 9.0
var _front := 1.7
var _back := 1.5
var _spacing := 1.15
var _back_spread := 1.6
var _tint := Color("#9FE8FF")


func setup() -> void:
	_pool = NodePool.new(self, func() -> Ally: return Ally.new(), 6)
	_half_width = Balance.f("track.width") * 0.5 - 0.45
	_smoothing = Balance.f("allies.follow_smoothing")
	_front = Balance.f("allies.front_offset")
	_back = Balance.f("allies.back_offset")
	_spacing = Balance.f("allies.spacing")
	_back_spread = Balance.f("allies.back_spread")


## Spawns/removes allies so the live squad matches stats.allies. Returns the number spawned.
func reconcile(stats: HeroStats, hero_pos: Vector3) -> int:
	var live: Dictionary = {}
	for a in allies:
		live[a.ally_id] = int(live.get(a.ally_id, 0)) + 1
	var spawned := 0
	for id: String in stats.allies:
		var missing := int(stats.allies[id]) - int(live.get(id, 0))
		for i in missing:
			var a := _pool.acquire() as Ally
			a.spawn(id, Content.ally(id), hero_pos + Vector3(randf_range(-0.5, 0.5), 0, 0), stats.ally_power)
			a.set_element_tint(_tint)
			allies.append(a)
			spawned += 1
	for id: String in live:
		var extra := int(live[id]) - int(stats.allies.get(id, 0))
		for k in range(allies.size() - 1, -1, -1):
			if extra <= 0:
				break
			if allies[k].ally_id == id:
				_release(k)
				extra -= 1
	_layout()
	return spawned


func set_element_tint(color: Color) -> void:
	_tint = color
	for a in allies:
		a.set_element_tint(color)


func tick(delta: float, hero_pos: Vector3, enemies: Array[Enemy]) -> void:
	for a in allies:
		if not a.active:
			continue
		a.follow(delta, hero_pos, _half_width, _smoothing)
		if not a.attack_ready():
			continue
		if a.kind == "ranged":
			if _any_enemy_ahead(a, enemies):
				a.on_attacked()
				ranged_shot.emit(a, a.global_position + Vector3(0, 1.0, -0.3))
		else:
			var target := _melee_target(a, enemies)
			if target:
				a.on_attacked()
				melee_hit.emit(a, target)


## Removes dead allies (after Run has updated stats) and closes the formation.
func sweep() -> bool:
	var removed := false
	for k in range(allies.size() - 1, -1, -1):
		if not allies[k].active:
			_release(k)
			removed = true
	if removed:
		_layout()
	return removed


func _release(index: int) -> void:
	var a := allies[index]
	a.active = false
	allies.remove_at(index)
	_pool.release(a)


## Front row (melee) ahead of the hero, back row (ranged) behind; rows of up to 5.
func _layout() -> void:
	var rows := {"front": [], "back": []}
	for a in allies:
		(rows["back"] if a.row == "back" else rows["front"]).append(a)
	for row_name: String in rows:
		var members: Array = rows[row_name]
		var direction := -1.0 if row_name == "front" else 1.0
		var base := _front if row_name == "front" else _back
		for i in members.size():
			var line := i / 5
			var in_line := i % 5
			# Fill outward from the center, alternating sides, leaving the hero's lane open so the
			# hero and its shots stay visible.
			var x := (-1.0 if in_line % 2 == 0 else 1.0) * (_spacing * 0.75 + (in_line / 2) * _spacing)
			if row_name == "back":
				# Flank the hero (left/right alternating) so ranged allies stay on screen.
				var side := -1.0 if i % 2 == 0 else 1.0
				x = side * (_back_spread + (i / 2) * 0.9)
				line = 0
			(members[i] as Ally).slot = Vector2(x, direction * (base + line * 1.2))


func _melee_target(a: Ally, enemies: Array[Enemy]) -> Enemy:
	var best: Enemy = null
	var best_dz := INF
	for e in enemies:
		if not e.active:
			continue
		var dz := a.position.z - e.position.z
		if dz < -0.6 or dz > a.attack_range + e.radius:
			continue
		if absf(e.position.x - a.position.x) > 0.9 + e.radius:
			continue
		if dz < best_dz:
			best_dz = dz
			best = e
	return best


func _any_enemy_ahead(a: Ally, enemies: Array[Enemy]) -> bool:
	for e in enemies:
		if e.active:
			var dz := a.position.z - e.position.z
			if dz > 1.0 and dz < a.attack_range:
				return true
	return false
