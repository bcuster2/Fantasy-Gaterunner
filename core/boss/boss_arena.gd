class_name BossArena
extends Node3D
## Executes boss attack orders. The track is split into lanes; telegraphed lanes glow and then hit,
## waves roll toward the hero with a gap to steer into, volleys and summons are handed back to Run.
## Steering out of danger is the whole skill check.

signal hero_hit(damage: float, at: Vector3)
signal ally_hit(ally: Ally, damage: float)
signal impact(at: Vector3, color: Color, strength: float)
signal volley_requested(attack: Dictionary)
signal summon_requested(attack: Dictionary)

const POOL := 12

var lanes := 4
var lane_width := 2.0
var hero_line := 0.0
var boss_z := -20.0
var color := Color("#FF5A3B")

var _telegraphs: Array[Dictionary] = []
var _waves: Array[Dictionary] = []
var _strips: Array[MeshInstance3D] = []
var _strip_mats: Array[StandardMaterial3D] = []
var _free_strips: Array[int] = []


func setup(hero_line_z: float, boss_line_z: float, track_width: float, lane_count: int, tint: Color) -> void:
	hero_line = hero_line_z
	boss_z = boss_line_z
	lanes = lane_count
	lane_width = track_width / lanes
	color = tint
	var length := absf(hero_line - boss_z) + 6.0
	for i in POOL:
		var strip := MeshInstance3D.new()
		strip.mesh = Placeholders.box(Vector3(lane_width - 0.18, 0.03, length))
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(1, 0.2, 0.15, 0.0)
		strip.material_override = m
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		strip.position = Vector3(0, 0.05, (hero_line + boss_z) * 0.5 + 1.5)
		strip.visible = false
		add_child(strip)
		_strips.append(strip)
		_strip_mats.append(m)
		_free_strips.append(i)


func lane_center(lane: int) -> float:
	return -lane_width * lanes * 0.5 + lane_width * (lane + 0.5)


func lane_of(x: float) -> int:
	return clampi(int(floor((x + lane_width * lanes * 0.5) / lane_width)), 0, lanes - 1)


## Lanes about to be hit (telegraphs and incoming waves). Used by the autopilot.
func danger_lanes() -> Array[int]:
	var out: Array[int] = []
	for t in _telegraphs:
		for lane: int in t["lanes"]:
			if not out.has(lane):
				out.append(lane)
	for w in _waves:
		if not bool(w["resolved"]):
			for lane in lanes:
				if not (w["gap"] as Array).has(lane) and not out.has(lane):
					out.append(lane)
	return out


func execute(attack: Dictionary, hero_x: float, rng: RandomNumberGenerator) -> void:
	var damage := float(attack.get("damage_abs", 10.0))
	var windup := float(attack.get("windup", 1.0))
	match String(attack.get("type", "")):
		"slam":
			var count := clampi(int(attack.get("lanes", 1)), 1, lanes - 1)
			var picked: Array[int] = [lane_of(hero_x)]
			var others: Array = range(lanes)
			others.erase(picked[0])
			GenUtil.shuffle(rng, others)
			for lane: int in others:
				if picked.size() >= count:
					break
				picked.append(lane)
			_add_telegraph(picked, windup, damage)
		"sweep":
			var order: Array = range(lanes)
			if rng.randf() < 0.5:
				order.reverse()
			var step := float(attack.get("step", 0.35))
			for k in order.size():
				_add_telegraph([order[k]], windup + k * step, damage)
		"wave":
			var gap: Array[int] = []
			var gap_count := clampi(int(attack.get("gap", 1)), 1, lanes - 1)
			var hero_lane := lane_of(hero_x)
			var options: Array = range(lanes)
			options.erase(hero_lane)
			GenUtil.shuffle(rng, options)
			for k in gap_count:
				gap.append(int(options[k % options.size()]))
			_add_wave(gap, float(attack.get("speed", 13.0)), damage)
		"volley":
			volley_requested.emit(attack)
		"summon":
			summon_requested.emit(attack)


func tick(delta: float, hero: Hero, allies: Array[Ally]) -> void:
	for k in range(_telegraphs.size() - 1, -1, -1):
		var t := _telegraphs[k]
		t["t"] = float(t["t"]) + delta
		var p := clampf(float(t["t"]) / maxf(float(t["windup"]), 0.01), 0.0, 1.0)
		var pulse := 0.5 + 0.5 * sin(float(t["t"]) * (8.0 + 16.0 * p))
		for idx: int in t["strips"]:
			_strip_mats[idx].albedo_color = Color(1.0, 0.25 - 0.15 * p, 0.12, 0.12 + 0.38 * p + 0.12 * pulse * p)
		if float(t["t"]) >= float(t["windup"]):
			_resolve_lanes(t["lanes"], float(t["damage"]), hero, allies)
			for idx: int in t["strips"]:
				_strips[idx].visible = false
				_free_strips.append(idx)
			_telegraphs.remove_at(k)

	for k in range(_waves.size() - 1, -1, -1):
		var w := _waves[k]
		var node: Node3D = w["node"]
		node.position.z += float(w["speed"]) * delta
		if not bool(w["resolved"]) and node.position.z >= hero.position.z:
			w["resolved"] = true
			var hit_lanes: Array[int] = []
			for lane in lanes:
				if not (w["gap"] as Array).has(lane):
					hit_lanes.append(lane)
			_resolve_lanes(hit_lanes, float(w["damage"]), hero, allies)
		if node.position.z > hero.position.z + 6.0:
			node.queue_free()
			_waves.remove_at(k)


func clear() -> void:
	for t in _telegraphs:
		for idx: int in t["strips"]:
			_strips[idx].visible = false
			_free_strips.append(idx)
	_telegraphs.clear()
	for w in _waves:
		(w["node"] as Node3D).queue_free()
	_waves.clear()


func _add_telegraph(lane_list: Array, windup: float, damage: float) -> void:
	var strips: Array[int] = []
	for lane: int in lane_list:
		if _free_strips.is_empty():
			break
		var idx: int = _free_strips.pop_back()
		_strips[idx].position.x = lane_center(lane)
		_strips[idx].visible = true
		_strip_mats[idx].albedo_color = Color(1, 0.25, 0.12, 0.1)
		strips.append(idx)
	_telegraphs.append({"lanes": lane_list.duplicate(), "t": 0.0, "windup": windup, "damage": damage, "strips": strips})


func _add_wave(gap: Array[int], speed: float, damage: float) -> void:
	var node := Node3D.new()
	node.position = Vector3(0, 0, boss_z + 2.0)
	add_child(node)
	var wall_mat := Placeholders.mat(color, 1.2)
	for lane in lanes:
		if gap.has(lane):
			var marker := Placeholders.part(Placeholders.box(Vector3(lane_width - 0.3, 0.06, 0.6)), Placeholders.overlay(Color(0.4, 1.0, 0.5, 0.7)), Vector3(lane_center(lane), 0.05, 0))
			node.add_child(marker)
			continue
		node.add_child(Placeholders.part(Placeholders.box(Vector3(lane_width - 0.1, 1.3, 0.5)), wall_mat, Vector3(lane_center(lane), 0.65, 0)))
	_waves.append({"node": node, "speed": speed, "gap": gap, "damage": damage, "resolved": false})


func _resolve_lanes(lane_list: Array, damage: float, hero: Hero, allies: Array[Ally]) -> void:
	var half := lane_width * 0.5
	var hero_struck := false
	for lane: int in lane_list:
		var cx := lane_center(lane)
		impact.emit(Vector3(cx, 0.6, hero.position.z - 1.0), color, 0.35)
		# One hit per attack even when the hero straddles two struck lanes.
		if not hero_struck and hero.alive and absf(hero.position.x - cx) < half + hero.radius * 0.5:
			hero_struck = true
			hero_hit.emit(damage, hero.position + Vector3(0, 1.0, 0))
		for a in allies:
			if a.active and absf(a.position.x - cx) < half:
				ally_hit.emit(a, damage * 0.5)
