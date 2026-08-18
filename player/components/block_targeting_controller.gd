class_name BlockTargetingController
extends Node

class BlockTarget:
	extends RefCounted

	var is_valid: bool = false
	var collider: Object
	var chunk: Chunk
	var block_position: Vector3i
	var local_position: Vector3i
	var hit_normal: Vector3
	var adjacent_block_position: Vector3i

var player: Player
var camera: Camera3D
var interaction_distance: float
var current_target := BlockTarget.new()


func setup(new_player: Player, new_camera: Camera3D, distance: float) -> void:
	player = new_player
	camera = new_camera
	interaction_distance = distance


func update_target() -> void:
	current_target = BlockTarget.new()
	if player.is_trapped_in_blocks and player.is_camera_inside_solid():
		if target_camera_block():
			return
	var from := camera.global_position
	var to := from + -camera.global_transform.basis.z * interaction_distance
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = 1
	var result := player.get_world_3d().direct_space_state.intersect_ray(query)

	if result.is_empty():
		return

	var hit_position: Vector3 = result.position
	var hit_normal: Vector3 = result.normal
	var chunk := Chunk.from_collider(result.collider)
	if chunk == null:
		return
	var block_position := Vector3i(
		floor(hit_position.x - hit_normal.x * 0.01),
		floor(hit_position.y - hit_normal.y * 0.01),
		floor(hit_position.z - hit_normal.z * 0.01)
	)
	var adjacent_position := Vector3i(
		floor(hit_position.x + hit_normal.x * 0.01),
		floor(hit_position.y + hit_normal.y * 0.01),
		floor(hit_position.z + hit_normal.z * 0.01)
	)
	if result.collider.has_meta("special_local_position"):
		block_position = chunk.local_to_world(result.collider.get_meta("special_local_position"))

	var local_position := chunk.world_to_local(block_position)

	if (
		local_position.x < 0
		or local_position.x >= Chunk.SIZE_XZ
		or local_position.y < 0
		or local_position.y >= Chunk.HEIGHT
		or local_position.z < 0
		or local_position.z >= Chunk.SIZE_XZ
	):
		return

	var block_id := chunk.data.get_block(local_position)

	if block_id == BlockRegistry.Block.AIR:
		return

	current_target.is_valid = true
	current_target.collider = result.collider
	current_target.chunk = chunk
	current_target.block_position = block_position
	current_target.local_position = local_position
	current_target.hit_normal = hit_normal
	current_target.adjacent_block_position = adjacent_position


func target_camera_block() -> bool:
	var block_position := player.get_camera_block_position()
	var chunk := player.world.get_chunk_at_world_position(block_position)
	if chunk == null:
		return false
	var local_position := chunk.world_to_local(block_position)
	if not chunk.is_valid_local_position(local_position):
		return false
	var block_id := chunk.get_block_local(local_position)
	if not BlockRegistry.is_mesh_block(block_id):
		return false
	current_target.is_valid = true
	current_target.chunk = chunk
	current_target.block_position = block_position
	current_target.local_position = local_position
	current_target.hit_normal = Vector3.ZERO
	current_target.adjacent_block_position = block_position
	return true
