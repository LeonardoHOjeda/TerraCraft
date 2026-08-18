class_name ItemIconFactory
extends RefCounted

const TILE_SIZE := 16
const ICON_SIZE := 32
const TOP_LIGHT := 1.08
const LEFT_LIGHT := 0.78
const RIGHT_LIGHT := 0.9

static var icon_cache: Dictionary = {}
static var atlas_image_cache: Dictionary = {}
static var block_texture_provider := ChunkMesher.new()


static func get_item_icon(atlas: Texture2D, item_id: int) -> Texture2D:
	if atlas == null or item_id == ItemRegistry.Item.NONE:
		return null
	var cache_key := Vector2i(atlas.get_instance_id(), item_id)
	if icon_cache.has(cache_key):
		return icon_cache[cache_key] as Texture2D
	var icon: Texture2D
	if ItemRegistry.is_block_item(item_id):
		icon = create_block_icon(atlas, ItemRegistry.get_placeable_block(item_id))
	else:
		icon = create_flat_icon(atlas, ItemRegistry.get_texture_position(item_id))
	icon_cache[cache_key] = icon
	return icon


static func create_flat_icon(atlas: Texture2D, tile: Vector2i) -> Texture2D:
	var texture := AtlasTexture.new()
	texture.atlas = atlas
	texture.region = Rect2(tile * TILE_SIZE, Vector2i(TILE_SIZE, TILE_SIZE))
	return texture


static func create_block_icon(atlas: Texture2D, block_id: int) -> Texture2D:
	var atlas_image := get_atlas_image(atlas)
	if atlas_image == null or atlas_image.is_empty():
		return create_flat_icon(
			atlas, block_texture_provider.get_block_texture(block_id, Vector3i.FORWARD)
		)
	var icon := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	draw_top_face(
		icon, atlas_image, block_texture_provider.get_block_texture(block_id, Vector3i.UP)
	)
	draw_left_face(
		icon, atlas_image, block_texture_provider.get_block_texture(block_id, Vector3i.LEFT)
	)
	draw_right_face(
		icon, atlas_image, block_texture_provider.get_block_texture(block_id, Vector3i.FORWARD)
	)
	return ImageTexture.create_from_image(icon)


static func get_atlas_image(atlas: Texture2D) -> Image:
	var atlas_key := atlas.get_instance_id()
	if not atlas_image_cache.has(atlas_key):
		var image := atlas.get_image()
		if image != null and image.is_compressed():
			image.decompress()
		atlas_image_cache[atlas_key] = image
	return atlas_image_cache[atlas_key] as Image


static func draw_top_face(target: Image, atlas_image: Image, tile: Vector2i) -> void:
	for y in range(1, 16):
		for x in ICON_SIZE:
			var sum := float(y - 1) * 15.0 / 7.0
			var difference := float(x - 16) * 15.0 / 14.0
			var source_x := floori((sum + difference) * 0.5)
			var source_y := floori((sum - difference) * 0.5)
			copy_pixel(target, atlas_image, x, y, tile, source_x, source_y, TOP_LIGHT)


static func draw_left_face(target: Image, atlas_image: Image, tile: Vector2i) -> void:
	for y in range(8, ICON_SIZE):
		for x in range(2, 17):
			var source_x := floori(float(x - 2) * 15.0 / 14.0)
			var top_y := 8.0 + float(source_x) * 7.0 / 15.0
			var source_y := floori(float(y - top_y) * 15.0 / 16.0)
			copy_pixel(target, atlas_image, x, y, tile, source_x, source_y, LEFT_LIGHT)


static func draw_right_face(target: Image, atlas_image: Image, tile: Vector2i) -> void:
	for y in range(8, ICON_SIZE):
		for x in range(16, 31):
			var source_x := floori(float(x - 16) * 15.0 / 14.0)
			var top_y := 15.0 - float(source_x) * 7.0 / 15.0
			var source_y := floori(float(y - top_y) * 15.0 / 16.0)
			copy_pixel(target, atlas_image, x, y, tile, source_x, source_y, RIGHT_LIGHT)


static func copy_pixel(
	target: Image,
	atlas_image: Image,
	target_x: int,
	target_y: int,
	tile: Vector2i,
	source_x: int,
	source_y: int,
	light: float
) -> void:
	if source_x < 0 or source_x >= TILE_SIZE or source_y < 0 or source_y >= TILE_SIZE:
		return
	var color := atlas_image.get_pixel(tile.x * TILE_SIZE + source_x, tile.y * TILE_SIZE + source_y)
	color.r = minf(color.r * light, 1.0)
	color.g = minf(color.g * light, 1.0)
	color.b = minf(color.b * light, 1.0)
	target.set_pixel(target_x, target_y, color)
