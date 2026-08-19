class_name BlockPlacementController
extends Node

var player: Player
var world: World
var hotbar_controller: HotbarController
var interaction_state: PlayerInteractionState
var targeting_controller: BlockTargetingController
var place_cooldown: float
var place_timer := 0.0

func setup(new_player: Player, new_world: World, new_hotbar_controller: HotbarController, new_interaction_state: PlayerInteractionState, new_targeting_controller: BlockTargetingController, cooldown: float) -> void:
	player = new_player
	world = new_world
	hotbar_controller = new_hotbar_controller
	interaction_state = new_interaction_state
	targeting_controller = new_targeting_controller
	place_cooldown = cooldown

func process(delta: float) -> void:
	place_timer = max(place_timer - delta, 0.0)
	if interaction_state.can_interact_with_blocks() and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and place_timer <= 0.0:
		place_block()
		place_timer = place_cooldown

func place_block() -> void:
	var target := targeting_controller.current_target
	if not target.is_valid:
		return
	var block_position: Vector3i = target.adjacent_block_position
	if is_block_inside_player(block_position) or world == null or hotbar_controller == null:
		return
	var selected_block: int = hotbar_controller.get_selected_block()
	if selected_block == BlockRegistry.Block.AIR:
		return
	var support_direction := Vector3i.DOWN
	if selected_block == BlockRegistry.Block.TORCH:
		var hit_direction := Vector3i(roundi(target.hit_normal.x), roundi(target.hit_normal.y), roundi(target.hit_normal.z))
		if hit_direction == Vector3i.DOWN or hit_direction == Vector3i.ZERO:
			return
		support_direction = -hit_direction
		var support_position := block_position + support_direction
		if not BlockRegistry.is_occluding_block(world.get_block_at_world_position(support_position)):
			return
	var target_chunk := world.get_chunk_at_world_position(block_position)
	if target_chunk == null:
		return
	var local_position := target_chunk.world_to_local(block_position)
	var placed := false
	if selected_block == BlockRegistry.Block.TORCH:
		placed = target_chunk.place_oriented_block_local(local_position, selected_block, support_direction)
	else:
		placed = target_chunk.place_block_local(local_position, selected_block)
	if placed:
		world.rebuild_chunk_and_neighbors(target_chunk, local_position)
		if selected_block == BlockRegistry.Block.WOOD:
			world.queue_leaf_checks_around(block_position)
		hotbar_controller.consume_selected_item(1)

func is_block_inside_player(block_position: Vector3i) -> bool:
	var capsule := player.collision_shape.shape as CapsuleShape3D
	if capsule == null:
		return false

	var center := player.collision_shape.global_position
	var radius := capsule.radius
	var half_height := capsule.height * 0.5
	var feet_y := center.y - half_height
	var block_top := float(block_position.y + 1)

	var block_min := Vector3(block_position)
	var block_max := block_min + Vector3.ONE

	var overlaps_player_horizontally := (
		block_min.x < center.x + radius
		and block_max.x > center.x - radius
		and block_min.z < center.z + radius
		and block_max.z > center.z - radius
	)

	var is_directly_below := (
		overlaps_player_horizontally
		and block_top <= feet_y + 0.1
	)

	if is_directly_below:
		return false

	var player_min := Vector3(
		center.x - radius,
		center.y - half_height,
		center.z - radius
	)

	var player_max := Vector3(
		center.x + radius,
		center.y + half_height,
		center.z + radius
	)

	return (
		block_min.x < player_max.x
		and block_max.x > player_min.x
		and block_min.y < player_max.y
		and block_max.y > player_min.y
		and block_min.z < player_max.z
		and block_max.z > player_min.z
	)
