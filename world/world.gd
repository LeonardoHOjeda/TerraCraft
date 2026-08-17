class_name World
extends Node3D

const INVALID_CHUNK_POSITION := Vector2i(2147483647, 2147483647)
const MAX_TREE_LOGS := 64
const TREE_LOG_DIRECTIONS: Array[Vector3i] = [
	Vector3i.UP,
	Vector3i.DOWN,
	Vector3i.LEFT,
	Vector3i.RIGHT,
	Vector3i.FORWARD,
	Vector3i.BACK,
]

@export var chunk_scene: PackedScene
@export_node_path("Node3D") var player_path: NodePath
@export_range(0, 32, 1) var load_distance: int = 3
@export_range(1, 40, 1) var unload_distance: int = 4
@export_range(1, 16, 1) var streaming_steps_per_frame: int = 1
@export_range(1, 8, 1) var max_background_jobs: int = 2
@export var log_chunk_timings: bool = true
@export var log_chunk_load_profile: bool = false
@export_range(1, 100, 1) var timing_samples_to_log: int = 12
@export var log_neighbor_rebuild_timings: bool = false
@export var log_gameplay_rebuild_timings: bool = false
@export_range(0.05, 0.5, 0.01) var gameplay_collision_delay: float = 0.15
@export var log_gameplay_collision_stats: bool = false
@export var log_chunk_override_application: bool = false
@export var log_collision_section_timings: bool = false
@export var log_tree_felling: bool = false

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

enum ChunkStage {
	GENERATE_DATA,
	GENERATING,
	BUILD_MESH_DATA,
	MESHING,
	APPLY_MESH,
	BUILD_COLLISION,
	READY,
}

var loaded_chunks: Dictionary = {}
var chunk_stages: Dictionary = {}
var work_queue: Array[Vector2i] = []
var queued_work: Dictionary = {}
var initial_chunks: Dictionary = {}
var chunk_timings: Dictionary = {}
var chunk_versions: Dictionary = {}
var version_counters: Dictionary = {}
var pending_mesh_data: Dictionary = {}
var active_jobs: Array[Dictionary] = []
var pending_generation_results: Array[Dictionary] = []
var gameplay_rebuilds: Dictionary = {}
var gameplay_collision_deadlines: Dictionary = {}
var gameplay_change_counts: Dictionary = {}
var gameplay_visual_rebuild_counts: Dictionary = {}
var chunk_overrides: Dictionary = {}
var special_block_metadata: Dictionary = {}
var pending_collision_sections: Dictionary = {}
var gameplay_collision_section_counts: Dictionary = {}
var timing_samples_logged: int = 0
var block_light_update_count: int = 0
var block_light_last_update_usec: int = 0
var block_light_last_changed_chunks: int = 0
var mesh_last_worker_usec: int = 0
var mesh_last_apply_usec: int = 0
var mesh_last_face_count: int = 0
var current_player_chunk := INVALID_CHUNK_POSITION
var player: Node3D


func _ready() -> void:
	setup_noise()
	resolve_player()
	if player != null:
		current_player_chunk = get_chunk_position(player.global_position)
		update_streaming_targets()


func _exit_tree() -> void:
	for job in active_jobs:
		var thread: Thread = job["thread"]
		if thread.is_started():
			thread.wait_to_finish()
	active_jobs.clear()


func _process(_delta: float) -> void:
	if player == null:
		resolve_player()
		if player == null:
			return
		current_player_chunk = get_chunk_position(player.global_position)
		update_streaming_targets()

	var new_player_chunk := get_chunk_position(player.global_position)
	if new_player_chunk != current_player_chunk:
		current_player_chunk = new_player_chunk
		update_streaming_targets()

	collect_finished_jobs()
	process_one_pending_generation_result()
	start_background_jobs()
	enqueue_due_gameplay_collisions()
	process_main_thread_queue()


func resolve_player() -> void:
	if player_path.is_empty():
		return
	player = get_node_or_null(player_path) as Node3D


func get_chunk_position(world_position: Vector3) -> Vector2i:
	return Vector2i(
		floori(world_position.x / float(Chunk.SIZE_XZ)),
		floori(world_position.z / float(Chunk.SIZE_XZ))
	)


func update_streaming_targets() -> void:
	unload_distance = maxi(unload_distance, load_distance + 1)

	for offset_x in range(-load_distance, load_distance + 1):
		for offset_z in range(-load_distance, load_distance + 1):
			var chunk_position := current_player_chunk + Vector2i(offset_x, offset_z)
			if chunk_stages.has(chunk_position):
				continue
			chunk_stages[chunk_position] = ChunkStage.GENERATE_DATA
			var next_version := int(version_counters.get(chunk_position, 0)) + 1
			version_counters[chunk_position] = next_version
			chunk_versions[chunk_position] = next_version
			initial_chunks[chunk_position] = true
			chunk_timings[chunk_position] = {
				"generation_worker_usec": 0,
				"generation_dispatch_usec": 0,
				"mesh_worker_usec": 0,
				"snapshot_usec": 0,
				"apply_mesh_usec": 0,
				"collision_usec": 0,
				"collision_sections_usec": {},
				"collision_section_frames": {},
				"apply_data_main_usec": 0,
				"special_blocks_main_usec": 0,
				"special_blocks_created": 0,
				"blocklight_clear_usec": 0,
				"blocklight_source_scan_usec": 0,
				"blocklight_border_reconcile_usec": 0,
				"blocklight_bfs_usec": 0,
				"blocklight_init_usec": 0,
				"blocklight_changed_neighbor_chunks": 0,
				"blocklight_neighbor_remesh_requests": 0,
				"snapshot_data_copy_usec": 0,
				"snapshot_block_borders_usec": 0,
				"snapshot_light_borders_usec": 0,
			}
			enqueue_work(chunk_position)

	var chunks_to_unload: Array[Vector2i] = []
	for chunk_position in chunk_stages:
		if chebyshev_distance(chunk_position, current_player_chunk) > unload_distance:
			chunks_to_unload.append(chunk_position)

	for chunk_position in chunks_to_unload:
		unload_chunk(chunk_position)


func enqueue_work(chunk_position: Vector2i) -> void:
	if queued_work.has(chunk_position):
		return
	work_queue.append(chunk_position)
	queued_work[chunk_position] = true


func start_background_jobs() -> void:
	var started := 0
	while active_jobs.size() < max_background_jobs and started < streaming_steps_per_frame:
		var chunk_position := pop_work_for_stages([ChunkStage.GENERATE_DATA, ChunkStage.BUILD_MESH_DATA])
		if chunk_position == INVALID_CHUNK_POSITION:
			return
		var stage: int = chunk_stages[chunk_position]
		var version: int = chunk_versions[chunk_position]
		var worker: RefCounted
		var callable: Callable
		if stage == ChunkStage.GENERATE_DATA:
			var dispatch_started_at := Time.get_ticks_usec()
			var parameters := create_generation_parameters(chunk_position)
			chunk_timings[chunk_position]["generation_dispatch_usec"] = Time.get_ticks_usec() - dispatch_started_at
			worker = ChunkGenerator.new()
			callable = Callable(worker, "generate_data").bind(parameters)
			chunk_stages[chunk_position] = ChunkStage.GENERATING
		else:
			var snapshot_started_at := Time.get_ticks_usec()
			var snapshot := create_meshing_snapshot(chunk_position)
			chunk_timings[chunk_position]["snapshot_usec"] = Time.get_ticks_usec() - snapshot_started_at
			worker = ChunkMesher.new()
			callable = Callable(worker, "build_mesh_data").bind(snapshot)
			chunk_stages[chunk_position] = ChunkStage.MESHING

		var thread := Thread.new()
		var error := thread.start(callable, Thread.PRIORITY_NORMAL)
		if error != OK:
			chunk_stages[chunk_position] = stage
			enqueue_work(chunk_position)
			return
		active_jobs.append({
			"thread": thread,
			"chunk_position": chunk_position,
			"version": version,
			"stage": stage,
			"worker": worker,
		})
		started += 1


func collect_finished_jobs() -> void:
	for index in range(active_jobs.size() - 1, -1, -1):
		var job: Dictionary = active_jobs[index]
		var thread: Thread = job["thread"]
		if thread.is_alive():
			continue
		var result: Dictionary = thread.wait_to_finish()
		active_jobs.remove_at(index)
		var chunk_position: Vector2i = job["chunk_position"]
		var version: int = job["version"]
		if not chunk_versions.has(chunk_position) or chunk_versions[chunk_position] != version:
			continue
		if job["stage"] == ChunkStage.GENERATE_DATA:
			pending_generation_results.append({
				"chunk_position": chunk_position,
				"version": version,
				"result": result,
			})
		else:
			chunk_timings[chunk_position]["mesh_worker_usec"] = result["worker_usec"]
			pending_mesh_data[chunk_position] = result
			chunk_stages[chunk_position] = ChunkStage.APPLY_MESH
			enqueue_work(chunk_position)


func process_one_pending_generation_result() -> void:
	if pending_generation_results.is_empty():
		return
	pending_generation_results.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var a_position: Vector2i = a["chunk_position"]
			var b_position: Vector2i = b["chunk_position"]
			var a_distance := distance_squared(a_position, current_player_chunk)
			var b_distance := distance_squared(b_position, current_player_chunk)
			if a_distance == b_distance:
				if a_position.x == b_position.x:
					return a_position.y < b_position.y
				return a_position.x < b_position.x
			return a_distance < b_distance
	)
	while not pending_generation_results.is_empty():
		var pending: Dictionary = pending_generation_results.pop_front()
		var chunk_position: Vector2i = pending["chunk_position"]
		var version: int = pending["version"]
		if not chunk_versions.has(chunk_position) or chunk_versions[chunk_position] != version:
			continue
		apply_generated_data(chunk_position, pending["result"])
		return


func process_main_thread_queue() -> void:
	var steps := 0
	while steps < streaming_steps_per_frame:
		var chunk_position := pop_work_for_stages([ChunkStage.APPLY_MESH, ChunkStage.BUILD_COLLISION])
		if chunk_position == INVALID_CHUNK_POSITION:
			return
		if chunk_stages[chunk_position] == ChunkStage.APPLY_MESH:
			apply_chunk_mesh(chunk_position)
		else:
			build_chunk_collision(chunk_position)
		steps += 1


func pop_work_for_stages(stages: Array) -> Vector2i:
	sort_work_queue()
	for index in work_queue.size():
		var chunk_position := work_queue[index]
		if not chunk_stages.has(chunk_position):
			queued_work.erase(chunk_position)
			work_queue.remove_at(index)
			return pop_work_for_stages(stages)
		if stages.has(chunk_stages[chunk_position]):
			work_queue.remove_at(index)
			queued_work.erase(chunk_position)
			return chunk_position
	return INVALID_CHUNK_POSITION


func sort_work_queue() -> void:
	work_queue.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			var a_is_gameplay := gameplay_rebuilds.has(a)
			var b_is_gameplay := gameplay_rebuilds.has(b)
			if a_is_gameplay != b_is_gameplay:
				return a_is_gameplay
			var a_distance := distance_squared(a, current_player_chunk)
			var b_distance := distance_squared(b, current_player_chunk)
			if a_distance == b_distance:
				if a.x == b.x:
					return a.y < b.y
				return a.x < b.x
			return a_distance < b_distance
	)


func distance_squared(a: Vector2i, b: Vector2i) -> int:
	var difference := a - b
	return difference.x * difference.x + difference.y * difference.y


func chebyshev_distance(a: Vector2i, b: Vector2i) -> int:
	var difference := a - b
	return maxi(absi(difference.x), absi(difference.y))


func create_generation_parameters(chunk_position: Vector2i) -> Dictionary:
	var overrides_snapshot: Dictionary = {}
	if chunk_overrides.has(chunk_position):
		overrides_snapshot = (chunk_overrides[chunk_position] as Dictionary).duplicate(true)
	return {
		"chunk_position": chunk_position,
		"continental_noise": continental_noise.duplicate() as FastNoiseLite,
		"detail_noise": detail_noise.duplicate() as FastNoiseLite,
		"biome_noise": biome_noise.duplicate() as FastNoiseLite,
		"tree_noise": tree_noise.duplicate() as FastNoiseLite,
		"cave_noise": cave_noise.duplicate() as FastNoiseLite,
		"coal_noise": coal_noise.duplicate() as FastNoiseLite,
		"iron_noise": iron_noise.duplicate() as FastNoiseLite,
		"copper_noise": copper_noise.duplicate() as FastNoiseLite,
		"tin_noise": tin_noise.duplicate() as FastNoiseLite,
		"gold_noise": gold_noise.duplicate() as FastNoiseLite,
		"tungsten_noise": tungsten_noise.duplicate() as FastNoiseLite,
		"platinum_noise": platinum_noise.duplicate() as FastNoiseLite,
		"terrain_height": terrain_height,
		"base_height": base_height,
		"overrides": overrides_snapshot,
	}


func apply_generated_data(chunk_position: Vector2i, result: Dictionary) -> void:
	var apply_started_at := Time.get_ticks_usec()
	if chunk_scene == null:
		return
	var chunk := chunk_scene.instantiate() as Chunk
	if chunk == null:
		chunk_stages.erase(chunk_position)
		initial_chunks.erase(chunk_position)
		chunk_timings.erase(chunk_position)
		chunk_versions.erase(chunk_position)
		return
	chunk.position = Vector3(chunk_position.x * Chunk.SIZE_XZ, 0, chunk_position.y * Chunk.SIZE_XZ)
	chunk.name = "Chunk_%d_%d" % [chunk_position.x, chunk_position.y]
	add_child(chunk)
	loaded_chunks[chunk_position] = chunk
	chunk.initialize_from_data(self, chunk_position, result["data"])
	chunk_timings[chunk_position]["special_blocks_main_usec"] = chunk.last_special_blocks_sync_usec
	chunk_timings[chunk_position]["special_blocks_created"] = chunk.last_special_blocks_created
	chunk_timings[chunk_position]["apply_data_main_usec"] = (
		Time.get_ticks_usec() - apply_started_at - chunk.last_special_blocks_sync_usec
	)
	chunk_timings[chunk_position]["apply_data_frame"] = Engine.get_process_frames()
	var light_changed_chunks := initialize_chunk_block_light(chunk)
	if log_chunk_override_application and int(result.get("override_count", 0)) > 0:
		print(
			"Chunk (%d,%d): applying %d block overrides"
			% [chunk_position.x, chunk_position.y, int(result["override_count"])]
		)
	# Procedural data already includes the immutable override snapshot applied by the worker.
	chunk_timings[chunk_position]["generation_worker_usec"] = result["worker_usec"]
	chunk_stages[chunk_position] = ChunkStage.BUILD_MESH_DATA
	enqueue_work(chunk_position)
	var neighbor_remesh_requests := 0
	for changed_position in light_changed_chunks:
		if changed_position != chunk_position:
			request_chunk_rebuild(changed_position)
			neighbor_remesh_requests += 1
	chunk_timings[chunk_position]["blocklight_changed_neighbor_chunks"] = neighbor_remesh_requests
	chunk_timings[chunk_position]["blocklight_neighbor_remesh_requests"] = neighbor_remesh_requests


func create_meshing_snapshot(chunk_position: Vector2i) -> Dictionary:
	var chunk := loaded_chunks.get(chunk_position) as Chunk
	var data_copy_started_at := Time.get_ticks_usec()
	var data_snapshot := chunk.data.duplicate_data()
	var data_copy_elapsed := Time.get_ticks_usec() - data_copy_started_at
	var block_borders_started_at := Time.get_ticks_usec()
	var negative_x := create_empty_boundary()
	var positive_x := create_empty_boundary()
	var negative_z := create_empty_boundary()
	var positive_z := create_empty_boundary()
	var negative_x_light := create_empty_light_boundary()
	var positive_x_light := create_empty_light_boundary()
	var negative_z_light := create_empty_light_boundary()
	var positive_z_light := create_empty_light_boundary()
	copy_neighbor_x_boundary(negative_x, chunk_position + Vector2i.LEFT, ChunkData.SIZE_XZ - 1)
	copy_neighbor_x_boundary(positive_x, chunk_position + Vector2i.RIGHT, 0)
	copy_neighbor_z_boundary(negative_z, chunk_position + Vector2i.UP, ChunkData.SIZE_XZ - 1)
	copy_neighbor_z_boundary(positive_z, chunk_position + Vector2i.DOWN, 0)
	var block_borders_elapsed := Time.get_ticks_usec() - block_borders_started_at
	var light_borders_started_at := Time.get_ticks_usec()
	copy_neighbor_x_light_boundary(negative_x_light, chunk_position + Vector2i.LEFT, ChunkData.SIZE_XZ - 1)
	copy_neighbor_x_light_boundary(positive_x_light, chunk_position + Vector2i.RIGHT, 0)
	copy_neighbor_z_light_boundary(negative_z_light, chunk_position + Vector2i.UP, ChunkData.SIZE_XZ - 1)
	copy_neighbor_z_light_boundary(positive_z_light, chunk_position + Vector2i.DOWN, 0)
	var light_borders_elapsed := Time.get_ticks_usec() - light_borders_started_at
	if chunk_timings.has(chunk_position):
		chunk_timings[chunk_position]["snapshot_data_copy_usec"] = data_copy_elapsed
		chunk_timings[chunk_position]["snapshot_block_borders_usec"] = block_borders_elapsed
		chunk_timings[chunk_position]["snapshot_light_borders_usec"] = light_borders_elapsed
		chunk_timings[chunk_position]["snapshot_frame"] = Engine.get_process_frames()
	return {
		"data": data_snapshot,
		"negative_x": negative_x,
		"positive_x": positive_x,
		"negative_z": negative_z,
		"positive_z": positive_z,
		"negative_x_light": negative_x_light,
		"positive_x_light": positive_x_light,
		"negative_z_light": negative_z_light,
		"positive_z_light": positive_z_light,
	}


func create_empty_boundary() -> PackedInt32Array:
	var boundary := PackedInt32Array()
	boundary.resize(ChunkData.HEIGHT * ChunkData.SIZE_XZ)
	boundary.fill(BlockRegistry.Block.AIR)
	return boundary


func create_empty_light_boundary() -> PackedByteArray:
	var boundary := PackedByteArray()
	boundary.resize(ChunkData.HEIGHT * ChunkData.SIZE_XZ)
	boundary.fill(0)
	return boundary


func copy_neighbor_x_boundary(target: PackedInt32Array, neighbor_position: Vector2i, source_x: int) -> void:
	var neighbor := loaded_chunks.get(neighbor_position) as Chunk
	if neighbor == null:
		return
	for y in ChunkData.HEIGHT:
		for z in ChunkData.SIZE_XZ:
			target[y * ChunkData.SIZE_XZ + z] = neighbor.data.get_block(Vector3i(source_x, y, z))


func copy_neighbor_z_boundary(target: PackedInt32Array, neighbor_position: Vector2i, source_z: int) -> void:
	var neighbor := loaded_chunks.get(neighbor_position) as Chunk
	if neighbor == null:
		return
	for y in ChunkData.HEIGHT:
		for x in ChunkData.SIZE_XZ:
			target[y * ChunkData.SIZE_XZ + x] = neighbor.data.get_block(Vector3i(x, y, source_z))


func copy_neighbor_x_light_boundary(target: PackedByteArray, neighbor_position: Vector2i, source_x: int) -> void:
	var neighbor := loaded_chunks.get(neighbor_position) as Chunk
	if neighbor == null:
		return
	for y in ChunkData.HEIGHT:
		for z in ChunkData.SIZE_XZ:
			target[y * ChunkData.SIZE_XZ + z] = neighbor.data.get_block_light(Vector3i(source_x, y, z))


func copy_neighbor_z_light_boundary(target: PackedByteArray, neighbor_position: Vector2i, source_z: int) -> void:
	var neighbor := loaded_chunks.get(neighbor_position) as Chunk
	if neighbor == null:
		return
	for y in ChunkData.HEIGHT:
		for x in ChunkData.SIZE_XZ:
			target[y * ChunkData.SIZE_XZ + x] = neighbor.data.get_block_light(Vector3i(x, y, source_z))


func apply_chunk_mesh(chunk_position: Vector2i) -> void:
	var chunk := loaded_chunks.get(chunk_position) as Chunk
	if chunk == null or not pending_mesh_data.has(chunk_position):
		return
	var started_at := Time.get_ticks_usec()
	var mesh_data: Dictionary = pending_mesh_data[chunk_position]
	chunk.apply_mesh_data(mesh_data)
	mesh_last_worker_usec = int(mesh_data.get("worker_usec", 0))
	mesh_last_face_count = chunk.rendered_face_count
	pending_mesh_data.erase(chunk_position)
	mesh_last_apply_usec = Time.get_ticks_usec() - started_at
	chunk_timings[chunk_position]["apply_mesh_usec"] = mesh_last_apply_usec
	chunk_timings[chunk_position]["apply_mesh_frame"] = Engine.get_process_frames()
	if initial_chunks.has(chunk_position):
		set_all_collision_sections_pending(chunk_position)
		chunk_stages[chunk_position] = ChunkStage.BUILD_COLLISION
		enqueue_work(chunk_position)
	elif gameplay_rebuilds.has(chunk_position):
		gameplay_visual_rebuild_counts[chunk_position] = int(
			gameplay_visual_rebuild_counts.get(chunk_position, 0)
		) + 1
		if has_pending_collision_sections(chunk_position):
			chunk_stages[chunk_position] = ChunkStage.BUILD_COLLISION
			enqueue_work(chunk_position)
		else:
			chunk_stages[chunk_position] = ChunkStage.READY
	else:
		set_all_collision_sections_pending(chunk_position)
		chunk_stages[chunk_position] = ChunkStage.BUILD_COLLISION
		enqueue_work(chunk_position)


func enqueue_due_gameplay_collisions() -> void:
	var now := Time.get_ticks_usec()
	for chunk_position in gameplay_collision_deadlines:
		var deadlines: Dictionary = gameplay_collision_deadlines[chunk_position]
		var due_sections: Array[int] = []
		for section in deadlines:
			if now >= int(deadlines[section]):
				due_sections.append(section)
		for section in due_sections:
			deadlines.erase(section)
			add_pending_collision_section(chunk_position, section)
		gameplay_collision_deadlines[chunk_position] = deadlines
		if due_sections.is_empty():
			continue
		if not chunk_stages.has(chunk_position):
			continue
		if chunk_stages[chunk_position] != ChunkStage.READY:
			continue
		chunk_stages[chunk_position] = ChunkStage.BUILD_COLLISION
		enqueue_work(chunk_position)


func set_all_collision_sections_pending(chunk_position: Vector2i) -> void:
	var sections: Array[int] = []
	for section in Chunk.COLLISION_SECTION_COUNT:
		sections.append(section)
	pending_collision_sections[chunk_position] = sections


func add_pending_collision_section(chunk_position: Vector2i, section: int) -> void:
	var sections: Array = pending_collision_sections.get(chunk_position, [])
	if not sections.has(section):
		sections.append(section)
		sections.sort()
	pending_collision_sections[chunk_position] = sections


func has_pending_collision_sections(chunk_position: Vector2i) -> bool:
	return (
		pending_collision_sections.has(chunk_position)
		and not (pending_collision_sections[chunk_position] as Array).is_empty()
	)


func build_chunk_collision(chunk_position: Vector2i) -> void:
	var chunk := loaded_chunks.get(chunk_position) as Chunk
	if chunk == null or not has_pending_collision_sections(chunk_position):
		return
	var sections: Array = pending_collision_sections[chunk_position]
	var section: int = sections.pop_front()
	pending_collision_sections[chunk_position] = sections
	var started_at := Time.get_ticks_usec()
	chunk.build_collision_section(section)
	var elapsed := Time.get_ticks_usec() - started_at
	var section_timings: Dictionary = chunk_timings[chunk_position].get("collision_sections_usec", {})
	section_timings[section] = elapsed
	chunk_timings[chunk_position]["collision_sections_usec"] = section_timings
	var section_frames: Dictionary = chunk_timings[chunk_position].get("collision_section_frames", {})
	section_frames[section] = Engine.get_process_frames()
	chunk_timings[chunk_position]["collision_section_frames"] = section_frames
	chunk_timings[chunk_position]["collision_usec"] = int(
		chunk_timings[chunk_position].get("collision_usec", 0)
	) + elapsed
	if gameplay_rebuilds.has(chunk_position):
		gameplay_collision_section_counts[chunk_position] = int(
			gameplay_collision_section_counts.get(chunk_position, 0)
		) + 1
	if log_collision_section_timings:
		var min_y := section * Chunk.COLLISION_SECTION_HEIGHT
		var max_y := min_y + Chunk.COLLISION_SECTION_HEIGHT - 1
		print(
			"Collision section (%d,%d)[Y%d-%d]: %.2f ms"
			% [chunk_position.x, chunk_position.y, min_y, max_y, float(elapsed) / 1000.0]
		)

	if has_pending_collision_sections(chunk_position):
		chunk_stages[chunk_position] = ChunkStage.BUILD_COLLISION
		enqueue_work(chunk_position)
		return
	pending_collision_sections.erase(chunk_position)
	chunk_stages[chunk_position] = ChunkStage.READY

	if initial_chunks.has(chunk_position):
		initial_chunks.erase(chunk_position)
		if log_chunk_load_profile:
			print_chunk_load_profile(chunk_position)
		if log_chunk_timings and timing_samples_logged < timing_samples_to_log:
			print_chunk_timing(chunk_position, false)
			timing_samples_logged += 1
		request_cardinal_neighbor_rebuilds(chunk_position)
	elif gameplay_rebuilds.has(chunk_position) and gameplay_collision_deadlines_empty(chunk_position):
		if log_gameplay_rebuild_timings:
			print_gameplay_rebuild_timing(chunk_position)
		if log_gameplay_collision_stats:
			print_gameplay_collision_stats(chunk_position)
		gameplay_rebuilds.erase(chunk_position)
		gameplay_collision_deadlines.erase(chunk_position)
		gameplay_change_counts.erase(chunk_position)
		gameplay_visual_rebuild_counts.erase(chunk_position)
		gameplay_collision_section_counts.erase(chunk_position)
	elif log_neighbor_rebuild_timings:
		print_chunk_timing(chunk_position, true)


func gameplay_collision_deadlines_empty(chunk_position: Vector2i) -> bool:
	return (
		not gameplay_collision_deadlines.has(chunk_position)
		or (gameplay_collision_deadlines[chunk_position] as Dictionary).is_empty()
	)


func print_gameplay_rebuild_timing(chunk_position: Vector2i) -> void:
	var timing: Dictionary = chunk_timings.get(chunk_position, {})
	print(
		"Gameplay rebuild (%d,%d): snapshot main %.2f ms | mesh-data worker %.2f ms | apply mesh main %.2f ms | collision main %.2f ms"
		% [
			chunk_position.x,
			chunk_position.y,
			float(timing.get("snapshot_usec", 0)) / 1000.0,
			float(timing.get("mesh_worker_usec", 0)) / 1000.0,
			float(timing.get("apply_mesh_usec", 0)) / 1000.0,
			float(timing.get("collision_usec", 0)) / 1000.0,
		]
	)


func print_chunk_load_profile(chunk_position: Vector2i) -> void:
	var timing: Dictionary = chunk_timings.get(chunk_position, {})
	var collision_sections: Dictionary = timing.get("collision_sections_usec", {})
	var collision_frames: Dictionary = timing.get("collision_section_frames", {})
	var main_total_usec := (
		int(timing.get("generation_dispatch_usec", 0))
		+ int(timing.get("apply_data_main_usec", 0))
		+ int(timing.get("special_blocks_main_usec", 0))
		+ int(timing.get("blocklight_init_usec", 0))
		+ int(timing.get("snapshot_usec", 0))
		+ int(timing.get("apply_mesh_usec", 0))
		+ int(timing.get("collision_usec", 0))
	)
	var lines: Array[String] = [
		"Chunk (%d,%d) load profile:" % [chunk_position.x, chunk_position.y],
		"  MAIN apply data/setup: %.3f ms (frame %d)" % [float(timing.get("apply_data_main_usec", 0)) / 1000.0, int(timing.get("apply_data_frame", -1))],
		"  MAIN special blocks: %.3f ms (%d created)" % [float(timing.get("special_blocks_main_usec", 0)) / 1000.0, int(timing.get("special_blocks_created", 0))],
		"  MAIN BlockLight clear: %.3f ms" % [float(timing.get("blocklight_clear_usec", 0)) / 1000.0],
		"  MAIN BlockLight source scan: %.3f ms" % [float(timing.get("blocklight_source_scan_usec", 0)) / 1000.0],
		"  MAIN BlockLight border reconcile: %.3f ms" % [float(timing.get("blocklight_border_reconcile_usec", 0)) / 1000.0],
		"  MAIN BlockLight BFS: %.3f ms" % [float(timing.get("blocklight_bfs_usec", 0)) / 1000.0],
		"  MAIN BlockLight total: %.3f ms (frame %d)" % [float(timing.get("blocklight_init_usec", 0)) / 1000.0, int(timing.get("blocklight_frame", -1))],
		"  MAIN light neighbor effects: %d chunks changed / %d remesh requests" % [int(timing.get("blocklight_changed_neighbor_chunks", 0)), int(timing.get("blocklight_neighbor_remesh_requests", 0))],
		"  MAIN snapshot data copy: %.3f ms" % [float(timing.get("snapshot_data_copy_usec", 0)) / 1000.0],
		"  MAIN snapshot block borders: %.3f ms" % [float(timing.get("snapshot_block_borders_usec", 0)) / 1000.0],
		"  MAIN snapshot light borders: %.3f ms" % [float(timing.get("snapshot_light_borders_usec", 0)) / 1000.0],
		"  MAIN snapshot total: %.3f ms (frame %d)" % [float(timing.get("snapshot_usec", 0)) / 1000.0, int(timing.get("snapshot_frame", -1))],
		"  MAIN apply ArrayMesh: %.3f ms (frame %d)" % [float(timing.get("apply_mesh_usec", 0)) / 1000.0, int(timing.get("apply_mesh_frame", -1))],
	]
	for section in range(Chunk.COLLISION_SECTION_COUNT):
		lines.append(
			"  MAIN collision section %d: %.3f ms (frame %d)"
			% [section, float(collision_sections.get(section, 0)) / 1000.0, int(collision_frames.get(section, -1))]
		)
	lines.append("  MAIN collision total: %.3f ms" % [float(timing.get("collision_usec", 0)) / 1000.0])
	lines.append("  MAIN accumulated total: %.3f ms" % [float(main_total_usec) / 1000.0])
	lines.append("  BACKGROUND generation worker: %.3f ms" % [float(timing.get("generation_worker_usec", 0)) / 1000.0])
	lines.append("  BACKGROUND mesh-data worker: %.3f ms" % [float(timing.get("mesh_worker_usec", 0)) / 1000.0])
	print("\n".join(lines))


func print_gameplay_collision_stats(chunk_position: Vector2i) -> void:
	var timing: Dictionary = chunk_timings.get(chunk_position, {})
	print(
		"Gameplay collision (%d,%d): %d changes grouped | %d visual rebuilds | sections rebuilt %d/%d | collision total %.2f ms"
		% [
			chunk_position.x,
			chunk_position.y,
			int(gameplay_change_counts.get(chunk_position, 0)),
			int(gameplay_visual_rebuild_counts.get(chunk_position, 0)),
			int(gameplay_collision_section_counts.get(chunk_position, 0)),
			Chunk.COLLISION_SECTION_COUNT,
			float(timing.get("collision_usec", 0)) / 1000.0,
		]
	)


func print_chunk_timing(chunk_position: Vector2i, is_rebuild: bool) -> void:
	var timing: Dictionary = chunk_timings.get(chunk_position, {})
	if is_rebuild:
		print(
			"Chunk rebuild (%d,%d): snapshot main %.2f ms | mesh-data worker %.2f ms | apply mesh main %.2f ms | collision main %.2f ms"
			% [
				chunk_position.x,
				chunk_position.y,
				float(timing.get("snapshot_usec", 0)) / 1000.0,
				float(timing.get("mesh_worker_usec", 0)) / 1000.0,
				float(timing.get("apply_mesh_usec", 0)) / 1000.0,
				float(timing.get("collision_usec", 0)) / 1000.0,
			]
		)
		return
	print(
		"Chunk (%d,%d): generation dispatch main %.2f ms | generation worker %.2f ms | snapshot main %.2f ms | mesh-data worker %.2f ms | apply mesh main %.2f ms | collision main %.2f ms"
		% [
			chunk_position.x,
			chunk_position.y,
			float(timing.get("generation_dispatch_usec", 0)) / 1000.0,
			float(timing.get("generation_worker_usec", 0)) / 1000.0,
			float(timing.get("snapshot_usec", 0)) / 1000.0,
			float(timing.get("mesh_worker_usec", 0)) / 1000.0,
			float(timing.get("apply_mesh_usec", 0)) / 1000.0,
			float(timing.get("collision_usec", 0)) / 1000.0,
		]
	)


func unload_chunk(chunk_position: Vector2i) -> void:
	var chunk := loaded_chunks.get(chunk_position) as Chunk
	var departed_sources: Array[Dictionary] = []
	if chunk != null:
		for x in Chunk.SIZE_XZ:
			for y in Chunk.HEIGHT:
				for z in Chunk.SIZE_XZ:
					var local_position := Vector3i(x, y, z)
					var emission := BlockRegistry.get_light_emission(chunk.data.get_block(local_position))
					if emission > 0:
						departed_sources.append({"position": chunk.local_to_world(local_position), "level": emission})
		# Future persistence hook: save modified block overrides before removing this chunk.
		chunk.queue_free()
	loaded_chunks.erase(chunk_position)
	for index in range(pending_generation_results.size() - 1, -1, -1):
		if pending_generation_results[index]["chunk_position"] == chunk_position:
			pending_generation_results.remove_at(index)
	var light_changed_chunks := remove_departed_light_sources(departed_sources)
	chunk_stages.erase(chunk_position)
	initial_chunks.erase(chunk_position)
	chunk_timings.erase(chunk_position)
	chunk_versions.erase(chunk_position)
	pending_mesh_data.erase(chunk_position)
	queued_work.erase(chunk_position)
	gameplay_rebuilds.erase(chunk_position)
	gameplay_collision_deadlines.erase(chunk_position)
	gameplay_change_counts.erase(chunk_position)
	gameplay_visual_rebuild_counts.erase(chunk_position)
	pending_collision_sections.erase(chunk_position)
	gameplay_collision_section_counts.erase(chunk_position)
	request_cardinal_neighbor_rebuilds(chunk_position)
	for changed_position in light_changed_chunks:
		request_chunk_rebuild(changed_position)


func request_cardinal_neighbor_rebuilds(chunk_position: Vector2i) -> void:
	for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		request_chunk_rebuild(chunk_position + offset)


func request_chunk_rebuild(
	chunk_position: Vector2i,
	gameplay_priority: bool = false,
	collision_sections: Array[int] = []
) -> void:
	if not loaded_chunks.has(chunk_position):
		return
	if gameplay_priority:
		if not gameplay_rebuilds.has(chunk_position):
			gameplay_change_counts[chunk_position] = 0
			gameplay_visual_rebuild_counts[chunk_position] = 0
			gameplay_collision_section_counts[chunk_position] = 0
			gameplay_rebuilds[chunk_position] = true
		gameplay_change_counts[chunk_position] = int(
			gameplay_change_counts.get(chunk_position, 0)
		) + 1
		var deadline := Time.get_ticks_usec() + roundi(gameplay_collision_delay * 1000000.0)
		var deadlines: Dictionary = gameplay_collision_deadlines.get(chunk_position, {})
		for section in collision_sections:
			deadlines[section] = deadline
			remove_pending_collision_section(chunk_position, section)
		gameplay_collision_deadlines[chunk_position] = deadlines
	var stage: int = chunk_stages.get(chunk_position, ChunkStage.READY)
	if stage == ChunkStage.GENERATE_DATA or stage == ChunkStage.GENERATING:
		return
	var next_version := int(version_counters.get(chunk_position, 0)) + 1
	version_counters[chunk_position] = next_version
	chunk_versions[chunk_position] = next_version
	chunk_stages[chunk_position] = ChunkStage.BUILD_MESH_DATA
	pending_mesh_data.erase(chunk_position)
	chunk_timings[chunk_position]["snapshot_usec"] = 0
	chunk_timings[chunk_position]["mesh_worker_usec"] = 0
	chunk_timings[chunk_position]["apply_mesh_usec"] = 0
	chunk_timings[chunk_position]["collision_usec"] = 0
	enqueue_work(chunk_position)


func remove_pending_collision_section(chunk_position: Vector2i, section: int) -> void:
	if not pending_collision_sections.has(chunk_position):
		return
	var sections: Array = pending_collision_sections[chunk_position]
	sections.erase(section)
	pending_collision_sections[chunk_position] = sections


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


func get_chunk_at_world_position(world_position: Vector3i) -> Chunk:
	var chunk_position := Vector2i(
		floori(float(world_position.x) / Chunk.SIZE_XZ),
		floori(float(world_position.z) / Chunk.SIZE_XZ)
	)
	return loaded_chunks.get(chunk_position) as Chunk


func get_block_at_world_position(position: Vector3i) -> int:
	var chunk := get_chunk_at_world_position(position)
	if chunk == null:
		return BlockRegistry.Block.AIR
	return chunk.get_block_local(chunk.world_to_local(position))


func get_block_light_at_world_position(position: Vector3i) -> int:
	var chunk := get_chunk_at_world_position(position)
	if chunk == null:
		return 0
	return chunk.data.get_block_light(chunk.world_to_local(position))


func set_block_light_at_world_position(position: Vector3i, level: int, changed_chunks: Dictionary) -> bool:
	var chunk := get_chunk_at_world_position(position)
	if chunk == null:
		return false
	var local_position := chunk.world_to_local(position)
	var clamped_level := clampi(level, 0, 15)
	if chunk.data.get_block_light(local_position) == clamped_level:
		return false
	chunk.data.set_block_light(local_position, clamped_level)
	changed_chunks[chunk.chunk_position] = true
	return true


func initialize_chunk_block_light(chunk: Chunk) -> Dictionary:
	var init_started_at := Time.get_ticks_usec()
	var changed_chunks: Dictionary = {}
	var propagation_queue: Array[Vector3i] = []
	var clear_started_at := Time.get_ticks_usec()
	chunk.data.block_light.fill(0)
	var clear_elapsed := Time.get_ticks_usec() - clear_started_at
	var source_scan_started_at := Time.get_ticks_usec()
	var chunk_origin := Vector3i(chunk.chunk_position.x * Chunk.SIZE_XZ, 0, chunk.chunk_position.y * Chunk.SIZE_XZ)
	for block_index in chunk.data.emissive_block_indices:
		var local_position := chunk.data.get_position_from_index(block_index)
		var emission := BlockRegistry.get_light_emission(chunk.data.get_block(local_position))
		chunk.data.set_block_light(local_position, emission)
		propagation_queue.append(chunk_origin + local_position)
	var source_scan_elapsed := Time.get_ticks_usec() - source_scan_started_at
	var border_started_at := Time.get_ticks_usec()
	seed_light_from_x_border(chunk.chunk_position + Vector2i.LEFT, Chunk.SIZE_XZ - 1, propagation_queue)
	seed_light_from_x_border(chunk.chunk_position + Vector2i.RIGHT, 0, propagation_queue)
	seed_light_from_z_border(chunk.chunk_position + Vector2i.UP, Chunk.SIZE_XZ - 1, propagation_queue)
	seed_light_from_z_border(chunk.chunk_position + Vector2i.DOWN, 0, propagation_queue)
	var border_elapsed := Time.get_ticks_usec() - border_started_at
	var bfs_started_at := Time.get_ticks_usec()
	propagate_block_light(propagation_queue, changed_chunks)
	var bfs_elapsed := Time.get_ticks_usec() - bfs_started_at
	if chunk_timings.has(chunk.chunk_position):
		chunk_timings[chunk.chunk_position]["blocklight_clear_usec"] = clear_elapsed
		chunk_timings[chunk.chunk_position]["blocklight_source_scan_usec"] = source_scan_elapsed
		chunk_timings[chunk.chunk_position]["blocklight_border_reconcile_usec"] = border_elapsed
		chunk_timings[chunk.chunk_position]["blocklight_bfs_usec"] = bfs_elapsed
		chunk_timings[chunk.chunk_position]["blocklight_init_usec"] = Time.get_ticks_usec() - init_started_at
		chunk_timings[chunk.chunk_position]["blocklight_frame"] = Engine.get_process_frames()
	return changed_chunks


func seed_light_from_x_border(neighbor_position: Vector2i, neighbor_x: int, propagation_queue: Array[Vector3i]) -> void:
	var neighbor := loaded_chunks.get(neighbor_position) as Chunk
	if neighbor == null:
		return
	var neighbor_origin := Vector3i(neighbor_position.x * Chunk.SIZE_XZ, 0, neighbor_position.y * Chunk.SIZE_XZ)
	for y in Chunk.HEIGHT:
		for z in Chunk.SIZE_XZ:
			var local_position := Vector3i(neighbor_x, y, z)
			if neighbor.data.get_block_light(local_position) > 1:
				propagation_queue.append(neighbor_origin + local_position)


func seed_light_from_z_border(neighbor_position: Vector2i, neighbor_z: int, propagation_queue: Array[Vector3i]) -> void:
	var neighbor := loaded_chunks.get(neighbor_position) as Chunk
	if neighbor == null:
		return
	var neighbor_origin := Vector3i(neighbor_position.x * Chunk.SIZE_XZ, 0, neighbor_position.y * Chunk.SIZE_XZ)
	for y in Chunk.HEIGHT:
		for x in Chunk.SIZE_XZ:
			var local_position := Vector3i(x, y, neighbor_z)
			if neighbor.data.get_block_light(local_position) > 1:
				propagation_queue.append(neighbor_origin + local_position)


func update_block_light_after_change(world_position: Vector3i) -> Dictionary:
	var started_at := Time.get_ticks_usec()
	var changed_chunks: Dictionary = {}
	var removal_queue: Array[Dictionary] = []
	var propagation_queue: Array[Vector3i] = []
	var old_level := get_block_light_at_world_position(world_position)
	var block := get_block_at_world_position(world_position)
	var emission := BlockRegistry.get_light_emission(block)
	var target_level := emission if BlockRegistry.is_light_transparent(block) else 0
	if old_level > target_level:
		set_block_light_at_world_position(world_position, target_level, changed_chunks)
		removal_queue.append({"position": world_position, "level": old_level})
	elif target_level > old_level:
		set_block_light_at_world_position(world_position, target_level, changed_chunks)
		propagation_queue.append(world_position)
	for direction in TREE_LOG_DIRECTIONS:
		var neighbor_position := world_position + direction
		if get_block_light_at_world_position(neighbor_position) > 0:
			propagation_queue.append(neighbor_position)
	process_block_light_removal(removal_queue, propagation_queue, changed_chunks)
	propagate_block_light(propagation_queue, changed_chunks)
	block_light_update_count += 1
	block_light_last_update_usec = Time.get_ticks_usec() - started_at
	block_light_last_changed_chunks = changed_chunks.size()
	return changed_chunks


func process_block_light_removal(removal_queue: Array[Dictionary], propagation_queue: Array[Vector3i], changed_chunks: Dictionary) -> void:
	var index := 0
	while index < removal_queue.size():
		var entry: Dictionary = removal_queue[index]
		index += 1
		var position: Vector3i = entry["position"]
		var removed_level: int = entry["level"]
		for direction in TREE_LOG_DIRECTIONS:
			var neighbor_position := position + direction
			var neighbor_level := get_block_light_at_world_position(neighbor_position)
			if neighbor_level <= 0:
				continue
			var neighbor_emission := BlockRegistry.get_light_emission(get_block_at_world_position(neighbor_position))
			if neighbor_level < removed_level and neighbor_level > neighbor_emission:
				set_block_light_at_world_position(neighbor_position, neighbor_emission, changed_chunks)
				removal_queue.append({"position": neighbor_position, "level": neighbor_level})
				if neighbor_emission > 0:
					propagation_queue.append(neighbor_position)
			else:
				propagation_queue.append(neighbor_position)


func propagate_block_light(propagation_queue: Array[Vector3i], changed_chunks: Dictionary) -> void:
	var queue_chunks: Array[Chunk] = []
	var queue_indices := PackedInt32Array()
	for seed_position in propagation_queue:
		var seed_chunk := get_chunk_at_world_position(seed_position)
		if seed_chunk == null:
			continue
		var seed_origin := Vector3i(seed_chunk.chunk_position.x * Chunk.SIZE_XZ, 0, seed_chunk.chunk_position.y * Chunk.SIZE_XZ)
		var seed_local := seed_position - seed_origin
		if seed_chunk.data.is_valid_position(seed_local):
			queue_chunks.append(seed_chunk)
			queue_indices.append(seed_chunk.data.get_index(seed_local))
	var index := 0
	while index < queue_indices.size():
		var source_chunk := queue_chunks[index]
		var source_local := source_chunk.data.get_position_from_index(queue_indices[index])
		index += 1
		var source_block := source_chunk.data.get_block(source_local)
		var level := maxi(source_chunk.data.get_block_light(source_local), BlockRegistry.get_light_emission(source_block))
		if level <= 1:
			continue
		for direction in TREE_LOG_DIRECTIONS:
			var neighbor_local := source_local + direction
			var neighbor_chunk: Chunk = source_chunk
			if neighbor_local.y < 0 or neighbor_local.y >= Chunk.HEIGHT:
				continue
			var neighbor_chunk_position := source_chunk.chunk_position
			if neighbor_local.x < 0:
				neighbor_chunk_position += Vector2i.LEFT
				neighbor_local.x = Chunk.SIZE_XZ - 1
			elif neighbor_local.x >= Chunk.SIZE_XZ:
				neighbor_chunk_position += Vector2i.RIGHT
				neighbor_local.x = 0
			elif neighbor_local.z < 0:
				neighbor_chunk_position += Vector2i.UP
				neighbor_local.z = Chunk.SIZE_XZ - 1
			elif neighbor_local.z >= Chunk.SIZE_XZ:
				neighbor_chunk_position += Vector2i.DOWN
				neighbor_local.z = 0
			if neighbor_chunk_position != source_chunk.chunk_position:
				neighbor_chunk = loaded_chunks.get(neighbor_chunk_position) as Chunk
				if neighbor_chunk == null:
					continue
			var neighbor_block := neighbor_chunk.data.get_block(neighbor_local)
			if not BlockRegistry.is_light_transparent(neighbor_block):
				continue
			var desired_level := maxi(level - 1, BlockRegistry.get_light_emission(neighbor_block))
			if desired_level <= neighbor_chunk.data.get_block_light(neighbor_local):
				continue
			neighbor_chunk.data.set_block_light(neighbor_local, desired_level)
			changed_chunks[neighbor_chunk.chunk_position] = true
			queue_chunks.append(neighbor_chunk)
			queue_indices.append(neighbor_chunk.data.get_index(neighbor_local))


func remove_departed_light_sources(sources: Array[Dictionary]) -> Dictionary:
	var started_at := Time.get_ticks_usec()
	var changed_chunks: Dictionary = {}
	var propagation_queue: Array[Vector3i] = []
	process_block_light_removal(sources, propagation_queue, changed_chunks)
	propagate_block_light(propagation_queue, changed_chunks)
	if not sources.is_empty():
		block_light_update_count += 1
		block_light_last_update_usec = Time.get_ticks_usec() - started_at
		block_light_last_changed_chunks = changed_chunks.size()
	return changed_chunks


func set_special_block_support(chunk_position: Vector2i, local_position: Vector3i, support_direction: Vector3i) -> void:
	var chunk_metadata: Dictionary = special_block_metadata.get(chunk_position, {})
	chunk_metadata[local_position] = {"support_direction": support_direction}
	special_block_metadata[chunk_position] = chunk_metadata


func get_special_block_support(chunk_position: Vector2i, local_position: Vector3i) -> Vector3i:
	var chunk_metadata: Dictionary = special_block_metadata.get(chunk_position, {})
	var metadata: Dictionary = chunk_metadata.get(local_position, {})
	return metadata.get("support_direction", Vector3i.DOWN)


func clear_special_block_metadata(chunk_position: Vector2i, local_position: Vector3i) -> void:
	var chunk_metadata: Dictionary = special_block_metadata.get(chunk_position, {})
	chunk_metadata.erase(local_position)
	if chunk_metadata.is_empty():
		special_block_metadata.erase(chunk_position)
	else:
		special_block_metadata[chunk_position] = chunk_metadata


func break_torches_supported_by(support_world_position: Vector3i) -> void:
	var candidate_directions: Array[Vector3i] = [Vector3i.UP, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]
	for offset in candidate_directions:
		var torch_world_position := support_world_position + offset
		var chunk := get_chunk_at_world_position(torch_world_position)
		if chunk == null:
			continue
		var local_position := chunk.world_to_local(torch_world_position)
		if chunk.get_block_local(local_position) != BlockRegistry.Block.TORCH:
			continue
		var support_direction := get_special_block_support(chunk.chunk_position, local_position)
		if torch_world_position + support_direction != support_world_position:
			continue
		if chunk.remove_block_local(local_position) != BlockRegistry.Block.TORCH:
			continue
		rebuild_chunk_and_neighbors(chunk, local_position)
		spawn_item(ItemRegistry.Item.TORCH, Vector3(torch_world_position) + Vector3(0.5, 0.35, 0.5))


func set_block_at_world_position(position: Vector3i, block: int, affected_chunks: Dictionary) -> void:
	var chunk := get_chunk_at_world_position(position)
	if chunk == null:
		return
	var local_position := chunk.world_to_local(position)
	if chunk.set_block_local_if_empty(local_position, block):
		affected_chunks[chunk] = true


func get_surface_y(world_x: int, world_z: int) -> int:
	var chunk := get_chunk_at_world_position(Vector3i(world_x, 0, world_z))
	if chunk == null:
		return -1
	var local_position := chunk.world_to_local(Vector3i(world_x, 0, world_z))
	return chunk.get_surface_height(local_position.x, local_position.z)


func get_procedural_surface_y(world_x: int, world_z: int) -> int:
	var continental := continental_noise.get_noise_2d(world_x, world_z)
	var detail := detail_noise.get_noise_2d(world_x, world_z)
	return clampi(base_height + roundi(continental * terrain_height + detail * 4.0), 1, Chunk.HEIGHT - 1)


func is_procedural_tree_log(position: Vector3i) -> bool:
	if not should_generate_tree(position.x, position.z):
		return false
	var trunk_base_y := get_procedural_surface_y(position.x, position.z) + 1
	return position.y >= trunk_base_y and position.y < trunk_base_y + 4


func fell_tree(start_position: Vector3i) -> bool:
	if get_block_at_world_position(start_position) != BlockRegistry.Block.WOOD:
		return false
	if not is_procedural_tree_log(start_position):
		return false

	var logs: Array[Vector3i] = []
	var frontier: Array[Vector3i] = [start_position]
	var visited: Dictionary = {start_position: true}
	while not frontier.is_empty() and logs.size() < MAX_TREE_LOGS:
		var position: Vector3i = frontier.pop_front()
		if (
			get_block_at_world_position(position) != BlockRegistry.Block.WOOD
			or not is_procedural_tree_log(position)
		):
			continue
		logs.append(position)
		for direction in TREE_LOG_DIRECTIONS:
			var neighbor := position + direction
			if not visited.has(neighbor):
				visited[neighbor] = true
				frontier.append(neighbor)

	if logs.is_empty():
		return false

	var rebuild_sections: Dictionary = {}
	var modified_chunks: Dictionary = {}
	for position in logs:
		var chunk := get_chunk_at_world_position(position)
		if chunk == null:
			continue
		var local_position := chunk.world_to_local(position)
		var broken_block := chunk.remove_block_local(local_position)
		if broken_block != BlockRegistry.Block.WOOD:
			continue
		break_torches_supported_by(position)
		record_block_override(chunk, local_position)
		modified_chunks[chunk.chunk_position] = true
		add_tree_rebuild_target(rebuild_sections, chunk.chunk_position, local_position.y)
		for neighbor_position in chunk.get_affected_neighbor_positions(local_position):
			add_tree_rebuild_target(rebuild_sections, neighbor_position, local_position.y)
		var dropped_item := ItemRegistry.get_drop(broken_block)
		if dropped_item != ItemRegistry.Item.NONE:
			var drop_offset := Vector3(randf_range(-0.18, 0.18), 0.5, randf_range(-0.18, 0.18))
			spawn_item(dropped_item, Vector3(position) + Vector3(0.5, 0.0, 0.5) + drop_offset)

	for chunk_position in rebuild_sections:
		var sections: Array[int] = []
		for section in rebuild_sections[chunk_position]:
			sections.append(section)
		sections.sort()
		request_chunk_rebuild(chunk_position, true, sections)

	if log_tree_felling:
		print("Tree felled: %d logs across %d chunks" % [logs.size(), modified_chunks.size()])
	return true


func add_tree_rebuild_target(targets: Dictionary, chunk_position: Vector2i, local_y: int) -> void:
	if not loaded_chunks.has(chunk_position):
		return
	var sections: Dictionary = targets.get(chunk_position, {})
	for section in get_affected_collision_sections(local_y):
		sections[section] = true
	targets[chunk_position] = sections


func apply_trees_to_chunk(chunk: Chunk) -> void:
	const TREE_RADIUS := 2
	var min_world_x := chunk.chunk_position.x * Chunk.SIZE_XZ
	var min_world_z := chunk.chunk_position.y * Chunk.SIZE_XZ
	var max_world_x := min_world_x + Chunk.SIZE_XZ - 1
	var max_world_z := min_world_z + Chunk.SIZE_XZ - 1

	for world_x in range(min_world_x - TREE_RADIUS, max_world_x + TREE_RADIUS + 1):
		for world_z in range(min_world_z - TREE_RADIUS, max_world_z + TREE_RADIUS + 1):
			if not should_generate_tree(world_x, world_z):
				continue
			var surface_y := get_procedural_surface_y(world_x, world_z)
			create_tree_part_in_chunk(Vector3i(world_x, surface_y + 1, world_z), chunk)


func should_generate_tree(world_x: int, world_z: int) -> bool:
	var biome_value := biome_noise.get_noise_2d(world_x, world_z)
	if biome_value < -0.25:
		return false

	var value := tree_noise.get_noise_2d(world_x, world_z)
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
			var neighbor_value := tree_noise.get_noise_2d(world_x + offset_x, world_z + offset_z)
			if neighbor_value > value:
				return false
	return true


func create_tree_part_in_chunk(position: Vector3i, chunk: Chunk) -> void:
	const TRUNK_HEIGHT := 4
	for y in TRUNK_HEIGHT:
		set_procedural_tree_block(position + Vector3i(0, y, 0), BlockRegistry.Block.WOOD, chunk)

	var leaves_center := position + Vector3i(0, TRUNK_HEIGHT, 0)
	for offset_x in range(-2, 3):
		for offset_y in range(-2, 2):
			for offset_z in range(-2, 3):
				if abs(offset_x) + abs(offset_z) > 3:
					continue
				set_procedural_tree_block(
					leaves_center + Vector3i(offset_x, offset_y, offset_z),
					BlockRegistry.Block.LEAVES,
					chunk
				)
	set_procedural_tree_block(leaves_center + Vector3i(0, 2, 0), BlockRegistry.Block.LEAVES, chunk)


func set_procedural_tree_block(world_position: Vector3i, block: int, chunk: Chunk) -> void:
	var target_position := Vector2i(
		floori(float(world_position.x) / Chunk.SIZE_XZ),
		floori(float(world_position.z) / Chunk.SIZE_XZ)
	)
	if target_position != chunk.chunk_position:
		return
	chunk.set_block_local_if_empty(chunk.world_to_local(world_position), block)


func setup_ore_noise(noise: FastNoiseLite, noise_seed: int, frequency: float) -> void:
	noise.seed = noise_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 2
	noise.fractal_gain = 0.5


func spawn_item(item_id: int, position: Vector3, amount: int = 1) -> void:
	if dropped_item_scene == null or item_id == ItemRegistry.Item.NONE:
		return
	var dropped_item := dropped_item_scene.instantiate() as DroppedItem
	if dropped_item == null:
		return
	dropped_item.item_id = item_id
	dropped_item.amount = amount
	add_child(dropped_item)
	dropped_item.global_position = position


func get_loaded_chunk_count() -> int:
	return loaded_chunks.size()


func get_total_rendered_face_count() -> int:
	var total := 0
	for chunk in loaded_chunks.values():
		if chunk is Chunk:
			total += (chunk as Chunk).rendered_face_count
	return total


func get_active_torch_count() -> int:
	var total := 0
	for chunk in loaded_chunks.values():
		if chunk is Chunk:
			total += (chunk as Chunk).get_torch_count()
	return total


func get_active_particle_emitter_count() -> int:
	var total := 0
	for chunk in loaded_chunks.values():
		if chunk is Chunk:
			total += (chunk as Chunk).get_particle_emitter_count()
	return total


func get_active_particle_budget() -> int:
	var total := 0
	for chunk in loaded_chunks.values():
		if chunk is Chunk:
			total += (chunk as Chunk).get_particle_budget()
	return total


func rebuild_chunk_and_neighbors(chunk: Chunk, local_position: Vector3i) -> void:
	record_block_override(chunk, local_position)
	var light_changed_chunks := update_block_light_after_change(chunk.local_to_world(local_position))
	var collision_sections := get_affected_collision_sections(local_position.y)
	request_chunk_rebuild(chunk.chunk_position, true, collision_sections)
	for neighbor_position in chunk.get_affected_neighbor_positions(local_position):
		request_chunk_rebuild(neighbor_position, true, collision_sections)
	for changed_position in light_changed_chunks:
		if changed_position != chunk.chunk_position and not chunk.get_affected_neighbor_positions(local_position).has(changed_position):
			request_chunk_rebuild(changed_position, true)


func get_affected_collision_sections(local_y: int) -> Array[int]:
	var section := clampi(
		floori(float(local_y) / Chunk.COLLISION_SECTION_HEIGHT),
		0,
		Chunk.COLLISION_SECTION_COUNT - 1
	)
	var sections: Array[int] = [section]
	var section_local_y := local_y % Chunk.COLLISION_SECTION_HEIGHT
	if section_local_y == 0 and section > 0:
		sections.append(section - 1)
	elif (
		section_local_y == Chunk.COLLISION_SECTION_HEIGHT - 1
		and section < Chunk.COLLISION_SECTION_COUNT - 1
	):
		sections.append(section + 1)
	sections.sort()
	return sections


func rebuild_chunk_at(chunk_position: Vector2i) -> void:
	var all_sections: Array[int] = []
	for section in Chunk.COLLISION_SECTION_COUNT:
		all_sections.append(section)
	request_chunk_rebuild(chunk_position, true, all_sections)


func record_block_override(chunk: Chunk, local_position: Vector3i) -> void:
	if chunk == null or not chunk.is_valid_local_position(local_position):
		return
	var overrides: Dictionary = chunk_overrides.get(chunk.chunk_position, {})
	overrides[local_position] = chunk.get_block_local(local_position)
	chunk_overrides[chunk.chunk_position] = overrides
