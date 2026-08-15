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
var place_timer: float = 0.0

var selected_slot: int = 0

var is_flying: bool = false
var inventory_open: bool = false

var nearby_workbench: bool = false
var nearby_furnace: bool = false
var station_check_timer: float = 0.0

var mining_progress: float = 0.0
var mining_block_position: Vector3i
var is_mining: bool = false

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	block_highlight.visible = false
	mining_cracks.visible = false
	build_mining_cracks_mesh()


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

	if event.is_action_pressed("ui_cancel") and not inventory_open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	place_timer = max(place_timer - delta, 0.0)

	if (not inventory_open and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)):
		process_mining(delta)
	else:
		reset_mining()

	if (not inventory_open and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and place_timer <= 0.0):
		place_block()
		place_timer = place_cooldown

	station_check_timer += delta

	if station_check_timer >= station_check_interval:
		station_check_timer = 0.0
		update_nearby_crafting_stations()

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

func collect_item(item_id: int, amount: int) -> int:
	return inventory.add_item(item_id, amount)



func has_nearby_station(station: int) -> bool:
	match station:
		CraftingRegistry.Station.NONE:
			return true

		CraftingRegistry.Station.WORKBENCH:
			return nearby_workbench

		CraftingRegistry.Station.FURNACE:
			return nearby_furnace

	return false


func update_nearby_crafting_stations() -> void:
	if world == null:
		return

	var found_workbench := false
	var found_furnace := false

	var player_block := Vector3i(
		floor(global_position.x),
		floor(global_position.y),
		floor(global_position.z)
	)

	for x in range(
		-crafting_station_radius,
		crafting_station_radius + 1
	):
		for y in range(
			-crafting_station_radius,
			crafting_station_radius + 1
		):
			for z in range(
				-crafting_station_radius,
				crafting_station_radius + 1
			):
				var block_position := (
					player_block
					+ Vector3i(x, y, z)
				)

				var block := world.get_block_at_world_position(
					block_position
				)

				if block == BlockRegistry.Block.WORKBENCH:
					found_workbench = true
				
				if block == BlockRegistry.Block.FURNACE:
					found_furnace = true

				

			if found_workbench and found_furnace:
				break

		if found_workbench and found_furnace:
				break

	var changed := false

	if nearby_workbench != found_workbench:
		nearby_workbench = found_workbench
		changed = true

	if nearby_furnace != found_furnace:
		nearby_furnace = found_furnace
		changed = true

	if changed:
		crafting_stations_changed.emit()


func process_mining(delta: float) -> void:
	var target := get_target_block()

	if target.is_empty():
		reset_mining()
		return

	var block_position: Vector3i = target["position"]
	var block: int = target["block"]

	if block == BlockRegistry.Block.AIR:
		reset_mining()
		return

	if block == BlockRegistry.Block.BEDROCK:
		reset_mining()
		return

	if not can_mine_block(block):
		reset_mining()
		return

	if not is_mining or mining_block_position != block_position:
		mining_block_position = block_position
		mining_progress = 0.0
		is_mining = true

	var hardness := BlockRegistry.get_hardness(block)
	var mining_speed := get_mining_speed_for_block(block)

	mining_progress += (mining_speed / hardness) * delta
	update_mining_cracks(block_position)

	if mining_progress >= 1.0:
		break_target_block(target)
		reset_mining()


func get_mining_speed_for_block(block: int) -> float:
	if hotbar == null:
		return 1.0

	var selected_item: int = hotbar.get_selected_item()

	var tool_type := ItemRegistry.get_tool_type(
		selected_item
	)

	var preferred_tool := BlockRegistry.get_preferred_tool(
		block
	)

	if preferred_tool == ItemRegistry.ToolType.NONE:
		return 1.0

	if tool_type != preferred_tool:
		return 0.35

	return ItemRegistry.get_mining_speed(
		selected_item
	)


func get_target_block() -> Dictionary:
	var from := camera.global_position
	var to := (
		from
		+ -camera.global_transform.basis.z
		* interaction_distance
	)

	var query := PhysicsRayQueryParameters3D.create(
		from,
		to
	)

	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = 1

	var result := (
		get_world_3d()
		.direct_space_state
		.intersect_ray(query)
	)

	if result.is_empty():
		return {}

	var hit_position: Vector3 = result.position
	var hit_normal: Vector3 = result.normal

	var block_position := Vector3i(
		floor(hit_position.x - hit_normal.x * 0.01),
		floor(hit_position.y - hit_normal.y * 0.01),
		floor(hit_position.z - hit_normal.z * 0.01)
	)

	var chunk := get_chunk_from_hit(
		result.collider
	)

	if chunk == null:
		return {}

	var local_position := (
		block_position
		- Vector3i(chunk.global_position)
	)

	return {
		"position": block_position,
		"local_position": local_position,
		"chunk": chunk,
		"block": chunk.get_block_local(local_position)
	}


func break_target_block(target: Dictionary) -> void:
	var chunk: Chunk = target["chunk"]
	var block_position: Vector3i = target["position"]
	var local_position: Vector3i = target["local_position"]

	var broken_block := chunk.remove_block(
		local_position
	)

	if broken_block == BlockRegistry.Block.AIR:
		return

	world.rebuild_chunk_and_neighbors(
		chunk,
		local_position
	)

	var dropped_item := ItemRegistry.get_drop(
		broken_block
	)

	if dropped_item == ItemRegistry.Item.NONE:
		return

	var drop_offset := Vector3(
		randf_range(-0.18, 0.18),
		0.5,
		randf_range(-0.18, 0.18)
	)

	world.spawn_item(dropped_item, Vector3(block_position) + Vector3(0.5, 0.0, 0.5) + drop_offset)


func reset_mining() -> void:
	mining_progress = 0.0
	is_mining = false
	mining_cracks.visible = false


func update_mining_cracks(block_position: Vector3i) -> void:
	if cracks_texture == null:
		mining_cracks.visible = false
		return

	var stage := clampi(
		floori(mining_progress * 9.0),
		0,
		8
	)

	var material := StandardMaterial3D.new()
	material.albedo_texture = cracks_texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

	var stage_width := 1.0 / 9.0

	material.uv1_scale = Vector3(
		stage_width,
		1.0,
		1.0
	)

	material.uv1_offset = Vector3(
		stage * stage_width,
		0.0,
		0.0
	)

	mining_cracks.material_override = material

	mining_cracks.global_position = (
		Vector3(block_position)
		+ Vector3(0.5, 0.5, 0.5)
	)

	mining_cracks.visible = true


func build_mining_cracks_mesh() -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var half := 0.5075

	add_crack_face(
		vertices, normals, uvs, indices,
		Vector3(-half, -half, half),
		Vector3(half, -half, half),
		Vector3(half, half, half),
		Vector3(-half, half, half),
		Vector3(0, 0, 1)
	)

	add_crack_face(
		vertices, normals, uvs, indices,
		Vector3(half, -half, -half),
		Vector3(-half, -half, -half),
		Vector3(-half, half, -half),
		Vector3(half, half, -half),
		Vector3(0, 0, -1)
	)

	add_crack_face(
		vertices, normals, uvs, indices,
		Vector3(-half, -half, -half),
		Vector3(-half, -half, half),
		Vector3(-half, half, half),
		Vector3(-half, half, -half),
		Vector3(-1, 0, 0)
	)

	add_crack_face(
		vertices, normals, uvs, indices,
		Vector3(half, -half, half),
		Vector3(half, -half, -half),
		Vector3(half, half, -half),
		Vector3(half, half, half),
		Vector3(1, 0, 0)
	)

	add_crack_face(
		vertices, normals, uvs, indices,
		Vector3(-half, half, half),
		Vector3(half, half, half),
		Vector3(half, half, -half),
		Vector3(-half, half, -half),
		Vector3(0, 1, 0)
	)

	add_crack_face(
		vertices, normals, uvs, indices,
		Vector3(-half, -half, -half),
		Vector3(half, -half, -half),
		Vector3(half, -half, half),
		Vector3(-half, -half, half),
		Vector3(0, -1, 0)
	)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)

	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(
		Mesh.PRIMITIVE_TRIANGLES,
		arrays
	)

	mining_cracks.mesh = mesh


func add_crack_face(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	indices: PackedInt32Array,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	d: Vector3,
	normal: Vector3
) -> void:
	var start := vertices.size()

	vertices.append_array([
		a, b, c, d
	])

	normals.append_array([
		normal, normal, normal, normal
	])

	uvs.append_array([
		Vector2(0, 1),
		Vector2(1, 1),
		Vector2(1, 0),
		Vector2(0, 0)
	])

	indices.append_array([
		start,
		start + 1,
		start + 2,
		start,
		start + 2,
		start + 3
	])


func can_mine_block(block: int) -> bool:
	var required_tier := BlockRegistry.get_required_mining_tier(block)

	if required_tier <= 0:
		return true

	if hotbar == null:
		return false

	var selected_item: int = hotbar.get_selected_item()
	var tool_type := ItemRegistry.get_tool_type(selected_item)

	if tool_type != ItemRegistry.ToolType.PICKAXE:
		return false

	var tool_tier := ItemRegistry.get_mining_tier(selected_item)

	return tool_tier >= required_tier
