class_name ChunkData
extends RefCounted

const SIZE_XZ := 16
const HEIGHT := 64

var blocks := []


func _init(initialize_blocks: bool = true) -> void:
	if initialize_blocks:
		reset()


func reset() -> void:
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


func duplicate_data() -> ChunkData:
	var copy := ChunkData.new(false)
	copy.blocks = blocks.duplicate(true)
	return copy
