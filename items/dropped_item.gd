class_name DroppedItem
extends CharacterBody3D

@export var item_id: int = ItemRegistry.Item.NONE
@export var amount: int = 1
@export var gravity: float = 12.0
@export var rotation_speed: float = 1.5
@export var atlas: Texture2D
@export var bob_height: float = 0.08
@export var bob_speed: float = 2.5

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var pickup_area: Area3D = $PickupArea

var base_mesh_y: float = 0.0
var bob_time: float = 0.0

func _ready() -> void:
	setup_texture()
	base_mesh_y = mesh_instance.position.y
	pickup_area.body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	mesh_instance.rotation.y += rotation_speed * delta

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	bob_time += delta

	mesh_instance.position.y = (
		base_mesh_y
		+ sin(bob_time * bob_speed) * bob_height
	)

	move_and_slide()


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		body.collect_item(item_id, amount)
		queue_free()


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

	add_face(
		vertices, normals, uvs, indices,
		Vector3(-half, -half, half),
		Vector3(half, -half, half),
		Vector3(half, half, half),
		Vector3(-half, half, half),
		Vector3(0, 0, 1),
		u0, v0, u1, v1
	)

	add_face(
		vertices, normals, uvs, indices,
		Vector3(half, -half, -half),
		Vector3(-half, -half, -half),
		Vector3(-half, half, -half),
		Vector3(half, half, -half),
		Vector3(0, 0, -1),
		u0, v0, u1, v1
	)

	add_face(
		vertices, normals, uvs, indices,
		Vector3(-half, -half, -half),
		Vector3(-half, -half, half),
		Vector3(-half, half, half),
		Vector3(-half, half, -half),
		Vector3(-1, 0, 0),
		u0, v0, u1, v1
	)

	add_face(
		vertices, normals, uvs, indices,
		Vector3(half, -half, half),
		Vector3(half, -half, -half),
		Vector3(half, half, -half),
		Vector3(half, half, half),
		Vector3(1, 0, 0),
		u0, v0, u1, v1
	)

	add_face(
		vertices, normals, uvs, indices,
		Vector3(-half, half, half),
		Vector3(half, half, half),
		Vector3(half, half, -half),
		Vector3(-half, half, -half),
		Vector3(0, 1, 0),
		u0, v0, u1, v1
	)

	add_face(
		vertices, normals, uvs, indices,
		Vector3(-half, -half, -half),
		Vector3(half, -half, -half),
		Vector3(half, -half, half),
		Vector3(-half, -half, half),
		Vector3(0, -1, 0),
		u0, v0, u1, v1
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

	var material := StandardMaterial3D.new()
	material.albedo_texture = atlas
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

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