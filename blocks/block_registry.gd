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