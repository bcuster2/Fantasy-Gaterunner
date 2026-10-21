class_name TrackBuilder
extends RefCounted
## Builds the static world for a run from a resolved zone (ZoneTheme): track, ground, curbs,
## zone props (MultiMesh), and either a finish arch or the boss arena markers.

const GROUND_SHADER := preload("res://core/shaders/ground.gdshader")
const CHECKER_SHADER := preload("res://core/shaders/checker.gdshader")
const START_Z := 40.0
const END_PAD := 110.0


## arena_d < 0: plain finish line at `length`. Otherwise the arena starts at arena_d.
static func build(parent: Node3D, length: float, half_width: float, seed_value: int, zone: Dictionary, arena_d := -1.0) -> void:
	var total := length + START_Z + END_PAD
	var center_z := START_Z - total * 0.5

	var grass := MeshInstance3D.new()
	var grass_mesh := PlaneMesh.new()
	grass_mesh.size = Vector2(90, total)
	grass.mesh = grass_mesh
	grass.material_override = Placeholders.mat(ZoneTheme.color(zone, "grass", Color("#5E9444")))
	grass.position = Vector3(0, -0.02, center_z)
	parent.add_child(grass)

	var ground := MeshInstance3D.new()
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(half_width * 2.0, total)
	ground.mesh = ground_mesh
	var ground_mat := ShaderMaterial.new()
	ground_mat.shader = GROUND_SHADER
	ground_mat.set_shader_parameter("half_width", half_width)
	ground_mat.set_shader_parameter("color_a", ZoneTheme.color(zone, "ground_a", Color("#8F785C")))
	ground_mat.set_shader_parameter("color_b", ZoneTheme.color(zone, "ground_b", Color("#806B52")))
	ground_mat.set_shader_parameter("edge_color", ZoneTheme.color(zone, "edge", Color("#EDD18C")))
	ground.material_override = ground_mat
	ground.position = Vector3(0, 0, center_z)
	parent.add_child(ground)

	var curb_mat := Placeholders.mat(ZoneTheme.color(zone, "curb", Color("#9C978C")))
	for side in [-1.0, 1.0]:
		parent.add_child(Placeholders.part(Placeholders.box(Vector3(0.4, 0.4, total)), curb_mat, Vector3(side * (half_width + 0.2), 0.2, center_z)))

	_build_props(parent, length, half_width, seed_value, zone)
	if arena_d >= 0.0:
		_build_arena(parent, arena_d, half_width, zone)
	else:
		_build_finish(parent, length, half_width)


# --- Props ------------------------------------------------------------------------------------

## Each prop type is a list of parts; every part becomes one MultiMesh (one draw call).
static func _build_props(parent: Node3D, length: float, half_width: float, seed_value: int, zone: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var props: Array = zone.get("props", ["pines"])
	var color_a := ZoneTheme.color(zone, "prop_color_a", Color("#2F6B3A"))
	var color_b := ZoneTheme.color(zone, "prop_color_b", Color("#4E9A42"))
	var accent := ZoneTheme.color(zone, "edge", Color("#FF8A3D"))
	var batches := {}
	var z := START_Z
	while z > -(length + END_PAD):
		for side in [-1.0, 1.0]:
			for layer in 2:
				if rng.randf() > 0.8:
					continue
				var x: float = side * (half_width + 1.4 + layer * 5.0 + rng.randf() * 5.0)
				var at := Vector3(x, 0, z + rng.randf_range(-1.4, 1.4))
				var s := rng.randf_range(0.75, 1.5)
				var yaw := rng.randf() * TAU
				var tint := color_a.lerp(color_b, rng.randf())
				_add_prop(batches, String(props[rng.randi_range(0, props.size() - 1)]), at, s, yaw, tint, accent, rng)
		z -= 3.0
	for key: String in batches:
		var b: Dictionary = batches[key]
		parent.add_child(_multimesh(b["mesh"], b["material"], b["xf"], b["colors"]))


static func _add_prop(batches: Dictionary, type: String, at: Vector3, s: float, yaw: float, tint: Color, accent: Color, rng: RandomNumberGenerator) -> void:
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s)
	var tinted := Placeholders.vertex_color_mat()
	match type:
		"pines":
			_push(batches, "trunk", Placeholders.cylinder(0.12, 0.18, 1.0, 6), Placeholders.mat(Placeholders.WOOD), Transform3D(basis, at + Vector3(0, 0.5 * s, 0)), Color.WHITE)
			_push(batches, "crown", Placeholders.cylinder(0.0, 1.0, 2.2, 7), tinted, Transform3D(basis, at + Vector3(0, 1.9 * s, 0)), tint)
		"bushes":
			_push(batches, "bush", Placeholders.sphere(0.7), tinted, Transform3D(basis.scaled(Vector3(1.0, 0.65, 1.0)), at + Vector3(0, 0.35 * s, 0)), tint.lightened(0.1))
		"rocks":
			var rock_basis := basis.rotated(Vector3.RIGHT, rng.randf() * 0.6).scaled(Vector3(1.0, 0.6, 1.0))
			_push(batches, "rock", Placeholders.sphere(0.8), tinted, Transform3D(rock_basis, at + Vector3(0, 0.25 * s, 0)), tint.lightened(0.15))
		"dead_trees":
			_push(batches, "dead_trunk", Placeholders.cylinder(0.06, 0.14, 2.4, 5), tinted, Transform3D(basis, at + Vector3(0, 1.2 * s, 0)), tint)
			var branch := basis * Basis(Vector3.FORWARD, 0.9)
			_push(batches, "dead_branch", Placeholders.cylinder(0.03, 0.06, 1.0, 4), tinted, Transform3D(branch, at + basis * Vector3(0.3, 1.7, 0)), tint)
			var branch2 := basis * Basis(Vector3.FORWARD, -0.7)
			_push(batches, "dead_branch", Placeholders.cylinder(0.03, 0.06, 1.0, 4), tinted, Transform3D(branch2, at + basis * Vector3(-0.25, 1.3, 0)), tint)
		"tombstones":
			var tilt := basis.rotated(Vector3.RIGHT, rng.randf_range(-0.15, 0.15))
			_push(batches, "tomb", Placeholders.box(Vector3(0.55, 0.85, 0.16)), tinted, Transform3D(tilt, at + Vector3(0, 0.42 * s, 0)), tint.lightened(0.25))
		"crystals":
			var c_basis := basis.scaled(Vector3(0.5, 1.6, 0.5))
			_push(batches, "crystal", Placeholders.crystal_mesh(), Placeholders.mat(accent, 1.2), Transform3D(c_basis, at + Vector3(0, 0.8 * s, 0)), Color.WHITE)
		"lava_spires":
			_push(batches, "spire", Placeholders.cylinder(0.0, 0.7, 2.6, 6), tinted, Transform3D(basis, at + Vector3(0, 1.3 * s, 0)), tint)
			_push(batches, "spire_glow", Placeholders.cylinder(0.0, 0.18, 0.5, 6), Placeholders.mat(accent, 2.0), Transform3D(basis, at + Vector3(0, 2.45 * s, 0)), Color.WHITE)


static func _push(batches: Dictionary, key: String, mesh: Mesh, material: Material, xf: Transform3D, color: Color) -> void:
	if not batches.has(key):
		batches[key] = {"mesh": mesh, "material": material, "xf": [] as Array[Transform3D], "colors": [] as Array[Color]}
	(batches[key]["xf"] as Array[Transform3D]).append(xf)
	(batches[key]["colors"] as Array[Color]).append(color)


static func _multimesh(mesh: Mesh, material: Material, transforms: Array[Transform3D], colors: Array[Color]) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for k in transforms.size():
		mm.set_instance_transform(k, transforms[k])
		mm.set_instance_color(k, colors[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


# --- Finish / arena ---------------------------------------------------------------------------

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


## Arena: a line of braziers where the hero stops, and a stone dais under the boss.
static func _build_arena(parent: Node3D, arena_d: float, half_width: float, zone: Dictionary) -> void:
	var z := -arena_d
	var stone := Placeholders.mat(ZoneTheme.color(zone, "curb", Color("#9C978C")).darkened(0.15))
	var flame := Placeholders.mat(ZoneTheme.color(zone, "edge", Color("#FF8A3D")), 2.2)
	for side in [-1.0, 1.0]:
		for k in 3:
			var bz := z - k * 9.0
			parent.add_child(Placeholders.part(Placeholders.cylinder(0.3, 0.4, 1.4, 8), stone, Vector3(side * (half_width + 0.9), 0.7, bz)))
			parent.add_child(Placeholders.part(Placeholders.sphere(0.32), flame, Vector3(side * (half_width + 0.9), 1.55, bz)))
	var line := Placeholders.part(Placeholders.box(Vector3(half_width * 2.0, 0.04, 0.35)), flame, Vector3(0, 0.03, z))
	parent.add_child(line)
	var dais := Placeholders.part(Placeholders.cylinder(3.4, 3.8, 0.3, 24), stone, Vector3(0, 0.15, z - 20.0))
	parent.add_child(dais)
