class_name Geo3D
extends RefCounted
## Shared 3D primitives and materials for the prototype.
## One set of meshes/materials is reused by every ant, spider and prop.
##
## Visual direction (after Empires of the Undergrowth): glossy chitin with a
## specular sheen, readable silhouettes, natural-but-dramatic lighting.

static var _done := false
static var sphere: SphereMesh
static var cyl: CylinderMesh
static var leg_mesh: CylinderMesh # tapered, for insect legs
static var box: BoxMesh
static var ring_mesh: TorusMesh # flat selection / marker ring
static var _mats := {}


static func ensure() -> void:
	if _done:
		return
	_done = true
	sphere = SphereMesh.new()
	sphere.radial_segments = 10
	sphere.rings = 6
	sphere.radius = 0.5
	sphere.height = 1.0
	cyl = CylinderMesh.new()
	cyl.radial_segments = 8
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.5
	cyl.height = 1.0
	leg_mesh = CylinderMesh.new()
	leg_mesh.radial_segments = 6
	leg_mesh.top_radius = 0.55
	leg_mesh.bottom_radius = 0.28
	leg_mesh.height = 1.0
	box = BoxMesh.new()
	box.size = Vector3(1, 1, 1)
	ring_mesh = TorusMesh.new()
	ring_mesh.inner_radius = 0.44
	ring_mesh.outer_radius = 0.52
	ring_mesh.rings = 24
	ring_mesh.ring_segments = 8


static func mat(name: String, color: Color) -> StandardMaterial3D:
	ensure()
	if not _mats.has(name):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.9
		_mats[name] = m
	return _mats[name]


## Glossy insect-chitin material: low roughness + strong specular so ants
## catch the sun like real exoskeletons.
static func chitin(name: String, color: Color, rough: float = 0.28) -> StandardMaterial3D:
	ensure()
	if not _mats.has(name):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = rough
		m.metallic = 0.12
		m.metallic_specular = 0.9
		_mats[name] = m
	return _mats[name]


## Emissive material for markers, selection rings, glows.
static func glow(name: String, color: Color, energy: float = 1.6) -> StandardMaterial3D:
	ensure()
	if not _mats.has(name):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = energy
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mats[name] = m
	return _mats[name]


static func part(parent: Node3D, mesh: Mesh, pos: Vector3, scl: Vector3, material: Material) -> MeshInstance3D:
	ensure()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.scale = scl
	if material != null:
		mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Flat ring that faces the camera (lies in the slab's XY plane).
static func flat_ring(parent: Node3D, radius: float, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = ring_mesh
	mi.rotation_degrees.x = 90.0
	mi.scale = Vector3(radius, radius, radius)
	if material != null:
		mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
