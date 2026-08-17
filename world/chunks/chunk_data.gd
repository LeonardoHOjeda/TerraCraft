class_name ChunkData
extends RefCounted

const SIZE_XZ := 16
const HEIGHT := 64

var blocks := []
var block_light := PackedByteArray()
var sun_light := PackedByteArray()
var direct_sun_mask := PackedByteArray()
var special_block_indices := PackedInt32Array()
var emissive_block_indices := PackedInt32Array()


func _init(initialize_blocks: bool = true) -> void:
	if initialize_blocks:
		reset()


func reset() -> void:
	special_block_indices.clear()
	emissive_block_indices.clear()
	block_light.resize(SIZE_XZ * HEIGHT * SIZE_XZ)
	block_light.fill(0)
	sun_light.resize(SIZE_XZ * HEIGHT * SIZE_XZ)
	sun_light.fill(0)
	direct_sun_mask.resize(ceili(float(SIZE_XZ * HEIGHT * SIZE_XZ) / 8.0))
	direct_sun_mask.fill(0)
	blocks.resize(SIZE_XZ)
	for x in SIZE_XZ:
		blocks[x] = []
		blocks[x].resize(HEIGHT)
		for y in HEIGHT:
			blocks[x][y] = []
			blocks[x][y].resize(SIZE_XZ)
			for z in SIZE_XZ:
				blocks[x][y][z] = BlockRegistry.Block.AIR


func is_valid_position(position: Vector3i) -> bool:
	return (
		position.x >= 0
		and position.y >= 0
		and position.z >= 0
		and position.x < SIZE_XZ
		and position.y < HEIGHT
		and position.z < SIZE_XZ
	)


func get_block(position: Vector3i) -> int:
	if not is_valid_position(position):
		return BlockRegistry.Block.AIR
	return blocks[position.x][position.y][position.z]


func set_block(position: Vector3i, block: int) -> bool:
	if not is_valid_position(position):
		return false
	var previous_block: int = blocks[position.x][position.y][position.z]
	if previous_block == block:
		return true
	var index := get_index(position)
	update_relevant_index(special_block_indices, index, BlockRegistry.is_special_block(previous_block), BlockRegistry.is_special_block(block))
	update_relevant_index(emissive_block_indices, index, BlockRegistry.get_light_emission(previous_block) > 0, BlockRegistry.get_light_emission(block) > 0)
	blocks[position.x][position.y][position.z] = block
	return true


func update_relevant_index(indices: PackedInt32Array, index: int, was_relevant: bool, is_relevant: bool) -> void:
	if was_relevant == is_relevant:
		return
	if is_relevant:
		indices.append(index)
		return
	var existing_index := indices.find(index)
	if existing_index >= 0:
		indices.remove_at(existing_index)


func get_block_light(position: Vector3i) -> int:
	if not is_valid_position(position):
		return 0
	return block_light[get_index(position)]


func set_block_light(position: Vector3i, level: int) -> bool:
	if not is_valid_position(position):
		return false
	block_light[get_index(position)] = clampi(level, 0, 15)
	return true


func get_sun_light(position: Vector3i) -> int:
	if not is_valid_position(position):
		return 0
	return sun_light[get_index(position)]


func set_sun_light(position: Vector3i, level: int) -> bool:
	if not is_valid_position(position):
		return false
	sun_light[get_index(position)] = clampi(level, 0, 15)
	return true


func is_direct_sunlight(position: Vector3i) -> bool:
	if not is_valid_position(position):
		return false
	var index := get_index(position)
	return (direct_sun_mask[index >> 3] & (1 << (index & 7))) != 0


func set_direct_sunlight(position: Vector3i, enabled: bool) -> void:
	if not is_valid_position(position):
		return
	var index := get_index(position)
	var byte_index := index >> 3
	var bit := 1 << (index & 7)
	if enabled:
		direct_sun_mask[byte_index] |= bit
	else:
		direct_sun_mask[byte_index] &= ~bit


func initialize_local_sunlight() -> Dictionary:
	var vertical_started_at := Time.get_ticks_usec()
	sun_light.fill(0)
	direct_sun_mask.fill(0)
	var direct_indices := PackedInt32Array()
	for x in SIZE_XZ:
		for z in SIZE_XZ:
			var sky_open := true
			for y in range(HEIGHT - 1, -1, -1):
				var index := (y * SIZE_XZ + z) * SIZE_XZ + x
				if sky_open and BlockRegistry.is_light_transparent(blocks[x][y][z]):
					sun_light[index] = 15
					direct_sun_mask[index >> 3] |= 1 << (index & 7)
					direct_indices.append(index)
				else:
					sky_open = false
	var vertical_usec := Time.get_ticks_usec() - vertical_started_at
	var bfs_started_at := Time.get_ticks_usec()
	var queue := PackedInt32Array()
	var seed_count := 0
	var queue_pushes := 0
	var legacy_seed_count := 0
	var duplicate_rejections := 0
	var neighbor_operations := 0
	for direct_index in direct_indices:
		var x := direct_index % SIZE_XZ
		var yz := direct_index / SIZE_XZ
		var z := yz % SIZE_XZ
		var y := yz / SIZE_XZ
		var legacy_source_can_seed := false
		for direction_index in 4:
			var neighbor_index := -1
			if direction_index == 0 and x > 0:
				neighbor_index = direct_index - 1
			elif direction_index == 1 and x + 1 < SIZE_XZ:
				neighbor_index = direct_index + 1
			elif direction_index == 2 and z > 0:
				neighbor_index = direct_index - SIZE_XZ
			elif direction_index == 3 and z + 1 < SIZE_XZ:
				neighbor_index = direct_index + SIZE_XZ
			if neighbor_index < 0:
				continue
			neighbor_operations += 1
			if (direct_sun_mask[neighbor_index >> 3] & (1 << (neighbor_index & 7))) != 0:
				continue
			var neighbor_x := neighbor_index % SIZE_XZ
			var neighbor_yz := neighbor_index / SIZE_XZ
			var neighbor_z := neighbor_yz % SIZE_XZ
			var neighbor_y := neighbor_yz / SIZE_XZ
			if not BlockRegistry.is_light_transparent(blocks[neighbor_x][neighbor_y][neighbor_z]):
				continue
			legacy_source_can_seed = true
			if sun_light[neighbor_index] >= 14:
				duplicate_rejections += 1
				continue
			sun_light[neighbor_index] = 14
			queue.append(neighbor_index)
			seed_count += 1
			queue_pushes += 1
		if legacy_source_can_seed:
			legacy_seed_count += 1
	var queue_index := 0
	while queue_index < queue.size():
		var index := queue[queue_index]
		queue_index += 1
		var level := sun_light[index]
		if level <= 1:
			continue
		var x := index % SIZE_XZ
		var yz := index / SIZE_XZ
		var z := yz % SIZE_XZ
		var y := yz / SIZE_XZ
		var desired: int = level - 1
		for direction_index in 6:
			var neighbor_index := -1
			if direction_index == 0 and x > 0:
				neighbor_index = index - 1
			elif direction_index == 1 and x + 1 < SIZE_XZ:
				neighbor_index = index + 1
			elif direction_index == 2 and z > 0:
				neighbor_index = index - SIZE_XZ
			elif direction_index == 3 and z + 1 < SIZE_XZ:
				neighbor_index = index + SIZE_XZ
			elif direction_index == 4 and y > 0:
				neighbor_index = index - SIZE_XZ * SIZE_XZ
			elif direction_index == 5 and y + 1 < HEIGHT:
				neighbor_index = index + SIZE_XZ * SIZE_XZ
			if neighbor_index < 0:
				continue
			neighbor_operations += 1
			var neighbor_x := neighbor_index % SIZE_XZ
			var neighbor_yz := neighbor_index / SIZE_XZ
			var neighbor_z := neighbor_yz % SIZE_XZ
			var neighbor_y := neighbor_yz / SIZE_XZ
			if not BlockRegistry.is_light_transparent(blocks[neighbor_x][neighbor_y][neighbor_z]):
				continue
			if desired <= sun_light[neighbor_index]:
				duplicate_rejections += 1
				continue
			sun_light[neighbor_index] = desired
			queue.append(neighbor_index)
			queue_pushes += 1
	return {
		"vertical_usec": vertical_usec,
		"bfs_usec": Time.get_ticks_usec() - bfs_started_at,
		"direct_voxels": direct_indices.size(),
		"seed_count": seed_count,
		"legacy_seed_count": legacy_seed_count,
		"processed_voxels": queue_index,
		"queue_pushes": queue_pushes,
		"duplicate_rejections": duplicate_rejections,
		"neighbor_operations": neighbor_operations,
	}


func get_index(position: Vector3i) -> int:
	return (position.y * SIZE_XZ + position.z) * SIZE_XZ + position.x


func get_position_from_index(index: int) -> Vector3i:
	var x := index % SIZE_XZ
	var yz := floori(float(index) / SIZE_XZ)
	var z := yz % SIZE_XZ
	var y := floori(float(yz) / SIZE_XZ)
	return Vector3i(x, y, z)


func duplicate_data() -> ChunkData:
	var copy := ChunkData.new(false)
	copy.blocks = blocks.duplicate(true)
	copy.block_light = block_light.duplicate()
	copy.sun_light = sun_light.duplicate()
	copy.direct_sun_mask = direct_sun_mask.duplicate()
	copy.special_block_indices = special_block_indices.duplicate()
	copy.emissive_block_indices = emissive_block_indices.duplicate()
	return copy
