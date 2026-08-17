class_name ChunkMesher
extends RefCounted

const ATLAS_SIZE := 16.0

const DIRECTIONS := [
	Vector3i(0, 1, 0),
	Vector3i(0, -1, 0),
	Vector3i(1, 0, 0),
	Vector3i(-1, 0, 0),
	Vector3i(0, 0, 1),
	Vector3i(0, 0, -1),
]

var vertices := PackedVector3Array()
var normals := PackedVector3Array()
var uvs := PackedVector2Array()
var indices := PackedInt32Array()


func build(data: ChunkData, neighbor_block_provider: Callable) -> ArrayMesh:
	reset_buffers()
	build_geometry(data, neighbor_block_provider)
	return create_mesh(get_mesh_data())


func build_mesh_data(snapshot: Dictionary) -> Dictionary:
	var started_at := Time.get_ticks_usec()
	reset_buffers()
	var data: ChunkData = snapshot["data"]
	for x in ChunkData.SIZE_XZ:
		for y in ChunkData.HEIGHT:
			for z in ChunkData.SIZE_XZ:
				var block: int = data.get_block(Vector3i(x, y, z))
				if block == BlockRegistry.Block.AIR:
					continue
				var block_position := Vector3i(x, y, z)
				for direction in DIRECTIONS:
					var neighbor_position = block_position + direction
					if get_snapshot_block(snapshot, neighbor_position) == BlockRegistry.Block.AIR:
						add_face(block_position, direction, block)
	var mesh_data := get_mesh_data()
	mesh_data["worker_usec"] = Time.get_ticks_usec() - started_at
	return mesh_data


func reset_buffers() -> void:
	vertices.clear()
	normals.clear()
	uvs.clear()
	indices.clear()


func build_geometry(data: ChunkData, neighbor_block_provider: Callable) -> void:
	for x in ChunkData.SIZE_XZ:
		for y in ChunkData.HEIGHT:
			for z in ChunkData.SIZE_XZ:
				var block: int = data.get_block(Vector3i(x, y, z))

				if block == BlockRegistry.Block.AIR:
					continue

				var block_position := Vector3i(x, y, z)

				for direction in DIRECTIONS:
					var neighbor_position = block_position + direction

					if neighbor_block_provider.call(neighbor_position) == BlockRegistry.Block.AIR:
						add_face(
							block_position,
							direction,
							block
						)


func get_mesh_data() -> Dictionary:
	return {
		"vertices": vertices,
		"normals": normals,
		"uvs": uvs,
		"indices": indices,
	}


func create_mesh(mesh_data: Dictionary) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = mesh_data["vertices"]
	arrays[Mesh.ARRAY_NORMAL] = mesh_data["normals"]
	arrays[Mesh.ARRAY_TEX_UV] = mesh_data["uvs"]
	arrays[Mesh.ARRAY_INDEX] = mesh_data["indices"]

	var generated_mesh := ArrayMesh.new()
	if (mesh_data["vertices"] as PackedVector3Array).size() > 0:
		generated_mesh.add_surface_from_arrays(
			Mesh.PRIMITIVE_TRIANGLES,
			arrays
		)

	return generated_mesh


func get_snapshot_block(snapshot: Dictionary, position: Vector3i) -> int:
	if position.y < 0 or position.y >= ChunkData.HEIGHT:
		return BlockRegistry.Block.AIR
	if position.x >= 0 and position.x < ChunkData.SIZE_XZ and position.z >= 0 and position.z < ChunkData.SIZE_XZ:
		var data: ChunkData = snapshot["data"]
		return data.get_block(position)
	if position.x < 0:
		return snapshot["negative_x"][position.y * ChunkData.SIZE_XZ + position.z]
	if position.x >= ChunkData.SIZE_XZ:
		return snapshot["positive_x"][position.y * ChunkData.SIZE_XZ + position.z]
	if position.z < 0:
		return snapshot["negative_z"][position.y * ChunkData.SIZE_XZ + position.x]
	return snapshot["positive_z"][position.y * ChunkData.SIZE_XZ + position.x]


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
		return [Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0)]
	if direction == Vector3i(0, -1, 0):
		return [Vector3(0, 0, 1), Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1)]
	if direction == Vector3i(1, 0, 0):
		return [Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(1, 0, 1)]
	if direction == Vector3i(-1, 0, 0):
		return [Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0), Vector3(0, 0, 0)]
	if direction == Vector3i(0, 0, 1):
		return [Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1), Vector3(0, 0, 1)]
	return [Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 0, 0)]
