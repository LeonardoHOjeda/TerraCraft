class_name CraftingPanel
extends GridContainer

var inventory: Inventory
var station_access: StationDetector
var atlas: Texture2D
var empty_label: Label
var crafting_buttons: Array[Button] = []


func setup(new_inventory: Inventory, new_station_access: StationDetector, new_atlas: Texture2D, new_empty_label: Label) -> void:
	inventory = new_inventory
	station_access = new_station_access
	atlas = new_atlas
	empty_label = new_empty_label
	add_theme_constant_override("v_separation", 6)
	inventory.slot_changed.connect(_on_inventory_changed)
	station_access.stations_changed.connect(refresh_recipes)
	refresh_recipes()


func refresh_recipes() -> void:
	if inventory == null or station_access == null:
		return

	for child in get_children():
		child.queue_free()
	crafting_buttons.clear()

	for recipe_index in CraftingRegistry.RECIPES.size():
		var recipe: Dictionary = CraftingRegistry.RECIPES[recipe_index]
		if not CraftingRegistry.can_craft(inventory, station_access, recipe):
			continue

		var output_item: int = recipe["output_item"]
		var output_amount: int = recipe["output_amount"]
		var button := InventoryTooltipButton.new()
		button.custom_minimum_size = Vector2(170, 46)
		button.icon = get_item_texture(output_item)
		button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 32)
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = InventoryTooltipButton.safe_item_name(output_item)
		if output_amount > 1:
			button.text += "  ×" + str(output_amount)
		button.tooltip_text = get_crafting_tooltip(recipe)
		apply_crafting_button_styles(button)
		button.gui_input.connect(_on_crafting_button_gui_input.bind(recipe_index))
		add_child(button)
		crafting_buttons.append(button)

	empty_label.visible = crafting_buttons.is_empty()
	get_parent().visible = not crafting_buttons.is_empty()


func _on_crafting_button_gui_input(event: InputEvent, recipe_index: int) -> void:
	if not event is InputEventMouseButton:
		return
	if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.shift_pressed:
		craft_max(recipe_index)
	else:
		craft_recipe(recipe_index)


func apply_crafting_button_styles(button: Button) -> void:
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0.10, 0.13, 0.18, 0.96)
	normal_style.border_color = Color(0.28, 0.34, 0.44)
	normal_style.set_border_width_all(1)
	normal_style.set_corner_radius_all(5)
	normal_style.content_margin_left = 8
	button.add_theme_stylebox_override("normal", normal_style)

	var hover_style := normal_style.duplicate() as StyleBoxFlat
	hover_style.bg_color = Color(0.19, 0.24, 0.32, 1.0)
	hover_style.border_color = Color(0.72, 0.82, 1.0)
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_stylebox_override("pressed", hover_style)


func craft_recipe(recipe_index: int) -> void:
	if inventory == null or station_access == null:
		return
	var recipe: Dictionary = CraftingRegistry.RECIPES[recipe_index]
	CraftingRegistry.craft(inventory, station_access, recipe)
	refresh_recipes()


func _on_inventory_changed(_index: int) -> void:
	refresh_recipes()


func get_item_texture(item_id: int) -> Texture2D:
	return ItemIconFactory.get_item_icon(atlas, item_id)


func craft_max(recipe_index: int) -> void:
	if inventory == null or station_access == null:
		return
	var recipe: Dictionary = CraftingRegistry.RECIPES[recipe_index]
	while CraftingRegistry.craft(inventory, station_access, recipe):
		pass
	refresh_recipes()


func get_crafting_tooltip(recipe: Dictionary) -> String:
	var output_item: int = recipe["output_item"]
	var output_amount: int = recipe["output_amount"]
	var ingredients: Dictionary = recipe["ingredients"]
	var text := InventoryTooltipButton.safe_item_name(output_item) + " ×" + str(output_amount)
	text += "\n\nRequiere:"

	for item_id in ingredients:
		var required: int = ingredients[item_id]
		var owned: int = inventory.get_total_amount(item_id)
		text += "\n" + InventoryTooltipButton.safe_item_name(item_id) + " " + str(owned) + "/" + str(required)

	return text
