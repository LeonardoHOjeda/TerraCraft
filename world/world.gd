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


func generate_world() -> void:
	for chunk_x in world_size_x:
		for chunk_z in world_size_z:
			create_chunk(chunk_x, chunk_z)

	generate_world_trees()


func create_chunk(chunk_x: int, chunk_z: int) -> void:
	if chunk_scene == null:
		return

	var chunk := chunk_scene.instantiate() as Chunk

	chunk.position = Vector3(chunk_x * Chunk.SIZE_XZ, 0, chunk_z * Chunk.SIZE_XZ)

	chunk.name = "Chunk_%d_%d" % [chunk_x, chunk_z]

	add_child(chunk)

	chunk.initialize(
		Vector2i(chunk_x, chunk_z),
		continental_noise,
		detail_noise,
		biome_noise,
		tree_noise,
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
		var block := get_block_at_world_position(
			Vector3i(world_x, y, world_z)
		)

		if (
			block == BlockRegistry.Block.GRASS
			or block == BlockRegistry.Block.SAND
		):
			return y

	return -1