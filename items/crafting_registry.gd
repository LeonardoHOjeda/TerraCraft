class_name CraftingRegistry
extends Node

enum Station {
	NONE,
	WORKBENCH,
	FURNACE,
	ANVIL,
}

const RECIPES := [
	{
		"name": "Tablones de madera",
		"output_item": ItemRegistry.Item.WOOD_PLANKS,
		"output_amount": 4,
    "station": Station.NONE,
		"ingredients": {
			ItemRegistry.Item.WOOD: 1
		}
	},
	{
		"name": "Palos",
		"output_item": ItemRegistry.Item.STICK,
		"output_amount": 4,
    "station": Station.NONE,
		"ingredients": {
			ItemRegistry.Item.WOOD_PLANKS: 2
		}
	},
	{
		"name": "Mesa de trabajo",
		"output_item": ItemRegistry.Item.WORKBENCH,
		"output_amount": 1,
    "station": Station.NONE,
		"ingredients": {
			ItemRegistry.Item.WOOD_PLANKS: 8
		}
	},
  {
    "name": "Horno",
		"output_item": ItemRegistry.Item.FURNACE,
		"output_amount": 1,
    "station": Station.WORKBENCH,
		"ingredients": {
			ItemRegistry.Item.STONE: 10
		}
  },
  {
    "name": "Pico de madera",
    "output_item": ItemRegistry.Item.WOODEN_PICKAXE,
    "output_amount": 1,
    "station": Station.WORKBENCH,
    "ingredients": {
      ItemRegistry.Item.WOOD_PLANKS: 5,
      ItemRegistry.Item.STICK: 3
    }
  },
  {
    "name": "Pico de piedra",
    "output_item": ItemRegistry.Item.STONE_PICKAXE,
    "output_amount": 1,
    "station": Station.WORKBENCH,
    "ingredients": {
      ItemRegistry.Item.STONE: 5,
      ItemRegistry.Item.STICK: 3
    }
  },
  {
    "name": "Pico de hierro",
    "output_item": ItemRegistry.Item.IRON_PICKAXE,
    "output_amount": 1,
    "station": Station.WORKBENCH,
    "ingredients": {
      ItemRegistry.Item.IRON_INGOT: 5,
      ItemRegistry.Item.STICK: 3
    }
  },
  {
    "name": "Hacha de madera",
    "output_item": ItemRegistry.Item.WOODEN_AXE,
    "output_amount": 1,
    "station": Station.WORKBENCH,
    "ingredients": {
      ItemRegistry.Item.WOOD_PLANKS: 3,
      ItemRegistry.Item.STICK: 2
    }
  },
  {
    "name": "Hacha de piedra",
    "output_item": ItemRegistry.Item.STONE_AXE,
    "output_amount": 1,
    "station": Station.WORKBENCH,
    "ingredients": {
      ItemRegistry.Item.STONE: 3,
      ItemRegistry.Item.STICK: 2
    }
  },
  {
    "name": "Hacha de hierro",
    "output_item": ItemRegistry.Item.IRON_AXE,
    "output_amount": 1,
    "station": Station.WORKBENCH,
    "ingredients": {
      ItemRegistry.Item.IRON_INGOT: 3,
      ItemRegistry.Item.STICK: 2
    }
  },
  {
    "name": "Lingote de hierro",
    "output_item": ItemRegistry.Item.IRON_INGOT,
    "output_amount": 1,
    "station": Station.FURNACE,
    "ingredients": {
      ItemRegistry.Item.RAW_IRON: 1,
    }
  },
]

static func can_craft(inventory: Inventory, station_access: StationDetector, recipe: Dictionary) -> bool:
	var station: int = recipe.get(
		"station",
		Station.NONE
	)

	if not station_access.has_nearby_station(station):
		return false

	for item_id in recipe["ingredients"]:
		var required: int = recipe["ingredients"][item_id]

		if not inventory.has_items(item_id, required):
			return false

	return true


static func craft(
	inventory: Inventory,
	station_access: StationDetector,
	recipe: Dictionary
) -> bool:
	if not can_craft(inventory, station_access, recipe):
		return false

	var output_item: int = recipe["output_item"]
	var output_amount: int = recipe["output_amount"]

	if not inventory.can_add_item(
		output_item,
		output_amount
	):
		return false

	for item_id in recipe["ingredients"]:
		inventory.remove_items(
			item_id,
			recipe["ingredients"][item_id]
		)

	inventory.add_item(
		output_item,
		output_amount
	)

	return true
