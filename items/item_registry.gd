class_name ItemRegistry
extends Node

enum ToolType {
	NONE,
	PICKAXE,
	AXE,
	SHOVEL,
}

enum Item {
	NONE,

	GRASS,
	DIRT,
	STONE,
	WOOD,
	SAND,

	COAL,

	RAW_IRON,
	RAW_COPPER,
	RAW_TIN,
	RAW_GOLD,
	RAW_TUNGSTEN,
	RAW_PLATINUM,

	IRON_INGOT,
	COPPER_INGOT,
	TIN_INGOT,
	GOLD_INGOT,
	TUNGSTEN_INGOT,
	PLATINUM_INGOT,
	WOOD_PLANKS,
	STICK,

	WORKBENCH,
	FURNACE,

	WOODEN_PICKAXE,
	STONE_PICKAXE,
	IRON_PICKAXE
}


static func get_drop(block: int) -> int:
	match block:
		BlockRegistry.Block.GRASS:
			return Item.DIRT

		BlockRegistry.Block.DIRT:
			return Item.DIRT

		BlockRegistry.Block.STONE:
			return Item.STONE

		BlockRegistry.Block.WOOD:
			return Item.WOOD

		BlockRegistry.Block.SAND:
			return Item.SAND

		BlockRegistry.Block.COAL:
			return Item.COAL

		BlockRegistry.Block.IRON:
			return Item.RAW_IRON

		BlockRegistry.Block.COPPER:
			return Item.RAW_COPPER

		BlockRegistry.Block.TIN:
			return Item.RAW_TIN

		BlockRegistry.Block.GOLD:
			return Item.RAW_GOLD

		BlockRegistry.Block.TUNGSTEN:
			return Item.RAW_TUNGSTEN

		BlockRegistry.Block.PLATINUM:
			return Item.RAW_PLATINUM

		BlockRegistry.Block.WOOD_PLANKS:
			return Item.WOOD_PLANKS

		BlockRegistry.Block.WORKBENCH:
			return Item.WORKBENCH

		BlockRegistry.Block.FURNACE:
			return Item.FURNACE

	return Item.NONE

# Funcion para obtener la textura de lo que sueltan los bloques minados
static func get_texture_position(item: int) -> Vector2i:
	match item:
		Item.DIRT:
			return BlockRegistry.TEXTURE_DIRT
		Item.STONE:
			return BlockRegistry.TEXTURE_STONE
		Item.WOOD:
			return BlockRegistry.TEXTURE_WOOD_SIDE
		Item.SAND:
			return BlockRegistry.TEXTURE_SAND
		Item.COAL:
			return BlockRegistry.TEXTURE_COAL
		Item.RAW_IRON:
			return BlockRegistry.TEXTURE_IRON_ORE
		Item.RAW_COPPER:
			return BlockRegistry.TEXTURE_COPPER
		Item.RAW_TIN:
			return BlockRegistry.TEXTURE_TIN
		Item.RAW_GOLD:
			return BlockRegistry.TEXTURE_GOLD
		Item.RAW_TUNGSTEN:
			return BlockRegistry.TEXTURE_TUNGSTEN
		Item.RAW_PLATINUM:
			return BlockRegistry.TEXTURE_PLATINUM
		Item.WOOD_PLANKS:
			return BlockRegistry.TEXTURE_WOOD_PLANK
		Item.STICK:
			return BlockRegistry.TEXTURE_STICK
		Item.WORKBENCH:
			return BlockRegistry.TEXTURE_WORKBENCH
		Item.FURNACE:
			return BlockRegistry.TEXTURE_FURNACE
		Item.WOODEN_PICKAXE:
			return Vector2i(9,1)
		Item.STONE_PICKAXE:
			return Vector2i(10,1)
		Item.IRON_INGOT:
			return BlockRegistry.TEXTURE_IRON_INGOT

	return BlockRegistry.TEXTURE_DIRT

static func get_placeable_block(item_id: int) -> int:
	print("Item ID: " + str(item_id))
	match item_id:
		Item.DIRT:
			return BlockRegistry.Block.DIRT

		Item.STONE:
			return BlockRegistry.Block.STONE

		Item.WOOD:
			return BlockRegistry.Block.WOOD

		Item.SAND:
			return BlockRegistry.Block.SAND

		Item.WOOD_PLANKS:
			return BlockRegistry.Block.WOOD_PLANKS

		Item.WORKBENCH:
			return BlockRegistry.Block.WORKBENCH

		Item.FURNACE:
			return BlockRegistry.Block.FURNACE

	return BlockRegistry.Block.AIR

static func get_max_stack(item_id: int) -> int:
	match item_id:
		Item.NONE:
			return 0
		Item.WOODEN_PICKAXE:
			return 1
		Item.STONE_PICKAXE:
			return 1
		Item.IRON_PICKAXE:
			return 1

	return 64

# Obtener el nombre del objeto dado el ID del objeto
static func get_item_name(item_id: int) -> String:
	match item_id:
		Item.DIRT:
			return "Tierra"
		Item.STONE:
			return "Piedra"
		Item.WOOD:
			return "Madera"
		Item.SAND:
			return "Arena"
		Item.COAL:
			return "Carbón"
		Item.RAW_IRON:
			return "Hierro en bruto"
		Item.RAW_COPPER:
			return "Cobre en bruto"
		Item.RAW_TIN:
			return "Estaño en bruto"
		Item.RAW_GOLD:
			return "Oro en bruto"
		Item.RAW_TUNGSTEN:
			return "Tungsteno en bruto"
		Item.RAW_PLATINUM:
			return "Platino en bruto"
		Item.IRON_INGOT:
			return "Lingote de hierro"
		Item.COPPER_INGOT:
			return "Lingote de cobre"
		Item.TIN_INGOT:
			return "Lingote de estaño"
		Item.GOLD_INGOT:
			return "Lingote de oro"
		Item.TUNGSTEN_INGOT:
			return "Lingote de tungsteno"
		Item.PLATINUM_INGOT:
			return "Lingote de platino"
		Item.WOOD_PLANKS:
			return "Tablones de madera"
		Item.STICK:
			return "Palo"
		Item.WORKBENCH:
			return "Mesa de trabajo"
		Item.FURNACE:
			return "Horno"
		Item.WOODEN_PICKAXE:
			return "Pico de madera"
		Item.STONE_PICKAXE:
			return "Pico de piedra"
		Item.IRON_PICKAXE:
			return "Pico de hierro"

	return ""

static func get_tool_type(item_id: int) -> ToolType:
	match item_id:
		Item.WOODEN_PICKAXE:
			return ToolType.PICKAXE
		Item.STONE_PICKAXE:
			return ToolType.PICKAXE
		Item.IRON_PICKAXE:
			return ToolType.PICKAXE

	return ToolType.NONE


static func get_mining_speed(item_id: int) -> float:
	match item_id:
		Item.WOODEN_PICKAXE:
			return 2.5
		Item.STONE_PICKAXE:
			return 4.0
		Item.IRON_PICKAXE:
			return 6.0

	return 1.0


static func get_mining_tier(item_id: int) -> int:
	match item_id:
		Item.WOODEN_PICKAXE:
			return 1
		Item.STONE_PICKAXE:
			return 2
		Item.IRON_PICKAXE:
			return 3

	return 0