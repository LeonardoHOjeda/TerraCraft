class_name ChunkMesher
extends RefCounted

const ATLAS_SIZE := 16.0
const COLLISION_SECTION_HEIGHT := 16
const COLLISION_SECTION_COUNT := ChunkData.HEIGHT / COLLISION_SECTION_HEIGHT

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
var colors := PackedColorArray()
var indices := PackedInt32Array()
var section_vertices: Array[PackedVector3Array] = []
var section_normals: Array[PackedVector3Array] = []
var section_uvs: Array[PackedVector2Array] = []
var section_indices: Array[PackedInt32Array] = []
var last_collision_sections: Array[Dictionary] = []


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
				if not BlockRegistry.is_mesh_block(block):
					continue
				var block_position := Vector3i(x, y, z)
				for direction in DIRECTIONS:
					var neighbor_position = block_position + direction
					if not BlockRegistry.is_occluding_block(get_snapshot_block(snapshot, neighbor_position)):
						add_face(block_position, direction, block, get_snapshot_light(snapshot, neighbor_position))
	var mesh_data := get_mesh_data()
	mesh_data["worker_usec"] = Time.get_ticks_usec() - started_at
	return mesh_data


func reset_buffers() -> void:
	vertices.clear()
	normals.clear()
	uvs.clear()
	colors.clear()
	indices.clear()
	section_vertices.clear()
	section_normals.clear()
	section_uvs.clear()
	section_indices.clear()
	for _section in COLLISION_SECTION_COUNT:
		section_vertices.append(PackedVector3Array())
		section_normals.append(PackedVector3Array())
		section_uvs.append(PackedVector2Array())
		section_indices.append(PackedInt32Array())


func build_geometry(data: ChunkData, neighbor_block_provider: Callable) -> void:
	for x in ChunkData.SIZE_XZ:
		for y in ChunkData.HEIGHT:
			for z in ChunkData.SIZE_XZ:
				var block: int = data.get_block(Vector3i(x, y, z))

				if not BlockRegistry.is_mesh_block(block):
					continue

				var block_position := Vector3i(x, y, z)

				for direction in DIRECTIONS:
					var neighbor_position = block_position + direction

					if not BlockRegistry.is_occluding_block(neighbor_block_provider.call(neighbor_position)):
						add_face(
							block_position,
							direction,
							block,
							get_neighbor_light(data, neighbor_position)
						)


func get_mesh_data() -> Dictionary:
	last_collision_sections = get_collision_section_data()
	return {
		"vertices": vertices,
		"normals": normals,
		"uvs": uvs,
		"colors": colors,
		"indices": indices,
		"collision_sections": last_collision_sections,
	}


func get_collision_section_data() -> Array[Dictionary]:
	var sections: Array[Dictionary] = []
	for section in COLLISION_SECTION_COUNT:
		sections.append({
			"vertices": section_vertices[section],
			"normals": section_normals[section],
			"uvs": section_uvs[section],
			"indices": section_indices[section],
		})
	return sections


func create_mesh(mesh_data: Dictionary) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = mesh_data["vertices"]
	arrays[Mesh.ARRAY_NORMAL] = mesh_data["normals"]
	arrays[Mesh.ARRAY_TEX_UV] = mesh_data["uvs"]
	if mesh_data.has("colors"):
		arrays[Mesh.ARRAY_COLOR] = mesh_data["colors"]
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


func get_snapshot_light(snapshot: Dictionary, position: Vector3i) -> int:
	if position.y < 0 or position.y >= ChunkData.HEIGHT:
		return 0
	if position.x >= 0 and position.x < ChunkData.SIZE_XZ and position.z >= 0 and position.z < ChunkData.SIZE_XZ:
		var data: ChunkData = snapshot["data"]
		return data.get_block_light(position)
	if position.x < 0:
		return snapshot["negative_x_light"][position.y * ChunkData.SIZE_XZ + position.z]
	if position.x >= ChunkData.SIZE_XZ:
		return snapshot["positive_x_light"][position.y * ChunkData.SIZE_XZ + position.z]
	if position.z < 0:
		return snapshot["negative_z_light"][position.y * ChunkData.SIZE_XZ + position.x]
	return snapshot["positive_z_light"][position.y * ChunkData.SIZE_XZ + position.x]


func get_neighbor_light(data: ChunkData, position: Vector3i) -> int:
	return data.get_block_light(position)


func add_face(block_position: Vector3i, direction: Vector3i, block: int, light_level: int) -> void:
	var face_vertices := get_face_vertices(direction)
	var texture_position := get_block_texture(block, direction)
	var face_uvs := get_atlas_uvs(texture_position)

	var start_index := vertices.size()
	var light_ratio := float(clampi(light_level, 0, 15)) / 15.0
	var brightness := pow(light_ratio, 1.35)

	for i in face_vertices.size():
		vertices.append(
			Vector3(block_position) + face_vertices[i]
		)

		normals.append(Vector3(direction))
		uvs.append(face_uvs[i])
		colors.append(Color(brightness, brightness, brightness, 1.0))

	indices.append(start_index)
	indices.append(start_index + 2)
	indices.append(start_index + 1)

	indices.append(start_index)
	indices.append(start_index + 3)
	indices.append(start_index + 2)

	add_collision_face(block_position, face_vertices, face_uvs, direction)


func add_collision_face(
	block_position: Vector3i,
	face_vertices: Array[Vector3],
	face_uvs: Array[Vector2],
	direction: Vector3i
) -> void:
	var section := clampi(
		floori(float(block_position.y) / COLLISION_SECTION_HEIGHT),
		0,
		COLLISION_SECTION_COUNT - 1
	)
	var target_vertices := section_vertices[section]
	var target_normals := section_normals[section]
	var target_uvs := section_uvs[section]
	var target_indices := section_indices[section]
	var start_index := target_vertices.size()
	for i in face_vertices.size():
		target_vertices.append(Vector3(block_position) + face_vertices[i])
		target_normals.append(Vector3(direction))
		target_uvs.append(face_uvs[i])
	target_indices.append(start_index)
	target_indices.append(start_index + 2)
	target_indices.append(start_index + 1)
	target_indices.append(start_index)
	target_indices.append(start_index + 3)
	target_indices.append(start_index + 2)
	section_vertices[section] = target_vertices
	section_normals[section] = target_normals
	section_uvs[section] = target_uvs
	section_indices[section] = target_indices


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
