class_name Player
extends CharacterBody3D

@export var speed: float = 5.0
@export var jump_velocity: float = 7.0
@export var mouse_sensitivity: float = 0.002
@export var interaction_distance: float = 6.0
@export var break_cooldown: float = 0.22
@export var place_cooldown: float = 0.12
@export var fly_speed: float = 12.0

@onready var camera: Camera3D = $Camera3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var hotbar = get_tree().get_first_node_in_group("hotbar")
@onready var block_highlight: MeshInstance3D = $BlockHighlight
@onready var world: World = get_tree().get_first_node_in_group("world")
@onready var inventory: Inventory = $Inventory

var gravity: float = 20.0
var break_timer: float = 0.0
var place_timer: float = 0.0

var selected_slot: int = 0

var is_flying: bool = false
var inventory_open: bool = false

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	block_highlight.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F:
		set_flying(!is_flying)

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)

		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		camera.rotation.x = clamp(
			camera.rotation.x,
			deg_to_rad(-89.0),
			deg_to_rad(89.0)
		)

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			select_slot(selected_slot - 1)

		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			select_slot(selected_slot + 1)

	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				select_slot(0)
			KEY_2:
				select_slot(1)
			KEY_3:
				select_slot(2)
			KEY_4:
				select_slot(3)
			KEY_5:
				select_slot(4)
			KEY_6:
				select_slot(5)
			KEY_7:
				select_slot(6)
			KEY_8:
				select_slot(7)
			KEY_9:
				select_slot(8)

	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	break_timer = max(break_timer - delta, 0.0)
	place_timer = max(place_timer - delta, 0.0)

	if (not inventory_open and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and break_timer <= 0.0):
		break_block()
		break_timer = break_cooldown

	if (not inventory_open and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and place_timer <= 0.0):
		place_block()
		place_timer = place_cooldown

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

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	var input_direction := Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_backward"
	)
	

	var direction := (transform.basis * Vector3(input_direction.x, 0.0, input_direction.y)).normalized()

	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	move_and_slide()

	update_block_highlight()

func break_block() -> void:
	var from := camera.global_position
	var to := from + -camera.global_transform.basis.z * interaction_distance

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = 1

	var result := get_world_3d().direct_space_state.intersect_ray(query)

	if result.is_empty():
		return

	var hit_position: Vector3 = result.position
	var hit_normal: Vector3 = result.normal

	var world_block_position := Vector3i(
	floor(hit_position.x - hit_normal.x * 0.01),
	floor(hit_position.y - hit_normal.y * 0.01),
	floor(hit_position.z - hit_normal.z * 0.01)
)

	var chunk := get_chunk_from_hit(result.collider)

	if chunk == null:
		return

	var local_block_position := world_block_position - Vector3i(chunk.global_position)

	var broken_block := chunk.remove_block(local_block_position)

	if broken_block == BlockRegistry.Block.AIR:
		return

	world.rebuild_chunk_and_neighbors(chunk, local_block_position)

	var dropped_item := ItemRegistry.get_drop(broken_block)

	if dropped_item == ItemRegistry.Item.NONE:
		return

	world.spawn_item(
		dropped_item,
		Vector3(world_block_position) + Vector3(0.5, 0.5, 0.5)
	)

func place_block() -> void:
	var from := camera.global_position
	var to := from + -camera.global_transform.basis.z * interaction_distance

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = 1

	var result := get_world_3d().direct_space_state.intersect_ray(query)

	if result.is_empty():
		return

	var hit_position: Vector3 = result.position
	var hit_normal: Vector3 = result.normal

	var block_position := Vector3i(
		floor(hit_position.x + hit_normal.x * 0.01),
		floor(hit_position.y + hit_normal.y * 0.01),
		floor(hit_position.z + hit_normal.z * 0.01)
	)

	if is_block_inside_player(block_position):
		return

	if world == null or hotbar == null:
		return

	var selected_block: int = hotbar.get_selected_block()

	if selected_block == BlockRegistry.Block.AIR:
		return

	var target_chunk := world.get_chunk_at_world_position(block_position)

	if target_chunk == null:
		return

	var local_block_position := block_position - Vector3i(target_chunk.global_position)
	

	if target_chunk.place_block(local_block_position, selected_block):
		world.rebuild_chunk_and_neighbors(
			target_chunk,
			local_block_position
		)

		hotbar.remove_selected_item(1)

func is_block_inside_player(block_position: Vector3i) -> bool:
	var block_min := Vector3(block_position)
	var block_max := block_min + Vector3.ONE

	var player_position := global_position

	var player_radius := 0.4
	var player_height := 1.8

	var player_min := Vector3(
		player_position.x - player_radius,
		player_position.y,
		player_position.z - player_radius
	)

	var player_max := Vector3(
		player_position.x + player_radius,
		player_position.y + player_height,
		player_position.z + player_radius
	)

	return (
		block_min.x < player_max.x
		and block_max.x > player_min.x
		and block_min.y < player_max.y
		and block_max.y > player_min.y
		and block_min.z < player_max.z
		and block_max.z > player_min.z
	)

func select_slot(index: int) -> void:
	if hotbar == null:
		return

	selected_slot = wrapi(index, 0, 9)
	hotbar.set_selected_slot(selected_slot)


func update_block_highlight() -> void:
	var from := camera.global_position
	var to := from + -camera.global_transform.basis.z * interaction_distance

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = 1

	var result := get_world_3d().direct_space_state.intersect_ray(query)

	if result.is_empty():
		block_highlight.visible = false
		return

	var hit_position: Vector3 = result.position
	var hit_normal: Vector3 = result.normal

	var block_position := Vector3i(
		floor(hit_position.x - hit_normal.x * 0.01),
		floor(hit_position.y - hit_normal.y * 0.01),
		floor(hit_position.z - hit_normal.z * 0.01)
	)

	block_highlight.global_position = Vector3(block_position) + Vector3(0.5, 0.5, 0.5)
	block_highlight.visible = true

func get_chunk_from_hit(collider: Object) -> Chunk:
	if collider == null:
		return null

	if collider.has_meta("chunk"):
		return collider.get_meta("chunk") as Chunk

	return null


func set_flying(enabled: bool) -> void:
	is_flying = enabled
	velocity = Vector3.ZERO

	collision_shape.set_deferred("disabled", enabled)

func collect_item(item_id: int, amount: int) -> void:
	var remaining := inventory.add_item(item_id, amount)

	if remaining > 0:
		print("Inventario lleno. Quedaron ", remaining, " items.")
