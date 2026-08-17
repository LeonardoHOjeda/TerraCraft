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
@onready var block_highlight: MeshInstance3D = $BlockHighlight
@onready var world: World = get_tree().get_first_node_in_group("world")
@onready var inventory: Inventory = $Inventory
@onready var mining_cracks: MeshInstance3D = $MiningCracks

var gravity: float = 20.0
var is_flying: bool = false
var mining_controller: MiningController
var block_placement_controller: BlockPlacementController
var station_detector: StationDetector
var hotbar_controller: HotbarController
var interaction_state: PlayerInteractionState
var targeting_controller: BlockTargetingController

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	block_highlight.visible = false
	setup_components()

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
	station_detector.stations_changed.connect(_on_crafting_stations_changed)

func _unhandled_input(event: InputEvent) -> void:
	hotbar_controller.handle_input(event)
	if event is InputEventKey and event.pressed and event.keycode == KEY_F:
		set_flying(!is_flying)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))
	if event.is_action_pressed("ui_cancel") and not interaction_state.is_inventory_open():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _physics_process(delta: float) -> void:
	targeting_controller.update_target()
	mining_controller.process(delta)
	block_placement_controller.process(delta)
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

func update_block_highlight() -> void:
	var target := targeting_controller.current_target
	if not target.is_valid:
		block_highlight.visible = false
		return
	block_highlight.global_position = Vector3(target.block_position) + Vector3(0.5, 0.5, 0.5)
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
