extends PanelContainer

const SLOT_SIZE := 48
const ICON_SIZE := 32

@export var atlas: Texture2D
@export var player: Player

var inventory: Inventory
var interaction_state: PlayerInteractionState
var inventory_interaction := InventoryInteractionController.new()

@onready var inventory_grid: GridContainer = $HBoxContainer/InventorySection/InventoryGrid
@onready var hotbar_grid: GridContainer = $HBoxContainer/InventorySection/HotbarGrid
@onready var crafting_panel: CraftingPanel = $HBoxContainer/CraftingSection/CraftingScroll/CraftingGrid
@onready var crafting_empty_label: Label = $HBoxContainer/CraftingSection/CraftingEmptyLabel

@onready var cursor_icon: TextureRect = $CursorItem
@onready var cursor_label: Label = $CursorItem/Amount


var slot_icons: Array[TextureRect] = []
var amount_labels: Array[Label] = []

var slot_buttons: Array[Button] = []

func _ready() -> void:
	visible = false
	apply_inventory_styles()

	cursor_icon.top_level = true
	cursor_icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	cursor_icon.size = Vector2(ICON_SIZE, ICON_SIZE)
	cursor_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cursor_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cursor_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	cursor_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if player:
		inventory = player.inventory
		interaction_state = player.interaction_state
		inventory_interaction.setup(inventory)

	inventory_grid.add_theme_constant_override("h_separation", 4)
	inventory_grid.add_theme_constant_override("v_separation", 4)

	hotbar_grid.add_theme_constant_override("h_separation", 4)

	create_slots()
	crafting_panel.setup(inventory, player.station_detector, atlas, crafting_empty_label)

	if player:
		inventory.slot_changed.connect(update_slot)

	update_all_slots()


func apply_inventory_styles() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.055, 0.065, 0.085, 0.97)
	panel_style.border_color = Color(0.30, 0.36, 0.46, 0.95)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(10)
	panel_style.content_margin_left = 18
	panel_style.content_margin_top = 16
	panel_style.content_margin_right = 18
	panel_style.content_margin_bottom = 16
	add_theme_stylebox_override("panel", panel_style)

	$HBoxContainer.add_theme_constant_override("separation", 18)
	$HBoxContainer/InventorySection.add_theme_constant_override("separation", 7)
	$HBoxContainer/CraftingSection.add_theme_constant_override("separation", 7)

	var scroll_style := StyleBoxFlat.new()
	scroll_style.bg_color = Color(0.035, 0.042, 0.055, 0.8)
	scroll_style.border_color = Color(0.20, 0.25, 0.33, 0.9)
	scroll_style.set_border_width_all(1)
	scroll_style.set_corner_radius_all(6)
	$HBoxContainer/CraftingSection/CraftingScroll.add_theme_stylebox_override("panel", scroll_style)


func _process(_delta: float) -> void:
	if not visible:
		return

	cursor_icon.global_position = get_viewport().get_mouse_position() + Vector2(8, 8)

	update_cursor_visual()


func create_slots() -> void:
	for i in Inventory.TOTAL_SLOT_COUNT:
		var slot := create_slot(i)

		if i < Inventory.HOTBAR_START:
			inventory_grid.add_child(slot)
		else:
			hotbar_grid.add_child(slot)


func create_slot(index: int) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.12, 0.16, 0.96)

	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2

	style.border_color = Color(0.27, 0.32, 0.41)
	style.set_corner_radius_all(5)

	slot.add_theme_stylebox_override("panel", style)

	var button := Button.new()
	button.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	button.flat = true
	button.mouse_filter = Control.MOUSE_FILTER_STOP

	button.mouse_entered.connect(
	func() -> void:
		update_slot_tooltip(index)
	)

	button.mouse_entered.connect(
		func() -> void:
			set_slot_hover(slot, true)
	)

	button.mouse_exited.connect(
		func() -> void:
			set_slot_hover(slot, false)
	)

	var icon := TextureRect.new()
	icon.position = Vector2(8, 8)
	icon.size = Vector2(ICON_SIZE, ICON_SIZE)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var amount_label := Label.new()
	amount_label.position = Vector2(27, 27)
	amount_label.size = Vector2(17, 17)
	amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	amount_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	button.add_child(icon)
	button.add_child(amount_label)

	button.gui_input.connect(
		func(event: InputEvent) -> void:
			_on_slot_gui_input(index, event)
	)

	slot.add_child(button)

	slot_buttons.append(button)
	slot_icons.append(icon)
	amount_labels.append(amount_label)

	return slot


func update_all_slots() -> void:
	for i in Inventory.TOTAL_SLOT_COUNT:
		update_slot(i)


func update_slot(index: int) -> void:
	if player == null:
		return

	var item_id := inventory.get_item(index)
	var amount := inventory.get_amount(index)

	if item_id == ItemRegistry.Item.NONE:
		slot_icons[index].texture = null
		amount_labels[index].text = ""
		update_slot_tooltip(index)
		return

	slot_icons[index].texture = ItemIconFactory.get_item_icon(atlas, item_id)
	amount_labels[index].text = str(amount) if amount > 1 else ""
	update_slot_tooltip(index)

func _unhandled_input(event: InputEvent) -> void:
	if (
		visible
		and event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_RIGHT
		and not get_global_rect().has_point(event.position)
		and inventory_interaction.cursor_item != ItemRegistry.Item.NONE
	):
		player.try_drop_item(
			inventory_interaction.cursor_item,
			inventory_interaction.remove_one_from_cursor
		)
		update_cursor_visual()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("inventory"):
		toggle_inventory()

	if event.is_action_pressed("ui_cancel") and visible:
		toggle_inventory()
		get_viewport().set_input_as_handled()


func toggle_inventory() -> void:
	if visible:
		var cursor_returned := inventory_interaction.return_cursor_to_inventory()
		update_cursor_visual()
		if not cursor_returned:
			return

	visible = !visible

	if interaction_state:
		interaction_state.set_inventory_open(visible)

	if visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_slot_gui_input(index: int, event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return

	if not event.pressed:
		return

	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.double_click:
			inventory_interaction.handle_double_click(index)
		elif event.shift_pressed:
			inventory_interaction.handle_shift_click(index)
		else:
			inventory_interaction.handle_left_click(index)

	elif event.button_index == MOUSE_BUTTON_RIGHT:
		inventory_interaction.handle_right_click(index)

	elif (
		event.button_index == MOUSE_BUTTON_WHEEL_UP
		or event.button_index == MOUSE_BUTTON_WHEEL_DOWN
	):
		if inventory_interaction.handle_wheel_transfer(index, event.button_index):
			slot_buttons[index].accept_event()

func update_cursor_visual() -> void:
	if inventory_interaction.cursor_item == ItemRegistry.Item.NONE:
		cursor_icon.texture = null
		cursor_label.text = ""
		return

	cursor_icon.texture = ItemIconFactory.get_item_icon(
		atlas, inventory_interaction.cursor_item
	)

	cursor_label.text = (
		str(inventory_interaction.cursor_amount)
		if inventory_interaction.cursor_amount > 1
		else ""
	)

func update_slot_tooltip(index: int) -> void:
	if player == null:
		return

	var item_id := inventory.get_item(index)

	if item_id == ItemRegistry.Item.NONE:
		slot_buttons[index].tooltip_text = ""
		return

	var amount := inventory.get_amount(index)
	var item_name := ItemRegistry.get_item_name(item_id)

	slot_buttons[index].tooltip_text = (
		item_name + "\nCantidad: " + str(amount)
	)

func set_slot_hover(slot: PanelContainer, hovered: bool) -> void:
	var style := StyleBoxFlat.new()

	style.bg_color = (
		Color(0.18, 0.22, 0.29, 1.0)
		if hovered
		else Color(0.10, 0.12, 0.16, 0.96)
	)

	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2

	style.border_color = (
		Color(0.72, 0.82, 1.0)
		if hovered
		else Color(0.27, 0.32, 0.41)
	)
	style.set_corner_radius_all(5)

	slot.add_theme_stylebox_override("panel", style)
