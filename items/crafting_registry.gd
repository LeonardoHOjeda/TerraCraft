class_name CraftingRegistry
extends Node

const RECIPES := [
	{
		"name": "Tablones de madera",
		"output_item": ItemRegistry.Item.WOOD_PLANKS,
		"output_amount": 4,
		"ingredients": {
			ItemRegistry.Item.WOOD: 1
		}
	},
	{
		"name": "Palos",
		"output_item": ItemRegistry.Item.STICK,
		"output_amount": 4,
		"ingredients": {
			ItemRegistry.Item.WOOD_PLANKS: 2
		}
	}
]

static func can_craft(inventory: Inventory, recipe: Dictionary) -> bool:
	for item_id in recipe.ingredients:
		var required: int = recipe.ingredients[item_id]

		if not inventory.has_items(item_id, required):
			return false

	return true


static func craft(inventory: Inventory, recipe: Dictionary) -> bool:
	if not can_craft(inventory, recipe):
		return false

	var output_item: int = recipe.output_item
	var output_amount: int = recipe.output_amount

	if not inventory.can_add_item(
		output_item,
		output_amount
	):
		return false

	for item_id in recipe.ingredients:
		inventory.remove_items(
			item_id,
			recipe.ingredients[item_id]
		)

	inventory.add_item(
		output_item,
		output_amount
	)

	return true