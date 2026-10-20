class_name Placeholders
extends RefCounted
## Code-built low-poly placeholder models. Meshes and materials are cached and shared, so a crowd
## of goblins costs a handful of resources. When real CC0 models arrive, swap these factories;
## callers only expect a Node3D facing +Z (toward the camera) for enemies and -Z for the hero.

const SKIN := Color("#F2C9A0")
const WOOD := Color("#7A5230")
const GOLD := Color("#E8B83A")

static var _materials: Dictionary = {}
static var _meshes: Dictionary = {}


# --- Shared resources -------------------------------------------------------------------------

static func mat(color: Color, emission := 0.0) -> StandardMaterial3D:
	var key := "solid|%s|%s" % [color.to_html(), emission]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	_materials[key] = m
	return m


## Unshaded translucent material used as material_overlay for hit flashes.
static func overlay(color: Color) -> StandardMaterial3D:
	var key := "overlay|%s" % color.to_html()
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	_materials[key] = m
	return m


static func vertex_color_mat() -> StandardMaterial3D:
	var key := "vertex_color"
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	_materials[key] = m
	return m


static func capsule(radius: float, height: float) -> CapsuleMesh:
	var key := "capsule|%s|%s" % [radius, height]
	if not _meshes.has(key):
		var m := CapsuleMesh.new()
		m.radius = radius
		m.height = height
		m.radial_segments = 12
		m.rings = 3
		_meshes[key] = m
	return _meshes[key]


static func sphere(radius: float) -> SphereMesh:
	var key := "sphere|%s" % radius
	if not _meshes.has(key):
		var m := SphereMesh.new()
		m.radius = radius
		m.height = radius * 2.0
		m.radial_segments = 12
		m.rings = 6
		_meshes[key] = m
	return _meshes[key]


## top_radius 0 makes a cone.
static func cylinder(top_radius: float, bottom_radius: float, height: float, segments := 10) -> CylinderMesh:
	var key := "cyl|%s|%s|%s|%s" % [top_radius, bottom_radius, height, segments]
	if not _meshes.has(key):
		var m := CylinderMesh.new()
		m.top_radius = top_radius
		m.bottom_radius = bottom_radius
		m.height = height
		m.radial_segments = segments
		m.rings = 1
		_meshes[key] = m
	return _meshes[key]


static func box(size: Vector3) -> BoxMesh:
	var key := "box|%s" % size
	if not _meshes.has(key):
		var m := BoxMesh.new()
		m.size = size
		_meshes[key] = m
	return _meshes[key]


static func part(mesh: Mesh, material: Material, pos: Vector3, rot_degrees := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation_degrees = rot_degrees
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		collect_meshes(child, out)


# --- Common pieces ----------------------------------------------------------------------------

static func blob_shadow(radius: float) -> MeshInstance3D:
	var mi := part(cylinder(radius, radius, 0.02, 16), overlay(Color(0, 0, 0, 0.32)), Vector3(0, 0.02, 0))
	mi.name = "Shadow"
	return mi


static func label(font_size := 64, pixel_size := 0.006) -> Label3D:
	var l := Label3D.new()
	l.font_size = font_size
	l.pixel_size = pixel_size
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.outline_size = 14
	l.outline_modulate = Color(0, 0, 0, 0.9)
	l.render_priority = 10
	l.outline_render_priority = 9
	return l


# --- Characters -------------------------------------------------------------------------------

## Hero faces -Z. Has a child named "Orb" used as the projectile muzzle.
static func make_wizard(robe: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	var robe_mat := mat(robe)
	var dark := mat(robe.darkened(0.4))
	root.add_child(part(capsule(0.34, 1.15), robe_mat, Vector3(0, 0.6, 0)))
	root.add_child(part(cylinder(0.36, 0.36, 0.09), mat(GOLD), Vector3(0, 0.72, 0)))
	root.add_child(part(sphere(0.24), mat(SKIN), Vector3(0, 1.33, 0)))
	root.add_child(part(cylinder(0.44, 0.44, 0.05, 14), dark, Vector3(0, 1.47, 0)))
	root.add_child(part(cylinder(0.0, 0.3, 0.6), dark, Vector3(0, 1.78, 0.05), Vector3(-12, 0, 0)))
	root.add_child(part(cylinder(0.035, 0.035, 1.5, 6), mat(WOOD), Vector3(0.4, 0.85, -0.1)))
	var orb := part(sphere(0.13), mat(Color("#9FE8FF"), 2.5), Vector3(0.4, 1.66, -0.1))
	orb.name = "Orb"
	root.add_child(orb)
	return root


## Enemies face +Z (toward the hero/camera).
static func make_goblin(skin: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	var skin_mat := mat(skin)
	root.add_child(part(capsule(0.3, 0.85), mat(Color("#6B4A2E")), Vector3(0, 0.45, 0)))
	root.add_child(part(sphere(0.3), skin_mat, Vector3(0, 1.05, 0)))
	root.add_child(part(cylinder(0.0, 0.1, 0.36, 6), skin_mat, Vector3(-0.34, 1.12, 0), Vector3(0, 0, 70)))
	root.add_child(part(cylinder(0.0, 0.1, 0.36, 6), skin_mat, Vector3(0.34, 1.12, 0), Vector3(0, 0, -70)))
	var eye := mat(Color("#FFE14D"), 1.5)
	root.add_child(part(sphere(0.06), eye, Vector3(-0.11, 1.1, 0.26)))
	root.add_child(part(sphere(0.06), eye, Vector3(0.11, 1.1, 0.26)))
	root.add_child(part(cylinder(0.07, 0.11, 0.6, 6), mat(WOOD), Vector3(0.38, 0.62, 0.12), Vector3(35, 0, 0)))
	return root


static func make_enemy(def: Dictionary) -> Node3D:
	var tint := Color(String(def.get("color", "#6BBF59")))
	match String(def.get("model", "goblin")):
		_:
			return make_goblin(tint)


static func make_hero(def: Dictionary) -> Node3D:
	var tint := Color(String(def.get("color", "#3F6FD8")))
	match String(def.get("model", "wizard")):
		_:
			return make_wizard(tint)
