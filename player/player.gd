class_name Player
extends CharacterBody3D

@export var speed: float = 5.0
@export var jump_velocity: float = 7.0
@export var mouse_sensitivity: float = 0.002
@export var interaction_distance: float = 6.0
@export var place_cooldown: float = 0.12
@export var fly_speed: float = 12.0
@export var crafting_station_radius: int = 3
@export var station_check_interval: float = 0.25
@export var cracks_texture: Texture2D
@export var voluntary_drop_distance: float = 1.75
@export var voluntary_drop_down_offset: float = 0.25
@export var voluntary_drop_forward_speed: float = 3.5
@export var voluntary_drop_upward_speed: float = 0.35
@export var manual_drop_pickup_delay: float = 1.25

@onready var camera: Camera3D = $Camera3D
@onready var held_item_light: OmniLight3D = $Camera3D/HeldItemLight
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var block_highlight: MeshInstance3D = $BlockHighlight
@onready var world: World = get_tree().get_first_node_in_group("world")
@onready var inventory: Inventory = $Inventory
@onready var mining_cracks: MeshInstance3D = $MiningCracks
@onready var trapped_overlay: ColorRect = $TrappedOverlay/BlackOverlay

var gravity: float = 20.0
var is_flying: bool = false
var is_trapped_in_blocks: bool = false
var mining_controller: MiningController
var block_placement_controller: BlockPlacementController
var station_detector: StationDetector
var hotbar_controller: HotbarController
var interaction_state: PlayerInteractionState
var targeting_controller: BlockTargetingController

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	block_highlight.visible = false
	trapped_overlay.visible = false
	setup_components()
	hotbar_controller.selected_item_changed.connect(update_held_item_light)
	update_held_item_light(hotbar_controller.get_selected_item())

func setup_components() -> void:
	interaction_state = PlayerInteractionState.new()
	interaction_state.name = "InteractionState"
	add_child(interaction_state)
	hotbar_controller = HotbarController.new()
	hotbar_controller.name = "HotbarController"
	add_child(hotbar_controller)
	hotbar_controller.setup(inventory)
	targeting_controller = BlockTargetingController.new()
	targeting_controller.name = "BlockTargetingController"
	add_child(targeting_controller)
	targeting_controller.setup(self, camera, interaction_distance)
	mining_controller = MiningController.new()
	mining_controller.name = "MiningController"
	add_child(mining_controller)
	mining_controller.setup(world, hotbar_controller, interaction_state, targeting_controller, mining_cracks, cracks_texture)
	block_placement_controller = BlockPlacementController.new()
	block_placement_controller.name = "BlockPlacementController"
	add_child(block_placement_controller)
	block_placement_controller.setup(self, world, hotbar_controller, interaction_state, targeting_controller, place_cooldown)
	station_detector = StationDetector.new()
	station_detector.name = "StationDetector"
	add_child(station_detector)
	station_detector.setup(self, world, crafting_station_radius, station_check_interval)


func update_held_item_light(item_id: int) -> void:
	held_item_light.visible = item_id == ItemRegistry.Item.TORCH

func _unhandled_input(event: InputEvent) -> void:
	if (
		event.is_action_pressed("drop_item")
		and event is InputEventKey
		and not event.echo
		and can_drop_from_hotbar()
	):
		if drop_selected_hotbar_item():
			get_viewport().set_input_as_handled()
		return

	if not interaction_state.is_inventory_open():
		hotbar_controller.handle_input(event)

	if event is InputEventKey and event.pressed and event.keycode == KEY_F:
		if not interaction_state.is_inventory_open():
			set_flying(!is_flying)

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))

	if event.is_action_pressed("ui_cancel") and not interaction_state.is_inventory_open():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func try_drop_item(item_id: int, consume_source: Callable) -> bool:
	if (
		world == null
		or item_id == ItemRegistry.Item.NONE
		or not consume_source.is_valid()
	):
		return false

	var forward := -camera.global_basis.z.normalized()
	var spawn_position := (
		camera.global_position
		+ forward * voluntary_drop_distance
		+ Vector3.DOWN * voluntary_drop_down_offset
	)
	var spawn_velocity := (
		forward * voluntary_drop_forward_speed
		+ Vector3.UP * voluntary_drop_upward_speed
	)
	var dropped_item := world.spawn_item(
		item_id,
		spawn_position,
		1,
		spawn_velocity,
		true,
		manual_drop_pickup_delay
	)

	if dropped_item == null:
		return false

	if not consume_source.call():
		dropped_item.queue_free()
		return false

	return true


func can_drop_from_hotbar() -> bool:
	return (
		not interaction_state.is_inventory_open()
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		and not is_trapped_in_blocks
	)


func drop_selected_hotbar_item() -> bool:
	var inventory_index := hotbar_controller.get_selected_inventory_index()
	var item_id := inventory.get_item(inventory_index)
	if item_id == ItemRegistry.Item.NONE:
		return false

	return try_drop_item(
		item_id,
		_remove_hotbar_item.bind(inventory_index, item_id)
	)


func _remove_hotbar_item(inventory_index: int, expected_item: int) -> bool:
	if inventory.get_item(inventory_index) != expected_item:
		return false
	return inventory.remove_item(inventory_index, 1)

func _physics_process(delta: float) -> void:
	update_noclip_state()
	targeting_controller.update_target()
	mining_controller.process(delta)
	block_placement_controller.process(delta)
	station_detector.process(delta)
	if is_trapped_in_blocks:
		velocity = Vector3.ZERO
		update_block_highlight()
		return
	if interaction_state.is_inventory_open():
		velocity.x = 0.0
		velocity.z = 0.0

		if is_flying:
			velocity.y = 0.0
		elif not is_on_floor():
			velocity.y -= gravity * delta

		move_and_slide()
		update_block_highlight()
		return

	if is_flying:
		var input_direction := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
		var direction := (transform.basis * Vector3(input_direction.x, 0.0, input_direction.y)).normalized()
		velocity.x = direction.x * fly_speed
		velocity.z = direction.z * fly_speed
		velocity.y = 0.0

		if Input.is_action_pressed("jump"):
			velocity.y = fly_speed
		if Input.is_action_pressed("fly_down"):
			velocity.y = -fly_speed
		move_and_slide()
		update_block_highlight()
		return

	if not is_on_floor():
		velocity.y -= gravity * delta
	if Input.is_action_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	var input_direction := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := (transform.basis * Vector3(input_direction.x, 0.0, input_direction.y)).normalized()

	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	move_and_slide()
	update_block_highlight()

func update_block_highlight() -> void:
	if is_camera_inside_solid():
		block_highlight.visible = false
		return
	var target := targeting_controller.current_target
	if not target.is_valid:
		block_highlight.visible = false
		return
	block_highlight.global_position = Vector3(target.block_position) + Vector3(0.5, 0.5, 0.5)
	block_highlight.visible = true

func set_flying(enabled: bool) -> void:
	is_flying = enabled
	velocity = Vector3.ZERO
	if enabled:
		is_trapped_in_blocks = false
		collision_shape.set_deferred("disabled", true)
	else:
		is_trapped_in_blocks = not is_body_space_free()
		collision_shape.set_deferred("disabled", is_trapped_in_blocks)
	update_trapped_overlay()

func update_noclip_state() -> void:
	if is_trapped_in_blocks and is_body_space_free() and is_physics_body_space_free():
		velocity = Vector3.ZERO
		if collision_shape.disabled:
			collision_shape.set_deferred("disabled", false)
		else:
			is_trapped_in_blocks = false
	update_trapped_overlay()

func update_trapped_overlay() -> void:
	trapped_overlay.visible = not is_flying and is_camera_inside_solid()

func is_camera_inside_solid() -> bool:
	if world == null:
		return false
	return BlockRegistry.is_mesh_block(
		world.get_block_at_world_position(get_camera_block_position())
	)

func get_camera_block_position() -> Vector3i:
	return Vector3i(
		floori(camera.global_position.x),
		floori(camera.global_position.y),
		floori(camera.global_position.z)
	)

func is_body_space_free() -> bool:
	if world == null or not collision_shape.shape is CapsuleShape3D:
		return true
	var capsule := collision_shape.shape as CapsuleShape3D
	var shape_transform := collision_shape.global_transform
	var radius := capsule.radius * maxf(
		shape_transform.basis.x.length(), shape_transform.basis.z.length()
	)
	var half_segment := maxf(capsule.height * 0.5 - capsule.radius, 0.0)
	half_segment *= shape_transform.basis.y.length()
	var center := shape_transform.origin
	var segment_bottom := center.y - half_segment
	var segment_top := center.y + half_segment
	var bounds_min := Vector3(center.x - radius, segment_bottom - radius, center.z - radius)
	var bounds_max := Vector3(center.x + radius, segment_top + radius, center.z + radius)
	for x in range(floori(bounds_min.x), floori(bounds_max.x) + 1):
		for y in range(floori(bounds_min.y), floori(bounds_max.y) + 1):
			for z in range(floori(bounds_min.z), floori(bounds_max.z) + 1):
				var block_position := Vector3i(x, y, z)
				if not BlockRegistry.is_mesh_block(
					world.get_block_at_world_position(block_position)
				):
					continue
				if capsule_overlaps_block(
					center, segment_bottom, segment_top, radius, block_position
				):
					return false
	return true

func is_physics_body_space_free() -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collision_shape.shape
	query.transform = collision_shape.global_transform
	query.collision_mask = 1
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func capsule_overlaps_block(
	center: Vector3,
	segment_bottom: float,
	segment_top: float,
	radius: float,
	block_position: Vector3i
) -> bool:
	var block_min := Vector3(block_position)
	var block_max := block_min + Vector3.ONE
	var closest_segment_y := clampf(center.y, segment_bottom, segment_top)
	var closest_block_y := clampf(closest_segment_y, block_min.y, block_max.y)
	closest_segment_y = clampf(closest_block_y, segment_bottom, segment_top)
	var delta := Vector3(
		center.x - clampf(center.x, block_min.x, block_max.x),
		closest_segment_y - clampf(closest_segment_y, block_min.y, block_max.y),
		center.z - clampf(center.z, block_min.z, block_max.z)
	)
	return delta.length_squared() < radius * radius

func collect_item(item_id: int, amount: int) -> int:
	return inventory.add_item(item_id, amount)
