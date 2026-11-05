class_name Bolts
extends MeshInstance3D
## Chain-lightning arcs: jagged glowing ribbons between two points, rebuilt each frame while alive.

var _bolts: Array[Dictionary] = []
var _mesh := ImmediateMesh.new()
var _rng := RandomNumberGenerator.new()


func setup() -> void:
	mesh = _mesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-50, -10, -100000), Vector3(100, 40, 200000))


func spawn(from: Vector3, to: Vector3, color: Color, life := 0.18) -> void:
	if _bolts.size() > 12:
		_bolts.pop_front()
	_bolts.append({"from": from, "to": to, "color": color, "age": 0.0, "life": life})


func tick(delta: float) -> void:
	_mesh.clear_surfaces()
	for k in range(_bolts.size() - 1, -1, -1):
		_bolts[k]["age"] = float(_bolts[k]["age"]) + delta
		if float(_bolts[k]["age"]) >= float(_bolts[k]["life"]):
			_bolts.remove_at(k)
	if _bolts.is_empty():
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in _bolts:
		var fade := 1.0 - float(b["age"]) / float(b["life"])
		var color: Color = b["color"]
		color.a = fade
		var a: Vector3 = b["from"]
		var z: Vector3 = b["to"]
		var dir := (z - a)
		var side := Vector3(-dir.z, 0, dir.x).normalized() * 0.09
		var segments := 7
		var prev := a
		for s in range(1, segments + 1):
			var t := float(s) / segments
			var p := a.lerp(z, t)
			if s < segments:
				p += Vector3(_rng.randf_range(-0.35, 0.35), _rng.randf_range(-0.2, 0.2), _rng.randf_range(-0.35, 0.35))
			_quad(prev, p, side, color)
			prev = p
	_mesh.surface_end()


func _quad(a: Vector3, b: Vector3, side: Vector3, color: Color) -> void:
	for v: Vector3 in [a - side, a + side, b + side, a - side, b + side, b - side]:
		_mesh.surface_set_color(color)
		_mesh.surface_add_vertex(v)
