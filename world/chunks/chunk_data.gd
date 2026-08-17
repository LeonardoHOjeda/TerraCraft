class_name ChunkData
extends RefCounted

const SIZE_XZ := 16
const HEIGHT := 64

var blocks := []
var block_light := PackedByteArray()
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
	copy.special_block_indices = special_block_indices.duplicate()
	copy.emissive_block_indices = emissive_block_indices.duplicate()
	return copy
