class_name World
extends Node3D

@export var chunk_scene: PackedScene

@export var world_size_x: int = 8
@export var world_size_z: int = 8

@export var seed: int = 12345
@export var terrain_frequency: float = 0.025

@export var base_height: int = 20
@export var terrain_height: int = 20

@export var dropped_item_scene: PackedScene

var continental_noise := FastNoiseLite.new()
var detail_noise := FastNoiseLite.new()
var biome_noise := FastNoiseLite.new()
var tree_noise := FastNoiseLite.new()
var cave_noise := FastNoiseLite.new()

var coal_noise := FastNoiseLite.new()
var iron_noise := FastNoiseLite.new()
var copper_noise := FastNoiseLite.new()
var tin_noise := FastNoiseLite.new()
var gold_noise := FastNoiseLite.new()
var tungsten_noise := FastNoiseLite.new()
var platinum_noise := FastNoiseLite.new()

func _ready() -> void:
	setup_noise()
	generate_world()


func setup_noise() -> void:
	continental_noise.seed = seed
	continental_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	continental_noise.frequency = 0.005
	continental_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	continental_noise.fractal_octaves = 4
	continental_noise.fractal_gain = 0.5
	continental_noise.fractal_lacunarity = 2.0

	detail_noise.seed = seed + 1
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	detail_noise.frequency = 0.025
	detail_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	detail_noise.fractal_octaves = 3
	detail_noise.fractal_gain = 0.45

	biome_noise.seed = seed + 2
	biome_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	biome_noise.frequency = 0.003
	biome_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	biome_noise.fractal_octaves = 3

	tree_noise.seed = seed + 3
	tree_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	tree_noise.frequency = 0.08

	cave_noise.seed = seed + 4
	cave_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	cave_noise.frequency = 0.045
	cave_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	cave_noise.fractal_octaves = 3
	cave_noise.fractal_gain = 0.5
	cave_noise.fractal_lacunarity = 2.0

	setup_ore_noise(coal_noise, seed + 10, 0.09)
	setup_ore_noise(iron_noise, seed + 11, 0.08)
	setup_ore_noise(copper_noise, seed + 12, 0.085)
	setup_ore_noise(tin_noise, seed + 13, 0.085)
	setup_ore_noise(gold_noise, seed + 14, 0.07)
	setup_ore_noise(tungsten_noise, seed + 15, 0.06)
	setup_ore_noise(platinum_noise, seed + 16, 0.055)


func generate_world() -> void:
	var half_x := world_size_x / 2
	var half_z := world_size_z / 2

	for chunk_x in range(-half_x, half_x):
		for chunk_z in range(-half_z, half_z):
			create_chunk(chunk_x, chunk_z)

	generate_world_trees()
	rebuild_all_chunks()


func create_chunk(chunk_x: int, chunk_z: int) -> void:
	if chunk_scene == null:
		return

	var chunk := chunk_scene.instantiate() as Chunk

	chunk.position = Vector3(chunk_x * Chunk.SIZE_XZ, 0, chunk_z * Chunk.SIZE_XZ)

	chunk.name = "Chunk_%d_%d" % [chunk_x, chunk_z]

	add_child(chunk)

	chunk.initialize(
		self,
		Vector2i(chunk_x, chunk_z),
		continental_noise,
		detail_noise,
		biome_noise,
		cave_noise,
		coal_noise,
		iron_noise,
		copper_noise,
		tin_noise,
		gold_noise,
		tungsten_noise,
		platinum_noise,
		terrain_height,
		base_height
	)

func get_chunk_at_world_position(world_position: Vector3i) -> Chunk:
	var chunk_x := floori(float(world_position.x) / Chunk.SIZE_XZ)
	var chunk_z := floori(float(world_position.z) / Chunk.SIZE_XZ)

	var chunk_name := "Chunk_%d_%d" % [chunk_x, chunk_z]
	return get_node_or_null(chunk_name) as Chunk

func get_block_at_world_position(position: Vector3i) -> int:
	var chunk := get_chunk_at_world_position(position)

	if chunk == null:
		return BlockRegistry.Block.AIR

	var local_position := position - Vector3i(chunk.global_position)

	return chunk.get_block_local(local_position)

func set_block_at_world_position(position: Vector3i, block: int, affected_chunks: Dictionary) -> void:
	var chunk := get_chunk_at_world_position(position)

	if chunk == null:
		return

	var local_position := position - Vector3i(chunk.global_position)

	if chunk.set_block_without_rebuild(local_position, block):
		affected_chunks[chunk] = true

func get_surface_y(world_x: int, world_z: int) -> int:
	for y in range(Chunk.HEIGHT - 1, 0, -1):
		var block := get_block_at_world_position(Vector3i(world_x, y, world_z))

		if (block == BlockRegistry.Block.GRASS or block == BlockRegistry.Block.SAND):
			return y

	return -1

func generate_world_trees() -> void:
	var affected_chunks: Dictionary = {}

	var half_x := world_size_x / 2
	var half_z := world_size_z / 2

	var min_world_x := -half_x * Chunk.SIZE_XZ
	var max_world_x := half_x * Chunk.SIZE_XZ

	var min_world_z := -half_z * Chunk.SIZE_XZ
	var max_world_z := half_z * Chunk.SIZE_XZ

	for world_x in range(min_world_x + 2, max_world_x - 2):
		for world_z in range(min_world_z + 2, max_world_z - 2):
			if not should_generate_tree(world_x, world_z):
				continue

			var surface_y := get_surface_y(world_x, world_z)

			if surface_y < 0:
				continue

			create_world_tree(
				Vector3i(
					world_x,
					surface_y + 1,
					world_z
				),
				affected_chunks
			)

func should_generate_tree(world_x: int, world_z: int) -> bool:
	var biome_value := biome_noise.get_noise_2d(
		world_x,
		world_z
	)

	if biome_value < -0.25:
		return false

	var value := tree_noise.get_noise_2d(
		world_x,
		world_z
	)

	var threshold := 0.72

	if biome_value > 0.35:
		threshold = 0.45

	if value < threshold:
		return false

	var minimum_distance := 4

	for offset_x in range(-minimum_distance, minimum_distance + 1):
		for offset_z in range(-minimum_distance, minimum_distance + 1):
			if offset_x == 0 and offset_z == 0:
				continue

			if offset_x * offset_x + offset_z * offset_z > minimum_distance * minimum_distance:
				continue

			var neighbor_value := tree_noise.get_noise_2d(
				world_x + offset_x,
				world_z + offset_z
			)

			if neighbor_value > value:
				return false

	return true

func create_world_tree(
	position: Vector3i,
	affected_chunks: Dictionary
) -> void:
	const TRUNK_HEIGHT := 4

	for y in TRUNK_HEIGHT:
		set_block_at_world_position(
			position + Vector3i(0, y, 0),
			BlockRegistry.Block.WOOD,
			affected_chunks
		)

	var leaves_center := position + Vector3i(0, TRUNK_HEIGHT, 0)

	for offset_x in range(-2, 3):
		for offset_y in range(-2, 2):
			for offset_z in range(-2, 3):
				if abs(offset_x) + abs(offset_z) > 3:
					continue

				set_block_at_world_position(
					leaves_center + Vector3i(
						offset_x,
						offset_y,
						offset_z
					),
					BlockRegistry.Block.LEAVES,
					affected_chunks
				)

	set_block_at_world_position(
		leaves_center + Vector3i(0, 2, 0),
		BlockRegistry.Block.LEAVES,
		affected_chunks
	)

func rebuild_all_chunks() -> void:
	for child in get_children():
		if child is Chunk:
			child.rebuild_mesh()


func setup_ore_noise(noise: FastNoiseLite, noise_seed: int, frequency: float) -> void:
	noise.seed = noise_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 2
	noise.fractal_gain = 0.5

func spawn_item(item_id: int, position: Vector3, amount: int = 1) -> void:
	if dropped_item_scene == null:
		return

	if item_id == ItemRegistry.Item.NONE:
		return

	var dropped_item := dropped_item_scene.instantiate() as DroppedItem

	if dropped_item == null:
		return

	dropped_item.item_id = item_id
	dropped_item.amount = amount

	add_child(dropped_item)

	dropped_item.global_position = position

func rebuild_chunk_and_neighbors(chunk: Chunk, local_position: Vector3i) -> void:
	chunk.rebuild_mesh()

	if local_position.x == 0:
		rebuild_chunk_at(chunk.chunk_position + Vector2i(-1, 0))

	elif local_position.x == Chunk.SIZE_XZ - 1:
		rebuild_chunk_at(chunk.chunk_position + Vector2i(1, 0))

	if local_position.z == 0:
		rebuild_chunk_at(chunk.chunk_position + Vector2i(0, -1))

	elif local_position.z == Chunk.SIZE_XZ - 1:
		rebuild_chunk_at(chunk.chunk_position + Vector2i(0, 1))

func rebuild_chunk_at(chunk_position: Vector2i) -> void:
	var chunk_name := "Chunk_%d_%d" % [chunk_position.x, chunk_position.y]

	var chunk := get_node_or_null(chunk_name) as Chunk

	if chunk:
		chunk.rebuild_mesh()
