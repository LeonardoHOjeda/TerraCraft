class_name Chunk
extends MeshInstance3D

const SIZE_XZ := 16
const HEIGHT := 64
const ATLAS_SIZE := 16.0

var chunk_position := Vector2i.ZERO

var continental_noise: FastNoiseLite
var detail_noise: FastNoiseLite
var biome_noise: FastNoiseLite
var tree_noise: FastNoiseLite

var terrain_height: int = 8
var base_height: int = 4

var blocks := []

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


func initialize(
	new_chunk_position: Vector2i,
	new_continental_noise: FastNoiseLite,
	new_detail_noise: FastNoiseLite,
	new_biome_noise: FastNoiseLite,
	new_tree_noise: FastNoiseLite,
	new_terrain_height: int,
	new_base_height: int
) -> void:
	chunk_position = new_chunk_position
	continental_noise = new_continental_noise
	detail_noise = new_detail_noise
	biome_noise = new_biome_noise
	tree_noise = new_tree_noise
	terrain_height = new_terrain_height
	base_height = new_base_height

	generate_blocks()
	rebuild_mesh()


func generate_blocks() -> void:
	blocks.resize(SIZE_XZ)

	for x in SIZE_XZ:
		blocks[x] = []
		blocks[x].resize(HEIGHT)

		for y in HEIGHT:
			blocks[x][y] = []
			blocks[x][y].resize(SIZE_XZ)

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

				if y == 0:
					blocks[x][y][z] = BlockRegistry.Block.BEDROCK

				elif y > surface_height:
					blocks[x][y][z] = BlockRegistry.Block.AIR

				elif y == surface_height:
					blocks[x][y][z] = surface_block

				elif y >= surface_height - 3:
					blocks[x][y][z] = underground_block

				else:
					blocks[x][y][z] = BlockRegistry.Block.STONE


func get_block(position: Vector3i) -> int:
	if (
		position.x < 0
		or position.y < 0
		or position.z < 0
		or position.x >= SIZE_XZ
		or position.y >= HEIGHT
		or position.z >= SIZE_XZ
	):
		return BlockRegistry.Block.AIR

	return blocks[position.x][position.y][position.z]


func rebuild_mesh() -> void:
	vertices.clear()
	normals.clear()
	uvs.clear()
	indices.clear()

	for x in SIZE_XZ:
		for y in HEIGHT:
			for z in SIZE_XZ:
				var block: int = blocks[x][y][z]

				if block == BlockRegistry.Block.AIR:
					continue

				var block_position := Vector3i(x, y, z)

				for direction in DIRECTIONS:
					var neighbor_position = block_position + direction

					if get_block(neighbor_position) == BlockRegistry.Block.AIR:
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


func add_face(
	block_position: Vector3i,
	direction: Vector3i,
	block: int
) -> void:
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


func get_block_texture(
	block: int,
	direction: Vector3i
) -> Vector2i:
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

	return BlockRegistry.TEXTURE_DIRT


func get_atlas_uvs(
	atlas_position: Vector2i
) -> Array[Vector2]:
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

func remove_block(position: Vector3i) -> void:
	if (position.x < 0 or position.y < 0 or position.z < 0 or position.x >= SIZE_XZ or position.y >= HEIGHT or position.z >= SIZE_XZ):
		return

	if blocks[position.x][position.y][position.z] == BlockRegistry.Block.AIR:
		return

	if blocks[position.x][position.y][position.z] == BlockRegistry.Block.BEDROCK:
		return

	blocks[position.x][position.y][position.z] = BlockRegistry.Block.AIR

	rebuild_mesh()

func place_block(position: Vector3i, block: int) -> void:
	if (position.x < 0 or position.y < 0 or position.z < 0 or position.x >= SIZE_XZ or position.y >= HEIGHT or position.z >= SIZE_XZ):
		return

	if blocks[position.x][position.y][position.z] != BlockRegistry.Block.AIR:
		return

	blocks[position.x][position.y][position.z] = block

	rebuild_mesh()


func generate_trees() -> void:
	var tree_positions: Array[Vector2i] = []
	var minimum_tree_distance := 4

	for x in SIZE_XZ:
		for z in SIZE_XZ:
			var world_x := chunk_position.x * SIZE_XZ + x
			var world_z := chunk_position.y * SIZE_XZ + z

			var biome_value := biome_noise.get_noise_2d(
				world_x,
				world_z
			)

			var tree_threshold := 0.60

			if biome_value > 0.35:
				# Bosque
				tree_threshold = 0.35
			elif biome_value >= -0.25:
				# Pradera
				tree_threshold = 0.72
			else:
				# Desierto
				continue

			var tree_value := tree_noise.get_noise_2d(
				world_x,
				world_z
			)

			if tree_value < tree_threshold:
				continue

			var surface_y := get_surface_height(x, z)

			if surface_y < 1:
				continue

			if surface_y + 6 >= HEIGHT:
				continue

			if x < 2 or x >= SIZE_XZ - 2:
				continue

			if z < 2 or z >= SIZE_XZ - 2:
				continue

			var candidate := Vector2i(x, z)

			var too_close := false

			for existing in tree_positions:
				if candidate.distance_to(existing) < minimum_tree_distance:
					too_close = true
					break

			if too_close:
				continue

			create_tree(Vector3i(x, surface_y + 1, z))
			tree_positions.append(candidate)

func get_surface_height(x: int, z: int) -> int:
	for y in range(HEIGHT - 1, -1, -1):
		var block: int = blocks[x][y][z]

		if (
			block == BlockRegistry.Block.GRASS
			or block == BlockRegistry.Block.SAND
		):
			return y

	return -1

func create_tree(position: Vector3i) -> void:
	var trunk_height := 4

	for y in trunk_height:
		set_block_safe(
			position + Vector3i(0, y, 0),
			BlockRegistry.Block.WOOD
		)

	var leaves_center := position + Vector3i(0, trunk_height, 0)

	for x in range(-2, 3):
		for y in range(-2, 2):
			for z in range(-2, 3):
				if abs(x) + abs(z) > 3:
					continue

				set_block_safe(
					leaves_center + Vector3i(x, y, z),
					BlockRegistry.Block.LEAVES
				)

	set_block_safe(
		leaves_center + Vector3i(0, 2, 0),
		BlockRegistry.Block.LEAVES
	)

func set_block_safe(position: Vector3i, block: int) -> void:
	if (
		position.x < 0
		or position.y < 0
		or position.z < 0
		or position.x >= SIZE_XZ
		or position.y >= HEIGHT
		or position.z >= SIZE_XZ
	):
		return

	if blocks[position.x][position.y][position.z] != BlockRegistry.Block.AIR:
		return

	blocks[position.x][position.y][position.z] = block


func set_block_without_rebuild(position: Vector3i, block: int) -> bool:
	if (
		position.x < 0
		or position.y < 0
		or position.z < 0
		or position.x >= SIZE_XZ
		or position.y >= HEIGHT
		or position.z >= SIZE_XZ
	):
		return false

	if blocks[position.x][position.y][position.z] != BlockRegistry.Block.AIR:
		return false

	blocks[position.x][position.y][position.z] = block
	return true

func get_block_local(position: Vector3i) -> int:
	return get_block(position)
