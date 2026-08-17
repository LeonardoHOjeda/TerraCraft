class_name BlockRegistry
extends RefCounted

enum Block {
	AIR,
	GRASS,
	DIRT,
	STONE,
	BEDROCK,
	WOOD,
	LEAVES,
	WATER,
	SAND,
	COAL,
	IRON,
	COPPER,
	TIN,
	GOLD,
	TUNGSTEN,
  PLATINUM,
	WOOD_PLANKS,
  STICK,
  IRON_ORE,
  WORKBENCH,
  FURNACE,
	TORCH
}

const ATLAS_SIZE := 16

const TEXTURE_DIRT := Vector2i(0, 0)
const TEXTURE_GRASS_TOP := Vector2i(1, 0)
const TEXTURE_GRASS_SIDE := Vector2i(2, 0)
const TEXTURE_STONE := Vector2i(4, 0)
const TEXTURE_BEDROCK := Vector2i(5, 0)
const TEXTURE_WOOD_SIDE := Vector2i(6, 0)
const TEXTURE_LEAVES := Vector2i(7, 0)
const TEXTURE_WOOD_TOP := Vector2i(8, 0)
const TEXTURE_WATER := Vector2i(9, 0)
const TEXTURE_SAND := Vector2i(10, 0)
const TEXTURE_COAL := Vector2i(11, 0)
const TEXTURE_IRON := Vector2i(12, 0)
const TEXTURE_COPPER := Vector2i(13, 0)
const TEXTURE_TIN := Vector2i(14, 0)
const TEXTURE_GOLD := Vector2i(15, 0)

const TEXTURE_TUNGSTEN := Vector2i(1, 1)
const TEXTURE_PLATINUM := Vector2i(2, 1)
const TEXTURE_WOOD_PLANK := Vector2i(3, 1)
const TEXTURE_STICK := Vector2i(4, 1)
const TEXTURE_IRON_ORE := Vector2i(5, 1)
const TEXTURE_WORKBENCH := Vector2i(6, 1)
const TEXTURE_FURNACE := Vector2i(8, 1)
const TEXTURE_IRON_INGOT := Vector2i(12, 1)
const TEXTURE_TORCH := Vector2i(4, 1) # Temporary inventory icon: reuse the stick tile.


static func is_special_block(block: int) -> bool:
	return block == Block.TORCH


static func is_mesh_block(block: int) -> bool:
	return block != Block.AIR and not is_special_block(block)


static func is_occluding_block(block: int) -> bool:
	return is_mesh_block(block)


static func is_instant_break(block: int) -> bool:
	return block == Block.TORCH


static func get_light_emission(block: int) -> int:
	if block == Block.TORCH:
		return 14
	return 0


static func is_light_transparent(block: int) -> bool:
	return block == Block.AIR or is_special_block(block)


static func get_preferred_tool(block: int) -> ItemRegistry.ToolType:
	match block:
		Block.STONE:
			return ItemRegistry.ToolType.PICKAXE

		Block.COAL:
			return ItemRegistry.ToolType.PICKAXE

		Block.IRON:
			return ItemRegistry.ToolType.PICKAXE

		Block.COPPER:
			return ItemRegistry.ToolType.PICKAXE

		Block.TIN:
			return ItemRegistry.ToolType.PICKAXE

		Block.GOLD:
			return ItemRegistry.ToolType.PICKAXE

		Block.TUNGSTEN:
			return ItemRegistry.ToolType.PICKAXE

		Block.PLATINUM:
			return ItemRegistry.ToolType.PICKAXE

		Block.WOOD:
			return ItemRegistry.ToolType.AXE

	return ItemRegistry.ToolType.NONE


static func get_hardness(block: int) -> float:
	match block:
		Block.DIRT:
			return 0.35

		Block.GRASS:
			return 0.4

		Block.SAND:
			return 0.3

		Block.WOOD:
			return 0.9

		Block.LEAVES:
			return 0.15

		Block.STONE:
			return 1.5

		Block.COAL:
			return 1.8

		Block.COPPER:
			return 2.0

		Block.TIN:
			return 2.0

		Block.IRON:
			return 2.5

		Block.GOLD:
			return 2.5

		Block.TUNGSTEN:
			return 4.0

		Block.PLATINUM:
			return 4.5

		Block.BEDROCK:
			return INF

	return 1.0


static func get_required_mining_tier(block: int) -> int:
	match block:
		Block.STONE:
			return 1

		Block.COAL:
			return 1

		Block.COPPER:
			return 1

		Block.TIN:
			return 1

		Block.IRON:
			return 2

		Block.GOLD:
			return 2

		Block.TUNGSTEN:
			return 3

		Block.PLATINUM:
			return 4

	return 0
