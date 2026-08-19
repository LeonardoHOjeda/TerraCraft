class_name World
extends Node3D

const INVALID_CHUNK_POSITION := Vector2i(2147483647, 2147483647)
const MAX_TREE_LOGS := 64
const LEAF_SUPPORT_DISTANCE := 6
const MAX_LEAF_BFS_NODES := 256
const LEAF_DECAY_DELAY_SECONDS := 0.45
const LEAF_DISAPPEAR_MIN_MSEC := 500
const LEAF_DISAPPEAR_MAX_MSEC := 3000
const LEAF_AMBIGUOUS_RETRY_SECONDS := 1.0
const MAX_LEAF_VALIDATIONS_PER_FRAME := 4
const MAX_LEAVES_REMOVED_PER_FRAME := 4
const MAX_BACKGROUND_STREAMING_JOBS := 1
const USE_CSHARP_CHUNK_MESHER := true
const USE_CSHARP_CHUNK_GENERATOR := true
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
@export_range(0, 8, 1) var max_chunk_unloads_per_frame: int = 1
@export_range(0.5, 20.0, 0.5) var streaming_main_thread_budget_ms: float = 4.0
@export var log_streaming_main_thread_frames: bool = false
@export var log_stutter_frames: bool = true
@export_range(1.0, 240.0, 1.0) var stutter_fps_threshold: float = 55.0
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
var sunlight_update_count: int = 0
var sunlight_last_update_usec: int = 0
var sunlight_last_removal_usec: int = 0
var sunlight_last_propagation_usec: int = 0
var sunlight_last_changed_chunks: int = 0
var mesh_last_worker_usec: int = 0
var mesh_last_apply_usec: int = 0
var mesh_last_face_count: int = 0
var current_player_chunk := INVALID_CHUNK_POSITION
var player: Node3D
var streaming_main_used_usec: int = 0
var streaming_main_tasks_executed: int = 0
var streaming_main_deferred_tasks: int = 0
var streaming_main_last_tasks: Array[String] = []
var streaming_main_last_task_details: Array[Dictionary] = []
var streaming_main_task_total_usec: int = 0
var streaming_main_frame_started_usec: int = 0
var previous_streaming_frame_profile: Dictionary = {}
var worst_stutter_frames: Array[Dictionary] = []
var gc_diagnostics := GcDiagnosticsCs.new()
var previous_gc_frame_snapshot: Dictionary = {}
var streaming_targets_update_usec: int = 0
var streaming_targets_unload_usec: int = 0
var streaming_targets_unloaded_count: int = 0
var streaming_targets_unload_profiles: Array[Dictionary] = []
var pending_chunk_unloads: Array[Vector2i] = []
var queued_chunk_unloads: Dictionary = {}
var pending_leaf_checks: Dictionary = {}
var pending_leaf_decay: Dictionary = {}


func _ready() -> void:
	setup_noise()
	resolve_player()
	if player != null:
		current_player_chunk = get_chunk_position(player.global_position)
		update_streaming_targets()


func _exit_tree() -> void:
	if log_stutter_frames:
		print_stutter_top_frames()
	for job in active_jobs:
		var thread: Thread = job["thread"]
		if thread.is_started():
			thread.wait_to_finish()
	active_jobs.clear()


func _process(_delta: float) -> void:
	profile_previous_frame_stutter(_delta)
	reset_streaming_targets_profile()
	var targets_started_at := Time.get_ticks_usec()
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
	process_pending_chunk_unloads()
	process_pending_leaf_checks()
	process_pending_leaf_decay()
	streaming_targets_update_usec = Time.get_ticks_usec() - targets_started_at

	begin_streaming_main_frame()
	collect_finished_jobs()
	enqueue_due_gameplay_collisions()
	process_main_thread_queue(true)
	process_one_pending_generation_result()
	process_main_thread_queue(false)
	start_background_jobs()
	finish_streaming_main_frame()


func reset_streaming_targets_profile() -> void:
	streaming_targets_update_usec = 0
	streaming_targets_unload_usec = 0
	streaming_targets_unloaded_count = 0
	streaming_targets_unload_profiles.clear()


func begin_streaming_main_frame() -> void:
	streaming_main_frame_started_usec = Time.get_ticks_usec()
	streaming_main_used_usec = 0
	streaming_main_tasks_executed = 0
	streaming_main_last_tasks.clear()
	streaming_main_last_task_details.clear()
	streaming_main_task_total_usec = 0


func streaming_budget_reached() -> bool:
	if streaming_main_tasks_executed == 0:
		return false
	return (
		Time.get_ticks_usec() - streaming_main_frame_started_usec
		>= roundi(streaming_main_thread_budget_ms * 1000.0)
	)


func record_streaming_main_task(
	task_name: String, task_started_usec: int, breakdown: Dictionary = {}
) -> void:
	var duration_usec := Time.get_ticks_usec() - task_started_usec
	streaming_main_tasks_executed += 1
	streaming_main_last_tasks.append(task_name)
	streaming_main_last_task_details.append({
		"name": task_name,
		"duration_usec": duration_usec,
		"breakdown": breakdown,
	})
	streaming_main_task_total_usec += duration_usec
	streaming_main_used_usec = Time.get_ticks_usec() - streaming_main_frame_started_usec


func finish_streaming_main_frame() -> void:
	streaming_main_used_usec = Time.get_ticks_usec() - streaming_main_frame_started_usec
	streaming_main_deferred_tasks = count_deferred_streaming_main_tasks()
	previous_streaming_frame_profile = {
		"frame": Engine.get_process_frames(),
		"streaming_wall_usec": streaming_main_used_usec,
		"streaming_task_usec": streaming_main_task_total_usec,
		"tasks": streaming_main_last_task_details.duplicate(true),
		"generation_worker_active": has_active_background_stage(ChunkStage.GENERATE_DATA),
		"mesh_worker_active": has_active_background_stage(ChunkStage.BUILD_MESH_DATA),
		"active_jobs": active_jobs.size(),
		"deferred": streaming_main_deferred_tasks,
		"targets_update_usec": streaming_targets_update_usec,
		"targets_unload_usec": streaming_targets_unload_usec,
		"targets_unloaded_count": streaming_targets_unloaded_count,
		"unload_profiles": streaming_targets_unload_profiles.duplicate(true),
	}
	if log_streaming_main_thread_frames and streaming_main_tasks_executed > 0:
		print(
			"Frame %d streaming main: %.3f ms | %s | deferred %d"
			% [
				Engine.get_process_frames(),
				float(streaming_main_used_usec) / 1000.0,
				", ".join(streaming_main_last_tasks),
				streaming_main_deferred_tasks,
			]
		)


func has_active_background_stage(stage: int) -> bool:
	for job in active_jobs:
		if int(job.get("stage", -1)) == stage:
			return true
	return false


func profile_previous_frame_stutter(delta: float) -> void:
	var current_gc_snapshot: Dictionary = gc_diagnostics.Capture()
	var gc_frame_delta := {
		"gen0": 0,
		"gen1": 0,
		"gen2": 0,
		"gen0_total": int(current_gc_snapshot["gen0"]),
		"gen1_total": int(current_gc_snapshot["gen1"]),
		"gen2_total": int(current_gc_snapshot["gen2"]),
		"managed_memory": int(current_gc_snapshot["managed_memory"]),
		"managed_memory_delta": 0,
		"total_allocated_bytes": int(current_gc_snapshot["total_allocated_bytes"]),
		"allocated_bytes_delta": 0,
	}
	if not previous_gc_frame_snapshot.is_empty():
		gc_frame_delta["gen0"] = int(current_gc_snapshot["gen0"]) - int(previous_gc_frame_snapshot["gen0"])
		gc_frame_delta["gen1"] = int(current_gc_snapshot["gen1"]) - int(previous_gc_frame_snapshot["gen1"])
		gc_frame_delta["gen2"] = int(current_gc_snapshot["gen2"]) - int(previous_gc_frame_snapshot["gen2"])
		gc_frame_delta["managed_memory_delta"] = int(current_gc_snapshot["managed_memory"]) - int(previous_gc_frame_snapshot["managed_memory"])
		gc_frame_delta["allocated_bytes_delta"] = int(current_gc_snapshot["total_allocated_bytes"]) - int(previous_gc_frame_snapshot["total_allocated_bytes"])
	previous_gc_frame_snapshot = current_gc_snapshot
	if previous_streaming_frame_profile.is_empty() or delta <= 0.0:
		return

	var frame_time_ms := delta * 1000.0
	var instantaneous_fps := 1.0 / delta

	if instantaneous_fps >= stutter_fps_threshold:
		return

	var sample := previous_streaming_frame_profile.duplicate(true)
	sample["frame_time_ms"] = frame_time_ms
	sample["fps"] = instantaneous_fps
	sample["gc"] = gc_frame_delta

	worst_stutter_frames.append(sample)
	worst_stutter_frames.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["frame_time_ms"]) > float(b["frame_time_ms"])
	)

	if worst_stutter_frames.size() > 10:
		worst_stutter_frames.resize(10)

	print("\n========== LIVE STUTTER ==========")
	print_stutter_sample(sample)
	print("player chunk: ", current_player_chunk)
	print("loaded chunks: ", loaded_chunks.size())
	print("work queue: ", work_queue.size())
	print("pending generation results: ", pending_generation_results.size())
	print("pending mesh data: ", pending_mesh_data.size())
	print("active jobs: ", active_jobs.size())
	print_streaming_targets_stutter_sample(sample)
	print_gc_stutter_sample(sample)

	for job in active_jobs:
		print(
			"  active job: chunk=%s stage=%s thread_alive=%s"
			% [
				str(job.get("chunk_position")),
				str(job.get("stage")),
				str((job["thread"] as Thread).is_alive())
			]
		)

	print("==================================\n")


func print_streaming_targets_stutter_sample(sample: Dictionary) -> void:
	print(
		"targets update: %.3f ms | unloading %.3f ms | unloaded %d chunks"
		% [
			float(sample.get("targets_update_usec", 0)) / 1000.0,
			float(sample.get("targets_unload_usec", 0)) / 1000.0,
			int(sample.get("targets_unloaded_count", 0)),
		]
	)
	for unload in sample.get("unload_profiles", []):
		var data: Dictionary = unload
		print(
			"  unload %s: total %.3f ms | voxel scan %.3f | queue_free %.3f | cleanup %.3f | block light %.3f | sunlight removal %.3f | sunlight propagation %.3f | cardinal rebuilds %.3f | light rebuild requests %.3f"
			% [
				str(data["chunk_position"]),
				float(data["total_usec"]) / 1000.0,
				float(data["voxel_scan_usec"]) / 1000.0,
				float(data["queue_free_usec"]) / 1000.0,
				float(data["cleanup_usec"]) / 1000.0,
				float(data["block_light_usec"]) / 1000.0,
				float(data["sunlight_removal_usec"]) / 1000.0,
				float(data["sunlight_propagation_usec"]) / 1000.0,
				float(data["cardinal_rebuilds_usec"]) / 1000.0,
				float(data["light_rebuild_requests_usec"]) / 1000.0,
			]
		)
		print(
			"    departed block/sunlight %d/%d | affected block/sunlight chunks %d/%d | rebuild requests block/sunlight %d/%d"
			% [
				int(data["departed_sources"]),
				int(data["departed_sunlight"]),
				int(data["block_light_changed_chunks"]),
				int(data["sunlight_changed_chunks"]),
				int(data["block_light_rebuild_requests"]),
				int(data["sunlight_rebuild_requests"]),
			]
		)


func print_gc_stutter_sample(sample: Dictionary) -> void:
	var gc: Dictionary = sample.get("gc", {})
	if gc.is_empty():
		return
	print(
		"GC: gen0 +%d | gen1 +%d | gen2 +%d | managed %.1f MB (%+.1f MB) | allocated +%.1f MB | totals %d/%d/%d | total allocated %.1f MB"
		% [
			int(gc["gen0"]),
			int(gc["gen1"]),
			int(gc["gen2"]),
			float(gc["managed_memory"]) / 1048576.0,
			float(gc["managed_memory_delta"]) / 1048576.0,
			float(gc["allocated_bytes_delta"]) / 1048576.0,
			int(gc["gen0_total"]),
			int(gc["gen1_total"]),
			int(gc["gen2_total"]),
			float(gc["total_allocated_bytes"]) / 1048576.0,
		]
	)


func print_stutter_sample(sample: Dictionary) -> void:
	print(
		"STUTTER frame %d | %.1f FPS | %.3f ms | streaming tasks %.3f ms (scheduler wall %.3f ms)"
		% [
			int(sample["frame"]),
			float(sample["fps"]),
			float(sample["frame_time_ms"]),
			float(sample["streaming_task_usec"]) / 1000.0,
			float(sample["streaming_wall_usec"]) / 1000.0,
		]
	)
	for task in sample["tasks"]:
		var task_data: Dictionary = task
		print("  - %s: %.3f ms" % [task_data["name"], float(task_data["duration_usec"]) / 1000.0])
		var breakdown: Dictionary = task_data.get("breakdown", {})
		for label in breakdown:
			print("      %s: %.3f ms" % [label, float(breakdown[label]) / 1000.0])
	print(
		"  background: generation=%s mesh=%s active=%d | deferred=%d"
		% [
			str(sample["generation_worker_active"]),
			str(sample["mesh_worker_active"]),
			int(sample["active_jobs"]),
			int(sample["deferred"]),
		]
	)


func print_stutter_top_frames() -> void:
	print("STUTTER TOP %d" % worst_stutter_frames.size())
	for rank in worst_stutter_frames.size():
		var sample: Dictionary = worst_stutter_frames[rank]
		print(
			"  #%d frame %d | %.1f FPS | %.3f ms | streaming %.3f ms | gen=%s mesh=%s jobs=%d deferred=%d | %s"
			% [
				rank + 1,
				int(sample["frame"]),
				float(sample["fps"]),
				float(sample["frame_time_ms"]),
				float(sample["streaming_task_usec"]) / 1000.0,
				str(sample["generation_worker_active"]),
				str(sample["mesh_worker_active"]),
				int(sample["active_jobs"]),
				int(sample["deferred"]),
				format_stutter_task_summary(sample["tasks"]),
			]
		)
		print_stutter_sample(sample)


func format_stutter_task_summary(tasks: Array) -> String:
	var parts: Array[String] = []
	for task in tasks:
		parts.append("%s=%.2fms" % [task["name"], float(task["duration_usec"]) / 1000.0])
	return ", ".join(parts) if not parts.is_empty() else "no streaming tasks"


func count_deferred_streaming_main_tasks() -> int:
	var count := pending_generation_results.size()
	for chunk_position in work_queue:
		if not chunk_stages.has(chunk_position):
			continue
		var stage: int = chunk_stages[chunk_position]
		if stage in [ChunkStage.GENERATE_DATA, ChunkStage.BUILD_MESH_DATA, ChunkStage.APPLY_MESH]:
			count += 1
		elif stage == ChunkStage.BUILD_COLLISION:
			count += maxi(1, (pending_collision_sections.get(chunk_position, []) as Array).size())
	return count


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
				"collision_unit_worker_usec": {},
				"collision_unit_solid_voxels": {},
				"collision_unit_box_counts": {},
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
				"snapshot_blocklight_borders_usec": 0,
				"snapshot_sunlight_borders_usec": 0,
				"sunlight_vertical_worker_usec": 0,
				"sunlight_local_bfs_worker_usec": 0,
				"sunlight_direct_voxels": 0,
				"sunlight_seed_count": 0,
				"sunlight_legacy_seed_count": 0,
				"sunlight_processed_voxels": 0,
				"sunlight_queue_pushes": 0,
				"sunlight_duplicate_rejections": 0,
				"sunlight_neighbor_operations": 0,
				"sunlight_reconcile_usec": 0,
				"sunlight_bfs_usec": 0,
				"sunlight_init_usec": 0,
				"sunlight_changed_neighbor_chunks": 0,
			}
			enqueue_work(chunk_position)

	for chunk_position in chunk_stages:
		if chebyshev_distance(chunk_position, current_player_chunk) > unload_distance:
			enqueue_chunk_unload(chunk_position)
	for index in range(pending_chunk_unloads.size() - 1, -1, -1):
		var pending_position := pending_chunk_unloads[index]
		if chebyshev_distance(pending_position, current_player_chunk) <= unload_distance:
			pending_chunk_unloads.remove_at(index)
			queued_chunk_unloads.erase(pending_position)


func enqueue_chunk_unload(chunk_position: Vector2i) -> void:
	if queued_chunk_unloads.has(chunk_position):
		return
	pending_chunk_unloads.append(chunk_position)
	queued_chunk_unloads[chunk_position] = true


func process_pending_chunk_unloads() -> void:
	var unloading_started_at := Time.get_ticks_usec()
	var processed := 0
	while processed < max_chunk_unloads_per_frame and not pending_chunk_unloads.is_empty():
		var chunk_position: Vector2i = pending_chunk_unloads.pop_front()
		queued_chunk_unloads.erase(chunk_position)
		if not chunk_stages.has(chunk_position):
			continue
		if chebyshev_distance(chunk_position, current_player_chunk) <= unload_distance:
			continue
		var unload_profile := unload_chunk(chunk_position)
		streaming_targets_unload_profiles.append(unload_profile)
		if bool(unload_profile["had_loaded_chunk"]):
			streaming_targets_unloaded_count += 1
		processed += 1
	streaming_targets_unload_usec = Time.get_ticks_usec() - unloading_started_at


func enqueue_work(chunk_position: Vector2i) -> void:
	if queued_work.has(chunk_position):
		return
	work_queue.append(chunk_position)
	queued_work[chunk_position] = true


func start_background_jobs() -> void:
	var started := 0

	while (active_jobs.size() < MAX_BACKGROUND_STREAMING_JOBS and started < streaming_steps_per_frame):
		if streaming_budget_reached():
			return

		# Finish a generated chunk's mesh before starting another generation job.
		var chunk_position := pop_work_for_stages([ChunkStage.BUILD_MESH_DATA])

		if chunk_position == INVALID_CHUNK_POSITION:
			chunk_position = pop_work_for_stages([ChunkStage.GENERATE_DATA])

		if chunk_position == INVALID_CHUNK_POSITION:
			return

		var stage: int = chunk_stages[chunk_position]
		var version: int = chunk_versions[chunk_position]
		var worker: RefCounted
		var callable: Callable

		if stage == ChunkStage.GENERATE_DATA:
			var dispatch_started_at := Time.get_ticks_usec()
			var parameters := create_generation_parameters(chunk_position)

			chunk_timings[chunk_position]["generation_dispatch_usec"] = (
				Time.get_ticks_usec() - dispatch_started_at
			)

			if USE_CSHARP_CHUNK_GENERATOR:
				worker = ChunkGeneratorCs.new()
				callable = Callable(worker, "GenerateData").bind(parameters)
			else:
				worker = ChunkGenerator.new()
				callable = Callable(worker, "generate_data").bind(parameters)

			chunk_stages[chunk_position] = ChunkStage.GENERATING

			record_streaming_main_task(
				"generation_dispatch(%d,%d)" % [chunk_position.x, chunk_position.y],
				dispatch_started_at
			)

		else:
			var snapshot_started_at := Time.get_ticks_usec()
			var snapshot := create_meshing_snapshot(chunk_position)

			chunk_timings[chunk_position]["snapshot_usec"] = (
				Time.get_ticks_usec() - snapshot_started_at
			)

			if USE_CSHARP_CHUNK_MESHER:
				worker = ChunkMesherCs.new()
				callable = Callable(worker, "BuildMeshData").bind(snapshot)
			else:
				worker = ChunkMesher.new()
				callable = Callable(worker, "build_mesh_data").bind(snapshot)

			chunk_stages[chunk_position] = ChunkStage.MESHING

			record_streaming_main_task(
				"snapshot(%d,%d)" % [chunk_position.x, chunk_position.y],
				snapshot_started_at,
				get_snapshot_task_breakdown(chunk_position)
			)

		var thread := Thread.new()
		var error := thread.start(callable, Thread.PRIORITY_LOW)

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
		if streaming_budget_reached():
			return
		var collect_started_at := Time.get_ticks_usec()
		var result: Dictionary = thread.wait_to_finish()
		active_jobs.remove_at(index)
		var chunk_position: Vector2i = job["chunk_position"]
		var version: int = job["version"]
		record_streaming_main_task(
			"collect_worker_result(%d,%d)" % [chunk_position.x, chunk_position.y],
			collect_started_at
		)
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
	if streaming_budget_reached():
		return
	var process_started_at := Time.get_ticks_usec()
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
		record_streaming_main_task(
			"apply_generated_data(%d,%d)" % [chunk_position.x, chunk_position.y],
			process_started_at,
			get_apply_generated_task_breakdown(chunk_position)
		)
		return


func process_main_thread_queue(gameplay_only: bool) -> void:
	var steps := 0
	while steps < streaming_steps_per_frame:
		if streaming_budget_reached():
			return
		var chunk_position := pop_work_for_stages(
			[ChunkStage.APPLY_MESH, ChunkStage.BUILD_COLLISION], gameplay_only
		)
		if chunk_position == INVALID_CHUNK_POSITION:
			return
		var task_started_at := Time.get_ticks_usec()
		if chunk_stages[chunk_position] == ChunkStage.APPLY_MESH:
			apply_chunk_mesh(chunk_position)
			record_streaming_main_task(
				"apply_mesh(%d,%d)" % [chunk_position.x, chunk_position.y],
				task_started_at
			)
		else:
			var sections: Array = pending_collision_sections.get(chunk_position, [])
			var section := int(sections[0]) if not sections.is_empty() else -1
			var region := ChunkMesher.get_collision_region_coords(section)
			build_chunk_collision(chunk_position)
			record_streaming_main_task(
				"collision(%d,%d)[region %d,%d,%d]"
				% [chunk_position.x, chunk_position.y, region.x, region.y, region.z],
				task_started_at,
				{"greedy collision apply": Time.get_ticks_usec() - task_started_at}
			)
		steps += 1


func pop_work_for_stages(stages: Array, gameplay_only: bool = false) -> Vector2i:
	sort_work_queue()
	for index in work_queue.size():
		var chunk_position := work_queue[index]
		if not chunk_stages.has(chunk_position):
			queued_work.erase(chunk_position)
			work_queue.remove_at(index)
			return pop_work_for_stages(stages, gameplay_only)
		if (
			stages.has(chunk_stages[chunk_position])
			and (not gameplay_only or gameplay_rebuilds.has(chunk_position))
		):
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
	chunk_timings[chunk_position]["sunlight_vertical_worker_usec"] = int(result.get("sunlight_vertical_worker_usec", 0))
	chunk_timings[chunk_position]["sunlight_local_bfs_worker_usec"] = int(result.get("sunlight_local_bfs_worker_usec", 0))
	for profile_key in [
		"sunlight_direct_voxels",
		"sunlight_seed_count",
		"sunlight_legacy_seed_count",
		"sunlight_processed_voxels",
		"sunlight_queue_pushes",
		"sunlight_duplicate_rejections",
		"sunlight_neighbor_operations",
	]:
		chunk_timings[chunk_position][profile_key] = int(result.get(profile_key, 0))
	var sun_changed_chunks := initialize_chunk_sunlight(chunk)
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
	var sun_neighbor_remesh_requests := 0
	for changed_position in sun_changed_chunks:
		if changed_position != chunk_position:
			request_chunk_rebuild(changed_position)
			sun_neighbor_remesh_requests += 1
	var block_neighbor_remesh_requests := 0
	for changed_position in light_changed_chunks:
		if changed_position != chunk_position:
			request_chunk_rebuild(changed_position)
			block_neighbor_remesh_requests += 1
	chunk_timings[chunk_position]["blocklight_changed_neighbor_chunks"] = block_neighbor_remesh_requests
	chunk_timings[chunk_position]["blocklight_neighbor_remesh_requests"] = block_neighbor_remesh_requests
	chunk_timings[chunk_position]["sunlight_changed_neighbor_chunks"] = sun_neighbor_remesh_requests


func create_meshing_snapshot(chunk_position: Vector2i) -> Dictionary:
	var chunk := loaded_chunks.get(chunk_position) as Chunk
	var data_copy_started_at := Time.get_ticks_usec()
	var data_snapshot := chunk.data.duplicate_data()
	var data_copy_elapsed := Time.get_ticks_usec() - data_copy_started_at
	var block_allocation_started_at := Time.get_ticks_usec()
	var negative_x := create_empty_boundary()
	var positive_x := create_empty_boundary()
	var negative_z := create_empty_boundary()
	var positive_z := create_empty_boundary()
	var block_allocation_elapsed := Time.get_ticks_usec() - block_allocation_started_at
	var blocklight_allocation_started_at := Time.get_ticks_usec()
	var negative_x_light := create_empty_light_boundary()
	var positive_x_light := create_empty_light_boundary()
	var negative_z_light := create_empty_light_boundary()
	var positive_z_light := create_empty_light_boundary()
	var blocklight_allocation_elapsed := Time.get_ticks_usec() - blocklight_allocation_started_at
	var sunlight_allocation_started_at := Time.get_ticks_usec()
	var negative_x_sun := create_empty_light_boundary()
	var positive_x_sun := create_empty_light_boundary()
	var negative_z_sun := create_empty_light_boundary()
	var positive_z_sun := create_empty_light_boundary()
	var sunlight_allocation_elapsed := Time.get_ticks_usec() - sunlight_allocation_started_at
	var combined_copy_started_at := Time.get_ticks_usec()
	copy_neighbor_x_snapshot_boundary(
		negative_x, negative_x_light, negative_x_sun,
		chunk_position + Vector2i.LEFT, ChunkData.SIZE_XZ - 1
	)
	copy_neighbor_x_snapshot_boundary(
		positive_x, positive_x_light, positive_x_sun,
		chunk_position + Vector2i.RIGHT, 0
	)
	copy_neighbor_z_snapshot_boundary(
		negative_z, negative_z_light, negative_z_sun,
		chunk_position + Vector2i.UP, ChunkData.SIZE_XZ - 1
	)
	copy_neighbor_z_snapshot_boundary(
		positive_z, positive_z_light, positive_z_sun,
		chunk_position + Vector2i.DOWN, 0
	)
	var combined_copy_elapsed := Time.get_ticks_usec() - combined_copy_started_at
	# The combined loop performs one fixed-cost assignment for each channel. Keep
	# the existing per-channel breakdown as an equal attribution of copy time.
	var copy_share := combined_copy_elapsed / 3
	var block_borders_elapsed := block_allocation_elapsed + copy_share
	var blocklight_borders_elapsed := blocklight_allocation_elapsed + copy_share
	var sunlight_borders_elapsed := sunlight_allocation_elapsed + combined_copy_elapsed - copy_share * 2
	var light_borders_elapsed := blocklight_borders_elapsed + sunlight_borders_elapsed
	if chunk_timings.has(chunk_position):
		chunk_timings[chunk_position]["snapshot_data_copy_usec"] = data_copy_elapsed
		chunk_timings[chunk_position]["snapshot_block_borders_usec"] = block_borders_elapsed
		chunk_timings[chunk_position]["snapshot_light_borders_usec"] = light_borders_elapsed
		chunk_timings[chunk_position]["snapshot_blocklight_borders_usec"] = blocklight_borders_elapsed
		chunk_timings[chunk_position]["snapshot_sunlight_borders_usec"] = sunlight_borders_elapsed
		chunk_timings[chunk_position]["snapshot_frame"] = Engine.get_process_frames()
	return {
		"data": data_snapshot,
		"blocks_flat": data_snapshot.get_blocks_flat_copy(),
		"block_light_flat": data_snapshot.block_light.duplicate(),
		"sun_light_flat": data_snapshot.sun_light.duplicate(),
		"negative_x": negative_x,
		"positive_x": positive_x,
		"negative_z": negative_z,
		"positive_z": positive_z,
		"negative_x_light": negative_x_light,
		"positive_x_light": positive_x_light,
		"negative_z_light": negative_z_light,
		"positive_z_light": positive_z_light,
		"negative_x_sun": negative_x_sun,
		"positive_x_sun": positive_x_sun,
		"negative_z_sun": negative_z_sun,
		"positive_z_sun": positive_z_sun,
		"collision_unit_indices": get_snapshot_collision_unit_indices(chunk_position),
	}


func get_snapshot_task_breakdown(chunk_position: Vector2i) -> Dictionary:
	var timing: Dictionary = chunk_timings.get(chunk_position, {})
	return {
		"duplicate ChunkData": int(timing.get("snapshot_data_copy_usec", 0)),
		"block borders": int(timing.get("snapshot_block_borders_usec", 0)),
		"BlockLight borders": int(timing.get("snapshot_blocklight_borders_usec", 0)),
		"SunLight borders": int(timing.get("snapshot_sunlight_borders_usec", 0)),
	}


func get_apply_generated_task_breakdown(chunk_position: Vector2i) -> Dictionary:
	var timing: Dictionary = chunk_timings.get(chunk_position, {})
	return {
		"apply ChunkData/setup": int(timing.get("apply_data_main_usec", 0)),
		"SpecialBlocks sync": int(timing.get("special_blocks_main_usec", 0)),
		"SunLight reconcile": int(timing.get("sunlight_reconcile_usec", 0)),
		"SunLight propagation": int(timing.get("sunlight_bfs_usec", 0)),
		"BlockLight clear": int(timing.get("blocklight_clear_usec", 0)),
		"BlockLight source scan": int(timing.get("blocklight_source_scan_usec", 0)),
		"BlockLight reconcile": int(timing.get("blocklight_border_reconcile_usec", 0)),
		"BlockLight propagation": int(timing.get("blocklight_bfs_usec", 0)),
	}


func get_snapshot_collision_unit_indices(chunk_position: Vector2i) -> Array[int]:
	if initial_chunks.has(chunk_position):
		var all_units: Array[int] = []
		for unit_index in Chunk.COLLISION_REGION_COUNT:
			all_units.append(unit_index)
		return all_units
	if not gameplay_rebuilds.has(chunk_position):
		return []
	var requested: Dictionary = {}
	var deadlines: Dictionary = gameplay_collision_deadlines.get(chunk_position, {})
	for unit_index in deadlines:
		requested[int(unit_index)] = true
	for unit_index in pending_collision_sections.get(chunk_position, []):
		requested[int(unit_index)] = true
	var units: Array[int] = []
	for unit_index in requested:
		units.append(unit_index)
	units.sort()
	return units


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


func copy_neighbor_x_snapshot_boundary(
	block_target: PackedInt32Array,
	blocklight_target: PackedByteArray,
	sunlight_target: PackedByteArray,
	neighbor_position: Vector2i,
	source_x: int
) -> void:
	var neighbor := loaded_chunks.get(neighbor_position) as Chunk
	if neighbor == null:
		return
	var neighbor_data := neighbor.data
	var source_blocks: Array = neighbor_data.blocks[source_x]
	var block_light: PackedByteArray = neighbor_data.block_light
	var sun_light: PackedByteArray = neighbor_data.sun_light
	for y in ChunkData.HEIGHT:
		var target_row := y * ChunkData.SIZE_XZ
		var source_row := target_row * ChunkData.SIZE_XZ + source_x
		var source_y: Array = source_blocks[y]
		for z in ChunkData.SIZE_XZ:
			var target_index := target_row + z
			var source_index := source_row + z * ChunkData.SIZE_XZ
			block_target[target_index] = source_y[z]
			blocklight_target[target_index] = block_light[source_index]
			sunlight_target[target_index] = sun_light[source_index]


func copy_neighbor_z_snapshot_boundary(
	block_target: PackedInt32Array,
	blocklight_target: PackedByteArray,
	sunlight_target: PackedByteArray,
	neighbor_position: Vector2i,
	source_z: int
) -> void:
	var neighbor := loaded_chunks.get(neighbor_position) as Chunk
	if neighbor == null:
		return
	var neighbor_data := neighbor.data
	var blocks: Array = neighbor_data.blocks
	var block_light: PackedByteArray = neighbor_data.block_light
	var sun_light: PackedByteArray = neighbor_data.sun_light
	for y in ChunkData.HEIGHT:
		var target_row := y * ChunkData.SIZE_XZ
		var source_row := (y * ChunkData.SIZE_XZ + source_z) * ChunkData.SIZE_XZ
		for x in ChunkData.SIZE_XZ:
			var target_index := target_row + x
			var source_index := source_row + x
			block_target[target_index] = blocks[x][y][source_z]
			blocklight_target[target_index] = block_light[source_index]
			sunlight_target[target_index] = sun_light[source_index]


func apply_chunk_mesh(chunk_position: Vector2i) -> void:
	var chunk := loaded_chunks.get(chunk_position) as Chunk
	if chunk == null or not pending_mesh_data.has(chunk_position):
		return
	var started_at := Time.get_ticks_usec()
	var mesh_data: Dictionary = pending_mesh_data[chunk_position]
	chunk.apply_mesh_data(mesh_data)
	var collision_worker_timings: Dictionary = {}
	var collision_solid_counts: Dictionary = {}
	var collision_box_counts: Dictionary = {}
	var collision_units: Array = mesh_data.get("collision_units", [])
	for unit in collision_units:
		var unit_data: Dictionary = unit
		var unit_index := int(unit_data["unit_index"])
		collision_worker_timings[unit_index] = int(unit_data.get("worker_usec", 0))
		collision_solid_counts[unit_index] = int(unit_data.get("solid_voxels", 0))
		collision_box_counts[unit_index] = (unit_data.get("centers", PackedVector3Array()) as PackedVector3Array).size()
	chunk_timings[chunk_position]["collision_unit_worker_usec"] = collision_worker_timings
	chunk_timings[chunk_position]["collision_unit_solid_voxels"] = collision_solid_counts
	chunk_timings[chunk_position]["collision_unit_box_counts"] = collision_box_counts
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
		# Neighbor/light-only remeshes do not change voxel ownership, so greedy
		# terrain boxes remain valid and no physics work is needed.
		chunk_stages[chunk_position] = ChunkStage.READY


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
	for section in Chunk.COLLISION_REGION_COUNT:
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
	var unit_data := chunk.get_collision_unit_data(section)
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
		var region := ChunkMesher.get_collision_region_coords(section)
		print(
			"Collision (%d,%d) unit %d: %d solid -> %d boxes | worker %.3f ms | apply %.3f ms"
			% [
				chunk_position.x,
				chunk_position.y,
				region.y,
				int(unit_data.get("solid_voxels", 0)),
				(unit_data.get("centers", PackedVector3Array()) as PackedVector3Array).size(),
				float(unit_data.get("worker_usec", 0)) / 1000.0,
				float(elapsed) / 1000.0,
			]
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
	var collision_worker_timings: Dictionary = timing.get("collision_unit_worker_usec", {})
	var collision_solid_counts: Dictionary = timing.get("collision_unit_solid_voxels", {})
	var collision_box_counts: Dictionary = timing.get("collision_unit_box_counts", {})
	var main_total_usec := (
		int(timing.get("generation_dispatch_usec", 0))
		+ int(timing.get("apply_data_main_usec", 0))
		+ int(timing.get("special_blocks_main_usec", 0))
		+ int(timing.get("blocklight_init_usec", 0))
		+ int(timing.get("sunlight_init_usec", 0))
		+ int(timing.get("snapshot_usec", 0))
		+ int(timing.get("apply_mesh_usec", 0))
		+ int(timing.get("collision_usec", 0))
	)
	var lines: Array[String] = [
		"Chunk (%d,%d) load profile:" % [chunk_position.x, chunk_position.y],
		"  MAIN apply data/setup: %.3f ms (frame %d)" % [float(timing.get("apply_data_main_usec", 0)) / 1000.0, int(timing.get("apply_data_frame", -1))],
		"  MAIN special blocks: %.3f ms (%d created)" % [float(timing.get("special_blocks_main_usec", 0)) / 1000.0, int(timing.get("special_blocks_created", 0))],
		"  BACKGROUND SunLight vertical: %.3f ms" % [float(timing.get("sunlight_vertical_worker_usec", 0)) / 1000.0],
		"  BACKGROUND SunLight local BFS: %.3f ms" % [float(timing.get("sunlight_local_bfs_worker_usec", 0)) / 1000.0],
		"    direct/legacy seeds/new seeds/processed: %d / %d / %d / %d" % [int(timing.get("sunlight_direct_voxels", 0)), int(timing.get("sunlight_legacy_seed_count", 0)), int(timing.get("sunlight_seed_count", 0)), int(timing.get("sunlight_processed_voxels", 0))],
		"    queue pushes/rejected/neighbor ops: %d / %d / %d" % [int(timing.get("sunlight_queue_pushes", 0)), int(timing.get("sunlight_duplicate_rejections", 0)), int(timing.get("sunlight_neighbor_operations", 0))],
		"  MAIN SunLight border reconcile: %.3f ms" % [float(timing.get("sunlight_reconcile_usec", 0)) / 1000.0],
		"  MAIN SunLight BFS: %.3f ms" % [float(timing.get("sunlight_bfs_usec", 0)) / 1000.0],
		"  MAIN SunLight total: %.3f ms / %d neighbor chunks" % [float(timing.get("sunlight_init_usec", 0)) / 1000.0, int(timing.get("sunlight_changed_neighbor_chunks", 0))],
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
	for section in range(Chunk.COLLISION_REGION_COUNT):
		var region := ChunkMesher.get_collision_region_coords(section)
		lines.append(
			"  collision unit Y%d: %d solid -> %d boxes | worker %.3f ms | MAIN apply %.3f ms (frame %d)"
			% [
				region.y,
				int(collision_solid_counts.get(section, 0)),
				int(collision_box_counts.get(section, 0)),
				float(collision_worker_timings.get(section, 0)) / 1000.0,
				float(collision_sections.get(section, 0)) / 1000.0,
				int(collision_frames.get(section, -1)),
			]
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
			Chunk.COLLISION_REGION_COUNT,
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


func unload_chunk(chunk_position: Vector2i) -> Dictionary:
	var total_started_at := Time.get_ticks_usec()
	var chunk := loaded_chunks.get(chunk_position) as Chunk
	var had_loaded_chunk := chunk != null
	var departed_sources: Array[Dictionary] = []
	var departed_sunlight: Array[Dictionary] = []
	var voxel_scan_started_at := Time.get_ticks_usec()
	if chunk != null:
		for block_index in chunk.data.emissive_block_indices:
			var local_position := chunk.data.get_position_from_index(block_index)
			var emission := BlockRegistry.get_light_emission(chunk.data.get_block(local_position))
			if emission > 0:
				departed_sources.append({"position": chunk.local_to_world(local_position), "level": emission})
		departed_sunlight = collect_departed_sunlight_boundaries(chunk)
	var voxel_scan_usec := Time.get_ticks_usec() - voxel_scan_started_at
	var queue_free_started_at := Time.get_ticks_usec()
	if chunk != null:
		# Future persistence hook: save modified block overrides before removing this chunk.
		chunk.queue_free()
	var queue_free_usec := Time.get_ticks_usec() - queue_free_started_at
	var cleanup_started_at := Time.get_ticks_usec()
	loaded_chunks.erase(chunk_position)
	for index in range(pending_generation_results.size() - 1, -1, -1):
		if pending_generation_results[index]["chunk_position"] == chunk_position:
			pending_generation_results.remove_at(index)
	var cleanup_usec := Time.get_ticks_usec() - cleanup_started_at
	var block_light_started_at := Time.get_ticks_usec()
	var light_changed_chunks := remove_departed_light_sources(departed_sources)
	var block_light_usec := Time.get_ticks_usec() - block_light_started_at
	var sun_changed_chunks: Dictionary = {}
	var sun_propagation_queue: Array[Vector3i] = []
	var sunlight_removal_started_at := Time.get_ticks_usec()
	process_sunlight_removal(departed_sunlight, sun_propagation_queue, sun_changed_chunks)
	var sunlight_removal_usec := Time.get_ticks_usec() - sunlight_removal_started_at
	var sunlight_propagation_started_at := Time.get_ticks_usec()
	propagate_sunlight(sun_propagation_queue, sun_changed_chunks)
	var sunlight_propagation_usec := Time.get_ticks_usec() - sunlight_propagation_started_at
	cleanup_started_at = Time.get_ticks_usec()
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
	cleanup_usec += Time.get_ticks_usec() - cleanup_started_at
	var cardinal_rebuilds_started_at := Time.get_ticks_usec()
	request_cardinal_neighbor_rebuilds(chunk_position)
	var cardinal_rebuilds_usec := Time.get_ticks_usec() - cardinal_rebuilds_started_at
	var light_rebuild_requests_started_at := Time.get_ticks_usec()
	var block_light_rebuild_requests := 0
	for changed_position in light_changed_chunks:
		request_chunk_rebuild(changed_position)
		block_light_rebuild_requests += 1
	var sunlight_rebuild_requests := 0
	for changed_position in sun_changed_chunks:
		request_chunk_rebuild(changed_position)
		sunlight_rebuild_requests += 1
	var light_rebuild_requests_usec := Time.get_ticks_usec() - light_rebuild_requests_started_at
	return {
		"chunk_position": chunk_position,
		"total_usec": Time.get_ticks_usec() - total_started_at,
		"voxel_scan_usec": voxel_scan_usec,
		"queue_free_usec": queue_free_usec,
		"cleanup_usec": cleanup_usec,
		"block_light_usec": block_light_usec,
		"sunlight_removal_usec": sunlight_removal_usec,
		"sunlight_propagation_usec": sunlight_propagation_usec,
		"cardinal_rebuilds_usec": cardinal_rebuilds_usec,
		"light_rebuild_requests_usec": light_rebuild_requests_usec,
		"departed_sources": departed_sources.size(),
		"departed_sunlight": departed_sunlight.size(),
		"block_light_changed_chunks": light_changed_chunks.size(),
		"sunlight_changed_chunks": sun_changed_chunks.size(),
		"block_light_rebuild_requests": block_light_rebuild_requests,
		"sunlight_rebuild_requests": sunlight_rebuild_requests,
		"had_loaded_chunk": had_loaded_chunk,
	}


func collect_departed_sunlight_boundaries(chunk: Chunk) -> Array[Dictionary]:
	var departed_by_position: Dictionary = {}
	collect_departed_sunlight_x_face(
		chunk, chunk.chunk_position + Vector2i.LEFT, 0, Chunk.SIZE_XZ - 1, departed_by_position
	)
	collect_departed_sunlight_x_face(
		chunk, chunk.chunk_position + Vector2i.RIGHT, Chunk.SIZE_XZ - 1, 0, departed_by_position
	)
	collect_departed_sunlight_z_face(
		chunk, chunk.chunk_position + Vector2i.UP, 0, Chunk.SIZE_XZ - 1, departed_by_position
	)
	collect_departed_sunlight_z_face(
		chunk, chunk.chunk_position + Vector2i.DOWN, Chunk.SIZE_XZ - 1, 0, departed_by_position
	)
	var departed: Array[Dictionary] = []
	for entry in departed_by_position.values():
		departed.append(entry)
	return departed


func collect_departed_sunlight_x_face(
	chunk: Chunk,
	neighbor_position: Vector2i,
	local_x: int,
	neighbor_x: int,
	departed_by_position: Dictionary
) -> void:
	var neighbor := loaded_chunks.get(neighbor_position) as Chunk
	if neighbor == null:
		return
	for y in Chunk.HEIGHT:
		for z in Chunk.SIZE_XZ:
			append_departed_sunlight_if_required(
				chunk,
				Vector3i(local_x, y, z),
				neighbor,
				Vector3i(neighbor_x, y, z),
				departed_by_position
			)


func collect_departed_sunlight_z_face(
	chunk: Chunk,
	neighbor_position: Vector2i,
	local_z: int,
	neighbor_z: int,
	departed_by_position: Dictionary
) -> void:
	var neighbor := loaded_chunks.get(neighbor_position) as Chunk
	if neighbor == null:
		return
	for y in Chunk.HEIGHT:
		for x in Chunk.SIZE_XZ:
			append_departed_sunlight_if_required(
				chunk,
				Vector3i(x, y, local_z),
				neighbor,
				Vector3i(x, y, neighbor_z),
				departed_by_position
			)


func append_departed_sunlight_if_required(
	chunk: Chunk,
	local_position: Vector3i,
	neighbor: Chunk,
	neighbor_local: Vector3i,
	departed_by_position: Dictionary
) -> void:
	var departed_level := chunk.data.get_sun_light(local_position)
	if departed_level <= 0:
		return
	var neighbor_level := neighbor.data.get_sun_light(neighbor_local)
	var neighbor_source_level := 15 if neighbor.data.is_direct_sunlight(neighbor_local) else 0
	if neighbor_level >= departed_level or neighbor_level <= neighbor_source_level:
		return
	var world_position := chunk.local_to_world(local_position)
	departed_by_position[world_position] = {
		"position": world_position,
		"level": departed_level,
	}


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


func try_get_block_at_world_position(position: Vector3i) -> Dictionary:
	if position.y < 0 or position.y >= Chunk.HEIGHT:
		return {"known": true, "block": BlockRegistry.Block.AIR}
	var chunk := get_chunk_at_world_position(position)
	if chunk == null:
		return {"known": false, "block": BlockRegistry.Block.AIR}
	return {"known": true, "block": chunk.get_block_local(chunk.world_to_local(position))}


func get_block_light_at_world_position(position: Vector3i) -> int:
	var chunk := get_chunk_at_world_position(position)
	if chunk == null:
		return 0
	return chunk.data.get_block_light(chunk.world_to_local(position))


func get_sun_light_at_world_position(position: Vector3i) -> int:
	if position.y >= Chunk.HEIGHT:
		return 15
	var chunk := get_chunk_at_world_position(position)
	if chunk == null:
		return 0
	return chunk.data.get_sun_light(chunk.world_to_local(position))


func initialize_chunk_sunlight(chunk: Chunk) -> Dictionary:
	var started_at := Time.get_ticks_usec()
	var changed_chunks: Dictionary = {}
	var propagation_queue: Array[Vector3i] = []
	var reconcile_started_at := Time.get_ticks_usec()
	seed_sunlight_across_borders(chunk, propagation_queue)
	var reconcile_elapsed := Time.get_ticks_usec() - reconcile_started_at
	var bfs_started_at := Time.get_ticks_usec()
	propagate_sunlight(propagation_queue, changed_chunks)
	var bfs_elapsed := Time.get_ticks_usec() - bfs_started_at
	if chunk_timings.has(chunk.chunk_position):
		chunk_timings[chunk.chunk_position]["sunlight_reconcile_usec"] = reconcile_elapsed
		chunk_timings[chunk.chunk_position]["sunlight_bfs_usec"] = bfs_elapsed
		chunk_timings[chunk.chunk_position]["sunlight_init_usec"] = Time.get_ticks_usec() - started_at
	return changed_chunks


func seed_sunlight_across_borders(chunk: Chunk, propagation_queue: Array[Vector3i]) -> void:
	seed_sunlight_x_pair(chunk, chunk.chunk_position + Vector2i.LEFT, 0, Chunk.SIZE_XZ - 1, propagation_queue)
	seed_sunlight_x_pair(chunk, chunk.chunk_position + Vector2i.RIGHT, Chunk.SIZE_XZ - 1, 0, propagation_queue)
	seed_sunlight_z_pair(chunk, chunk.chunk_position + Vector2i.UP, 0, Chunk.SIZE_XZ - 1, propagation_queue)
	seed_sunlight_z_pair(chunk, chunk.chunk_position + Vector2i.DOWN, Chunk.SIZE_XZ - 1, 0, propagation_queue)


func seed_sunlight_x_pair(chunk: Chunk, neighbor_position: Vector2i, local_x: int, neighbor_x: int, queue: Array[Vector3i]) -> void:
	var neighbor := loaded_chunks.get(neighbor_position) as Chunk
	if neighbor == null:
		return
	var chunk_origin := Vector3i(chunk.chunk_position.x * Chunk.SIZE_XZ, 0, chunk.chunk_position.y * Chunk.SIZE_XZ)
	var neighbor_origin := Vector3i(neighbor_position.x * Chunk.SIZE_XZ, 0, neighbor_position.y * Chunk.SIZE_XZ)
	for y in Chunk.HEIGHT:
		for z in Chunk.SIZE_XZ:
			var local := Vector3i(local_x, y, z)
			var neighbor_local := Vector3i(neighbor_x, y, z)
			var local_level := chunk.data.get_sun_light(local)
			var neighbor_level := neighbor.data.get_sun_light(neighbor_local)
			if local_level - 1 > neighbor_level and BlockRegistry.is_light_transparent(neighbor.data.get_block(neighbor_local)):
				queue.append(chunk_origin + local)
			if neighbor_level - 1 > local_level and BlockRegistry.is_light_transparent(chunk.data.get_block(local)):
				queue.append(neighbor_origin + neighbor_local)


func seed_sunlight_z_pair(chunk: Chunk, neighbor_position: Vector2i, local_z: int, neighbor_z: int, queue: Array[Vector3i]) -> void:
	var neighbor := loaded_chunks.get(neighbor_position) as Chunk
	if neighbor == null:
		return
	var chunk_origin := Vector3i(chunk.chunk_position.x * Chunk.SIZE_XZ, 0, chunk.chunk_position.y * Chunk.SIZE_XZ)
	var neighbor_origin := Vector3i(neighbor_position.x * Chunk.SIZE_XZ, 0, neighbor_position.y * Chunk.SIZE_XZ)
	for y in Chunk.HEIGHT:
		for x in Chunk.SIZE_XZ:
			var local := Vector3i(x, y, local_z)
			var neighbor_local := Vector3i(x, y, neighbor_z)
			var local_level := chunk.data.get_sun_light(local)
			var neighbor_level := neighbor.data.get_sun_light(neighbor_local)
			if local_level - 1 > neighbor_level and BlockRegistry.is_light_transparent(neighbor.data.get_block(neighbor_local)):
				queue.append(chunk_origin + local)
			if neighbor_level - 1 > local_level and BlockRegistry.is_light_transparent(chunk.data.get_block(local)):
				queue.append(neighbor_origin + neighbor_local)


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


func propagate_sunlight(propagation_queue: Array[Vector3i], changed_chunks: Dictionary) -> void:
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
		var level := source_chunk.data.get_sun_light(source_local)
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
			if not BlockRegistry.is_light_transparent(neighbor_chunk.data.get_block(neighbor_local)):
				continue
			var desired_level := level - 1
			if desired_level <= neighbor_chunk.data.get_sun_light(neighbor_local):
				continue
			neighbor_chunk.data.set_sun_light(neighbor_local, desired_level)
			changed_chunks[neighbor_chunk.chunk_position] = true
			queue_chunks.append(neighbor_chunk)
			queue_indices.append(neighbor_chunk.data.get_index(neighbor_local))


func update_sunlight_after_change(world_position: Vector3i) -> Dictionary:
	var started_at := Time.get_ticks_usec()
	var changed_chunks: Dictionary = {}
	var removal_queue: Array[Dictionary] = []
	var propagation_queue: Array[Vector3i] = []
	var chunk := get_chunk_at_world_position(world_position)
	if chunk == null:
		return changed_chunks
	var local_changed := chunk.world_to_local(world_position)
	var chunk_origin := Vector3i(chunk.chunk_position.x * Chunk.SIZE_XZ, 0, chunk.chunk_position.y * Chunk.SIZE_XZ)
	var sky_open := true
	for y in range(Chunk.HEIGHT - 1, -1, -1):
		var local := Vector3i(local_changed.x, y, local_changed.z)
		var block := chunk.data.get_block(local)
		var should_be_direct := sky_open and BlockRegistry.is_light_transparent(block)
		var was_direct := chunk.data.is_direct_sunlight(local)
		var old_level := chunk.data.get_sun_light(local)
		chunk.data.set_direct_sunlight(local, should_be_direct)
		if should_be_direct:
			if old_level < 15:
				chunk.data.set_sun_light(local, 15)
				changed_chunks[chunk.chunk_position] = true
				propagation_queue.append(chunk_origin + local)
		else:
			if was_direct or (local == local_changed and old_level > 0 and not BlockRegistry.is_light_transparent(block)):
				chunk.data.set_sun_light(local, 0)
				changed_chunks[chunk.chunk_position] = true
				removal_queue.append({"position": chunk_origin + local, "level": old_level})
			sky_open = false
	var removal_started_at := Time.get_ticks_usec()
	process_sunlight_removal(removal_queue, propagation_queue, changed_chunks)
	sunlight_last_removal_usec = Time.get_ticks_usec() - removal_started_at
	var propagation_started_at := Time.get_ticks_usec()
	propagate_sunlight(propagation_queue, changed_chunks)
	sunlight_last_propagation_usec = Time.get_ticks_usec() - propagation_started_at
	sunlight_update_count += 1
	sunlight_last_update_usec = Time.get_ticks_usec() - started_at
	sunlight_last_changed_chunks = changed_chunks.size()
	return changed_chunks


func process_sunlight_removal(removal_queue: Array[Dictionary], propagation_queue: Array[Vector3i], changed_chunks: Dictionary) -> void:
	var index := 0
	while index < removal_queue.size():
		var entry: Dictionary = removal_queue[index]
		index += 1
		var position: Vector3i = entry["position"]
		var removed_level: int = entry["level"]
		for direction in TREE_LOG_DIRECTIONS:
			var neighbor_position := position + direction
			var neighbor_chunk := get_chunk_at_world_position(neighbor_position)
			if neighbor_chunk == null:
				continue
			var neighbor_local := neighbor_chunk.world_to_local(neighbor_position)
			var neighbor_level := neighbor_chunk.data.get_sun_light(neighbor_local)
			if neighbor_level <= 0:
				continue
			var source_level := 15 if neighbor_chunk.data.is_direct_sunlight(neighbor_local) else 0
			if neighbor_level < removed_level and neighbor_level > source_level:
				neighbor_chunk.data.set_sun_light(neighbor_local, source_level)
				changed_chunks[neighbor_chunk.chunk_position] = true
				removal_queue.append({"position": neighbor_position, "level": neighbor_level})
				if source_level > 0:
					propagation_queue.append(neighbor_position)
			else:
				propagation_queue.append(neighbor_position)


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

	var modified_chunks: Dictionary = {}
	var removed_positions: Array[Vector3i] = []
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
		removed_positions.append(position)
		queue_leaf_checks_around(position)
		var dropped_item := ItemRegistry.get_drop(broken_block)
		if dropped_item != ItemRegistry.Item.NONE:
			var drop_offset := Vector3(randf_range(-0.18, 0.18), 0.5, randf_range(-0.18, 0.18))
			spawn_item(dropped_item, Vector3(position) + Vector3(0.5, 0.0, 0.5) + drop_offset)

	apply_removed_blocks_batch(removed_positions)

	if log_tree_felling:
		print("Tree felled: %d logs across %d chunks" % [logs.size(), modified_chunks.size()])
	return true


func add_tree_rebuild_target(
	targets: Dictionary, chunk_position: Vector2i, local_position: Vector3i
) -> void:
	if not loaded_chunks.has(chunk_position):
		return
	var sections: Dictionary = targets.get(chunk_position, {})
	for section in get_affected_collision_regions(local_position):
		sections[section] = true
	targets[chunk_position] = sections


func add_tree_neighbor_rebuild_target(
	targets: Dictionary,
	source_chunk_position: Vector2i,
	neighbor_chunk_position: Vector2i,
	source_local_position: Vector3i
) -> void:
	if not loaded_chunks.has(neighbor_chunk_position):
		return
	# Greedy boxes contain only voxels owned by their chunk, so border visibility
	# requires a visual remesh but never a physics rebuild in the neighbor.
	targets[neighbor_chunk_position] = targets.get(neighbor_chunk_position, {})


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


func spawn_item(
	item_id: int,
	position: Vector3,
	amount: int = 1,
	initial_velocity: Vector3 = Vector3.ZERO,
	use_initial_velocity: bool = false,
	pickup_delay_override: float = -1.0
) -> DroppedItem:
	if dropped_item_scene == null or item_id == ItemRegistry.Item.NONE or amount <= 0:
		return null
	var dropped_item := dropped_item_scene.instantiate() as DroppedItem
	if dropped_item == null:
		return null
	dropped_item.item_id = item_id
	dropped_item.amount = amount
	dropped_item.initial_velocity = initial_velocity
	dropped_item.has_initial_velocity = use_initial_velocity
	if pickup_delay_override >= 0.0:
		dropped_item.pickup_delay = pickup_delay_override
	add_child(dropped_item)
	dropped_item.global_position = position
	return dropped_item


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
	var sun_changed_chunks := update_sunlight_after_change(chunk.local_to_world(local_position))
	var collision_sections := get_affected_collision_regions(local_position)
	request_chunk_rebuild(chunk.chunk_position, true, collision_sections)
	for neighbor_position in chunk.get_affected_neighbor_positions(local_position):
		request_chunk_rebuild(neighbor_position, true, [])
	for changed_position in light_changed_chunks:
		if changed_position != chunk.chunk_position and not chunk.get_affected_neighbor_positions(local_position).has(changed_position):
			request_chunk_rebuild(changed_position, true)
	for changed_position in sun_changed_chunks:
		if changed_position != chunk.chunk_position and not chunk.get_affected_neighbor_positions(local_position).has(changed_position):
			request_chunk_rebuild(changed_position, true)


func queue_leaf_checks_around(world_position: Vector3i) -> void:
	for direction in TREE_LOG_DIRECTIONS:
		queue_leaf_check(world_position + direction)


func queue_leaf_check(world_position: Vector3i, delay_seconds: float = LEAF_DECAY_DELAY_SECONDS) -> void:
	var block_result := try_get_block_at_world_position(world_position)
	if not bool(block_result["known"]) or int(block_result["block"]) != BlockRegistry.Block.LEAVES:
		return
	var due_msec := Time.get_ticks_msec() + roundi(delay_seconds * 1000.0)
	if pending_leaf_checks.has(world_position):
		pending_leaf_checks[world_position] = mini(int(pending_leaf_checks[world_position]), due_msec)
	else:
		pending_leaf_checks[world_position] = due_msec


func process_pending_leaf_checks() -> void:
	if pending_leaf_checks.is_empty():
		return
	var now_msec := Time.get_ticks_msec()
	var validations := 0
	for position in pending_leaf_checks.keys():
		if validations >= MAX_LEAF_VALIDATIONS_PER_FRAME:
			break
		if int(pending_leaf_checks[position]) > now_msec:
			continue
		pending_leaf_checks.erase(position)
		validations += 1
		var support_result := check_leaf_support(position)
		if bool(support_result["ambiguous"]):
			queue_leaf_check(position, LEAF_AMBIGUOUS_RETRY_SECONDS)
		elif not bool(support_result["supported"]):
			schedule_leaf_decay(position)


func schedule_leaf_decay(world_position: Vector3i) -> void:
	if pending_leaf_decay.has(world_position):
		return
	var delay_range := LEAF_DISAPPEAR_MAX_MSEC - LEAF_DISAPPEAR_MIN_MSEC + 1
	var position_hash := int(hash(world_position)) & 0x7fffffff
	var delay_msec := LEAF_DISAPPEAR_MIN_MSEC + position_hash % delay_range
	pending_leaf_decay[world_position] = Time.get_ticks_msec() + delay_msec
	queue_leaf_checks_around(world_position)


func process_pending_leaf_decay() -> void:
	if pending_leaf_decay.is_empty():
		return
	var now_msec := Time.get_ticks_msec()
	var validations := 0
	var leaves_to_remove: Array[Vector3i] = []
	for position in pending_leaf_decay.keys():
		if validations >= MAX_LEAF_VALIDATIONS_PER_FRAME or leaves_to_remove.size() >= MAX_LEAVES_REMOVED_PER_FRAME:
			break
		if int(pending_leaf_decay[position]) > now_msec:
			continue
		pending_leaf_decay.erase(position)
		validations += 1
		var support_result := check_leaf_support(position)
		if bool(support_result["ambiguous"]):
			pending_leaf_decay[position] = now_msec + roundi(LEAF_AMBIGUOUS_RETRY_SECONDS * 1000.0)
		elif not bool(support_result["supported"]):
			leaves_to_remove.append(position)
	remove_leaves_batch(leaves_to_remove)


func check_leaf_support(start_position: Vector3i) -> Dictionary:
	var start_result := try_get_block_at_world_position(start_position)
	if not bool(start_result["known"]):
		return {"supported": false, "ambiguous": true}
	if int(start_result["block"]) != BlockRegistry.Block.LEAVES:
		return {"supported": true, "ambiguous": false}
	var frontier: Array[Dictionary] = [{"position": start_position, "distance": 0}]
	var visited: Dictionary = {start_position: true}
	var frontier_index := 0
	while frontier_index < frontier.size():
		var entry: Dictionary = frontier[frontier_index]
		frontier_index += 1
		var position: Vector3i = entry["position"]
		var distance: int = entry["distance"]
		if distance >= LEAF_SUPPORT_DISTANCE:
			continue
		for direction in TREE_LOG_DIRECTIONS:
			var neighbor := position + direction
			var block_result := try_get_block_at_world_position(neighbor)
			if not bool(block_result["known"]):
				return {"supported": false, "ambiguous": true}
			var block := int(block_result["block"])
			if block == BlockRegistry.Block.WOOD:
				return {"supported": true, "ambiguous": false}
			if block != BlockRegistry.Block.LEAVES or visited.has(neighbor):
				continue
			if visited.size() >= MAX_LEAF_BFS_NODES:
				return {"supported": false, "ambiguous": true}
			visited[neighbor] = true
			frontier.append({"position": neighbor, "distance": distance + 1})
	return {"supported": false, "ambiguous": false}


func remove_leaves_batch(world_positions: Array[Vector3i]) -> void:
	var removed_positions: Array[Vector3i] = []
	for world_position in world_positions:
		var chunk := get_chunk_at_world_position(world_position)
		if chunk == null:
			continue
		var local_position := chunk.world_to_local(world_position)
		if chunk.get_block_local(local_position) != BlockRegistry.Block.LEAVES:
			continue
		if chunk.remove_block_local(local_position) != BlockRegistry.Block.LEAVES:
			continue
		record_block_override(chunk, local_position)
		removed_positions.append(world_position)
		queue_leaf_checks_around(world_position)
	apply_removed_blocks_batch(removed_positions)


func apply_removed_blocks_batch(world_positions: Array[Vector3i]) -> void:
	if world_positions.is_empty():
		return
	var rebuild_sections: Dictionary = {}
	var light_changed_chunks: Dictionary = {}
	var sun_changed_chunks: Dictionary = {}
	var sunlight_columns: Dictionary = {}
	for world_position in world_positions:
		var chunk := get_chunk_at_world_position(world_position)
		if chunk == null:
			continue
		var local_position := chunk.world_to_local(world_position)
		add_tree_rebuild_target(rebuild_sections, chunk.chunk_position, local_position)
		for neighbor_position in chunk.get_affected_neighbor_positions(local_position):
			add_tree_neighbor_rebuild_target(
				rebuild_sections, chunk.chunk_position, neighbor_position, local_position
			)
		merge_chunk_set(light_changed_chunks, update_block_light_after_change(world_position))
		var column := Vector2i(world_position.x, world_position.z)
		if not sunlight_columns.has(column):
			sunlight_columns[column] = world_position
	for world_position in sunlight_columns.values():
		merge_chunk_set(sun_changed_chunks, update_sunlight_after_change(world_position))
	for changed_position in light_changed_chunks:
		if not rebuild_sections.has(changed_position):
			rebuild_sections[changed_position] = {}
	for changed_position in sun_changed_chunks:
		if not rebuild_sections.has(changed_position):
			rebuild_sections[changed_position] = {}
	for chunk_position in rebuild_sections:
		var sections: Array[int] = []
		for section in rebuild_sections[chunk_position]:
			sections.append(section)
		sections.sort()
		request_chunk_rebuild(chunk_position, true, sections)


func merge_chunk_set(target: Dictionary, source: Dictionary) -> void:
	for chunk_position in source:
		target[chunk_position] = true


func get_affected_collision_regions(local_position: Vector3i) -> Array[int]:
	var region := Vector3i(
		clampi(local_position.x / Chunk.COLLISION_REGION_SIZE, 0, Chunk.COLLISION_REGION_COUNT_X - 1),
		clampi(local_position.y / Chunk.COLLISION_REGION_SIZE, 0, Chunk.COLLISION_REGION_COUNT_Y - 1),
		clampi(local_position.z / Chunk.COLLISION_REGION_SIZE, 0, Chunk.COLLISION_REGION_COUNT_Z - 1)
	)
	return [ChunkMesher.get_collision_region_index(region)]


func rebuild_chunk_at(chunk_position: Vector2i) -> void:
	var all_sections: Array[int] = []
	for section in Chunk.COLLISION_REGION_COUNT:
		all_sections.append(section)
	request_chunk_rebuild(chunk_position, true, all_sections)


func record_block_override(chunk: Chunk, local_position: Vector3i) -> void:
	if chunk == null or not chunk.is_valid_local_position(local_position):
		return
	var overrides: Dictionary = chunk_overrides.get(chunk.chunk_position, {})
	overrides[local_position] = chunk.get_block_local(local_position)
	chunk_overrides[chunk.chunk_position] = overrides
