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
	var target_chunk := world.get_chunk_at_world_position(block_position)
	if target_chunk == null:
		return
	var local_position := block_position - Vector3i(target_chunk.global_position)
	if target_chunk.place_block(local_position, selected_block):
		world.rebuild_chunk_and_neighbors(target_chunk, local_position)
		hotbar_controller.consume_selected_item(1)

func is_block_inside_player(block_position: Vector3i) -> bool:
	var block_min := Vector3(block_position)
	var block_max := block_min + Vector3.ONE
	var position := player.global_position
	var player_min := Vector3(position.x - 0.4, position.y, position.z - 0.4)
	var player_max := Vector3(position.x + 0.4, position.y + 1.8, position.z + 0.4)
	return block_min.x < player_max.x and block_max.x > player_min.x and block_min.y < player_max.y and block_max.y > player_min.y and block_min.z < player_max.z and block_max.z > player_min.z
