class_name ChunkGenerator
extends RefCounted

var coal_noise: FastNoiseLite
var iron_noise: FastNoiseLite
var copper_noise: FastNoiseLite
var tin_noise: FastNoiseLite
var gold_noise: FastNoiseLite
var tungsten_noise: FastNoiseLite
var platinum_noise: FastNoiseLite


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
