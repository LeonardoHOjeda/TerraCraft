class_name Player
extends CharacterBody3D

signal crafting_stations_changed

@export var speed: float = 5.0
@export var jump_velocity: float = 7.0
@export var mouse_sensitivity: float = 0.002
@export var interaction_distance: float = 6.0
@export var place_cooldown: float = 0.12
@export var fly_speed: float = 12.0
@export var crafting_station_radius: int = 3
@export var station_check_interval: float = 0.25
@export var cracks_texture: Texture2D

@onready var camera: Camera3D = $Camera3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var hotbar = get_tree().get_first_node_in_group("hotbar")
@onready var block_highlight: MeshInstance3D = $BlockHighlight
@onready var world: World = get_tree().get_first_node_in_group("world")
@onready var inventory: Inventory = $Inventory
@onready var mining_cracks: MeshInstance3D = $MiningCracks

var gravity: float = 20.0
var selected_slot: int = 0
var is_flying: bool = false
var inventory_open: bool = false
var mining_controller: MiningController
var block_placement_controller: BlockPlacementController
var station_detector: StationDetector

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	block_highlight.visible = false
	setup_components()

func setup_components() -> void:
	mining_controller = MiningController.new()
	mining_controller.name = "MiningController"
	add_child(mining_controller)
	mining_controller.setup(self, camera, world, hotbar, mining_cracks, interaction_distance, cracks_texture)
	block_placement_controller = BlockPlacementController.new()
	block_placement_controller.name = "BlockPlacementController"
	add_child(block_placement_controller)
	block_placement_controller.setup(self, camera, world, hotbar, interaction_distance, place_cooldown)
	station_detector = StationDetector.new()
	station_detector.name = "StationDetector"
	add_child(station_detector)
	station_detector.setup(self, world, crafting_station_radius, station_check_interval)
	station_detector.stations_changed.connect(_on_crafting_stations_changed)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F:
		set_flying(!is_flying)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			select_slot(selected_slot - 1)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			select_slot(selected_slot + 1)
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1: select_slot(0)
			KEY_2: select_slot(1)
			KEY_3: select_slot(2)
			KEY_4: select_slot(3)
			KEY_5: select_slot(4)
			KEY_6: select_slot(5)
			KEY_7: select_slot(6)
			KEY_8: select_slot(7)
			KEY_9: select_slot(8)
	if event.is_action_pressed("ui_cancel") and not inventory_open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _physics_process(delta: float) -> void:
	mining_controller.process(delta, not inventory_open)
	block_placement_controller.process(delta, not inventory_open)
	station_detector.process(delta)
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
	var block_position := Vector3i(floor(hit_position.x - hit_normal.x * 0.01), floor(hit_position.y - hit_normal.y * 0.01), floor(hit_position.z - hit_normal.z * 0.01))
	block_highlight.global_position = Vector3(block_position) + Vector3(0.5, 0.5, 0.5)
	block_highlight.visible = true

func set_flying(enabled: bool) -> void:
	is_flying = enabled
	velocity = Vector3.ZERO
	collision_shape.set_deferred("disabled", enabled)

func collect_item(item_id: int, amount: int) -> int:
	return inventory.add_item(item_id, amount)

func has_nearby_station(station: int) -> bool:
	return station_detector.has_nearby_station(station)

func _on_crafting_stations_changed() -> void:
	crafting_stations_changed.emit()
