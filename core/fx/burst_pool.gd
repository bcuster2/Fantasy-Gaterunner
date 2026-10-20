class_name BurstPool
extends Node3D
## Pooled one-shot particle bursts (CPUParticles3D: reliable on GL Compatibility / older GPUs).

const POOL_SIZE := 16

var _emitters: Array[CPUParticles3D] = []
var _next := 0


func setup() -> void:
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	for i in POOL_SIZE:
		var p := CPUParticles3D.new()
		p.emitting = false
		p.one_shot = true
		p.explosiveness = 1.0
		p.amount = 16
		p.lifetime = 0.55
		p.mesh = Placeholders.box(Vector3(0.16, 0.16, 0.16))
		p.material_override = Placeholders.vertex_color_mat()
		p.direction = Vector3.UP
		p.spread = 70.0
		p.initial_velocity_min = 3.5
		p.initial_velocity_max = 7.0
		p.gravity = Vector3(0, -16, 0)
		p.angular_velocity_min = -360.0
		p.angular_velocity_max = 360.0
		p.scale_amount_min = 0.7
		p.scale_amount_max = 1.4
		p.scale_amount_curve = curve
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p)
		_emitters.append(p)


func burst(at: Vector3, color: Color) -> void:
	var p := _emitters[_next]
	_next = (_next + 1) % POOL_SIZE
	p.global_position = at
	p.color = color
	p.restart()
