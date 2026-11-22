extends Node3D
## Runtime scenery touch-ups on top of the hand-built canyon: red-flag breach line, scattered
## pebbles and dry grass, a few cacti, sandbags / crates / camo net around the nest, slow
## clouds, and wind-blown dust that drifts the way the bullets will. Purely decorative, no
## collisions, and nothing is placed on the central lanes where enemies walk.

const TerrainSampler := preload("res://scripts/terrain_sampler.gd")

@export var breach_z := -82.0

var _sampler = null
var _rng := RandomNumberGenerator.new()
var _dust: CPUParticles3D
var _cloud_material: ShaderMaterial
var _dust_material: StandardMaterial3D


func _ready() -> void:
	add_to_group("wind_listeners")
	add_to_group("night_listeners")
	_rng.seed = 90210
	var coll := get_node_or_null("../DesertCanyon/Terrain/TerrainCollision") as CollisionShape3D
	_sampler = TerrainSampler.new()
	_sampler.setup(coll)
	if _sampler.ok:
		_build_breach_line()
		_scatter_clutter()
		_build_cacti()
		_build_nest_props()
	_build_clouds()
	_build_dust()


## Called by the game manager with the wave's wind acceleration (m/s^2, + = towards +x).
func set_wind(accel_x: float) -> void:
	if _dust != null:
		_dust.gravity = Vector3(accel_x * 0.45, -0.03, 0.0)


## 0 = day, 1 = night. Clouds and floating dust must not glow in the dark.
func set_night_factor(t: float) -> void:
	if _cloud_material != null:
		_cloud_material.set_shader_parameter("cloud_color", Color(1.0, 0.92, 0.8).lerp(Color(0.1, 0.12, 0.19), t))
	if _dust_material != null:
		_dust_material.albedo_color = Color(0.92, 0.82, 0.62, 0.3).lerp(Color(0.2, 0.22, 0.3, 0.08), t)


# ---------------------------------------------------------------- helpers

func _mat(color: Color, rough: float = 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m


func _slope_at(x: float, z: float) -> float:
	var dx: float = _sampler.height_at(x + 2.0, z) - _sampler.height_at(x - 2.0, z)
	var dz: float = _sampler.height_at(x, z + 2.0) - _sampler.height_at(x, z - 2.0)
	return Vector2(dx, dz).length() / 4.0


func _add_mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)
	mi.position = pos
	mi.rotation = rot
	return mi


# ---------------------------------------------------------------- breach line

func _build_breach_line() -> void:
	var root := Node3D.new()
	root.name = "BreachLine"
	add_child(root)
	var wood := _mat(Color(0.3, 0.21, 0.13))
	var wire := _mat(Color(0.08, 0.08, 0.08), 0.5)
	var flag_mat := StandardMaterial3D.new()
	flag_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flag_mat.albedo_color = Color(0.82, 0.1, 0.07)
	flag_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.16, 2.6, 0.16)
	var flag_mesh := QuadMesh.new()
	flag_mesh.size = Vector2(1.2, 0.7)
	var prev := Vector3.ZERO
	var has_prev := false
	var x := -150.0
	while x <= 150.0:
		var y: float = _sampler.height_at(x, breach_z)
		if y < 40.0 and _slope_at(x, breach_z) < 0.7:
			var base := Vector3(x, y, breach_z)
			_add_mesh(root, post_mesh, wood, base + Vector3(0.0, 1.0, 0.0))
			_add_mesh(root, flag_mesh, flag_mat, base + Vector3(0.65, 2.0, 0.0))
			if has_prev and base.distance_to(prev) < 11.0:
				for h in [0.9, 1.6]:
					var a := prev + Vector3(0.0, h, 0.0)
					var b := base + Vector3(0.0, h, 0.0)
					var seg := BoxMesh.new()
					seg.size = Vector3(a.distance_to(b), 0.02, 0.02)
					var mid := (a + b) * 0.5
					_add_mesh(root, seg, wire, mid, Vector3(0.0, 0.0, atan2(b.y - a.y, b.x - a.x)))
			prev = base
			has_prev = true
		else:
			has_prev = false
		x += 10.0


# ---------------------------------------------------------------- clutter

func _scatter_clutter() -> void:
	var rock := SphereMesh.new()
	rock.radius = 0.5
	rock.height = 1.0
	rock.radial_segments = 8
	rock.rings = 4
	rock.material = _tinted_material()
	_scatter(rock, 520, Color(0.46, 0.37, 0.28), Color(0.7, 0.58, 0.44), Vector2(0.25, 1.2), 0.6, 0.0)

	var tuft := CylinderMesh.new()
	tuft.top_radius = 0.0
	tuft.bottom_radius = 0.11
	tuft.height = 0.4
	tuft.radial_segments = 5
	tuft.rings = 1
	tuft.material = _tinted_material()
	_scatter(tuft, 700, Color(0.5, 0.44, 0.22), Color(0.68, 0.6, 0.32), Vector2(0.7, 1.5), 1.0, 40.0)

	var shrub_scene := load("res://scenes/environment/components/desert_shrub.tscn") as PackedScene
	if shrub_scene != null:
		var placed := 0
		var tries := 0
		while placed < 34 and tries < 400:
			tries += 1
			var x := _rng.randf_range(-155.0, 155.0)
			var z := _rng.randf_range(-320.0, -40.0)
			if absf(x) < 40.0:
				continue
			var y: float = _sampler.height_at(x, z)
			if y > 40.0 or _slope_at(x, z) > 0.45:
				continue
			var shrub := shrub_scene.instantiate() as Node3D
			add_child(shrub)
			shrub.position = Vector3(x, y - 0.05, z)
			shrub.rotation.y = _rng.randf() * TAU
			shrub.scale = Vector3.ONE * _rng.randf_range(0.8, 1.5)
			placed += 1


func _tinted_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(1, 1, 1)
	m.roughness = 1.0
	return m


## Scatters many copies of a mesh over the valley floor with a MultiMesh.
## keep_clear_x: nothing is placed within that distance of the centre line (the enemy lanes).
func _scatter(mesh: Mesh, count: int, tint_a: Color, tint_b: Color, scale_range: Vector2, squash: float, keep_clear_x: float) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 8:
		tries += 1
		var x := _rng.randf_range(-160.0, 160.0)
		var z := _rng.randf_range(-330.0, -30.0)
		if absf(x) < keep_clear_x and z < -60.0:
			continue
		var y: float = _sampler.height_at(x, z)
		if y > 42.0 or _slope_at(x, z) > 0.6:
			continue
		var s := _rng.randf_range(scale_range.x, scale_range.y)
		var b3 := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * squash * _rng.randf_range(0.8, 1.2), s))
		mm.set_instance_transform(placed, Transform3D(b3, Vector3(x, y, z)))
		mm.set_instance_color(placed, tint_a.lerp(tint_b, _rng.randf()))
		placed += 1
	mm.visible_instance_count = placed
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)


# ---------------------------------------------------------------- cacti

func _build_cacti() -> void:
	var green := _mat(Color(0.24, 0.37, 0.2), 0.8)
	var placed := 0
	var tries := 0
	while placed < 16 and tries < 500:
		tries += 1
		var x := _rng.randf_range(55.0, 150.0) * (1.0 if _rng.randf() < 0.5 else -1.0)
		var z := _rng.randf_range(-300.0, -60.0)
		var y: float = _sampler.height_at(x, z)
		if y > 38.0 or _slope_at(x, z) > 0.4:
			continue
		var cactus := Node3D.new()
		add_child(cactus)
		cactus.position = Vector3(x, y - 0.1, z)
		cactus.rotation.y = _rng.randf() * TAU
		var h := _rng.randf_range(3.0, 5.2)
		var trunk := CapsuleMesh.new()
		trunk.radius = 0.24
		trunk.height = h
		_add_mesh(cactus, trunk, green, Vector3(0.0, h * 0.5, 0.0))
		var arms := 1 + _rng.randi() % 2
		for i in arms:
			var side := 1.0 if i == 0 else -1.0
			var ay := h * _rng.randf_range(0.4, 0.62)
			var reach := CapsuleMesh.new()
			reach.radius = 0.17
			reach.height = 1.0
			_add_mesh(cactus, reach, green, Vector3(side * 0.5, ay, 0.0), Vector3(0.0, 0.0, PI * 0.5))
			var up := CapsuleMesh.new()
			up.radius = 0.16
			up.height = _rng.randf_range(0.9, 1.5)
			_add_mesh(cactus, up, green, Vector3(side * 0.95, ay + up.height * 0.45, 0.0))
		placed += 1


# ---------------------------------------------------------------- nest dressing

func _build_nest_props() -> void:
	var root := Node3D.new()
	root.name = "NestProps"
	add_child(root)
	var sand := _mat(Color(0.6, 0.5, 0.34))
	var sand2 := _mat(Color(0.54, 0.45, 0.3))
	var wood := _mat(Color(0.34, 0.25, 0.15))
	var lid := _mat(Color(0.27, 0.2, 0.12))
	var olive := _mat(Color(0.2, 0.24, 0.15))
	var metal := _mat(Color(0.1, 0.1, 0.11), 0.4)
	metal.metallic = 0.7
	var bag := BoxMesh.new()
	bag.size = Vector3(0.7, 0.24, 0.38)
	# sandbag stacks tucked against the back wall
	for sx in [-7.5, 5.8]:
		for row in 3:
			for i in 4 - row:
				var p := Vector3(sx + i * 0.74 + row * 0.37, 0.12 + row * 0.24, 6.3)
				p.y += _sampler.height_at(p.x, p.z)
				_add_mesh(root, bag, sand if (i + row) % 2 == 0 else sand2, p, Vector3(0.0, _rng.randf_range(-0.07, 0.07), 0.0))
	# ammunition crates
	var crate := BoxMesh.new()
	crate.size = Vector3(0.8, 0.4, 0.42)
	var crate_lid := BoxMesh.new()
	crate_lid.size = Vector3(0.82, 0.04, 0.44)
	var gy: float = _sampler.height_at(0.0, 5.7)
	for c in [Vector3(-3.4, 0.0, 5.9), Vector3(-2.5, 0.0, 5.95), Vector3(-3.0, 0.4, 5.9), Vector3(3.2, 0.0, 5.9)]:
		_add_mesh(root, crate, wood, Vector3(c.x, gy + 0.2 + c.y, c.z), Vector3(0.0, _rng.randf_range(-0.12, 0.12), 0.0))
		_add_mesh(root, crate_lid, lid, Vector3(c.x, gy + 0.42 + c.y, c.z))
	# spotting scope on a tripod
	var tx := 8.2
	var tz := 5.2
	var ty: float = _sampler.height_at(tx, tz)
	var leg := CylinderMesh.new()
	leg.top_radius = 0.012
	leg.bottom_radius = 0.016
	leg.height = 1.1
	for a in [0.0, 2.094, 4.188]:
		var off := Vector3(cos(a) * 0.28, 0.0, sin(a) * 0.28)
		var tilt := Vector3(-sin(a) * 0.27, 0.0, -cos(a) * 0.27)
		_add_mesh(root, leg, metal, Vector3(tx + off.x * 0.5, ty + 0.55, tz + off.z * 0.5), Vector3(tilt.x, 0.0, tilt.z))
	var tube := CylinderMesh.new()
	tube.top_radius = 0.035
	tube.bottom_radius = 0.045
	tube.height = 0.38
	_add_mesh(root, tube, metal, Vector3(tx, ty + 1.16, tz), Vector3(PI * 0.5 - 0.12, 0.0, 0.0))
	# camouflage net over the back-left corner
	var net := PlaneMesh.new()
	net.size = Vector2(4.6, 3.4)
	var net_mat := _mat(Color(0.21, 0.26, 0.15), 1.0)
	net_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var ny: float = _sampler.height_at(-7.0, 4.6)
	_add_mesh(root, net, net_mat, Vector3(-7.4, ny + 2.7, 4.6), Vector3(0.12, 0.0, 0.05))
	var pole := CylinderMesh.new()
	pole.top_radius = 0.04
	pole.bottom_radius = 0.045
	pole.height = 2.7
	for pp in [Vector3(-9.5, 0.0, 3.0), Vector3(-5.3, 0.0, 3.0), Vector3(-9.5, 0.0, 6.2), Vector3(-5.3, 0.0, 6.2)]:
		_add_mesh(root, pole, olive, Vector3(pp.x, ny + 1.35, pp.z))


# ---------------------------------------------------------------- sky and air

func _build_clouds() -> void:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = noise
	var shader := Shader.new()
	shader.code = "shader_type spatial;\nrender_mode unshaded, cull_disabled, depth_draw_never;\nuniform sampler2D noise_tex : repeat_enable;\nuniform vec3 cloud_color = vec3(1.0, 0.92, 0.8);\nuniform float coverage = 0.5;\nvoid fragment() {\n\tvec2 uv = UV * 3.0 + vec2(0.004, 0.0015) * TIME;\n\tfloat n = texture(noise_tex, uv).r * 0.65 + texture(noise_tex, uv * 2.7 + vec2(0.31)).r * 0.35;\n\tfloat a = smoothstep(coverage, coverage + 0.2, n);\n\tfloat edge = 1.0 - smoothstep(0.22, 0.5, length(UV - vec2(0.5)));\n\tALBEDO = cloud_color;\n\tALPHA = a * edge * 0.7;\n}\n"
	_cloud_material = ShaderMaterial.new()
	_cloud_material.shader = shader
	_cloud_material.set_shader_parameter("noise_tex", tex)
	var plane := PlaneMesh.new()
	plane.size = Vector2(9000.0, 9000.0)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = _cloud_material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.position = Vector3(0.0, 850.0, -500.0)


func _build_dust() -> void:
	_dust = CPUParticles3D.new()
	_dust.amount = 260
	_dust.lifetime = 6.0
	_dust.local_coords = false
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_dust.emission_box_extents = Vector3(50.0, 14.0, 60.0)
	_dust.direction = Vector3.UP
	_dust.spread = 180.0
	_dust.initial_velocity_min = 0.0
	_dust.initial_velocity_max = 0.4
	_dust.damping_min = 0.15
	_dust.damping_max = 0.15
	_dust.gravity = Vector3(0.0, -0.03, 0.0)
	_dust.scale_amount_min = 0.6
	_dust.scale_amount_max = 1.6
	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.14)
	_dust_material = StandardMaterial3D.new()
	_dust_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dust_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dust_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_dust_material.albedo_color = Color(0.92, 0.82, 0.62, 0.3)
	quad.material = _dust_material
	_dust.mesh = quad
	_dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_dust)
	_dust.position = Vector3(0.0, 58.0, -35.0)
	_dust.emitting = true
