class_name Chunk
extends MeshInstance3D

const SIZE_XZ := ChunkData.SIZE_XZ
const HEIGHT := ChunkData.HEIGHT
const COLLISION_SECTION_HEIGHT := ChunkMesher.COLLISION_SECTION_HEIGHT
const COLLISION_SECTION_COUNT := ChunkMesher.COLLISION_SECTION_COUNT

var world: World

var chunk_position := Vector2i.ZERO

var data := ChunkData.new()
var generator := ChunkGenerator.new()
var mesher := ChunkMesher.new()
var collision_builder := ChunkCollisionBuilder.new()
var collision_section_mesh_data: Array[Dictionary] = []
var special_blocks_root: Node3D
var special_block_nodes: Dictionary = {}


func _ready() -> void:
	special_blocks_root = Node3D.new()
	special_blocks_root.name = "SpecialBlocks"
	add_child(special_blocks_root)


static func from_collider(collider: Object) -> Chunk:
	if collider != null and collider.has_meta("chunk"):
		return collider.get_meta("chunk") as Chunk
	return null


func is_valid_local_position(local_position: Vector3i) -> bool:
	return data.is_valid_position(local_position)


func world_to_local(world_position: Vector3i) -> Vector3i:
	return world_position - Vector3i(global_position)


func local_to_world(local_position: Vector3i) -> Vector3i:
	return Vector3i(global_position) + local_position


func get_block_local(local_position: Vector3i) -> int:
	return get_block(local_position)


func remove_block_local(local_position: Vector3i) -> int:
	return remove_block(local_position)


func place_block_local(local_position: Vector3i, block: int) -> bool:
	return place_block(local_position, block)


func set_block_local_if_empty(local_position: Vector3i, block: int) -> bool:
	return set_block_without_rebuild(local_position, block)


func rebuild_representation() -> void:
	rebuild_mesh()


func get_affected_neighbor_positions(local_position: Vector3i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	if local_position.x == 0:
		neighbors.append(chunk_position + Vector2i(-1, 0))
	elif local_position.x == SIZE_XZ - 1:
		neighbors.append(chunk_position + Vector2i(1, 0))
	if local_position.z == 0:
		neighbors.append(chunk_position + Vector2i(0, -1))
	elif local_position.z == SIZE_XZ - 1:
		neighbors.append(chunk_position + Vector2i(0, 1))
	return neighbors


func initialize(
	new_world: World,
	new_chunk_position: Vector2i,
	new_continental_noise: FastNoiseLite,
	new_detail_noise: FastNoiseLite,
	new_biome_noise: FastNoiseLite,
	new_cave_noise: FastNoiseLite,
	new_coal_noise: FastNoiseLite,
	new_iron_noise: FastNoiseLite,
	new_copper_noise: FastNoiseLite,
	new_tin_noise: FastNoiseLite,
	new_gold_noise: FastNoiseLite,
	new_tungsten_noise: FastNoiseLite,
	new_platinum_noise: FastNoiseLite,
	new_terrain_height: int,
	new_base_height: int
) -> void:
	world = new_world
	chunk_position = new_chunk_position

	generator.populate(
		data,
		chunk_position,
		new_continental_noise,
		new_detail_noise,
		new_biome_noise,
		new_cave_noise,
		new_coal_noise,
		new_iron_noise,
		new_copper_noise,
		new_tin_noise,
		new_gold_noise,
		new_tungsten_noise,
		new_platinum_noise,
		new_terrain_height,
		new_base_height
	)
	rebuild_special_blocks()


func initialize_from_data(new_world: World, new_chunk_position: Vector2i, new_data: ChunkData) -> void:
	world = new_world
	chunk_position = new_chunk_position
	data = new_data
	rebuild_special_blocks()


func get_block(position: Vector3i) -> int:
	return data.get_block(position)


func rebuild_mesh() -> void:
	build_mesh_only()
	build_collision_only()


func build_mesh_only() -> void:
	mesh = mesher.build(data, Callable(self, "get_neighbor_block"))
	collision_section_mesh_data = mesher.last_collision_sections


func apply_mesh_data(mesh_data: Dictionary) -> void:
	collision_section_mesh_data = mesh_data["collision_sections"]
	mesh = mesher.create_mesh(mesh_data)


func build_collision_only() -> void:
	collision_builder.rebuild(self, self)


func build_collision_section(section: int) -> void:
	collision_builder.rebuild_section(self, section, get_collision_section_mesh_data(section))


func get_collision_section_mesh_data(section: int) -> Dictionary:
	if section < 0 or section >= collision_section_mesh_data.size():
		return {
			"vertices": PackedVector3Array(),
			"normals": PackedVector3Array(),
			"uvs": PackedVector2Array(),
			"indices": PackedInt32Array(),
		}
	return collision_section_mesh_data[section]


func remove_block(position: Vector3i) -> int:
	if not data.is_valid_position(position):
		return BlockRegistry.Block.AIR

	var block: int = data.get_block(position)

	if block == BlockRegistry.Block.AIR:
		return BlockRegistry.Block.AIR

	if block == BlockRegistry.Block.BEDROCK:
		return BlockRegistry.Block.AIR

	data.set_block(position, BlockRegistry.Block.AIR)
	remove_special_block(position)

	return block

func place_block(position: Vector3i, block: int) -> bool:
	if not data.is_valid_position(position):
		return false

	if data.get_block(position) != BlockRegistry.Block.AIR:
		return false

	data.set_block(position, block)
	sync_special_block(position)

	return true


func place_oriented_block_local(position: Vector3i, block: int, support_direction: Vector3i) -> bool:
	if not data.is_valid_position(position) or data.get_block(position) != BlockRegistry.Block.AIR:
		return false
	if world != null:
		world.set_special_block_support(chunk_position, position, support_direction)
	data.set_block(position, block)
	sync_special_block(position)
	return true


func get_surface_height(x: int, z: int) -> int:
	for y in range(HEIGHT - 1, -1, -1):
		var block: int = data.get_block(Vector3i(x, y, z))

		if (
			block == BlockRegistry.Block.GRASS
			or block == BlockRegistry.Block.SAND
		):
			return y

	return -1



func set_block_without_rebuild(position: Vector3i, block: int) -> bool:
	if not data.is_valid_position(position):
		return false

	if data.get_block(position) != BlockRegistry.Block.AIR:
		return false

	data.set_block(position, block)
	sync_special_block(position)
	return true


func rebuild_special_blocks() -> void:
	for node in special_block_nodes.values():
		(node as Node).queue_free()
	special_block_nodes.clear()
	for x in SIZE_XZ:
		for y in HEIGHT:
			for z in SIZE_XZ:
				var local_position := Vector3i(x, y, z)
				if BlockRegistry.is_special_block(data.get_block(local_position)):
					create_special_block(local_position)


func sync_special_block(local_position: Vector3i) -> void:
	remove_special_block(local_position)
	if BlockRegistry.is_special_block(data.get_block(local_position)):
		create_special_block(local_position)


func remove_special_block(local_position: Vector3i) -> void:
	var node := special_block_nodes.get(local_position) as Node3D
	if node != null:
		node.queue_free()
		special_block_nodes.erase(local_position)
	if world != null and data.get_block(local_position) == BlockRegistry.Block.AIR:
		world.clear_special_block_metadata(chunk_position, local_position)


func create_special_block(local_position: Vector3i) -> void:
	if special_blocks_root == null or special_block_nodes.has(local_position):
		return
	var torch := Node3D.new()
	torch.name = "Torch_%d_%d_%d" % [local_position.x, local_position.y, local_position.z]
	torch.position = Vector3(local_position) + Vector3(0.5, 0.0, 0.5)
	special_blocks_root.add_child(torch)
	var support_direction := Vector3i.DOWN
	if world != null:
		support_direction = world.get_special_block_support(chunk_position, local_position)
	var outward := -Vector3(support_direction)
	var shaft_direction := Vector3.UP
	var base_position := Vector3.ZERO
	if support_direction != Vector3i.DOWN:
		shaft_direction = (Vector3.UP * 0.88 + outward * 0.48).normalized()
		base_position = Vector3(support_direction) * 0.39 + Vector3.UP * 0.2
	var shaft_rotation := Quaternion(Vector3.UP, shaft_direction)

	var stick := MeshInstance3D.new()
	var stick_mesh := BoxMesh.new()
	stick_mesh.size = Vector3(0.11, 0.62, 0.11)
	stick.mesh = stick_mesh
	stick.position = base_position + shaft_direction * 0.31
	stick.quaternion = shaft_rotation
	var stick_material := StandardMaterial3D.new()
	stick_material.albedo_color = Color(0.22, 0.09, 0.035)
	stick.material_override = stick_material
	torch.add_child(stick)

	var ember := MeshInstance3D.new()
	var ember_mesh := BoxMesh.new()
	ember_mesh.size = Vector3(0.15, 0.14, 0.15)
	ember.mesh = ember_mesh
	ember.position = base_position + shaft_direction * 0.59
	ember.quaternion = shaft_rotation
	var ember_material := StandardMaterial3D.new()
	ember_material.albedo_color = Color(0.12, 0.055, 0.025)
	ember.material_override = ember_material
	torch.add_child(ember)

	var tip := MeshInstance3D.new()
	var tip_mesh := BoxMesh.new()
	tip_mesh.size = Vector3(0.2, 0.22, 0.2)
	tip.mesh = tip_mesh
	tip.position = base_position + shaft_direction * 0.68
	tip.quaternion = shaft_rotation
	var tip_material := StandardMaterial3D.new()
	tip_material.albedo_color = Color(1.0, 0.64, 0.16)
	tip_material.emission_enabled = true
	tip_material.emission = Color(1.0, 0.34, 0.04)
	tip_material.emission_energy_multiplier = 2.0
	tip.material_override = tip_material
	torch.add_child(tip)

	var body := StaticBody3D.new()
	body.set_meta("chunk", self)
	body.set_meta("special_local_position", local_position)
	body.set_meta("special_block", BlockRegistry.Block.TORCH)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.18, 0.72, 0.18)
	collision.shape = shape
	collision.position = base_position + shaft_direction * 0.36
	collision.quaternion = shaft_rotation
	body.add_child(collision)
	torch.add_child(body)
	special_block_nodes[local_position] = torch


func get_torch_light_count() -> int:
	return 0

func get_neighbor_block(local_position: Vector3i) -> int:
	if (
		local_position.x >= 0
		and local_position.x < SIZE_XZ
		and local_position.y >= 0
		and local_position.y < HEIGHT
		and local_position.z >= 0
		and local_position.z < SIZE_XZ
	):
		return get_block(local_position)

	if world == null:
		return BlockRegistry.Block.AIR

	var world_position := (
		Vector3i(global_position)
		+ local_position
	)

	return world.get_block_at_world_position(world_position)
