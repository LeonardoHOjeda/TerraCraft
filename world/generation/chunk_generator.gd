class_name ChunkGenerator
extends RefCounted

var coal_noise: FastNoiseLite
var iron_noise: FastNoiseLite
var copper_noise: FastNoiseLite
var tin_noise: FastNoiseLite
var gold_noise: FastNoiseLite
var tungsten_noise: FastNoiseLite
var platinum_noise: FastNoiseLite


func generate_data(parameters: Dictionary) -> Dictionary:
	var started_at := Time.get_ticks_usec()
	var data := ChunkData.new(false)
	var chunk_position: Vector2i = parameters["chunk_position"]
	populate(
		data,
		chunk_position,
		parameters["continental_noise"],
		parameters["detail_noise"],
		parameters["biome_noise"],
		parameters["cave_noise"],
		parameters["coal_noise"],
		parameters["iron_noise"],
		parameters["copper_noise"],
		parameters["tin_noise"],
		parameters["gold_noise"],
		parameters["tungsten_noise"],
		parameters["platinum_noise"],
		parameters["terrain_height"],
		parameters["base_height"]
	)
	apply_trees(
		data,
		chunk_position,
		parameters["continental_noise"],
		parameters["detail_noise"],
		parameters["biome_noise"],
		parameters["tree_noise"],
		parameters["terrain_height"],
		parameters["base_height"]
	)
	var overrides: Dictionary = parameters.get("overrides", {})
	apply_overrides(data, overrides)
	return {
		"data": data,
		"worker_usec": Time.get_ticks_usec() - started_at,
		"override_count": overrides.size(),
	}


func apply_overrides(data: ChunkData, overrides: Dictionary) -> void:
	for local_position in overrides:
		if data.is_valid_position(local_position):
			data.set_block(local_position, int(overrides[local_position]))


func populate(
	data: ChunkData,
	chunk_position: Vector2i,
	continental_noise: FastNoiseLite,
	detail_noise: FastNoiseLite,
	biome_noise: FastNoiseLite,
	cave_noise: FastNoiseLite,
	new_coal_noise: FastNoiseLite,
	new_iron_noise: FastNoiseLite,
	new_copper_noise: FastNoiseLite,
	new_tin_noise: FastNoiseLite,
	new_gold_noise: FastNoiseLite,
	new_tungsten_noise: FastNoiseLite,
	new_platinum_noise: FastNoiseLite,
	terrain_height: int,
	base_height: int
) -> void:
	coal_noise = new_coal_noise
	iron_noise = new_iron_noise
	copper_noise = new_copper_noise
	tin_noise = new_tin_noise
	gold_noise = new_gold_noise
	tungsten_noise = new_tungsten_noise
	platinum_noise = new_platinum_noise

	data.reset()

	for x in ChunkData.SIZE_XZ:
		for y in ChunkData.HEIGHT:
			for z in ChunkData.SIZE_XZ:
				var world_x := chunk_position.x * ChunkData.SIZE_XZ + x
				var world_z := chunk_position.y * ChunkData.SIZE_XZ + z
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

				surface_height = clampi(surface_height, 1, ChunkData.HEIGHT - 1)

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


func apply_trees(
	data: ChunkData,
	chunk_position: Vector2i,
	continental_noise: FastNoiseLite,
	detail_noise: FastNoiseLite,
	biome_noise: FastNoiseLite,
	tree_noise: FastNoiseLite,
	terrain_height: int,
	base_height: int
) -> void:
	const TREE_RADIUS := 2
	var min_world_x := chunk_position.x * ChunkData.SIZE_XZ
	var min_world_z := chunk_position.y * ChunkData.SIZE_XZ
	var max_world_x := min_world_x + ChunkData.SIZE_XZ - 1
	var max_world_z := min_world_z + ChunkData.SIZE_XZ - 1

	for world_x in range(min_world_x - TREE_RADIUS, max_world_x + TREE_RADIUS + 1):
		for world_z in range(min_world_z - TREE_RADIUS, max_world_z + TREE_RADIUS + 1):
			if not should_generate_tree(world_x, world_z, biome_noise, tree_noise):
				continue
			var continental := continental_noise.get_noise_2d(world_x, world_z)
			var detail := detail_noise.get_noise_2d(world_x, world_z)
			var surface_y := clampi(
				base_height + roundi(continental * terrain_height + detail * 4.0),
				1,
				ChunkData.HEIGHT - 1
			)
			create_tree_part(
				data,
				chunk_position,
				Vector3i(world_x, surface_y + 1, world_z)
			)


func should_generate_tree(
	world_x: int,
	world_z: int,
	biome_noise: FastNoiseLite,
	tree_noise: FastNoiseLite
) -> bool:
	var biome_value := biome_noise.get_noise_2d(world_x, world_z)
	if biome_value < -0.25:
		return false
	var value := tree_noise.get_noise_2d(world_x, world_z)
	var threshold := 0.45 if biome_value > 0.35 else 0.72
	if value < threshold:
		return false
	var minimum_distance := 4
	for offset_x in range(-minimum_distance, minimum_distance + 1):
		for offset_z in range(-minimum_distance, minimum_distance + 1):
			if offset_x == 0 and offset_z == 0:
				continue
			if offset_x * offset_x + offset_z * offset_z > minimum_distance * minimum_distance:
				continue
			if tree_noise.get_noise_2d(world_x + offset_x, world_z + offset_z) > value:
				return false
	return true


func create_tree_part(data: ChunkData, chunk_position: Vector2i, position: Vector3i) -> void:
	const TRUNK_HEIGHT := 4
	for y in TRUNK_HEIGHT:
		set_tree_block(data, chunk_position, position + Vector3i(0, y, 0), BlockRegistry.Block.WOOD)
	var leaves_center := position + Vector3i(0, TRUNK_HEIGHT, 0)
	for offset_x in range(-2, 3):
		for offset_y in range(-2, 2):
			for offset_z in range(-2, 3):
				if abs(offset_x) + abs(offset_z) > 3:
					continue
				set_tree_block(
					data,
					chunk_position,
					leaves_center + Vector3i(offset_x, offset_y, offset_z),
					BlockRegistry.Block.LEAVES
				)
	set_tree_block(
		data,
		chunk_position,
		leaves_center + Vector3i(0, 2, 0),
		BlockRegistry.Block.LEAVES
	)


func set_tree_block(
	data: ChunkData,
	chunk_position: Vector2i,
	world_position: Vector3i,
	block: int
) -> void:
	var target_chunk := Vector2i(
		floori(float(world_position.x) / ChunkData.SIZE_XZ),
		floori(float(world_position.z) / ChunkData.SIZE_XZ)
	)
	if target_chunk != chunk_position:
		return
	var local_position := world_position - Vector3i(
		chunk_position.x * ChunkData.SIZE_XZ,
		0,
		chunk_position.y * ChunkData.SIZE_XZ
	)
	if data.get_block(local_position) == BlockRegistry.Block.AIR:
		data.set_block(local_position, block)
