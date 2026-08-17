class_name Chunk
extends MeshInstance3D

const SIZE_XZ := ChunkData.SIZE_XZ
const HEIGHT := ChunkData.HEIGHT

var world: World

var chunk_position := Vector2i.ZERO

var data := ChunkData.new()
var generator := ChunkGenerator.new()
var mesher := ChunkMesher.new()


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


func get_block(position: Vector3i) -> int:
	return data.get_block(position)


func rebuild_mesh() -> void:
	mesh = mesher.build(data, Callable(self, "get_neighbor_block"))

	for child in get_children():
		if child is StaticBody3D:
			child.free()

	if mesh != null and mesh.get_surface_count() > 0:
		create_trimesh_collision()

		for child in get_children():
			if child is StaticBody3D:
				child.set_meta("chunk", self)


func remove_block(position: Vector3i) -> int:
	if not data.is_valid_position(position):
		return BlockRegistry.Block.AIR

	var block: int = data.get_block(position)

	if block == BlockRegistry.Block.AIR:
		return BlockRegistry.Block.AIR

	if block == BlockRegistry.Block.BEDROCK:
		return BlockRegistry.Block.AIR

	data.set_block(position, BlockRegistry.Block.AIR)

	return block

func place_block(position: Vector3i, block: int) -> bool:
	if not data.is_valid_position(position):
		return false

	if data.get_block(position) != BlockRegistry.Block.AIR:
		return false

	data.set_block(position, block)

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
	return true

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
