class_name World
extends Node3D

@export var chunk_scene: PackedScene

@export var world_size_x: int = 8
@export var world_size_z: int = 8

@export var seed: int = 12345
@export var terrain_frequency: float = 0.025

@export var base_height: int = 20
@export var terrain_height: int = 20

var continental_noise := FastNoiseLite.new()
var detail_noise := FastNoiseLite.new()
var biome_noise := FastNoiseLite.new()
var tree_noise := FastNoiseLite.new()
var cave_noise := FastNoiseLite.new()

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
