class_name Sparks
extends Node3D
## Pooled one-shot particle styles, one look per element plus gold, dust and bone.
## Fire throws rising embers, ice falling shards, lightning fast short sparks, arcane a cyan puff.

const STYLES := {
	"arcane": {"color": "#8FE3FF", "amount": 8, "life": 0.3, "speed": [3.0, 6.0], "gravity": -6.0, "size": 0.09, "spread": 80.0, "pool": 10},
	"fire": {"color": "#FF8A3D", "amount": 10, "life": 0.55, "speed": [1.5, 3.5], "gravity": 4.0, "size": 0.12, "spread": 55.0, "pool": 10},
	"ice": {"color": "#CFF4FF", "amount": 8, "life": 0.45, "speed": [2.0, 5.0], "gravity": -14.0, "size": 0.13, "spread": 70.0, "pool": 10},
	"lightning": {"color": "#FFF27A", "amount": 10, "life": 0.18, "speed": [6.0, 10.0], "gravity": 0.0, "size": 0.07, "spread": 180.0, "pool": 10},
	"gold": {"color": "#FFD166", "amount": 14, "life": 0.7, "speed": [2.5, 5.5], "gravity": -7.0, "size": 0.11, "spread": 90.0, "pool": 8},
	"dust": {"color": "#8C7A60", "amount": 3, "life": 0.45, "speed": [0.4, 1.0], "gravity": 0.6, "size": 0.14, "spread": 70.0, "pool": 8},
	"bone": {"color": "#E8E2D0", "amount": 10, "life": 0.6, "speed": [3.0, 6.0], "gravity": -16.0, "size": 0.12, "spread": 80.0, "pool": 6},
}

var _pools: Dictionary = {}


func setup() -> void:
	var shrink := Curve.new()
	shrink.add_point(Vector2(0, 1))
	shrink.add_point(Vector2(1, 0))
	for style: String in STYLES:
		var cfg: Dictionary = STYLES[style]
		var emitters: Array[CPUParticles3D] = []
		for i in int(cfg["pool"]):
			var p := CPUParticles3D.new()
			p.emitting = false
			p.one_shot = true
			p.explosiveness = 1.0
			p.amount = int(cfg["amount"])
			p.lifetime = float(cfg["life"])
			var size := float(cfg["size"])
			if style in ["ice", "bone"]:
				p.mesh = Placeholders.crystal_mesh()
			elif style == "dust":
				p.mesh = Placeholders.sphere(size)
			else:
				p.mesh = Placeholders.box(Vector3(size, size, size))
			p.scale_amount_min = size / 0.5 if style in ["ice", "bone"] else 1.0
			p.scale_amount_max = p.scale_amount_min * 1.6
			p.scale_amount_curve = shrink
			p.material_override = _material()
			p.direction = Vector3.UP
			p.spread = float(cfg["spread"])
			p.initial_velocity_min = float(cfg["speed"][0])
			p.initial_velocity_max = float(cfg["speed"][1])
			p.gravity = Vector3(0, float(cfg["gravity"]), 0)
			p.angular_velocity_min = -500.0
			p.angular_velocity_max = 500.0
			p.color = Color(String(cfg["color"]))
			p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(p)
			emitters.append(p)
		_pools[style] = {"emitters": emitters, "next": 0}


## Style name for an element ("none" -> arcane).
static func style_for(element: String) -> String:
	return element if STYLES.has(element) else "arcane"


func emit(style: String, at: Vector3) -> void:
	var pool: Dictionary = _pools.get(style, _pools["arcane"])
	var emitters: Array[CPUParticles3D] = pool["emitters"]
	var p := emitters[int(pool["next"])]
	pool["next"] = (int(pool["next"]) + 1) % emitters.size()
	p.global_position = at
	p.restart()


var _mat: StandardMaterial3D


func _material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.vertex_color_use_as_albedo = true
	return _mat
