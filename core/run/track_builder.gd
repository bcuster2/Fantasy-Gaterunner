class_name TrackBuilder
extends RefCounted
## Builds the static world for a run: track, grass, curbs, forest (MultiMesh), and finish arch.
## Zone themes (Milestone 5) will feed colors in here.

const GROUND_SHADER := preload("res://core/shaders/ground.gdshader")
const CHECKER_SHADER := preload("res://core/shaders/checker.gdshader")
const START_Z := 40.0
const END_PAD := 110.0


static func build(parent: Node3D, length: float, half_width: float, seed_value: int) -> void:
	var total := length + START_Z + END_PAD
	var center_z := START_Z - total * 0.5

	var grass := MeshInstance3D.new()
	var grass_mesh := PlaneMesh.new()
	grass_mesh.size = Vector2(90, total)
	grass.mesh = grass_mesh
	grass.material_override = Placeholders.mat(Color("#5E9444"))
	grass.position = Vector3(0, -0.02, center_z)
	parent.add_child(grass)

	var ground := MeshInstance3D.new()
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(half_width * 2.0, total)
	ground.mesh = ground_mesh
	var ground_mat := ShaderMaterial.new()
	ground_mat.shader = GROUND_SHADER
	ground_mat.set_shader_parameter("half_width", half_width)
	ground.material_override = ground_mat
	ground.position = Vector3(0, 0, center_z)
	parent.add_child(ground)

	var curb_mat := Placeholders.mat(Color("#9C978C"))
	for side in [-1.0, 1.0]:
		var curb := Placeholders.part(Placeholders.box(Vector3(0.4, 0.4, total)), curb_mat, Vector3(side * (half_width + 0.2), 0.2, center_z))
		parent.add_child(curb)

	_build_forest(parent, length, half_width, seed_value)
	_build_finish(parent, length, half_width)


static func _build_forest(parent: Node3D, length: float, half_width: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var trunks: Array[Transform3D] = []
	var crowns: Array[Transform3D] = []
	var crown_colors: Array[Color] = []
	var z := START_Z
	while z > -(length + END_PAD):
		for side in [-1.0, 1.0]:
			for layer in 2:
				if rng.randf() > 0.8:
					continue
				var x: float = side * (half_width + 1.4 + layer * 5.0 + rng.randf() * 5.0)
				var s := rng.randf_range(0.75, 1.5)
				var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s)
				var at := Vector3(x, 0, z + rng.randf_range(-1.4, 1.4))
				trunks.append(Transform3D(basis, at + Vector3(0, 0.5 * s, 0)))
				crowns.append(Transform3D(basis, at + Vector3(0, 1.9 * s, 0)))
				crown_colors.append(Color("#2F6B3A").lerp(Color("#4E9A42"), rng.randf()))
		z -= 3.0

	parent.add_child(_multimesh(Placeholders.cylinder(0.12, 0.18, 1.0, 6), Placeholders.mat(Placeholders.WOOD), trunks, []))
	parent.add_child(_multimesh(Placeholders.cylinder(0.0, 1.0, 2.2, 7), Placeholders.vertex_color_mat(), crowns, crown_colors))


static func _multimesh(mesh: Mesh, material: Material, transforms: Array[Transform3D], colors: Array[Color]) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for k in transforms.size():
		mm.set_instance_transform(k, transforms[k])
		if mm.use_colors:
			mm.set_instance_color(k, colors[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


static func _build_finish(parent: Node3D, length: float, half_width: float) -> void:
	var z := -length
	var strip := MeshInstance3D.new()
	var strip_mesh := PlaneMesh.new()
	strip_mesh.size = Vector2(half_width * 2.0, 2.0)
	strip.mesh = strip_mesh
	var checker := ShaderMaterial.new()
	checker.shader = CHECKER_SHADER
	strip.material_override = checker
	strip.position = Vector3(0, 0.01, z)
	parent.add_child(strip)

	var stone := Placeholders.mat(Color("#CFC6B4"))
	for side in [-1.0, 1.0]:
		parent.add_child(Placeholders.part(Placeholders.box(Vector3(0.7, 5.0, 0.7)), stone, Vector3(side * (half_width + 0.6), 2.5, z)))
	parent.add_child(Placeholders.part(Placeholders.box(Vector3(half_width * 2.0 + 2.2, 0.9, 0.5)), Placeholders.mat(Color("#B23A48")), Vector3(0, 5.2, z)))
	var banner := Label3D.new()
	banner.text = "FINISH"
	banner.font_size = 140
	banner.pixel_size = 0.008
	banner.outline_size = 20
	banner.position = Vector3(0, 5.2, z + 0.3)
	parent.add_child(banner)
