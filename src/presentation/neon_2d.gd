extends Node2D
## Two instanced batches provide sphere shading and glow without per-ball lights or nodes.
const BallShader = preload("res://src/presentation/neon_ball.gdshader")
const WallShader = preload("res://src/presentation/neon_wall.gdshader")
var enabled := false
var settings: Dictionary = {}
var balls: MultiMeshInstance2D
var walls: MultiMeshInstance2D

## Batch order keeps solid balls above their glowing obstacles.
func _ready() -> void:
	walls = _batch(WallShader)
	balls = _batch(BallShader)
	balls.z_index = 1

## Own one shared quad and material per primitive type, never per object.
func _batch(shader: Shader) -> MultiMeshInstance2D:
	var batch := MultiMeshInstance2D.new()
	batch.multimesh = MultiMesh.new()
	batch.multimesh.transform_format = MultiMesh.TRANSFORM_2D
	batch.multimesh.use_colors = true
	batch.multimesh.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	batch.multimesh.mesh = quad
	batch.material = ShaderMaterial.new()
	batch.material.shader = shader
	add_child(batch)
	return batch

## Changing visual controls only updates uniforms; geometry and physics remain intact.
func configure(value: Dictionary) -> void:
	settings = value.duplicate(true)
	enabled = bool(settings.get("enabled", false))
	visible = enabled
	for batch in [balls, walls]:
		batch.material.set_shader_parameter("glow_width", float(settings.get("glow_width", 18)))
		batch.material.set_shader_parameter("glow_strength", float(settings.get("glow_strength", 0.9)))
	balls.material.set_shader_parameter("highlight_size", float(settings.get("highlight_size", 0.3)))
	balls.material.set_shader_parameter("highlight_strength", float(settings.get("highlight_strength", 1.1)))

## Grow storage geometrically and update only the live instances at actual body poses.
func present(ball_items: Array, wall_items: Array) -> void:
	if not enabled: return
	_update(balls, ball_items, true)
	_update(walls, wall_items, false)

## Custom data stores sphere radius/quad extent or the wall's exact half dimensions.
func _update(batch: MultiMeshInstance2D, items: Array, spherical: bool) -> void:
	var mesh := batch.multimesh
	if mesh.instance_count < items.size(): mesh.instance_count = maxi(items.size(), maxi(64, mesh.instance_count * 2))
	mesh.visible_instance_count = items.size()
	var padding := float(settings.get("glow_width", 18)) + 1.0
	for index in items.size():
		var item: Dictionary = items[index]
		var half: Vector2 = Vector2.ONE * float(item["size"]) if spherical else item["half_size"]
		var extent := half + Vector2.ONE * padding
		mesh.set_instance_transform_2d(index, Transform2D(float(item.get("rotation", 0)), extent, 0, item["position"]))
		mesh.set_instance_color(index, item["color"])
		mesh.set_instance_custom_data(index, Color(half.x, extent.x if spherical else half.y, 0, 0))

