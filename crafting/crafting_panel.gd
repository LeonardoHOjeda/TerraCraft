class_name CraftingPanel
extends GridContainer

var inventory: Inventory
var player: Player
var atlas: Texture2D
var crafting_buttons: Array[Button] = []


func setup(new_inventory: Inventory, new_player: Player, new_atlas: Texture2D) -> void:
	inventory = new_inventory
	player = new_player
	atlas = new_atlas
	add_theme_constant_override("h_separation", 4)
	add_theme_constant_override("v_separation", 4)
	inventory.slot_changed.connect(_on_inventory_changed)
	player.crafting_stations_changed.connect(update_crafting_buttons)
	create_crafting_buttons()


func create_crafting_buttons() -> void:
	for child in get_children():
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

		add_child(button)
		crafting_buttons.append(button)

	update_crafting_buttons()


func update_crafting_buttons() -> void:
	if player == null:
		return

	for i in CraftingRegistry.RECIPES.size():
		var recipe: Dictionary = CraftingRegistry.RECIPES[i]
		var can_craft := CraftingRegistry.can_craft(player, recipe)
		crafting_buttons[i].disabled = not can_craft
		crafting_buttons[i].modulate = Color.WHITE if can_craft else Color(1, 1, 1, 0.35)


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
	atlas_texture.region = Rect2(texture_position.x * 16, texture_position.y * 16, 16, 16)
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
	var text := ItemRegistry.get_item_name(output_item) + " ×" + str(output_amount)
	text += "\n\nRequiere:"

	for item_id in ingredients:
		var required: int = ingredients[item_id]
		var owned: int = inventory.get_total_amount(item_id)
		text += "\n" + ItemRegistry.get_item_name(item_id) + " " + str(owned) + "/" + str(required)

	crafting_buttons[recipe_index].tooltip_text = text
