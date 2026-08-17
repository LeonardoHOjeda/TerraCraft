extends Label

@export var player: Player
@export var world: World

var debug_visible := false


func _ready() -> void:
	visible = false


func _process(_delta: float) -> void:
	if not debug_visible:
		return

	update_debug_info()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		debug_visible = !debug_visible
		visible = debug_visible


func update_debug_info() -> void:
	if player == null or world == null:
		return

	var position := player.global_position

	var block_position := Vector3i(
		floori(position.x),
		floori(position.y),
		floori(position.z)
	)

	var chunk_x := floori(position.x / Chunk.SIZE_XZ)
	var chunk_z := floori(position.z / Chunk.SIZE_XZ)

	var biome_value := world.biome_noise.get_noise_2d(
		position.x,
		position.z
	)

	var biome_name := get_biome_name(biome_value)

	text = """
XYZ: %.2f / %.2f / %.2f
Block: %d / %d / %d
Chunk: %d / %d
Biome: %s
Biome Value: %.3f
Seed: %d
FPS: %d
Torch lights loaded: %d
Block light: %d
BlockLight updates: %d
BlockLight last: %.2f ms / %d chunks
""" % [
		position.x,
		position.y,
		position.z,
		block_position.x,
		block_position.y,
		block_position.z,
		chunk_x,
		chunk_z,
		biome_name,
		biome_value,
		world.seed,
		Engine.get_frames_per_second(),
		world.get_loaded_torch_light_count(),
		world.get_block_light_at_world_position(block_position),
		world.block_light_update_count,
		float(world.block_light_last_update_usec) / 1000.0,
		world.block_light_last_changed_chunks
	]


func get_biome_name(value: float) -> String:
	if value < -0.25:
		return "Desierto"

	if value > 0.35:
		return "Bosque"

	return "Pradera"
