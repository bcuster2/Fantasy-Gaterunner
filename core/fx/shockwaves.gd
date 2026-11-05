class_name Shockwaves
extends Node3D
## Pooled expanding ground rings for gate passes, boss slams, phase changes and big kills.

const RING_SHADER := preload("res://core/shaders/ring.gdshader")
const POOL := 10

var _rings: Array[MeshInstance3D] = []
var _mats: Array[ShaderMaterial] = []
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _next := 0


func setup() -> void:
	_age.resize(POOL)
	_life.resize(POOL)
	var quad := PlaneMesh.new()
	quad.size = Vector2(2, 2)
	for i in POOL:
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		var m := ShaderMaterial.new()
		m.shader = RING_SHADER
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_rings.append(mi)
		_mats.append(m)


## radius in meters at full size.
func spawn(at: Vector3, color: Color, radius := 3.0, life := 0.45) -> void:
	var i := _next
	_next = (_next + 1) % POOL
	_rings[i].global_position = Vector3(at.x, 0.08, at.z)
	_rings[i].scale = Vector3.ONE * radius
	_rings[i].visible = true
	_mats[i].set_shader_parameter("tint", color)
	_mats[i].set_shader_parameter("progress", 0.0)
	_age[i] = 0.0
	_life[i] = life


func tick(delta: float) -> void:
	for i in POOL:
		if not _rings[i].visible:
			continue
		_age[i] += delta
		var p := _age[i] / maxf(_life[i], 0.01)
		if p >= 1.0:
			_rings[i].visible = false
			continue
		_mats[i].set_shader_parameter("progress", 1.0 - pow(1.0 - p, 2.0))
