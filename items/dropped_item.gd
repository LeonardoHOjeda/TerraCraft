class_name DroppedItem
extends CharacterBody3D

@export var item_id: int = ItemRegistry.Item.NONE
@export var amount: int = 1
@export var gravity: float = 12.0
@export var rotation_speed: float = 1.5
@export var atlas: Texture2D

@onready var sprite: Sprite3D = $Sprite3D
@onready var pickup_area: Area3D = $PickupArea


func _ready() -> void:
	setup_texture()
	pickup_area.body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	rotation.y += rotation_speed * delta

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	move_and_slide()


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		body.collect_item(item_id, amount)
		queue_free()


func setup_texture() -> void:
	if atlas == null:
		return

	var atlas_position := ItemRegistry.get_texture_position(item_id)

	var atlas_texture := AtlasTexture.new()
	atlas_texture.atlas = atlas
	atlas_texture.region = Rect2(
		atlas_position.x * 16,
		atlas_position.y * 16,
		16,
		16
	)

	sprite.texture = atlas_texture