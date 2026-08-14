extends HBoxContainer

const SLOT_SIZE := 48
const ICON_SIZE := 32

@export var atlas: Texture2D

var blocks := [
	BlockRegistry.Block.DIRT,
	BlockRegistry.Block.STONE,
	BlockRegistry.Block.WOOD,
	BlockRegistry.Block.LEAVES,
	BlockRegistry.Block.SAND,
	BlockRegistry.Block.COAL,
	BlockRegistry.Block.GRASS,
	BlockRegistry.Block.DIRT,
	BlockRegistry.Block.DIRT,
]

var selected_slot := 0
var slots: Array[PanelContainer] = []


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	create_slots()
	update_selection()


func create_slots() -> void:
	for child in get_children():
		child.queue_free()

	slots.clear()

	for i in blocks.size():
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)

		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

		var atlas_texture := AtlasTexture.new()
		atlas_texture.atlas = atlas
		atlas_texture.region = get_texture_region(blocks[i])

		icon.texture = atlas_texture

		slot.add_child(icon)
		add_child(slot)

		slots.append(slot)


func set_selected_slot(index: int) -> void:
	selected_slot = wrapi(index, 0, blocks.size())
	update_selection()


func update_selection() -> void:
	for i in slots.size():
		var style := StyleBoxFlat.new()

		style.bg_color = Color(0.12, 0.12, 0.12, 0.85)

		if i == selected_slot:
			style.border_width_left = 4
			style.border_width_top = 4
			style.border_width_right = 4
			style.border_width_bottom = 4
			style.border_color = Color.WHITE
		else:
			style.border_width_left = 2
			style.border_width_top = 2
			style.border_width_right = 2
			style.border_width_bottom = 2
			style.border_color = Color(0.4, 0.4, 0.4)

		slots[i].add_theme_stylebox_override("panel", style)


func get_texture_region(block: int) -> Rect2:
	var texture_position := Vector2i.ZERO

	match block:
		BlockRegistry.Block.DIRT:
			texture_position = BlockRegistry.TEXTURE_DIRT

		BlockRegistry.Block.STONE:
			texture_position = BlockRegistry.TEXTURE_STONE

		BlockRegistry.Block.WOOD:
			texture_position = BlockRegistry.TEXTURE_WOOD_SIDE

		BlockRegistry.Block.LEAVES:
			texture_position = BlockRegistry.TEXTURE_LEAVES

		BlockRegistry.Block.SAND:
			texture_position = BlockRegistry.TEXTURE_SAND

		BlockRegistry.Block.COAL:
			texture_position = BlockRegistry.TEXTURE_COAL

		BlockRegistry.Block.GRASS:
			texture_position = BlockRegistry.TEXTURE_GRASS_TOP

		BlockRegistry.Block.BEDROCK:
			texture_position = BlockRegistry.TEXTURE_BEDROCK

	return Rect2(
		texture_position.x * 16,
		texture_position.y * 16,
		16,
		16
	)

func get_selected_block() -> int:
	return blocks[selected_slot]