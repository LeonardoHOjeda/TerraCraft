class_name Chunk
extends MeshInstance3D

const SIZE_XZ := ChunkData.SIZE_XZ
const HEIGHT := ChunkData.HEIGHT
const ATLAS_SIZE := 16.0

var world: World

var chunk_position := Vector2i.ZERO

var continental_noise: FastNoiseLite
var detail_noise: FastNoiseLite
var biome_noise: FastNoiseLite
var cave_noise: FastNoiseLite

var coal_noise: FastNoiseLite
var iron_noise: FastNoiseLite
var copper_noise: FastNoiseLite
var tin_noise: FastNoiseLite
var gold_noise: FastNoiseLite
var tungsten_noise: FastNoiseLite
var platinum_noise: FastNoiseLite

var terrain_height: int = 8
var base_height: int = 4

var data := ChunkData.new()

var vertices := PackedVector3Array()
var normals := PackedVector3Array()
var uvs := PackedVector2Array()
var indices := PackedInt32Array()


const DIRECTIONS := [
	Vector3i(0, 1, 0),
	Vector3i(0, -1, 0),
	Vector3i(1, 0, 0),
	Vector3i(-1, 0, 0),
	Vector3i(0, 0, 1),
	Vector3i(0, 0, -1),
]


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

	continental_noise = new_continental_noise
	detail_noise = new_detail_noise
	biome_noise = new_biome_noise
	cave_noise = new_cave_noise

	coal_noise = new_coal_noise
	iron_noise = new_iron_noise
	copper_noise = new_copper_noise
	tin_noise = new_tin_noise
	gold_noise = new_gold_noise
	tungsten_noise = new_tungsten_noise
	platinum_noise = new_platinum_noise

	terrain_height = new_terrain_height
	base_height = new_base_height

	generate_blocks()


func generate_blocks() -> void:
	data.reset()

	for x in SIZE_XZ:
		for y in HEIGHT:
			for z in SIZE_XZ:
				var world_x := chunk_position.x * SIZE_XZ + x
				var world_z := chunk_position.y * SIZE_XZ + z
				var biome_value := biome_noise.get_noise_2d(world_x, world_z)

				var continental := continental_noise.get_noise_2d(world_x, world_z)

				var detail := detail_noise.get_noise_2d(world_x, world_z)

				var surface_height := base_height + roundi(continental * terrain_height + detail * 4.0)

				var surface_block := BlockRegistry.Block.GRASS
				var underground_block := BlockRegistry.Block.DIRT

				if biome_value < -0.25:
					surface_block = BlockRegistry.Block.SAND
					underground_block = BlockRegistry.Block.SAND
				elif biome_value > 0.35:
					surface_block = BlockRegistry.Block.GRASS
					underground_block = BlockRegistry.Block.DIRT

				surface_height = clampi(surface_height, 1, HEIGHT - 1)

				var cave_value := cave_noise.get_noise_3d(
					world_x,
					y,
					world_z
				)

				var is_cave := false

				if y > 2 and y < surface_height - 4:
					if cave_value > 0.38:
						is_cave = true

				if y == 0:
					data.set_block(Vector3i(x, y, z), BlockRegistry.Block.BEDROCK)

				elif y > surface_height:
					data.set_block(Vector3i(x, y, z), BlockRegistry.Block.AIR)

				elif is_cave:
					data.set_block(Vector3i(x, y, z), BlockRegistry.Block.AIR)

				elif y == surface_height:
					data.set_block(Vector3i(x, y, z), surface_block)

				elif y >= surface_height - 3:
					data.set_block(Vector3i(x, y, z), underground_block)

				else:
					data.set_block(Vector3i(x, y, z), get_ore_block(world_x, y, world_z))


func get_block(position: Vector3i) -> int:
	return data.get_block(position)


func rebuild_mesh() -> void:
	vertices.clear()
	normals.clear()
	uvs.clear()
	indices.clear()

	for x in SIZE_XZ:
		for y in HEIGHT:
			for z in SIZE_XZ:
				var block: int = data.get_block(Vector3i(x, y, z))

				if block == BlockRegistry.Block.AIR:
					continue

				var block_position := Vector3i(x, y, z)

				for direction in DIRECTIONS:
					var neighbor_position = block_position + direction

					if get_neighbor_block(neighbor_position) == BlockRegistry.Block.AIR:
						add_face(
							block_position,
							direction,
							block
						)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)

	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var generated_mesh := ArrayMesh.new()

	if vertices.size() > 0:
		generated_mesh.add_surface_from_arrays(
			Mesh.PRIMITIVE_TRIANGLES,
			arrays
		)

	mesh = generated_mesh

	for child in get_children():
		if child is StaticBody3D:
			child.free()

	if mesh != null and mesh.get_surface_count() > 0:
		create_trimesh_collision()

		for child in get_children():
			if child is StaticBody3D:
				child.set_meta("chunk", self)


func add_face(block_position: Vector3i, direction: Vector3i, block: int) -> void:
	var face_vertices := get_face_vertices(direction)
	var texture_position := get_block_texture(block, direction)
	var face_uvs := get_atlas_uvs(texture_position)

	var start_index := vertices.size()

	for i in face_vertices.size():
		vertices.append(
			Vector3(block_position) + face_vertices[i]
		)

		normals.append(Vector3(direction))
		uvs.append(face_uvs[i])

	indices.append(start_index)
	indices.append(start_index + 2)
	indices.append(start_index + 1)

	indices.append(start_index)
	indices.append(start_index + 3)
	indices.append(start_index + 2)


func get_block_texture(block: int, direction: Vector3i) -> Vector2i:
	match block:
		BlockRegistry.Block.GRASS:
			if direction == Vector3i.UP:
				return BlockRegistry.TEXTURE_GRASS_TOP

			if direction == Vector3i.DOWN:
				return BlockRegistry.TEXTURE_DIRT

			return BlockRegistry.TEXTURE_GRASS_SIDE

		BlockRegistry.Block.DIRT:
			return BlockRegistry.TEXTURE_DIRT

		BlockRegistry.Block.STONE:
			return BlockRegistry.TEXTURE_STONE

		BlockRegistry.Block.BEDROCK:
			return BlockRegistry.TEXTURE_BEDROCK

		BlockRegistry.Block.WOOD:
			if direction == Vector3i.UP or direction == Vector3i.DOWN:
				return BlockRegistry.TEXTURE_WOOD_TOP

			return BlockRegistry.TEXTURE_WOOD_SIDE

		BlockRegistry.Block.LEAVES:
			return BlockRegistry.TEXTURE_LEAVES

		BlockRegistry.Block.WATER:
			return BlockRegistry.TEXTURE_WATER

		BlockRegistry.Block.SAND:
			return BlockRegistry.TEXTURE_SAND

		BlockRegistry.Block.COAL:
			return BlockRegistry.TEXTURE_COAL

		BlockRegistry.Block.IRON:
			return BlockRegistry.TEXTURE_IRON

		BlockRegistry.Block.COPPER:
			return BlockRegistry.TEXTURE_COPPER

		BlockRegistry.Block.TIN:
			return BlockRegistry.TEXTURE_TIN

		BlockRegistry.Block.GOLD:
			return BlockRegistry.TEXTURE_GOLD

		BlockRegistry.Block.TUNGSTEN:
			return BlockRegistry.TEXTURE_TUNGSTEN

		BlockRegistry.Block.PLATINUM:
			return BlockRegistry.TEXTURE_PLATINUM

		BlockRegistry.Block.WOOD_PLANKS:
			return BlockRegistry.TEXTURE_WOOD_PLANK
			
		BlockRegistry.Block.WORKBENCH:
			return BlockRegistry.TEXTURE_WORKBENCH

		BlockRegistry.Block.FURNACE:
			return BlockRegistry.TEXTURE_FURNACE

	return BlockRegistry.TEXTURE_DIRT


func get_atlas_uvs(atlas_position: Vector2i) -> Array[Vector2]:
	var tile_size := 1.0 / ATLAS_SIZE

	var left := atlas_position.x * tile_size
	var right := left + tile_size

	var top := atlas_position.y * tile_size
	var bottom := top + tile_size

	return [
		Vector2(left, bottom),
		Vector2(left, top),
		Vector2(right, top),
		Vector2(right, bottom),
	]


func get_face_vertices(direction: Vector3i) -> Array[Vector3]:
	if direction == Vector3i(0, 1, 0):
		return [
			Vector3(0, 1, 0),
			Vector3(0, 1, 1),
			Vector3(1, 1, 1),
			Vector3(1, 1, 0),
		]

	if direction == Vector3i(0, -1, 0):
		return [
			Vector3(0, 0, 1),
			Vector3(0, 0, 0),
			Vector3(1, 0, 0),
			Vector3(1, 0, 1),
		]

	if direction == Vector3i(1, 0, 0):
		return [
			Vector3(1, 0, 0),
			Vector3(1, 1, 0),
			Vector3(1, 1, 1),
			Vector3(1, 0, 1),
		]

	if direction == Vector3i(-1, 0, 0):
		return [
			Vector3(0, 0, 1),
			Vector3(0, 1, 1),
			Vector3(0, 1, 0),
			Vector3(0, 0, 0),
		]

	if direction == Vector3i(0, 0, 1):
		return [
			Vector3(1, 0, 1),
			Vector3(1, 1, 1),
			Vector3(0, 1, 1),
			Vector3(0, 0, 1),
		]

	return [
		Vector3(0, 0, 0),
		Vector3(0, 1, 0),
		Vector3(1, 1, 0),
		Vector3(1, 0, 0),
	]

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

func get_ore_block(world_x: int, y: int, world_z: int) -> int:
	if y <= 45:
		var value := coal_noise.get_noise_3d(world_x, y, world_z)

		if value > 0.58:
			return BlockRegistry.Block.COAL

	if y <= 40:
		var value := copper_noise.get_noise_3d(world_x, y, world_z)

		if value > 0.60:
			return BlockRegistry.Block.COPPER

	if y <= 35:
		var value := tin_noise.get_noise_3d(world_x, y, world_z)

		if value > 0.62:
			return BlockRegistry.Block.TIN

	if y <= 32:
		var value := iron_noise.get_noise_3d(world_x, y, world_z)

		if value > 0.64:
			return BlockRegistry.Block.IRON

	if y <= 18:
		var value := gold_noise.get_noise_3d(world_x, y, world_z)

		if value > 0.68:
			return BlockRegistry.Block.GOLD

	if y <= 14:
		var value := tungsten_noise.get_noise_3d(world_x, y, world_z)

		if value > 0.72:
			return BlockRegistry.Block.TUNGSTEN

	if y <= 10:
		var value := platinum_noise.get_noise_3d(world_x, y, world_z)

		if value > 0.76:
			return BlockRegistry.Block.PLATINUM

	return BlockRegistry.Block.STONE
