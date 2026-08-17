class_name ChunkData
extends RefCounted

const SIZE_XZ := 16
const HEIGHT := 64

var blocks := []
var block_light := PackedByteArray()


func _init(initialize_blocks: bool = true) -> void:
	if initialize_blocks:
		reset()


func reset() -> void:
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
	blocks[position.x][position.y][position.z] = block
	return true


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


func duplicate_data() -> ChunkData:
	var copy := ChunkData.new(false)
	copy.blocks = blocks.duplicate(true)
	copy.block_light = block_light.duplicate()
	return copy
