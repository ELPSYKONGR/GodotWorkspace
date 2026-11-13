extends Node3D
## 由配置构建真实三维刚体场景，并提供碰撞事件与物理验证报告。

signal event_logged(event: Dictionary)

var settings: Dictionary = {}
var bodies: Array[RigidBody3D] = []
var elapsed := 0.0
var collision_events := 0
var escaped := 0
var max_speed := 0.0
var _configured := false
var _built := false
var _contact_keys: Dictionary = {}


## 保存场景配置，并在节点已进入场景树时启动构建。
func setup(config: Dictionary) -> void:
	settings = config.duplicate(true)
	_configured = true
	if is_inside_tree():
		_build_once()


## 等待配置就绪后构建场景，兼容先加入节点再调用 setup 的方式。
func _ready() -> void:
	if _configured:
		_build_once()
	else:
		call_deferred("_build_once")


## 创建统一粗糙度的物体材质，保持各形状的视觉风格一致。
func _material(color: Color, metallic: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = 0.35
	return material


## 创建显示尺寸与碰撞尺寸一致的静态地面、挡板或斜坡。
func _static_box(label: String, at: Vector3, size: Vector3, color: Color, tilt: float = 0.0) -> void:
	var body := StaticBody3D.new()
	body.name = label
	body.position = at
	body.rotation.z = tilt
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _material(color)
	body.add_child(mesh)
	add_child(body)


## 按配置一次性创建灯光、相机、容器以及交错分布的球和长方体。
func _build_once() -> void:
	if _built:
		return
	_built = true
	var environment := WorldEnvironment.new()
	var world := Environment.new()
	world.background_mode = Environment.BG_COLOR
	world.background_color = Color("101827")
	world.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.ambient_light_color = Color("b9c8e3")
	world.ambient_light_energy = 0.65
	environment.environment = world
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-58.0, -25.0, 0.0)
	light.light_energy = 1.5
	light.shadow_enabled = true
	add_child(light)
	var camera := Camera3D.new()
	camera.position = Vector3(13.0, 15.0, 20.0)
	camera.fov = 46.0
	camera.size = float(settings.get("camera_size", 23.0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL if settings.get("projection", "orthogonal") == "orthogonal" else Camera3D.PROJECTION_PERSPECTIVE
	add_child(camera)
	camera.look_at(Vector3(0.0, 2.3, 0.0))
	camera.current = true
	_static_box("Floor", Vector3(0.0, -0.4, 0.0), Vector3(9.0, 0.5, 7.0), Color("263e57"))
	_static_box("LeftWall", Vector3(-4.6, 0.6, 0.0), Vector3(0.3, 1.5, 7.0), Color("3c6880"))
	_static_box("RightWall", Vector3(4.6, 0.6, 0.0), Vector3(0.3, 1.5, 7.0), Color("3c6880"))
	_static_box("BackWall", Vector3(0.0, 0.6, -3.6), Vector3(9.5, 1.5, 0.3), Color("3c6880"))
	_static_box("FrontWall", Vector3(0.0, 0.1, 3.6), Vector3(9.5, 0.5, 0.3), Color("3c6880"))
	if bool(settings.get("ramp", true)):
		_static_box("Ramp", Vector3(-1.2, 0.8, -0.6), Vector3(4.2, 0.25, 2.0), Color("526a7d"), -0.22)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(settings.get("seed", 20261113))
	var count := clampi(int(settings.get("count", 12)), 2, 24)
	var palette: Array = settings.get("palette", ["#2ed5ab", "#ffb45c", "#77aaff", "#d98eff"])
	if palette.is_empty():
		palette = ["#2ed5ab"]
	for index in range(count):
		var body := RigidBody3D.new()
		body.name = "Object_%02d" % index
		body.set_meta("probe_id", index)
		body.position = Vector3((index % 4 - 1.5) * 1.3, 3.5 + (index / 4) * 1.3, -1.5 + (index % 3) * 1.4)
		body.rotation = Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.4, 0.4), rng.randf_range(-0.2, 0.2))
		body.linear_velocity = Vector3(rng.randf_range(-0.5, 0.5), 0.0, rng.randf_range(-0.4, 0.4))
		body.contact_monitor = true
		body.max_contacts_reported = 16
		body.continuous_cd = true
		body.gravity_scale = float(settings.get("gravity", 9.8)) / float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
		var physics := PhysicsMaterial.new()
		physics.bounce = clampf(float(settings.get("restitution", 0.65)), 0.0, 1.0)
		physics.friction = 0.45
		body.physics_material_override = physics
		body.linear_damp = 0.05
		body.angular_damp = 0.08
		var collider := CollisionShape3D.new()
		var mesh := MeshInstance3D.new()
		if index % 2 == 0:
			var shape := SphereShape3D.new()
			shape.radius = 0.44
			collider.shape = shape
			var sphere := SphereMesh.new()
			sphere.radius = 0.44
			sphere.height = 0.88
			mesh.mesh = sphere
		else:
			var shape := BoxShape3D.new()
			shape.size = Vector3(0.85, 0.65, 0.75)
			collider.shape = shape
			var box := BoxMesh.new()
			box.size = shape.size
			mesh.mesh = box
		mesh.material_override = _material(Color(str(palette[index % palette.size()])), 0.15)
		body.add_child(collider)
		body.add_child(mesh)
		body.body_entered.connect(_on_contact.bind(index))
		bodies.append(body)
		add_child(body)


## 记录真实接触事件，并合并同一物理帧中同一对物体的重复通知。
func _on_contact(other: Node, object_id: int) -> void:
	var other_id := int(other.get_meta("probe_id", -1))
	var pair := "%d:%s" % [object_id, other.name]
	if other_id >= 0:
		pair = "%d:%d" % [mini(object_id, other_id), maxi(object_id, other_id)]
	var key := "%d:%s" % [Engine.get_physics_frames(), pair]
	if _contact_keys.has(key):
		return
	_contact_keys[key] = true
	collision_events += 1
	event_logged.emit({"type": "collision", "time": elapsed, "body_id": object_id, "other_id": other_id, "other": str(other.name)})


## 每个物理步累计运行时间、最大速度与跌出容器的物体数量。
func _physics_process(delta: float) -> void:
	elapsed += delta
	for body in bodies:
		max_speed = maxf(max_speed, body.linear_velocity.length())
		if body.position.y < -2.0 and not body.has_meta("escaped"):
			body.set_meta("escaped", true)
			escaped += 1


## 汇总物体位置、接触次数与逃逸情况，供自动验证及导出记录使用。
func get_report() -> Dictionary:
	var positions: Array = []
	for body in bodies:
		positions.append({"id": int(body.get_meta("probe_id")), "position": [body.position.x, body.position.y, body.position.z]})
	return {"dimension": "3d", "physics": "Godot RigidBody3D", "created": bodies.size(), "active": bodies.size(), "collision_events": collision_events, "escaped": escaped, "max_speed": max_speed, "projection": str(settings.get("projection", "orthogonal")), "positions": positions}
