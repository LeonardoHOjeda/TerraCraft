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

	current_target.is_valid = true
	current_target.collider = result.collider
	current_target.chunk = chunk
	current_target.block_position = block_position
	current_target.hit_normal = hit_normal
	current_target.adjacent_block_position = adjacent_position
	if chunk != null:
		current_target.local_position = chunk.world_to_local(block_position)
