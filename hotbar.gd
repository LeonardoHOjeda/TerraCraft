extends HBoxContainer

const SLOT_SIZE := 48
const ICON_SIZE := 32

@export var atlas: Texture2D
@export var player: Player

var selected_slot: int = 0

var slots: Array[PanelContainer] = []
var icons: Array[TextureRect] = []
var amount_labels: Array[Label] = []


func _ready() -> void:
	add_theme_constant_override("separation", 4)

	create_slots()

	if player:
		player.inventory.slot_changed.connect(_on_inventory_slot_changed)

	update_all_slots()
	update_selection()


func create_slots() -> void:
	for child in get_children():
		child.queue_free()

	slots.clear()
	icons.clear()
	amount_labels.clear()

	for i in Inventory.HOTBAR_SLOT_COUNT:
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)

		var content := Control.new()
		content.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)

		var icon := TextureRect.new()
		icon.position = Vector2(8, 8)
		icon.size = Vector2(ICON_SIZE, ICON_SIZE)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

		var amount_label := Label.new()
		amount_label.position = Vector2(27, 27)
		amount_label.size = Vector2(17, 17)
		amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		amount_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM

		content.add_child(icon)
		content.add_child(amount_label)

		slot.add_child(content)
		add_child(slot)

		slots.append(slot)
		icons.append(icon)
		amount_labels.append(amount_label)


func set_selected_slot(index: int) -> void:
	selected_slot = wrapi(
		index,
		0,
		Inventory.HOTBAR_SLOT_COUNT
	)

	update_selection()


func get_selected_item() -> int:
	if player == null:
		return ItemRegistry.Item.NONE

	var inventory_index := (
		Inventory.HOTBAR_START
		+ selected_slot
	)

	return player.inventory.get_item(inventory_index)


func get_selected_block() -> int:
	return ItemRegistry.get_placeable_block(
		get_selected_item()
	)


func get_selected_amount() -> int:
	if player == null:
		return 0

	var inventory_index := (
		Inventory.HOTBAR_START
		+ selected_slot
	)

	return player.inventory.get_amount(
		inventory_index
	)


func remove_selected_item(amount: int = 1) -> bool:
	if player == null:
		return false

	var inventory_index := (
		Inventory.HOTBAR_START
		+ selected_slot
	)

	return player.inventory.remove_item(
		inventory_index,
		amount
	)


func update_all_slots() -> void:
	for i in Inventory.HOTBAR_SLOT_COUNT:
		update_slot(i)


func update_slot(hotbar_index: int) -> void:
	if player == null:
		return

	var inventory_index := (
		Inventory.HOTBAR_START
		+ hotbar_index
	)

	var item_id := player.inventory.get_item(
		inventory_index
	)

	var amount := player.inventory.get_amount(
		inventory_index
	)

	if item_id == ItemRegistry.Item.NONE:
		icons[hotbar_index].texture = null
		amount_labels[hotbar_index].text = ""
		return

	var texture_position := (
		ItemRegistry.get_texture_position(item_id)
	)

	var atlas_texture := AtlasTexture.new()
	atlas_texture.atlas = atlas
	atlas_texture.region = Rect2(
		texture_position.x * 16,
		texture_position.y * 16,
		16,
		16
	)

	icons[hotbar_index].texture = atlas_texture

	if amount > 1:
		amount_labels[hotbar_index].text = str(amount)
	else:
		amount_labels[hotbar_index].text = ""


func update_selection() -> void:
	for i in slots.size():
		var style := StyleBoxFlat.new()

		style.bg_color = Color(
			0.12,
			0.12,
			0.12,
			0.85
		)

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
			style.border_color = Color(
				0.4,
				0.4,
				0.4
			)

		slots[i].add_theme_stylebox_override(
			"panel",
			style
		)


func _on_inventory_slot_changed(
	inventory_index: int
) -> void:
	if inventory_index < Inventory.HOTBAR_START:
		return

	var hotbar_index := (
		inventory_index
		- Inventory.HOTBAR_START
	)

	if hotbar_index >= Inventory.HOTBAR_SLOT_COUNT:
		return

	update_slot(hotbar_index)