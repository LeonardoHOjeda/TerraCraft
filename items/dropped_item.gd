class_name DroppedItem
extends CharacterBody3D

@export var item_id: int = ItemRegistry.Item.NONE
@export var amount: int = 1
@export var gravity: float = 12.0
@export var rotation_speed: float = 1.5
@export var atlas: Texture2D
@export var bob_height: float = 0.08
@export var bob_speed: float = 2.5
@export var pickup_delay: float = 0.5
@export var merge_radius: float = 1.25
@export var merge_interval: float = 0.4
@export var lifetime: float = 300.0
@export var spawn_horizontal_speed: float = 1.5
@export var spawn_vertical_speed: float = 2.5

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var pickup_area: Area3D = $PickupArea

var base_mesh_y: float = 0.0
var bob_time: float = 0.0

var pickup_enabled: bool = false
var pickup_timer: float = 0.0

var merge_timer: float = 0.0
var lifetime_timer: float = 0.0

func _ready() -> void:
	setup_texture()
	base_mesh_y = mesh_instance.position.y
	pickup_area.body_entered.connect(_on_body_entered)
	add_to_group("dropped_items")
	apply_spawn_impulse()


func _physics_process(delta: float) -> void:
	lifetime_timer += delta

	if lifetime_timer >= lifetime:
		queue_free()
		return
	if not pickup_enabled:
		pickup_timer += delta

		if pickup_timer >= pickup_delay:
			pickup_enabled = true
			try_pickup_existing_body()

	merge_timer += delta

	if merge_timer >= merge_interval:
		merge_timer = 0.0
		try_merge_nearby()

	mesh_instance.rotation.y += rotation_speed * delta

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
		velocity.x = move_toward(velocity.x, 0.0, 6.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 6.0 * delta)

	bob_time += delta

	mesh_instance.position.y = (
		base_mesh_y
		+ sin(bob_time * bob_speed) * bob_height
	)

	move_and_slide()


func _on_body_entered(body: Node3D) -> void:
	if not pickup_enabled:
		return
		
	if body is Player:
		var remaining: int = body.collect_item(item_id, amount)

		if remaining <= 0:
			queue_free()
		else:
			amount = remaining


func setup_texture() -> void:
	if atlas == null:
		return

	var tile := ItemRegistry.get_texture_position(item_id)

	var u0 := float(tile.x) / 16.0
	var v0 := float(tile.y) / 16.0
	var u1 := float(tile.x + 1) / 16.0
	var v1 := float(tile.y + 1) / 16.0

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var half := 0.15
	var is_placeable := ItemRegistry.get_placeable_block(item_id) != BlockRegistry.Block.AIR

	if is_placeable:
		add_face(vertices, normals, uvs, indices, Vector3(-half, -half, half), Vector3(half, -half, half), Vector3(half, half, half), Vector3(-half, half, half), Vector3(0, 0, 1), u0, v0, u1, v1)
		add_face(vertices, normals, uvs, indices, Vector3(half, -half, -half), Vector3(-half, -half, -half), Vector3(-half, half, -half), Vector3(half, half, -half), Vector3(0, 0, -1), u0, v0, u1, v1)
		add_face(vertices, normals, uvs, indices, Vector3(-half, -half, -half), Vector3(-half, -half, half), Vector3(-half, half, half), Vector3(-half, half, -half), Vector3(-1, 0, 0), u0, v0, u1, v1)
		add_face(vertices, normals, uvs, indices, Vector3(half, -half, half), Vector3(half, -half, -half), Vector3(half, half, -half), Vector3(half, half, half), Vector3(1, 0, 0), u0, v0, u1, v1)
		add_face(vertices, normals, uvs, indices, Vector3(-half, half, half), Vector3(half, half, half), Vector3(half, half, -half), Vector3(-half, half, -half), Vector3(0, 1, 0), u0, v0, u1, v1)
		add_face(vertices, normals, uvs, indices, Vector3(-half, -half, -half), Vector3(half, -half, -half), Vector3(half, -half, half), Vector3(-half, -half, half), Vector3(0, -1, 0), u0, v0, u1, v1)
	else:
		add_face(vertices, normals, uvs, indices, Vector3(-half, -half, 0), Vector3(half, -half, 0), Vector3(half, half, 0), Vector3(-half, half, 0), Vector3(0, 0, 1), u0, v0, u1, v1)

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

	var material := StandardMaterial3D.new()
	material.albedo_texture = atlas
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if not is_placeable:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	mesh.surface_set_material(0, material)

	mesh_instance.mesh = mesh

func add_face(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	indices: PackedInt32Array,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	d: Vector3,
	normal: Vector3,
	u0: float,
	v0: float,
	u1: float,
	v1: float
) -> void:
	var start := vertices.size()

	vertices.append_array([
		a, b, c, d
	])

	normals.append_array([
		normal, normal, normal, normal
	])

	uvs.append_array([
		Vector2(u0, v1),
		Vector2(u1, v1),
		Vector2(u1, v0),
		Vector2(u0, v0)
	])

	indices.append_array([
		start,
		start + 1,
		start + 2,
		start,
		start + 2,
		start + 3
	])

func try_pickup_existing_body() -> void:
	for body in pickup_area.get_overlapping_bodies():
		if body is Player:
			var remaining = body.collect_item(item_id, amount)

			if remaining <= 0:
				queue_free()
			else:
				amount = remaining

			return

func try_merge_nearby() -> void:
	if amount >= ItemRegistry.get_max_stack(item_id):
		return

	for node in get_tree().get_nodes_in_group("dropped_items"):
		if node == self:
			continue

		if not node is DroppedItem:
			continue

		var other := node as DroppedItem

		if other.item_id != item_id:
			continue

		if other.get_instance_id() < get_instance_id():
			continue

		if global_position.distance_squared_to(other.global_position) > merge_radius * merge_radius:
			continue

		var max_stack := ItemRegistry.get_max_stack(item_id)
		var space := max_stack - amount

		if space <= 0:
			return

		var transferred: int = min(space, other.amount)

		amount += transferred
		other.amount -= transferred

		lifetime_timer = min(lifetime_timer, other.lifetime_timer)

		if other.amount <= 0:
			other.queue_free()
			continue

		if amount >= max_stack:
			return

func apply_spawn_impulse() -> void:
	var angle := randf() * TAU

	velocity.x = cos(angle) * spawn_horizontal_speed
	velocity.z = sin(angle) * spawn_horizontal_speed
	velocity.y = spawn_vertical_speed
