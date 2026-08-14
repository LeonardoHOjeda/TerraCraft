class_name ItemRegistry
extends Node

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

	return Item.NONE

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
			return BlockRegistry.TEXTURE_IRON

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

	return BlockRegistry.TEXTURE_DIRT

static func get_placeable_block(item_id: int) -> int:
	match item_id:
		Item.DIRT:
			return BlockRegistry.Block.DIRT

		Item.STONE:
			return BlockRegistry.Block.STONE

		Item.WOOD:
			return BlockRegistry.Block.WOOD

		Item.SAND:
			return BlockRegistry.Block.SAND

	return BlockRegistry.Block.AIR

static func get_max_stack(item_id: int) -> int:
	match item_id:
		Item.NONE:
			return 0

	return 64

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

	return ""