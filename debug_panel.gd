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
	var streaming_metrics := world.get_streaming_metrics()

	text = """
XYZ: %.2f / %.2f / %.2f
Block: %d / %d / %d
Chunk: %d / %d
Biome: %s
Biome Value: %.3f
Seed: %d
FPS: %d
Chunks loaded: %d
Streaming target/visible/ready: %d / %d / %d
Chunks with collider: %d
Generating/meshing/collider: %d / %d / %d
Queues work/unload (max): %d / %d (%d / %d)
Collider queue (max): %d (%d)
Collision shapes: %d
Managed C# memory: %.1f MB
Rendered faces: %d
Last mesh: %d faces / %.2f ms worker / %.2f ms apply
Torches: %d
Particle emitters/budget: %d / %d
Block light: %d
Sun light: %d
Final voxel light: %d
BlockLight updates: %d
BlockLight last: %.2f ms / %d chunks
SunLight updates: %d
SunLight last: %.2f ms / %d chunks
Sun remove/reprop: %.2f / %.2f ms
Streaming main budget/used: %.1f / %.2f ms
Streaming tasks/deferred: %d / %d
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
		world.get_loaded_chunk_count(),
		int(streaming_metrics.get("target_chunks", 0)),
		int(streaming_metrics.get("visible_chunks", 0)),
		int(streaming_metrics.get("ready_chunks", 0)),
		int(streaming_metrics.get("chunks_with_collision", 0)),
		int(streaming_metrics.get("generating_chunks", 0)),
		int(streaming_metrics.get("meshing_chunks", 0)),
		int(streaming_metrics.get("waiting_collision_chunks", 0)),
		int(streaming_metrics.get("work_queue", 0)),
		int(streaming_metrics.get("unload_queue", 0)),
		int(streaming_metrics.get("max_work_queue", 0)),
		int(streaming_metrics.get("max_unload_queue", 0)),
		int(streaming_metrics.get("collision_queue", 0)),
		int(streaming_metrics.get("max_collision_queue", 0)),
		int(streaming_metrics.get("collision_shapes", 0)),
		float(streaming_metrics.get("managed_memory", 0)) / 1048576.0,
		world.get_total_rendered_face_count(),
		world.mesh_last_face_count,
		float(world.mesh_last_worker_usec) / 1000.0,
		float(world.mesh_last_apply_usec) / 1000.0,
		world.get_active_torch_count(),
		world.get_active_particle_emitter_count(),
		world.get_active_particle_budget(),
		world.get_block_light_at_world_position(block_position),
		world.get_sun_light_at_world_position(block_position),
		maxi(world.get_block_light_at_world_position(block_position), world.get_sun_light_at_world_position(block_position)),
		world.block_light_update_count,
		float(world.block_light_last_update_usec) / 1000.0,
		world.block_light_last_changed_chunks,
		world.sunlight_update_count,
		float(world.sunlight_last_update_usec) / 1000.0,
		world.sunlight_last_changed_chunks,
		float(world.sunlight_last_removal_usec) / 1000.0,
		float(world.sunlight_last_propagation_usec) / 1000.0,
		world.streaming_main_thread_budget_ms,
		float(world.streaming_main_used_usec) / 1000.0,
		world.streaming_main_tasks_executed,
		world.streaming_main_deferred_tasks
	]


func get_biome_name(value: float) -> String:
	if value < -0.25:
		return "Desierto"

	if value > 0.35:
		return "Bosque"

	return "Pradera"
