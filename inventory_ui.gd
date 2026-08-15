extends PanelContainer

const SLOT_SIZE := 48
const ICON_SIZE := 32

@export var atlas: Texture2D
@export var player: Player

@onready var inventory_grid: GridContainer = $HBoxContainer/InventorySection/InventoryGrid
@onready var hotbar_grid: GridContainer = $HBoxContainer/InventorySection/HotbarGrid
@onready var crafting_grid: GridContainer = $HBoxContainer/CraftingSection/CraftingScroll/CraftingGrid

@onready var cursor_icon: TextureRect = $CursorItem
@onready var cursor_label: Label = $CursorItem/Amount


var slot_icons: Array[TextureRect] = []
var amount_labels: Array[Label] = []

var cursor_item: int = ItemRegistry.Item.NONE
var cursor_amount: int = 0

var slot_buttons: Array[Button] = []

var crafting_buttons: Array[Button] = []


func _ready() -> void:
	visible = false

	inventory_grid.add_theme_constant_override("h_separation", 4)
	inventory_grid.add_theme_constant_override("v_separation", 4)

	hotbar_grid.add_theme_constant_override("h_separation", 4)

	create_slots()
	create_crafting_buttons()
	crafting_grid.add_theme_constant_override("h_separation", 4)
	crafting_grid.add_theme_constant_override("v_separation", 4)

	if player:
		player.inventory.slot_changed.connect(update_slot)
		player.inventory.slot_changed.connect(_on_inventory_changed)
		player.crafting_stations_changed.connect(update_crafting_buttons)

	update_all_slots()


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
	style.bg_color = Color(0.12, 0.12, 0.12, 0.9)

	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2

	style.border_color = Color(0.4, 0.4, 0.4)

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

	var item_id := player.inventory.get_item(index)
	var amount := player.inventory.get_amount(index)

	if item_id == ItemRegistry.Item.NONE:
		slot_icons[index].texture = null
		amount_labels[index].text = ""
		update_slot_tooltip(index)
		return

	var texture_position := ItemRegistry.get_texture_position(item_id)

	var atlas_texture := AtlasTexture.new()
	atlas_texture.atlas = atlas
	atlas_texture.region = Rect2(
		texture_position.x * 16,
		texture_position.y * 16,
		16,
		16
	)

	slot_icons[index].texture = atlas_texture
	amount_labels[index].text = str(amount) if amount > 1 else ""
	update_slot_tooltip(index)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		toggle_inventory()

	if event.is_action_pressed("ui_cancel") and visible:
		toggle_inventory()
		get_viewport().set_input_as_handled()


func toggle_inventory() -> void:
	visible = !visible

	if player:
		player.inventory_open = visible

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
			handle_double_click(index)
		elif event.shift_pressed:
			handle_shift_click(index)
		else:
			handle_left_click(index)

	elif event.button_index == MOUSE_BUTTON_RIGHT:
		handle_right_click(index)

func handle_left_click(index: int) -> void:
	var inventory := player.inventory

	var slot_item := inventory.get_item(index)
	var slot_amount := inventory.get_amount(index)

	# Cursor vacío: tomar stack completo.
	if cursor_item == ItemRegistry.Item.NONE:
		if slot_item == ItemRegistry.Item.NONE:
			return

		cursor_item = slot_item
		cursor_amount = slot_amount

		inventory.set_slot(
			index,
			ItemRegistry.Item.NONE,
			0
		)

		return

	# Slot vacío: soltar stack completo.
	if slot_item == ItemRegistry.Item.NONE:
		inventory.set_slot(
			index,
			cursor_item,
			cursor_amount
		)

		clear_cursor()
		return

	# Mismo item: intentar combinar.
	if slot_item == cursor_item:
		cursor_amount = inventory.add_to_slot(
			index,
			cursor_item,
			cursor_amount
		)

		if cursor_amount <= 0:
			clear_cursor()

		return

	# Items diferentes: intercambiar.
	inventory.set_slot(
		index,
		cursor_item,
		cursor_amount
	)

	cursor_item = slot_item
	cursor_amount = slot_amount

func handle_right_click(index: int) -> void:
	var inventory := player.inventory

	var slot_item := inventory.get_item(index)
	var slot_amount := inventory.get_amount(index)

	# Cursor vacío: tomar la mitad.
	if cursor_item == ItemRegistry.Item.NONE:
		if slot_item == ItemRegistry.Item.NONE:
			return

		var take_amount := ceili(slot_amount / 2.0)

		cursor_item = slot_item
		cursor_amount = take_amount

		inventory.remove_item(
			index,
			take_amount
		)

		return

	# Cursor tiene algo y slot está vacío:
	# colocar solo uno.
	if slot_item == ItemRegistry.Item.NONE:
		inventory.set_slot(
			index,
			cursor_item,
			1
		)

		cursor_amount -= 1

		if cursor_amount <= 0:
			clear_cursor()

		return

	# Mismo item: colocar uno.
	if slot_item == cursor_item:
		var remaining := inventory.add_to_slot(
			index,
			cursor_item,
			1
		)

		if remaining == 0:
			cursor_amount -= 1

			if cursor_amount <= 0:
				clear_cursor()

func update_cursor_visual() -> void:
	if cursor_item == ItemRegistry.Item.NONE:
		cursor_icon.texture = null
		cursor_label.text = ""
		return

	var texture_position := ItemRegistry.get_texture_position(
		cursor_item
	)

	var atlas_texture := AtlasTexture.new()
	atlas_texture.atlas = atlas
	atlas_texture.region = Rect2(
		texture_position.x * 16,
		texture_position.y * 16,
		16,
		16
	)

	cursor_icon.texture = atlas_texture

	cursor_label.text = (
		str(cursor_amount)
		if cursor_amount > 1
		else ""
	)

func clear_cursor() -> void:
	cursor_item = ItemRegistry.Item.NONE
	cursor_amount = 0
	update_cursor_visual()

func update_slot_tooltip(index: int) -> void:
	if player == null:
		return

	var item_id := player.inventory.get_item(index)

	if item_id == ItemRegistry.Item.NONE:
		slot_buttons[index].tooltip_text = ""
		return

	var amount := player.inventory.get_amount(index)
	var item_name := ItemRegistry.get_item_name(item_id)

	slot_buttons[index].tooltip_text = (
		item_name + "\nCantidad: " + str(amount)
	)

func set_slot_hover(slot: PanelContainer, hovered: bool) -> void:
	var style := StyleBoxFlat.new()

	style.bg_color = (
		Color(0.20, 0.20, 0.20, 0.95)
		if hovered
		else Color(0.12, 0.12, 0.12, 0.9)
	)

	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2

	style.border_color = (
		Color(0.75, 0.75, 0.75)
		if hovered
		else Color(0.4, 0.4, 0.4)
	)

	slot.add_theme_stylebox_override("panel", style)

func handle_shift_click(index: int) -> void:
	if player == null:
		return

	if cursor_item != ItemRegistry.Item.NONE:
		return

	var inventory := player.inventory

	if inventory.get_item(index) == ItemRegistry.Item.NONE:
		return

	# Mochila → Hotbar
	if index < Inventory.HOTBAR_START:
		inventory.move_stack_to_range(
			index,
			Inventory.HOTBAR_START,
			Inventory.TOTAL_SLOT_COUNT
		)

	# Hotbar → Mochila
	else:
		inventory.move_stack_to_range(
			index,
			0,
			Inventory.HOTBAR_START
		)


func handle_double_click(index: int) -> void:
	if player == null:
		return

	var inventory := player.inventory
	var target_item := cursor_item

	if target_item == ItemRegistry.Item.NONE:
		target_item = inventory.get_item(index)

		if target_item == ItemRegistry.Item.NONE:
			return

		cursor_item = target_item
		cursor_amount = 0

	var max_stack := ItemRegistry.get_max_stack(target_item)

	for i in Inventory.TOTAL_SLOT_COUNT:
		if cursor_amount >= max_stack:
			break

		if inventory.get_item(i) != target_item:
			continue

		var available := inventory.get_amount(i)
		var needed := max_stack - cursor_amount
		var to_take: int = min(available, needed)

		if to_take <= 0:
			continue

		inventory.remove_item(i, to_take)
		cursor_amount += to_take

	update_cursor_visual()


func create_crafting_buttons() -> void:
	for child in crafting_grid.get_children():
		child.queue_free()

	crafting_buttons.clear()

	for recipe_index in CraftingRegistry.RECIPES.size():
		var recipe: Dictionary = CraftingRegistry.RECIPES[recipe_index]
		var output_item: int = recipe["output_item"]

		var button := Button.new()
		button.custom_minimum_size = Vector2(48, 48)
		button.icon = get_item_texture(output_item)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 32)

		button.gui_input.connect(
			func(event: InputEvent) -> void:
				if not event is InputEventMouseButton:
					return

				if not event.pressed:
					return

				if event.button_index != MOUSE_BUTTON_LEFT:
					return

				if event.shift_pressed:
					craft_max(recipe_index)
				else:
					craft_recipe(recipe_index)
		)

		button.mouse_entered.connect(
			func() -> void:
				update_crafting_tooltip(recipe_index)
		)

		crafting_grid.add_child(button)
		crafting_buttons.append(button)

	update_crafting_buttons()


func update_crafting_buttons() -> void:
	if player == null:
		return

	for i in CraftingRegistry.RECIPES.size():
		var recipe: Dictionary = CraftingRegistry.RECIPES[i]

		var can_craft := CraftingRegistry.can_craft(
			player,
			recipe
		)

		crafting_buttons[i].disabled = not can_craft

		crafting_buttons[i].modulate = (
			Color.WHITE
			if can_craft
			else Color(1, 1, 1, 0.35)
		)


func craft_recipe(recipe_index: int) -> void:
	if player == null:
		return

	var recipe: Dictionary = CraftingRegistry.RECIPES[recipe_index]

	CraftingRegistry.craft(player,recipe)

	update_crafting_buttons()


func _on_inventory_changed(_index: int) -> void:
	update_crafting_buttons()


func get_item_texture(item_id: int) -> Texture2D:
	var texture_position := ItemRegistry.get_texture_position(item_id)

	var atlas_texture := AtlasTexture.new()
	atlas_texture.atlas = atlas
	atlas_texture.region = Rect2(
		texture_position.x * 16,
		texture_position.y * 16,
		16,
		16
	)

	return atlas_texture


func craft_max(recipe_index: int) -> void:
	if player == null:
		return

	var recipe: Dictionary = CraftingRegistry.RECIPES[recipe_index]

	while CraftingRegistry.craft(player,recipe):
		pass

	update_crafting_buttons()


func update_crafting_tooltip(recipe_index: int) -> void:
	var recipe: Dictionary = CraftingRegistry.RECIPES[recipe_index]

	var output_item: int = recipe["output_item"]
	var output_amount: int = recipe["output_amount"]
	var ingredients: Dictionary = recipe["ingredients"]

	var text := (
		ItemRegistry.get_item_name(output_item)
		+ " ×"
		+ str(output_amount)
	)

	text += "\n\nRequiere:"

	for item_id in ingredients:
		var required: int = ingredients[item_id]
		var owned: int = player.inventory.get_total_amount(item_id)

		text += (
			"\n"
			+ ItemRegistry.get_item_name(item_id)
			+ " "
			+ str(owned)
			+ "/"
			+ str(required)
		)

	crafting_buttons[recipe_index].tooltip_text = text
