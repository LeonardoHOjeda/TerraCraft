class_name MiningController
extends Node

var player: Player
var camera: Camera3D
var world: World
var hotbar_controller: HotbarController
var interaction_state: PlayerInteractionState
var mining_cracks: MeshInstance3D
var interaction_distance: float
var cracks_texture: Texture2D
var mining_progress := 0.0
var mining_block_position: Vector3i
var is_mining := false

func setup(new_player: Player, new_camera: Camera3D, new_world: World, new_hotbar_controller: HotbarController, new_interaction_state: PlayerInteractionState, cracks: MeshInstance3D, distance: float, texture: Texture2D) -> void:
	player = new_player
	camera = new_camera
	world = new_world
	hotbar_controller = new_hotbar_controller
	interaction_state = new_interaction_state
	mining_cracks = cracks
	interaction_distance = distance
	cracks_texture = texture
	mining_cracks.visible = false
	build_mining_cracks_mesh()

func process(delta: float) -> void:
	if interaction_state.can_interact_with_blocks() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		process_mining(delta)
	else:
		reset_mining()

func process_mining(delta: float) -> void:
	var target := get_target_block()
	if target.is_empty():
		reset_mining()
		return
	var block_position: Vector3i = target["position"]
	var block: int = target["block"]
	if block == BlockRegistry.Block.AIR or block == BlockRegistry.Block.BEDROCK or not can_mine_block(block):
		reset_mining()
		return
	if not is_mining or mining_block_position != block_position:
		mining_block_position = block_position
		mining_progress = 0.0
		is_mining = true
	var hardness := BlockRegistry.get_hardness(block)
	mining_progress += (get_mining_speed_for_block(block) / hardness) * delta
	update_mining_cracks(block_position)
	if mining_progress >= 1.0:
		break_target_block(target)
		reset_mining()

func get_mining_speed_for_block(block: int) -> float:
	if hotbar_controller == null:
		return 1.0
	var selected_item: int = hotbar_controller.get_selected_item()
	var tool_type := ItemRegistry.get_tool_type(selected_item)
	var preferred_tool := BlockRegistry.get_preferred_tool(block)
	if preferred_tool == ItemRegistry.ToolType.NONE:
		return 1.0
	if tool_type != preferred_tool:
		return 0.35
	return ItemRegistry.get_mining_speed(selected_item)

func get_target_block() -> Dictionary:
	var from := camera.global_position
	var to := from + -camera.global_transform.basis.z * interaction_distance
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = 1
	var result := player.get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return {}
	var hit_position: Vector3 = result.position
	var hit_normal: Vector3 = result.normal
	var block_position := Vector3i(floor(hit_position.x - hit_normal.x * 0.01), floor(hit_position.y - hit_normal.y * 0.01), floor(hit_position.z - hit_normal.z * 0.01))
	var chunk := get_chunk_from_hit(result.collider)
	if chunk == null:
		return {}
	var local_position := block_position - Vector3i(chunk.global_position)
	return {"position": block_position, "local_position": local_position, "chunk": chunk, "block": chunk.get_block_local(local_position)}

func get_chunk_from_hit(collider: Object) -> Chunk:
	if collider != null and collider.has_meta("chunk"):
		return collider.get_meta("chunk") as Chunk
	return null

func break_target_block(target: Dictionary) -> void:
	var chunk: Chunk = target["chunk"]
	var block_position: Vector3i = target["position"]
	var local_position: Vector3i = target["local_position"]
	var broken_block := chunk.remove_block(local_position)
	if broken_block == BlockRegistry.Block.AIR:
		return
	world.rebuild_chunk_and_neighbors(chunk, local_position)
	var dropped_item := ItemRegistry.get_drop(broken_block)
	if dropped_item == ItemRegistry.Item.NONE:
		return
	var drop_offset := Vector3(randf_range(-0.18, 0.18), 0.5, randf_range(-0.18, 0.18))
	world.spawn_item(dropped_item, Vector3(block_position) + Vector3(0.5, 0.0, 0.5) + drop_offset)

func reset_mining() -> void:
	mining_progress = 0.0
	is_mining = false
	mining_cracks.visible = false

func update_mining_cracks(block_position: Vector3i) -> void:
	if cracks_texture == null:
		mining_cracks.visible = false
		return
	var stage := clampi(floori(mining_progress * 9.0), 0, 8)
	var material := StandardMaterial3D.new()
	material.albedo_texture = cracks_texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var stage_width := 1.0 / 9.0
	material.uv1_scale = Vector3(stage_width, 1.0, 1.0)
	material.uv1_offset = Vector3(stage * stage_width, 0.0, 0.0)
	mining_cracks.material_override = material
	mining_cracks.global_position = Vector3(block_position) + Vector3(0.5, 0.5, 0.5)
	mining_cracks.visible = true

func build_mining_cracks_mesh() -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var half := 0.5075
	add_crack_face(vertices, normals, uvs, indices, Vector3(-half, -half, half), Vector3(half, -half, half), Vector3(half, half, half), Vector3(-half, half, half), Vector3(0, 0, 1))
	add_crack_face(vertices, normals, uvs, indices, Vector3(half, -half, -half), Vector3(-half, -half, -half), Vector3(-half, half, -half), Vector3(half, half, -half), Vector3(0, 0, -1))
	add_crack_face(vertices, normals, uvs, indices, Vector3(-half, -half, -half), Vector3(-half, -half, half), Vector3(-half, half, half), Vector3(-half, half, -half), Vector3(-1, 0, 0))
	add_crack_face(vertices, normals, uvs, indices, Vector3(half, -half, half), Vector3(half, -half, -half), Vector3(half, half, -half), Vector3(half, half, half), Vector3(1, 0, 0))
	add_crack_face(vertices, normals, uvs, indices, Vector3(-half, half, half), Vector3(half, half, half), Vector3(half, half, -half), Vector3(-half, half, -half), Vector3(0, 1, 0))
	add_crack_face(vertices, normals, uvs, indices, Vector3(-half, -half, -half), Vector3(half, -half, -half), Vector3(half, -half, half), Vector3(-half, -half, half), Vector3(0, -1, 0))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mining_cracks.mesh = mesh

func add_crack_face(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	var start := vertices.size()
	vertices.append_array([a, b, c, d])
	normals.append_array([normal, normal, normal, normal])
	uvs.append_array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
	indices.append_array([start, start + 1, start + 2, start, start + 2, start + 3])

func can_mine_block(block: int) -> bool:
	var required_tier := BlockRegistry.get_required_mining_tier(block)
	if required_tier <= 0:
		return true
	if hotbar_controller == null:
		return false
	var selected_item: int = hotbar_controller.get_selected_item()
	if ItemRegistry.get_tool_type(selected_item) != ItemRegistry.ToolType.PICKAXE:
		return false
	return ItemRegistry.get_mining_tier(selected_item) >= required_tier
