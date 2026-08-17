class_name ChunkMesher
extends RefCounted

const ATLAS_SIZE := 16.0
const COLLISION_REGION_SIZE := 16
const COLLISION_REGION_COUNT_X := ChunkData.SIZE_XZ / COLLISION_REGION_SIZE
const COLLISION_REGION_COUNT_Y := ChunkData.HEIGHT / COLLISION_REGION_SIZE
const COLLISION_REGION_COUNT_Z := ChunkData.SIZE_XZ / COLLISION_REGION_SIZE
const COLLISION_REGION_COUNT := (
	COLLISION_REGION_COUNT_X * COLLISION_REGION_COUNT_Y * COLLISION_REGION_COUNT_Z
)

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
var last_collision_units: Array[Dictionary] = []


func build(data: ChunkData, neighbor_block_provider: Callable) -> ArrayMesh:
	reset_buffers()
	build_geometry(data, neighbor_block_provider)
	last_collision_units = build_greedy_collision_units(data, get_all_collision_unit_indices())
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
						add_face(
							block_position,
							direction,
							block,
							get_snapshot_light(snapshot, neighbor_position),
							get_snapshot_sun_light(snapshot, neighbor_position)
						)
	last_collision_units = build_greedy_collision_units(
		data, snapshot.get("collision_unit_indices", [])
	)
	var mesh_data := get_mesh_data()
	mesh_data["worker_usec"] = Time.get_ticks_usec() - started_at
	return mesh_data


func reset_buffers() -> void:
	vertices.clear()
	normals.clear()
	uvs.clear()
	colors.clear()
	indices.clear()
	last_collision_units.clear()


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
							get_neighbor_light(data, neighbor_position),
							get_neighbor_sun_light(data, neighbor_position)
						)


func get_mesh_data() -> Dictionary:
	return {
		"vertices": vertices,
		"normals": normals,
		"uvs": uvs,
		"colors": colors,
		"indices": indices,
		"collision_units": last_collision_units,
	}


func get_all_collision_unit_indices() -> Array[int]:
	var indices: Array[int] = []
	for unit_index in COLLISION_REGION_COUNT:
		indices.append(unit_index)
	return indices


func build_greedy_collision_units(
	data: ChunkData, unit_indices: Array = []
) -> Array[Dictionary]:
	var units: Array[Dictionary] = []
	for unit_index in unit_indices:
		var unit_y: int = int(unit_index)
		if unit_y < 0 or unit_y >= COLLISION_REGION_COUNT_Y:
			continue
		var started_at := Time.get_ticks_usec()
		var y_min := unit_y * COLLISION_REGION_SIZE
		var y_max := mini(y_min + COLLISION_REGION_SIZE, ChunkData.HEIGHT)
		var visited := PackedByteArray()
		visited.resize(ChunkData.SIZE_XZ * (y_max - y_min) * ChunkData.SIZE_XZ)
		visited.fill(0)
		var centers := PackedVector3Array()
		var sizes := PackedVector3Array()
		var solid_voxels := 0
		for y in range(y_min, y_max):
			for z in ChunkData.SIZE_XZ:
				for x in ChunkData.SIZE_XZ:
					var visited_index := get_collision_unit_voxel_index(x, y - y_min, z)
					if not BlockRegistry.is_mesh_block(data.blocks[x][y][z]):
						continue
					solid_voxels += 1
					if visited[visited_index] != 0:
						continue
					var end_x := x + 1
					while end_x < ChunkData.SIZE_XZ:
						var candidate_index := get_collision_unit_voxel_index(end_x, y - y_min, z)
						if visited[candidate_index] != 0 or not BlockRegistry.is_mesh_block(data.blocks[end_x][y][z]):
							break
						end_x += 1
					var end_z := z + 1
					while end_z < ChunkData.SIZE_XZ and is_collision_strip_available(
						data, visited, x, end_x, y, y_min, end_z
					):
						end_z += 1
					var end_y := y + 1
					while end_y < y_max and is_collision_layer_available(
						data, visited, x, end_x, z, end_z, end_y, y_min
					):
						end_y += 1
					for mark_y in range(y, end_y):
						for mark_z in range(z, end_z):
							for mark_x in range(x, end_x):
								visited[get_collision_unit_voxel_index(mark_x, mark_y - y_min, mark_z)] = 1
					var size := Vector3(end_x - x, end_y - y, end_z - z)
					sizes.append(size)
					centers.append(Vector3(x, y, z) + size * 0.5)
		units.append({
			"unit_index": unit_y,
			"centers": centers,
			"sizes": sizes,
			"solid_voxels": solid_voxels,
			"worker_usec": Time.get_ticks_usec() - started_at,
		})
	return units


func get_collision_unit_voxel_index(x: int, local_y: int, z: int) -> int:
	return (local_y * ChunkData.SIZE_XZ + z) * ChunkData.SIZE_XZ + x


func is_collision_strip_available(
	data: ChunkData,
	visited: PackedByteArray,
	start_x: int,
	end_x: int,
	y: int,
	y_min: int,
	z: int
) -> bool:
	for x in range(start_x, end_x):
		var index := get_collision_unit_voxel_index(x, y - y_min, z)
		if visited[index] != 0 or not BlockRegistry.is_mesh_block(data.blocks[x][y][z]):
			return false
	return true


func is_collision_layer_available(
	data: ChunkData,
	visited: PackedByteArray,
	start_x: int,
	end_x: int,
	start_z: int,
	end_z: int,
	y: int,
	y_min: int
) -> bool:
	for z in range(start_z, end_z):
		for x in range(start_x, end_x):
			var index := get_collision_unit_voxel_index(x, y - y_min, z)
			if visited[index] != 0 or not BlockRegistry.is_mesh_block(data.blocks[x][y][z]):
				return false
	return true


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


func get_snapshot_sun_light(snapshot: Dictionary, position: Vector3i) -> int:
	if position.y >= ChunkData.HEIGHT:
		return 15
	if position.y < 0:
		return 0
	if position.x >= 0 and position.x < ChunkData.SIZE_XZ and position.z >= 0 and position.z < ChunkData.SIZE_XZ:
		var data: ChunkData = snapshot["data"]
		return data.get_sun_light(position)
	if position.x < 0:
		return snapshot["negative_x_sun"][position.y * ChunkData.SIZE_XZ + position.z]
	if position.x >= ChunkData.SIZE_XZ:
		return snapshot["positive_x_sun"][position.y * ChunkData.SIZE_XZ + position.z]
	if position.z < 0:
		return snapshot["negative_z_sun"][position.y * ChunkData.SIZE_XZ + position.x]
	return snapshot["positive_z_sun"][position.y * ChunkData.SIZE_XZ + position.x]


func get_neighbor_sun_light(data: ChunkData, position: Vector3i) -> int:
	if position.y >= ChunkData.HEIGHT:
		return 15
	return data.get_sun_light(position)


func add_face(block_position: Vector3i, direction: Vector3i, block: int, block_light_level: int, sun_light_level: int) -> void:
	var face_vertices := get_face_vertices(direction)
	var texture_position := get_block_texture(block, direction)
	var face_uvs := get_atlas_uvs(texture_position)

	var start_index := vertices.size()
	var block_ratio := float(clampi(block_light_level, 0, 15)) / 15.0
	var sun_ratio := float(clampi(sun_light_level, 0, 15)) / 15.0
	var block_brightness := pow(block_ratio, 1.35)
	var sun_brightness := pow(sun_ratio, 1.2)

	for i in face_vertices.size():
		vertices.append(
			Vector3(block_position) + face_vertices[i]
		)

		normals.append(Vector3(direction))
		uvs.append(face_uvs[i])
		colors.append(Color(block_brightness, sun_brightness, 0.0, 1.0))

	indices.append(start_index)
	indices.append(start_index + 2)
	indices.append(start_index + 1)

	indices.append(start_index)
	indices.append(start_index + 3)
	indices.append(start_index + 2)



static func get_collision_region_index(region: Vector3i) -> int:
	return (
		(region.y * COLLISION_REGION_COUNT_Z + region.z) * COLLISION_REGION_COUNT_X
		+ region.x
	)


static func get_collision_region_coords(index: int) -> Vector3i:
	var region_x := index % COLLISION_REGION_COUNT_X
	var yz := index / COLLISION_REGION_COUNT_X
	var region_z := yz % COLLISION_REGION_COUNT_Z
	var region_y := yz / COLLISION_REGION_COUNT_Z
	return Vector3i(region_x, region_y, region_z)


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
